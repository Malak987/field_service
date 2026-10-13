import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/theme/app_colors.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_radius.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Heading of a non-workflow information section on the Job Details page.
///
/// Workflow stages receive their own numbered treatment. This compact identity
/// block makes read-only job, customer and request information recognisable
/// without competing with the next actionable step.
class JobSectionHeading extends StatelessWidget {
  const JobSectionHeading({
    super.key,
    required this.icon,
    required this.title,
  });

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Container(
        width: AppDimensions.buttonHeightCompact,
        height: AppDimensions.buttonHeightCompact,
        decoration: const BoxDecoration(
          color: AppColors.primarySurface,
          borderRadius: AppRadius.banner,
        ),
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: AppDimensions.iconMd,
          color: AppColors.primary,
        ),
      ),
      const SizedBox(width: AppSpacing.md),
      Expanded(child: Text(title, style: context.textStyles.titleMedium)),
    ],
  );
}
