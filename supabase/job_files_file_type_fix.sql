-- =============================================================================
-- Field Service — job_files file_type CHECK constraint fix
-- =============================================================================
-- Problem (runtime-confirmed, code 23514):
--   Storage upload succeeds and `register_job_file` reaches Supabase, but the
--   INSERT into `public.job_files` fails with:
--     new row for relation "job_files" violates check constraint
--     "job_files_file_type_check"
--   `signature` registrations succeed while `before` and `after` are refused —
--   i.e. the LIVE constraint accepts a value set that does not match the app
--   contract. No setup file in this repository creates a CHECK constraint on
--   `job_files.file_type` (the repo DDL is `file_type text NOT NULL`, no
--   CHECK), so this constraint was created outside the repo and drifted.
--
-- Unified file-type contract (Flutter <-> register_job_file <-> job_files):
--   'before' | 'after' | 'signature'
--   Flutter sends exactly these three values and nothing else.
--
-- Fix — ONLY the CHECK constraint, nothing else:
--   Drop the drifted constraint (if present) and recreate it under the same
--   standard auto-generated name with exactly the contract values.
--   * Idempotent: safe to re-run (DROP IF EXISTS + fixed-name re-add).
--   * Transactional: all-or-nothing; if an existing row violated the new
--     constraint the whole script rolls back and nothing changes.
--
-- NOT changed here: `register_job_file` (all authorization, ownership,
-- in_progress, path-integrity, idempotency and event logic untouched),
-- RLS policies, the Storage bucket/object policies, table columns, any other
-- constraint, and any Flutter code.
-- =============================================================================

BEGIN;

ALTER TABLE public.job_files
  DROP CONSTRAINT IF EXISTS job_files_file_type_check;

ALTER TABLE public.job_files
  ADD CONSTRAINT job_files_file_type_check
  CHECK (file_type IN ('before', 'after', 'signature'));

COMMIT;

-- ---------------------------------------------------------------------------
-- Verify after running (in the SQL Editor):
--
-- 1) The constraint now has exactly the contract values (expect one row):
--    SELECT conname, pg_get_constraintdef(oid)
--    FROM pg_constraint
--    WHERE conrelid = 'public.job_files'::regclass AND contype = 'c';
--
-- 2) Retry one captured before photo from the app; then confirm the row and
--    its event exist:
--    SELECT id, file_type, storage_path, captured_at
--    FROM public.job_files
--    WHERE job_id = '9483a55b-1fd5-439c-a7ff-59781d2c1adc';
--    SELECT event_type, occurred_at FROM public.job_events
--    WHERE job_id = '9483a55b-1fd5-439c-a7ff-59781d2c1adc'
--    ORDER BY occurred_at;
-- ---------------------------------------------------------------------------
