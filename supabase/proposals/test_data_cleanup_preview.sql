-- Read-only cleanup scope preview. Replace the empty UUID array with explicit
-- verified test job ids only. No DELETE statements are included.
WITH target(job_id) AS (
  SELECT unnest(ARRAY[]::uuid[])
)
SELECT 'job' AS record_type, j.id::text AS record_id,
       j.created_at::text AS created_at, j.expires_at::text AS expires_at,
       j.status AS state, NULL::text AS storage_path
FROM public.jobs j JOIN target t ON t.job_id=j.id
UNION ALL
SELECT 'job_file', f.id::text, f.captured_at::text, NULL::text,
       f.file_type, f.storage_path
FROM public.job_files f JOIN target t ON t.job_id=f.job_id
UNION ALL
SELECT 'job_event', e.id::text, e.occurred_at::text, NULL::text,
       e.event_type, NULL::text
FROM public.job_events e JOIN target t ON t.job_id=e.job_id
ORDER BY record_type, record_id;

-- Exact Storage paths registered to the explicit target jobs:
WITH target(job_id) AS (SELECT unnest(ARRAY[]::uuid[]))
SELECT DISTINCT f.storage_path
FROM public.job_files f JOIN target t ON t.job_id=f.job_id
WHERE f.storage_path IS NOT NULL
ORDER BY f.storage_path;

-- Unmatched objects are shown separately and are NEVER included in a cleanup
-- scope merely because they are unmatched. Do not infer job ownership from
-- names that fail the known jobs/{uuid}/{type}/{file-id} shape.
SELECT o.name AS unmatched_storage_path
FROM storage.objects o
LEFT JOIN public.job_files f
  ON f.storage_path=o.name AND o.bucket_id='job-files'
WHERE o.bucket_id='job-files' AND f.id IS NULL
ORDER BY o.name;
