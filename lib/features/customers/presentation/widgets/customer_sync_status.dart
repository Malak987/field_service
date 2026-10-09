import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/sync/sync_status.dart';
import 'package:field_service/core/sync/sync_status_cubit.dart';
import 'package:field_service/core/theme/app_colors.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_radius.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/features/customers/domain/entities/customer_sync_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Compact sync badge for one customer row.
///
/// Reads the row's local-only [CustomerSyncStatus] — an offline render never
/// waits for the network to know what it can display here.
class CustomerSyncStatusChip extends StatelessWidget {
  const CustomerSyncStatusChip({super.key, required this.status});

  final CustomerSyncStatus status;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    final (IconData icon, String label, Color color) = switch (status) {
      CustomerSyncStatus.synced => (
        Icons.cloud_done_outlined,
        l10n.syncedLabel,
        AppColors.success,
      ),
      CustomerSyncStatus.pending => (
        Icons.cloud_upload_outlined,
        l10n.pendingSyncLabel,
        AppColors.warning,
      ),
      CustomerSyncStatus.inProgress => (
        Icons.sync,
        l10n.syncingLabel,
        AppColors.info,
      ),
      CustomerSyncStatus.failed => (
        Icons.cloud_off_outlined,
        l10n.syncFailedLabel,
        AppColors.error,
      ),
    };

    final Color background = switch (status) {
      CustomerSyncStatus.synced => AppColors.successSurface,
      CustomerSyncStatus.pending => AppColors.warningSurface,
      CustomerSyncStatus.inProgress => AppColors.primarySurface,
      CustomerSyncStatus.failed => AppColors.errorSurface,
    };

    return _SyncBadge(
      icon: icon,
      label: label,
      color: color,
      background: background,
    );
  }
}

/// Whole-engine sync indicator for the customers screen header.
///
/// Purely re-uses the shared `SyncStatusCubit` (connectivity + queue health);
/// the feature deliberately does not grow its own network or queue logic.
class CustomerSyncStatusBar extends StatelessWidget {
  const CustomerSyncStatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return BlocBuilder<SyncStatusCubit, SyncHealth>(
      builder: (BuildContext context, SyncHealth health) {
        final (
          IconData icon,
          String label,
          Color color,
        ) = switch (health.displayStatus) {
          SyncDisplayStatus.synced => (
            Icons.cloud_done_outlined,
            l10n.syncedLabel,
            AppColors.success,
          ),
          SyncDisplayStatus.syncing => (
            Icons.sync,
            l10n.syncingLabel,
            AppColors.info,
          ),
          SyncDisplayStatus.offline => (
            Icons.cloud_off_outlined,
            l10n.offlineLabel,
            context.colors.outline,
          ),
          SyncDisplayStatus.pendingChanges => (
            Icons.cloud_upload_outlined,
            l10n.pendingSyncLabel,
            AppColors.warning,
          ),
          SyncDisplayStatus.failed => (
            Icons.error_outline,
            l10n.syncFailedLabel,
            AppColors.error,
          ),
        };

        return _SyncBadge(
          icon: icon,
          label: label,
          color: color,
          background: Colors.transparent,
        );
      },
    );
  }
}

class _SyncBadge extends StatelessWidget {
  const _SyncBadge({
    required this.icon,
    required this.label,
    required this.color,
    required this.background,
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
