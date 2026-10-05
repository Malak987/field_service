import 'package:field_service/app/router/app_routes.dart';
import 'package:field_service/core/constants/app_constants.dart';
import 'package:field_service/core/localization/app_localizations.dart';
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
import 'package:field_service/features/authentication/presentation/widgets/auth_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    await context.read<AuthenticationCubit>().signIn(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );
  }

  void _navigateToForgotPassword() {
    context.read<AuthenticationCubit>().clearFeedback();
    final GoRouter? router = GoRouter.maybeOf(context);
    router?.push(AppRoutes.forgotPassword);
  }

  void _navigateToRegister() {
    context.read<AuthenticationCubit>().clearFeedback();
    final GoRouter? router = GoRouter.maybeOf(context);
    router?.push(AppRoutes.register);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return BlocListener<AuthenticationCubit, AuthenticationState>(
      listenWhen:
          (AuthenticationState previous, AuthenticationState current) =>
              previous.status != current.status,
      listener: (BuildContext context, AuthenticationState state) {
        final GoRouter? router = GoRouter.maybeOf(context);
        if (router == null) {
          return;
        }

        if (state.status == AuthenticationStatus.passwordRecovery) {
          router.go(AppRoutes.resetPassword);
          return;
        }

        if (state.status == AuthenticationStatus.authenticated &&
            state.user != null) {
          final String currentPath =
              router.routeInformationProvider.value.uri.path;
          if (currentPath != AppRoutes.root) {
            router.go(AppRoutes.root);
          }
        }
      },
      child: AuthScaffold(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AuthHeader(
              title: l10n.loginTitle,
              subtitle: l10n.loginSubtitle,
            ),
            const SizedBox(height: AppSpacing.xxl),
            AuthFormContainer(
              child: Form(
                key: _formKey,
                child: AutofillGroup(
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
                        builder:
                            (
                              BuildContext context,
                              AuthenticationState state,
                            ) {
                              if (!state.hasError) {
                                return const SizedBox.shrink();
                              }

                              final String localizedError =
                                  AuthenticationErrorMapper.toLocalizedMessage(
                                    context.l10n,
                                    code: state.errorCode,
                                    error: state.message,
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
                        textInputAction: TextInputAction.next,
                        autofillHints: const <String>[AutofillHints.email],
                        validator: (String? value) =>
                            PasswordValidator.validateEmail(value, context.l10n),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      AuthPasswordField(
                        controller: _passwordController,
                        label: l10n.passwordLabel,
                        hint: l10n.passwordHint,
                        textInputAction: TextInputAction.done,
                        autofillHints: const <String>[AutofillHints.password],
                        onFieldSubmitted: (_) => _submit(),
                        validator: (String? value) =>
                            PasswordValidator.validateLoginPassword(
                              value,
                              context.l10n,
                            ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: TextButton(
                          onPressed: _navigateToForgotPassword,
                          child: Text(l10n.forgotPasswordLink),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AuthLoadingButton(
                        label: l10n.signInButton,
                        icon: Icons.login_outlined,
                        onPressed: _submit,
                      ),
                      if (AppConstants.allowSelfRegistration) ...<Widget>[
                        const AuthDivider(),
                        AuthFooter(
                          promptText: l10n.noAccountPrompt,
                          actionText: l10n.registerLink,
                          onActionPressed: _navigateToRegister,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
