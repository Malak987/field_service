import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/theme/app_colors.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// One tappable destination on a role home screen (Admin Dashboard /
/// Technician Home).
///
/// The single reusable navigation component of the app's hub-and-spoke
/// navigation: home screens compose these tiles, each wired to an existing
/// route via `context.go`/`context.push`. Purely presentational — icon,
/// localized label and the tap callback come from the caller, so the widget
/// carries no feature or role knowledge and works for both roles.
///
/// Visual language follows the existing card/button design: theme Card,
/// icon badge in the primary surface colour, chevron affordance, light/dark
/// aware through [AppColors].
class HomeNavigationTile extends StatelessWidget {
  const HomeNavigationTile({
    super.key,
    required this.icon,
    required this.label,
    this.subtitle,
    required this.onTap,
  });

  /// Leading icon of the destination.
  final IconData icon;

  /// Localized title (e.g. "View Jobs", "Customers").
  final String label;

  /// Optional localized subtitle line.
  final String? subtitle;

  /// Called when the tile is tapped (repeated taps are safe: callers
  /// navigate with `context.go`, which never stacks duplicates).
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String? subtitle = this.subtitle;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: <Widget>[
              Container(
                width: AppDimensions.iconXl,
                height: AppDimensions.iconXl,
                decoration: BoxDecoration(
                  color: AppColors.primarySurface,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: AppDimensions.iconMd,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(label, style: context.textStyles.titleMedium),
                    if (subtitle != null) ...<Widget>[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        subtitle,
                        style: context.textStyles.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: AppDimensions.iconLg,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
