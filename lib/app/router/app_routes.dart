/// Every top-level route path of the application, declared in one place.
///
/// Navigation code must always reference these constants
/// (`context.go(AppRoutes.login)`) so a path is never duplicated as a literal.
abstract final class AppRoutes {
  /// Application entry point (`AuthGatePage`).
  static const String root = '/';

  /// Authentication routes.
  static const String login = '/login';
  static const String register = '/register';
  static const String forgotPassword = '/forgot-password';
  static const String resetPassword = '/reset-password';

  /// Web email-confirmation landing path.
  ///
  /// On the web the confirmation link returns to the app's own origin
  /// (`.../auth-callback`) so the Supabase client can read the code. The
  /// session is established by that time, so this route simply forwards to the
  /// auth gate. On mobile/desktop the equivalent callback is the
  /// `fieldservice://auth-callback` deep link and this route is never used.
  static const String authCallback = '/auth-callback';

  /// Role-based home routes.
  static const String admin = '/admin';
  static const String technician = '/technician';

  /// Jobs list for both roles (rows visible to the caller are scoped by RLS).
  static const String jobs = '/jobs';

  /// Job details; requires an `:id` path parameter.
  static const String jobDetails = '/jobs/:id';
}
