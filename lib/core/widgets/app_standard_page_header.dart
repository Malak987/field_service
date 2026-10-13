import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_colors.dart';
import 'package:field_service/core/theme/app_radius.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Shared header for focused list, account, management and form pages.
///
/// Dashboard heroes and job identities intentionally keep their richer,
/// task-specific layouts. Standard pages share this quieter frame so a user
/// always finds the Heimwerk mark, hierarchy and supporting facts in the same
/// place without making unrelated screens behave alike.
class AppStandardPageHeader extends StatelessWidget {
  const AppStandardPageHeader({
    super.key,
    required this.logoAssetName,
    required this.title,
    required this.subtitle,
    this.supporting,
  });

  /// The existing centralized Heimwerk asset constant supplied by the caller.
  final String logoAssetName;
  final String title;
  final String subtitle;

  /// Optional supporting fact such as a localized count badge. It deliberately
  /// sits below the copy so long German titles remain readable on small phones.
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
      child: Stack(
        children: <Widget>[
          PositionedDirectional(
            start: 0,
            top: 0,
            bottom: 0,
            child: Container(width: 4, color: AppColors.primary),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Semantics(
                      image: true,
                      label: context.l10n.appName,
                      child: ExcludeSemantics(
                        child: Container(
                          width: 60,
                          height: 60,
                          padding: const EdgeInsets.all(AppSpacing.sm),
                          decoration: const BoxDecoration(
                            color: AppColors.goldSurface,
                            borderRadius: AppRadius.logoBadge,
                          ),
                          child: Image.asset(
                            logoAssetName,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(title, style: context.textStyles.headlineMedium),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            subtitle,
                            style: context.textStyles.bodyMedium?.copyWith(
                              color: context.colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (supporting != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.md),
                  supporting!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
