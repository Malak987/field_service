-- =============================================================================
-- Field Service — Before Photos (job_files table, register_job_file RPC,
-- private Storage bucket + object policies)
-- =============================================================================
-- Purpose:
--   After `start_job` flips a job to `in_progress`, the assigned technician
--   captures one or more BEFORE photos documenting the site condition. This
--   file provides the server side of that flow:
--
--   1. `public.job_files` — remote metadata of job-attached files. The app's
--      local Drift mirror (`job_files`) already exists; this is the remote
--      counterpart the sync engine pushes to. The client-generated file id is
--      the primary key, which is what makes retries idempotent.
--   2. `public.register_job_file(...)` — SECURITY DEFINER RPC and the ONLY
--      write path. It enforces the full ownership chain
--        auth.uid() → employees.auth_user_id → employees.id
--        → jobs.assigned_employee_id → job_files.job_id
--      refuses before photos for jobs that are not `in_progress`, inserts the
--      row idempotently (ON CONFLICT DO NOTHING) and appends exactly ONE
--      `before_photo_captured` event — with `occurred_at` set to the ORIGINAL
--      capture time, never the upload time.
--   3. A private Storage bucket `job-files` with object policies that mirror
--      the table authorization (assigned active employee or active admin).
--      Object paths follow `jobs/{job_id}/{file_type}/{file_id}{ext}` — the
--      stable file id, never the device filename, is the storage identity.
--
--   No policy grants technicians INSERT/UPDATE/DELETE on `public.job_files`;
--   registration happens exclusively inside the SECURITY DEFINER function.
--   No existing policy on jobs/customers is changed or weakened.
--
--   Self-contained on purpose: no helper functions are assumed to exist
--   (`is_active_admin()` / `get_my_role()` are not required); every check is
--   inlined, and no new helper functions are introduced.
--
-- Idempotent: re-running this file is safe (CREATE TABLE IF NOT EXISTS,
-- CREATE OR REPLACE FUNCTION, DROP POLICY IF EXISTS, ON CONFLICT DO NOTHING).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1) Remote `job_files` table
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.job_files (
  -- Stable, client-generated file id (uuid). Retries reuse the same id, so
  -- the same photo can never create a second row.
  id            uuid PRIMARY KEY,
  job_id        uuid NOT NULL REFERENCES public.jobs (id) ON DELETE CASCADE,
  -- The employee the upload was registered for; resolved server-side from
  -- auth.uid(), never accepted from the client.
  employee_id   uuid REFERENCES public.employees (id),
  -- 'before' | 'after' | 'signature' | 'document' (this phase uses 'before').
  file_type     text NOT NULL,
  -- Supabase Storage object path: jobs/{job_id}/{file_type}/{file_id}{ext}.
  storage_path  text NOT NULL,
  file_name     text NOT NULL,
  mime_type     text,
  size_bytes    bigint,
  -- The ORIGINAL capture time (client-recorded at capture, preserved through
  -- the whole sync path). Never replaced by the upload time.
  captured_at   timestamptz NOT NULL,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_job_files_job
  ON public.job_files (job_id);

ALTER TABLE public.job_files ENABLE ROW LEVEL SECURITY;

-- Reads: only the assigned ACTIVE employee of the owning job, or an active
-- admin. This is what lets the Job Details screen list a job's before photos
-- (and lets admins view them) while keeping every other job's files hidden.
DROP POLICY IF EXISTS job_files_select_assigned_or_admin ON public.job_files;
CREATE POLICY job_files_select_assigned_or_admin
  ON public.job_files
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.jobs j
      WHERE j.id = job_files.job_id
        AND (
          j.assigned_employee_id = (
            SELECT e.id
            FROM public.employees e
            WHERE e.auth_user_id = auth.uid()
              AND e.is_active = true
            LIMIT 1
          )
          OR EXISTS (
            SELECT 1
            FROM public.employees a
            WHERE a.auth_user_id = auth.uid()
              AND a.is_active = true
              AND a.role = 'admin'
          )
        )
    )
  );

-- Deliberately NO insert/update/delete policies: the RPC below is the only
-- write path (it runs as the table owner and therefore bypasses RLS).
GRANT SELECT ON public.job_files TO authenticated;

-- ---------------------------------------------------------------------------
-- 2) register_job_file — the ONLY registration path (SECURITY DEFINER)
-- ---------------------------------------------------------------------------
-- Contract:
--   * Accepts the file id generated on the device plus metadata. It resolves
--     the caller's identity itself (auth.uid() → active employee) and never
--     trusts a client-provided employee/customer id.
--   * Ownership: non-admins must be the job's assigned employee. Admins may
--     register for any job (existing management rights, nothing widened).
--   * Business rule: a `before` photo requires the job to be `in_progress`.
--   * Idempotent: if the file id is already registered (for the same job),
--     the call succeeds without touching anything — no duplicate row, no
--     duplicate event. This makes lost-ack sync replays safe.
--   * Atomic: row insert + event insert happen in one transaction.
--   * The event's occurred_at is p_captured_at (the original capture time).
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
  v_is_admin    boolean;
  v_job         public.jobs;
  v_inserted    integer;
