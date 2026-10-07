-- =============================================================================
-- Field Service — Job Workflow Business-Rule Correction
-- =============================================================================
-- Purpose:
--   Enforce the corrected business workflow at the database level:
--
--     ADMIN:     Create -> Assign -> Monitor
--     TECHNICIAN: Start -> Before Photos -> Work Details -> After Photos
--                 -> Signature -> Complete
--
--   The admin creates and assigns jobs; ONLY the assigned active technician
--   executes the job. An admin must never be able to run the technician
--   workflow — not through the UI and not by calling the backend directly.
--
-- This file contains:
--   1. Job category migration — `jobs.job_type` becomes an explicit,
--      constrained business category with EXACTLY two supported values:
--        'home_renovation'    (Home Renovation / Hausrenovierung)
--        'kitchen_renovation' (Kitchen Renovation / Küchenrenovierung)
--      Legacy values are migrated; a CHECK constraint locks the set.
--   2. `start_job` — rewritten authorization: admins can NO LONGER start
--      jobs. Only an ACTIVE TECHNICIAN whose employee row is the job's
--      `assigned_employee_id` may start it, and only from `assigned`.
--   3. `register_job_file` — rewritten authorization: admins can NO LONGER
--      register (capture) job files. Only the assigned active technician
--      captures photos; admins keep their existing read-only (SELECT)
--      access for monitoring. Nothing else about the function changes.
--   4. `create_job` — NEW admin-only RPC: the single write path for
--      creating and assigning a job. Generates `job_number` server-side,
--      sets `status = 'assigned'` and `assigned_at = now()` (server time —
--      the client never sends a timestamp), validates the category and the
--      assigned technician, and appends the `job_created` / `job_assigned`
--      events atomically.
--
-- Preserved (untouched): jobs/customers/employees RLS policies, the job
-- event system, technician job-visibility rules, admin visibility of all
-- jobs, the Before Photos read path, `get_job_customer`.
--
-- Idempotent: re-running this file is safe (UPDATE ... WHERE, DROP ... IF
-- EXISTS, CREATE OR REPLACE FUNCTION, REVOKE/GRANT).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1) Job category migration: exactly two supported categories
-- ---------------------------------------------------------------------------
-- The business has exactly two job categories. The stable backend values are
-- 'home_renovation' and 'kitchen_renovation'; the UI displays localized
-- labels and never shows the raw values.

-- 1a) Kitchen-type legacy values -> 'kitchen_renovation'.
--     Covers the legacy stored value 'kitchen_installation' (displayed as
--     "Kitchen Installation") in both underscore and space spellings.
UPDATE public.jobs
   SET job_type   = 'kitchen_renovation',
       updated_at = now()
 WHERE LOWER(REPLACE(job_type, '-', '_')) IN
       ('kitchen_installation', 'kitchen installation')
   AND job_type <> 'kitchen_renovation';

-- 1b) Everything else that is not already one of the two supported values
--     (e.g. legacy 'renovation', 'maintenance', free text) becomes
--     'home_renovation'. After 1a) + 1b) only the two supported values
--     remain in the column.
UPDATE public.jobs
   SET job_type   = 'home_renovation',
       updated_at = now()
 WHERE job_type NOT IN ('home_renovation', 'kitchen_renovation');

-- 1c) Lock the category set at the database level. New rows (including rows
--     inserted through `create_job`) can only ever carry one of the two
--     supported values.
ALTER TABLE public.jobs
  DROP CONSTRAINT IF EXISTS jobs_job_type_valid;

ALTER TABLE public.jobs
  ADD CONSTRAINT jobs_job_type_valid
  CHECK (job_type IN ('home_renovation', 'kitchen_renovation'));

-- ---------------------------------------------------------------------------
-- 2) start_job — technician-only authorization (admin bypass REMOVED)
-- ---------------------------------------------------------------------------
-- Contract (unchanged parts):
--   * atomic: status + server timestamps + one `job_started` event,
--   * idempotent replay: an already-`in_progress` job is returned unchanged
--     (no second event, `started_at` never reset) — queued sync retries stay
--     safe,
--   * the client sends only the job id; every timestamp is server-generated.
-- Changed part (business correction):
--   * the caller must be an ACTIVE employee with role 'technician',
--   * AND the job must be assigned to exactly that employee,
--   * admins are refused with `insufficient_privilege` (42501) even though
--     they can see every job — monitoring only, never execution.
CREATE OR REPLACE FUNCTION public.start_job(p_job_id uuid)
RETURNS SETOF public.jobs
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_employee_id uuid;
  v_role        text;
  v_job         public.jobs;
