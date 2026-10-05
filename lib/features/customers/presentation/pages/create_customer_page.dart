import 'package:field_service/app/di/injection.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/features/customers/presentation/cubit/customers_cubit.dart';
import 'package:field_service/features/customers/presentation/cubit/customers_state.dart';
import 'package:field_service/features/customers/presentation/widgets/customer_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// Create-customer screen (admin only by UI + RLS).
///
/// The page is intentionally thin: [CustomerForm] owns all field/validation
/// logic; submitting goes through the feature Cubit into the repository,
/// which writes to Drift + the sync queue synchronously enough for the list
/// to show the new customer before this page pops — with or without a
/// network. The remote push happens afterwards via the shared sync engine.
class CreateCustomerPage extends StatelessWidget {
  const CreateCustomerPage({super.key, this.cubit});

  /// Test/DI seam (see [CustomersPage]).
  final CustomersCubit? cubit;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<CustomersCubit>(
      create: (_) => cubit ?? sl<CustomersCubit>(),
      child: const _CreateCustomerForm(),
    );
  }
}

class _CreateCustomerForm extends StatelessWidget {
  const _CreateCustomerForm();

  Future<void> _submit(BuildContext context, CustomerFormData data) async {
    final AppLocalizations l10n = context.l10n;
    final CustomersCubit cubit = context.read<CustomersCubit>();

    final bool created = await cubit.createCustomer(
      name: data.name,
      address: data.address,
      phone: data.phone,
      email: data.email,
      city: data.city,
      postalCode: data.postalCode,
      notes: data.notes,
    );

    if (!created) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.customerSaveFailed)));
      return;
    }

    if (context.mounted) {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.addCustomer)),
      body: SafeArea(
        child: ListView(
          padding: AppSpacing.pagePadding,
          children: <Widget>[
            BlocBuilder<CustomersCubit, CustomersState>(
              buildWhen: (CustomersState a, CustomersState b) =>
                  a.isSaving != b.isSaving,
              builder: (BuildContext context, CustomersState state) =>
                  CustomerForm(
                    submitLabel: l10n.saveButton,
                    isBusy: state.isSaving,
                    onSubmit: (CustomerFormData data) => _submit(context, data),
                    onCancel: () => context.pop(),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
