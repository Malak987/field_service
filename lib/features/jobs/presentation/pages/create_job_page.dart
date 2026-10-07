import 'package:field_service/app/di/injection.dart';
import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/features/customers/domain/entities/customer.dart';
import 'package:field_service/features/employees/domain/entities/employee.dart';
import 'package:field_service/features/jobs/domain/entities/job_category.dart';
import 'package:field_service/features/jobs/presentation/cubit/create_job_cubit.dart';
import 'package:field_service/features/jobs/presentation/cubit/create_job_state.dart';
import 'package:field_service/features/jobs/presentation/utils/job_label_mapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// Admin Create Job screen (route `/jobs/create`, admin-only by router
/// guard + the server-side `create_job` RPC).
///
/// The admin's workflow in one form: select the customer (existing
/// offline-first Customers feature), choose one of the two job categories,
/// describe what the customer requested, pick an ACTIVE technician and
/// Create & Assign. Submission is one server action (`create_job` RPC): the
/// job is created with `status = 'assigned'`, a server-generated job number
/// and a server-stamped `assigned_at` — then it appears in the admin Jobs
/// list and in the assigned technician's My Jobs.
class CreateJobPage extends StatelessWidget {
  const CreateJobPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<CreateJobCubit>(
      create: (_) => sl<CreateJobCubit>()..loadOptions(),
      child: const _CreateJobForm(),
    );
  }
}

class _CreateJobForm extends StatelessWidget {
  const _CreateJobForm();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.createJobButton)),
      body: BlocConsumer<CreateJobCubit, CreateJobState>(
        listenWhen: (CreateJobState previous, CreateJobState current) =>
            previous.createdJob != current.createdJob ||
            previous.error != current.error,
        listener: (BuildContext context, CreateJobState state) {
          if (state.createdJob != null) {
            // Capture l10n + messenger before the async gap of pop().
            final AppLocalizations l10n = context.l10n;
            final ScaffoldMessengerState messenger =
                ScaffoldMessenger.of(context);
            messenger.showSnackBar(
              SnackBar(content: Text(l10n.createJobSuccessMessage)),
            );
            context.pop();
            return;
          }
          if (state.error != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.l10n.createJobFailedMessage)),
            );
          }
        },
        builder: (BuildContext context, CreateJobState state) {
          final AppLocalizations l10n = context.l10n;
          final CreateJobCubit cubit = context.read<CreateJobCubit>();
          final JobLabelMapper mapper = JobLabelMapper(l10n);

          return SafeArea(
            child: ListView(
              padding: AppSpacing.pagePadding,
              children: <Widget>[
                if (state.isLoadingOptions)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.xl),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else ...<Widget>[
                  // --- Customer (existing Customers feature, offline-first)
                  DropdownButtonFormField<String>(
                    key: const Key('create_job_customer_dropdown'),
                    initialValue: state.selectedCustomerId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: l10n.selectCustomerLabel,
                      border: const OutlineInputBorder(),
                      errorText: state.showValidationErrors &&
                              !state.hasCustomer
                          ? l10n.validationRequiredField
                          : null,
                    ),
                    items: <DropdownMenuItem<String>>[
                      for (final Customer customer in state.customers)
                        DropdownMenuItem<String>(
                          value: customer.id,
                          child: Text(customer.name),
                        ),
                    ],
                    onChanged: cubit.selectCustomer,
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // --- Category: EXACTLY the two supported business values.
                  DropdownButtonFormField<String>(
                    key: const Key('create_job_category_dropdown'),
                    initialValue: state.selectedCategory,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: l10n.jobTypeLabel,
                      border: const OutlineInputBorder(),
                      errorText: state.showValidationErrors &&
                              !state.hasCategory
                          ? l10n.validationRequiredField
                          : null,
                    ),
                    items: <DropdownMenuItem<String>>[
                      for (final String value in JobCategory.supportedValues)
                        DropdownMenuItem<String>(
                          value: value,
                          child: Text(mapper.jobTypeLabel(value)),
                        ),
                    ],
                    onChanged: cubit.selectCategory,
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // --- Job description: the admin's note of what the
                  //     customer requested. NOT the technician's future
                  //     Work Details — those stay a separate feature.
                  TextFormField(
                    key: const Key('create_job_description_field'),
                    initialValue: state.description,
                    minLines: 3,
                    maxLines: 6,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: l10n.descriptionLabel,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: cubit.setDescription,
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // --- Technician: active technicians only (never admins,
                  //     never inactive employees — enforced by the query and
                  //     re-validated by the create_job RPC).
                  if (state.technicians.isEmpty)
                    Text(
                      l10n.noActiveTechniciansMessage,
                      style: context.textStyles.bodyMedium,
                    )
                  else
                    DropdownButtonFormField<String>(
                      key: const Key('create_job_technician_dropdown'),
                      initialValue: state.selectedTechnicianId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: l10n.selectTechnicianLabel,
                        border: const OutlineInputBorder(),
                        errorText: state.showValidationErrors &&
                                !state.hasTechnician
                            ? l10n.validationRequiredField
                            : null,
                      ),
                      items: <DropdownMenuItem<String>>[
                        // Display the REAL `employees.name` exactly as
                        // stored in Supabase — never a hardcoded or invented
                        // name. `displayName` falls back to the employee
                        // code only for rows with an unexpectedly empty
                        // name (a logged data problem).
                        for (final Employee employee in state.technicians)
                          DropdownMenuItem<String>(
                            value: employee.id,
                            child: Text(employee.displayName),
                          ),
                      ],
                      onChanged: cubit.selectTechnician,
                    ),
                  const SizedBox(height: AppSpacing.xl),

                  // --- Create & Assign: one server action does both.
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const Key('create_and_assign_job_button'),
                      onPressed: state.isSubmitting
                          ? null
                          : () => _onSubmit(context, cubit),
                      icon: state.isSubmitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_task_rounded),
                      label: Text(l10n.createAndAssignJobButton),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  /// Submits the form. The cubit validates completeness; the server
  /// (`create_job` RPC) is the final authority for every authorization rule.
  Future<void> _onSubmit(BuildContext context, CreateJobCubit cubit) async {
    await cubit.submit();
    // Success/error feedback is delivered by the BlocConsumer listener
    // (snackbar + pop on success) — nothing to do here.
  }
}
