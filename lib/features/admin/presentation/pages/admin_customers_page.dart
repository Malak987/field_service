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
import 'package:field_service/features/admin/domain/entities/managed_customer.dart';
import 'package:field_service/features/admin/presentation/cubit/admin_customers_cubit.dart';
import 'package:field_service/features/admin/presentation/utils/admin_management_labels.dart';
import 'package:field_service/features/admin/presentation/widgets/admin_account_status_badge.dart';
import 'package:field_service/features/admin/presentation/widgets/admin_confirm_dialog.dart';
import 'package:field_service/features/customers/presentation/widgets/customer_search_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// `إدارة العملاء / Manage Customers` — the admin's customer management list
/// (route `/admin/customers`, refused to non-admin roles by the router guard and
/// by the database).
///
/// Shows every customer with its details and its lifecycle state, and offers
/// add / edit / block / unblock / soft delete. Blocked or soft deleted
/// customers stay visible on purpose: their historical jobs, photos and
/// signatures must remain reachable for the roles that could already read them.
class AdminCustomersPage extends StatelessWidget {
  const AdminCustomersPage({super.key, this.cubit});

  /// Test seam: inject a pre-wired cubit; `null` resolves the configured
  /// instance from the service locator.
  final AdminCustomersCubit? cubit;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<AdminCustomersCubit>(
      create: (_) => cubit ?? (sl<AdminCustomersCubit>()..load()),
      child: const _AdminCustomersView(),
    );
  }
}

class _AdminCustomersView extends StatefulWidget {
  const _AdminCustomersView();

  @override
  State<_AdminCustomersView> createState() => _AdminCustomersViewState();
}

class _AdminCustomersViewState extends State<_AdminCustomersView> {
  String _query = '';

  /// Pushes a child screen and reloads the list when it returns.
  ///
  /// The management screens own one cubit per page (factory), so a create /
  /// edit / status change performed on a child page would otherwise leave the
  /// list stale until the next manual pull-to-refresh.
  Future<void> _pushAndReload(BuildContext context, String route) async {
    final AdminCustomersCubit cubit = context.read<AdminCustomersCubit>();
    await context.push(route);
    if (!mounted || cubit.isClosed) {
      return;
    }
    await cubit.load();
  }

  Future<void> _pushNamedAndReload(
    BuildContext context,
    String name,
    String customerId,
  ) async {
    final AdminCustomersCubit cubit = context.read<AdminCustomersCubit>();
    await context.pushNamed(name, pathParameters: <String, String>{'id': customerId});
    if (!mounted || cubit.isClosed) {
      return;
    }
    await cubit.load();
  }