BEGIN
  -- 1) Caller must be authenticated.
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated.'
      USING ERRCODE = '28000'; -- invalid_authorization_specification
  END IF;

  -- 2) Resolve the caller's ACTIVE employee row.
  SELECT e.id, (e.role = 'admin')
    INTO v_employee_id, v_is_admin
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

  -- 5) Authorization: active admins may register for any job; anyone else
  --    MUST be the assigned employee (an unassigned job is refused too).
  IF NOT v_is_admin
     AND v_job.assigned_employee_id IS DISTINCT FROM v_employee_id THEN
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
-- 3) Private Storage bucket + object policies
-- ---------------------------------------------------------------------------
-- Object identity: jobs/{job_id}/{file_type}/{file_id}{ext}. Uploads use
-- upsert on the same path, so a retried upload overwrites the same object —
-- never a second one. The policies below gate access by the SAME ownership
-- chain as the table policy: path segment 2 must be a job assigned to the
-- caller's active employee (or the caller is an active admin).
INSERT INTO storage.buckets (id, name, public)
VALUES ('job-files', 'job-files', false)
ON CONFLICT (id) DO NOTHING;

-- Read an object of an authorized job (viewing before photos).
DROP POLICY IF EXISTS job_files_objects_select ON storage.objects;
CREATE POLICY job_files_objects_select
  ON storage.objects
  FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'job-files'
    AND (storage.foldername(name))[1] = 'jobs'
    AND EXISTS (
      SELECT 1
      FROM public.jobs j
      WHERE (storage.foldername(name))[2] ~ '^[0-9a-fA-F-]{36}$'
        AND j.id = ((storage.foldername(name))[2])::uuid
        AND (
          j.assigned_employee_id = (
            SELECT e.id
            FROM public.employees e
            WHERE e.auth_user_id = auth.uid()
              AND e.is_active = true
            LIMIT 1
          )
          OR EXISTS (
            SELECT 1
            FROM public.employees a
            WHERE a.auth_user_id = auth.uid()
              AND a.is_active = true
              AND a.role = 'admin'
          )
        )
    )
  );

-- Upload an object to an authorized job. (Upserts reuse the INSERT path.)
DROP POLICY IF EXISTS job_files_objects_insert ON storage.objects;
CREATE POLICY job_files_objects_insert
  ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'job-files'
    AND (storage.foldername(name))[1] = 'jobs'
    AND EXISTS (
      SELECT 1
      FROM public.jobs j
      WHERE (storage.foldername(name))[2] ~ '^[0-9a-fA-F-]{36}$'
        AND j.id = ((storage.foldername(name))[2])::uuid
        AND (
          j.assigned_employee_id = (
            SELECT e.id
            FROM public.employees e
            WHERE e.auth_user_id = auth.uid()
              AND e.is_active = true
            LIMIT 1
          )
          OR EXISTS (
            SELECT 1
            FROM public.employees a
            WHERE a.auth_user_id = auth.uid()
              AND a.is_active = true
              AND a.role = 'admin'
          )
        )
    )
  );

-- Update an object of an authorized job (required for upserted retries of
-- the SAME object path; a new path is still an INSERT).
DROP POLICY IF EXISTS job_files_objects_update ON storage.objects;
CREATE POLICY job_files_objects_update
  ON storage.objects
  FOR UPDATE
  TO authenticated
  USING (
    bucket_id = 'job-files'
    AND (storage.foldername(name))[1] = 'jobs'
    AND EXISTS (
      SELECT 1
      FROM public.jobs j
      WHERE (storage.foldername(name))[2] ~ '^[0-9a-fA-F-]{36}$'
        AND j.id = ((storage.foldername(name))[2])::uuid
        AND (
          j.assigned_employee_id = (
            SELECT e.id
            FROM public.employees e
            WHERE e.auth_user_id = auth.uid()
              AND e.is_active = true
            LIMIT 1
          )
          OR EXISTS (
            SELECT 1
            FROM public.employees a
            WHERE a.auth_user_id = auth.uid()
              AND a.is_active = true
              AND a.role = 'admin'
          )
        )
    )
  )
  WITH CHECK (
    bucket_id = 'job-files'
    AND (storage.foldername(name))[1] = 'jobs'
    AND EXISTS (
      SELECT 1
      FROM public.jobs j
      WHERE (storage.foldername(name))[2] ~ '^[0-9a-fA-F-]{36}$'
        AND j.id = ((storage.foldername(name))[2])::uuid
        AND (
          j.assigned_employee_id = (
            SELECT e.id
            FROM public.employees e
            WHERE e.auth_user_id = auth.uid()
              AND e.is_active = true
            LIMIT 1
          )
          OR EXISTS (
            SELECT 1
            FROM public.employees a
            WHERE a.auth_user_id = auth.uid()
              AND a.is_active = true
              AND a.role = 'admin'
          )
        )
    )
  );

-- Deliberately NO delete policy on storage.objects: captured site
-- documentation is not deletable from the client in this phase.
