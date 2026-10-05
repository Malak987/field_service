import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/theme/app_colors.dart';
import 'package:field_service/core/theme/app_radius.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/features/jobs/domain/entities/job_status.dart';
import 'package:flutter/material.dart';

/// Small pill that displays a job's [JobStatus] with a semantic colour.
///
/// The label is passed in (localized via [JobLabelMapper]) so this widget
/// stays purely presentational.
class JobStatusBadge extends StatelessWidget {
  const JobStatusBadge({super.key, required this.label, required this.status});

  /// Localized status text to display.
  final String label;

  /// Status whose value determines the colour.
  final JobStatus status;

  @override
  Widget build(BuildContext context) {
    final (Color foreground, Color background) = _styleFor(context);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadius.circular,
      ),
      child: Text(
        label,
        style: context.textStyles.bodySmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  (Color, Color) _styleFor(BuildContext context) {
    final bool isDark = context.isDarkMode;
    final ColorScheme colors = context.colors;

    return switch (status.value) {
      JobStatus.completed => (
        AppColors.success,
        isDark
            ? AppColors.successSurfaceDark
            : AppColors.successSurfaceLight,
      ),
      JobStatus.cancelled => (
        AppColors.error,
        isDark ? AppColors.errorSurfaceDark : AppColors.errorSurfaceLight,
      ),
      JobStatus.started || JobStatus.inProgress => (
        AppColors.warning,
        isDark
            ? AppColors.warningSurfaceDark
            : AppColors.warningSurfaceLight,
      ),
      JobStatus.assigned => (
        AppColors.info,
        isDark
            ? AppColors.primarySurfaceDark
            : AppColors.primarySurfaceLight,
      ),
      // Unknown backend value: neutral, theme-aware colours.
      _ => (colors.onSurfaceVariant, colors.outlineVariant),
    };
  }
}
