import 'package:field_service/app/di/injection.dart';
import 'package:field_service/app/router/app_routes.dart';
import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_colors.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_radius.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/core/widgets/language_switcher.dart';
import 'package:field_service/features/admin/domain/entities/admin_account_status.dart';
import 'package:field_service/features/admin/domain/entities/admin_failure.dart';
import 'package:field_service/features/admin/domain/entities/managed_employee.dart';
import 'package:field_service/features/admin/presentation/cubit/technicians_cubit.dart';
import 'package:field_service/features/admin/presentation/utils/admin_management_labels.dart';
import 'package:field_service/features/admin/presentation/widgets/admin_account_status_badge.dart';
import 'package:field_service/features/admin/presentation/widgets/admin_confirm_dialog.dart';
import 'package:field_service/features/authentication/presentation/cubit/authentication_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// `إدارة الفنيين / Manage Technicians` — the admin's technician management
/// screen (route `/admin/technicians`, refused to non-admin roles by the
/// router guard and by the database).
///
/// It lists every employee with the REAL name from `public.employees.name`,
/// the current lifecycle state, the job counters, and offers exactly three
/// actions — block, unblock, soft delete — each behind a confirmation dialog.
///
/// Nothing here is a security boundary: the buttons are a convenience. Every
/// action calls an admin-only SECURITY DEFINER RPC that re-checks the caller,
/// refuses self-management and never hard-deletes a row.
class AdminTechniciansPage extends StatelessWidget {
  const AdminTechniciansPage({super.key, this.cubit});

  /// Test seam: inject a pre-wired cubit; `null` resolves the configured
  /// instance from the service locator (same convention as `CustomersPage`).
  final TechniciansCubit? cubit;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<TechniciansCubit>(
      create: (_) => cubit ?? (sl<TechniciansCubit>()..load()),
      child: const _AdminTechniciansView(),
    );
  }
}

