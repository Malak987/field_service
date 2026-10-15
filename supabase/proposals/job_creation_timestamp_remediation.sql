-- Heimwerk: preserve the original task creation timestamp for retention.
--
-- REVIEW ONLY. This proposal has not been applied. It targets the live
-- Supabase definitions inspected on 2026-10-14. Run only in a disposable
-- staging project after reviewing the preflight output and this rollback.
-- SCOPE LIMIT: this changes task timestamps only. It does NOT enforce expiry
-- on Storage uploads or register_job_file, implement retention cleanup, or
-- clean device-local queue/files. Do not treat it as complete retention
-- enforcement until a separate server-side expiry/deletion contract is
-- implemented and tested. The repository's current register_job_file and
-- job-files Storage policy definitions do not check expires_at; delayed file
-- retries may therefore reach those paths while a job exists, and a Storage
-- object can be orphaned if deletion races metadata registration.
--
-- The timestamp is supplied by the device and is user-tamperable. This SQL
-- does not make the device clock trustworthy, add a time service, or change
-- the retention policy. Calls without p_created_at use server time.
-- Flutter stores the timestamp in the durable create-operation payload;
-- legacy create operations fall back to their original queue createdAt.

-- -------------------------------------------------------------------------
-- READ-ONLY PREFLIGHT (run and review before applying)
-- -------------------------------------------------------------------------
-- Expected live contracts from the reviewed project:
--   technician_create_customer_and_job(text x9, uuid, uuid)
--   technician_create_job(uuid, text, text, uuid)
--   _tech_insert_job(uuid, uuid, uuid, text, text)
--   set_job_expiry_from_created_at() attached to jobs BEFORE INSERT OR UPDATE
--   technician_create_job_for_customer is absent.
-- Existing RPC owners are postgres. The two public technician RPCs grant
-- EXECUTE only to authenticated (plus owner); anon/service_role cannot call.
--
-- SELECT p.oid::regprocedure AS signature,
--        pg_get_userbyid(p.proowner) AS owner,
--        p.proacl,
--        has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_exec,
--        has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth_exec,
--        has_function_privilege('service_role', p.oid, 'EXECUTE') AS service_exec,
--        pg_get_functiondef(p.oid) AS definition
-- FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
-- WHERE n.nspname='public'
--   AND p.proname IN ('technician_create_customer_and_job',
--                     'technician_create_job',
--                     'technician_create_job_for_customer',
--                     '_tech_insert_job',
--                     'set_job_expiry_from_created_at')
-- ORDER BY p.proname, p.oid::regprocedure::text;
--
-- SELECT t.tgname, pg_get_triggerdef(t.oid) AS trigger_definition
-- FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
-- JOIN pg_namespace n ON n.oid=c.relnamespace
-- WHERE n.nspname='public' AND c.relname='jobs' AND NOT t.tgisinternal;
--
-- SELECT count(*) AS jobs_with_expiry_mismatch
-- FROM public.jobs
-- WHERE expires_at IS DISTINCT FROM created_at + INTERVAL '1 year';
--
-- Review the complete definitions above. In particular, confirm the live
-- customer ownership checks and technician checks still match the baseline.
-- Do not proceed if a signature, owner, ACL, trigger, definition, or expiry
-- mismatch differs from the documented baseline below.

BEGIN;

-- Fail closed if this proposal is run against a different schema/role state.
DO $$
DECLARE
  v_rpc_oid oid;
  v_trigger_oid oid;
  v_def text;
  v_trigger_count integer;
  v_rpc_count integer;
  v_named_count integer;
  v_expiry_mismatches bigint;
