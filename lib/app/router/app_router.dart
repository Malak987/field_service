import 'package:field_service/app/router/app_routes.dart';
import 'package:field_service/app/router/pages/route_error_page.dart';
import 'package:field_service/features/admin/presentation/pages/admin_home_page.dart';
import 'package:field_service/features/authentication/presentation/pages/auth_gate_page.dart';
import 'package:field_service/features/authentication/presentation/pages/forgot_password_page.dart';
import 'package:field_service/features/authentication/presentation/pages/login_page.dart';
import 'package:field_service/features/authentication/presentation/pages/register_page.dart';
import 'package:field_service/features/authentication/presentation/pages/reset_password_page.dart';
import 'package:field_service/features/jobs/presentation/pages/job_details_page.dart';
import 'package:field_service/features/jobs/presentation/pages/jobs_page.dart';
import 'package:field_service/features/technician/presentation/pages/technician_home_page.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Owns the application's [GoRouter].
///
/// Why routing lives in the application layer and not inside a feature:
/// authentication redirects, role-based shells (admin vs. technician) and deep
/// links all span several features, so they need one owner.
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
  static final List<RouteBase> _applicationRoutes = <RouteBase>[
    GoRoute(
      path: AppRoutes.root,
      name: 'root',
      builder: (BuildContext context, GoRouterState state) =>
          const AuthGatePage(),
    ),
    GoRoute(
      path: AppRoutes.login,
      name: 'login',
      builder: (BuildContext context, GoRouterState state) =>
          const LoginPage(),
    ),
    GoRoute(
      path: AppRoutes.register,
      name: 'register',
      builder: (BuildContext context, GoRouterState state) =>
          const RegisterPage(),
    ),
    GoRoute(
      path: AppRoutes.forgotPassword,
      name: 'forgotPassword',
      builder: (BuildContext context, GoRouterState state) =>
          const ForgotPasswordPage(),
    ),
    GoRoute(
      path: AppRoutes.resetPassword,
      name: 'resetPassword',
      builder: (BuildContext context, GoRouterState state) =>
          const ResetPasswordPage(),
    ),
    // Web email-confirmation landing path: the session is already established
    // by the time the browser lands here, so just forward to the auth gate.
    // (Mobile/desktop use the `fieldservice://auth-callback` deep link instead.)
    GoRoute(
      path: AppRoutes.authCallback,
      name: 'authCallback',
      redirect: (BuildContext context, GoRouterState state) => AppRoutes.root,
    ),
    GoRoute(
      path: AppRoutes.admin,
      name: 'admin',
      builder: (BuildContext context, GoRouterState state) =>
          const AdminHomePage(),
    ),
    GoRoute(
      path: AppRoutes.technician,
      name: 'technician',
      builder: (BuildContext context, GoRouterState state) =>
          const TechnicianHomePage(),
    ),
    GoRoute(
      path: AppRoutes.jobs,
      name: 'jobs',
      builder: (BuildContext context, GoRouterState state) => const JobsPage(),
    ),
    GoRoute(
      path: AppRoutes.jobDetails,
      name: 'jobDetails',
      builder: (BuildContext context, GoRouterState state) {
        final String? jobId = state.pathParameters['id'];
        if (jobId == null || jobId.isEmpty) {
          return RouteErrorPage(location: state.uri.toString());
        }
        return JobDetailsPage(jobId: jobId);
      },
    ),
  ];

  /// The configured router instance.
  late final GoRouter router = GoRouter(
    initialLocation: initialLocation,
    routes: routes,
    errorBuilder: (BuildContext context, GoRouterState state) =>
        RouteErrorPage(location: state.uri.toString(), error: state.error),
  );
}
