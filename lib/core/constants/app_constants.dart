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

  /// Whether unauthenticated users may self-register from the login screen.
  ///
  /// Registration always creates a *pending* employee account: activation and
  /// role assignment stay with an admin (`employees.is_active` /
  /// `employees.role`), so toggling this flag off only hides the sign-up
  /// entry points — it is not a security control (RLS is).
  static const bool allowSelfRegistration = true;

  /// Debounce applied to customer search input so list filtering does not
  /// re-run on every keystroke of a field technician on a slow device.
  static const Duration customerSearchDebounce = Duration(milliseconds: 250);
}
