import 'package:field_service/app/router/app_routes.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/core/utils/password_validator.dart';
import 'package:field_service/features/authentication/presentation/cubit/authentication_cubit.dart';
import 'package:field_service/features/authentication/presentation/cubit/authentication_state.dart';
import 'package:field_service/features/authentication/presentation/utils/authentication_error_mapper.dart';
import 'package:field_service/features/authentication/presentation/widgets/auth_error_message.dart';
import 'package:field_service/features/authentication/presentation/widgets/auth_form_container.dart';
import 'package:field_service/features/authentication/presentation/widgets/auth_header.dart';
import 'package:field_service/features/authentication/presentation/widgets/auth_loading_button.dart';
import 'package:field_service/features/authentication/presentation/widgets/auth_password_field.dart';
import 'package:field_service/features/authentication/presentation/widgets/auth_primary_button.dart';
import 'package:field_service/features/authentication/presentation/widgets/auth_scaffold.dart';
import 'package:field_service/features/authentication/presentation/widgets/auth_secondary_button.dart';
import 'package:field_service/features/authentication/presentation/widgets/auth_success_message.dart';
import 'package:field_service/features/authentication/presentation/widgets/password_requirements.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  @override
  void dispose() {
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    await context.read<AuthenticationCubit>().updatePassword(
      newPassword: _newPasswordController.text,
    );
  }

  void _returnToLogin() {
    context.read<AuthenticationCubit>().clearFeedback();
    GoRouter.maybeOf(context)?.go(AppRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return AuthScaffold(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AuthHeader(
            title: l10n.resetPasswordTitle,
            subtitle: l10n.resetPasswordSubtitle,
            icon: Icons.key_outlined,
          ),
          const SizedBox(height: AppSpacing.xxl),
          AuthFormContainer(
            child: BlocBuilder<AuthenticationCubit, AuthenticationState>(
              buildWhen: (
                AuthenticationState previous,
                AuthenticationState current,
              ) =>
                  (previous.status ==
                      AuthenticationStatus.passwordResetSuccess) !=
                  (current.status ==
                      AuthenticationStatus.passwordResetSuccess),
              builder: (BuildContext context, AuthenticationState state) {
                if (state.status ==
                    AuthenticationStatus.passwordResetSuccess) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      AuthSuccessMessage(
                        message: l10n.successPasswordUpdated,
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      AuthPrimaryButton(
                        label: l10n.backToLoginButton,
                        icon: Icons.login_outlined,
                        onPressed: _returnToLogin,
                      ),
                    ],
                  );
                }

                return Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      BlocBuilder<AuthenticationCubit, AuthenticationState>(
                        buildWhen: (
                          AuthenticationState previous,
                          AuthenticationState current,
                        ) =>
                            previous.status != current.status ||
                            previous.errorCode != current.errorCode ||
                            previous.message != current.message,
                        builder: (
                          BuildContext context,
                          AuthenticationState errorState,
                        ) {
                          if (!errorState.hasError) {
                            return const SizedBox.shrink();
                          }

                          final String localizedError =
                              AuthenticationErrorMapper.toLocalizedMessage(
                                context.l10n,
                                code: errorState.errorCode,
                                error: errorState.message,
                              );

                          return Padding(
                            padding: const EdgeInsetsDirectional.only(
                              bottom: AppSpacing.lg,
                            ),
                            child: AuthErrorMessage(
                              message: localizedError,
                              onDismiss: () => context
                                  .read<AuthenticationCubit>()
                                  .clearFeedback(),
                            ),
                          );
                        },
                      ),
                      AuthPasswordField(
                        controller: _newPasswordController,
                        label: l10n.newPasswordLabel,
                        hint: l10n.newPasswordHint,
                        textInputAction: TextInputAction.next,
                        autofillHints: const <String>[
                          AutofillHints.newPassword,
                        ],
                        validator: (String? value) =>
                            PasswordValidator.validateNewPassword(
                              value,
                              context.l10n,
                            ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      PasswordRequirements(
                        controller: _newPasswordController,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      AuthPasswordField(
                        controller: _confirmPasswordController,
                        label: l10n.confirmPasswordLabel,
                        hint: l10n.confirmPasswordHint,
                        textInputAction: TextInputAction.done,
                        autofillHints: const <String>[
                          AutofillHints.newPassword,
                        ],
                        onFieldSubmitted: (_) => _submit(),
                        validator: (String? value) =>
                            PasswordValidator.validateConfirmPassword(
                              value,
                              _newPasswordController.text,
                              context.l10n,
                            ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      AuthLoadingButton(
                        label: l10n.savePasswordButton,
                        icon: Icons.check_circle_outline,
                        onPressed: _submit,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AuthSecondaryButton(
                        label: l10n.backToLoginButton,
                        icon: Icons.arrow_back_outlined,
                        onPressed: _returnToLogin,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
