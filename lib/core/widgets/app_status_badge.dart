import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/theme/app_colors.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_radius.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// The semantic treatment for a compact state label.
///
/// A badge communicates status, never a primary action. It is therefore kept
/// compact, uses a soft tonal fill and never relies on colour alone: callers
/// always provide a localized [label] and may provide an [icon].
enum AppStatusTone { neutral, brand, info, success, warning, danger }

/// A reusable, accessible status badge for sync, account, job and validation
/// states.
///
/// Labels remain feature-owned and localized by the caller. The component owns
/// only the visual grammar: icon, compact type, semantic colour and pill shape.
/// [foregroundColor] and [backgroundColor] are available for an established
/// domain colour mapping while new callers should prefer [tone].
class AppStatusBadge extends StatelessWidget {
  const AppStatusBadge({
    required this.label,
    this.icon,
    this.tone = AppStatusTone.neutral,
    this.filled = true,
    this.foregroundColor,
    this.backgroundColor,
    super.key,
  });

  final String label;
  final IconData? icon;
  final AppStatusTone tone;

  /// Removes the soft colour wash while retaining the semantic foreground.
  /// Useful when the badge appears in compact header chrome.
  final bool filled;

  /// Optional semantic foreground override for legacy domain mappings.
  final Color? foregroundColor;

  /// Optional soft-surface override for legacy domain mappings.
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final _BadgeColors colors = _resolveColors(context);
    final Color foreground = foregroundColor ?? colors.foreground;
    final Color background = filled
        ? backgroundColor ?? colors.background
        : Colors.transparent;

    return Semantics(
      label: label,
      child: Container(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: AppRadius.circular,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: AppDimensions.iconSm, color: foreground),
              const SizedBox(width: AppSpacing.xs),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textStyles.labelSmall?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  _BadgeColors _resolveColors(BuildContext context) => switch (tone) {
    AppStatusTone.neutral => _BadgeColors(
      context.colors.onSurfaceVariant,
      AppColors.surfaceMuted,
    ),
    AppStatusTone.brand => const _BadgeColors(
      AppColors.primary,
      AppColors.primarySurface,
    ),
    AppStatusTone.info => const _BadgeColors(
      AppColors.info,
      AppColors.infoSurface,
    ),
    AppStatusTone.success => const _BadgeColors(
      AppColors.success,
      AppColors.successSurface,
    ),
    AppStatusTone.warning => const _BadgeColors(
      AppColors.warning,
      AppColors.warningSurface,
    ),
    AppStatusTone.danger => const _BadgeColors(
      AppColors.error,
      AppColors.errorSurface,
    ),
  };
}

class _BadgeColors {
  const _BadgeColors(this.foreground, this.background);

  final Color foreground;
  final Color background;
}
