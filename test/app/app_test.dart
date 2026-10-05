import 'dart:async';

import 'package:field_service/app/di/injection.dart';
import 'package:field_service/app/router/app_routes.dart';
import 'package:field_service/core/deep_linking/auth_deep_link_config.dart';
import 'package:field_service/features/admin/presentation/pages/admin_home_page.dart';
import 'package:field_service/features/authentication/domain/entities/auth_session_event.dart';
import 'package:field_service/features/authentication/presentation/cubit/authentication_cubit.dart';
import 'package:field_service/features/authentication/presentation/cubit/authentication_state.dart';
import 'package:field_service/features/authentication/presentation/pages/auth_gate_page.dart';
import 'package:field_service/features/authentication/presentation/pages/forgot_password_page.dart';
import 'package:field_service/features/authentication/presentation/pages/login_page.dart';
import 'package:field_service/features/authentication/presentation/pages/register_page.dart';
import 'package:field_service/features/authentication/presentation/pages/reset_password_page.dart';
import 'package:field_service/features/jobs/presentation/pages/jobs_page.dart';
import 'package:field_service/features/technician/presentation/pages/technician_home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_test_harness.dart';
import '../support/test_authentication_repository.dart';

void main() {
  late AppTestHarness app;

  setUp(() => app = AppTestHarness());
  tearDown(() => app.dispose());

  testWidgets('logged-out startup resolves through AuthGate to LoginPage', (
    tester,
  ) async {
    await app.configure();
    await app.pump(tester);
    expect(find.byType(AuthGatePage), findsOneWidget);
    expect(find.byType(LoginPage), findsOneWidget);
    expect(app.router.routeInformationProvider.value.uri.path, AppRoutes.root);
  });

  for (final user in [adminUser, technicianUser]) {
    final Type home = user.isAdmin ? AdminHomePage : TechnicianHomePage;
    final String alias = user.isAdmin ? AppRoutes.admin : AppRoutes.technician;
    for (final path in [AppRoutes.root, alias]) {
      testWidgets('${user.role} logout at $path clears session and leaves home', (
        tester,
      ) async {
        await app.configure(user: user, initialLocation: path);
        await app.pump(tester);
        expect(find.byType(home), findsOneWidget);
        final shared = sl<AuthenticationCubit>();
        expect(identical(shared, sl<AuthenticationCubit>()), isTrue);
        expect(
          tester.element(find.byType(home)).read<AuthenticationCubit>(),
          same(shared),
        );

        await tester.tap(find.byTooltip('Sign Out'));
        await tester.pumpAndSettle();
        expect(app.authentication.signOutCalls, 1);
        expect(app.authentication.currentUser, isNull);
        expect(shared.state.status, AuthenticationStatus.unauthenticated);
        expect(shared.state.user, isNull);
        expect(find.byType(AuthGatePage), findsOneWidget);
        expect(find.byType(LoginPage), findsOneWidget);
        expect(find.byType(home), findsNothing);
        expect(
          app.router.routeInformationProvider.value.uri.path,
          AppRoutes.root,
        );

        // Re-entering a protected URL (browser history/refresh) cannot restore
        // the old screen merely because the URL names the user's previous role.
        app.router.go(alias);
        await tester.pumpAndSettle();
        expect(find.byType(LoginPage), findsOneWidget);
        expect(find.byType(home), findsNothing);
      });
    }
  }

  for (final path in [
    AppRoutes.admin,
    AppRoutes.technician,
    AppRoutes.jobs,
    '/jobs/a-job',
    AppRoutes.customers,
    AppRoutes.customerCreate,
    '/customers/a-customer',
    '/customers/a-customer/edit',
  ]) {
    testWidgets('logged-out direct URL $path returns through the gate', (
      tester,
    ) async {
      await app.configure(initialLocation: path);
      await app.pump(tester);
      expect(find.byType(AuthGatePage), findsOneWidget);
      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.byType(AdminHomePage), findsNothing);
      expect(find.byType(TechnicianHomePage), findsNothing);
    });
  }

  testWidgets('role URL cannot select the wrong home', (tester) async {
    await app.configure(user: technicianUser, initialLocation: AppRoutes.admin);
    await app.pump(tester);
    expect(find.byType(TechnicianHomePage), findsOneWidget);
    expect(find.byType(AdminHomePage), findsNothing);
  });

  testWidgets('Jobs navigation and its logout use the same session', (
    tester,
  ) async {
    await app.configure(user: adminUser);
    await app.pump(tester);
    await tester.tap(find.text('View Jobs'));
    await tester.pumpAndSettle();
    expect(find.byType(JobsPage), findsOneWidget);
    await tester.tap(find.byTooltip('Sign Out'));
    await tester.pumpAndSettle();
    expect(app.authentication.signOutCalls, 1);
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byType(JobsPage), findsNothing);
  });

  testWidgets('out-of-band signedOut removes a protected Jobs route', (
    tester,
  ) async {
    await app.configure(user: adminUser);
    await app.pump(tester);
    app.router.go(AppRoutes.jobs);
    await tester.pumpAndSettle();
    app.authentication.currentUser = null;
    app.authentication.events.add(AuthSessionEvent.signedOut);
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
    expect(app.router.routeInformationProvider.value.uri.path, AppRoutes.root);
  });

  testWidgets('pending/failed logout is not presented as a successful logout', (
    tester,
  ) async {
    await app.configure(user: adminUser);
    await app.pump(tester);
    final pending = Completer<void>();
    app.authentication.pendingSignOut = pending;
    app.authentication.signOutError = StateError('test sign-out failure');
    await tester.tap(find.byTooltip('Sign Out'));
    await tester.pump();
    expect(find.byType(AdminHomePage), findsOneWidget);
    expect(find.byType(LoginPage), findsNothing);
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.logout_outlined),
          )
          .onPressed,
      isNull,
    );

    pending.complete();
    await tester.pumpAndSettle();
    expect(app.authentication.currentUser, adminUser);
    expect(find.byType(AdminHomePage), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.logout_outlined),
          )
          .onPressed,
      isNotNull,
    );

    app.authentication.signOutError = null;
    await tester.tap(find.byTooltip('Sign Out'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('form login uses the shared cubit and gate', (tester) async {
    await app.configure(initialLocation: AppRoutes.login);
    await app.pump(tester);
    await tester.enterText(find.byType(TextFormField).at(0), adminUser.email);
    await tester.enterText(find.byType(TextFormField).at(1), 'test-password');
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();
    expect(find.byType(AuthGatePage), findsOneWidget);
    expect(find.byType(AdminHomePage), findsOneWidget);
  });

  testWidgets('cold email-confirmation signedIn still resolves the employee', (
    tester,
  ) async {
    await app.configure();
    await app.pump(tester);
    app.authentication.currentUser = adminUser;
    app.authentication.events.add(AuthSessionEvent.signedIn);
    await tester.pumpAndSettle();
    expect(find.byType(AdminHomePage), findsOneWidget);
    expect(
      AuthDeepLinkConfig.isAuthCallbackUriPredicate(
        Uri.parse('fieldservice://auth-callback?code=confirmation-code'),
      ),
      isTrue,
    );
  });

  testWidgets('recovery event on a protected route keeps the reset flow', (
    tester,
  ) async {
    await app.configure(user: adminUser);
    await app.pump(tester);
    app.router.go(AppRoutes.jobs);
    await tester.pumpAndSettle();
    app.authentication.events.add(AuthSessionEvent.passwordRecovery);
    await tester.pumpAndSettle();
    expect(find.byType(ResetPasswordPage), findsOneWidget);
    expect(find.byType(JobsPage), findsNothing);
    expect(
      app.router.routeInformationProvider.value.uri.path,
      AppRoutes.resetPassword,
    );
    await sl<AuthenticationCubit>().updatePassword(
      newPassword: 'NewPassword1!',
    );
    await tester.pumpAndSettle();
    expect(find.byType(ResetPasswordPage), findsOneWidget);
    expect(
      sl<AuthenticationCubit>().state.status,
      AuthenticationStatus.passwordResetSuccess,
    );
    expect(app.authentication.currentUser, isNull);
  });

  for (final entry in {
    AppRoutes.register: RegisterPage,
    AppRoutes.forgotPassword: ForgotPasswordPage,
    AppRoutes.resetPassword: ResetPasswordPage,
  }.entries) {
    testWidgets('public auth route ${entry.key} stays accessible', (
      tester,
    ) async {
      await app.configure(initialLocation: entry.key);
      await app.pump(tester);
      expect(find.byType(entry.value), findsOneWidget);
    });
  }
}
