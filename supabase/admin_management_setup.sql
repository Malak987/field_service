-- =============================================================================
-- Field Service — Admin Management (Technicians & Customers)
-- =============================================================================
-- Purpose:
--   Give an ACTIVE ADMIN full, server-enforced control over the technicians
--   and the customers of the system:
--
--     TECHNICIANS   list (real names + current state), block, unblock,
--                   soft delete (never a hard delete, never an orphaned
--                   history).
--     CUSTOMERS     list (details), create, edit, block, unblock,
--                   soft delete.
--
--   Everything is enforced in the DATABASE, not in the Flutter UI:
--   * every management action is a SECURITY DEFINER RPC whose FIRST step is
--     an inline "is the caller an active admin?" check (42501 otherwise) —
--     a technician calling the function directly, with any payload, gets
--     refused;
--   * the existing employees RLS ("employees_write_admin_only") keeps every
--     direct table write admin-only as well, so a technician cannot PATCH
--     `employees` (no self-unblock, no role escalation);
--   * blocking sets `employees.is_active = false`, the single flag every
--     existing RPC (`start_job`, `register_job_file`, `save_work_description`,
--     `complete_job`) and every existing RLS policy already tests — so an
--     OLD JWT of a blocked technician keeps authenticating but every
--     protected read/write is refused by the database;
--   * RESTRICTIVE guard policies are added on top of the existing permissive
--     policies of `jobs`, `job_files`, `customers` and the `storage.objects`
--     rows of the private `job-files` bucket: they can only ever SUBTRACT
--     access, never grant it, so a blocked/deleted employee loses table and
--     Storage access even if a permissive policy elsewhere was widened.
--
-- What this file deliberately does NOT do:
--   * it never deletes an `employees` row, never deletes a `customers` row,
--     never touches `auth.users`, never reassigns `jobs.assigned_employee_id`
--     and never deletes `job_files` / `job_events` — work history, photos
--     and signatures are preserved and stay readable to the roles that could
--     already read them;
--   * it does not install any CASCADE delete;
--   * it does not change the registration path: `handle_new_auth_user()`
--     still creates exactly one `technician` row (never `admin`) after the
--     e-mail confirmation / first sign-up, and nothing in this file lets a
--     client choose a role at sign-up.
--
-- Idempotent: safe to re-run (ADD COLUMN IF NOT EXISTS, DROP POLICY IF
-- EXISTS, CREATE OR REPLACE FUNCTION, ON CONFLICT DO NOTHING).
--
-- Order: run AFTER authentication_setup.sql, job_workflow_permissions_setup.sql
-- and the job-file setup files (it replaces `create_job` and `is_active_admin`
-- with a superset of their current behaviour).
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 0) Pre-flight guards — fail loudly (and roll back) instead of half-applying
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'employees'
      AND column_name = 'is_active'
  ) THEN
    RAISE EXCEPTION
      'public.employees.is_active not found — apply authentication_setup.sql first.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'employees'
      AND column_name = 'auth_user_id'
  ) THEN
    RAISE EXCEPTION
      'public.employees.auth_user_id not found — apply authentication_setup.sql first.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'jobs'
      AND column_name = 'assigned_employee_id'
  ) THEN
    RAISE EXCEPTION
      'public.jobs.assigned_employee_id not found — this file targets the jobs workflow schema.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'customers'
      AND column_name = 'address'
  ) THEN
    RAISE EXCEPTION
      'public.customers.address not found — this file targets the customers schema.';
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- 1) employees — admin-managed account lifecycle
-- ---------------------------------------------------------------------------
-- `is_active` remains THE security flag (every RPC/RLS already tests it).
-- `account_status` is the admin-facing state machine and is kept in sync with
-- `is_active` by the trigger below, so both always agree:
--
--   account_status = 'active'  <=>  is_active = true
--   account_status = 'blocked' <=>  is_active = false  (blocked_at stamped)
--   account_status = 'deleted' <=>  is_active = false  (deleted_at stamped)
--
-- Soft delete = 'deleted'. The row, the Auth account, the job assignments,
-- the job_files and the job_events are all left untouched.
ALTER TABLE public.employees
  ADD COLUMN IF NOT EXISTS account_status text NOT NULL DEFAULT 'active';

ALTER TABLE public.employees
  ADD COLUMN IF NOT EXISTS blocked_at timestamptz;

ALTER TABLE public.employees
  ADD COLUMN IF NOT EXISTS deleted_at timestamptz;

ALTER TABLE public.employees
  ADD COLUMN IF NOT EXISTS status_changed_at timestamptz;

-- Who performed the last status change (`employees.id` of the acting admin).
ALTER TABLE public.employees
  ADD COLUMN IF NOT EXISTS status_changed_by uuid;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'employees_status_changed_by_fkey'
      AND conrelid = 'public.employees'::regclass
  ) THEN
    ALTER TABLE public.employees
      ADD CONSTRAINT employees_status_changed_by_fkey
      FOREIGN KEY (status_changed_by) REFERENCES public.employees (id)
      ON DELETE SET NULL;
  END IF;
