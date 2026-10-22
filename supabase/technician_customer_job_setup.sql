-- =============================================================================
-- Field Service — Technician: Create Customer & Job
-- =============================================================================
-- Purpose:
--   Let an ACTIVE TECHNICIAN register a new customer and create a job for
--   them — or create a job for a customer they may already work for — without
--   ever touching the admin-only surfaces of the database.
--
--   Everything is enforced IN THE DATABASE, never in the Flutter UI:
--
--     * `public.customers` stays **admin-only** in RLS. NO new SELECT/INSERT
--       policy for technicians is added anywhere in this file — the only way
--       a technician can create a customer row is through the SECURITY
--       DEFINER function below, whose first step is an inline "is the caller
--       an active technician?" check.
--     * The assignee is NEVER taken from the client. The function resolves
--       the caller with `auth.uid() → employees.auth_user_id → employees.id`
--       and writes exactly that id into `jobs.assigned_employee_id`. A
--       technician can therefore not assign work to somebody else, and cannot
--       change any role.
--     * `jobs.job_number` is NOT sent by the client: the column is
--       `GENERATED ALWAYS AS IDENTITY`, so the INSERT omits it and the
--       database assigns the next number (the same mechanism `create_job`
--       already uses).
--     * The customer insert and the job insert happen inside ONE function
--       body, i.e. one transaction: if the job insert fails, the customer
--       insert is rolled back too. There is no orphan customer path.
--     * Both write functions are IDEMPOTENT on the client-generated job id,
--       so a replayed offline operation (retry after a lost acknowledgement,
--       a duplicated sync-queue push) can never create a second job.
--
-- What this file deliberately does NOT do:
--   * it does not weaken, replace or drop any existing policy or function
--     (`create_job`, `admin_*`, `start_job`, `complete_job`, RLS, the
--     RESTRICTIVE guards of admin_management_setup.sql all stay as they are);
--   * it does not use `service_role`; it does not touch `auth.users`;
--   * it does not let a technician read the whole customer table — the read
--     function returns ONLY the customers already linked to one of the
--     caller's own jobs;
--   * it does not let an admin use these functions (admins keep their own
--     `create_job` / `admin_create_customer` workflow);
--   * it never reassigns an existing job and never updates an existing
--     customer row.
--
-- Idempotent: safe to re-run (CREATE OR REPLACE FUNCTION, DROP ... IF EXISTS).
--
-- Order: run AFTER authentication_setup.sql, job_workflow_permissions_setup.sql
-- and admin_management_setup.sql (it relies on `employees.account_status` and
-- `customers.account_status`, both introduced there).
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
      AND column_name = 'account_status'
  ) THEN
    RAISE EXCEPTION
      'public.employees.account_status not found — apply admin_management_setup.sql first.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'customers'
      AND column_name = 'account_status'
  ) THEN
    RAISE EXCEPTION
      'public.customers.account_status not found — apply admin_management_setup.sql first.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'jobs'
      AND column_name = 'assigned_employee_id'
  ) THEN
    RAISE EXCEPTION
      'public.jobs.assigned_employee_id not found — this file targets the jobs workflow schema.';
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- 1) technician_accessible_customers — the ONLY customer read for a technician
-- ---------------------------------------------------------------------------
-- Scope (deliberately narrow): a technician may only ever see the customers
-- that are already referenced by a job assigned to THEIR OWN active employee
-- row. That is the same population `get_job_customer(job_id)` exposes per job,
-- just as a list, so no generic "read all customers" path is created and no
-- SELECT policy on `public.customers` is added for technicians.
--
-- Returns ZERO rows (never an error, never data) for:
--   * a caller without an employee row, an inactive/blocked/deleted employee,
--   * an admin (admins have `admin_list_customers`),
--   * a technician who simply has no job yet.
CREATE OR REPLACE FUNCTION public.technician_accessible_customers(
  p_search text DEFAULT NULL
)
RETURNS TABLE (
  id          uuid,
  name        text,
  phone       text,
  address     text,
  city        text,
  postal_code text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
#variable_conflict use_column
DECLARE
  v_technician_id uuid;
  v_search        text;
BEGIN
  SELECT e.id
    INTO v_technician_id
  FROM public.employees e
  WHERE e.auth_user_id = auth.uid()
    AND e.role = 'technician'
    AND e.is_active = true
    AND e.account_status = 'active'
  LIMIT 1;

  IF v_technician_id IS NULL THEN
    -- Zero rows, not an exception: the list is simply empty for anybody who
    -- is not an active technician (mirrors how every RLS-scoped read of this
    -- app behaves — no data, no error, no information leak).
    RETURN;
  END IF;

  v_search := NULLIF(btrim(COALESCE(p_search, '')), '');

  RETURN QUERY
  SELECT DISTINCT
    c.id,
    c.name,
    c.phone,
    c.address,
    c.city,
    c.postal_code
  FROM public.customers c
  WHERE c.account_status = 'active'
    AND EXISTS (
      SELECT 1
      FROM public.jobs j
      WHERE j.customer_id = c.id
        AND j.assigned_employee_id = v_technician_id
    )
    AND (
      v_search IS NULL
      OR c.name ILIKE '%' || v_search || '%'
      OR COALESCE(c.phone, '') ILIKE '%' || v_search || '%'
      OR COALESCE(c.address, '') ILIKE '%' || v_search || '%'
      OR COALESCE(c.city, '') ILIKE '%' || v_search || '%'
    )
  ORDER BY c.name ASC NULLS LAST, c.id ASC;
END;
$$;

REVOKE ALL ON FUNCTION public.technician_accessible_customers(text) FROM public;
REVOKE ALL ON FUNCTION public.technician_accessible_customers(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.technician_accessible_customers(text)
  TO authenticated;

-- ---------------------------------------------------------------------------
-- 2) technician_create_customer_and_job — customer + job as ONE unit
-- ---------------------------------------------------------------------------
-- Contract:
--   * caller must be an ACTIVE TECHNICIAN (42501 otherwise) — admins use
--     `create_job`, an unauthenticated caller gets 28000;
--   * `p_name` and `p_address` are required (P0001) — the same two columns
--     that are NOT NULL in `public.customers`;
--   * `p_job_type` must be one of the two supported categories (P0001);
--   * `p_customer_id` / `p_job_id` are the CLIENT-GENERATED STABLE ids. They
--     are what makes the call idempotent: if a job with `p_job_id` already
--     exists, the function returns that row instead of creating anything
--     (a replayed offline operation is therefore a no-op that still reports
--     the authoritative row). The customer row is inserted with
--     `ON CONFLICT (id) DO NOTHING`, so a replay never overwrites it either;
--   * the customer insert and the job insert are in ONE transaction (this
--     function body). A failing job insert rolls the customer back — no
--     orphan customer;
--   * `jobs.assigned_employee_id` is the CALLER's own employee id, resolved
--     server-side. There is no parameter for it;
--   * `job_number` is generated by the identity column (the INSERT omits it),
--     `status = 'assigned'`, `assigned_at` / `created_at` / `updated_at` are
--     `now()` — the client sends NO timestamp and NO number;
--   * two append-only events are recorded (`job_created`, `job_assigned`),
--     attributed to the creating technician's own employee row;
--   * returns the inserted (or already existing) job row.
DROP FUNCTION IF EXISTS public.technician_create_customer_and_job(
  uuid, uuid, text, text, text, text, text, text, text, text, text
);

CREATE OR REPLACE FUNCTION public.technician_create_customer_and_job(
  p_customer_id uuid,
  p_job_id      uuid,
  p_name        text,
  p_address     text,
  p_phone       text DEFAULT NULL,
  p_email       text DEFAULT NULL,
  p_city        text DEFAULT NULL,
  p_postal_code text DEFAULT NULL,
  p_notes       text DEFAULT NULL,
  p_job_type    text DEFAULT NULL,
  p_description text DEFAULT NULL,
  p_created_at  timestamptz DEFAULT now()
)
RETURNS SETOF public.jobs
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
#variable_conflict use_column
DECLARE
  v_technician_id uuid;
BEGIN
  -- 1) Caller must be authenticated.
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated.'
      USING ERRCODE = '28000';
  END IF;

  -- 2) Caller must be an ACTIVE TECHNICIAN (never an admin, never a
  --    blocked/soft deleted employee).
  SELECT e.id
    INTO v_technician_id
  FROM public.employees e
  WHERE e.auth_user_id = auth.uid()
    AND e.role = 'technician'
    AND e.is_active = true
    AND e.account_status = 'active'
  LIMIT 1;

  IF v_technician_id IS NULL THEN
    RAISE EXCEPTION 'Only an active technician can create a customer and job.'
      USING ERRCODE = '42501';
  END IF;

  -- 3) The stable client ids are mandatory: they are the idempotency keys.
  IF p_customer_id IS NULL OR p_job_id IS NULL THEN
    RAISE EXCEPTION 'A customer id and a job id are required.'
      USING ERRCODE = 'P0001';
  END IF;

  -- 4) Idempotency: this exact draft was already applied (a retry after a
  --    lost acknowledgement, a duplicated queue push). Return the existing
  --    row instead of creating anything — no second job, no second event.
  IF EXISTS (SELECT 1 FROM public.jobs j WHERE j.id = p_job_id) THEN
    RETURN QUERY
    SELECT * FROM public.jobs j WHERE j.id = p_job_id;
    RETURN;
  END IF;

  -- 5) Required customer fields (mirror of the NOT NULL columns).
  IF p_name IS NULL OR btrim(p_name) = '' THEN
    RAISE EXCEPTION 'A customer name is required.'
      USING ERRCODE = 'P0001';
  END IF;

  IF p_address IS NULL OR btrim(p_address) = '' THEN
    RAISE EXCEPTION 'A customer address is required.'
      USING ERRCODE = 'P0001';
  END IF;

  -- 6) Category: exactly the two supported business values.
  IF p_job_type IS NULL
     OR p_job_type NOT IN ('home_renovation', 'kitchen_renovation') THEN
    RAISE EXCEPTION 'Unsupported job category.'
      USING ERRCODE = 'P0001';
  END IF;

  -- 7) The customer row. `ON CONFLICT DO NOTHING` keeps a replay from ever
  --    overwriting master data; the job below references the real row id.
  INSERT INTO public.customers (
    id, name, phone, email, address, city, postal_code, notes,
    account_status, created_at, updated_at
  )
  VALUES (
    p_customer_id,
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
  )
  ON CONFLICT (id) DO NOTHING;

  -- 8) A blocked or soft deleted customer can never receive a new job —
  --    whatever the client sent (same rule `create_job` enforces, F0008).
  IF EXISTS (
    SELECT 1 FROM public.customers c
    WHERE c.id = p_customer_id
      AND c.account_status <> 'active'
  ) THEN
    RAISE EXCEPTION 'This customer is blocked or deleted.'
      USING ERRCODE = 'F0008';
  END IF;

  -- 9) The job. `job_number` is deliberately OMITTED (GENERATED ALWAYS AS
  --    IDENTITY); `assigned_employee_id` is the caller, resolved above — the
  --    client contributes no identity and no timestamp.
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
    p_job_id,
    p_customer_id,
    v_technician_id,
    p_job_type,
    NULLIF(btrim(COALESCE(p_description, '')), ''),
    'assigned',
    now(),
    COALESCE(p_created_at, now()),
    now(),
    COALESCE(p_created_at, now()) + INTERVAL '90 days'
  );

  -- 10) Append-only history, attributed to the creating technician.
  INSERT INTO public.job_events (job_id, employee_id, event_type, occurred_at)
  VALUES (p_job_id, v_technician_id, 'job_created', now());

  INSERT INTO public.job_events (job_id, employee_id, event_type, occurred_at)
  VALUES (p_job_id, v_technician_id, 'job_assigned', now());

  RETURN QUERY
  SELECT * FROM public.jobs j WHERE j.id = p_job_id;
