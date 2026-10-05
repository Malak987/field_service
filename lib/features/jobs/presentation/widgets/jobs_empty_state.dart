import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Centered placeholder shown when the user has no accessible jobs.
class JobsEmptyState extends StatelessWidget {
  const JobsEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return Center(
      child: Padding(
        padding: AppSpacing.pagePadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.event_note,
              size: AppDimensions.iconXl,
              color: context.colors.outline,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              l10n.jobsEmptyTitle,
              textAlign: TextAlign.center,
              style: context.textStyles.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.jobsEmptySubtitle,
              textAlign: TextAlign.center,
              style: context.textStyles.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