BEGIN
  -- 1) Caller must be authenticated.
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated.'
      USING ERRCODE = '28000'; -- invalid_authorization_specification
  END IF;

  -- 2) Resolve the caller's ACTIVE employee row (role captured for step 4).
  SELECT e.id, e.role
    INTO v_employee_id, v_role
  FROM public.employees e
  WHERE e.auth_user_id = auth.uid()
    AND e.is_active = true
  LIMIT 1;

  IF v_employee_id IS NULL THEN
    -- No employee row at all, or the employee is inactive: refuse.
    RAISE EXCEPTION 'No active employee is linked to this account.'
      USING ERRCODE = '28000';
  END IF;

  -- 3) Load and lock the target job.
  SELECT *
    INTO v_job
  FROM public.jobs j
  WHERE j.id = p_job_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Job not found.'
      USING ERRCODE = 'P0002'; -- no_data_found
  END IF;

  -- 4) Authorization: ONLY an active technician may start a job, and only
  --    one assigned to exactly them. Admins are refused outright — they
  --    create/assign/monitor jobs but never execute the technician
  --    workflow, even by calling this function directly. An unassigned job
  --    can never be started by anyone.
  IF v_role <> 'technician' THEN
    RAISE EXCEPTION 'Only the assigned technician can start this job.'
      USING ERRCODE = '42501'; -- insufficient_privilege
  END IF;

  IF v_job.assigned_employee_id IS DISTINCT FROM v_employee_id THEN
    RAISE EXCEPTION 'This job is not assigned to you.'
      USING ERRCODE = '42501'; -- insufficient_privilege
  END IF;

  -- 5) Duplicate-start protection / invalid-state handling.
  IF v_job.status = 'in_progress' THEN
    -- Already started: succeed without mutating anything — no second event,
    -- started_at untouched. This is what makes queued sync retries safe.
    RETURN NEXT v_job;
    RETURN;
  END IF;

  IF v_job.status <> 'assigned' THEN
    RAISE EXCEPTION 'Job cannot be started from status "%".', v_job.status
      USING ERRCODE = 'P0001';
  END IF;

  -- 6) Atomic start: status + server timestamps + the append-only event.
  UPDATE public.jobs j
     SET status     = 'in_progress',
         started_at = now(),
         updated_at = now()
   WHERE j.id = p_job_id;

  INSERT INTO public.job_events (job_id, employee_id, event_type, occurred_at)
  VALUES (p_job_id, v_employee_id, 'job_started', now());

  RETURN QUERY
  SELECT *
  FROM public.jobs j
  WHERE j.id = p_job_id;
END;
$$;

