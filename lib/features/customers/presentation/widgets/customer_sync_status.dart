import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_colors.dart';
import 'package:field_service/core/widgets/app_sync_status_badge.dart';
import 'package:field_service/features/customers/domain/entities/customer_sync_status.dart';
import 'package:flutter/material.dart';

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

    return AppSyncBadge(
      icon: icon,
      label: label,
      color: color,
      background: background,
    );
  }
}
