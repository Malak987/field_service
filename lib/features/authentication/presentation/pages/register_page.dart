import 'package:field_service/app/router/app_routes.dart';
import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_radius.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/core/utils/password_validator.dart';
import 'package:field_service/features/authentication/presentation/cubit/authentication_cubit.dart';
import 'package:field_service/features/authentication/presentation/cubit/authentication_state.dart';
import 'package:field_service/features/authentication/presentation/utils/authentication_error_mapper.dart';
import 'package:field_service/features/authentication/presentation/widgets/auth_divider.dart';
import 'package:field_service/features/authentication/presentation/widgets/auth_error_message.dart';
import 'package:field_service/features/authentication/presentation/widgets/auth_footer.dart';
import 'package:field_service/features/authentication/presentation/widgets/auth_form_container.dart';
import 'package:field_service/features/authentication/presentation/widgets/auth_header.dart';
import 'package:field_service/features/authentication/presentation/widgets/auth_loading_button.dart';
import 'package:field_service/features/authentication/presentation/widgets/auth_password_field.dart';
import 'package:field_service/features/authentication/presentation/widgets/auth_scaffold.dart';
import 'package:field_service/features/authentication/presentation/widgets/auth_secondary_button.dart';
import 'package:field_service/features/authentication/presentation/widgets/auth_success_message.dart';
import 'package:field_service/features/authentication/presentation/widgets/auth_text_field.dart';
import 'package:field_service/features/authentication/presentation/widgets/password_requirements.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    await context.read<AuthenticationCubit>().signUp(
      fullName: _fullNameController.text.trim(),
      email: _emailController.text.trim(),
      password: _passwordController.text,
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

    return BlocListener<AuthenticationCubit, AuthenticationState>(
      listenWhen: (AuthenticationState previous, AuthenticationState current) =>
          previous.status != current.status,
      listener: (BuildContext context, AuthenticationState state) {
        if (state.status == AuthenticationStatus.authenticated &&
            state.user != null) {
          GoRouter.maybeOf(context)?.go(AppRoutes.root);
        }
      },
      child: AuthScaffold(
        onBackPressed: _backToLogin,
        backTooltip: l10n.backToLoginButton,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AuthHeader(
              title: l10n.registerTitle,
              subtitle: l10n.registerSubtitle,
              icon: Icons.person_add_alt_1_outlined,
            ),
            const SizedBox(height: AppSpacing.xxl),
            AuthFormContainer(
              child: BlocBuilder<AuthenticationCubit, AuthenticationState>(
                buildWhen:
                    (
                      AuthenticationState previous,
                      AuthenticationState current,
                    ) =>
                        (previous.status ==
                            AuthenticationStatus.registrationSuccess) !=
                        (current.status ==
                            AuthenticationStatus.registrationSuccess),
                builder: (BuildContext context, AuthenticationState state) {
                  if (state.status ==
                      AuthenticationStatus.registrationSuccess) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        AuthSuccessMessage(
                          message: l10n.successRegistrationPending,
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
                    child: AutofillGroup(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          BlocBuilder<AuthenticationCubit, AuthenticationState>(
                            buildWhen:
                                (
                                  AuthenticationState previous,
                                  AuthenticationState current,
                                ) =>
                                    previous.status != current.status ||
                                    previous.errorCode != current.errorCode ||
                                    previous.message != current.message,
                            builder:
                                (
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
                            controller: _fullNameController,
                            label: l10n.fullNameLabel,
                            hint: l10n.fullNameHint,
                            prefixIcon: Icons.badge_outlined,
                            keyboardType: TextInputType.name,
                            textInputAction: TextInputAction.next,
                            autofillHints: const <String>[AutofillHints.name],
                            validator: (String? value) =>
                                PasswordValidator.validateFullName(
                                  value,
                                  context.l10n,
                                ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          AuthTextField(
                            controller: _emailController,
                            label: l10n.emailLabel,
                            hint: l10n.emailHint,
                            prefixIcon: Icons.email_outlined,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autofillHints: const <String>[AutofillHints.email],
                            validator: (String? value) =>
                                PasswordValidator.validateEmail(
                                  value,
                                  context.l10n,
                                ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          AuthPasswordField(
                            controller: _passwordController,
                            label: l10n.passwordLabel,
                            hint: l10n.passwordHint,
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
                          PasswordRequirements(controller: _passwordController),
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
                                  _passwordController.text,
                                  context.l10n,
                                ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          Container(
                            padding: AppSpacing.bannerPadding,
                            decoration: BoxDecoration(
                              borderRadius: AppRadius.bannerDirectional,
                              border: Border.all(
                                color: context.colors.outlineVariant,
                                width: AppDimensions.borderWidth,
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Icon(
                                  Icons.verified_user_outlined,
                                  size: AppDimensions.iconMd,
                                  color: context.colors.primary,
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Text(
                                    l10n.roleNoticeBanner,
                                    style: context.textStyles.bodySmall,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          AuthLoadingButton(
                            label: l10n.signUpButton,
                            icon: Icons.person_add_outlined,
                            onPressed: _submit,
                          ),
                          const AuthDivider(),
                          AuthFooter(
                            promptText: l10n.alreadyHaveAccountPrompt,
                            actionText: l10n.loginLink,
                            onActionPressed: _backToLogin,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
