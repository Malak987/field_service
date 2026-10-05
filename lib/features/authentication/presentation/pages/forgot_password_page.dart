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
import 'package:field_service/features/authentication/presentation/widgets/auth_scaffold.dart';
import 'package:field_service/features/authentication/presentation/widgets/auth_secondary_button.dart';
import 'package:field_service/features/authentication/presentation/widgets/auth_success_message.dart';
import 'package:field_service/features/authentication/presentation/widgets/auth_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    await context.read<AuthenticationCubit>().sendPasswordResetEmail(
      email: _emailController.text.trim(),
    );
  }

  void _backToLogin() {
    context.read<AuthenticationCubit>().clearFeedback();
    final GoRouter? router = GoRouter.maybeOf(context);
    if (router != null && router.canPop()) {
      router.pop();
    } else {
      router?.go(AppRoutes.login);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return AuthScaffold(
      onBackPressed: _backToLogin,
      backTooltip: l10n.backToLoginButton,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AuthHeader(
            title: l10n.forgotPasswordTitle,
            subtitle: l10n.forgotPasswordSubtitle,
            icon: Icons.lock_reset_outlined,
          ),
          const SizedBox(height: AppSpacing.xxl),
          AuthFormContainer(
            child: BlocBuilder<AuthenticationCubit, AuthenticationState>(
              buildWhen: (
                AuthenticationState previous,
                AuthenticationState current,
              ) =>
                  (previous.status ==
                      AuthenticationStatus.passwordResetEmailSent) !=
                  (current.status ==
                      AuthenticationStatus.passwordResetEmailSent),
              builder: (BuildContext context, AuthenticationState state) {
                if (state.status ==
                    AuthenticationStatus.passwordResetEmailSent) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      AuthSuccessMessage(
                        message: l10n.successPasswordResetEmailSent,
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      AuthSecondaryButton(
                        label: l10n.backToLoginButton,
                        icon: Icons.arrow_back_outlined,
                        onPressed: _backToLogin,
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
                      AuthTextField(
                        controller: _emailController,
                        label: l10n.emailLabel,
                        hint: l10n.emailHint,
                        prefixIcon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.done,
                        autofillHints: const <String>[AutofillHints.email],
                        onFieldSubmitted: (_) => _submit(),
                        validator: (String? value) =>
                            PasswordValidator.validateEmail(value, context.l10n),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      AuthLoadingButton(
                        label: l10n.sendResetLinkButton,
                        icon: Icons.send_outlined,
                        onPressed: _submit,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AuthSecondaryButton(
                        label: l10n.backToLoginButton,
                        icon: Icons.arrow_back_outlined,
                        onPressed: _backToLogin,
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
