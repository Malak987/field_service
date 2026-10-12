import 'package:field_service/app/di/injection.dart';
import 'package:field_service/app/router/app_routes.dart';
import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/features/admin/domain/entities/admin_account_status.dart';
import 'package:field_service/features/admin/domain/entities/admin_failure.dart';
import 'package:field_service/features/admin/domain/entities/managed_customer.dart';
import 'package:field_service/features/admin/presentation/cubit/admin_customers_cubit.dart';
import 'package:field_service/features/admin/presentation/pages/admin_customers_page.dart';
import 'package:field_service/features/admin/presentation/utils/admin_management_labels.dart';
import 'package:field_service/features/admin/presentation/widgets/admin_account_status_badge.dart';
import 'package:field_service/features/admin/presentation/widgets/admin_confirm_dialog.dart';
import 'package:field_service/features/customers/presentation/utils/customers_date_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// Customer details of the management area (route `/admin/customers/:id`).
///
/// Shows every stored field, the lifecycle state and the management actions
/// (edit / block / unblock / soft delete). Historical jobs of the customer stay
/// untouched and are only counted here — nothing in this screen can delete or
/// rewrite a job, a photo or a signature.
class AdminCustomerDetailsPage extends StatelessWidget {
  const AdminCustomerDetailsPage({super.key, required this.customerId, this.cubit});

  /// `customers.id` of the record to show.
  final String customerId;

  /// Test seam: inject a pre-wired cubit.
  final AdminCustomersCubit? cubit;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<AdminCustomersCubit>(
      create: (_) => (cubit ?? sl<AdminCustomersCubit>())..loadCustomer(customerId),
      child: _AdminCustomerDetailsView(customerId: customerId),
    );
  }
}

class _AdminCustomerDetailsView extends StatelessWidget {
  const _AdminCustomerDetailsView({required this.customerId});

  final String customerId;

  Future<void> _runStatusAction(
    BuildContext context,
    AdminCustomersCubit cubit,
    ManagedCustomer customer,
    AdminAccountStatus status,
    String title,
    String body,
    bool isDestructive,
  ) async {
    final AppLocalizations l10n = context.l10n;

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
      AdminAccountStatus.blocked => await cubit.block(customer),
      AdminAccountStatus.active => await cubit.unblock(customer),
      AdminAccountStatus.deleted => await cubit.softDelete(customer),
      AdminAccountStatus.unknown => null,
    };
    if (!context.mounted) {
      return;
    }

