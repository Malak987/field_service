-- =============================================================================
-- Field Service — Supabase Authentication & Employees RLS Setup
-- =============================================================================
-- Purpose:
--   1. Ensures an authenticated user can read their own row in `public.employees`
--      via `employees.auth_user_id = auth.uid()` (required during sign-in role
--      resolution).
--   2. Ensures administrators (`role = 'admin'` and `is_active = true`) can
--      read and manage employee records.
--   3. Prevents privilege escalation: clients can NEVER set or update `role` or
--      `is_active` on their own record.
--   4. Optional trigger `on_auth_user_created` that automatically provisions a
--      default `technician` record in `public.employees` when a new user signs
--      up via Supabase Auth (never `admin`).
-- =============================================================================

-- 1. Enable Row Level Security on `public.employees`
ALTER TABLE public.employees ENABLE ROW LEVEL SECURITY;

-- 2. Helper function (SECURITY DEFINER) to check if the current user is an
--    active administrator without triggering recursive RLS evaluation.
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
  );
$$;

-- 3. Policy: Any authenticated user can read their OWN employee profile
--    linked via `auth_user_id = auth.uid()`.
DROP POLICY IF EXISTS "employees_select_own" ON public.employees;
CREATE POLICY "employees_select_own"
  ON public.employees
  FOR SELECT
  TO authenticated
  USING (auth_user_id = auth.uid());

-- 4. Policy: Active admins can read all employee profiles.
DROP POLICY IF EXISTS "employees_select_admin" ON public.employees;
CREATE POLICY "employees_select_admin"
  ON public.employees
  FOR SELECT
  TO authenticated
  USING (public.is_active_admin());

-- 5. Policy: Only active admins can insert, update, or delete employee records
--    (prevents any regular user from escalating their role to 'admin').
DROP POLICY IF EXISTS "employees_Write_admin_only" ON public.employees;
CREATE POLICY "employees_write_admin_only"
  ON public.employees
  FOR ALL
  TO authenticated
  USING (public.is_active_admin())
  WITH CHECK (public.is_active_admin());

-- 6. Trigger function: Automatically link or create a default `technician`
--    employee row when a new Supabase Auth user registers.
--    Security:
--      * Hardcodes `role = 'technician'` (never reads `role` from user metadata).
--      * If an admin pre-created an employee row with matching email and null
--        `auth_user_id`, links `auth_user_id = NEW.id` while preserving the
--        admin-assigned role and `is_active` status.
CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_full_name text;
  v_existing_id uuid;
BEGIN
  v_full_name := COALESCE(
    NULLIF(TRIM(NEW.raw_user_meta_data ->> 'full_name'), ''),
    SPLIT_PART(NEW.email, '@', 1)
  );

  -- Check if an administrator already pre-registered this employee by email.
  SELECT id INTO v_existing_id
  FROM public.employees
  WHERE LOWER(email) = LOWER(NEW.email)
    AND auth_user_id IS NULL
  LIMIT 1;

  IF v_existing_id IS NOT NULL THEN
    UPDATE public.employees
    SET auth_user_id = NEW.id,
        name = COALESCE(NULLIF(name, ''), v_full_name),
        updated_at = NOW()
    WHERE id = v_existing_id;
  ELSE
    INSERT INTO public.employees (
      auth_user_id,
      employee_code,
      name,
      email,
      role,
      is_active
    )
    VALUES (
      NEW.id,
      'EMP-' || UPPER(SUBSTRING(REPLACE(NEW.id::text, '-', '') FROM 1 FOR 6)),
      v_full_name,
      NEW.email,
      'technician', -- Never 'admin'; only an admin can promote a user.
      true
    );
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_auth_user();
