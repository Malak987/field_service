/// Every top-level route path of the application, declared in one place.
///
/// Navigation code must always reference these constants
/// (`context.go(AppRoutes.jobs)`) so a path is never duplicated as a literal.
///
/// The `:id` routes carry their placeholder here; callers build the concrete
/// location with `goNamed(...)`/`pushNamed(...)` and `pathParameters`, or
/// navigate via the static routes (`AppRoutes.customerCreate`) where no
/// parameter exists.
abstract final class AppRoutes {
  /// Application entry point. Always resolves through the authentication gate
  /// (`AuthGatePage`), which restores the Supabase-backed employee session and
  /// selects the destination.
  static const String root = '/';

  /// Authentication flow.
  static const String login = '/login';

  /// New employee registration (pending activation).
  static const String register = '/register';

  /// "Forgot password" — sends the recovery mail.
  static const String forgotPassword = '/forgot-password';

  /// Password reset form opened from the recovery deep link / after
  /// `passwordRecovery`.
  static const String resetPassword = '/reset-password';

  /// Admin area.
  static const String admin = '/admin';

  /// Technician area.
  static const String technician = '/technician';

  /// Jobs list.
  static const String jobs = '/jobs';

  /// Create & assign a new job — admin-only (the router refuses this route
  /// for non-admin roles; the `create_job` RPC re-enforces it server-side).
  /// Declared before [jobDetails] so the static segment wins over `:id`.
  static const String jobCreate = '/jobs/create';

  /// Job details; requires a `:id` path parameter.
  static const String jobDetails = '/jobs/:id';

  /// Customers list — admin-only (offline-first, local Drift source of
  /// truth). The router refuses this route (and every child route) for
  /// non-admin roles.
  static const String customers = '/customers';

  /// Single customer; requires a `:id` path parameter (the client-generated
  /// UUID of `customers.id`).
  static const String customerDetails = '/customers/:id';

  /// Create-customer form (admin only). Declared before [customerDetails] so
  /// the static segment always wins over the `:id` placeholder.
  static const String customerCreate = '/customers/create';

  /// Edit-customer form (admin only); requires a `:id` path parameter.
  static const String customerEdit = '/customers/:id/edit';
}
