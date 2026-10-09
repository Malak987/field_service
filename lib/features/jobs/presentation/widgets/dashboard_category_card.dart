import 'package:field_service/core/theme/app_colors.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_radius.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Accessible dashboard shortcut for one of the two supported job categories.
/// Count is nullable so unavailable data is never replaced with a fabricated 0.
class DashboardCategoryCard extends StatelessWidget {
  const DashboardCategoryCard({
    super.key,
    required this.title,
    required this.icon,
    required this.jobCount,
    required this.countLabel,
    required this.semanticLabel,
    required this.onTap,
    required this.isKitchen,
  });

  final String title;
  final IconData icon;
  final int? jobCount;
  final String Function(int count) countLabel;
  final String semanticLabel;
  final VoidCallback onTap;
  final bool isKitchen;

  @override
  Widget build(BuildContext context) {
    final Color accent = isKitchen ? AppColors.primary : AppColors.primaryDark;
    final Color wash = isKitchen ? AppColors.primarySurface : AppColors.goldSurface;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        button: true,
        container: true,
        label: semanticLabel,
        onTap: onTap,
        child: ExcludeSemantics(
          child: InkWell(
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 112),
              decoration: BoxDecoration(
                border: BorderDirectional(
                  start: BorderSide(color: accent, width: 4),
                ),
              ),
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: wash,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      icon,
                      size: AppDimensions.iconLg,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        if (jobCount != null) ...<Widget>[
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            countLabel(jobCount!),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: AppDimensions.iconSm,
                    color: accent,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
