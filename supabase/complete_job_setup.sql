-- =============================================================================
-- Field Service — Complete Job (SECURITY DEFINER RPC)
-- =============================================================================
-- Purpose:
--   The FINAL workflow step and the ONLY write path for completing a job.
--   The server is the authority: it re-validates EVERY completion condition
--   itself (no client-supplied booleans like `has_before_photo`) and applies
--   the transition atomically:
--
--     jobs.status        = 'completed'
--     jobs.completed_at  = now()        (server time — the client never
--     jobs.updated_at    = now()        sends a timestamp)
--     job_events         += 'job_completed' (exactly one)
--
--   Completion conditions (all queried server-side):
--   1. the caller is authenticated and an ACTIVE employee with role
--      `technician` — admins are refused (they monitor read-only),
--   2. the job is assigned to exactly the caller's employee,
--   3. the job is currently `in_progress`,
--   4. at least one `job_files` row with file_type = 'before' exists,
--   5. `jobs.work_description` is non-empty after trimming,
--   6. at least one `job_files` row with file_type = 'after' exists,
--   7. at least one `job_files` row with file_type = 'signature' exists.
--
--   If ANY condition fails: no status change, no `completed_at`, no event.
--
-- Concurrency / idempotency:
--   The job row is locked (`FOR UPDATE`) for the whole function, so two
--   simultaneous completion requests serialize: the first performs the
--   transition, the second observes `status = 'completed'` and returns the
--   row UNCHANGED — no second mutation, no duplicate `job_completed` event,
--   `completed_at` never reset. Retries are therefore safe. Any other
--   status (`assigned`, `cancelled`, ...) raises: invalid state.
--
-- Error codes the client maps to localized explanations:
--   28000  not authenticated / no active employee
--   F0007  caller is not a technician (e.g. admin)          -> unauthorized
--   P0002  job not found
--   F0005  job not assigned to the caller                   -> not_assigned
--   F0006  job not in progress                              -> invalid_status
--   F0001  missing before photo                             -> missing_before_photo
--   F0002  missing/blank work description                   -> missing_work_description
--   F0003  missing after photo                              -> missing_after_photo
--   F0004  missing customer signature                       -> missing_signature
--
-- Self-contained like the other workflow RPCs: no helper functions are
-- assumed; every check is inlined. RLS on `public.jobs` / `job_files` /
-- `job_events` and all existing RPCs remain untouched. Idempotent: safe to
-- run again (CREATE OR REPLACE FUNCTION, REVOKE/GRANT).
-- =============================================================================

CREATE OR REPLACE FUNCTION public.complete_job(p_job_id uuid)
RETURNS SETOF public.jobs
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_employee_id uuid;
  v_role        text;
  v_job         public.jobs;
  v_updated     integer;
BEGIN
  -- 1) Caller must be authenticated.
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated.'
      USING ERRCODE = '28000'; -- invalid_authorization_specification
  END IF;

  -- 2) Resolve the caller's ACTIVE employee row. The client never supplies
  --    an employee id or a timestamp — identity comes from auth.uid().
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

  -- 3) Only ACTIVE TECHNICIANS complete jobs. Admins keep their read-only
  --    monitoring access and are refused here even when calling the
  --    function directly.
  IF v_role <> 'technician' THEN
    RAISE EXCEPTION 'Only the assigned technician can complete a job.'
      USING ERRCODE = 'F0007'; -- unauthorized role
  END IF;

  -- 4) Load and lock the target job for the whole transaction.
  SELECT *
    INTO v_job
  FROM public.jobs j
  WHERE j.id = p_job_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Job not found.'
      USING ERRCODE = 'P0002'; -- no_data_found
  END IF;

  -- 5) Ownership: the job must be assigned to exactly this technician.
  IF v_job.assigned_employee_id IS DISTINCT FROM v_employee_id THEN
    RAISE EXCEPTION 'This job is not assigned to you.'
      USING ERRCODE = 'F0005'; -- not_assigned
  END IF;

  -- 6) Duplicate-completion protection / invalid-state handling.
  IF v_job.status = 'completed' THEN
    -- Already completed: succeed without mutating anything — no second
    -- event, completed_at untouched. This keeps retries/replays safe.
    RETURN NEXT v_job;
    RETURN;
  END IF;

  IF v_job.status <> 'in_progress' THEN
    RAISE EXCEPTION 'Job cannot be completed from status "%".'
      , v_job.status
      USING ERRCODE = 'F0006'; -- invalid_status
  END IF;

  -- 7) Completion conditions — the server queries them itself; no flag
  --    from the client is trusted. If any is missing, NOTHING changes.
  IF NOT EXISTS (
    SELECT 1 FROM public.job_files f
    WHERE f.job_id = p_job_id AND f.file_type = 'before'
  ) THEN
    RAISE EXCEPTION 'A before photo is required to complete this job.'
      USING ERRCODE = 'F0001'; -- missing_before_photo
  END IF;

  IF v_job.work_description IS NULL
     OR btrim(v_job.work_description) = '' THEN
    RAISE EXCEPTION 'A work description is required to complete this job.'
      USING ERRCODE = 'F0002'; -- missing_work_description
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.job_files f
    WHERE f.job_id = p_job_id AND f.file_type = 'after'
  ) THEN
    RAISE EXCEPTION 'An after photo is required to complete this job.'
      USING ERRCODE = 'F0003'; -- missing_after_photo
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.job_files f
    WHERE f.job_id = p_job_id AND f.file_type = 'signature'
  ) THEN
    RAISE EXCEPTION 'A customer signature is required to complete this job.'
      USING ERRCODE = 'F0004'; -- missing_signature
  END IF;

  -- 8) Atomic completion: status + SERVER timestamps (the client never
  --    supplies completed_at) guarded by the current status so a racing
  --    request can never apply the transition twice.
  UPDATE public.jobs j
     SET status       = 'completed',
         completed_at = now(),
         updated_at   = now()
   WHERE j.id = p_job_id
     AND j.status = 'in_progress';

  GET DIAGNOSTICS v_updated = ROW_COUNT;

  IF v_updated = 0 THEN
    -- Lost the race despite the lock (defensive): nothing was changed, and
    -- no event is written.
    RAISE EXCEPTION 'Job cannot be completed from status "%".'
      , v_job.status
      USING ERRCODE = 'F0006';
  END IF;

  -- 9) Exactly ONE append-only audit event, server-stamped.
  INSERT INTO public.job_events (job_id, employee_id, event_type, occurred_at)
  VALUES (p_job_id, v_employee_id, 'job_completed', now());

  RETURN QUERY
  SELECT *
  FROM public.jobs j
  WHERE j.id = p_job_id;
END;
$$;

-- Executable by signed-in users only; `anon` and the implicit `public` role
-- get nothing. (RLS on `public.jobs` itself is untouched — technicians still
-- have no general UPDATE access; this function is the single narrow action.)
REVOKE ALL ON FUNCTION public.complete_job(uuid) FROM public;
REVOKE ALL ON FUNCTION public.complete_job(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.complete_job(uuid) TO authenticated;
