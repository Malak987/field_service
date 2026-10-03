# features/jobs

The core aggregate of the product: renovation, kitchen installation and
maintenance jobs — scheduling, assignment, status and site work.

**Phase 3 status: structure only — nothing is implemented in this folder yet.**

## Layers

| Folder | Contents | May depend on |
|---|---|---|
| `domain/` | `Job` entity (id, type, status, schedule, customer, assigned technician, address, notes), value objects such as `JobStatus` / `JobType`, the `JobRepository` contract, use cases (`GetJobs`, `GetJobById`, `GetTechnicianAgenda`, `CreateJob`, `UpdateJobStatus`, `AssignTechnician`) | Dart only, plus `core/errors` |
| `data/` | `JobRemoteDataSource`, `JobLocalDataSource`, DTO models, `JobRepositoryImpl` | `domain/`, `core/network`, `core/database`, `core/sync` |
| `presentation/` | `JobsCubit` / `JobDetailsCubit` + states, list and details pages, page-private widgets | `domain/` use cases only |

## Notes

- Status transitions are business rules: they belong to use cases in `domain/`,
  never to a widget or a Cubit.
- Every mutation is written locally first and enqueued as a `SyncOperation`
  (`core/sync`); the UI shows "pending sync" instead of blocking on the network.
- `Job` must not reference Drift rows or backend payloads: rows are mapped to the
  entity inside `data/`.
- Job files (photos, signatures) are a separate feature — `features/job_files` —
  so image handling never bloats this feature.
