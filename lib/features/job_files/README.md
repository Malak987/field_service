# features/job_files

Files attached to a job: before-work photos, after-work photos, customer
signatures and documents.

**Phase 3 status: structure only — nothing is implemented in this folder yet.**

## Layers

| Folder | Contents | May depend on |
|---|---|---|
| `domain/` | `JobFile` entity (id, job id, kind, relative path, mime type, size, created at, sync state), the `JobFileRepository` contract, use cases (`PickAndAttachPhoto`, `CaptureSignature`, `DeleteJobFile`, `GetJobFiles`) | Dart only, plus `core/errors` |
| `data/` | `JobFileRemoteDataSource` (upload/download), `JobFileLocalDataSource`, DTO models, `JobFileRepositoryImpl` | `domain/`, `core/storage`, `core/database`, `core/sync` |
| `presentation/` | `JobFilesCubit` + states, gallery/signature pages, page-private widgets | `domain/` use cases only |

## Notes

- Two storage systems, one rule: **bytes live on disk** behind
  `core/storage/FileStorage`, **metadata lives in the database** (the
  `job_files` table planned in `core/database`). The database never stores blobs.
- Only relative paths are persisted; absolute container paths change between
  installs and OS upgrades.
- Uploads are queued like every other offline change — a photo taken in a
  basement is uploaded when connectivity returns, not lost.
- `image_picker`, `path_provider` and `path` are already in `pubspec.yaml` for
  this feature; the camera/signature workflow itself is implemented in a later
  phase.
