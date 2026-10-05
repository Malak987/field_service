# `core` — offline-first foundation

This is the shared offline infrastructure that **Customers, Jobs, Job Events,
Photos and Customer Signatures** will be built on. It is deliberately
reusable: no feature logic lives here, and nothing in here knows about a
specific customer or job.

> Structure note: the offline layer follows the project's existing core
> layout instead of a single `core/offline/` folder:
>
> | Concern | Location |
> |---|---|
> | Local database (Drift) | `core/database/` |
> | Sync queue / engine | `core/sync/` |
> | Connectivity | `core/network/` |
> | File storage | `core/storage/` |
> | DI registration | `app/di/modules/offline_module.dart` |

## Architecture

```text
Presentation (pages, Cubits — read the local DB via repositories)
    ↓
Domain (entities, use cases — pure Dart, no DB types)
    ↓
Repository (writes locally, enqueues the change)
   ↙     ↘
Local    Remote
Drift    Supabase (authenticated client + RLS, via SyncOperationHandler)
   ↓
SyncManager  ← connectivity (online/offline)
   ↓
SyncQueue (Drift table, durable)
```

**The local database is the source of truth for the UI during normal
operation.** The UI never calls Supabase directly for local data: it reads
local rows, repositories write local rows and enqueue the change, and the
sync engine pushes when the internet is available.

## Local database (`core/database/`)

`AppDatabase` (Drift) owns the schema; `AppDatabaseFactory` decides how the
file is opened (platform path via `path_provider`, shared across isolates so
a future background sync worker can reuse the connection).

| Table | Purpose |
|---|---|
| `sync_queue` | Durable queue of local changes awaiting the backend |
| `customers` | Local mirror of the remote `customers` table |
| `jobs` | Local mirror of the remote `jobs` table |
| `job_events` | Append-only events (type + JSON payload) |
| `job_files` | File metadata (photos / signatures); bytes live on disk |

Migrations: schema versioning through `MigrationStrategy`. Upgrades only add
or extend — **the database is never deleted or recreated on a schema
change**; a technician's offline work must survive every app update.

### Local sync metadata (no backend schema change)

Every local entity row carries three **local-only** columns that never exist
on Supabase and never leave the device:

* `sync_status` — `pending` / `inProgress` / `synced` / `failed`
* `local_updated_at` — last local modification
* `last_synced_at` — last confirmed exchange with the backend

This is what keeps the Supabase schema untouched while still letting the UI
and the sync engine know a row's state.

## Sync queue (`core/sync/`)

`SyncQueue` (contract) / `DriftSyncQueue` (Drift implementation).

* One row = one logical change: `entity_type` + `entity_id` + `operation`
  (`create` / `update` / `delete` / `upload`) + JSON `payload`.
* Plain strings for types, operations and status → extensible without a
  destructive migration.
* Durable: every transition is a committed SQLite write; restarts, force
  closes and airplane mode cannot lose queued work.
* **Idempotent enqueue** on the operation id: a retried enqueue is a no-op.
* `nextPending()` is oldest-first **and dependency-aware**.
* `claimPending()` is a conditional write — exactly one run can take an
  operation (`pending → inProgress`), which is the duplicate-processing
  guard at the queue level.

### Retry behavior

* A failed attempt never removes the operation. It stays in the queue as
  `failed` with `attempt_count` incremented, `last_attempt_at` set and a
  **sanitised** `last_error` persisted (raw Supabase exceptions are mapped
  by `SyncErrorMapper` — never stored or shown raw).
* `SyncManager.retryFailedOperations()` requeues all failed operations
  (counters and history preserved) and runs — the "Try again" action.
* `SyncManager.start()` runs crash recovery first: operations left
  `inProgress` by a killed app become `pending` again, so nothing is stuck.
* If one operation fails, the run **continues with the remaining
  operations** — one bad record never blocks the queue.

### Dependency ordering

`sync_queue.depends_on` references another operation id. A dependent
operation is only handed to the backend once its parent is `synced`. This is
what keeps an offline-built chain consistent, e.g.:

```text
customer created  →  job created (depends on customer)
                 →  job event (depends on job)
                 →  job file / photo (depends on job)
                 →  signature (depends on job)
                 →  job completed (depends on job)
```