BEGIN
  IF current_user <> 'postgres' THEN
    RAISE EXCEPTION 'Run as postgres so function ownership/default privileges are deterministic.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='service_role')
     OR NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon')
     OR NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN
    RAISE EXCEPTION 'Expected Supabase roles are missing; review the target project.';
  END IF;
  IF to_regclass('public.jobs') IS NULL
     OR to_regclass('public.employees') IS NULL
     OR to_regclass('public.customers') IS NULL
     OR to_regclass('public.job_events') IS NULL
     OR to_regprocedure('public._tech_insert_customer(uuid,uuid,text,text,text,text,text,text,text)') IS NULL THEN
    RAISE EXCEPTION 'Required Heimwerk tables/helper are missing; no change applied.';
  END IF;
  IF NOT EXISTS (
       SELECT 1 FROM pg_attribute a
       WHERE a.attrelid='public.jobs'::regclass AND a.attname='created_at'
         AND a.atttypid='timestamptz'::regtype AND a.attnotnull AND NOT a.attisdropped
     )
     OR NOT EXISTS (
       SELECT 1 FROM pg_attribute a
       WHERE a.attrelid='public.jobs'::regclass AND a.attname='expires_at'
         AND a.atttypid='timestamptz'::regtype AND NOT a.attisdropped
     ) THEN
    RAISE EXCEPTION 'Expected jobs.created_at NOT NULL and timestamptz expiry columns.';
  END IF;

  SELECT count(*) INTO v_rpc_count FROM pg_proc p
  JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname='technician_create_customer_and_job';
  IF v_rpc_count <> 1 OR to_regprocedure(
    'public.technician_create_customer_and_job(text,text,text,text,text,text,text,text,text,uuid,uuid)'
  ) IS NULL THEN
    RAISE EXCEPTION 'Expected exactly the inspected 11-argument customer/job RPC.';
  END IF;
  SELECT p.oid INTO v_rpc_oid FROM pg_proc p
  WHERE p.oid=to_regprocedure(
    'public.technician_create_customer_and_job(text,text,text,text,text,text,text,text,text,uuid,uuid)'
  );
  IF pg_get_userbyid((SELECT proowner FROM pg_proc WHERE oid=v_rpc_oid)) <> 'postgres'
     OR (SELECT proacl::text FROM pg_proc WHERE oid=v_rpc_oid) <> '{postgres=X/postgres,authenticated=X/postgres}'
     OR has_function_privilege('anon', v_rpc_oid, 'EXECUTE')
     OR NOT has_function_privilege('authenticated', v_rpc_oid, 'EXECUTE')
     OR has_function_privilege('service_role', v_rpc_oid, 'EXECUTE') THEN
    RAISE EXCEPTION 'Live customer/job RPC owner or effective grants differ from the reviewed baseline.';
  END IF;
  v_def := lower(pg_get_functiondef(v_rpc_oid));
  IF position('auth.uid()' IN v_def)=0
     OR position('e.is_active = true' IN v_def)=0
     OR position('v_role <> ''technician''' IN v_def)=0
     OR position('assigned_employee_id is distinct from v_emp' IN v_def)=0
     OR position('created_by_employee_id is distinct from v_emp' IN v_def)=0
     OR position('public._tech_insert_customer' IN v_def)=0 THEN
    RAISE EXCEPTION 'Live customer/job RPC security behavior differs from the reviewed baseline.';
  END IF;

  SELECT count(*) INTO v_rpc_count FROM pg_proc p
  JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname='technician_create_job';
  IF v_rpc_count <> 1 OR to_regprocedure(
    'public.technician_create_job(uuid,text,text,uuid)'
  ) IS NULL THEN
    RAISE EXCEPTION 'Expected exactly the inspected technician_create_job RPC.';
  END IF;
  SELECT p.oid INTO v_rpc_oid FROM pg_proc p
  WHERE p.oid=to_regprocedure('public.technician_create_job(uuid,text,text,uuid)');
  IF pg_get_userbyid((SELECT proowner FROM pg_proc WHERE oid=v_rpc_oid)) <> 'postgres'
     OR (SELECT proacl::text FROM pg_proc WHERE oid=v_rpc_oid) <> '{postgres=X/postgres,authenticated=X/postgres}'
     OR has_function_privilege('anon', v_rpc_oid, 'EXECUTE')
     OR NOT has_function_privilege('authenticated', v_rpc_oid, 'EXECUTE')
     OR has_function_privilege('service_role', v_rpc_oid, 'EXECUTE') THEN
    RAISE EXCEPTION 'Live technician_create_job owner or effective grants differ from the reviewed baseline.';
  END IF;
  v_def := lower(pg_get_functiondef(v_rpc_oid));
  IF position('auth.uid()' IN v_def)=0
     OR position('e.is_active = true' IN v_def)=0
     OR position('v_role <> ''technician''' IN v_def)=0
     OR position('created_by_employee_id = v_emp' IN v_def)=0
     OR position('j.assigned_employee_id = v_emp' IN v_def)=0 THEN
    RAISE EXCEPTION 'Live technician_create_job access behavior differs from the reviewed baseline.';
  END IF;

  IF to_regprocedure('public._tech_insert_job(uuid,uuid,uuid,text,text)') IS NULL
     OR to_regprocedure('public._tech_insert_job_with_created_at(uuid,uuid,uuid,text,text,timestamptz)') IS NOT NULL THEN
    RAISE EXCEPTION 'Expected old helper only; the timestamp helper already exists or the old helper is missing.';
  END IF;
  SELECT p.oid INTO v_rpc_oid FROM pg_proc p
  WHERE p.oid=to_regprocedure('public._tech_insert_job(uuid,uuid,uuid,text,text)');
  IF pg_get_userbyid((SELECT proowner FROM pg_proc WHERE oid=v_rpc_oid)) <> 'postgres'
     OR (SELECT proacl::text FROM pg_proc WHERE oid=v_rpc_oid) <> '{postgres=X/postgres}'
     OR has_function_privilege('anon', v_rpc_oid, 'EXECUTE')
     OR has_function_privilege('authenticated', v_rpc_oid, 'EXECUTE')
     OR has_function_privilege('service_role', v_rpc_oid, 'EXECUTE') THEN
    RAISE EXCEPTION 'Live helper owner or effective grants differ from the reviewed baseline.';
  END IF;

  SELECT count(*) INTO v_named_count FROM pg_proc p
  JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname='technician_create_job_for_customer';
  IF v_named_count <> 0 THEN
    RAISE EXCEPTION 'A technician_create_job_for_customer overload already exists; review before adding another.';
  END IF;
  SELECT count(*) INTO v_trigger_count
  FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
  JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND c.relname='jobs' AND NOT t.tgisinternal;
  IF v_trigger_count = 1 THEN
    SELECT t.oid INTO v_trigger_oid
    FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
    JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='public' AND c.relname='jobs' AND NOT t.tgisinternal;
  END IF;
  IF v_trigger_count <> 1
     OR (SELECT tgname FROM pg_trigger WHERE oid=v_trigger_oid) <> 'jobs_enforce_expiry_from_created_at'
     OR (SELECT tgfoid FROM pg_trigger WHERE oid=v_trigger_oid)
          <> to_regprocedure('public.set_job_expiry_from_created_at()')
     OR (SELECT tgenabled FROM pg_trigger WHERE oid=v_trigger_oid) <> 'O'
     OR pg_get_triggerdef(v_trigger_oid) <>
       'CREATE TRIGGER jobs_enforce_expiry_from_created_at BEFORE INSERT OR UPDATE ON public.jobs FOR EACH ROW EXECUTE FUNCTION set_job_expiry_from_created_at()' THEN
    RAISE EXCEPTION 'Expected one enabled jobs trigger bound to public.set_job_expiry_from_created_at() with the inspected definition.';
  END IF;
  v_rpc_oid := to_regprocedure('public.set_job_expiry_from_created_at()');
  IF v_rpc_oid IS NULL
     OR pg_get_userbyid((SELECT proowner FROM pg_proc WHERE oid=v_rpc_oid)) <> 'postgres'
     OR (SELECT proacl::text FROM pg_proc WHERE oid=v_rpc_oid) <> '{postgres=X/postgres}'
     OR has_function_privilege('anon', v_rpc_oid, 'EXECUTE')
     OR has_function_privilege('authenticated', v_rpc_oid, 'EXECUTE')
     OR has_function_privilege('service_role', v_rpc_oid, 'EXECUTE') THEN
    RAISE EXCEPTION 'Expiry trigger function owner or effective grants differ from the reviewed baseline.';
  END IF;
  v_def := lower(pg_get_functiondef(v_rpc_oid));
  IF position('new.expires_at := new.created_at + interval ''1 year''' IN v_def)=0 THEN
    RAISE EXCEPTION 'Expiry trigger function definition differs from the reviewed baseline.';
  END IF;

  SELECT count(*) INTO v_expiry_mismatches
  FROM public.jobs
  WHERE expires_at IS DISTINCT FROM created_at + INTERVAL '1 year';
  IF v_expiry_mismatches <> 0 THEN
    RAISE EXCEPTION 'Existing expiry values differ from created_at + 1 year; investigate before changing trigger behavior.';
  END IF;
