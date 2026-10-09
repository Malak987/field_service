import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/features/admin/presentation/pages/admin_home_page.dart';
import 'package:field_service/features/authentication/domain/entities/app_user.dart';
import 'package:field_service/features/authentication/presentation/cubit/authentication_cubit.dart';
import 'package:field_service/features/authentication/presentation/cubit/authentication_state.dart';
import 'package:field_service/features/authentication/presentation/pages/login_page.dart';
import 'package:field_service/features/authentication/presentation/pages/reset_password_page.dart';
import 'package:field_service/features/authentication/presentation/utils/authentication_error_mapper.dart';
import 'package:field_service/features/authentication/presentation/widgets/auth_error_message.dart';
import 'package:field_service/features/authentication/presentation/widgets/auth_scaffold.dart';
import 'package:field_service/features/authentication/presentation/widgets/auth_secondary_button.dart';
import 'package:field_service/features/technician/presentation/pages/technician_home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Selects the login, password-recovery or role-specific home screen from the
/// app-scoped [AuthenticationCubit] state.
class AuthGatePage extends StatelessWidget {
  const AuthGatePage({super.key});

  @override
  Widget build(BuildContext context) => const _AuthGateView();
}

class _AuthGateView extends StatelessWidget {
  const _AuthGateView();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AuthenticationCubit, AuthenticationState>(
      listenWhen: (previous, current) =>
          current.hasError && current.user != null,
      listener: (BuildContext context, AuthenticationState state) {
        // Sign-out failures keep the real session and allow the user to retry.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AuthenticationErrorMapper.toLocalizedMessage(
                context.l10n,
                code: state.errorCode,
                error: state.message,
              ),
            ),
          ),
        );
      },
      buildWhen: (AuthenticationState previous, AuthenticationState current) =>
          previous.status != current.status || previous.user != current.user,
      builder: (BuildContext context, AuthenticationState state) {
        final AppUser? user = state.user;
        if (user != null &&
            (state.status == AuthenticationStatus.authenticated ||
                state.status == AuthenticationStatus.loading ||
                state.status == AuthenticationStatus.failure)) {
          if (!user.isActive) {
            return _AccessDeniedGateView(
              message: context.l10n.errorEmployeeInactive,
            );
          }
          if (user.isAdmin) {
            return const AdminHomePage();
          }
          if (user.isTechnician) {
            return const TechnicianHomePage();
          }
          return _AccessDeniedGateView(message: context.l10n.errorInvalidRole);
        }

        switch (state.status) {
          case AuthenticationStatus.initial:
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );

          case AuthenticationStatus.passwordRecovery:
          case AuthenticationStatus.passwordResetSuccess:
            return const ResetPasswordPage();

          case AuthenticationStatus.loading:
          case AuthenticationStatus.unauthenticated:
          case AuthenticationStatus.failure:
          case AuthenticationStatus.passwordResetEmailSent:
          case AuthenticationStatus.registrationSuccess:
            return const LoginPage();

          case AuthenticationStatus.authenticated:
            return const LoginPage();
        }
      },
    );
  }
}

class _AccessDeniedGateView extends StatelessWidget {
  const _AccessDeniedGateView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return AuthScaffold(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: AppSpacing.huge),
          Icon(
            Icons.gpp_bad_outlined,
            size: AppDimensions.iconXl,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: AppSpacing.lg),
          AuthErrorMessage(message: message),
          const SizedBox(height: AppSpacing.xl),
          AuthSecondaryButton(
            label: l10n.logoutButton,
            icon: Icons.logout_outlined,
            onPressed: () {
              context.read<AuthenticationCubit>().signOut();
            },
          ),
        ],
      ),
    );
  }
}
