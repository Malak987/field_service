# features/authentication

Role-based authentication, registration, password recovery, and session handling for `admin` and `technician` users.

## Layers

| Folder | Contents | May depend on |
|---|---|---|
| `domain/` | `AppUser`, `AuthSessionEvent`, `AuthenticationRepository`, use cases (`SignIn`, `SignUp`, `SendPasswordResetEmail`, `UpdatePassword`, `GetCurrentUser`, `SignOut`, `WatchAuthStateChanges`) | Dart only |
| `data/` | `AuthenticationRemoteDataSource`, `AppUserModel`, `AuthenticationRepositoryImpl` | `domain/`, `core/network`, `supabase_flutter` |
| `presentation/` | `AuthenticationCubit`, `AuthenticationState`, `AuthenticationErrorMapper`, screens (`AuthGatePage`, `LoginPage`, `RegisterPage`, `ForgotPasswordPage`, `ResetPasswordPage`), and single-responsibility reusable widgets | `domain/` use cases, `core/` theme/localization/validators |
