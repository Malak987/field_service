import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_colors.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Blocking, unblocking and soft deleting are consequential, so every one of
/// them is confirmed first (the requirement: "تأكيد قبل التنفيذ").
///
/// Returns `true` only when the admin explicitly confirms; dismissing the
/// dialog (back button, tap outside, Cancel) returns `false` — the safe default
/// for every management action.
///
/// The dialog is deliberately read-only: it explains what the action does and
/// that history is preserved, and it never triggers the API by itself.
Future<bool> showAdminActionConfirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  String? notice,
  bool isDestructive = false,
}) async {
  final AppLocalizations l10n = context.l10n;

  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) {
      return AlertDialog(
        key: const Key('admin_confirm_dialog'),
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(body),
            if (notice != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: AppSpacing.bannerPadding,
                decoration: BoxDecoration(
                  color: AppColors.primarySurface,
                  borderRadius: BorderRadius.circular(AppSpacing.md),
                ),
                child: Text(
                  notice,
                  style: Theme.of(dialogContext).textTheme.bodySmall,
                ),
              ),
            ],
          ],
        ),
        actions: <Widget>[
          TextButton(
            key: const Key('admin_confirm_cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancelButton),
          ),
          FilledButton(
            key: const Key('admin_confirm_accept'),
            style: isDestructive
                ? FilledButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                  )
                : null,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.adminConfirmAction),
          ),
        ],
      );
    },
  );

  return confirmed ?? false;
}
