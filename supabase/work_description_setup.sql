-- =============================================================================
-- Field Service — Work Description (technician's record of the actual work)
-- =============================================================================
-- Purpose:
--   The technician documents WHAT WAS ACTUALLY DONE on the job. This is a
--   separate concept from `jobs.description`, which holds the ADMIN'S
--   customer request entered at job creation. The two are never merged:
--
--     jobs.description        — admin's customer request (create-time)
--     jobs.work_description   — technician's actual work (execution-time)
--
-- This file provides:
--   1. `jobs.work_description` — dedicated nullable text column on the
--      existing `jobs` table (no second table, no second event system).
--   2. `save_work_description(job_id, work_description)` — SECURITY DEFINER
--      RPC and the ONLY write path, in the exact tradition of `start_job`
--      and `register_job_file`:
--        * caller authenticated, resolved to an ACTIVE employee row via
--          `employees.auth_user_id = auth.uid()` (the client never supplies
--          an employee id for authorization),
--        * caller must have role 'technician' — admins are REFUSED
--          (42501): they may view work descriptions (plain jobs SELECT),
--          never write them, even by calling the RPC directly,
--        * the job must exist, be assigned to EXACTLY that technician, and
--          be `in_progress` — assigned/completed/cancelled jobs are
--          refused, so nothing can be modified after completion,
--        * input validated server-side: not null, not blank after TRIM,
--          at most 4000 characters,
--        * the stored value is the TRIMmed text with `updated_at = now()`;
--          the authoritative save time lives in the event's `occurred_at`
--          (`now()`), never a client-provided timestamp,
--        * exactly one `work_description_added` event per EFFECTIVE change.
--
-- Replay/idempotency:
--   If the stored value already equals the submitted value (a replayed sync
--   operation after a lost ack), the call succeeds WITHOUT updating and
--   WITHOUT a second event. A changed value updates the column and appends
--   one new event. Retries can therefore never duplicate events.
--
-- Preserved (untouched): every existing RLS policy (admins keep SELECT on
-- all jobs — hence can view work descriptions; technicians keep SELECT on
-- their own jobs), `start_job`, `register_job_file`, `create_job`,
-- `get_job_customer`, the job events architecture.
--
-- EXECUTE THIS FILE IN SUPABASE before releasing the client feature.
-- Idempotent: re-running is safe (ADD COLUMN IF NOT EXISTS, CREATE OR
-- REPLACE FUNCTION, REVOKE/GRANT).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1) Dedicated column for the technician's work description
-- ---------------------------------------------------------------------------
ALTER TABLE public.jobs
  ADD COLUMN IF NOT EXISTS work_description text;

-- ---------------------------------------------------------------------------
-- 2) save_work_description — the ONLY write path (SECURITY DEFINER)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.save_work_description(
  p_job_id           uuid,
  p_work_description text
)
RETURNS SETOF public.jobs
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_employee_id uuid;
  v_role        text;
  v_job         public.jobs;
  v_clean       text;
BEGIN
  -- 1) Caller must be authenticated.
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated.'
      USING ERRCODE = '28000'; -- invalid_authorization_specification
  END IF;

  -- 2) Resolve the caller's ACTIVE employee row from the auth identity.
  --    The employee id is NEVER accepted from the client.
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

  -- 3) Role: ONLY technicians write work descriptions. Admins are refused
  --    outright — they monitor jobs (read access via the jobs SELECT
  --    policies) but never execute the technician workflow.
  IF v_role <> 'technician' THEN
    RAISE EXCEPTION 'Only the assigned technician can save the work description.'
      USING ERRCODE = '42501'; -- insufficient_privilege
  END IF;

  -- 4) Validation: not null, not blank, within the length limit.
  IF p_work_description IS NULL THEN
    RAISE EXCEPTION 'Work description is required.'
      USING ERRCODE = 'P0001';
  END IF;

  v_clean := TRIM(p_work_description);

  IF v_clean = '' THEN
    RAISE EXCEPTION 'Work description cannot be empty.'
      USING ERRCODE = 'P0001';
  END IF;

  IF LENGTH(v_clean) > 4000 THEN
    RAISE EXCEPTION 'Work description is too long (maximum 4000 characters).'
      USING ERRCODE = 'P0001';
  END IF;

  -- 5) Load and lock the target job.
  SELECT *
    INTO v_job
  FROM public.jobs j
  WHERE j.id = p_job_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Job not found.'
      USING ERRCODE = 'P0002'; -- no_data_found
  END IF;

  -- 6) Ownership: exactly the assigned technician (another technician's
  --    job, or an unassigned job, is refused).
  IF v_job.assigned_employee_id IS DISTINCT FROM v_employee_id THEN
    RAISE EXCEPTION 'This job is not assigned to you.'
      USING ERRCODE = '42501'; -- insufficient_privilege
  END IF;

  -- 7) Business rule: work descriptions are written WHILE the job is being
  --    executed. Assigned jobs have no work yet; completed/cancelled jobs
  --    are closed — neither can be modified.
  IF v_job.status <> 'in_progress' THEN
    RAISE EXCEPTION
      'Work description can only be saved while the job is in progress.'
      USING ERRCODE = 'P0001';
  END IF;

  -- 8) Idempotent apply: only an EFFECTIVE change updates the row and
  --    appends an event. A replayed sync operation (same value already
  --    stored) succeeds without touching anything — no duplicate event.
  IF v_job.work_description IS DISTINCT FROM v_clean THEN
    UPDATE public.jobs j
       SET work_description = v_clean,
           updated_at       = now()
     WHERE j.id = p_job_id;

    INSERT INTO public.job_events (
      job_id, employee_id, event_type, occurred_at
    )
    VALUES (p_job_id, v_employee_id, 'work_description_added', now());
  END IF;

  RETURN QUERY
  SELECT *
  FROM public.jobs j
  WHERE j.id = p_job_id;
END;
$$;

-- Executable by signed-in users only; the function body itself refuses
-- everyone who is not the job's assigned active technician.
REVOKE ALL ON FUNCTION public.save_work_description(uuid, text) FROM public;
REVOKE ALL ON FUNCTION public.save_work_description(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.save_work_description(uuid, text)
  TO authenticated;
