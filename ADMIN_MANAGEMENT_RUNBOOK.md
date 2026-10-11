# Admin Management — apply-once runbook

Scope: the technician/customer management feature
(`supabase/admin_management_setup.sql` + the `lib/features/admin/` code).

Status of this document: prepared by the agent. **The migration has NOT been
applied to the live Supabase project** — this sandbox cannot reach
`*.supabase.co`, so the file was validated on a local PostgreSQL 16.2 instance
that had the ten existing `supabase/*.sql` files applied first (105/105 checks,
including a clean re-run for idempotency). Apply it once yourself and run the
verification below.

---

## 1. Preconditions

The file is a **superset** of two functions that must already exist, so it must
be applied *after* (all of these are already applied in the project):

1. `supabase/authentication_setup.sql`
2. `supabase/job_workflow_permissions_setup.sql` (it replaces `create_job` with
   the identical signature `(uuid, text, text, uuid) RETURNS SETOF public.jobs`,
   plus the blocked-customer check)
3. the job-file files (`before_photos_setup.sql`, `after_photos_setup.sql`,
   `signature_setup.sql`, `start_job_setup.sql`,
   `work_description_setup.sql`, `complete_job_setup.sql`,
   `job_customer_access_setup.sql`, `job_files_file_type_fix.sql`)

The file is a single transaction (`BEGIN … COMMIT`) with pre-flight `RAISE
EXCEPTION` guards: if anything is missing it aborts **and rolls back**, leaving
the database exactly as it was. Re-running it is safe (idempotent).

Optional pre-flight — run these two queries first; if the first one returns a
row, an earlier draft of this file already exists and you should tell me before
applying:

```sql
SELECT p.proname, pg_get_function_result(p.oid)
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname LIKE 'admin\_%';

SELECT column_name FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'employees'
  AND column_name IN ('account_status','deleted_at');
```

Both should return **zero rows** before the first application.

## 2. Apply once

Pick one:

* **Dashboard → SQL Editor**: paste the whole `supabase/admin_management_setup.sql`
  and Run. It ends with `COMMIT;`; a failure message means nothing was applied.
* **Supabase CLI**: copy the file to `supabase/migrations/<timestamp>_admin_management_setup.sql`
  and run `supabase db push`. (Do not re-run it through `db push` afterwards —
  it would just re-apply idempotently.)
* **psql / connection string**: `psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/admin_management_setup.sql`

Expected: no error output. If you see `Only ... not found — apply ... first`,
the named prerequisite file is missing.

## 3. Verify the schema (all queries are read-only)

```sql
-- 3.1 new lifecycle columns (employees: account_status NOT NULL DEFAULT 'active')
SELECT table_name, column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name IN ('employees','customers')
  AND column_name IN ('account_status','blocked_at','deleted_at',
                      'status_changed_at','status_changed_by')
ORDER BY table_name, column_name;
-- expect 10 rows (5 per table)

-- 3.2 constraints + the consistency trigger
SELECT conname, pg_get_constraintdef(oid) FROM pg_constraint
WHERE conname IN ('employees_account_status_check','customers_account_status_check',
                  'employees_status_changed_by_fkey','customers_status_changed_by_fkey');
SELECT tgname, tgrelid::regclass::text FROM pg_trigger
WHERE tgname = 'sync_employee_account_status';

-- 3.3 the seven management RPCs exist and only `authenticated` may execute them
SELECT p.proname,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_can_execute,
       has_function_privilege('anon',          p.oid, 'EXECUTE') AS anon_can_execute
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname LIKE 'admin\_%'
ORDER BY p.proname;
-- expect 7 rows: authenticated_can_execute = t, anon_can_execute = f

-- 3.4 the RESTRICTIVE guards (the server-side enforcement for stale sessions)
SELECT tablename, policyname, permissive, cmd, roles::text FROM pg_policies
WHERE policyname IN ('jobs_active_employee_required',
                     'job_files_active_employee_required',
                     'customers_active_employee_required',
                     'job_files_objects_active_employee_required',
                     'job_events_active_employee_required',
                     'admin_action_log_select_admin')
ORDER BY tablename, policyname;
-- expect the four table guards + the storage.objects guard as RESTRICTIVE,
-- and admin_action_log_select_admin as PERMISSIVE/SELECT

-- 3.5 audit table
SELECT to_regclass('public.admin_action_log') AS audit_table;  -- expect admin_action_log
```

## 4. Functional smoke test (server side)