END;
$$;

ALTER TABLE public.employees
  DROP CONSTRAINT IF EXISTS employees_account_status_check;
ALTER TABLE public.employees
  ADD CONSTRAINT employees_account_status_check
  CHECK (account_status IN ('active', 'blocked', 'deleted'));

-- Backfill: any pre-existing row that was deactivated (`is_active <> true`)
-- becomes 'blocked' — the state it effectively is in today. Rows are never
-- silently set back to active.
UPDATE public.employees
   SET is_active = false
 WHERE is_active IS NULL;

UPDATE public.employees
   SET account_status = 'blocked',
       blocked_at     = COALESCE(blocked_at, updated_at, now())
 WHERE account_status = 'active'
   AND is_active IS NOT TRUE;

-- `is_active` is now guaranteed NOT NULL with a default (existing rows were
-- just backfilled; the trigger below keeps it consistent from now on).
ALTER TABLE public.employees
  ALTER COLUMN is_active SET DEFAULT true;

ALTER TABLE public.employees
  ALTER COLUMN is_active SET NOT NULL;

-- The invariant, enforced in the database — not by convention:
--   * account_status is authoritative; is_active mirrors it;
--   * a legacy/out-of-band `is_active` update cannot silently resurrect a
--     deleted account (an explicit account_status change is required, and the
--     admin RPC below is the only supported path);
--   * flipping is_active = false on an active account downgrades it to
--     'blocked' (never to 'deleted').
CREATE OR REPLACE FUNCTION public.sync_employee_account_status()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.account_status := COALESCE(NEW.account_status, 'active');
    NEW.is_active      := (NEW.account_status = 'active');
    RETURN NEW;
  END IF;

  IF NEW.account_status IS DISTINCT FROM OLD.account_status THEN
    -- Explicit lifecycle change (the admin RPC path): status wins.
    NEW.is_active := (NEW.account_status = 'active');
  ELSIF NEW.is_active IS DISTINCT FROM OLD.is_active THEN
    -- Legacy flag-only update.
    IF NEW.is_active THEN
      IF OLD.account_status = 'deleted' THEN
        -- Deleted accounts are not resurrected by flipping the legacy flag.
        NEW.is_active := false;
      ELSE
        NEW.account_status := 'active';
      END IF;
    ELSIF OLD.account_status = 'active' THEN
      NEW.account_status := 'blocked';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS sync_employee_account_status ON public.employees;
CREATE TRIGGER sync_employee_account_status
  BEFORE INSERT OR UPDATE ON public.employees
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_employee_account_status();

-- ---------------------------------------------------------------------------
-- 2) Authorization helpers
-- ---------------------------------------------------------------------------
-- `is_active_admin()` — same contract as authentication_setup.sql, hardened:
-- a deleted administrator is NOT an active admin any more.
CREATE OR REPLACE FUNCTION public.is_active_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.employees e
    WHERE e.auth_user_id = auth.uid()
      AND e.role = 'admin'
      AND e.is_active = true
      AND e.account_status = 'active'
  );
$$;

-- `is_active_employee()` — true only for a signed-in user whose employee row
-- is active AND not blocked/deleted. Used by the RESTRICTIVE guard policies
-- below (section 8); it is a pure predicate and returns false for `anon`.
CREATE OR REPLACE FUNCTION public.is_active_employee()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.employees e
    WHERE e.auth_user_id = auth.uid()
      AND e.is_active = true
      AND e.account_status = 'active'
  );
$$;

-- ---------------------------------------------------------------------------
-- 3) Admin action log (append-only audit trail)
-- ---------------------------------------------------------------------------
-- Written ONLY by the SECURITY DEFINER RPCs below (no INSERT policy exists),
-- readable by active admins. Rows are never updated or deleted by the app.
CREATE TABLE IF NOT EXISTS public.admin_action_log (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_employee_id uuid REFERENCES public.employees (id) ON DELETE SET NULL,
  entity_type       text NOT NULL CHECK (entity_type IN ('employee', 'customer')),
  entity_id         uuid NOT NULL,
  action            text NOT NULL,
  previous_status   text,
  new_status        text,
  created_at        timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_admin_action_log_entity
  ON public.admin_action_log (entity_type, entity_id, created_at DESC);

ALTER TABLE public.admin_action_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS admin_action_log_select_admin ON public.admin_action_log;
CREATE POLICY admin_action_log_select_admin
  ON public.admin_action_log
  FOR SELECT
  TO authenticated
  USING (public.is_active_admin());

GRANT SELECT ON public.admin_action_log TO authenticated;

-- ---------------------------------------------------------------------------
-- 4) Technician management RPCs
-- ---------------------------------------------------------------------------

