-- Heimwerk: expired-job write protection and retryable Storage cleanup queue.
-- REVIEW ONLY. Do not apply to production. Test after the separate
-- job_creation_timestamp_remediation.sql has been validated/applied in staging.
-- No existing technician workflow RPC or permissive Storage policy is replaced.
--
-- Required before use: verify live employee columns, job_files cascade behavior,
-- owners/ACLs, all policies, and the timestamp migration's jobs trigger. This
-- proposal intentionally fails if the expected objects already exist.

-- READ-ONLY PREFLIGHT:
-- SELECT p.oid::regprocedure, pg_get_userbyid(p.proowner), p.proacl,
--        pg_get_functiondef(p.oid)
-- FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
-- WHERE n.nspname='public' AND p.proname IN
--   ('register_job_file','start_job','save_work_description','complete_job',
--    'authorize_job_file_upload','jobs_guard_expiry_and_tombstone');
-- SELECT c.relname, c.relrowsecurity, c.relforcerowsecurity
-- FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
-- WHERE (n.nspname='public' AND c.relname IN ('jobs','job_files'))
--    OR (n.nspname='storage' AND c.relname='objects');
-- SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
-- FROM pg_policies WHERE (schemaname,tablename) IN
--   (('public','jobs'),('public','job_files'),('storage','objects'));
-- SELECT tgname, pg_get_triggerdef(oid) FROM pg_trigger
-- WHERE tgrelid='public.jobs'::regclass AND NOT tgisinternal;

BEGIN;
DO $$
BEGIN
  IF current_user <> 'postgres' THEN
    RAISE EXCEPTION 'Apply only as postgres in an isolated staging project.';
  END IF;
  IF to_regclass('public.jobs') IS NULL OR to_regclass('public.job_files') IS NULL
     OR to_regclass('public.employees') IS NULL OR to_regclass('storage.objects') IS NULL
     OR to_regprocedure('public.register_job_file(uuid,uuid,text,text,text,text,bigint,timestamptz)') IS NULL
     OR to_regprocedure('public.set_job_expiry_from_created_at()') IS NULL THEN
    RAISE EXCEPTION 'Required reviewed objects are missing; no changes applied.';
  END IF;
  IF to_regprocedure('public.authorize_job_file_upload(uuid)') IS NOT NULL
     OR to_regclass('public.job_retention_tombstones') IS NOT NULL
     OR to_regclass('public.job_storage_cleanup_outbox') IS NOT NULL THEN
    RAISE EXCEPTION 'A proposed object already exists; inspect instead of replacing it.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid='public.jobs'::regclass
                 AND attname='expires_at' AND NOT attisdropped)
     OR NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid='public.employees'::regclass
                    AND attname='auth_user_id' AND NOT attisdropped) THEN
    RAISE EXCEPTION 'Expected expiry or employee identity columns are missing.';
  END IF;
END;
$$;

-- Minimal tombstone prevents an old idempotent create retry from resurrecting
-- a deleted job. It contains no customer, employee, or task details.
CREATE TABLE public.job_retention_tombstones (
  job_id uuid PRIMARY KEY,
  deleted_at timestamptz NOT NULL DEFAULT pg_catalog.statement_timestamp()
);
ALTER TABLE public.job_retention_tombstones ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.job_retention_tombstones FROM PUBLIC, anon, authenticated, service_role;

-- A durable prefix task closes the race where an upload finishes just after a
-- purge listed the folder. The worker must repeatedly list/remove this prefix
-- and only mark complete after a successful empty listing.
CREATE TABLE public.job_storage_cleanup_outbox (
  job_id uuid PRIMARY KEY,
  storage_prefix text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.statement_timestamp(),
  attempts integer NOT NULL DEFAULT 0,
  last_error text,
  processed_at timestamptz
);
ALTER TABLE public.job_storage_cleanup_outbox ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.job_storage_cleanup_outbox FROM PUBLIC, anon, authenticated;
GRANT SELECT, UPDATE ON public.job_storage_cleanup_outbox TO service_role;

