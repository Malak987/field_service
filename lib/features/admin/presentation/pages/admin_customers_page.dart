import 'package:field_service/app/di/injection.dart';
import 'package:field_service/app/router/app_routes.dart';
import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_colors.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_radius.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/core/widgets/app_page_body.dart';
import 'package:field_service/core/widgets/app_standard_page_header.dart';
import 'package:field_service/core/widgets/app_status_badge.dart';
import 'package:field_service/features/admin/domain/entities/admin_account_status.dart';
import 'package:field_service/features/admin/domain/entities/admin_failure.dart';
import 'package:field_service/features/admin/domain/entities/managed_customer.dart';
import 'package:field_service/features/admin/presentation/cubit/admin_customers_cubit.dart';
import 'package:field_service/features/admin/presentation/utils/admin_management_labels.dart';
import 'package:field_service/features/admin/presentation/widgets/admin_account_status_badge.dart';
import 'package:field_service/features/admin/presentation/widgets/admin_confirm_dialog.dart';
import 'package:field_service/features/authentication/presentation/widgets/auth_logo.dart';
import 'package:field_service/features/customers/presentation/widgets/customer_search_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// The admin's customer management directory (route `/admin/customers`).
///
/// The router refuses this screen for non-admin roles and the management RPCs
/// enforce that same boundary. This widget only presents the already-authorized
/// customer records and existing management actions.
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

  /// Pushes a child screen and reloads the directory on return. Customer forms
  /// own a separate cubit, so this keeps the visible list current without
  /// changing any persistence or management behaviour.
  Future<void> _pushAndReload(BuildContext context, String route) async {
    final AdminCustomersCubit cubit = context.read<AdminCustomersCubit>();
    await context.push(route);
    if (!mounted || cubit.isClosed) {
      return;
    }
    await cubit.load();
  }

  Widget _buildCustomerCard(
    BuildContext context,
    AdminCustomersState state,
    ManagedCustomer customer,
  ) {
    return _CustomerCard(
      customer: customer,
      isBusy: state.busyCustomerId == customer.id,
      isAnyBusy: state.isBusy,
      onOpenDetails: () =>
          _pushNamedAndReload(context, 'adminCustomerDetails', customer.id),
      onEdit: () =>
          _pushNamedAndReload(context, 'adminCustomerEdit', customer.id),
    );
  }

  Future<void> _pushNamedAndReload(
    BuildContext context,
    String name,
    String customerId,
  ) async {
    final AdminCustomersCubit cubit = context.read<AdminCustomersCubit>();
    await context.pushNamed(
      name,
      pathParameters: <String, String>{'id': customerId},
    );
    if (!mounted || cubit.isClosed) {
      return;
    }
    await cubit.load();
  }

  /// Client-side search across exactly the data already supported by the
  /// existing list: name, phone, email, address, city and postal code.
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
      // The logo-led directory header below is the screen title. The app bar
      // remains navigation chrome, keeping the back action compact on phones.
      appBar: AppBar(
        leading: BackButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(AppRoutes.root),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('admin_add_customer_fab'),
        tooltip: l10n.addCustomer,
        onPressed: () =>
            _pushAndReload(context, AppRoutes.adminCustomerCreate),
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: Text(l10n.addCustomer),
      ),
      body: BlocBuilder<AdminCustomersCubit, AdminCustomersState>(
        builder: (BuildContext context, AdminCustomersState state) {
          final AdminCustomersCubit cubit = context.read<AdminCustomersCubit>();
          final List<ManagedCustomer> visible = _applySearch(state.customers);

          return LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double width = constraints.maxWidth;
              final EdgeInsetsDirectional horizontalPadding =
                  AppPageGutter.forWidth(width);

              return Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AppDimensions.wideContentMaxWidth,
                  ),
                  child: SafeArea(
                    child: Column(
                      children: <Widget>[
                        Padding(
                          padding: horizontalPadding,
                          child: _CustomersHeader(
                            title: l10n.adminCustomersTitle,
                            subtitle: l10n.adminCustomersTileSubtitle,
                            countLabel: l10n.customersCountLabel(
                              state.customers.length,
                            ),
                          ),
                        ),
                        if (state.hasCustomers)
                          Padding(
                            padding: AppPageGutter.withVertical(
                              width,
                              top: 0,
                              bottom: AppSpacing.md,
                            ),
                            child: _SearchPanel(
                              child: CustomerSearchField(
                                onQueryChanged: (String query) =>
                                    setState(() => _query = query),
                              ),
                            ),
                          ),
                        Expanded(
                          child: _buildBody(
                            context,
                            state,
                            visible,
                            cubit,
                            horizontalPadding,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AdminCustomersState state,
    List<ManagedCustomer> visible,
    AdminCustomersCubit cubit,
    EdgeInsetsGeometry padding,
  ) {
    final AppLocalizations l10n = context.l10n;

    final bool isInitialLoad =
        state.status == AdminCustomersStatus.initial ||
        state.status == AdminCustomersStatus.loading;
    if (isInitialLoad && !state.hasCustomers) {
      return Center(
        child: Semantics(
          label: l10n.adminCustomersLoadingLabel,
          child: const CircularProgressIndicator(),
        ),
      );
    }

    if (state.status == AdminCustomersStatus.failure && !state.hasCustomers) {
      return _CustomersError(
        message: adminFailureMessage(
          l10n,
          state.loadFailure ?? AdminFailureKind.unknown,
        ),
        onRetry: cubit.load,
      );
    }

    if (state.status == AdminCustomersStatus.success && !state.hasCustomers) {
      return _NoCustomers(
        onCreate: () => _pushAndReload(
          context,
          AppRoutes.adminCustomerCreate,
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: cubit.load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: padding,
        children: <Widget>[
          if (state.status == AdminCustomersStatus.loading) ...<Widget>[
            const LinearProgressIndicator(),
            const SizedBox(height: AppSpacing.md),
          ],
          if (visible.isEmpty)
            _NoSearchResults()
          else
            for (final ManagedCustomer customer in visible) ...<Widget>[
              _buildCustomerCard(context, state, customer),
              const SizedBox(height: AppSpacing.md),
            ],
          // Keeps the final customer clear of the extended creation FAB.
          const SizedBox(height: AppSpacing.huge),
        ],
      ),
    );
  }
}

class _CustomersHeader extends StatelessWidget {
  const _CustomersHeader({
    required this.title,
    required this.subtitle,
    required this.countLabel,
  });

  final String title;
  final String subtitle;
  final String countLabel;

  @override
  Widget build(BuildContext context) => AppStandardPageHeader(
    logoAssetName: AuthLogo.assetName,
    title: title,
    subtitle: subtitle,
    supporting: AppStatusBadge(
      icon: Icons.people_outline_rounded,
      label: countLabel,
      tone: AppStatusTone.brand,
    ),
  );
}

class _SearchPanel extends StatelessWidget {
  const _SearchPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.card,
        side: BorderSide(color: context.colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xs),
        child: child,
      ),
    );
  }
}

/// One administrative customer card. It holds no customer logic: navigation,
/// status mutation and confirmation callbacks are supplied by the existing
/// page and Cubit flows.
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
  final VoidCallback onOpenDetails;
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
    final List<_CustomerFact> facts = _facts();

    return Material(
      color: context.colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.card,
        side: BorderSide(color: context.colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('admin_customer_row_${customer.id}'),
        onTap: onOpenDetails,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _CustomerAvatar(name: customer.name),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          customer.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.textStyles.titleMedium,
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          l10n.adminCustomerJobsCountLabel(customer.jobsCount),
                          style: context.textStyles.bodySmall?.copyWith(
                            color: context.colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      AdminAccountStatusBadge(status: customer.status),
                      const SizedBox(height: AppSpacing.xs),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: AppDimensions.iconMd,
                        color: context.colors.onSurfaceVariant,
                      ),
                    ],
                  ),
                ],
              ),
              if (facts.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                Divider(height: 1, color: context.colors.outlineVariant),
                const SizedBox(height: AppSpacing.md),
                for (final _CustomerFact fact in facts) ...<Widget>[
                  _CustomerFactLine(fact: fact),
                  if (fact != facts.last)
                    const SizedBox(height: AppSpacing.xs),
                ],
              ],
              if (isBusy) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                const LinearProgressIndicator(),
              ],
              const SizedBox(height: AppSpacing.md),
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
                              l10n.adminBlockCustomerConfirmBody(customer.name),
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

  List<_CustomerFact> _facts() {
    final String address = customer.address.trim();
    final String city = customer.cityLine;
    final String addressLine = city.isEmpty ? address : '$address, $city';
    final String phone = customer.phone?.trim() ?? '';
    final String email = customer.email?.trim() ?? '';

    return <_CustomerFact>[
      if (phone.isNotEmpty)
        _CustomerFact(icon: Icons.phone_outlined, value: phone),
      if (email.isNotEmpty)
        _CustomerFact(icon: Icons.mail_outline_rounded, value: email),
      if (addressLine.isNotEmpty)
        _CustomerFact(icon: Icons.place_outlined, value: addressLine),
    ];
  }
}

