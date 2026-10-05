import 'package:field_service/app/di/injection.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/features/admin/presentation/pages/admin_home_page.dart';
import 'package:field_service/features/authentication/domain/entities/app_user.dart';
import 'package:field_service/features/authentication/presentation/cubit/authentication_cubit.dart';
import 'package:field_service/features/authentication/presentation/cubit/authentication_state.dart';
import 'package:field_service/features/authentication/presentation/pages/login_page.dart';
import 'package:field_service/features/authentication/presentation/pages/reset_password_page.dart';
import 'package:field_service/features/authentication/presentation/widgets/auth_error_message.dart';
import 'package:field_service/features/authentication/presentation/widgets/auth_form_container.dart';
import 'package:field_service/features/authentication/presentation/widgets/auth_scaffold.dart';
import 'package:field_service/features/authentication/presentation/widgets/auth_secondary_button.dart';
import 'package:field_service/features/technician/presentation/pages/technician_home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class AuthGatePage extends StatelessWidget {
  const AuthGatePage({super.key});

  @override
  Widget build(BuildContext context) {
    final AuthenticationCubit? existingCubit = context
        .read<AuthenticationCubit?>();
    if (existingCubit != null) {
      return const _AuthGateView();
    }

    return BlocProvider<AuthenticationCubit>(
      create: (_) => sl<AuthenticationCubit>()..checkCurrentUser(),
      child: const _AuthGateView(),
    );
  }
}

class _AuthGateView extends StatelessWidget {
  const _AuthGateView();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthenticationCubit, AuthenticationState>(
      buildWhen:
          (AuthenticationState previous, AuthenticationState current) =>
              previous.status != current.status ||
              previous.user != current.user,
      builder: (BuildContext context, AuthenticationState state) {
        switch (state.status) {
          case AuthenticationStatus.initial:
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
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
            final AppUser? user = state.user;

            if (user == null) {
              return const LoginPage();
            }

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

            // Unknown or invalid roles are never silently granted access.
            return _AccessDeniedGateView(
              message: context.l10n.errorInvalidRole,
            );
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
      child: AuthFormContainer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
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
      ),
    );
  }
}
