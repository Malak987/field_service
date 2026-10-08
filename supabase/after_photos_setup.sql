-- =============================================================================
-- Field Service — After Photos (generalizes register_job_file for
-- file_type = 'after')
-- =============================================================================
-- Purpose:
--   After the technician documented the work, they capture one or more AFTER
--   photos documenting the finished site condition. The job file
--   architecture of the Before Photos phase is REUSED end to end:
--
--   * the SAME `public.job_files` table (no new table),
--   * the SAME private `job-files` Storage bucket and object policies — the
--     existing policies gate objects by job ownership, not by file type, so
--     `jobs/{job_id}/after/{file_id}{ext}` is already covered (no storage
--     change),
--   * the SAME `job_events` system — a successfully registered after photo
--     appends exactly ONE `after_photo_captured` event whose `occurred_at`
--     is the ORIGINAL capture time, never the upload time,
--   * the SAME idempotency mechanism (client-generated file id,
--     ON CONFLICT DO NOTHING, replay returns without a second row/event).
--
--   The ONLY server-side change is this generalized `register_job_file`,
--   which now distinguishes before vs after:
--
--   1. Both `before` AND `after` photos require the job to be `in_progress`.
--      (Previously only `before` was checked; after photos now carry the
--      same rule — capture happens while work is in progress, never before
--      the job started and never after it completed.)
--   2. A NEW registration emits the matching event exactly once:
--        before → `before_photo_captured`   (unchanged)
--        after  → `after_photo_captured`
--   3. The storage path must actually point at the job/file it registers:
--      `jobs/{job_id}/{file_type}/{file_id}…` — a mismatch is refused, so a
--      caller can never link an object path outside the job's own folder.
--
--   PRESERVED, unchanged, from the corrected workflow phase
--   (job_workflow_permissions_setup.sql):
--   * authentication + resolution of the caller's ACTIVE employee row from
--     auth.uid() — the client never supplies an employee id,
--   * technician-only authorization: admins are refused (they keep their
--     read-only SELECT access for monitoring and can never register files,
--     not even by calling this function directly),
--   * ownership: the job must be assigned to exactly the caller's employee,
--   * replay safety on the stable file id,
--   * atomic row + event insert in one transaction.
--
--   Idempotent: re-running this file is safe (CREATE OR REPLACE FUNCTION,
--   REVOKE/GRANT). No other SQL file is modified; the Before Photos table,
--   bucket, policies and RLS remain exactly as they were.
-- =============================================================================

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
  v_event_type  text;
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

  -- 7) Business rule: before AND after photos document an in-progress job —
  --    before photos the site before work, after photos the finished work.
  --    Both are only accepted while the job is in progress: never before
  --    Start Job, never after completion. (The UI offers capture only in
  --    that window; the server enforces it regardless.)
  IF p_file_type IN ('before', 'after') AND v_job.status <> 'in_progress' THEN
    RAISE EXCEPTION
      'Photos can only be added to a job that is in progress.'
      USING ERRCODE = 'P0001';
  END IF;

  -- 7b) Storage path integrity: the registered object must live under this
  --     job's own folder segment for exactly this file type and file id —
  --     `jobs/{job_id}/{file_type}/{file_id}…`. Anything else is refused.
  IF p_storage_path NOT LIKE
     'jobs/' || p_job_id::text || '/' || p_file_type || '/'
       || p_file_id::text || '%' THEN
    RAISE EXCEPTION 'The storage path does not match the registered file.'
      USING ERRCODE = 'P0001';
  END IF;

  -- 8) Atomic registration: the file row plus (only when the row is new)
  --    exactly ONE event whose occurred_at is the ORIGINAL capture time —
  --    never the upload time. The event type follows the photo kind.
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

  IF v_inserted > 0 THEN
    v_event_type := CASE p_file_type
      WHEN 'before' THEN 'before_photo_captured'
      WHEN 'after'  THEN 'after_photo_captured'
      ELSE NULL
    END;

    IF v_event_type IS NOT NULL THEN
      INSERT INTO public.job_events (
        job_id, employee_id, event_type, occurred_at
      )
      VALUES (
        p_job_id, v_employee_id, v_event_type, p_captured_at
      );
    END IF;
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