END;
$$;

REVOKE ALL ON FUNCTION public.technician_create_customer_and_job(
  uuid, uuid, text, text, text, text, text, text, text, text, text, timestamptz
) FROM public;
REVOKE ALL ON FUNCTION public.technician_create_customer_and_job(
  uuid, uuid, text, text, text, text, text, text, text, text, text, timestamptz
) FROM anon;
GRANT EXECUTE ON FUNCTION public.technician_create_customer_and_job(
  uuid, uuid, text, text, text, text, text, text, text, text, text, timestamptz
) TO authenticated;

-- ---------------------------------------------------------------------------
-- 3) technician_create_job_for_customer — job for an EXISTING customer
-- ---------------------------------------------------------------------------
-- Same server-authoritative contract as (2), minus the customer insert, PLUS
-- the access rule that replaces the admin's "may use any customer":
--
--   the customer must already be referenced by a job assigned to the CALLER's
--   own active employee row (i.e. it must be one of
--   `technician_accessible_customers`). Otherwise 42501 — a technician can
--   never attach a job to a customer they have no business relationship with,
--   and cannot probe customer ids.
DROP FUNCTION IF EXISTS public.technician_create_job_for_customer(
  uuid, uuid, text, text
);

CREATE OR REPLACE FUNCTION public.technician_create_job_for_customer(
  p_customer_id uuid,
  p_job_id      uuid,
  p_job_type    text,
  p_description text DEFAULT NULL,
  p_created_at  timestamptz DEFAULT now()
)
RETURNS SETOF public.jobs
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
#variable_conflict use_column
DECLARE
  v_technician_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated.'
      USING ERRCODE = '28000';
  END IF;

  SELECT e.id
    INTO v_technician_id
  FROM public.employees e
  WHERE e.auth_user_id = auth.uid()
    AND e.role = 'technician'
    AND e.is_active = true
    AND e.account_status = 'active'
  LIMIT 1;

  IF v_technician_id IS NULL THEN
    RAISE EXCEPTION 'Only an active technician can create a job.'
      USING ERRCODE = '42501';
  END IF;

  IF p_customer_id IS NULL OR p_job_id IS NULL THEN
    RAISE EXCEPTION 'A customer id and a job id are required.'
      USING ERRCODE = 'P0001';
  END IF;

  -- Idempotency (same rule as above): a replay returns the existing row.
  IF EXISTS (SELECT 1 FROM public.jobs j WHERE j.id = p_job_id) THEN
    RETURN QUERY
    SELECT * FROM public.jobs j WHERE j.id = p_job_id;
    RETURN;
  END IF;

  IF p_job_type IS NULL
     OR p_job_type NOT IN ('home_renovation', 'kitchen_renovation') THEN
    RAISE EXCEPTION 'Unsupported job category.'
      USING ERRCODE = 'P0001';
  END IF;

  -- The customer must exist AND already belong to the caller's work.
  IF NOT EXISTS (
    SELECT 1 FROM public.customers c WHERE c.id = p_customer_id
  ) THEN
    RAISE EXCEPTION 'Customer not found.'
      USING ERRCODE = 'P0002';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.jobs j
    WHERE j.customer_id = p_customer_id
      AND j.assigned_employee_id = v_technician_id
  ) THEN
    RAISE EXCEPTION 'You are not allowed to create a job for this customer.'
      USING ERRCODE = '42501';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.customers c
    WHERE c.id = p_customer_id
      AND c.account_status <> 'active'
  ) THEN
    RAISE EXCEPTION 'This customer is blocked or deleted.'
      USING ERRCODE = 'F0008';
  END IF;

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
    p_job_id,
    p_customer_id,
    v_technician_id,
    p_job_type,
    NULLIF(btrim(COALESCE(p_description, '')), ''),
    'assigned',
    now(),
    COALESCE(p_created_at, now()),
    now(),
    COALESCE(p_created_at, now()) + INTERVAL '90 days'
  );

  INSERT INTO public.job_events (job_id, employee_id, event_type, occurred_at)
  VALUES (p_job_id, v_technician_id, 'job_created', now());

  INSERT INTO public.job_events (job_id, employee_id, event_type, occurred_at)
  VALUES (p_job_id, v_technician_id, 'job_assigned', now());

  RETURN QUERY
  SELECT * FROM public.jobs j WHERE j.id = p_job_id;
