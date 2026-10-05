import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/core/widgets/language_switcher.dart';
import 'package:flutter/material.dart';

/// Responsive shell shared by all authentication screens (Login, Register,
/// Forgot Password, Reset Password).
///
/// Features:
/// * Top bar with optional leading back action and the [LanguageSwitcher].
/// * `SafeArea` + `LayoutBuilder` + `SingleChildScrollView` + `ConstrainedBox`
///   so the layout adapts from compact phones to tablets and Flutter Web
///   without overflow when the on-screen keyboard appears.
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
            final EdgeInsetsDirectional outerPadding = isCompact
                ? AppSpacing.pagePaddingCompact
                : AppSpacing.pagePadding;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: EdgeInsetsDirectional.only(
                    start: isCompact ? AppSpacing.md : AppSpacing.xxl,
                    end: isCompact ? AppSpacing.md : AppSpacing.xxl,
                    top: AppSpacing.md,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      if (onBackPressed != null)
                        IconButton(
                          onPressed: onBackPressed,
                          tooltip: backTooltip,
                          icon: const Icon(Icons.arrow_back_outlined),
                        )
                      else
                        const SizedBox(width: AppDimensions.iconLg),
                      if (showLanguageSwitcher) const LanguageSwitcher(),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: outerPadding,
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
