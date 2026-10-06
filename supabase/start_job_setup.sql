-- =============================================================================
-- Field Service — Start Job (SECURITY DEFINER RPC)
-- =============================================================================
-- Purpose:
--   The ONLY write path for technicians to start a job. Technicians get no
--   UPDATE policy on `public.jobs` (existing RLS is untouched); starting is
--   a narrow server-side action that:
--
--   1. authenticates the caller (`auth.uid()`),
--   2. resolves their ACTIVE employee row,
--   3. verifies the job is assigned to exactly that employee
--      (auth.uid() → employees.auth_user_id → employees.id
--       → jobs.assigned_employee_id → target job),
--   4. verifies the job is currently `assigned`,
--   5. atomically sets `status = 'in_progress'`, `started_at = now()`,
--      `updated_at = now()` (server time is authoritative — the client never
--      sends a timestamp),
--   6. appends one `job_events` row (`job_started`), never twice.
--
-- Duplicate-start protection:
--   * `assigned`  → performs the start (the only mutating path).
--   * `in_progress` → returns the current row UNCHANGED: no second event,
--     `started_at` never reset. This makes offline-sync retries idempotent:
--     if the first push succeeded but the queue row was not marked synced
--     (crash / lost ack), the replayed operation simply observes the started
--     job and succeeds.
--   * any other status (completed, cancelled, ...) → raises: invalid state.
--
-- Admins:
--   An ACTIVE admin may start any job (their existing management rights are
--   preserved). This does not widen technician rights in any way.
--
-- Self-contained on purpose: the function does not assume any helper
-- function exists (`is_active_admin()` / `get_my_role()` are not required);
-- every check is inlined below.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.start_job(p_job_id uuid)
RETURNS SETOF public.jobs
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_employee_id uuid;
  v_is_admin    boolean;
  v_job         public.jobs;
BEGIN
  -- 1) Caller must be authenticated.
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated.'
      USING ERRCODE = '28000'; -- invalid_authorization_specification
  END IF;

  -- 2) Resolve the caller's ACTIVE employee row (role captured for step 3).
  SELECT e.id, (e.role = 'admin')
    INTO v_employee_id, v_is_admin
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

  -- 4) Authorization: active admins may start any job; anyone else MUST be
  --    the assigned employee. An unassigned job (assigned_employee_id NULL)
  --    can therefore never be started by a technician.
  IF NOT v_is_admin
     AND v_job.assigned_employee_id IS DISTINCT FROM v_employee_id THEN
    RAISE EXCEPTION 'This job is not assigned to you.'
      USING ERRCODE = '42501'; -- insufficient_privilege
  END IF;

  -- 5) Duplicate-start protection / invalid-state handling.
  IF v_job.status = 'in_progress' THEN
    -- Already started (by whoever was entitled to): succeed without
    -- mutating anything — no second event, started_at untouched. This is
    -- what makes queued sync retries safe.
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

-- Executable by signed-in users only; `anon` and the implicit `public` role
-- get nothing. (RLS on `public.jobs` itself is untouched — technicians still
-- have no general UPDATE access; this function is the single narrow action.)
REVOKE ALL ON FUNCTION public.start_job(uuid) FROM public;
REVOKE ALL ON FUNCTION public.start_job(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.start_job(uuid) TO authenticated;