REVOKE ALL ON FUNCTION public.start_job(uuid) FROM public;
REVOKE ALL ON FUNCTION public.start_job(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.start_job(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- 3) register_job_file — capture is technician-only (admin bypass REMOVED)
-- ---------------------------------------------------------------------------
-- Business correction: capturing job files (Before Photos today; After
-- Photos / Signature later) is part of the technician execution workflow.
-- Admins monitor jobs — they never capture. The assignment check alone
-- would already refuse admins (jobs are assigned to technicians), the
-- explicit role check documents and enforces the rule regardless.
-- Everything else (replay safety, in_progress rule for before photos,
-- atomic row + event insert, original capture timestamp) is unchanged.
CREATE OR REPLACE FUNCTION public.register_job_file(
  p_file_id      uuid,
  p_job_id       uuid,
  p_file_type    text,
  p_storage_path text,
  p_file_name    text,
  p_mime_type    text,
  p_size_bytes   bigint,
  p_captured_at  timestamptz
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_employee_id uuid;
  v_role        text;
  v_job         public.jobs;
  v_inserted    integer;
BEGIN
  -- 1) Caller must be authenticated.
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated.'
      USING ERRCODE = '28000'; -- invalid_authorization_specification
  END IF;

  -- 2) Resolve the caller's ACTIVE employee row.
  SELECT e.id, e.role
    INTO v_employee_id, v_role
  FROM public.employees e
  WHERE e.auth_user_id = auth.uid()
    AND e.is_active = true
  LIMIT 1;

  IF v_employee_id IS NULL THEN
    RAISE EXCEPTION 'No active employee is linked to this account.'
      USING ERRCODE = '28000';
  END IF;

  -- 3) Basic input validation.
  IF p_file_id IS NULL OR p_job_id IS NULL
     OR p_storage_path IS NULL OR p_file_name IS NULL
     OR p_captured_at IS NULL THEN
    RAISE EXCEPTION 'Missing required file metadata.'
      USING ERRCODE = 'P0001';
  END IF;

  IF p_file_type IS NULL
     OR p_file_type NOT IN ('before', 'after', 'signature', 'document') THEN
    RAISE EXCEPTION 'Unsupported file type.'
      USING ERRCODE = 'P0001';
  END IF;

  -- 4) Load and lock the target job.
  SELECT *
    INTO v_job
  FROM public.jobs j
  WHERE j.id = p_job_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Job not found.'
      USING ERRCODE = 'P0002'; -- no_data_found
  END IF;

  -- 5) Authorization: ONLY an active technician may register job files, and
  --    only for a job assigned to exactly them. Admins are refused — they
  --    keep read access (job_files SELECT policy) for monitoring, but never
  --    capture, even by calling this function directly.
  IF v_role <> 'technician' THEN
    RAISE EXCEPTION 'Only the assigned technician can add job files.'
      USING ERRCODE = '42501'; -- insufficient_privilege
  END IF;

  IF v_job.assigned_employee_id IS DISTINCT FROM v_employee_id THEN
    RAISE EXCEPTION 'This job is not assigned to you.'
      USING ERRCODE = '42501'; -- insufficient_privilege
  END IF;

  -- 6) Replay safety: this exact file id is already registered. Succeed
  --    without touching anything, but only when it belongs to this job
  --    (a file id cannot be re-registered against a different job).
  IF EXISTS (
    SELECT 1 FROM public.job_files f WHERE f.id = p_file_id
  ) THEN
    IF EXISTS (
      SELECT 1
      FROM public.job_files f
      WHERE f.id = p_file_id AND f.job_id <> p_job_id
    ) THEN
      RAISE EXCEPTION 'This file id is already registered to another job.'
        USING ERRCODE = '42501';
    END IF;
    RETURN;
  END IF;

  -- 7) Business rule: before photos document the site BEFORE work begins —
  --    they are only accepted while the job is in progress. (The UI offers
  --    capture only after Start Job; the server enforces it regardless.)
  IF p_file_type = 'before' AND v_job.status <> 'in_progress' THEN
    RAISE EXCEPTION
      'Before photos can only be added to a job that is in progress.'
      USING ERRCODE = 'P0001';
  END IF;

  -- 8) Atomic registration: the file row plus (only when the row is new)
  --    exactly one `before_photo_captured` event whose occurred_at is the
  --    ORIGINAL capture time — never the upload time.
  INSERT INTO public.job_files (
    id, job_id, employee_id, file_type, storage_path,
    file_name, mime_type, size_bytes, captured_at
  )
  VALUES (
    p_file_id, p_job_id, v_employee_id, p_file_type, p_storage_path,
    p_file_name, p_mime_type, p_size_bytes, p_captured_at
  )
  ON CONFLICT (id) DO NOTHING;

  GET DIAGNOSTICS v_inserted = ROW_COUNT;

  IF v_inserted > 0 AND p_file_type = 'before' THEN
    INSERT INTO public.job_events (
      job_id, employee_id, event_type, occurred_at
    )
    VALUES (
      p_job_id, v_employee_id, 'before_photo_captured', p_captured_at
    );
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.register_job_file(
  uuid, uuid, text, text, text, text, bigint, timestamptz
) FROM public;
REVOKE ALL ON FUNCTION public.register_job_file(
  uuid, uuid, text, text, text, text, bigint, timestamptz
) FROM anon;
GRANT EXECUTE ON FUNCTION public.register_job_file(
  uuid, uuid, text, text, text, text, bigint, timestamptz
) TO authenticated;

