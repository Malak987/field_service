import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/theme/app_colors.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_radius.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';

/// Accessible inline error alert banner displayed inside authentication forms.
///
/// Quiet but unmistakable: a soft red wash on the white surface with a hairline
/// red border — no giant red boxes, no dialogs, no raw exceptions.
class AuthErrorMessage extends StatelessWidget {
  const AuthErrorMessage({required this.message, this.onDismiss, super.key});

  final String message;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final Color foregroundColor = context.colors.error;

    return Semantics(
      liveRegion: true,
      child: Container(
        padding: AppSpacing.bannerPadding,
        decoration: BoxDecoration(
          color: AppColors.errorSurface,
          borderRadius: AppRadius.bannerDirectional,
          border: Border.all(
            color: foregroundColor.withValues(alpha: 0.35),
            width: AppDimensions.borderWidth,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              Icons.error_outline,
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
            if (onDismiss != null) ...<Widget>[
              const SizedBox(width: AppSpacing.xs),
              InkWell(
                onTap: onDismiss,
                customBorder: const CircleBorder(),
                child: Icon(
                  Icons.close,
                  size: AppDimensions.iconSm,
                  color: foregroundColor,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