    final String message = failure == null
        ? switch (status) {
            AdminAccountStatus.blocked => l10n.adminCustomerBlockedMessage,
            AdminAccountStatus.active => l10n.adminCustomerUnblockedMessage,
            AdminAccountStatus.deleted => l10n.adminCustomerDeletedMessage,
            AdminAccountStatus.unknown => l10n.adminCustomerUnblockedMessage,
          }
        : adminFailureMessage(l10n, failure);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(AppRoutes.root),
        ),
        title: Text(l10n.adminCustomerDetailsTitle),
        actions: <Widget>[
          BlocBuilder<AdminCustomersCubit, AdminCustomersState>(
            buildWhen: (AdminCustomersState a, AdminCustomersState b) =>
                a.selectedCustomer != b.selectedCustomer,
            builder: (BuildContext context, AdminCustomersState state) {
              final ManagedCustomer? customer = state.selectedCustomer;
              if (customer == null || !customer.canBeEdited) {
                return const SizedBox.shrink();
              }
              return IconButton(
                key: const Key('admin_customer_details_edit'),
                tooltip: l10n.editCustomer,
                icon: const Icon(Icons.edit_outlined, size: AppDimensions.iconMd),
                onPressed: () => context.pushNamed(
                  'adminCustomerEdit',
                  pathParameters: <String, String>{'id': customer.id},
                ),
              );
            },
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: BlocBuilder<AdminCustomersCubit, AdminCustomersState>(
        builder: (BuildContext context, AdminCustomersState state) {
          final AdminCustomersCubit cubit = context.read<AdminCustomersCubit>();

          if (state.isCustomerLoading) {
            return Center(
              child: Semantics(
                label: l10n.adminCustomersLoadingLabel,
                child: const CircularProgressIndicator(),
              ),
            );
          }

          final ManagedCustomer? customer = state.selectedCustomer;
          if (customer == null) {
            return Center(
              child: Padding(
                padding: AppSpacing.pagePadding,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.search_off_outlined,
                      size: AppDimensions.iconXl,
                      color: context.colors.error,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      l10n.customerNotFoundTitle,
                      textAlign: TextAlign.center,
                      style: context.textStyles.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      adminFailureMessage(
                        l10n,
                        state.loadFailure ?? AdminFailureKind.notFound,
                      ),
                      textAlign: TextAlign.center,
                      style: context.textStyles.bodyMedium,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    FilledButton(
                      key: const Key('admin_customer_details_retry'),
                      onPressed: () => cubit.loadCustomer(customerId),
                      child: Text(l10n.tryAgainButton),
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => cubit.loadCustomer(customerId),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: AppSpacing.pagePadding,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        customer.name,
                        style: context.textStyles.titleLarge,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    AdminAccountStatusBadge(status: customer.status),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                if (state.isBusy) ...<Widget>[
                  const LinearProgressIndicator(),
                  const SizedBox(height: AppSpacing.md),
                ],
                _DetailRow(
                  icon: Icons.place_outlined,
                  label: l10n.customerAddressLabel,
                  value: customer.address,
                ),
                if (customer.cityLine.isNotEmpty)
                  _DetailRow(
                    icon: Icons.location_city_outlined,
                    label: l10n.customerCityLabel,
                    value: customer.cityLine,
                  ),
                if ((customer.phone ?? '').trim().isNotEmpty)
                  _DetailRow(
                    icon: Icons.phone_outlined,
                    label: l10n.customerPhoneLabel,
                    value: customer.phone!.trim(),
                  ),
                if ((customer.email ?? '').trim().isNotEmpty)
                  _DetailRow(
                    icon: Icons.mail_outline,
                    label: l10n.customerEmailLabel,
                    value: customer.email!.trim(),
                  ),
                if ((customer.notes ?? '').trim().isNotEmpty)
                  _DetailRow(
                    icon: Icons.sticky_note_2_outlined,
                    label: l10n.customerNotesLabel,
                    value: customer.notes!.trim(),
                  ),
                _DetailRow(
                  icon: Icons.assignment_outlined,
                  label: l10n.jobsTitle,
                  value: l10n.adminCustomerJobsCountLabel(customer.jobsCount),
                ),
                if (customer.createdAt != null)
                  _DetailRow(
                    icon: Icons.event_outlined,
                    label: l10n.createdAtLabel,
                    value: formatCustomerDate(customer.createdAt!, context),
                  ),
                if (customer.updatedAt != null)
                  _DetailRow(
                    icon: Icons.update_outlined,
                    label: l10n.updatedAtLabel,
                    value: formatCustomerDate(customer.updatedAt!, context),
                  ),
                if (customer.blockedAt != null)
                  _DetailRow(
                    icon: Icons.block_outlined,
                    label: l10n.adminStatusBlocked,
                    value: l10n.adminBlockedOnLabel(
                      formatCustomerDate(customer.blockedAt!, context),
                    ),
                  ),
                if (customer.deletedAt != null)
                  _DetailRow(
                    icon: Icons.delete_outline,
                    label: l10n.adminStatusDeleted,
                    value: l10n.adminDeletedOnLabel(
                      formatCustomerDate(customer.deletedAt!, context),
                    ),
                  ),
                if (!customer.isDeleted) ...<Widget>[
                  const SizedBox(height: AppSpacing.lg),
                  AdminInfoBanner(text: l10n.adminHistoryKeptNotice),
                ],
                if (customer.isDeleted) ...<Widget>[
                  const SizedBox(height: AppSpacing.lg),
                  AdminInfoBanner(text: l10n.adminDeletedCustomerNotice),
                ],
                const SizedBox(height: AppSpacing.xl),
                if (customer.canBeBlocked)
                  OutlinedButton.icon(
                    key: Key('admin_customer_details_block_${customer.id}'),
                    onPressed: state.isBusy
                        ? null
                        : () => _runStatusAction(
                            context,
                            cubit,
                            customer,
                            AdminAccountStatus.blocked,
                            l10n.adminBlockCustomerConfirmTitle,
                            l10n.adminBlockCustomerConfirmBody(customer.name),
                            true,
                          ),
                    icon: const Icon(Icons.block_outlined),
                    label: Text(l10n.adminBlockAction),
                  ),
                if (customer.canBeUnblocked)
                  FilledButton.icon(
                    key: Key('admin_customer_details_unblock_${customer.id}'),
                    onPressed: state.isBusy
                        ? null
                        : () => _runStatusAction(
                            context,
                            cubit,
                            customer,
                            AdminAccountStatus.active,
                            l10n.adminUnblockCustomerConfirmTitle,
                            l10n.adminUnblockCustomerConfirmBody(customer.name),
                            false,
                          ),
                    icon: const Icon(Icons.lock_open_outlined),
                    label: Text(l10n.adminUnblockAction),
                  ),
                if (customer.canBeDeleted)
                  TextButton.icon(
                    key: Key('admin_customer_details_delete_${customer.id}'),
                    onPressed: state.isBusy
                        ? null
                        : () => _runStatusAction(
                            context,
                            cubit,
                            customer,
                            AdminAccountStatus.deleted,
                            l10n.adminDeleteCustomerConfirmTitle,
                            l10n.adminDeleteCustomerConfirmBody(customer.name),
                            true,
                          ),
                    icon: const Icon(Icons.delete_outline),
                    label: Text(l10n.adminSoftDeleteAction),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: AppDimensions.iconMd, color: context.colors.primary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: context.textStyles.labelMedium?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(value, style: context.textStyles.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
