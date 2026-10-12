import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/sync/sync_status.dart';
import 'package:field_service/core/theme/app_colors.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_radius.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// The one sync/connection indicator of the app.
///
/// Every surface that reports offline work — the customers header, the account
/// screen, the job details steps — renders this widget instead of growing a
/// second opinion about what "syncing" looks like. The copy and the colour come
/// from the shared queue/connectivity facts, never from a feature's own guess.
class AppSyncBadge extends StatelessWidget {
  const AppSyncBadge({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    this.background = Colors.transparent,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: AppDimensions.iconSm, color: color),
            const SizedBox(width: AppSpacing.xs),
            Text(
              label,
              style: context.textStyles.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The whole-engine indicator: connectivity plus the state of the sync queue.
///
/// Feed it the health the shared `SyncStatusCubit` exposes — the badge itself
/// owns no network or queue logic, it only says what the engine already knows.
class AppSyncStatusBadge extends StatelessWidget {
  const AppSyncStatusBadge({
    super.key,
    required this.health,
    this.filled = false,
  });

  final SyncHealth health;

  /// Paint the state's wash behind the badge (for a card / settings row) or
  /// leave it transparent (for a header).
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    final (IconData icon, String label, Color color, Color background) =
        switch (health.displayStatus) {
          SyncDisplayStatus.synced => (
            Icons.cloud_done_outlined,
            l10n.syncedLabel,
            AppColors.success,
            AppColors.successSurface,
          ),
          SyncDisplayStatus.syncing => (
            Icons.sync,
            l10n.syncingLabel,
            AppColors.info,
            AppColors.primarySurface,
          ),
          SyncDisplayStatus.offline => (
            Icons.cloud_off_outlined,
            l10n.offlineLabel,
            context.colors.outline,
            AppColors.surfaceMuted,
          ),
          SyncDisplayStatus.pendingChanges => (
            Icons.cloud_upload_outlined,
            l10n.pendingSyncLabel,
            AppColors.warning,
            AppColors.warningSurface,
          ),
          SyncDisplayStatus.failed => (
            Icons.error_outline,
            l10n.syncFailedLabel,
            AppColors.error,
            AppColors.errorSurface,
          ),
        };

    return AppSyncBadge(
      icon: icon,
      label: label,
      color: color,
      background: filled ? background : Colors.transparent,
    );
  }
}
