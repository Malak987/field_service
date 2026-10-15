-- REVIEW-ONLY, INDEPENDENT PROPOSAL. Do not execute without owner approval.
-- Scope: future tables created by role postgres in schema public only.
-- It does not modify existing tables or the broader supabase_admin defaults.
--
-- Verified default ACL for postgres/public tables currently grants
-- TRUNCATE, REFERENCES, TRIGGER and MAINTAIN to anon, authenticated and
-- service_role. These defaults are not inherited by admin_action_log after
-- creation; its current privileges are direct table grants. This proposal
-- prevents those four grants from being added to future postgres-created
-- public tables. Future application access should be granted explicitly per
-- table after enabling RLS and reviewing its policies.

-- READ-ONLY PREFLIGHT: record the postgres and supabase_admin table defaults.
SELECT
  pg_get_userbyid(d.defaclrole) AS owner_role,
  n.nspname AS schema_name,
  d.defaclobjtype AS object_type,
  d.defaclacl::text AS default_acl
FROM pg_default_acl AS d
LEFT JOIN pg_namespace AS n ON n.oid = d.defaclnamespace
WHERE n.nspname = 'public'
  AND d.defaclobjtype = 'r'
  AND pg_get_userbyid(d.defaclrole) IN ('postgres', 'supabase_admin')
ORDER BY owner_role;

-- PROPOSED CHANGE (postgres-created future public tables only):
-- ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
--   REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN
--   ON TABLES FROM anon, authenticated, service_role;

-- POST-CHANGE VERIFICATION: expected no listed privileges for the three
-- application roles in the postgres/public TABLES default ACL.
SELECT
  pg_get_userbyid(d.defaclrole) AS owner_role,
  x.grantee_role,
  x.privilege_type,
  x.is_grantable
FROM pg_default_acl AS d
JOIN pg_namespace AS n ON n.oid = d.defaclnamespace
CROSS JOIN LATERAL (
  SELECT r.rolname AS grantee_role, a.privilege_type, a.is_grantable
  FROM aclexplode(d.defaclacl) AS a
  JOIN pg_roles AS r ON r.oid = a.grantee
) AS x
WHERE n.nspname = 'public'
  AND d.defaclobjtype = 'r'
  AND pg_get_userbyid(d.defaclrole) = 'postgres'
  AND x.grantee_role IN ('anon', 'authenticated', 'service_role')
ORDER BY x.grantee_role, x.privilege_type;

-- ROLLBACK (restores only the verified four defaults; no default GRANT OPTION):
-- WARNING: this reintroduces powerful defaults on future postgres-created
-- public tables. Use only with explicit owner approval of that risk.
-- ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
--   GRANT TRUNCATE, REFERENCES, TRIGGER, MAINTAIN
--   ON TABLES TO anon, authenticated, service_role;
-- Re-run the preflight query and compare with the saved baseline.

-- Separate finding requiring a wider review: current schema-scoped defaults
-- for supabase_admin include all table privileges for these API roles. This
-- proposal does not alter them because the table-creation/migration role and
-- impact on future application tables have not been established. Review and
-- authorize a distinct least-privilege change before changing that owner ACL.