Repositories enqueue the parent before the child (the foreign key on
`depends_on` enforces the parent's existence in the queue). If a parent
fails, its children wait until the parent is retried and succeeds — no
"upload everything simultaneously" shortcuts.

### Idempotency

* Every entity id is a **client-generated uuid**, created locally before the
  backend has ever seen the record. The payload always carries that same id.
* Retries reuse the exact same operation row (same `id`, same `payload`) —
  no new id is generated per attempt.
* Remote handlers are contractually required to **upsert on the client id**,
  so an operation that succeeded remotely but wasn't marked `synced` locally
  (crash in between) is safe to retry without duplicating the logical
  record.

## Connectivity (`core/network/`)

* `NetworkInfo` — one question: *usable internet right now?* The
  `ConnectivityNetworkInfo` implementation combines `connectivity_plus`
  (is there a network interface?) with
  `internet_connection_checker_plus` (is external routing actually working?).
  **A connected router without internet is `offline`** — the sync engine
  would only produce confusing errors otherwise.
* `ConnectivityService` — turns that into a managed state stream: cached
  `current` state, broadcast `onStatusChanged` emitting only transitions
  (`online` / `offline`), idempotent `start()`. The `SyncManager` listens
  and triggers a run when the status becomes `online`.

The app never blocks startup on connectivity: the first probe runs in the
background and the default assumption is `offline` (safe: no push is
attempted before the first confirmation).

## Sync engine (`core/sync/sync_manager.dart`)

`SyncManager implements SyncProcessor` (`processPendingOperations`,
`retryFailedOperations`, `isSyncing`) plus:

* `start()` — crash recovery + connectivity subscription + initial flush if
  already online. Non-blocking.
* `onHealthChanged` / `currentHealth` — a `SyncHealth` snapshot
  (connectivity, in-flight run, pending/failed counts, last safe error).
* Pausing: when the internet disappears mid-run, the loop stops at the next
  checkpoint; an in-flight operation is either resolved or released back to
  `pending`. **The queue is never cleared.**
* Unhandled entity types fail loudly: the operation is marked `failed` with
  "No remote handler registered for entity type … yet." — never silently
  dropped, never fake-synced.

UI mechanism: `SyncStatusCubit` exposes `SyncHealth` whose
`displayStatus` derives the indicator state (`synced` / `syncing` /
`offline` / `pendingChanges` / `failed`). No feature should build its own
sync indicator.

## File storage (`core/storage/`)

* `FileStorage` — relative-path byte storage; the database persists the
  relative reference, the implementation owns the physical root.
* `AppFileStorage` — app-owned root (`<application documents>/files/`,
  injectable for tests), path-escape protection, idempotent delete.
* `LocalFileStorage` — registration layer for job files:
  * copies picked camera/gallery files **immediately** (OS temp paths are
    never relied upon),
  * stable uuid file id + deterministic storage path,
  * inserts the `job_files` row (`sync_status = pending`) and enqueues an
    `upload` operation,
  * `markUploaded()` (called by the future upload handler after the
    backend confirms) → `deleteAfterConfirmedUpload()`, which **refuses to
    delete an unsynced file** (the local copy is the only copy until the
    upload is confirmed).
  * multiple files per job of any kind — `before` / `after` / `signature` /
    `document` — there is no one-before/one-after assumption.

## Conflict strategy (intended ownership rules)

Not implemented as automatic resolution yet — documented so the future sync
handlers follow one rule set:

* **Customers**: only the **admin** role edits customers; technicians never
  do. Admin-originated customer writes are the authoritative direction.
* **Jobs**: the **admin** controls assignment, scheduling, editing and
  deletion; the **technician** performs execution steps (status transitions,
  notes, events, files, signature).
* Practical consequence for later push handlers: when a remote change and a
  local change could both apply, the ownership rules above decide the
  winner per field group (identity/assignment fields ← admin, execution
  fields ← technician). A simple per-field ownership policy is sufficient;
  no generic last-write-wins is used.

## Security

* Only the authenticated Supabase client (publishable key, existing RLS) is
  used for remote access. **No service-role key, no admin secrets, no RLS
  bypass** — synchronization goes through the same RLS-protected tables.
* A push denied by RLS surfaces as a persisted, user-safe failure
  ("The backend rules rejected this change (permission denied)."), never as
  a crash or a silent drop.

## Background behavior (current scope)

Synchronization runs when:

1. the app starts (`SyncManager.start()` in `main()`),
2. usable connectivity returns while the app is running (stream trigger),
3. a user explicitly triggers a run (`processPendingOperations` /
   `retryFailedOperations` — e.g. a future "Sync now" action).

True OS background execution (isolates / scheduled workers) is not promised
yet; the architecture allows it without rewriting: a background task opens
the same shared database connection (via `AppDatabaseFactory`) and calls
`processPendingOperations`.

## How Customers / Jobs integrate later (sketch)

```text
1. Feature repository writes the local row (Drift) and flips
   sync_status = pending, local_updated_at = now.
2. It enqueues a SyncOperation (client id in payload, dependsOn = parent op
   when referencing a locally-created entity).
3. It registers its SyncOperationHandler in the SyncHandlerRegistry:
   sl<SyncHandlerRegistry>().register(SyncEntityType.customer, ...);
4. The SyncManager picks the operation up (when online and unblocked) and
   the handler upserts into Supabase by client id; on success the handler
   also flips the local row to synced (last_synced_at = now).
```

No UI reads Supabase for this data — it reads the local tables.

## Testing

Unit tests live in `test/core/` and run without a Supabase project:

* `sync_operation_test.dart` — value-object semantics
* `drift_sync_queue_test.dart` — insertion, idempotent enqueue, ordering,
  claims, retries, dependency gating, failure persistence (in-memory Drift)
* `sync_manager_test.dart` — runs, retry/idempotency, dependency ordering,
  mid-run connectivity loss, auto-trigger on return, unhandled types,
  crash recovery, health transitions (fake handler + fake network)
* `sync_status_test.dart` — indicator state derivation (`displayStatus`)
  and the `SyncStatusCubit` wiring
* `connectivity_service_test.dart` — online/offline transitions,
  transition-only emission, probe-error survival, idempotent start
  (fake `NetworkInfo`)
* `local_file_storage_test.dart` / `app_file_storage_test.dart` — file
  registration, stable ids, delete safety, path resolution and
  escape protection

The production `ConnectivityNetworkInfo` (connectivity_plus +
internet_connection_checker_plus) is the seam that is faked in tests; the
"connected router ≠ internet" policy lives there and is verified on device.

Host tests that use an in-memory Drift database need the system `libsqlite3`
(standard for Drift on desktop; present on every dev machine with a normal
OS package set).
