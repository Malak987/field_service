import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Horizontal separator with an optional centered label.
class AuthDivider extends StatelessWidget {
  const AuthDivider({this.label, super.key});

  final String? label;

  @override
  Widget build(BuildContext context) {
    if (label == null || label!.isEmpty) {
      return const Padding(
        padding: EdgeInsetsDirectional.symmetric(vertical: AppSpacing.lg),
        child: Divider(),
      );
    }

    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(vertical: AppSpacing.lg),
      child: Row(
        children: <Widget>[
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: AppSpacing.md,
            ),
            child: Text(label!, style: context.textStyles.bodySmall),
          ),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }
}