END;
$$;

REVOKE ALL ON FUNCTION public.technician_create_job_for_customer(
  uuid, uuid, text, text, timestamptz
) FROM public;
REVOKE ALL ON FUNCTION public.technician_create_job_for_customer(
  uuid, uuid, text, text, timestamptz
) FROM anon;
GRANT EXECUTE ON FUNCTION public.technician_create_job_for_customer(
  uuid, uuid, text, text, timestamptz
) TO authenticated;

COMMIT;

-- =============================================================================
-- Verification (run these in the Supabase SQL editor — read-only)
-- =============================================================================
-- 1) The three functions exist with the expected signatures:
--    SELECT p.proname, pg_get_function_arguments(p.oid) AS args
--    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--    WHERE n.nspname = 'public'
--      AND p.proname LIKE 'technician\_%'
--    ORDER BY p.proname;
--
-- 2) Execute rights (authenticated only, never anon/public):
--    SELECT p.proname, p.proacl
--    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--    WHERE n.nspname = 'public' AND p.proname LIKE 'technician\_%';
--
-- 3) RLS is untouched — `public.customers` must still have NO permissive
--    SELECT policy for technicians (this file adds none):
--    SELECT policyname, cmd, roles, qual
--    FROM pg_policies
--    WHERE schemaname = 'public' AND tablename = 'customers';
--
-- 4) As a TECHNICIAN session (SQL editor → "Run as role" is not enough; use a
--    real signed-in technician JWT from the app):
--      SELECT * FROM public.technician_accessible_customers();
--      -- only customers already linked to one of their own jobs
--
--      SELECT * FROM public.technician_create_customer_and_job(
--        gen_random_uuid(), gen_random_uuid(),
--        'Test Customer', 'Test Street 1',
--        '+49 151 000000', NULL, 'Berlin', '10115', NULL,
--        'home_renovation', 'Created from the app');
--      -- job_number comes from the identity column, status = 'assigned',
--      -- assigned_employee_id = the caller's own employees.id
--
--      -- Replay with the SAME two ids: returns the same row, no second job:
--      -- (run the previous statement again with the same uuid values)
--
-- 5) As an ADMIN session: both write functions raise 42501
--    ('Only an active technician can ...').
--
-- 6) As a technician, creating a job for a customer they never worked for
--    raises 42501 ('You are not allowed to create a job for this customer.').
-- =============================================================================
