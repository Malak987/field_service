-- =============================================================================
-- Field Service — Per-Job Customer Access (SECURITY DEFINER RPC)
-- =============================================================================
-- Purpose:
--   `public.customers` stays **admin-only** in RLS (unchanged). Technicians
--   still need the contact/site details of the customer belonging to a job
--   assigned to them — nothing more. This function is the single, narrow
--   read path for that, so no SELECT policy for technicians is ever added
--   to `public.customers`.
--
-- Authorization chain enforced below:
--   auth.uid() → employees.auth_user_id → employees.id
--              → jobs.assigned_employee_id → jobs.customer_id → customer row
--
-- Security properties:
--   * SECURITY DEFINER + fixed `search_path`: the body runs as the function
--     owner, so it is immune to caller-controlled search_path tricks; RLS is
--     intentionally replaced *inside this function only* by the explicit
--     ownership check in the WHERE clause (admins pass via the existing
--     `is_active_admin()` helper, which is itself SECURITY DEFINER).
--   * Takes a **job id**, never a customer id: there is no generic
--     "get customer by id" path. A caller can only ever receive the customer
--     of a job they are allowed to work.
--   * Inactive employees get nothing: the employee row must have
--     `is_active = true`, and the admin path reuses `is_active_admin()`
--     (which also requires `is_active = true`).
--   * Returns **zero rows** (never an error, never data) when:
--       - the job does not exist,
--       - the job is assigned to somebody else (another technician),
--       - the job is unassigned and the caller is not an active admin,
--       - the caller has no employee row / is inactive.
--   * Returns only the five fields Job Details needs; nothing else from
--     `customers` is ever exposed through this function.
--
-- Usage from the app (both roles, same call):
--   select * from get_job_customer('<job uuid>');
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_job_customer(p_job_id uuid)
RETURNS TABLE (
  name        text,
  phone       text,
  address     text,
  city        text,
  postal_code text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT c.name,
         c.phone,
         c.address,
         c.city,
         c.postal_code
  FROM public.jobs j
  JOIN public.customers c ON c.id = j.customer_id
  WHERE j.id = p_job_id
    AND (
      -- Admins may see the customer of any job (they can already read
      -- `public.customers` directly; this keeps Job Details on one path).
      public.is_active_admin()
      OR
      -- Technicians only for jobs assigned to THEIR OWN active employee row.
      j.assigned_employee_id IN (
        SELECT e.id
        FROM public.employees e
        WHERE e.auth_user_id = auth.uid()
          AND e.is_active = true
      )
    );
$$;

-- Executable by signed-in users only; `anon` and the implicit `public` role
-- get nothing.
REVOKE ALL ON FUNCTION public.get_job_customer(uuid) FROM public;
REVOKE ALL ON FUNCTION public.get_job_customer(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_job_customer(uuid) TO authenticated;
