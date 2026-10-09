import 'package:field_service/app/di/injection.dart';
import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_radius.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/features/authentication/presentation/cubit/authentication_cubit.dart';
import 'package:field_service/features/customers/domain/entities/customer.dart';
import 'package:field_service/features/customers/presentation/cubit/customers_cubit.dart';
import 'package:field_service/features/customers/presentation/cubit/customers_state.dart';
import 'package:field_service/features/customers/presentation/utils/customers_date_format.dart';
import 'package:field_service/features/customers/presentation/widgets/customer_sync_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// Customer details — a read view over the local Drift row.
///
/// Renders from the `watchCustomerById` stream, so the screen works fully
/// offline, updates live after a local edit, and its sync chip flips when
/// the queued operation reaches the backend.
///
/// Customers is **admin-only**: the router guard refuses every `/customers`
/// route (including this details page) for non-admin roles, and Supabase
/// RLS remains the security boundary on top of that.
class CustomerDetailsPage extends StatelessWidget {
  const CustomerDetailsPage({super.key, required this.customerId, this.cubit});

  /// The client-generated customer UUID (also the remote primary key).
  final String customerId;

  /// Test/DI seam (see [CustomersPage]).
  final CustomersCubit? cubit;

  @override
  Widget build(BuildContext context) {
    final bool isAdmin = context.select<AuthenticationCubit, bool>(
      (AuthenticationCubit cubit) => cubit.state.user?.isAdmin ?? false,
    );

    return BlocProvider<CustomersCubit>(
      create: (_) => cubit ?? sl<CustomersCubit>()
        ..loadCustomer(customerId),
      child: CustomerDetailsView(customerId: customerId, isAdmin: isAdmin),
    );
  }
}

class CustomerDetailsView extends StatelessWidget {
  const CustomerDetailsView({
    super.key,
    required this.customerId,
    required this.isAdmin,
  });

  final String customerId;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.customerTitle)),
      body: BlocBuilder<CustomersCubit, CustomersState>(
        builder: (BuildContext context, CustomersState state) {
          switch (state.status) {
            case CustomersStatus.initial:
            case CustomersStatus.loading:
              return const Center(child: CircularProgressIndicator());

            case CustomersStatus.failure:
              return _DetailsErrorView(
                onRetry: () =>
                    context.read<CustomersCubit>().loadCustomer(customerId),
              );

            case CustomersStatus.success:
              final Customer? customer = state.selectedCustomer;
              if (customer == null) {
                return const _CustomerNotFoundView();
              }
              return _CustomerDetailsBody(
                customer: customer,
                isAdmin: isAdmin,
                onEdit: () => context.pushNamed(
                  'customerEdit',
                  pathParameters: <String, String>{'id': customer.id},
                ),
                onDelete: () => _confirmDelete(context, customer),
              );
          }
        },
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, Customer customer) async {
    final AppLocalizations l10n = context.l10n;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        key: const Key('delete_customer_dialog'),
        title: Text(l10n.deleteCustomer),
        content: Text(l10n.deleteCustomerConfirmation(customer.name)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancelButton),
          ),
          FilledButton(
            key: const Key('delete_customer_confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: dialogContext.colors.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.deleteButton),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    final CustomerDeleteOutcome outcome = await context
        .read<CustomersCubit>()
        .deleteCustomer(customer.id);
    if (!context.mounted) {
      return;
    }

    switch (outcome) {
      case CustomerDeleteOutcome.success:
        // Leave the (now deleted) record behind; the list stream already
        // reflects the removal on this and other screens.
        if (GoRouter.maybeOf(context) != null) {
          context.pop();
        } else {
          Navigator.of(context).pop();
        }
      case CustomerDeleteOutcome.linkedToJobs:
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.customerLinkedJobsError)));
      case CustomerDeleteOutcome.failure:
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.customerSaveFailed)));
    }
  }
}

class _CustomerDetailsBody extends StatelessWidget {
  const _CustomerDetailsBody({
    required this.customer,
    required this.isAdmin,
    required this.onEdit,
    required this.onDelete,
  });

  final Customer customer;
  final bool isAdmin;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final String cityLine = customer.cityLine;

