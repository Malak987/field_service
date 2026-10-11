import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_colors.dart';
import 'package:field_service/core/theme/app_radius.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/features/admin/domain/entities/admin_account_status.dart';
import 'package:field_service/features/admin/presentation/utils/admin_management_labels.dart';
import 'package:flutter/material.dart';

/// Small pill showing an admin-managed account's lifecycle state
/// (active / blocked / soft deleted) — the same visual language as
/// `JobStatusBadge` and `CustomerSyncStatusChip`.
///
/// Purely presentational: the label comes from the shared localization lookup
/// and the colours from the semantic palette, so both management screens show
/// identical states.
class AdminAccountStatusBadge extends StatelessWidget {
  const AdminAccountStatusBadge({super.key, required this.status});

  final AdminAccountStatus status;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final (Color foreground, Color background) = _styleFor(context, status);

    return Container(
      key: Key('admin_status_badge_${status.name}'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadius.circular,
      ),
      child: Text(
        adminStatusLabel(l10n, status),
        style: context.textStyles.bodySmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// Semantic foreground/background pair of a lifecycle state.
  /// Kept public so list rows and the details pages reuse exactly one palette.
  static (Color, Color) styleFor(
    BuildContext context,
    AdminAccountStatus status,
  ) {
    switch (status) {
      case AdminAccountStatus.active:
        return (AppColors.success, AppColors.successSurface);
      case AdminAccountStatus.blocked:
        return (AppColors.warning, AppColors.warningSurface);
      case AdminAccountStatus.deleted:
        return (AppColors.error, AppColors.errorSurface);
      case AdminAccountStatus.unknown:
        final ColorScheme colors = context.colors;
        return (colors.onSurfaceVariant, colors.outlineVariant);
    }
  }
}
