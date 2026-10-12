import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// The opening block of a dashboard: who you are, what today is, and nothing
/// else.
///
/// Kept as open text on the canvas rather than a boxed "profile card". A
/// decorative avatar tile spent ~88px of a phone screen on chrome before any
/// work was visible; the greeting carries the same information in three lines
/// and leaves the rest of the viewport for the job.
///
/// The date is shown because an administrator deciding what to chase today is
/// working against a calendar, and because a technician's shift has a date.
/// It is formatted through `intl` for the active locale, so it is never a
/// hard-coded English string.
class AppDashboardHeader extends StatelessWidget {
  const AppDashboardHeader({
    required this.greeting,
    this.subtitle,
    this.dateLabel,
    super.key,
  });

  /// The welcome line, already localized and already containing the user's real
  /// name when one is known.
  final String greeting;

  /// The role under the greeting ("Administrator" / "Technician").
  final String? subtitle;

  /// Today's date, formatted for the active locale. Omitted rather than
  /// guessed when the caller has no date to show.
  final String? dateLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          greeting,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: context.textStyles.headlineMedium,
        ),
        if (subtitle != null || dateLabel != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              if (subtitle != null)
                Flexible(
                  child: Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.textStyles.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ),
              if (subtitle != null && dateLabel != null)
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: AppSpacing.sm,
                    end: AppSpacing.sm,
                  ),
                  child: Container(
                    width: 3,
                    height: 3,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: context.colors.outlineVariant,
                    ),
                  ),
                ),
              if (dateLabel != null) ...<Widget>[
                Icon(
                  Icons.calendar_today_outlined,
                  size: AppDimensions.iconSm,
                  color: context.colors.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(
                    dateLabel!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.textStyles.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}
