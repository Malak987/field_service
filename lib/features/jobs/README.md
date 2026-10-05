# features/jobs

The core aggregate of the product: renovation, kitchen installation and
maintenance jobs — assignment, status and (later) site work.

**Status: list + read-only details implemented (online, Supabase only).**
Offline sync, photos and signatures are out of scope for this phase.

## Layers

| Folder | Contents | May depend on |
|---|---|---|
| `domain/` | `Job` entity (1:1 with the real `public.jobs` columns), `JobStatus` value object (flexible free-string wrapper), the `JobsRepository` contract, use cases (`GetJobs`, `GetJobById`, `UpdateJobStatus`) | Dart only |
| `data/` | `JobsRemoteDataSource` + impl (the only place with Supabase queries), `JobModel` (row → entity mapping), `JobsRepositoryImpl` | `domain/`, Supabase client |
| `presentation/` | `JobsCubit` / `JobsState`, `JobsPage`, `JobDetailsPage`, reusable widgets (`JobsListItem`, `JobStatusBadge`, empty/error/loading states, `JobDetailField`), label + date mappers | `domain/` use cases (via DI) |

## Design notes

- **Visibility is Supabase RLS.** The same query runs for every role; RLS on
  `public.jobs` scopes technicians to their own assignments and admins see
  all jobs. There is no role branching in the data layer.
- **No invented columns.** `Job` maps exactly the real columns of
  `public.jobs`; customer / technician display names come from the
  `customers(name)` / `employees(name)` PostgREST embeds and are optional.
- **Free-text columns stay flexible.** `status` and `job_type` are plain
  `text` in the DB — `JobStatus` is a string wrapper and
  `JobLabelMapper` falls back to the raw value for unknown entries, so new
  backend values never break the UI.
- **Read-only details for now.** `JobDetailsPage` presents data only; the
  cubit already exposes `updateJobStatus()` for the upcoming
  completion workflow, but no UI triggers it yet.
- **Navigation** is GoRouter-only (`/jobs`, `/jobs/:id`); widgets never call
  `Navigator` directly.
