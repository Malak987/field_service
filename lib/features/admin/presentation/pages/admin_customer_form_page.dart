import 'package:field_service/app/di/injection.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/features/admin/domain/entities/admin_account_status.dart';
import 'package:field_service/features/admin/domain/entities/managed_customer.dart';
import 'package:field_service/features/admin/presentation/cubit/admin_customers_cubit.dart';
import 'package:field_service/features/admin/presentation/utils/admin_management_labels.dart';
import 'package:field_service/features/customers/domain/entities/customer.dart';
import 'package:field_service/features/customers/domain/entities/customer_sync_status.dart';
import 'package:field_service/features/customers/presentation/widgets/customer_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// Create **and** edit form of the customer management area.
///
/// Routes: `/admin/customers/create` (no [customerId]) and
/// `/admin/customers/:id/edit` ([customerId] set).
///
/// The field/validation layer is the EXISTING [CustomerForm] (create and edit
/// share it in the Customers feature too), so both admin paths validate exactly
/// like the offline-first ones; the write goes through the management RPCs
/// (`admin_create_customer` / `admin_update_customer`), which validate and stamp
/// the row server-side.
class AdminCustomerFormPage extends StatelessWidget {
  const AdminCustomerFormPage({super.key, this.customerId, this.cubit});

  /// `customers.id` to edit; `null` for the create form.
  final String? customerId;

  /// Test seam: inject a pre-wired cubit.
  final AdminCustomersCubit? cubit;

  @override
  Widget build(BuildContext context) {
    final String? id = customerId;
    return BlocProvider<AdminCustomersCubit>(
      create: (_) {
        final AdminCustomersCubit resolved = cubit ?? sl<AdminCustomersCubit>();
        if (id != null) {
          resolved.loadCustomer(id);
        }
        return resolved;
      },
      child: _AdminCustomerFormView(customerId: customerId),
    );
  }
}

class _AdminCustomerFormView extends StatelessWidget {
  const _AdminCustomerFormView({required this.customerId});

  final String? customerId;

  Future<void> _submit(
    BuildContext context,
    CustomerFormData data, {
    String? existingId,
  }) async {
    final AppLocalizations l10n = context.l10n;
    final AdminCustomersCubit cubit = context.read<AdminCustomersCubit>();

    final AdminFailureKind? failure = existingId == null
        ? await cubit.createCustomer(
            name: data.name,
            address: data.address,
            phone: data.phone,
            email: data.email,
            city: data.city,
            postalCode: data.postalCode,
            notes: data.notes,
          )
        : await cubit.updateCustomer(
            customerId: existingId,
            name: data.name,
            address: data.address,
            phone: data.phone,
            email: data.email,
            city: data.city,
            postalCode: data.postalCode,
            notes: data.notes,
          );

    if (!context.mounted) {
      return;
    }

    if (failure != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(adminFailureMessage(l10n, failure))),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          existingId == null
              ? l10n.adminCustomerCreatedMessage
              : l10n.adminCustomerUpdatedMessage,
        ),
      ),
    );
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final String? id = customerId;

    return Scaffold(
      appBar: AppBar(
        title: Text(id == null ? l10n.addCustomer : l10n.editCustomer),
      ),
      body: SafeArea(
        child: BlocBuilder<AdminCustomersCubit, AdminCustomersState>(
          builder: (BuildContext context, AdminCustomersState state) {
            if (id != null && state.isCustomerLoading) {
              return Center(
                child: Semantics(
                  label: l10n.adminCustomersLoadingLabel,
                  child: const CircularProgressIndicator(),
                ),
              );
            }

            final ManagedCustomer? existing = state.selectedCustomer;
            if (id != null && existing == null) {
              return Center(
                child: Padding(
                  padding: AppSpacing.pagePadding,
                  child: Text(
                    adminFailureMessage(
                      l10n,
                      state.loadFailure ?? AdminFailureKind.notFound,
                    ),
                    textAlign: TextAlign.center,
                    style: context.textStyles.bodyMedium,
                  ),
                ),
              );
            }

            return ListView(
              padding: AppSpacing.pagePadding,
              children: <Widget>[
                CustomerForm(
                  key: Key('admin_customer_form_${id ?? 'new'}'),
                  initial: existing == null ? null : _asCustomer(existing),
                  submitLabel: l10n.saveButton,
                  isBusy: state.isBusy,
                  onSubmit: (CustomerFormData data) =>
                      _submit(context, data, existingId: existing?.id),
                  onCancel: () => context.pop(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// The existing [CustomerForm] works on the Customers feature entity; the
  /// management row is mapped onto it so both forms stay literally the same —
  /// only the persistence path differs (server RPC instead of Drift + queue).
  Customer _asCustomer(ManagedCustomer customer) {
    final DateTime fallback = DateTime.now();
    return Customer(
      id: customer.id,
      name: customer.name,
      address: customer.address,
      phone: customer.phone,
      email: customer.email,
      city: customer.city,
      postalCode: customer.postalCode,
      notes: customer.notes,
      createdAt: customer.createdAt ?? fallback,
      updatedAt: customer.updatedAt ?? fallback,
      syncStatus: CustomerSyncStatus.synced,
    );
  }
}
