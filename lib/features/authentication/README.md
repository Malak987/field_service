# features/authentication

Login and session handling for the two roles of the system (admin, technician).

**Phase 3 status: structure only — nothing is implemented in this folder yet.**

## Layers

| Folder | Contents | May depend on |
|---|---|---|
| `domain/` | `User` / `Session` entities, the `AuthenticationRepository` contract, use cases (`SignIn`, `SignOut`, `RestoreSession`, `RefreshSession`) | Dart only, plus `core/errors` |
| `data/` | `AuthenticationRemoteDataSource` (backend later), `AuthenticationLocalDataSource` (cached session so a technician keeps working offline), DTO models, `AuthenticationRepositoryImpl` | `domain/`, `core/network`, `core/database`, `core/storage` |
| `presentation/` | `AuthenticationCubit` + its states, the login page, page-private widgets | `domain/` use cases only |

## Notes

- The session must be **cached locally**: an expired token with no signal must
  not lock a technician out of work already scheduled for today. Offline
  behaviour is defined with the sync phase, not here.
- Supabase is not referenced in this feature yet; it will be added behind
  `data/datasources/` so `domain/` never learns about it.
- Role-based navigation (admin vs. technician) is decided by the router in
  `lib/app/router/`, not by this feature.