class _CustomerAvatar extends StatelessWidget {
  const _CustomerAvatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final String initials = _initials(name);

    return Semantics(
      label: name,
      child: ExcludeSemantics(
        child: Container(
          width: AppDimensions.buttonHeightCompact,
          height: AppDimensions.buttonHeightCompact,
          decoration: const BoxDecoration(
            color: AppColors.primarySurface,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: initials.isEmpty
              ? const Icon(
                  Icons.person_outline_rounded,
                  size: AppDimensions.iconMd,
                  color: AppColors.primary,
                )
              : Text(
                  initials,
                  style: context.textStyles.labelMedium?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ),
    );
  }

  String _initials(String value) {
    final List<String> words = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((String word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty) {
      return '';
    }
    return words.take(2).map((String word) => word[0]).join().toUpperCase();
  }
}

class _CustomerFact {
  const _CustomerFact({required this.icon, required this.value});

  final IconData icon;
  final String value;
}

class _CustomerFactLine extends StatelessWidget {
  const _CustomerFactLine({required this.fact});

  final _CustomerFact fact;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(
          fact.icon,
          size: AppDimensions.iconSm,
          color: context.colors.onSurfaceVariant,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            fact.value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: context.textStyles.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _NoSearchResults extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
      child: Column(
        children: <Widget>[
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: AppColors.surfaceMuted,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.search_off_rounded,
              size: AppDimensions.iconLg,
              color: context.colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            context.l10n.customersNoResultsTitle,
            textAlign: TextAlign.center,
            style: context.textStyles.titleMedium,
          ),
        ],
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
        padding: AppPageGutter.forWidth(MediaQuery.sizeOf(context).width),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AppColors.goldSurface,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.people_outline_rounded,
                size: AppDimensions.iconLg,
                color: AppColors.goldDeep,
              ),
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
              style: context.textStyles.bodyMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              key: const Key('admin_customers_empty_create'),
              onPressed: onCreate,
              icon: const Icon(Icons.person_add_alt_1_outlined),
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
        padding: AppPageGutter.forWidth(MediaQuery.sizeOf(context).width),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AppColors.errorSurface,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.error_outline_rounded,
                size: AppDimensions.iconLg,
                color: context.colors.error,
              ),
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
              style: context.textStyles.bodyMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              key: const Key('admin_list_retry'),
              onPressed: () => onRetry(),
              icon: const Icon(Icons.refresh_rounded),
              label: Text(l10n.tryAgainButton),
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
