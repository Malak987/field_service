# features/sync

The user-facing side of synchronisation: sync status, pending changes, retries
and conflict resolution screens.

**Phase 3 status: structure only — nothing is implemented in this folder yet.**

## Layers

| Folder | Contents | May depend on |
|---|---|---|
| `domain/` | `SyncSummary` / conflict entities, the `SyncStatusRepository` contract, use cases (`WatchSyncStatus`, `TriggerManualSync`, `ResolveConflict`) | Dart only, plus `core/errors`, `core/sync` |
| `data/` | implementations that read the queue state out of the local database and delegate driving to `core/sync/SyncProcessor` | `domain/`, `core/database`, `core/sync` |
| `presentation/` | `SyncStatusCubit` + states, the sync status page/sheet and the reusable "pending changes" badge | `domain/` use cases only |

## Division of responsibility with `core/sync`

`core/sync` owns the **primitives** every feature needs:

- `SyncOperation` — the queued unit of work
- `SyncQueue` — durable, ordered storage contract for pending changes
- `SyncProcessor` — the engine contract that pushes the queue

This feature owns the **user experience and orchestration around them**: showing
what is waiting, letting the technician force a sync or retry, and explaining a
rejected change. Business rules of individual aggregates stay in their own
feature; this one never edits a job or a customer directly.