-- ---------------------------------------------------------------------------
-- 4) create_job — the ONLY job creation/assignment path (admin-only RPC)
-- ---------------------------------------------------------------------------
-- Contract:
--   * caller must be an ACTIVE ADMIN (verified inline; technicians and
--     inactive employees are refused with 42501),
--   * `p_job_type` must be one of the two supported categories
--     (the table CHECK constraint is the final backstop),
--   * `p_assigned_employee_id` must reference an ACTIVE employee whose role
--     is 'technician' — inactive employees, admins and unknown ids are
--     refused (a job is always created assigned; there is no unassigned
--     creation path),
--   * `p_customer_id` must reference an existing customer,
--   * `job_number` is generated SERVER-side by the table itself:
--     `jobs.job_number` is a GENERATED ALWAYS AS IDENTITY column (error
--     428C9 proves it refuses any client-provided value), so the INSERT
--     omits the column entirely and the identity sequence assigns the next
--     number — the existing numbering mechanism, reused, never duplicated.
--     The returned row carries the generated number,
--   * `status = 'assigned'`, `assigned_at = now()`, `created_at/updated_at =
--     now()` — all server time; the client sends NO timestamp,
--   * `expires_at` is stamped deterministically (90 days from creation) so
--     the function is self-contained regardless of project-specific column
--     defaults; the app treats it as a display value,
--   * two append-only events are recorded: `job_created` and `job_assigned`,
--     both attributed to the creating admin's employee row,
--   * returns the inserted row so the client shows the authoritative job.
CREATE OR REPLACE FUNCTION public.create_job(
  p_customer_id          uuid,
  p_job_type             text,
  p_description          text,
  p_assigned_employee_id uuid
)
RETURNS SETOF public.jobs
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_employee_id uuid;
  v_new_id            uuid := gen_random_uuid();
BEGIN
  -- 1) Caller must be authenticated.
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated.'
      USING ERRCODE = '28000'; -- invalid_authorization_specification
  END IF;

  -- 2) Caller must be an ACTIVE ADMIN. This is the admin's creation and
  --    assignment action; no other role may create jobs.
  SELECT e.id
    INTO v_admin_employee_id
  FROM public.employees e
  WHERE e.auth_user_id = auth.uid()
    AND e.role = 'admin'
    AND e.is_active = true
  LIMIT 1;

  IF v_admin_employee_id IS NULL THEN
    RAISE EXCEPTION 'Only an active admin can create jobs.'
      USING ERRCODE = '42501'; -- insufficient_privilege
  END IF;

  -- 3) Category: exactly the two supported business values.
  IF p_job_type IS NULL
     OR p_job_type NOT IN ('home_renovation', 'kitchen_renovation') THEN
    RAISE EXCEPTION 'Unsupported job category.'
      USING ERRCODE = 'P0001';
  END IF;

  -- 4) The customer must exist.
  IF p_customer_id IS NULL
     OR NOT EXISTS (
       SELECT 1 FROM public.customers c WHERE c.id = p_customer_id
     ) THEN
    RAISE EXCEPTION 'Customer not found.'
      USING ERRCODE = 'P0002'; -- no_data_found
  END IF;

  -- 5) The assignee must be an ACTIVE TECHNICIAN. Never an admin, never an
  --    inactive employee, never an unknown id.
  IF p_assigned_employee_id IS NULL
     OR NOT EXISTS (
       SELECT 1
       FROM public.employees t
       WHERE t.id = p_assigned_employee_id
         AND t.role = 'technician'
         AND t.is_active = true
     ) THEN
    RAISE EXCEPTION 'Only an active technician can be assigned to a job.'
      USING ERRCODE = 'P0001';
  END IF;

  -- 6) Insert the assigned job. `job_number` is deliberately OMITTED: the
  --    column is GENERATED ALWAYS AS IDENTITY, so the database assigns the
  --    next number from its own sequence — any explicit value is rejected
  --    (PostgreSQL error 428C9). Every timestamp is generated here, on the
  --    server — the client contributes neither a number nor a time.
  INSERT INTO public.jobs (
    id,
    customer_id,
    assigned_employee_id,
    job_type,
    description,
    status,
    assigned_at,
    created_at,
    updated_at,
    expires_at
  )
  VALUES (
    v_new_id,
    p_customer_id,
    p_assigned_employee_id,
    p_job_type,
    NULLIF(TRIM(p_description), ''),
    'assigned',
    now(),
    now(),
    now(),
    now() + INTERVAL '90 days'
  );

  -- 7) Append-only history: creation and assignment, attributed to the
  --    creating admin's employee row.
  INSERT INTO public.job_events (job_id, employee_id, event_type, occurred_at)
  VALUES (v_new_id, v_admin_employee_id, 'job_created', now());

  INSERT INTO public.job_events (job_id, employee_id, event_type, occurred_at)
  VALUES (v_new_id, v_admin_employee_id, 'job_assigned', now());

  RETURN QUERY
  SELECT *
  FROM public.jobs j
  WHERE j.id = v_new_id;
END;
$$;

-- Executable by signed-in users only; the function body itself refuses
-- everyone who is not an active admin.
REVOKE ALL ON FUNCTION public.create_job(uuid, text, text, uuid) FROM public;
REVOKE ALL ON FUNCTION public.create_job(uuid, text, text, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_job(uuid, text, text, uuid)
  TO authenticated;
