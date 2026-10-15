// Retryable worker for the job_storage_cleanup_outbox contract.
// Not deployed or scheduled by this change. The request must pass the Edge
// gateway JWT check and a separate JOB_STORAGE_CLEANUP_SECRET header.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

type CleanupRow = {
  job_id: string;
  storage_prefix: string;
  attempts: number;
};

type StorageBucket = {
  list: (folder: string, options: {
    limit: number;
    offset: number;
    sortBy: { column: string; order: 'asc' | 'desc' };
  }) => Promise<{
    data: Array<{ id: string | null; name: string }> | null;
    error: unknown | null;
  }>;
  remove: (paths: string[]) => Promise<{ error: unknown | null }>;
};

const bucket = 'job-files';
const pageSize = 100;
const maxRounds = 4;
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function json(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8' },
  });
}

async function equalSecret(actual: string, expected: string): Promise<boolean> {
  const encoder = new TextEncoder();
  const [left, right] = await Promise.all([
    crypto.subtle.digest('SHA-256', encoder.encode(actual)),
    crypto.subtle.digest('SHA-256', encoder.encode(expected)),
  ]);
  const a = new Uint8Array(left);
  const b = new Uint8Array(right);
  let difference = 0;
  for (let index = 0; index < a.length; index++) difference |= a[index] ^ b[index];
  return difference === 0;
}

function expectedPrefix(jobId: string): string {
  return `jobs/${jobId}/`;
}

async function listPaths(
  storage: StorageBucket,
  folder: string,
  prefix: string,
): Promise<string[]> {
  const paths: string[] = [];
  for (let offset = 0; ; offset += pageSize) {
    const { data, error } = await storage.list(folder, {
      limit: pageSize,
      offset,
      sortBy: { column: 'name', order: 'asc' },
    });
    if (error) throw new Error('storage_list_failed');
    const entries = data ?? [];
    for (const entry of entries) {
      const path = `${folder}/${entry.name}`;
      if (!path.startsWith(prefix) || path.split('/').includes('..')) {
        throw new Error('storage_path_out_of_scope');
      }
      // Supabase Storage returns folders without an object id. Recurse; only
      // exact listed object paths are ever passed to remove().
      if (entry.id === null) paths.push(...await listPaths(storage, path, prefix));
      else paths.push(path);
    }
    if (entries.length < pageSize) break;
  }
  return paths;
}

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

  const expectedSecret = Deno.env.get('JOB_STORAGE_CLEANUP_SECRET');
  const suppliedSecret = request.headers.get('x-job-cleanup-secret') ?? '';
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const bearer = request.headers.get('authorization') ?? '';
  if (!expectedSecret || !suppliedSecret ||
      !serviceRoleKey ||
      !await equalSecret(suppliedSecret, expectedSecret) ||
      !await equalSecret(bearer, `Bearer ${serviceRoleKey}`)) {
    return json({ error: 'unauthorized' }, 401);
  }

  const url = Deno.env.get('SUPABASE_URL');
  if (!url) return json({ error: 'worker_not_configured' }, 503);

  const supabase = createClient(url, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  let lastJobId = '';
  let completed = 0;
  let retryable = 0;

  try {
    while (true) {
      let query = supabase.from('job_storage_cleanup_outbox')
        .select('job_id,storage_prefix,attempts')
        // Pending rows only (processed_at IS NULL), matching the SQL outbox
        // contract. Uploads for a deleted job are refused by the restrictive
        // Storage policy, so a processed prefix does not need revisiting.
        .is('processed_at', null)
        .order('job_id', { ascending: true })
        .limit(50);
      if (lastJobId) query = query.gt('job_id', lastJobId);
      const { data: rows, error } = await query;
      if (error) return json({ error: 'outbox_read_failed' }, 503);
      if (!rows?.length) break;

      for (const row of rows as CleanupRow[]) {
        lastJobId = row.job_id;
        const prefix = expectedPrefix(row.job_id);
        if (!uuidPattern.test(row.job_id) || row.storage_prefix !== prefix) {
          retryable++;
          await supabase.from('job_storage_cleanup_outbox').update({
            attempts: row.attempts + 1,
            last_error: 'invalid_outbox_scope',
          }).eq('job_id', row.job_id);
          continue;
        }

        const storage: StorageBucket = supabase.storage.from(bucket);
        try {
          for (let round = 0; round < maxRounds; round++) {
            const paths = await listPaths(storage, `jobs/${row.job_id}`, prefix);
            if (paths.length === 0) break;
            for (let offset = 0; offset < paths.length; offset += pageSize) {
              const batch = paths.slice(offset, offset + pageSize);
              if (batch.some((path) => !path.startsWith(prefix))) {
                throw new Error('storage_path_out_of_scope');
              }
              const { error: removeError } = await storage.remove(batch);
              if (removeError) throw new Error('storage_remove_failed');
            }
          }

          // Re-list after removals; processed_at is only set once the prefix
          // is empty. A failed row stays pending and is retried next run.
          const remaining = await listPaths(storage, `jobs/${row.job_id}`, prefix);
          if (remaining.length > 0) throw new Error('storage_prefix_not_empty');

          const { error: updateError } = await supabase
            .from('job_storage_cleanup_outbox')
            .update({
              attempts: row.attempts + 1,
              last_error: null,
              processed_at: new Date().toISOString(),
            })
            .eq('job_id', row.job_id);
          if (updateError) throw new Error('outbox_update_failed');
          completed++;
        } catch (error) {
          retryable++;
          const reason = error instanceof Error ? error.message : 'cleanup_failed';
          await supabase.from('job_storage_cleanup_outbox').update({
            attempts: row.attempts + 1,
            last_error: reason.slice(0, 80),
          }).eq('job_id', row.job_id);
        }
      }
      if (rows.length < 50) break;
    }
  } catch {
    return json({ error: 'cleanup_worker_failed' }, 503);
  }

  return json({ completed, retryable });
});
