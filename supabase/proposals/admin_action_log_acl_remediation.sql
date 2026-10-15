-- REVIEW-ONLY proposal. Never execute against production without owner approval.
-- Purpose: remove direct non-owner privileges from this audit table that are
-- not required by its current policies or SECURITY DEFINER write path.
--
-- Verified live state on 2026-10-14:
--   owner: postgres
--   anon: TRUNCATE, REFERENCES, TRIGGER, MAINTAIN
--   authenticated: SELECT, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN
--   service_role: TRUNCATE, REFERENCES, TRIGGER, MAINTAIN
--   RLS: SELECT only for authenticated where public.is_active_admin()
-- Four SECURITY DEFINER audit-writing RPCs are owned by postgres. The table
-- owner and those RPCs retain their current ability to write the table.
--
-- DEFAULT PRIVILEGES NOTE:
-- postgres's current public-schema default ACL also grants TRUNCATE,
-- REFERENCES, TRIGGER, and MAINTAIN to anon/authenticated/service_role on
-- future tables it creates. This proposal intentionally leaves that broader
-- default alone because it affects every future public table. Review and
-- approve a separate default-ACL change after auditing all such tables/RPCs.

-- 1) READ-ONLY PREFLIGHT. Save the output for rollback and compare it with the
-- verified state above. This shows direct grants, effective privileges,
-- ownership, RLS policies, roles, and default privileges.
WITH target AS (
  SELECT c.oid, c.relowner, c.relacl
  FROM pg_class AS c
  JOIN pg_namespace AS n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname = 'admin_action_log'
)
SELECT
  'owner_and_direct_acl' AS section,
  jsonb_build_object(
    'owner', pg_get_userbyid(t.relowner),
    'acl', t.relacl::text,
    'expanded_acl', (
      SELECT jsonb_agg(jsonb_build_object(
        'grantee', COALESCE(grantee.rolname, 'PUBLIC'),
        'grantor', grantor.rolname,
        'privilege', x.privilege_type,
        'grantable', x.is_grantable
      ) ORDER BY COALESCE(grantee.rolname, 'PUBLIC'), x.privilege_type)
      FROM aclexplode(COALESCE(t.relacl, acldefault('r', t.relowner))) AS x
      LEFT JOIN pg_roles AS grantee ON grantee.oid = x.grantee
      LEFT JOIN pg_roles AS grantor ON grantor.oid = x.grantor
    )
  ) AS details
FROM target AS t
UNION ALL
SELECT
  'effective_privileges',
  jsonb_agg(jsonb_build_object(
    'role', r.rolname,
    'select', has_table_privilege(r.rolname, t.oid, 'SELECT'),
    'insert', has_table_privilege(r.rolname, t.oid, 'INSERT'),
    'update', has_table_privilege(r.rolname, t.oid, 'UPDATE'),
    'delete', has_table_privilege(r.rolname, t.oid, 'DELETE'),
    'truncate', has_table_privilege(r.rolname, t.oid, 'TRUNCATE'),
    'references', has_table_privilege(r.rolname, t.oid, 'REFERENCES'),
    'trigger', has_table_privilege(r.rolname, t.oid, 'TRIGGER'),
    'maintain', has_table_privilege(r.rolname, t.oid, 'MAINTAIN')
  ) ORDER BY r.rolname)
FROM target AS t
JOIN pg_roles AS r ON r.rolname IN
  ('anon', 'authenticated', 'service_role', 'postgres', 'authenticator')
UNION ALL
SELECT
  'rls_policies',
  COALESCE(jsonb_agg(jsonb_build_object(
    'name', policyname,
    'roles', roles,
    'command', cmd,
    'using', qual,
    'with_check', with_check
  ) ORDER BY policyname), '[]'::jsonb)
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'admin_action_log'
UNION ALL
SELECT
  'postgres_public_table_default_acl',
  COALESCE(jsonb_agg(jsonb_build_object(
    'owner', pg_get_userbyid(d.defaclrole),
    'object_type', d.defaclobjtype,
    'acl', d.defaclacl::text
  )), '[]'::jsonb)
FROM pg_default_acl AS d
LEFT JOIN pg_namespace AS n ON n.oid = d.defaclnamespace
WHERE pg_get_userbyid(d.defaclrole) = 'postgres'
  AND n.nspname = 'public'
  AND d.defaclobjtype = 'r';

-- 2) PROPOSED CHANGE. Only direct grants on this table are changed. Existing
-- table owner and SECURITY DEFINER functions remain able to write the audit.
REVOKE ALL PRIVILEGES ON TABLE public.admin_action_log FROM anon;
REVOKE ALL PRIVILEGES ON TABLE public.admin_action_log FROM authenticated;
REVOKE ALL PRIVILEGES ON TABLE public.admin_action_log FROM service_role;
GRANT SELECT ON TABLE public.admin_action_log TO authenticated;

-- 3) POST-CHANGE VERIFICATION. Expected:
-- anon: no listed table privilege; authenticated: SELECT only;
-- service_role: no listed table privilege; postgres remains owner.
SELECT
  r.rolname AS role,
  has_table_privilege(r.rolname, 'public.admin_action_log', 'SELECT') AS can_select,
  has_table_privilege(r.rolname, 'public.admin_action_log', 'INSERT') AS can_insert,
  has_table_privilege(r.rolname, 'public.admin_action_log', 'UPDATE') AS can_update,
  has_table_privilege(r.rolname, 'public.admin_action_log', 'DELETE') AS can_delete,
  has_table_privilege(r.rolname, 'public.admin_action_log', 'TRUNCATE') AS can_truncate,
  has_table_privilege(r.rolname, 'public.admin_action_log', 'REFERENCES') AS can_reference,
  has_table_privilege(r.rolname, 'public.admin_action_log', 'TRIGGER') AS can_create_trigger,
  has_table_privilege(r.rolname, 'public.admin_action_log', 'MAINTAIN') AS can_maintain
FROM pg_roles AS r
WHERE r.rolname IN ('anon', 'authenticated', 'service_role', 'postgres')
ORDER BY r.rolname;

SELECT policyname, roles, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'admin_action_log';

-- 4) ROLLBACK PLAN: if approved behavior fails, restore the exact verified
-- direct grants (all were non-GRANTABLE) and authenticated SELECT policy path.
-- This does not alter ownership, policies, or default privileges.
-- WARNING: the rollback deliberately restores TRUNCATE for anon,
-- authenticated, and service_role, allowing those roles to erase the audit
-- table again. Use only if the owner explicitly accepts that security risk.
-- REVOKE ALL PRIVILEGES ON TABLE public.admin_action_log FROM anon;
-- REVOKE ALL PRIVILEGES ON TABLE public.admin_action_log FROM authenticated;
-- REVOKE ALL PRIVILEGES ON TABLE public.admin_action_log FROM service_role;
-- GRANT TRUNCATE, REFERENCES, TRIGGER, MAINTAIN
--   ON TABLE public.admin_action_log TO anon;
-- GRANT SELECT, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN
--   ON TABLE public.admin_action_log TO authenticated;
-- GRANT TRUNCATE, REFERENCES, TRIGGER, MAINTAIN
--   ON TABLE public.admin_action_log TO service_role;
-- Then rerun the preflight/effective-privilege queries and confirm RLS remains
-- enabled with admin_action_log_select_admin unchanged.