-- 4a) admin_list_employees — every employee row with its real name, its
--     current state and its job history counters. Admin-only.
CREATE OR REPLACE FUNCTION public.admin_list_employees()
RETURNS TABLE (
  id             uuid,
  name           text,
  email          text,
  employee_code  text,
  phone          text,
  role           text,
  is_active      boolean,
  account_status text,
  blocked_at     timestamptz,
  deleted_at     timestamptz,
  assigned_jobs  bigint,
  completed_jobs bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_id uuid;
BEGIN
  SELECT a.id
    INTO v_admin_id
  FROM public.employees a
  WHERE a.auth_user_id = auth.uid()
    AND a.role = 'admin'
    AND a.is_active = true
    AND a.account_status = 'active'
  LIMIT 1;

  IF v_admin_id IS NULL THEN
    RAISE EXCEPTION 'Only an active admin can list employees.'
      USING ERRCODE = '42501'; -- insufficient_privilege
  END IF;

  RETURN QUERY
  SELECT
    e.id,
    e.name,
    e.email,
    e.employee_code,
    e.phone,
    e.role,
    e.is_active,
    e.account_status,
    e.blocked_at,
    e.deleted_at,
    (SELECT count(*) FROM public.jobs j WHERE j.assigned_employee_id = e.id),
    (SELECT count(*)
       FROM public.jobs j
      WHERE j.assigned_employee_id = e.id
        AND j.status = 'completed')
  FROM public.employees e
  ORDER BY
    CASE e.account_status
      WHEN 'active'  THEN 0
      WHEN 'blocked' THEN 1
      ELSE 2
    END,
    e.name ASC NULLS LAST,
    e.id ASC;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_employees() FROM public;
REVOKE ALL ON FUNCTION public.admin_list_employees() FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_list_employees() TO authenticated;

-- 4b) admin_set_employee_status — the ONLY supported lifecycle transition.
--
--   p_status = 'blocked' : is_active = false, blocked_at stamped. Every
--                          protected RPC and every RLS policy of the app
--                          refuses the technician from that moment on, even
--                          with a still-valid JWT.
--   p_status = 'active'  : unblock / (re)activate — refused for a soft
--                          deleted technician.
--   p_status = 'deleted' : SOFT delete — deleted_at stamped, is_active =
--                          false. The row, the Auth account, the assigned
--                          jobs (incl. their current assignments), the
--                          job_files and the job_events stay exactly as they
--                          are; nothing is cascaded.
--
-- Guard rails (all server-side):
--   * caller must be an active admin                    -> 42501
--   * an admin can never change their own status        -> 42501
--   * only `technician` rows are managed here, so an
--     admin cannot lock the last administrator out      -> P0001
--   * a soft deleted technician is never reactivated
--     or re-blocked through this function               -> P0001
--   * an unknown id                                     -> P0002
CREATE OR REPLACE FUNCTION public.admin_set_employee_status(
  p_employee_id uuid,
  p_status      text
)
RETURNS TABLE (
  id             uuid,
  name           text,
  email          text,
  employee_code  text,
  phone          text,
  role           text,
  is_active      boolean,
  account_status text,
  blocked_at     timestamptz,
  deleted_at     timestamptz,
  assigned_jobs  bigint,
  completed_jobs bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
#variable_conflict use_column
DECLARE
  v_admin_id  uuid;
  v_target    public.employees;
  v_previous  text;
BEGIN
  IF p_status IS NULL OR p_status NOT IN ('active', 'blocked', 'deleted') THEN
    RAISE EXCEPTION 'Unsupported account status.'
      USING ERRCODE = 'P0001';
  END IF;

  -- Caller must be an ACTIVE admin (a blocked or deleted admin is refused).
  SELECT a.id
    INTO v_admin_id
  FROM public.employees a
  WHERE a.auth_user_id = auth.uid()
    AND a.role = 'admin'
    AND a.is_active = true
    AND a.account_status = 'active'
  LIMIT 1;

  IF v_admin_id IS NULL THEN
    RAISE EXCEPTION 'Only an active admin can change employee accounts.'
      USING ERRCODE = '42501'; -- insufficient_privilege
  END IF;

  SELECT *
    INTO v_target
  FROM public.employees e
  WHERE e.id = p_employee_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Employee not found.'
      USING ERRCODE = 'P0002'; -- no_data_found
  END IF;

  -- An admin never manages their own account here (no self-block, no
  -- self-delete) — that is what keeps the last administrator usable.
  IF v_target.id = v_admin_id THEN
    RAISE EXCEPTION 'You cannot change your own account status.'
      USING ERRCODE = '42501';
  END IF;

  -- Technicians only: administrator accounts are deliberately out of scope,
  -- so this function can never lock the system out of its admins.
  IF v_target.role IS DISTINCT FROM 'technician' THEN
    RAISE EXCEPTION 'Only technician accounts can be managed here.'
      USING ERRCODE = 'P0001';
  END IF;

  v_previous := COALESCE(v_target.account_status, 'active');

  IF v_previous = 'deleted' THEN
    IF p_status = 'deleted' THEN
      -- Idempotent replay of the same soft delete: nothing changes.
      RETURN QUERY
      SELECT
        e.id, e.name, e.email, e.employee_code, e.phone, e.role,
        e.is_active, e.account_status, e.blocked_at, e.deleted_at,
        (SELECT count(*) FROM public.jobs j WHERE j.assigned_employee_id = e.id),
        (SELECT count(*) FROM public.jobs j
          WHERE j.assigned_employee_id = e.id AND j.status = 'completed')
      FROM public.employees e
      WHERE e.id = p_employee_id;
      RETURN;
    END IF;

    RAISE EXCEPTION
      'A soft deleted technician cannot be reactivated or re-blocked.'
      USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.employees AS e
     SET account_status    = p_status,
         is_active         = (p_status = 'active'),
         blocked_at        = CASE
                               WHEN p_status = 'blocked' THEN now()
                               ELSE NULL
                             END,
         deleted_at        = CASE
                               WHEN p_status = 'deleted' THEN now()
                               ELSE NULL
                             END,
         status_changed_at = now(),
         status_changed_by = v_admin_id,
         updated_at        = now()
   WHERE e.id = p_employee_id;

  INSERT INTO public.admin_action_log (
    actor_employee_id, entity_type, entity_id, action,
    previous_status, new_status
  )
  VALUES (
    v_admin_id, 'employee', p_employee_id, p_status, v_previous, p_status
  );

  RETURN QUERY
  SELECT
    e.id, e.name, e.email, e.employee_code, e.phone, e.role,
    e.is_active, e.account_status, e.blocked_at, e.deleted_at,
    (SELECT count(*) FROM public.jobs j WHERE j.assigned_employee_id = e.id),
    (SELECT count(*) FROM public.jobs j
      WHERE j.assigned_employee_id = e.id AND j.status = 'completed')
  FROM public.employees e
  WHERE e.id = p_employee_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_set_employee_status(uuid, text) FROM public;
REVOKE ALL ON FUNCTION public.admin_set_employee_status(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_set_employee_status(uuid, text)
  TO authenticated;

-- ---------------------------------------------------------------------------
-- 5) customers — admin-managed account lifecycle (columns only)
-- ---------------------------------------------------------------------------
-- `customers` has no legacy `is_active` flag, so `account_status` is the only
-- state column here. A blocked customer is simply not selectable for a NEW
-- job (see `create_job` in section 7); the jobs that already reference the
-- customer keep their rows, their files, their signature and their history.
ALTER TABLE public.customers
  ADD COLUMN IF NOT EXISTS account_status text NOT NULL DEFAULT 'active';

ALTER TABLE public.customers
  ADD COLUMN IF NOT EXISTS blocked_at timestamptz;

ALTER TABLE public.customers
  ADD COLUMN IF NOT EXISTS deleted_at timestamptz;

ALTER TABLE public.customers
  ADD COLUMN IF NOT EXISTS status_changed_at timestamptz;

ALTER TABLE public.customers
  ADD COLUMN IF NOT EXISTS status_changed_by uuid;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'customers_status_changed_by_fkey'
      AND conrelid = 'public.customers'::regclass
  ) THEN
    ALTER TABLE public.customers
      ADD CONSTRAINT customers_status_changed_by_fkey
      FOREIGN KEY (status_changed_by) REFERENCES public.employees (id)
      ON DELETE SET NULL;
  END IF;
