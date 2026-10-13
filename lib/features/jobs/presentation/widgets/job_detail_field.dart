import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/theme/app_colors.dart';
import 'package:field_service/core/theme/app_radius.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// One label/value pair on the Job Details page.
///
/// Value-first layout: the value is the visual focus, the label sits above it
/// in secondary text. Each fact gets a quiet inset surface, which keeps dates
/// and assignment metadata scannable without making the surrounding section a
/// second stack of cards.
class JobDetailField extends StatelessWidget {
  const JobDetailField({super.key, required this.label, required this.value});

  /// Localized field label (e.g. `l10n.customerLabel`).
  final String label;

  /// Display value (name, date, number, ...).
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: AppRadius.banner,
        border: Border.all(color: context.colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: context.textStyles.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(value, style: context.textStyles.titleSmall),
        ],
      ),
    );
  }
}