The RPCs resolve the caller from `auth.uid()`, so the SQL editor (which runs as
`postgres`) cannot call them directly. Impersonate an active admin inside a
transaction that you roll back:

```sql
BEGIN;
SELECT set_config(
         'request.jwt.claims',
         json_build_object(
           'sub', (SELECT auth_user_id::text FROM public.employees
                    WHERE role = 'admin' AND is_active LIMIT 1),
           'role', 'authenticated')::text,
         true);
SET LOCAL role authenticated;

SELECT id, name, role, account_status, assigned_jobs, completed_jobs
FROM public.admin_list_employees();                       -- technicians + admins, real names
SELECT id, name, account_status, jobs_count FROM public.admin_list_customers(NULL);
SELECT count(*) AS unavailable_customers
FROM public.admin_unavailable_customer_ids();             -- blocked/deleted customers

ROLLBACK;   -- always roll back: this was only a read-only impersonation
```

Then, with a real technician account blocked through the app (section 5), the
strongest end-to-end check is *that technician's own session*: job lists, photos
and signatures must all come back empty, and starting/uploading/completing a job
must be refused — even though their JWT is still valid.

## 5. Functional smoke test (through the app)

1. Sign in as an admin → home shows the new section **Administration /
   Verwaltung** with **Manage Technicians** (إدارة الفنيين) and
   **Manage Customers** (إدارة العملاء).
2. Manage Technicians: the list shows every technician with the real name and
   the state; block one (dialog → Confirm) → the row flips to *Blocked* and the
   blocked technician's app can no longer open jobs, photos or signatures.
3. Unblock the same technician → the full flow works again.
4. Delete (logical): the row stays in the list as *Deleted* with its job
   counters, the technician cannot be reactivated, and their historical jobs,
   photos and signatures remain intact.
5. Manage Customers: add a customer, edit it, block it → then open *Create
   Job*: the blocked customer is not offered, and the server refuses it anyway
   (`create_job` → "This customer is blocked or deleted"). Unblock it → it is
   selectable again. Its old jobs remain readable.
6. A technician account must not see the management section, and typing
   `/admin/technicians` / `/admin/customers` must bounce to their home.

## 6. Local Flutter checks (no SDK in the agent sandbox)

```bash
flutter pub get
flutter analyze
flutter test                                        # whole suite
flutter test test/features/admin/                   # the new management scenarios
flutter test test/features/jobs/create_job_test.dart
```

The agent could not run these (no Flutter/Dart SDK available and no way to
download one), so the Dart code is *not* compile-checked yet. Send me any
analyzer/test output and I will fix it in the same feature.

## 7. Notes and contingencies

* **Rollback**: the migration is one transaction. A failure = nothing applied.
  There are no destructive statements; a successful run adds columns, functions,
  triggers, a log table and RESTRICTIVE policies, and replaces `create_job` and
  `is_active_admin()` with supersets of themselves.
* **`storage.objects` policy** (line ~1222): on Supabase this table is owned by
  the storage admin. Creating the policy from the SQL editor normally works; if
  you get `42501 insufficient privilege`, create the equivalent policy from
  **Dashboard → Storage → Policies** for the private `job-files` bucket with
  `USING (bucket_id <> 'job-files' OR public.is_active_employee())` and the same
  `WITH CHECK`, then re-run only that statement's `DROP/CREATE` block through the
  dashboard. The rest of the file is unaffected.
* **Existing behaviour is untouched**: the migration adds new policies only; the
  permissive policies of `jobs`, `job_files`, `customers`, `employees` and the
  private `job-files` bucket keep working exactly as today (the new guards can
  only ever subtract access). Registration/email confirmation still provisions
  one `technician` row (`role` from sign-up metadata is still ignored).
* **Open schema question (not changed on purpose)**: `before_photos_setup.sql`
  declares `job_files.file_name NOT NULL`, but `register_job_file()` inserts
  only `(id, job_id, file_type, storage_path, captured_at)`. Please run
  `\d public.job_files` (or `SELECT is_nullable FROM information_schema.columns
  WHERE table_name='job_files' AND column_name='file_name'`) and tell me the
  result; if it is `NO`, photo uploads need a one-line fix and I will propose it
  before touching anything.
* A customer deleted through the *existing* Customers screen (offline-first
  feature) still performs the legacy hard delete for customers without linked
  jobs, because that behaviour was already in the app and was explicitly left
  unchanged. The management screen always performs the logical delete.