CREATE FUNCTION public.jobs_guard_expiry_and_tombstone()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF EXISTS (SELECT 1 FROM public.job_retention_tombstones t WHERE t.job_id=NEW.id) THEN
      RAISE EXCEPTION 'JOB_DELETED: this job id was already deleted.' USING ERRCODE='P0001';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'Job creation time is immutable.' USING ERRCODE='23514';
  END IF;
  IF OLD.expires_at IS NULL OR OLD.expires_at <= pg_catalog.statement_timestamp() THEN
    RAISE EXCEPTION 'JOB_EXPIRED: this job is no longer writable.' USING ERRCODE='P0001';
  END IF;
  NEW.created_at := OLD.created_at;
  NEW.expires_at := OLD.expires_at;
  RETURN NEW;
END;
$$;
ALTER FUNCTION public.jobs_guard_expiry_and_tombstone() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.jobs_guard_expiry_and_tombstone() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER jobs_guard_expiry_and_tombstone
BEFORE INSERT OR UPDATE ON public.jobs
FOR EACH ROW EXECUTE FUNCTION public.jobs_guard_expiry_and_tombstone();

CREATE FUNCTION public.job_files_guard_expiry()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_expires_at timestamptz;
BEGIN
  SELECT j.expires_at INTO v_expires_at FROM public.jobs j WHERE j.id=NEW.job_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'JOB_DELETED: job does not exist.' USING ERRCODE='P0001';
  END IF;
  IF v_expires_at IS NULL OR v_expires_at <= pg_catalog.statement_timestamp() THEN
    RAISE EXCEPTION 'JOB_EXPIRED: this job is no longer writable.' USING ERRCODE='P0001';
  END IF;
  RETURN NEW;
END;
$$;
ALTER FUNCTION public.job_files_guard_expiry() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.job_files_guard_expiry() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER job_files_guard_expiry
BEFORE INSERT OR UPDATE ON public.job_files
FOR EACH ROW EXECUTE FUNCTION public.job_files_guard_expiry();

CREATE FUNCTION public.job_deleted_enqueue_storage_cleanup()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  INSERT INTO public.job_retention_tombstones(job_id) VALUES (OLD.id)
  ON CONFLICT (job_id) DO NOTHING;
  INSERT INTO public.job_storage_cleanup_outbox(job_id, storage_prefix)
  VALUES (OLD.id, 'jobs/' || OLD.id::text || '/')
  ON CONFLICT (job_id) DO NOTHING;
  RETURN OLD;
END;
$$;
ALTER FUNCTION public.job_deleted_enqueue_storage_cleanup() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.job_deleted_enqueue_storage_cleanup() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER jobs_enqueue_storage_cleanup
BEFORE DELETE ON public.jobs
FOR EACH ROW EXECUTE FUNCTION public.job_deleted_enqueue_storage_cleanup();