    return ListView(
      padding: AppSpacing.pagePadding,
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: <Widget>[
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: context.colors.primaryContainer,
                    borderRadius: AppRadius.card,
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.person_outline_rounded,
                    size: AppDimensions.iconLg,
                    color: context.colors.primary,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        customer.name,
                        style: context.textStyles.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (cityLine.isNotEmpty) ...<Widget>[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          cityLine,
                          style: context.textStyles.bodyMedium?.copyWith(
                            color: context.colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.sm),
                      CustomerSyncStatusChip(status: customer.syncStatus),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if ((customer.phone ?? '').trim().isNotEmpty ||
            (customer.email ?? '').trim().isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          _CustomerDetailsSection(
            icon: Icons.contact_mail_outlined,
            title: l10n.customerContactGroup,
            children: <Widget>[
              _DetailField(label: l10n.customerPhoneLabel, value: customer.phone),
              _DetailField(label: l10n.customerEmailLabel, value: customer.email),
            ],
          ),
        ],
        if (customer.address.trim().isNotEmpty || cityLine.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          _CustomerDetailsSection(
            icon: Icons.place_outlined,
            title: l10n.customerAddressGroup,
            children: <Widget>[
              _DetailField(
                label: l10n.customerAddressLabel,
                value: customer.address,
              ),
              _DetailField(
                label: l10n.customerCityLabel,
                value: cityLine.isEmpty ? null : cityLine,
              ),
            ],
          ),
        ],
        if ((customer.notes ?? '').trim().isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          _CustomerDetailsSection(
            icon: Icons.notes_rounded,
            title: l10n.customerNotesGroup,
            children: <Widget>[
              _DetailField(label: l10n.customerNotesLabel, value: customer.notes),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final bool sideBySide = constraints.maxWidth >= 400;
                    final Widget created = _DetailField(
                      label: l10n.createdAtLabel,
                      value: formatCustomerDate(customer.createdAt, context),
                    );
                    final Widget updated = _DetailField(
                      label: l10n.updatedAtLabel,
                      value: formatCustomerDate(customer.updatedAt, context),
                    );
                    if (!sideBySide) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[created, updated],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(child: created),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(child: updated),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        // Admin-only mutations. Technicians see no action row at all.
        if (isAdmin) ...<Widget>[
          FilledButton.icon(
            key: const Key('edit_customer_button'),
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: AppDimensions.iconMd),
            label: Text(l10n.editCustomer),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            key: const Key('delete_customer_button'),
            onPressed: onDelete,
            style: OutlinedButton.styleFrom(
              foregroundColor: context.colors.error,
              side: BorderSide(color: context.colors.error),
            ),
            icon: const Icon(Icons.delete_outline, size: AppDimensions.iconMd),
            label: Text(l10n.deleteCustomer),
          ),
        ],
      ],
    );
  }
}

class _CustomerDetailsSection extends StatelessWidget {
  const _CustomerDetailsSection({
    required this.icon,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: AppDimensions.iconMd, color: context.colors.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  title,
                  style: context.textStyles.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          ...children,
        ],
      ),
    ),
  );
}

class _DetailField extends StatelessWidget {
  const _DetailField({required this.label, this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    if (value == null || value!.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: context.textStyles.bodySmall),
          const SizedBox(height: AppSpacing.xxs),
          Text(value!, style: context.textStyles.bodyLarge),
        ],
      ),
    );
  }
}

class _CustomerNotFoundView extends StatelessWidget {
  const _CustomerNotFoundView();

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
              Icons.person_off_outlined,
              size: AppDimensions.iconXl,
              color: context.colors.outline,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              l10n.customerNotFoundTitle,
              style: context.textStyles.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.customerNotFoundSubtitle,
              textAlign: TextAlign.center,
              style: context.textStyles.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailsErrorView extends StatelessWidget {
  const _DetailsErrorView({required this.onRetry});

  final VoidCallback onRetry;

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
              style: context.textStyles.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton(onPressed: onRetry, child: Text(l10n.tryAgainButton)),
          ],
        ),
      ),
    );
  }
}
