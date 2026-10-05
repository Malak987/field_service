import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/theme/app_colors.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_radius.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';

/// Accessible inline success alert banner displayed inside authentication forms.
class AuthSuccessMessage extends StatelessWidget {
  const AuthSuccessMessage({
    required this.message,
    super.key,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    final bool isDark = context.isDarkMode;
    final Color backgroundColor = isDark
        ? AppColors.successSurfaceDark
        : AppColors.successSurfaceLight;
    const Color foregroundColor = AppColors.success;

    return Semantics(
      liveRegion: true,
      child: Container(
        padding: AppSpacing.bannerPadding,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: AppRadius.bannerDirectional,
          border: Border.all(
            color: foregroundColor.withValues(alpha: 0.35),
            width: AppDimensions.borderWidth,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(
              Icons.check_circle_outline,
              size: AppDimensions.iconMd,
              color: foregroundColor,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                message,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: foregroundColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