-- Called before sending bytes. This repeats the existing technician/job
-- ownership rule without replacing register_job_file; the latter still makes
-- the final authorization and state decision after upload.
CREATE FUNCTION public.authorize_job_file_upload(p_job_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_employee_id uuid; v_assigned_id uuid; v_expires_at timestamptz;
BEGIN
  SELECT e.id INTO v_employee_id FROM public.employees e
  WHERE e.auth_user_id=auth.uid() AND e.is_active=true AND e.role='technician';
  IF v_employee_id IS NULL THEN
    RAISE EXCEPTION 'Only an active technician may upload job files.' USING ERRCODE='42501';
  END IF;
  SELECT j.assigned_employee_id, j.expires_at
    INTO v_assigned_id, v_expires_at FROM public.jobs j WHERE j.id=p_job_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'JOB_DELETED: job does not exist.' USING ERRCODE='P0001';
  END IF;
  IF v_expires_at IS NULL OR v_expires_at <= pg_catalog.statement_timestamp() THEN
    RAISE EXCEPTION 'JOB_EXPIRED: this job is no longer writable.' USING ERRCODE='P0001';
  END IF;
  IF v_assigned_id IS DISTINCT FROM v_employee_id THEN
    RAISE EXCEPTION 'This job is not assigned to you.' USING ERRCODE='42501';
  END IF;
END;
$$;
ALTER FUNCTION public.authorize_job_file_upload(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.authorize_job_file_upload(uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.authorize_job_file_upload(uuid) TO authenticated;

-- Restrictive policies only subtract access from existing policies. Existing
-- permissive ownership/admin checks stay in force. INSERT+UPDATE cover upsert.
CREATE POLICY job_files_storage_unexpired_insert ON storage.objects
AS RESTRICTIVE FOR INSERT TO authenticated
WITH CHECK (bucket_id <> 'job-files' OR EXISTS (
  SELECT 1 FROM public.jobs j
  WHERE (storage.foldername(name))[1]='jobs'
    AND (storage.foldername(name))[2] ~ '^[0-9a-fA-F-]{36}$'
    AND j.id=((storage.foldername(name))[2])::uuid
    AND j.expires_at > pg_catalog.statement_timestamp()
));
CREATE POLICY job_files_storage_unexpired_update ON storage.objects
AS RESTRICTIVE FOR UPDATE TO authenticated
USING (bucket_id <> 'job-files' OR EXISTS (
  SELECT 1 FROM public.jobs j
  WHERE (storage.foldername(name))[1]='jobs'
    AND (storage.foldername(name))[2] ~ '^[0-9a-fA-F-]{36}$'
    AND j.id=((storage.foldername(name))[2])::uuid
    AND j.expires_at > pg_catalog.statement_timestamp()
))
WITH CHECK (bucket_id <> 'job-files' OR EXISTS (
  SELECT 1 FROM public.jobs j
  WHERE (storage.foldername(name))[1]='jobs'
    AND (storage.foldername(name))[2] ~ '^[0-9a-fA-F-]{36}$'
    AND j.id=((storage.foldername(name))[2])::uuid
    AND j.expires_at > pg_catalog.statement_timestamp()
));

-- POST-CHANGE VERIFICATION (read-only): inspect trigger/policies/function ACL;
-- run staging-only valid/expired/missing/unassigned cases; verify old RPC ACLs
-- and definitions byte-for-byte against the preflight snapshot.
-- SELECT tgname, pg_get_triggerdef(oid) FROM pg_trigger
-- WHERE tgrelid IN ('public.jobs'::regclass,'public.job_files'::regclass)
--   AND NOT tgisinternal ORDER BY tgname;
-- SELECT policyname, permissive, roles, cmd, qual, with_check FROM pg_policies
-- WHERE schemaname='storage' AND tablename='objects'
--   AND policyname LIKE 'job_files_storage_unexpired_%';
-- SELECT p.oid::regprocedure, pg_get_userbyid(p.proowner), p.proacl,
--   has_function_privilege('anon',p.oid,'EXECUTE') AS anon_exec,
--   has_function_privilege('authenticated',p.oid,'EXECUTE') AS auth_exec,
--   has_function_privilege('service_role',p.oid,'EXECUTE') AS service_exec
-- FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
-- WHERE n.nspname='public' AND p.proname='authorize_job_file_upload';
COMMIT;

-- ROLLBACK PLAN AFTER COMMIT (manual; SQL ROLLBACK is no longer applicable):
-- First stop the new outbox worker and export its rows plus all tombstone ids.
-- Drop the three named triggers, two restrictive policies, and four helper functions,
-- then restore the preflight-snapshotted definitions/ACLs only if separately
-- changed. Do not drop populated tombstones/outbox blindly: that can permit
-- job resurrection or lose pending Storage cleanup. Restore a staging snapshot
-- if a fully clean rollback is required. No previous RPC definition is
-- replaced by this proposal.

-- STORAGE OUTBOX WORKER CONTRACT (not implemented/deployed here): claim a
-- pending row with FOR UPDATE SKIP LOCKED; list all objects under prefix;
-- remove returned exact paths (missing objects are success); list again; set
-- processed_at only after the prefix is empty. On failure increment attempts
-- and persist a short sanitized error. This worker must be added to the
-- existing purge function or a reviewed separate Edge Function before apply.
-- The active remote purge worker is not changed by this local proposal.
