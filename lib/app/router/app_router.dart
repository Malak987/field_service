import 'package:field_service/app/router/app_routes.dart';
import 'package:field_service/app/router/pages/route_error_page.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
  import 'package:field_service/features/authentication/presentation/pages/auth_gate_page.dart';
/// Owns the application's [GoRouter].
///
/// Why routing lives in the application layer and not inside a feature:
/// authentication redirects, role-based shells (admin vs. technician) and deep
/// links all span several features, so they need one owner.
///
/// Phase 3 status: routes, deep-link paths and the not-found screen are wired;
/// authentication redirects are intentionally absent (see
/// [AppRoutes] for the paths reserved for later phases).
class AppRouter {
  /// Creates the router.
  ///
  /// [initialLocation] and [routes] are injectable so tests can boot the app at
  /// a specific location with a reduced route set.
  AppRouter({this.initialLocation = AppRoutes.root, List<RouteBase>? routes})
    : routes = routes ?? _applicationRoutes;

  /// Location the application starts at when no deep link is opened.
  final String initialLocation;

  /// The route table served by [router].
  final List<RouteBase> routes;

  /// Routes owned by the application shell.
  ///
  /// Feature routes are appended here (or nested under a shell route) as each
  /// feature is implemented, keeping the navigation graph in one auditable
  /// place:
  ///
  /// ```dart
  /// GoRoute(path: AppRoutes.login, builder: (context, state) => const LoginPage()),
  /// GoRoute(
  ///   path: AppRoutes.jobDetails,
  ///   builder: (context, state) => JobDetailsPage(jobId: state.pathParameters['id']!),
  /// ),
  /// ```
  static final List<RouteBase> _applicationRoutes = <RouteBase>[
    GoRoute(
      path: AppRoutes.root,
      name: 'root',
      builder: (BuildContext context, GoRouterState state) =>
      const AuthGatePage(),
    ),
  ];

  /// The configured router instance.
  ///
  /// Built lazily so the dependency graph can construct [AppRouter] without
  /// touching the widget layer.
  late final GoRouter router = GoRouter(
    initialLocation: initialLocation,
    routes: routes,
    errorBuilder: (BuildContext context, GoRouterState state) =>
        RouteErrorPage(location: state.uri.toString(), error: state.error),
  );
}