class _AdminTechniciansView extends StatelessWidget {
  const _AdminTechniciansView();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final String? ownEmployeeId = context.select<AuthenticationCubit, String?>(
      (AuthenticationCubit cubit) => cubit.state.user?.employeeId,
    );

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(AppRoutes.root),
        ),
        title: Text(l10n.adminTechniciansTitle),
        actions: <Widget>[
          const Padding(
            padding: EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.sm),
            child: Center(child: LanguageSwitcher()),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: BlocBuilder<TechniciansCubit, TechniciansState>(
        builder: (BuildContext context, TechniciansState state) {
          final TechniciansCubit cubit = context.read<TechniciansCubit>();

          switch (state.status) {
            case TechniciansStatus.initial:
            case TechniciansStatus.loading:
              if (state.hasEmployees) {
                break;
              }
              return Center(
                child: Semantics(
                  label: l10n.adminTechniciansLoadingLabel,
                  child: const CircularProgressIndicator(),
                ),
              );

            case TechniciansStatus.failure:
              if (state.hasEmployees) {
                break;
              }
              return _AdminListError(
                title: l10n.adminLoadFailedTitle,
                message: adminFailureMessage(
                  l10n,
                  state.loadFailure ?? AdminFailureKind.unknown,
                ),
                onRetry: cubit.load,
              );

            case TechniciansStatus.success:
              if (!state.hasEmployees) {
                return const _NoTechnicians();
              }
              break;
          }

          return RefreshIndicator(
            onRefresh: cubit.load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: AppSpacing.pagePadding,
              children: <Widget>[
                _IntroCard(
                  title: l10n.adminTechniciansSubtitle,
                  count: state.employees.length,
                ),
                const SizedBox(height: AppSpacing.lg),
                for (final ManagedEmployee employee in state.employees) ...[
                  _TechnicianCard(
                    employee: employee,
                    isBusy: state.busyEmployeeId == employee.id,
                    isOwnAccount: ownEmployeeId == employee.id,
                    isAnyBusy: state.isBusy,
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// One employee row: identity, real name, state, job history and the three
/// management actions.
class _TechnicianCard extends StatelessWidget {
  const _TechnicianCard({
    required this.employee,
    required this.isBusy,
    required this.isOwnAccount,
    required this.isAnyBusy,
  });

  final ManagedEmployee employee;
  final bool isBusy;
  final bool isOwnAccount;
  final bool isAnyBusy;

  Future<void> _confirmAndRun(
    BuildContext context,
    AdminAccountStatus status,
    String title,
    String body,
    bool isDestructive,
  ) async {
    final AppLocalizations l10n = context.l10n;
    final TechniciansCubit cubit = context.read<TechniciansCubit>();

    final bool confirmed = await showAdminActionConfirmDialog(
      context,
      title: title,
      body: body,
      notice: l10n.adminHistoryKeptNotice,
      isDestructive: isDestructive,
    );
    if (!confirmed || !context.mounted) {
      return;
    }

    final AdminFailureKind? failure = switch (status) {
      AdminAccountStatus.blocked => await cubit.block(employee),
      AdminAccountStatus.active => await cubit.unblock(employee),
      AdminAccountStatus.deleted => await cubit.softDelete(employee),
      AdminAccountStatus.unknown => null,
    };
    if (!context.mounted) {
      return;
    }

    final String message = failure == null
        ? switch (status) {
            AdminAccountStatus.blocked => l10n.adminTechnicianBlockedMessage,
            AdminAccountStatus.active => l10n.adminTechnicianUnblockedMessage,
            AdminAccountStatus.deleted => l10n.adminTechnicianDeletedMessage,
            AdminAccountStatus.unknown => l10n.adminTechnicianUnblockedMessage,
          }
        : adminFailureMessage(l10n, failure);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return Card(
      key: Key('technician_row_${employee.id}'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    employee.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.textStyles.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                AdminAccountStatusBadge(status: employee.status),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              _subtitle(l10n),
              style: context.textStyles.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
            if (employee.blockedAt != null || employee.deletedAt != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                _stateDate(l10n),
                style: context.textStyles.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${l10n.adminAssignedJobsLabel(employee.assignedJobs)} · '
              '${l10n.adminCompletedJobsLabel(employee.completedJobs)}',
              style: context.textStyles.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            if (isBusy) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              const LinearProgressIndicator(),
            ],
            if (!employee.isManageable || isOwnAccount) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(
                // Three distinct non-manageable situations, three messages:
                // the admin's own row, a soft deleted technician (history kept,
                // no reactivation) and a non-technician account.
                isOwnAccount
                    ? l10n.adminOwnAccountNotice
                    : employee.isDeleted
                    ? l10n.adminDeletedTechnicianNotice
                    : l10n.adminAdministratorNotice,
                style: context.textStyles.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ] else ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: <Widget>[
                  if (employee.canBeBlocked)
                    OutlinedButton.icon(
                      key: Key('technician_block_${employee.id}'),
                      onPressed: isAnyBusy
                          ? null
                          : () => _confirmAndRun(
                              context,
                              AdminAccountStatus.blocked,
                              l10n.adminBlockTechnicianConfirmTitle,
                              l10n.adminBlockTechnicianConfirmBody(
                                employee.displayName,
                              ),
                              true,
                            ),
                      icon: const Icon(
                        Icons.block_outlined,
                        size: AppDimensions.iconMd,
                      ),
                      label: Text(l10n.adminBlockAction),
                    ),
                  if (employee.canBeReactivated)
                    FilledButton.icon(
                      key: Key('technician_unblock_${employee.id}'),
                      onPressed: isAnyBusy
                          ? null
                          : () => _confirmAndRun(
                              context,
                              AdminAccountStatus.active,
                              l10n.adminUnblockTechnicianConfirmTitle,
                              l10n.adminUnblockTechnicianConfirmBody(
                                employee.displayName,
                              ),
                              false,
                            ),
                      icon: const Icon(
                        Icons.lock_open_outlined,
                        size: AppDimensions.iconMd,
                      ),
                      label: Text(l10n.adminUnblockAction),
                    ),
                  if (employee.canBeDeleted)
                    TextButton.icon(
                      key: Key('technician_delete_${employee.id}'),
                      onPressed: isAnyBusy
                          ? null
                          : () => _confirmAndRun(
                              context,
                              AdminAccountStatus.deleted,
                              l10n.adminDeleteTechnicianConfirmTitle,
                              l10n.adminDeleteTechnicianConfirmBody(
                                employee.displayName,
                              ),
                              true,
                            ),
                      icon: const Icon(
                        Icons.delete_outline,
                        size: AppDimensions.iconMd,
                      ),
                      label: Text(l10n.adminSoftDeleteAction),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _subtitle(AppLocalizations l10n) {
    final List<String> parts = <String>[
      if (employee.isTechnician) l10n.roleTechnicianLabel else l10n.roleAdminLabel,
      if ((employee.employeeCode ?? '').trim().isNotEmpty)
        employee.employeeCode!.trim(),
      if ((employee.email ?? '').trim().isNotEmpty) employee.email!.trim(),
    ];
    return parts.join(' · ');
  }

  String _stateDate(AppLocalizations l10n) {
    final String? date = (employee.deletedAt ?? employee.blockedAt)?.toLocal()
        .toIso8601String()
        .split('T')
        .first;
    if (employee.deletedAt != null) {
      return l10n.adminDeletedOnLabel(date ?? '');
    }
    return l10n.adminBlockedOnLabel(date ?? '');
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return Container(
      width: double.infinity,
      padding: AppSpacing.bannerPadding,
      decoration: BoxDecoration(
        color: AppColors.primarySurface,
        borderRadius: AppRadius.banner,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: context.textStyles.bodyMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.adminAccountsCountLabel(count),
            style: context.textStyles.labelMedium?.copyWith(
              color: AppColors.primaryDark,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _NoTechnicians extends StatelessWidget {
  const _NoTechnicians();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return Center(
      child: Padding(
        padding: AppSpacing.pagePadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.badge_outlined,
              size: AppDimensions.iconXl,
              color: AppColors.goldDeep,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              l10n.adminTechniciansEmptyTitle,
              textAlign: TextAlign.center,
              style: context.textStyles.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.adminTechniciansEmptySubtitle,
              textAlign: TextAlign.center,
              style: context.textStyles.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared "could not load" placeholder of the two management list screens.
class _AdminListError extends StatelessWidget {
  const _AdminListError({
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final String title;
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return Center(
      child: Padding(
        padding: AppSpacing.pagePadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.error_outline,
              size: AppDimensions.iconXl,
              color: context.colors.error,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: context.textStyles.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: context.textStyles.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton(
              key: const Key('admin_list_retry'),
              onPressed: () => onRetry(),
              child: Text(l10n.tryAgainButton),
            ),
          ],
        ),
      ),
    );
  }
}