END;
$$;

ALTER TABLE public.customers
  DROP CONSTRAINT IF EXISTS customers_account_status_check;
ALTER TABLE public.customers
  ADD CONSTRAINT customers_account_status_check
  CHECK (account_status IN ('active', 'blocked', 'deleted'));

-- Existing customers keep working exactly as before.
UPDATE public.customers
   SET account_status = 'active'
 WHERE account_status IS NULL;

-- ---------------------------------------------------------------------------
-- 6) Customer management RPCs
-- ---------------------------------------------------------------------------

-- Shared shape of every customer-management RPC result.
-- (Kept identical across the four functions so the Flutter layer maps one
-- single row shape.)

-- 6a) admin_list_customers — the management list, with job counters and the
--     optional [p_search] filter (name / phone / e-mail / address / city).
CREATE OR REPLACE FUNCTION public.admin_list_customers(
  p_search text DEFAULT NULL
)
RETURNS TABLE (
  id             uuid,
  name           text,
  phone          text,
  email          text,
  address        text,
  city           text,
  postal_code    text,
  notes          text,
  account_status text,
  blocked_at     timestamptz,
  deleted_at     timestamptz,
  created_at     timestamptz,
  updated_at     timestamptz,
  jobs_count     bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_id uuid;
  v_search   text;
BEGIN
  SELECT a.id
    INTO v_admin_id
  FROM public.employees a
  WHERE a.auth_user_id = auth.uid()
    AND a.role = 'admin'
    AND a.is_active = true
    AND a.account_status = 'active'
  LIMIT 1;

  IF v_admin_id IS NULL THEN
    RAISE EXCEPTION 'Only an active admin can list customers.'
      USING ERRCODE = '42501';
  END IF;

  v_search := NULLIF(btrim(COALESCE(p_search, '')), '');

  RETURN QUERY
  SELECT
    c.id,
    c.name,
    c.phone,
    c.email,
    c.address,
    c.city,
    c.postal_code,
    c.notes,
    c.account_status,
    c.blocked_at,
    c.deleted_at,
    c.created_at,
    c.updated_at,
    (SELECT count(*) FROM public.jobs j WHERE j.customer_id = c.id)
  FROM public.customers c
  WHERE v_search IS NULL
     OR c.name ILIKE '%' || v_search || '%'
     OR COALESCE(c.phone, '') ILIKE '%' || v_search || '%'
     OR COALESCE(c.email, '') ILIKE '%' || v_search || '%'
     OR COALESCE(c.address, '') ILIKE '%' || v_search || '%'
     OR COALESCE(c.city, '') ILIKE '%' || v_search || '%'
  ORDER BY
    CASE c.account_status
      WHEN 'active'  THEN 0
      WHEN 'blocked' THEN 1
      ELSE 2
    END,
    c.name ASC NULLS LAST,
    c.id ASC;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_customers(text) FROM public;
REVOKE ALL ON FUNCTION public.admin_list_customers(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_list_customers(text) TO authenticated;

-- 6b) admin_create_customer — validated, server-timestamped insert.
--     (The app's offline-first create path is untouched and keeps working
--     through the existing `customers` insert policy; this RPC is the
--     management screen's online path.)
CREATE OR REPLACE FUNCTION public.admin_create_customer(
  p_name        text,
  p_address     text,
  p_phone       text DEFAULT NULL,
  p_email       text DEFAULT NULL,
  p_city        text DEFAULT NULL,
  p_postal_code text DEFAULT NULL,
  p_notes       text DEFAULT NULL
)
RETURNS TABLE (
  id             uuid,
  name           text,
  phone          text,
  email          text,
  address        text,
  city           text,
  postal_code    text,
  notes          text,
  account_status text,
  blocked_at     timestamptz,
  deleted_at     timestamptz,
  created_at     timestamptz,
  updated_at     timestamptz,
  jobs_count     bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
#variable_conflict use_column
DECLARE
  v_admin_id uuid;
  v_new_id   uuid := gen_random_uuid();
BEGIN
  SELECT a.id
    INTO v_admin_id
  FROM public.employees a
  WHERE a.auth_user_id = auth.uid()
    AND a.role = 'admin'
    AND a.is_active = true
    AND a.account_status = 'active'
  LIMIT 1;

  IF v_admin_id IS NULL THEN
    RAISE EXCEPTION 'Only an active admin can create customers.'
      USING ERRCODE = '42501';
  END IF;

  IF p_name IS NULL OR btrim(p_name) = '' THEN
    RAISE EXCEPTION 'A customer name is required.'
      USING ERRCODE = 'P0001';
  END IF;

  IF p_address IS NULL OR btrim(p_address) = '' THEN
    RAISE EXCEPTION 'A customer address is required.'
      USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.customers (
    id, name, phone, email, address, city, postal_code, notes,
    account_status, created_at, updated_at
  )
  VALUES (
    v_new_id,
    btrim(p_name),
    NULLIF(btrim(COALESCE(p_phone, '')), ''),
    NULLIF(btrim(COALESCE(p_email, '')), ''),
    btrim(p_address),
    NULLIF(btrim(COALESCE(p_city, '')), ''),
    NULLIF(btrim(COALESCE(p_postal_code, '')), ''),
    NULLIF(btrim(COALESCE(p_notes, '')), ''),
    'active',
    now(),
    now()
  );

  INSERT INTO public.admin_action_log (
    actor_employee_id, entity_type, entity_id, action,
    previous_status, new_status
  )
  VALUES (v_admin_id, 'customer', v_new_id, 'created', NULL, 'active');

  RETURN QUERY
  SELECT
    c.id, c.name, c.phone, c.email, c.address, c.city, c.postal_code,
    c.notes, c.account_status, c.blocked_at, c.deleted_at,
    c.created_at, c.updated_at,
    (SELECT count(*) FROM public.jobs j WHERE j.customer_id = c.id)
  FROM public.customers c
  WHERE c.id = v_new_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_create_customer(
  text, text, text, text, text, text, text
) FROM public;
REVOKE ALL ON FUNCTION public.admin_create_customer(
  text, text, text, text, text, text, text
) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_create_customer(
  text, text, text, text, text, text, text
) TO authenticated;

-- 6c) admin_update_customer — edits the master data only. Never the status
--     (that is `admin_set_customer_status`) and never a soft deleted row.
CREATE OR REPLACE FUNCTION public.admin_update_customer(
  p_customer_id uuid,
  p_name        text,
  p_address     text,
  p_phone       text DEFAULT NULL,
  p_email       text DEFAULT NULL,
  p_city        text DEFAULT NULL,
  p_postal_code text DEFAULT NULL,
  p_notes       text DEFAULT NULL
)
RETURNS TABLE (
  id             uuid,
  name           text,
  phone          text,
  email          text,
  address        text,
  city           text,
  postal_code    text,
  notes          text,
  account_status text,
  blocked_at     timestamptz,
  deleted_at     timestamptz,
  created_at     timestamptz,
  updated_at     timestamptz,
  jobs_count     bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
#variable_conflict use_column
DECLARE
  v_admin_id uuid;
  v_target   public.customers;
BEGIN
  SELECT a.id
    INTO v_admin_id
  FROM public.employees a
  WHERE a.auth_user_id = auth.uid()
    AND a.role = 'admin'
    AND a.is_active = true
    AND a.account_status = 'active'
  LIMIT 1;

  IF v_admin_id IS NULL THEN
    RAISE EXCEPTION 'Only an active admin can edit customers.'
      USING ERRCODE = '42501';
  END IF;

  SELECT *
    INTO v_target
  FROM public.customers c
  WHERE c.id = p_customer_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Customer not found.'
      USING ERRCODE = 'P0002';
  END IF;

  IF v_target.account_status = 'deleted' THEN
    RAISE EXCEPTION 'A soft deleted customer cannot be edited.'
      USING ERRCODE = 'P0001';
  END IF;

  IF p_name IS NULL OR btrim(p_name) = '' THEN
    RAISE EXCEPTION 'A customer name is required.'
      USING ERRCODE = 'P0001';
  END IF;

  IF p_address IS NULL OR btrim(p_address) = '' THEN
    RAISE EXCEPTION 'A customer address is required.'
      USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.customers AS c
     SET name       = btrim(p_name),
         address    = btrim(p_address),
         phone      = NULLIF(btrim(COALESCE(p_phone, '')), ''),
         email      = NULLIF(btrim(COALESCE(p_email, '')), ''),
         city       = NULLIF(btrim(COALESCE(p_city, '')), ''),
         postal_code= NULLIF(btrim(COALESCE(p_postal_code, '')), ''),
         notes      = NULLIF(btrim(COALESCE(p_notes, '')), ''),
         updated_at = now()
   WHERE c.id = p_customer_id;

  INSERT INTO public.admin_action_log (
    actor_employee_id, entity_type, entity_id, action,
    previous_status, new_status
  )
  VALUES (
    v_admin_id, 'customer', p_customer_id, 'updated',
    v_target.account_status, v_target.account_status
  );

  RETURN QUERY
  SELECT
    c.id, c.name, c.phone, c.email, c.address, c.city, c.postal_code,
    c.notes, c.account_status, c.blocked_at, c.deleted_at,
    c.created_at, c.updated_at,
    (SELECT count(*) FROM public.jobs j WHERE j.customer_id = c.id)
  FROM public.customers c
  WHERE c.id = p_customer_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_update_customer(
  uuid, text, text, text, text, text, text, text
) FROM public;
REVOKE ALL ON FUNCTION public.admin_update_customer(
  uuid, text, text, text, text, text, text, text
) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_update_customer(
  uuid, text, text, text, text, text, text, text
) TO authenticated;

-- 6d) admin_set_customer_status — block / unblock / soft delete.
--     Never a hard delete: the row stays, `jobs.customer_id` stays valid,
--     every historical job, photo and signature stays readable.
CREATE OR REPLACE FUNCTION public.admin_set_customer_status(
  p_customer_id uuid,
  p_status      text
)
RETURNS TABLE (
  id             uuid,
  name           text,
  phone          text,
  email          text,
  address        text,
  city           text,
  postal_code    text,
  notes          text,
  account_status text,
  blocked_at     timestamptz,
  deleted_at     timestamptz,
  created_at     timestamptz,
  updated_at     timestamptz,
  jobs_count     bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
#variable_conflict use_column
DECLARE
  v_admin_id uuid;
  v_target   public.customers;
  v_previous text;
BEGIN
  IF p_status IS NULL OR p_status NOT IN ('active', 'blocked', 'deleted') THEN
    RAISE EXCEPTION 'Unsupported account status.'
      USING ERRCODE = 'P0001';
  END IF;

  SELECT a.id
    INTO v_admin_id
  FROM public.employees a
  WHERE a.auth_user_id = auth.uid()
    AND a.role = 'admin'
    AND a.is_active = true
    AND a.account_status = 'active'
  LIMIT 1;

  IF v_admin_id IS NULL THEN
    RAISE EXCEPTION 'Only an active admin can change customer accounts.'
      USING ERRCODE = '42501';
  END IF;

  SELECT *
    INTO v_target
  FROM public.customers c
  WHERE c.id = p_customer_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Customer not found.'
      USING ERRCODE = 'P0002';
  END IF;

  v_previous := COALESCE(v_target.account_status, 'active');

  IF v_previous = 'deleted' THEN
    IF p_status = 'deleted' THEN
      -- Idempotent replay of the same soft delete.
      RETURN QUERY
      SELECT
        c.id, c.name, c.phone, c.email, c.address, c.city, c.postal_code,
        c.notes, c.account_status, c.blocked_at, c.deleted_at,
        c.created_at, c.updated_at,
        (SELECT count(*) FROM public.jobs j WHERE j.customer_id = c.id)
      FROM public.customers c
      WHERE c.id = p_customer_id;
      RETURN;
    END IF;

    RAISE EXCEPTION 'A soft deleted customer cannot be reactivated.'
      USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.customers AS c
     SET account_status    = p_status,
         blocked_at        = CASE
                               WHEN p_status = 'blocked' THEN now()
                               ELSE NULL
                             END,
         deleted_at        = CASE
                               WHEN p_status = 'deleted' THEN now()
                               ELSE NULL
                             END,
         status_changed_at = now(),
         status_changed_by = v_admin_id,
         updated_at        = now()
   WHERE c.id = p_customer_id;

  INSERT INTO public.admin_action_log (
    actor_employee_id, entity_type, entity_id, action,
    previous_status, new_status
  )
  VALUES (
    v_admin_id, 'customer', p_customer_id, p_status, v_previous, p_status
  );

  RETURN QUERY
  SELECT
    c.id, c.name, c.phone, c.email, c.address, c.city, c.postal_code,
    c.notes, c.account_status, c.blocked_at, c.deleted_at,
    c.created_at, c.updated_at,
    (SELECT count(*) FROM public.jobs j WHERE j.customer_id = c.id)
  FROM public.customers c
  WHERE c.id = p_customer_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_set_customer_status(uuid, text) FROM public;
REVOKE ALL ON FUNCTION public.admin_set_customer_status(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_set_customer_status(uuid, text)
  TO authenticated;

-- 6e) admin_unavailable_customer_ids — the ids of the customers that must NOT
--     be offered when creating a new job (blocked or soft deleted).
--     The admin Create Job screen uses it as the client-side filter; the
--     authoritative refusal stays inside `create_job` (section 7).
CREATE OR REPLACE FUNCTION public.admin_unavailable_customer_ids()
RETURNS SETOF uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_id uuid;
BEGIN
  SELECT a.id
    INTO v_admin_id
  FROM public.employees a
  WHERE a.auth_user_id = auth.uid()
    AND a.role = 'admin'
    AND a.is_active = true
    AND a.account_status = 'active'
  LIMIT 1;

  IF v_admin_id IS NULL THEN
    RAISE EXCEPTION 'Only an active admin can read customer availability.'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT c.id
  FROM public.customers c
  WHERE c.account_status <> 'active';
END;
$$;

REVOKE ALL ON FUNCTION public.admin_unavailable_customer_ids() FROM public;
REVOKE ALL ON FUNCTION public.admin_unavailable_customer_ids() FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_unavailable_customer_ids()
  TO authenticated;

-- ---------------------------------------------------------------------------
-- 7) create_job — same contract as job_workflow_permissions_setup.sql, PLUS:
--      * the customer must be ACTIVE (not blocked / not soft deleted) -> F0008
--      * the assignee must additionally be account_status = 'active'
--    Everything else (admin-only, server-generated job_number / status /
--    timestamps, append-only events, no client timestamp) is unchanged.
-- ---------------------------------------------------------------------------
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
      USING ERRCODE = '28000';
  END IF;

  -- 2) Caller must be an ACTIVE admin (and not blocked/deleted).
  SELECT e.id
    INTO v_admin_employee_id
  FROM public.employees e
  WHERE e.auth_user_id = auth.uid()
    AND e.role = 'admin'
    AND e.is_active = true
    AND e.account_status = 'active'
  LIMIT 1;

  IF v_admin_employee_id IS NULL THEN
    RAISE EXCEPTION 'Only an active admin can create jobs.'
      USING ERRCODE = '42501';
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
      USING ERRCODE = 'P0002';
  END IF;

  -- 4b) ... and must be ACTIVE. A blocked or soft deleted customer can never
  --     be attached to a new job, whatever the client sends. Existing jobs of
  --     that customer are untouched and stay readable.
  IF EXISTS (
    SELECT 1
    FROM public.customers c
    WHERE c.id = p_customer_id
      AND c.account_status <> 'active'
  ) THEN
    RAISE EXCEPTION 'This customer is blocked or deleted.'
      USING ERRCODE = 'F0008';
  END IF;

  -- 5) The assignee must be an ACTIVE TECHNICIAN (never an admin, never a
  --    blocked/deleted employee, never an unknown id).
  IF p_assigned_employee_id IS NULL
     OR NOT EXISTS (
       SELECT 1
       FROM public.employees t
       WHERE t.id = p_assigned_employee_id
         AND t.role = 'technician'
         AND t.is_active = true
         AND t.account_status = 'active'
     ) THEN
    RAISE EXCEPTION 'Only an active technician can be assigned to a job.'
      USING ERRCODE = 'P0001';
  END IF;

  -- 6) Insert the assigned job. `job_number` stays server-generated by the
  --    identity column; every timestamp is generated here.
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

  -- 7) Append-only history, attributed to the creating admin's employee row.
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

