/// Application-wide constants that do not depend on the build environment.
///
/// Environment-specific values (backend URL, anon keys, endpoints) do **not**
/// belong here; they will live in a dedicated environment configuration once
/// the backend integration phase starts.
abstract final class AppConstants {
  /// Human readable application name (window title, share sheets, logs).
  static const String appName = 'Field Service';

  /// Base file name of the local Drift database.
  ///
  /// Stored without extension because drift appends `.sqlite`. The concrete
  /// database class is added in a later phase.
  static const String databaseFileName = 'field_service';
}
