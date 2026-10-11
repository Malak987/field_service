import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/theme/app_colors.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Heading of an information section on the Job Details page.
///
/// Used by the sections that are NOT workflow steps (job information, customer
/// request, customer) — the numbered [JobWorkflowStep] frame carries its own
/// heading, so these two never nest.
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
      Icon(icon, size: AppDimensions.iconMd, color: AppColors.primary),
      const SizedBox(width: AppSpacing.sm),
      Expanded(child: Text(title, style: context.textStyles.titleSmall)),
    ],
  );
}
