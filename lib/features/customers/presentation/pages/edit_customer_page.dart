import 'package:field_service/app/di/injection.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/features/customers/domain/entities/customer.dart';
import 'package:field_service/features/customers/presentation/cubit/customers_cubit.dart';
import 'package:field_service/features/customers/presentation/cubit/customers_state.dart';
import 'package:field_service/features/customers/presentation/widgets/customer_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// Edit-customer screen (admin only by UI + RLS).
///
/// Pre-fills from the local Drift row (live stream, so even this screen is
/// offline-first on read). Saving produces the updated [Customer] with the
/// **same stable id** — jobs keep referencing it — and the repository queues
/// an `update` operation; no network is required for the save itself.
class EditCustomerPage extends StatelessWidget {
  const EditCustomerPage({super.key, required this.customerId, this.cubit});

  final String customerId;

  /// Test/DI seam (see [CustomersPage]).
  final CustomersCubit? cubit;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<CustomersCubit>(
      create: (_) => cubit ?? sl<CustomersCubit>()..loadCustomer(customerId),
      child: const _EditCustomerForm(),
    );
  }
}

class _EditCustomerForm extends StatelessWidget {
  const _EditCustomerForm();

  Future<void> _submit(
    BuildContext context,
    Customer existing,
    CustomerFormData data,
  ) async {
    final AppLocalizations l10n = context.l10n;
    final CustomersCubit cubit = context.read<CustomersCubit>();

    // Rebuilt explicitly (not copyWith): every optional field must be
    // able to go back to null when the admin clears it.
    final Customer updated = Customer(
      id: existing.id,
      name: data.name,
      address: data.address,
      phone: data.phone,
      email: data.email,
      city: data.city,
      postalCode: data.postalCode,
      notes: data.notes,
      createdAt: existing.createdAt,
      updatedAt: existing.updatedAt,
      syncStatus: existing.syncStatus,
    );

    final bool saved = await cubit.updateCustomer(updated);
    if (!context.mounted) {
      return;
    }

    if (!saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.customerSaveFailed)),
      );
      return;
    }

    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.editCustomer)),
      body: SafeArea(
        child: BlocBuilder<CustomersCubit, CustomersState>(
          buildWhen: (CustomersState a, CustomersState b) =>
              a.selectedCustomer != b.selectedCustomer ||
              a.isSaving != b.isSaving ||
              a.status != b.status,
          builder: (BuildContext context, CustomersState state) {
            final Customer? customer = state.selectedCustomer;

            if (customer == null) {
              return Center(
                child: state.status == CustomersStatus.failure
                    ? Text(l10n.customerNotFoundTitle)
                    : const CircularProgressIndicator(),
              );
            }

            return ListView(
              padding: AppSpacing.pagePadding,
              children: <Widget>[
                CustomerForm(
                  initial: customer,
                  submitLabel: l10n.saveButton,
                  isBusy: state.isSaving,
                  onSubmit: (CustomerFormData data) =>
                      _submit(context, customer, data),
                  onCancel: () => context.pop(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
