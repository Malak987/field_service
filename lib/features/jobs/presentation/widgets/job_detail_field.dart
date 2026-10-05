import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// One label/value pair on the job details page.
///
/// Value-first layout: the value is the visual focus, the label sits above
/// it in secondary text.
class JobDetailField extends StatelessWidget {
  const JobDetailField({super.key, required this.label, required this.value});

  /// Localized field label (e.g. `l10n.customerLabel`).
  final String label;

  /// Display value (name, date, number, ...).
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: context.textStyles.bodySmall),
        const SizedBox(height: AppSpacing.xxs),
        Text(value, style: context.textStyles.titleSmall),
      ],
    );
  }
}