REVOKE ALL ON FUNCTION public.create_job(uuid, text, text, uuid) FROM public;
REVOKE ALL ON FUNCTION public.create_job(uuid, text, text, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_job(uuid, text, text, uuid)
  TO authenticated;

-- ---------------------------------------------------------------------------
-- 8) Defense in depth — RESTRICTIVE guards
-- ---------------------------------------------------------------------------
-- The existing permissive policies keep deciding WHO may see/write WHAT
-- (admin: all jobs, technician: own jobs, ...). The RESTRICTIVE policies below
-- can only ever REMOVE access: they require the caller to be an active,
-- non-blocked employee. A blocked or soft deleted technician therefore loses
-- table access *and* Storage access immediately, even though the JWT they
-- already hold stays cryptographically valid until it expires — and even if
-- another permissive policy was widened by accident later on.
--
-- SECURITY DEFINER RPCs run as the table owner and are unaffected: they keep
-- enforcing their own, narrower rules.
DROP POLICY IF EXISTS jobs_active_employee_required ON public.jobs;
CREATE POLICY jobs_active_employee_required
  ON public.jobs
  AS RESTRICTIVE
  FOR ALL
  TO authenticated
  USING (public.is_active_employee())
  WITH CHECK (public.is_active_employee());

DROP POLICY IF EXISTS job_files_active_employee_required ON public.job_files;
CREATE POLICY job_files_active_employee_required
  ON public.job_files
  AS RESTRICTIVE
  FOR ALL
  TO authenticated
  USING (public.is_active_employee())
  WITH CHECK (public.is_active_employee());

