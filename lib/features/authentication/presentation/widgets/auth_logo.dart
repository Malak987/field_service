import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/theme/app_colors.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_radius.dart';
import 'package:flutter/material.dart';

/// Branded emblem displayed at the top of authentication screens.
class AuthLogo extends StatelessWidget {
  const AuthLogo({
    this.icon = Icons.handyman_outlined,
    super.key,
  });

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final bool isDark = context.isDarkMode;
    final Color backgroundColor = isDark
        ? AppColors.primarySurfaceDark
        : AppColors.primarySurfaceLight;
    final Color iconColor = context.colors.primary;

    return Center(
      child: Container(
        width: AppDimensions.authLogoContainerSize,
        height: AppDimensions.authLogoContainerSize,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: AppRadius.logoBadge,
          border: Border.all(
            color: iconColor.withValues(alpha: 0.2),
            width: AppDimensions.borderWidth,
          ),
        ),
        alignment: AlignmentDirectional.center,
        child: Icon(
          icon,
          size: AppDimensions.authLogoIconSize,
          color: iconColor,
        ),
      ),
    );
  }
}
