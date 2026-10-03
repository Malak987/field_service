/// Every top-level route path of the application, declared in one place.
///
/// Navigation code must always reference these constants
/// (`context.go(AppRoutes.jobs)`) so a path is never duplicated as a literal.
///
/// Phase 3 status: only [root] is wired into the router. The remaining paths
/// are the ones announced for this project; they are declared now so that the
/// routes and their deep links are agreed on before the screens exist, and they
/// must not be navigated to until their phase implements them.
abstract final class AppRoutes {
  /// Application entry point (later: splash + the "where does this user go?"
  /// decision). Currently renders a development placeholder.
  static const String root = '/';

  /// Authentication flow. *(planned — not wired yet)*
  static const String login = '/login';

  /// Admin area. *(planned — not wired yet)*
  static const String admin = '/admin';

  /// Technician area. *(planned — not wired yet)*
  static const String technician = '/technician';

  /// Jobs list. *(planned — not wired yet)*
  static const String jobs = '/jobs';

  /// Job details; requires a `:id` path parameter.
  /// *(planned — not wired yet)*
  static const String jobDetails = '/jobs/:id';
}
