# features/employees

Staff records: technicians, team leads and admins, including who is available
to be assigned to a job.

**Phase 3 status: structure only — nothing is implemented in this folder yet.**

## Layers

| Folder | Contents | May depend on |
|---|---|---|
| `domain/` | `Employee` entity (id, name, role, phone, active flag), the `EmployeeRepository` contract, use cases (`GetEmployees`, `GetAssignableTechnicians`, `GetEmployeeById`) | Dart only, plus `core/errors` |
| `data/` | `EmployeeRemoteDataSource`, `EmployeeLocalDataSource` (cache for offline job assignment), DTO models with `fromJson`/`toJson`, `EmployeeRepositoryImpl` | `domain/`, `core/network`, `core/database` |
| `presentation/` | `EmployeesCubit` + states, employees list/detail pages, page-private widgets | `domain/` use cases only |

## Notes

- Employees are read-mostly data: cache-first reads with a background refresh,
  so assigning a job offline still works.
- Write operations (create/update/delete) follow the same offline-first rule as
  every other feature: local write first, then a `SyncOperation` on the queue.
- Money- or permission-related fields must not be modelled here until the
  backend schema exists.