DROP POLICY IF EXISTS customers_active_employee_required ON public.customers;
CREATE POLICY customers_active_employee_required
  ON public.customers
  AS RESTRICTIVE
  FOR ALL
  TO authenticated
  USING (public.is_active_employee())
  WITH CHECK (public.is_active_employee());

-- Storage: the private `job-files` bucket is only reachable by an active,
-- non-blocked employee. `anon` can never reach that bucket at all; other
-- buckets are left to their own policies (`bucket_id <> 'job-files'`).
DROP POLICY IF EXISTS job_files_objects_active_employee_required
  ON storage.objects;
CREATE POLICY job_files_objects_active_employee_required
  ON storage.objects
  AS RESTRICTIVE
  FOR ALL
  TO authenticated, anon
  USING (bucket_id <> 'job-files' OR public.is_active_employee())
  WITH CHECK (bucket_id <> 'job-files' OR public.is_active_employee());

-- `job_events` is not part of the app's client-side read path today; the guard
-- is added only when the table already has RLS enabled, so this file never
-- changes the visibility of a table that is intentionally open.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'job_events'
      AND c.relrowsecurity
  ) THEN
    EXECUTE 'DROP POLICY IF EXISTS job_events_active_employee_required '
            'ON public.job_events';
    EXECUTE 'CREATE POLICY job_events_active_employee_required '
            'ON public.job_events AS RESTRICTIVE FOR ALL TO authenticated '
            'USING (public.is_active_employee()) '
            'WITH CHECK (public.is_active_employee())';
  END IF;
