import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// A section heading on the open canvas: label, optional one-line context and
/// an optional trailing action, closed by a hairline rule.
///
/// This replaces the recurring "wrap everything in a card with a bold title"
/// pattern. Sections are separated by *space and a rule*, which keeps a screen
/// calm and lets the few real cards (the job that needs action, a form) stand
/// out because nothing else competes with them.
class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader({
    required this.title,
    this.subtitle,
    this.trailing,
    this.showRule = true,
    super.key,
  });

  /// The section label. Kept sentence-case — never all-caps.
  final String title;

  /// One line of context under [title]. Optional; omit rather than pad.
  final String? subtitle;

  /// A compact action on the trailing edge (usually a [TextButton]).
  final Widget? trailing;

  /// Whether the hairline rule is drawn. Turn it off when the section content
  /// immediately provides its own edge (a bordered card, a search field).
  final bool showRule;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: context.textStyles.titleSmall),
                    if (subtitle != null) ...<Widget>[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        subtitle!,
                        style: context.textStyles.bodySmall?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...<Widget>[
                const SizedBox(width: AppSpacing.sm),
                trailing!,
              ],
            ],
          ),
          if (showRule) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Divider(height: 1, color: context.colors.outlineVariant),
          ],
        ],
      ),
    );
  }
}
