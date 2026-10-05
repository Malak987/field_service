import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Reusable footer row for switching between authentication screens (e.g.
/// "Need an employee account? Register").
///
/// Uses `Wrap` so long German translations never overflow on small mobile
/// screens.
class AuthFooter extends StatelessWidget {
  const AuthFooter({
    required this.promptText,
    required this.actionText,
    required this.onActionPressed,
    super.key,
  });

  final String promptText;
  final String actionText;
  final VoidCallback onActionPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: AppSpacing.lg),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xxs,
        children: <Widget>[
          Text(
            promptText,
            style: context.textStyles.bodyMedium,
          ),
          TextButton(
            onPressed: onActionPressed,
            child: Text(actionText),
          ),
        ],
      ),
    );
  }
}
