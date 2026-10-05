import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Centered placeholder for the customers list.
///
/// Two flavors: the account has no customers at all, or the search query
/// matches none of them. Both stay fully offline-safe — they only describe
/// the local data.
class CustomerEmptyState extends StatelessWidget {
  const CustomerEmptyState({super.key, this.queryActive = false});

  /// `true` when a search query is applied and filtered everything out.
  final bool queryActive;

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
              queryActive ? Icons.search_off : Icons.people_outline,
              size: AppDimensions.iconXl,
              color: context.colors.outline,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              queryActive
                  ? l10n.customersNoResultsTitle
                  : l10n.customersEmptyTitle,
              textAlign: TextAlign.center,
              style: context.textStyles.titleMedium,
            ),
            if (!queryActive) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.customersEmptySubtitle,
                textAlign: TextAlign.center,
                style: context.textStyles.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
