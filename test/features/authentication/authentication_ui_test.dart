import 'dart:async';

import 'package:field_service/app/router/app_routes.dart';
import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/locale_cubit.dart';
import 'package:field_service/core/theme/app_colors.dart';
import 'package:field_service/features/admin/presentation/pages/admin_home_page.dart';
import 'package:field_service/features/authentication/domain/entities/app_user.dart';
import 'package:field_service/features/authentication/presentation/pages/forgot_password_page.dart';
import 'package:field_service/features/authentication/presentation/pages/login_page.dart';
import 'package:field_service/features/authentication/presentation/pages/register_page.dart';
import 'package:field_service/features/authentication/presentation/widgets/auth_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_test_harness.dart';
import '../../support/test_authentication_repository.dart';

/// Phase 2 — Authentication UI redesign.
///
/// Covers the redesigned visual system: brand logo asset, greeting hierarchy,
/// premium inputs, burgundy CTA (incl. its loading state), EN/DE localization,
/// small-screen fit and the single fixed brand theme.
void main() {
  late AppTestHarness app;

  setUp(() => app = AppTestHarness());
  tearDown(() => app.dispose());

  Finder logoImage() => find.byWidgetPredicate(
    (Widget widget) =>
        widget is Image &&
        widget.image is AssetImage &&
        (widget.image as AssetImage).assetName == AuthLogo.assetName,
  );

  Color renderedButtonColor(WidgetTester tester) {
    final Material material = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(FilledButton),
            matching: find.byType(Material),
          )
          .first,
    );
    return material.color!;
  }

  group('login screen', () {
    testWidgets('renders the redesigned brand layout', (tester) async {
      await app.configure(initialLocation: AppRoutes.login);
      await app.pump(tester);

      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.byType(AuthLogo), findsOneWidget);
      expect(logoImage(), findsOneWidget);
      expect(find.text('Welcome back'), findsOneWidget);
      expect(
        find.text('Sign in to continue to your workspace.'),
        findsOneWidget,
      );
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Forgot Password?'), findsOneWidget);
      expect(find.text('Sign In'), findsOneWidget);
      expect(find.text('Need an employee account?'), findsOneWidget);
      expect(find.text('Register'), findsOneWidget);
    });

    testWidgets('primary CTA uses the burgundy brand colour on white', (
      tester,
    ) async {
      await app.configure(initialLocation: AppRoutes.login);
      await app.pump(tester);

      expect(renderedButtonColor(tester), AppColors.primary);
    });

    testWidgets('shows inline validation errors for an empty submit', (
      tester,
    ) async {
      await app.configure(initialLocation: AppRoutes.login);
      await app.pump(tester);

      await tester.ensureVisible(find.text('Sign In'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign In'));
      await tester.pump();

      expect(find.text('Email address is required.'), findsOneWidget);
      expect(find.text('Password is required.'), findsOneWidget);
      expect(app.authentication.signInCalls, 0);
    });

    testWidgets('password visibility toggle shows and hides the password', (
      tester,
    ) async {
      await app.configure(initialLocation: AppRoutes.login);
      await app.pump(tester);

      await tester.enterText(find.byType(TextFormField).at(1), 'secret123');
      await tester.pump();

      EditableText editableText() =>
          tester.widget<EditableText>(find.byType(EditableText).at(1));
      expect(editableText().obscureText, isTrue);

      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pump();
      expect(editableText().obscureText, isFalse);
      expect(find.byTooltip('Hide password'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.visibility_off_outlined));
      await tester.pump();
      expect(editableText().obscureText, isTrue);
      expect(find.byTooltip('Show password'), findsOneWidget);
    });

    testWidgets('loading CTA keeps its size, shows progress and blocks '
        'duplicate submissions', (tester) async {
      final Completer<AppUser> pending = Completer<AppUser>();
      await app.configure(initialLocation: AppRoutes.login);
      app.authentication.pendingSignIn = pending.future;
      await app.pump(tester);

      final double buttonHeightBefore = tester
          .getSize(find.byType(FilledButton))
          .height;

      await tester.enterText(find.byType(TextFormField).at(0), adminUser.email);
      await tester.enterText(find.byType(TextFormField).at(1), 'secret123');
      await tester.ensureVisible(find.text('Sign In'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign In'));
      await tester.pump(const Duration(milliseconds: 250));

      // Disabled, with a progress indicator, and exactly the same height.
      expect(app.authentication.signInCalls, 1);
      final FilledButton loadingButton = tester.widget<FilledButton>(
        find.byType(FilledButton),
      );
      expect(loadingButton.onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        tester.getSize(find.byType(FilledButton)).height,
        buttonHeightBefore,
      );

      // A second tap cannot pass through the disabled button.
      await tester.tap(find.byType(FilledButton), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 100));
      expect(app.authentication.signInCalls, 1);

      pending.complete(adminUser);
      await tester.pumpAndSettle();
      expect(find.byType(AdminHomePage), findsOneWidget);
    });

    testWidgets('renders the localized German layout', (tester) async {
      await app.configure(initialLocation: AppRoutes.login);
      await app.pump(tester);

      final BuildContext context = tester.element(find.byType(LoginPage));
      // The LocaleCubit outlives this test (app-scoped singleton) — always
      // restore English so neighbouring tests keep their expected strings.
      final LocaleCubit cubit = context.read<LocaleCubit>();
      addTearDown(() {
        if (!cubit.isClosed) {
          cubit.emit(const Locale('en'));
        }
      });
      cubit.emit(const Locale('de'));
      await tester.pumpAndSettle();

      expect(find.text('Willkommen zurück'), findsOneWidget);
      expect(
        find.text(
          'Melden Sie sich an, um in Ihrem Arbeitsbereich weiterzuarbeiten.',
        ),
        findsOneWidget,
      );
      expect(find.text('E-Mail-Adresse'), findsOneWidget);
      expect(find.text('Passwort'), findsOneWidget);
      expect(find.text('Passwort vergessen?'), findsOneWidget);
      expect(find.text('Anmelden'), findsOneWidget);
      expect(find.text('Noch kein Mitarbeiterkonto?'), findsOneWidget);
      expect(find.text('Registrieren'), findsOneWidget);
    });

    testWidgets('fits a 360dp screen without overflow', (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await app.configure(initialLocation: AppRoutes.login);
      await app.pump(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.text('Welcome back'), findsOneWidget);
    });

    testWidgets('keeps the fixed brand theme under a dark platform setting', (
      tester,
    ) async {
      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.dark;
      addTearDown(
        tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
      );

      await app.configure(initialLocation: AppRoutes.login);
      await app.pump(tester);

      final BuildContext context = tester.element(find.byType(LoginPage));
      expect(context.theme.brightness, Brightness.light);
      expect(context.theme.scaffoldBackgroundColor, AppColors.background);
      expect(renderedButtonColor(tester), AppColors.primary);
    });
  });

  group('navigation between auth screens', () {
    testWidgets('login links to register and back keeps one visual system', (
      tester,
    ) async {
      await app.configure(initialLocation: AppRoutes.login);
      await app.pump(tester);

      // The logo asset decodes asynchronously: before any interaction with
      // lower content, scroll it into view (layout height differs between the
      // first frame and the decoded-logo frame).
      await tester.ensureVisible(find.text('Register'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Register'));
      await tester.pumpAndSettle();
      expect(find.byType(RegisterPage), findsOneWidget);
      expect(find.byType(AuthLogo), findsOneWidget);
      expect(logoImage(), findsOneWidget);

      await tester.ensureVisible(find.text('Sign In').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign In').last);
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
    });

    testWidgets('login links to forgot password', (tester) async {
      await app.configure(initialLocation: AppRoutes.login);
      await app.pump(tester);

      await tester.tap(find.text('Forgot Password?'));
      await tester.pumpAndSettle();
      expect(find.byType(ForgotPasswordPage), findsOneWidget);
      expect(find.byType(AuthLogo), findsOneWidget);
      expect(logoImage(), findsOneWidget);
    });
  });

  group('register screen', () {
    testWidgets('renders the shared brand system with all existing fields', (
      tester,
    ) async {
      await app.configure(initialLocation: AppRoutes.register);
      await app.pump(tester);

      expect(find.byType(RegisterPage), findsOneWidget);
      expect(find.byType(AuthLogo), findsOneWidget);
      expect(logoImage(), findsOneWidget);
      expect(find.text('Create employee account'), findsOneWidget);
      expect(find.text('Full Name'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Confirm Password'), findsOneWidget);
      expect(find.text('Password requirements'), findsOneWidget);
      expect(find.text('Create Account'), findsOneWidget);
      expect(find.text('Already have an account?'), findsOneWidget);
    });

    testWidgets('empty submit surfaces validation without registration', (
      tester,
    ) async {
      await app.configure(initialLocation: AppRoutes.register);
      await app.pump(tester);

      await tester.ensureVisible(find.text('Create Account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create Account'));
      await tester.pump();

      expect(find.text('Full name is required.'), findsOneWidget);
      expect(find.text('Email address is required.'), findsOneWidget);
      expect(find.text('Password is required.'), findsOneWidget);
      expect(find.text('Please confirm your password.'), findsOneWidget);
    });
  });

  group('forgot password screen', () {
    testWidgets('renders the shared brand system', (tester) async {
      await app.configure(initialLocation: AppRoutes.forgotPassword);
      await app.pump(tester);

      expect(find.byType(ForgotPasswordPage), findsOneWidget);
      expect(find.byType(AuthLogo), findsOneWidget);
      expect(logoImage(), findsOneWidget);
      expect(find.text('Forgot your password?'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Send Recovery Link'), findsOneWidget);
      expect(find.text('Back to Sign In'), findsOneWidget);
    });

    testWidgets('empty submit surfaces validation without a reset call', (
      tester,
    ) async {
      await app.configure(initialLocation: AppRoutes.forgotPassword);
      await app.pump(tester);

      await tester.ensureVisible(find.text('Send Recovery Link'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send Recovery Link'));
      await tester.pump();

      expect(find.text('Email address is required.'), findsOneWidget);
    });
  });
}
