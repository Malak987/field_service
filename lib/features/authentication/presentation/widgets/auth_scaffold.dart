import 'package:field_service/core/theme/app_colors.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/core/widgets/language_switcher.dart';
import 'package:flutter/material.dart';

/// Responsive shell shared by all authentication screens (Login, Register,
/// Forgot Password, Reset Password).
///
/// The canvas is the warm cream brand background; the form column itself is
/// centred and width-capped so tablet/desktop never stretches the fields.
///
/// Features:
/// * Top bar with optional leading back action and the [LanguageSwitcher].
/// * `SafeArea` + `LayoutBuilder` + `SingleChildScrollView` + `ConstrainedBox`
///   so the layout adapts from compact phones to tablets and Flutter Web
///   without overflow when the on-screen keyboard appears.
/// * Keyboard dismisses on scroll drag.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    required this.child,
    this.onBackPressed,
    this.backTooltip,
    this.showLanguageSwitcher = true,
    super.key,
  });

  final Widget child;
  final VoidCallback? onBackPressed;
  final String? backTooltip;
  final bool showLanguageSwitcher;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints viewportConstraints) {
            final bool isCompact =
                viewportConstraints.maxWidth <
                AppDimensions.compactMobileBreakpoint;
            final double horizontalPadding = isCompact
                ? AppSpacing.lg
                : AppSpacing.xxl;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: AppSpacing.md,
                    end: AppSpacing.md,
                    top: AppSpacing.xs,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      if (onBackPressed != null)
                        IconButton(
                          onPressed: onBackPressed,
                          tooltip: backTooltip,
                          icon: const Icon(
                            Icons.arrow_back_outlined,
                            color: AppColors.primary,
                          ),
                        )
                      else
                        const SizedBox(
                          width: AppDimensions.buttonHeightCompact,
                        ),
                      if (showLanguageSwitcher) const LanguageSwitcher(),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsetsDirectional.only(
                      start: horizontalPadding,
                      end: horizontalPadding,
                      top: AppSpacing.xxl,
                      bottom: AppSpacing.xxl,
                    ),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: AppDimensions.authFormMaxWidth,
                        ),
                        child: child,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
