import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// The quiet "this step has nothing yet" note, shared by the Job Details steps
/// (before photos, after photos, work description, signature).
///
/// It exists because an empty step is not an empty LIST: inside a workflow card
/// the technician needs to know what is missing and why it matters, without the
/// full-height centred empty state a list gets. One soft icon, the step's own
/// existing headline, and — when the step is required for completion — one line
/// saying so. All copy is passed in, so every step keeps its real message.
class JobStepEmptyNote extends StatelessWidget {
  const JobStepEmptyNote({
    super.key,
    required this.icon,
    required this.title,
    this.message,
  });

  final IconData icon;

  /// The step's existing empty headline (translated, never invented here).
  final String title;

  /// Optional one-line explanation, e.g. that the step is required to complete
  /// the job.
  final String? message;

  @override
  Widget build(BuildContext context) {
    final String? message = this.message;

    return Semantics(
      container: true,
      label: message == null ? title : '$title. $message',
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: context.colors.surfaceContainerHighest,
              ),
              alignment: Alignment.center,
              child: Icon(
                icon,
                size: AppDimensions.iconMd,
                color: context.colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: context.textStyles.titleSmall),
                  if (message != null) ...<Widget>[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      message,
                      style: context.textStyles.bodySmall?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
