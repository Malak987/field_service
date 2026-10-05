import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/theme/app_colors.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_radius.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Card-styled container that wraps authentication forms with consistent
/// padding, border, and responsive spacing.
class AuthFormContainer extends StatelessWidget {
  const AuthFormContainer({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bool isDark = context.isDarkMode;
    final bool isWide =
        context.screenSize.width >= AppDimensions.tabletBreakpoint;
    final Color backgroundColor = isDark
        ? AppColors.cardDark
        : AppColors.cardLight;
    final Color borderColor = isDark
        ? AppColors.borderDark
        : AppColors.borderLight;

    return Container(
      padding: isWide
          ? AppSpacing.formContainerPaddingLarge
          : AppSpacing.formContainerPadding,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: AppRadius.cardDirectional,
        border: Border.all(
          color: borderColor,
          width: AppDimensions.borderWidth,
        ),
      ),
      child: child,
    );
  }
}
