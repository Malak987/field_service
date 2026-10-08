import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Centered error placeholder with a retry action.
class JobsErrorState extends StatelessWidget {
  const JobsErrorState({super.key, required this.onRetry});

  /// Invoked when the user taps "Try again".
  final VoidCallback onRetry;

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
              Icons.error_outline,
              size: AppDimensions.iconXl,
              color: context.colors.error,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              l10n.jobsErrorTitle,
              textAlign: TextAlign.center,
              style: context.textStyles.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.jobsErrorSubtitle,
              textAlign: TextAlign.center,
              style: context.textStyles.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton(onPressed: onRetry, child: Text(l10n.tryAgainButton)),
          ],
        ),
      ),
    );
  }
}