END;
$$;

-- This trigger keeps the original creation timestamp immutable. On UPDATE it
-- also preserves the existing expiry value; on INSERT it derives expiry from
-- the accepted creation timestamp exactly once.
CREATE OR REPLACE FUNCTION public.set_job_expiry_from_created_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF NEW.created_at IS DISTINCT FROM OLD.created_at THEN
      RAISE EXCEPTION 'jobs.created_at is immutable.' USING ERRCODE = '23514';
    END IF;
    NEW.created_at := OLD.created_at;
    NEW.expires_at := OLD.expires_at;
    RETURN NEW;
  END IF;

  IF NEW.created_at IS NULL THEN
    NEW.created_at := pg_catalog.statement_timestamp();
  END IF;
  NEW.expires_at := NEW.created_at + INTERVAL '1 year';
  RETURN NEW;
END;
$$;

-- Add a timestamp-aware private helper under a distinct name. Avoids creating
-- an overload of the live five-argument helper and leaves that helper and
-- technician_create_job untouched.
CREATE FUNCTION public._tech_insert_job_with_created_at(
  p_employee_id uuid,
  p_job_id uuid,
  p_customer_id uuid,
  p_job_type text,
  p_description text,
  p_created_at timestamptz
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_id uuid := COALESCE(p_job_id, gen_random_uuid());
  v_created_at timestamptz := COALESCE(p_created_at, statement_timestamp());
BEGIN
  IF p_job_type IS NULL
     OR p_job_type NOT IN ('home_renovation', 'kitchen_renovation') THEN
    RAISE EXCEPTION 'Unsupported job category.' USING ERRCODE = 'P0001';
  END IF;
  IF length(COALESCE(p_description, '')) > 4000 THEN
    RAISE EXCEPTION 'Description is too long (max 4000 characters).' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.jobs (
    id, customer_id, assigned_employee_id, job_type, description, status,
    assigned_at, created_at, updated_at, expires_at
  ) VALUES (
    v_id, p_customer_id, p_employee_id, p_job_type,
    NULLIF(btrim(COALESCE(p_description, '')), ''), 'assigned',
    statement_timestamp(), v_created_at, statement_timestamp(),
    v_created_at + INTERVAL '1 year'
  );

  -- Event timestamps are server acceptance time; created_at remains the
  -- original device-recorded task time.
  INSERT INTO public.job_events (job_id, employee_id, event_type, occurred_at)
  VALUES (v_id, p_employee_id, 'job_created', statement_timestamp());
  INSERT INTO public.job_events (job_id, employee_id, event_type, occurred_at)
  VALUES (v_id, p_employee_id, 'job_assigned', statement_timestamp());
  RETURN v_id;
END;
$$;
ALTER FUNCTION public._tech_insert_job_with_created_at(uuid, uuid, uuid, text, text, timestamptz)
  OWNER TO postgres;
REVOKE ALL ON FUNCTION public._tech_insert_job_with_created_at(uuid, uuid, uuid, text, text, timestamptz)
  FROM PUBLIC, anon, authenticated, service_role;

-- Replace the single live RPC signature (no overloads; PostgREST does not
-- support overloaded function APIs). All prior parameters retain their names,
-- positions and defaults. The new final default keeps callers that omit
-- p_created_at compatible, while new Flutter calls send it explicitly.
DROP FUNCTION public.technician_create_customer_and_job(
  text, text, text, text, text, text, text, text, text, uuid, uuid
);
CREATE FUNCTION public.technician_create_customer_and_job(
  p_name text,
  p_phone text,
  p_email text,
  p_address text,
  p_city text,
  p_postal_code text,
  p_notes text,
  p_job_type text,
  p_description text,
  p_customer_id uuid DEFAULT NULL,
  p_job_id uuid DEFAULT NULL,
  p_created_at timestamptz DEFAULT NULL
)
RETURNS SETOF public.jobs
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_emp uuid;
  v_role text;
  v_existing public.jobs;
  v_cust uuid;
  v_job_id uuid;
  v_customer public.customers;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated.' USING ERRCODE = '28000';
  END IF;
  SELECT e.id, e.role INTO v_emp, v_role
  FROM public.employees e
  WHERE e.auth_user_id = auth.uid() AND e.is_active = true
  LIMIT 1;
  IF v_emp IS NULL THEN
    RAISE EXCEPTION 'No active employee is linked to this account.' USING ERRCODE = '28000';
  END IF;
  IF v_role <> 'technician' THEN
    RAISE EXCEPTION 'Only an active technician can use this action.' USING ERRCODE = '42501';
  END IF;

  IF p_job_id IS NOT NULL THEN
    SELECT * INTO v_existing FROM public.jobs WHERE id = p_job_id;
    IF FOUND THEN
      IF v_existing.assigned_employee_id IS DISTINCT FROM v_emp THEN
        RAISE EXCEPTION 'This job id is already in use.' USING ERRCODE = '42501';
      END IF;
      RETURN NEXT v_existing;
      RETURN;
    END IF;
  END IF;

  IF p_customer_id IS NOT NULL THEN
    SELECT * INTO v_customer FROM public.customers WHERE id = p_customer_id;
    IF FOUND THEN
      IF v_customer.created_by_employee_id IS DISTINCT FROM v_emp THEN
        RAISE EXCEPTION 'This customer id is already in use.' USING ERRCODE = '42501';
      END IF;
      v_cust := v_customer.id;
    END IF;
  END IF;

  IF v_cust IS NULL THEN
    v_cust := public._tech_insert_customer(
      v_emp, p_customer_id, p_name, p_phone, p_email, p_address,
      p_city, p_postal_code, p_notes
    );
  END IF;
  v_job_id := public._tech_insert_job_with_created_at(
    v_emp, p_job_id, v_cust, p_job_type, p_description, p_created_at
  );
  RETURN QUERY SELECT * FROM public.jobs WHERE id = v_job_id;
END;
$$;
ALTER FUNCTION public.technician_create_customer_and_job(
  text, text, text, text, text, text, text, text, text, uuid, uuid, timestamptz
) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.technician_create_customer_and_job(
  text, text, text, text, text, text, text, text, text, uuid, uuid, timestamptz
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.technician_create_customer_and_job(
  text, text, text, text, text, text, text, text, text, uuid, uuid, timestamptz
) TO authenticated;

-- This endpoint is absent in the inspected live project but is the current
-- Flutter RPC for a task assigned to an existing customer. Match the live
-- technician_create_job owner/assignment checks exactly: technician must be
-- active; customer must be created by this technician or already linked to
-- this technician's job. Do not add an account_status filter here.
-- Defaults preserve calls that omit description and/or p_created_at.
CREATE FUNCTION public.technician_create_job_for_customer(
  p_customer_id uuid,
  p_job_id uuid,
  p_job_type text,
  p_description text DEFAULT NULL,
  p_created_at timestamptz DEFAULT NULL
)
RETURNS SETOF public.jobs
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_emp uuid;
  v_role text;
  v_existing public.jobs;
  v_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated.' USING ERRCODE = '28000';
  END IF;
  SELECT e.id, e.role INTO v_emp, v_role
  FROM public.employees e
  WHERE e.auth_user_id = auth.uid() AND e.is_active = true
  LIMIT 1;
  IF v_emp IS NULL THEN
    RAISE EXCEPTION 'No active employee is linked to this account.' USING ERRCODE = '28000';
  END IF;
  IF v_role <> 'technician' THEN
    RAISE EXCEPTION 'Only an active technician can use this action.' USING ERRCODE = '42501';
  END IF;
  IF p_customer_id IS NULL OR p_job_id IS NULL THEN
    RAISE EXCEPTION 'A customer id and a job id are required.' USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_existing FROM public.jobs WHERE id = p_job_id;
  IF FOUND THEN
    IF v_existing.assigned_employee_id IS DISTINCT FROM v_emp THEN
      RAISE EXCEPTION 'This job id is already in use.' USING ERRCODE = '42501';
    END IF;
    RETURN NEXT v_existing;
    RETURN;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.customers c
    WHERE c.id = p_customer_id
      AND (c.created_by_employee_id = v_emp OR EXISTS (
        SELECT 1 FROM public.jobs j
        WHERE j.customer_id = c.id AND j.assigned_employee_id = v_emp
      ))
  ) THEN
    RAISE EXCEPTION 'Customer not found or not allowed.' USING ERRCODE = 'P0002';
  END IF;

  v_id := public._tech_insert_job_with_created_at(
    v_emp, p_job_id, p_customer_id, p_job_type, p_description, p_created_at
  );
  RETURN QUERY SELECT * FROM public.jobs WHERE id = v_id;
END;
$$;
ALTER FUNCTION public.technician_create_job_for_customer(
  uuid, uuid, text, text, timestamptz
) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.technician_create_job_for_customer(
  uuid, uuid, text, text, timestamptz
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.technician_create_job_for_customer(
  uuid, uuid, text, text, timestamptz
) TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;

-- -------------------------------------------------------------------------
-- READ-ONLY POST-APPLY CHECKS (run in staging; do not use as a substitute
-- for behavioral tests)
-- -------------------------------------------------------------------------
-- SELECT p.oid::regprocedure AS signature, pg_get_userbyid(p.proowner) owner,
--        p.proacl,
--        has_function_privilege('anon',p.oid,'EXECUTE') AS anon_exec,
--        has_function_privilege('authenticated',p.oid,'EXECUTE') AS auth_exec,
--        has_function_privilege('service_role',p.oid,'EXECUTE') AS service_exec,
--        pg_get_functiondef(p.oid) AS definition
-- FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
-- WHERE n.nspname='public'
--   AND p.proname IN ('technician_create_customer_and_job',
--                     'technician_create_job',
--                     'technician_create_job_for_customer',
--                     '_tech_insert_job','set_job_expiry_from_created_at')
-- ORDER BY p.proname,p.oid::regprocedure::text;
-- Expected: exactly one technician_create_customer_and_job signature exists,
-- with the final p_created_at default; technician_create_job remains exactly
-- unchanged; the separately named helper is present and there are no API
-- overloads.
-- all new functions owner=postgres; RPC EXECUTE authenticated=true and
-- anon/service_role=false; helper and trigger function are not executable by
-- anon/authenticated/service_role. Compare the printed technician_create_job
-- body/ACL with the preflight output; its grants and definition must match.
--
-- SELECT t.tgname, t.tgenabled, t.tgfoid::regprocedure AS trigger_function,
--        pg_get_triggerdef(t.oid)
-- FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
-- JOIN pg_namespace n ON n.oid=c.relnamespace
-- WHERE n.nspname='public' AND c.relname='jobs' AND NOT t.tgisinternal;
-- SELECT count(*) AS jobs_with_expiry_mismatch
-- FROM public.jobs WHERE expires_at IS DISTINCT FROM created_at + INTERVAL '1 year';
--
-- STAGING BEHAVIORAL CHECKS (use disposable employee/customer/job fixtures;
-- wrap data checks in a transaction and ROLLBACK there):
-- 1. Call the new 12-argument customer/job RPC without p_created_at (using
--    old named-argument payloads) and the unchanged technician_create_job RPC.
--    Confirm auth, customer ownership, job assignment and idempotency remain.
-- 2. Call the customer/job RPC with a known p_created_at and the new
--    technician_create_job_for_customer RPC with p_created_at. Confirm
--    created_at equals that instant and expires_at equals created_at + 1 year.
-- 3. Call technician_create_job_for_customer without p_created_at; confirm
--    the RPC remains callable and the server supplies the timestamp.
-- 4. Try UPDATE jobs SET created_at=... and confirm SQLSTATE 23514; try an
--    ordinary job update including a forged expires_at and confirm both
--    created_at and expires_at remain unchanged.
-- 5. Verify a technician cannot use another technician's customer/job id,
--    and that no new account_status restriction rejects a previously
--    accessible customer.
-- 6. Replay each create with the same job id and a different timestamp; the
--    existing row/timestamp must be returned unchanged.
-- 7. Retention integration gate (requires the separate cleanup/expiry
--    contract; this proposal alone cannot pass it): try a pending file upload
--    for a server-expired job and for a deleted job. The server must reject
--    before accepting bytes when possible, and register_job_file must reject
--    atomically if expiry/deletion occurs after upload. Verify the local
--    queue payload, photos/signatures, and local bytes remain available for
--    user resolution, with no automatic infinite retries or silent removal.

-- -------------------------------------------------------------------------
-- MANUAL ROLLBACK AFTER A SUCCESSFUL COMMIT
-- Stop/retire clients that send p_created_at first.
-- This is a new transaction and does NOT rely on ROLLBACK from the apply
-- transaction. Run only if the post-apply objects still match these exact
-- signatures. DROP uses RESTRICT by default and fails safely if dependencies
-- have since been added.
-- technician_create_job and the old five-argument _tech_insert_job were
-- never replaced and need no restoration.
--
-- BEGIN;
-- DROP FUNCTION public.technician_create_job_for_customer(
--   uuid, uuid, text, text, timestamptz
-- );
-- DROP FUNCTION public.technician_create_customer_and_job(
--   text, text, text, text, text, text, text, text, text, uuid, uuid, timestamptz
-- );
-- DROP FUNCTION public._tech_insert_job_with_created_at(
--   uuid, uuid, uuid, text, text, timestamptz
-- );
-- CREATE FUNCTION public.technician_create_customer_and_job(
--   p_name text,
--   p_phone text,
--   p_email text,
--   p_address text,
--   p_city text,
--   p_postal_code text,
--   p_notes text,
--   p_job_type text,
--   p_description text,
--   p_customer_id uuid DEFAULT NULL,
--   p_job_id uuid DEFAULT NULL
-- )
-- RETURNS SETOF public.jobs
-- LANGUAGE plpgsql
-- SECURITY DEFINER
-- SET search_path = 'public'
-- AS $$
-- DECLARE
--   v_emp uuid;
--   v_role text;
--   v_existing public.jobs;
--   v_cust uuid;
--   v_id uuid;
--   v_ec public.customers;
-- BEGIN
--   IF auth.uid() IS NULL THEN
--     RAISE EXCEPTION 'Not authenticated.' USING ERRCODE = '28000';
--   END IF;
--   SELECT e.id, e.role INTO v_emp, v_role
--   FROM public.employees e
--   WHERE e.auth_user_id = auth.uid() AND e.is_active = true LIMIT 1;
--   IF v_emp IS NULL THEN
--     RAISE EXCEPTION 'No active employee is linked to this account.' USING ERRCODE = '28000';
--   END IF;
--   IF v_role <> 'technician' THEN
--     RAISE EXCEPTION 'Only an active technician can use this action.' USING ERRCODE = '42501';
--   END IF;
--
--   IF p_job_id IS NOT NULL THEN
--     SELECT * INTO v_existing FROM public.jobs WHERE id = p_job_id;
--     IF FOUND THEN
--       IF v_existing.assigned_employee_id IS DISTINCT FROM v_emp THEN
--         RAISE EXCEPTION 'This job id is already in use.' USING ERRCODE = '42501';
--       END IF;
--       RETURN NEXT v_existing;
--       RETURN;
--     END IF;
--   END IF;
--
--   IF p_customer_id IS NOT NULL THEN
--     SELECT * INTO v_ec FROM public.customers WHERE id = p_customer_id;
--     IF FOUND THEN
--       IF v_ec.created_by_employee_id IS DISTINCT FROM v_emp THEN
--         RAISE EXCEPTION 'This customer id is already in use.' USING ERRCODE = '42501';
--       END IF;
--       v_cust := v_ec.id;
--     END IF;
--   END IF;
--   IF v_cust IS NULL THEN
--     v_cust := public._tech_insert_customer(
--       v_emp, p_customer_id, p_name, p_phone, p_email, p_address,
--       p_city, p_postal_code, p_notes
--     );
--   END IF;
--   v_id := public._tech_insert_job(v_emp, p_job_id, v_cust, p_job_type, p_description);
--   RETURN QUERY SELECT * FROM public.jobs WHERE id = v_id;
-- END;
-- $$;
-- ALTER FUNCTION public.technician_create_customer_and_job(
--   text, text, text, text, text, text, text, text, text, uuid, uuid
-- ) OWNER TO postgres;
-- REVOKE ALL ON FUNCTION public.technician_create_customer_and_job(
--   text, text, text, text, text, text, text, text, text, uuid, uuid
-- ) FROM PUBLIC, anon, authenticated, service_role;
-- GRANT EXECUTE ON FUNCTION public.technician_create_customer_and_job(
--   text, text, text, text, text, text, text, text, text, uuid, uuid
-- ) TO authenticated;
-- CREATE OR REPLACE FUNCTION public.set_job_expiry_from_created_at()
-- RETURNS trigger
-- LANGUAGE plpgsql
-- SET search_path = ''
-- AS $$
-- BEGIN
--   NEW.expires_at := NEW.created_at + INTERVAL '1 year';
--   RETURN NEW;
-- END;
-- $$;
-- COMMIT;
--
-- The trigger function's original owner was postgres and its ACL was owner
-- only; CREATE OR REPLACE preserves both. The original trigger definition is
-- left attached and unchanged. This rollback restores old future UPDATE
-- behavior (recompute expiry from created_at); it does not rewrite any rows.
