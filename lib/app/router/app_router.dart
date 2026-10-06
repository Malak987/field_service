import 'package:field_service/app/router/app_routes.dart';
import 'package:field_service/app/router/pages/route_error_page.dart';
import 'package:field_service/features/authentication/presentation/cubit/authentication_cubit.dart';
import 'package:field_service/features/authentication/presentation/cubit/authentication_state.dart';
import 'package:field_service/features/authentication/presentation/pages/auth_gate_page.dart';
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
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// Owns the application's [GoRouter].
///
/// Why routing lives in the application layer and not inside a feature:
/// authentication redirects, role-based shells (admin vs. technician) and deep
/// links all span several features, so they need one owner.
///
/// Startup routing: `/` always builds [AuthGatePage]. The gate resolves the
/// destination from the shared [AuthenticationCubit], whose session and
/// employee role are restored through the authentication feature. The router
/// deliberately does not infer authentication from Supabase initialization;
/// **Supabase RLS remains the actual security boundary**.
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
          const AuthGatePage(),
    ),

    // --- Authentication ------------------------------------------------------
    GoRoute(
      path: AppRoutes.login,
      name: 'login',
      builder: (BuildContext context, GoRouterState state) => const LoginPage(),
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

    // Home URLs are aliases of the gate, not unguarded copies of the homes.
    // The employee role is resolved by AuthGatePage, never by the URL.
    // --- Role shells ----------------------------------------------------------
    GoRoute(
      path: AppRoutes.admin,
      name: 'admin',
      redirect: (BuildContext context, GoRouterState state) => AppRoutes.root,
    ),
    GoRoute(
      path: AppRoutes.technician,
      name: 'technician',
      redirect: (BuildContext context, GoRouterState state) => AppRoutes.root,
    ),

    // --- Jobs ------------------------------------------------------------------
    GoRoute(
      path: AppRoutes.jobs,
      name: 'jobs',
      builder: (BuildContext context, GoRouterState state) => const JobsPage(),
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

  /// FieldServiceApp refreshes this router on the shared cubit's session
  /// changes, including a Supabase signedOut event on a feature page.
  /// Redirect through the gate so it remains the owner of login/role selection.
  static String? _redirect(BuildContext context, GoRouterState route) {
    final AuthenticationState auth = context.read<AuthenticationCubit>().state;
    final String path = route.uri.path;

    // Recovery can arrive while any screen is open. Leave the recovery route
    // alone while it saves/signs out so its success/error feedback is preserved.
    if (auth.status == AuthenticationStatus.passwordRecovery) {
      return path == AppRoutes.resetPassword ? null : AppRoutes.resetPassword;
    }

    final bool isProtected =
        path == AppRoutes.admin ||
        path == AppRoutes.technician ||
        path == AppRoutes.jobs ||
        path.startsWith('${AppRoutes.jobs}/') ||
        path == AppRoutes.customers ||
        path.startsWith('${AppRoutes.customers}/');
    if (!isProtected) {
      // Keep login, registration, confirmation callbacks and recovery public.
      return null;
    }

    final user = auth.user;
    // A pending/failed sign-out retains the validated user until Supabase
    // actually ends the session. Never pretend a failed request logged out.
    if (user == null || !user.isActive || !user.hasValidRole) {
      return AppRoutes.root;
    }

    // Customers is an **admin-only** feature. Every `/customers` route — the
    // list, the details page and both forms — is refused for any non-admin
    // role *before* a page builds, so no customer data is ever loaded (no
    // `CustomersCubit`, no Drift read) for a technician. Hiding the button
    // alone would not survive a typed URL / deep link; this guard is the
    // in-app enforcement while Supabase RLS remains the security boundary.
    // Redirecting through the gate lands the technician on their dashboard.
    final bool isCustomersArea =
        path == AppRoutes.customers ||
        path.startsWith('${AppRoutes.customers}/');
    if (isCustomersArea && !user.isAdmin) {
      return AppRoutes.root;
    }

    return null;
  }

  /// The configured router instance.
  ///
  /// Built lazily so the dependency graph can construct [AppRouter] without
  /// touching the widget layer.
  late final GoRouter router = GoRouter(
    initialLocation: initialLocation,
    routes: routes,
    redirect: _redirect,
    errorBuilder: (BuildContext context, GoRouterState state) =>
        RouteErrorPage(location: state.uri.toString(), error: state.error),
  );
}