  List<ManagedCustomer> _applySearch(List<ManagedCustomer> customers) {
    if (_query.isEmpty) {
      return customers;
    }
    final String needle = _query.trim().toLowerCase();
    bool matches(ManagedCustomer customer) {
      return customer.name.toLowerCase().contains(needle) ||
          (customer.phone?.toLowerCase().contains(needle) ?? false) ||
          (customer.email?.toLowerCase().contains(needle) ?? false) ||
          customer.address.toLowerCase().contains(needle) ||
          (customer.city?.toLowerCase().contains(needle) ?? false) ||
          (customer.postalCode?.toLowerCase().contains(needle) ?? false);
    }

    return customers.where(matches).toList();
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
        title: Text(l10n.adminCustomersTitle),
        actions: <Widget>[
          const Padding(
            padding: EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.sm),
            child: Center(child: LanguageSwitcher()),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('admin_add_customer_fab'),
        tooltip: l10n.addCustomer,
        onPressed: () =>
            _pushAndReload(context, AppRoutes.adminCustomerCreate),
        child: const Icon(Icons.add, size: AppDimensions.iconLg),
      ),
      body: BlocBuilder<AdminCustomersCubit, AdminCustomersState>(
        builder: (BuildContext context, AdminCustomersState state) {
          final AdminCustomersCubit cubit = context.read<AdminCustomersCubit>();

          switch (state.status) {
            case AdminCustomersStatus.initial:
            case AdminCustomersStatus.loading:
              if (state.hasCustomers) {
                break;
              }
              return Center(
                child: Semantics(
                  label: l10n.adminCustomersLoadingLabel,
                  child: const CircularProgressIndicator(),
                ),
              );

            case AdminCustomersStatus.failure:
              if (state.hasCustomers) {
                break;
              }
              return _CustomersError(
                message: adminFailureMessage(
                  l10n,
                  state.loadFailure ?? AdminFailureKind.unknown,
                ),
                onRetry: cubit.load,
              );

            case AdminCustomersStatus.success:
              if (!state.hasCustomers) {
                return _NoCustomers(
                  onCreate: () =>
                      _pushAndReload(context, AppRoutes.adminCustomerCreate),
                );
              }
              break;
          }

          final List<ManagedCustomer> visible = _applySearch(state.customers);

          return Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  AppSpacing.xxl,
                  AppSpacing.md,
                  AppSpacing.xxl,
                  AppSpacing.sm,
                ),
                child: CustomerSearchField(
                  onQueryChanged: (String query) =>
                      setState(() => _query = query),
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: cubit.load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: AppSpacing.pagePadding,
                    children: <Widget>[
                      if (visible.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.xxxl,
                          ),
                          child: Text(
                            l10n.customersNoResultsTitle,
                            textAlign: TextAlign.center,
                            style: context.textStyles.titleMedium,
                          ),
                        ),
                      for (final ManagedCustomer customer in visible) ...[
                        _CustomerCard(
                          customer: customer,
                          isBusy: state.busyCustomerId == customer.id,
                          isAnyBusy: state.isBusy,
                          onOpenDetails: () => _pushNamedAndReload(
                            context,
                            'adminCustomerDetails',
                            customer.id,
                          ),
                          onEdit: () => _pushNamedAndReload(
                            context,
                            'adminCustomerEdit',
                            customer.id,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One customer row: details, state and the management actions.
class _CustomerCard extends StatelessWidget {
  const _CustomerCard({
    required this.customer,
    required this.isBusy,
    required this.isAnyBusy,
    required this.onOpenDetails,
    required this.onEdit,
  });

  final ManagedCustomer customer;
  final bool isBusy;
  final bool isAnyBusy;

  /// Opens the details page and refreshes the list on return.
  final VoidCallback onOpenDetails;

  /// Opens the edit form and refreshes the list on return.
  final VoidCallback onEdit;

  Future<void> _confirmAndRun(
    BuildContext context,
    AdminAccountStatus status,
    String title,
    String body,
    bool isDestructive,
  ) async {
    final AppLocalizations l10n = context.l10n;
    final AdminCustomersCubit cubit = context.read<AdminCustomersCubit>();

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
    final String cityLine = customer.cityLine;
    final String addressLine = cityLine.isEmpty
        ? customer.address.trim()
        : '${customer.address.trim()}, $cityLine';

    return Card(
      key: Key('admin_customer_row_${customer.id}'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpenDetails,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      customer.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textStyles.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  AdminAccountStatusBadge(status: customer.status),
                ],
              ),
              if (addressLine.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  addressLine,
                  style: context.textStyles.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ],
              if ((customer.phone ?? '').trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  customer.phone!.trim(),
                  style: context.textStyles.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.xs),
              Text(
                l10n.adminCustomerJobsCountLabel(customer.jobsCount),
                style: context.textStyles.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              if (isBusy) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                const LinearProgressIndicator(),
              ],
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: <Widget>[
                  if (customer.canBeEdited)
                    OutlinedButton.icon(
                      key: Key('admin_customer_edit_${customer.id}'),
                      onPressed: isAnyBusy ? null : onEdit,
                      icon: const Icon(
                        Icons.edit_outlined,
                        size: AppDimensions.iconMd,
                      ),
                      label: Text(l10n.editCustomer),
                    ),
                  if (customer.canBeBlocked)
                    OutlinedButton.icon(
                      key: Key('admin_customer_block_${customer.id}'),
                      onPressed: isAnyBusy
                          ? null
                          : () => _confirmAndRun(
                              context,
                              AdminAccountStatus.blocked,
                              l10n.adminBlockCustomerConfirmTitle,
                              l10n.adminBlockCustomerConfirmBody(
                                customer.name,
                              ),
                              true,
                            ),
                      icon: const Icon(
                        Icons.block_outlined,
                        size: AppDimensions.iconMd,
                      ),
                      label: Text(l10n.adminBlockAction),
                    ),
                  if (customer.canBeUnblocked)
                    FilledButton.icon(
                      key: Key('admin_customer_unblock_${customer.id}'),
                      onPressed: isAnyBusy
                          ? null
                          : () => _confirmAndRun(
                              context,
                              AdminAccountStatus.active,
                              l10n.adminUnblockCustomerConfirmTitle,
                              l10n.adminUnblockCustomerConfirmBody(
                                customer.name,
                              ),
                              false,
                            ),
                      icon: const Icon(
                        Icons.lock_open_outlined,
                        size: AppDimensions.iconMd,
                      ),
                      label: Text(l10n.adminUnblockAction),
                    ),
                  if (customer.canBeDeleted)
                    TextButton.icon(
                      key: Key('admin_customer_delete_${customer.id}'),
                      onPressed: isAnyBusy
                          ? null
                          : () => _confirmAndRun(
                              context,
                              AdminAccountStatus.deleted,
                              l10n.adminDeleteCustomerConfirmTitle,
                              l10n.adminDeleteCustomerConfirmBody(
                                customer.name,
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
          ),
        ),
      ),
    );
  }
}

class _NoCustomers extends StatelessWidget {
  const _NoCustomers({required this.onCreate});

  final VoidCallback onCreate;

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
              Icons.people_outline,
              size: AppDimensions.iconXl,
              color: AppColors.goldDeep,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              l10n.adminCustomersEmptyTitle,
              textAlign: TextAlign.center,
              style: context.textStyles.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.adminCustomersEmptySubtitle,
              textAlign: TextAlign.center,
              style: context.textStyles.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              key: const Key('admin_customers_empty_create'),
              onPressed: onCreate,
              icon: const Icon(Icons.add, size: AppDimensions.iconMd),
              label: Text(l10n.addCustomer),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomersError extends StatelessWidget {
  const _CustomersError({required this.message, required this.onRetry});

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
              l10n.adminLoadFailedTitle,
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

/// Rounded info banner reused by the details and form pages.
class AdminInfoBanner extends StatelessWidget {
  const AdminInfoBanner({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: AppSpacing.bannerPadding,
      decoration: BoxDecoration(
        color: AppColors.primarySurface,
        borderRadius: AppRadius.banner,
      ),
      child: Text(text, style: context.textStyles.bodyMedium),
    );
  }
}
