import 'package:field_service/app/di/injection.dart';
import 'package:field_service/app/router/app_routes.dart';
import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/sync/sync_status_cubit.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/core/widgets/language_switcher.dart';
import 'package:field_service/features/authentication/presentation/cubit/authentication_cubit.dart';
import 'package:field_service/features/customers/domain/entities/customer.dart';
import 'package:field_service/features/customers/presentation/cubit/customers_cubit.dart';
import 'package:field_service/features/customers/presentation/cubit/customers_state.dart';
import 'package:field_service/features/customers/presentation/widgets/customer_card.dart';
import 'package:field_service/features/customers/presentation/widgets/customer_empty_state.dart';
import 'package:field_service/features/customers/presentation/widgets/customer_search_field.dart';
import 'package:field_service/features/customers/presentation/widgets/customer_sync_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// Customers list — the feature's offline-first front door.
///
/// Data flow (never blocked on the network):
/// 1. `CustomersCubit.loadCustomers` emits the Drift snapshot immediately;
/// 2. the remote pull runs afterwards and updates the same stream;
/// 3. with no internet, step 2 is a no-op and the local list simply shows.
///
/// Role behavior: Customers is **admin-only**. The router guard refuses
/// every `/customers` route for non-admin roles (so a technician never
/// builds this page and never reads the Drift mirror); the technician
/// dashboard exposes no entry point either. Supabase RLS remains the
/// security boundary — this is the in-app layer on top of it.
class CustomersPage extends StatelessWidget {
  const CustomersPage({super.key, this.customersCubit, this.syncStatusCubit});

  /// Test/DI seam: inject pre-wired cubits (widget tests); `null` resolves
  /// the configured instances from the service locator, like `JobsPage`.
  final CustomersCubit? customersCubit;
  final SyncStatusCubit? syncStatusCubit;

  @override
  Widget build(BuildContext context) {
    final bool isAdmin = context.select<AuthenticationCubit, bool>(
      (AuthenticationCubit cubit) => cubit.state.user?.isAdmin ?? false,
    );

    return MultiBlocProvider(
      // Elements type inferred (nested's SingleChildWidget is not a direct
      // dependency of this package, so it must not be named here).
      providers: [
        BlocProvider<CustomersCubit>(
          create: (_) => customersCubit ?? sl<CustomersCubit>()
            ..loadCustomers(),
        ),
        BlocProvider<SyncStatusCubit>(
          create: (_) => syncStatusCubit ?? sl<SyncStatusCubit>(),
        ),
      ],
      child: _CustomersPageView(isAdmin: isAdmin),
    );
  }
}

class _CustomersPageView extends StatefulWidget {
  const _CustomersPageView({required this.isAdmin});

  final bool isAdmin;

  @override
  State<_CustomersPageView> createState() => _CustomersPageViewState();
}

class _CustomersPageViewState extends State<_CustomersPageView> {
  String _query = '';

  List<Customer> _applySearch(List<Customer> customers) {
    if (_query.isEmpty) {
      return customers;
    }

    final String needle = _query.toLowerCase();
    bool matches(Customer customer) {
      return customer.name.toLowerCase().contains(needle) ||
          (customer.phone?.toLowerCase().contains(needle) ?? false) ||
          (customer.address.toLowerCase().contains(needle)) ||
          (customer.city?.toLowerCase().contains(needle) ?? false);
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
        title: Text(l10n.customersTitle),
        actions: <Widget>[
          const CustomerSyncStatusBar(),
          const Padding(
            padding: EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.sm),
            child: Center(child: LanguageSwitcher()),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      // Admin-only feature (router guard refuses non-admins every
      // `/customers` route); the check stays as defense in depth, and RLS
      // rejects unauthorized writes server-side regardless.
      floatingActionButton: widget.isAdmin
          ? FloatingActionButton(
              key: const Key('add_customer_fab'),
              tooltip: l10n.addCustomer,
              onPressed: () => context.push(AppRoutes.customerCreate),
              child: const Icon(Icons.add, size: AppDimensions.iconLg),
            )
          : null,
      body: BlocBuilder<CustomersCubit, CustomersState>(
        builder: (BuildContext context, CustomersState state) {
          final CustomersCubit cubit = context.read<CustomersCubit>();

          switch (state.status) {
            case CustomersStatus.initial:
            case CustomersStatus.loading:
              return const Center(child: CircularProgressIndicator());

            case CustomersStatus.failure:
              return _CustomersErrorView(onRetry: cubit.loadCustomers);

            case CustomersStatus.success:
              final List<Customer> visible = _applySearch(state.customers);

              return Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.sm,
                      AppSpacing.lg,
                      AppSpacing.xs,
                    ),
                    child: CustomerSearchField(
                      onQueryChanged: (String query) =>
                          setState(() => _query = query),
                    ),
                  ),
                  Expanded(
                    child: RefreshIndicator(
                      // Pull-to-refresh stays offline-first: `refresh` only
                      // re-pulls the remote rows into Drift (a no-op while
                      // offline) and never blanks the list.
                      onRefresh: cubit.refresh,
                      child: visible.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: <Widget>[
                                SizedBox(
                                  height:
                                      MediaQuery.sizeOf(context).height * 0.55,
                                  child: CustomerEmptyState(
                                    queryActive: _query.isNotEmpty,
                                  ),
                                ),
                              ],
                            )
                          : ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: AppSpacing.pagePadding,
                              itemCount: visible.length,
                              separatorBuilder: (
                                BuildContext context,
                                int index,
                              ) => const SizedBox(height: AppSpacing.sm),
                              itemBuilder: (BuildContext context, int index) {
                                final Customer customer = visible[index];
                                return CustomerCard(
                                  customer: customer,
                                  onTap: () => context.pushNamed(
                                    'customerDetails',
                                    pathParameters: <String, String>{
                                      'id': customer.id,
                                    },
                                  ),
                                );
                              },
                            ),
                    ),
                  ),
                ],
              );
          }
        },
      ),
    );
  }
}

/// Centered error placeholder with a retry action (page-private, mirrors
/// `JobsErrorState` for the customers feed).
class _CustomersErrorView extends StatelessWidget {
  const _CustomersErrorView({required this.onRetry});

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
              l10n.customersErrorTitle,
              textAlign: TextAlign.center,
              style: context.textStyles.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.customersErrorSubtitle,
              textAlign: TextAlign.center,
              style: context.textStyles.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton(
              onPressed: () => onRetry(),
              child: Text(l10n.tryAgainButton),
            ),
          ],
        ),
      ),
    );
  }
}
