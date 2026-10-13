import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/theme/app_colors.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_radius.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// A numbered, visually grouped section of either job-creation form.
///
/// The form page owns its fields, validation and workflow. This widget owns
/// only the shared visual hierarchy: a step marker, a section icon, optional
/// context and a consistently bordered surface.
class JobFormSection extends StatelessWidget {
  const JobFormSection({
    super.key,
    required this.number,
    required this.icon,
    required this.title,
    required this.child,
    this.supporting,
  });

  /// Visual step marker. It is intentionally excluded from semantics because
  /// the localized title is the useful section announcement.
  final String number;
  final IconData icon;
  final String title;
  final Widget child;

  /// Optional contextual content below the title, retained for form sections
  /// that need to explain a choice without creating a new heading pattern.
  final Widget? supporting;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.card,
        side: BorderSide(color: context.colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Semantics(
              header: true,
              label: title,
              child: ExcludeSemantics(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Container(
                      width: AppDimensions.buttonHeightCompact,
                      height: AppDimensions.buttonHeightCompact,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: AppColors.primarySurface,
                        borderRadius: AppRadius.banner,
                      ),
                      child: Icon(
                        icon,
                        color: AppColors.primary,
                        size: AppDimensions.iconMd,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        title,
                        style: context.textStyles.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        number,
                        style: context.textStyles.labelLarge?.copyWith(
                          color: AppColors.onBrand,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (supporting != null) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: AppDimensions.buttonHeightCompact + AppSpacing.md,
                ),
                child: supporting!,
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            child,
          ],
        ),
      ),
    );
  }
}
