import 'package:field_service/app/router/app_routes.dart';
import 'package:field_service/app/router/pages/app_root_page.dart';
import 'package:field_service/app/router/pages/route_error_page.dart';
import 'package:field_service/features/admin/presentation/pages/admin_home_page.dart';
import 'package:field_service/features/authentication/presentation/pages/forgot_password_page.dart';
import 'package:field_service/features/authentication/presentation/pages/login_page.dart';
import 'package:field_service/features/authentication/presentation/pages/register_page.dart';
import 'package:field_service/features/authentication/presentation/pages/reset_password_page.dart';
import 'package:field_service/features/customers/presentation/pages/create_customer_page.dart';
import 'package:field_service/features/customers/presentation/pages/customer_details_page.dart';
import 'package:field_service/features/customers/presentation/pages/customers_page.dart';
import 'package:field_service/features/customers/presentation/pages/edit_customer_page.dart';
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
///
/// Access protection: pages read the role from the [AuthenticationCubit]
/// provided above them by the auth gate (`AppUser.isAdmin`) and hide
/// not-permitted actions; **Supabase RLS is the actual security boundary**.
/// The router deliberately does not duplicate that role logic.
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
  /// place.
  static final List<RouteBase> _applicationRoutes = <RouteBase>[
    GoRoute(
      path: AppRoutes.root,
      name: 'root',
      builder: (BuildContext context, GoRouterState state) =>
          const AppRootPage(),
    ),

    // --- Authentication ------------------------------------------------------
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

    // --- Role shells ----------------------------------------------------------
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

    // --- Jobs ------------------------------------------------------------------
    GoRoute(
      path: AppRoutes.jobs,
      name: 'jobs',
      builder: (BuildContext context, GoRouterState state) =>
          const JobsPage(),
      routes: <RouteBase>[
        GoRoute(
          path: ':id',
          name: 'jobDetails',
          builder: (BuildContext context, GoRouterState state) =>
              JobDetailsPage(jobId: state.pathParameters['id']!),
        ),
      ],
    ),

    // --- Customers ---------------------------------------------------------------
    // `create` is declared before `:id` so the static segment always wins.
    GoRoute(
      path: AppRoutes.customers,
      name: 'customers',
      builder: (BuildContext context, GoRouterState state) =>
          const CustomersPage(),
      routes: <RouteBase>[
        GoRoute(
          path: 'create',
          name: 'customerCreate',
          builder: (BuildContext context, GoRouterState state) =>
              const CreateCustomerPage(),
        ),
        GoRoute(
          path: ':id',
          name: 'customerDetails',
          builder: (BuildContext context, GoRouterState state) =>
              CustomerDetailsPage(customerId: state.pathParameters['id']!),
          routes: <RouteBase>[
            GoRoute(
              path: 'edit',
              name: 'customerEdit',
              builder: (BuildContext context, GoRouterState state) =>
                  EditCustomerPage(customerId: state.pathParameters['id']!),
            ),
          ],
        ),
      ],
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