END;
$$;

COMMIT;

-- =============================================================================
-- Verification (run these in the Supabase SQL editor — read-only)
-- =============================================================================
-- 1) New columns and their invariants:
--    SELECT id, name, role, is_active, account_status, blocked_at, deleted_at
--    FROM public.employees ORDER BY account_status, name;
--
--    -- must return ZERO rows (status and flag are always consistent):
--    SELECT id FROM public.employees
--    WHERE (account_status = 'active') IS DISTINCT FROM (is_active IS TRUE);
--
-- 2) Policies in place (expect one RESTRICTIVE row per table + the Storage
--    guard):
--    SELECT schemaname, tablename, policyname, permissive, cmd, roles
--    FROM pg_policies
--    WHERE policyname IN (
--      'jobs_active_employee_required',
--      'job_files_active_employee_required',
--      'customers_active_employee_required',
--      'job_files_objects_active_employee_required',
--      'job_events_active_employee_required')
--    ORDER BY tablename;
--
-- 3) The management RPCs:
--    SELECT p.proname, pg_get_function_arguments(p.oid) AS args
--    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--    WHERE n.nspname = 'public'
--      AND p.proname LIKE 'admin\_%' ORDER BY p.proname;
--
-- 4) Blocking really blocks (replace the ids):
--    SELECT public.admin_set_employee_status('<technician employees.id>',
--                                            'blocked');
--    -- then, as that technician's session: any job_files/jobs read returns
--    -- zero rows and start_job / register_job_file raise 28000.
-- =============================================================================
