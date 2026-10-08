-- =============================================================================
-- Field Service — Customer Signature (generalizes register_job_file for
-- file_type = 'signature')
-- =============================================================================
-- Purpose:
--   After the after photos, the customer signs on the technician's device.
--   The signature image (a PNG rendered from the touch drawing) reuses the
--   job-file architecture of the photo phases END TO END:
--
--   * the SAME `public.job_files` table (no signatures table),
--   * the SAME private `job-files` Storage bucket and object policies — the
--     policies gate objects by job ownership, not by file type, so
--     `jobs/{job_id}/signature/{file_id}{ext}` is already covered (no
--     storage change),
--   * the SAME `job_events` system — a successfully registered signature
--     appends exactly ONE `signature_captured` event whose `occurred_at` is
--     the ORIGINAL capture time (same convention as the photo events: the
--     client-recorded capture time travels as metadata; every row
--     created_at/updated_at stays server-generated `now()`),
--   * the SAME idempotency mechanism (client-generated file id,
--     ON CONFLICT DO NOTHING, replay returns without a second row/event).
--
--   The ONLY server-side change is this generalized `register_job_file`,
--   which now treats `signature` like the photos where the rules match:
--
--   1. Signatures, like before/after photos, require the job to be
--      `in_progress` — never before Start Job, never after completion.
--   2. A NEW registration emits the matching event exactly once:
--        before    → `before_photo_captured`   (unchanged)
--        after     → `after_photo_captured`    (unchanged)
--        signature → `signature_captured`      (new)
--
--   PRESERVED, unchanged, from the earlier workflow phases:
--   * authentication + resolution of the caller's ACTIVE employee row from
--     auth.uid() — the client never supplies an employee id,
--   * technician-only authorization: admins are refused for ALL file types
--     (they keep their read-only SELECT access for monitoring and can never
--     capture/replace a signature, not even by calling this function
--     directly),
--   * ownership: the job must be assigned to exactly the caller's employee,
--   * storage-path integrity: the object must live under
--     `jobs/{job_id}/{file_type}/{file_id}…`,
--   * replay safety on the stable file id,
--   * atomic row + event insert in one transaction.
--
--   Idempotent: re-running this file is safe (CREATE OR REPLACE FUNCTION,
--   REVOKE/GRANT). No other SQL file is modified; the Before/After Photos
--   rules, table, bucket, policies and RLS remain exactly as they were.
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
  --    capture photos or signatures, even by calling this function
  --    directly.
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

  -- 7) Business rule: before/after photos AND the customer signature all
  --    document an in-progress job — never before Start Job, never after
  --    completion. (The UI offers capture only in that window; the server
  --    enforces it regardless.)
  IF p_file_type IN ('before', 'after', 'signature')
     AND v_job.status <> 'in_progress' THEN
    RAISE EXCEPTION
      'Job files can only be added to a job that is in progress.'
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
  --    never the upload time. The event type follows the file kind.
  -- The live `public.job_files` schema persists identity + classification
  -- only: (id, job_id, file_type, storage_path, captured_at, created_at).
  -- `created_at` stays server-generated (DEFAULT now()); the metadata
  -- parameters (file name, mime type, size) are accepted for client
  -- compatibility but have no column in the table and are not persisted.
  INSERT INTO public.job_files (
    id, job_id, file_type, storage_path, captured_at
  )
  VALUES (
    p_file_id, p_job_id, p_file_type, p_storage_path, p_captured_at
  )
  ON CONFLICT (id) DO NOTHING;

  GET DIAGNOSTICS v_inserted = ROW_COUNT;

  IF v_inserted > 0 THEN
    v_event_type := CASE p_file_type
      WHEN 'before'    THEN 'before_photo_captured'
      WHEN 'after'     THEN 'after_photo_captured'
      WHEN 'signature' THEN 'signature_captured'
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
