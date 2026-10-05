/// Application-wide constants that do not depend on the build environment.
///
/// Environment-specific values (backend URL, anon keys, endpoints) do **not**
/// belong here; they live in `SupabaseConfig`.
abstract final class AppConstants {
  /// Human readable application name (window title, share sheets, logs).
  static const String appName = 'Field Service';

  /// Base file name of the local Drift database.
  ///
  /// Stored without extension because drift appends `.sqlite`. The concrete
  /// database class is added in a later phase.
  static const String databaseFileName = 'field_service';

  /// Controls whether the self-service employee registration link is shown on
  /// the login screen.
  ///
  /// Structured so that if employee creation is later restricted exclusively
  /// to the Admin Dashboard, self-registration can be disabled in one place
  /// while reusing the same `SignUp` domain use case.
  static const bool allowSelfRegistration = true;
}
