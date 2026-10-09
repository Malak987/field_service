import 'package:field_service/app/di/injection.dart';
import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/theme/app_colors.dart';
import 'package:field_service/core/theme/app_radius.dart';
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

import '../../../../core/localization/app_localizations.dart';

/// Admin Create Job screen. Creation and assignment remain one existing
/// server-authorized `create_job` operation; technicians execute assigned jobs.
class CreateJobPage extends StatelessWidget {
  const CreateJobPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider<CreateJobCubit>(
    create: (_) => sl<CreateJobCubit>()..loadOptions(),
    child: const _CreateJobForm(),
  );
}

class _CreateJobForm extends StatefulWidget {
  const _CreateJobForm();

  @override
  State<_CreateJobForm> createState() => _CreateJobFormState();
}

class _CreateJobFormState extends State<_CreateJobForm> {
  Future<void> _selectCustomer(
    BuildContext context,
    CreateJobCubit cubit,
    CreateJobState state,
  ) async {
    final Customer? customer = await showModalBottomSheet<Customer>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext _) => _CustomerPicker(
        customers: state.customers,
        selectedId: state.selectedCustomerId,
      ),
    );
    if (customer != null && context.mounted) cubit.selectCustomer(customer.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.createJobButton)),
      body: BlocConsumer<CreateJobCubit, CreateJobState>(
        listenWhen: (previous, current) =>
            previous.createdJob != current.createdJob ||
            previous.error != current.error,
        listener: (context, state) {
          if (state.createdJob != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.l10n.createJobSuccessMessage)),
            );
            context.pop();
          } else if (state.error != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.l10n.createJobFailedMessage)),
            );
          }
        },
        builder: (context, state) {
          final l10n = context.l10n;
          final cubit = context.read<CreateJobCubit>();
          final mapper = JobLabelMapper(l10n);
          final Customer? selectedCustomer = _findCustomer(
            state.customers,
            state.selectedCustomerId,
          );
          final Employee? selectedTechnician = _findTechnician(
            state.technicians,
            state.selectedTechnicianId,
          );

          return SafeArea(
            child: Column(
              children: <Widget>[
                Expanded(
                  child: ListView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      AppSpacing.lg,
                      AppSpacing.md,
                      AppSpacing.lg,
                      AppSpacing.lg,
                    ),
                    children: <Widget>[
                      _IntroCard(
                        title: l10n.createAndAssignJobButton,
                        subtitle: l10n.createJobIntro,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _SectionTitle(number: '1', title: l10n.selectCustomerLabel),
                      const SizedBox(height: AppSpacing.sm),
                      if (state.isLoadingCustomers && state.customers.isEmpty)
                        const _LoadingOption()
                      else if (state.customerOptionsFailed)
                        _OptionError(
                          message: l10n.createJobOptionsFailedMessage,
                          onRetry: cubit.loadOptions,
                        )
                      else if (state.customers.isEmpty)
                        _OptionEmpty(message: l10n.customersEmptyTitle)
                      else
                        _CustomerSelectionTile(
                          key: const Key('create_job_customer_dropdown'),
                          customer: selectedCustomer,
                          hasError: state.showValidationErrors &&
                              !state.hasCustomer,
                          onTap: state.isSubmitting
                              ? null
                              : () => _selectCustomer(context, cubit, state),
                        ),
                      if (state.showValidationErrors && !state.hasCustomer)
                        _FieldError(message: l10n.validationRequiredField),
                      const SizedBox(height: AppSpacing.lg),
                      _SectionTitle(number: '2', title: l10n.jobTypeLabel),
                      const SizedBox(height: AppSpacing.sm),
                      DropdownButtonFormField<String>(
                        key: const Key('create_job_category_dropdown'),
                        initialValue: state.selectedCategory,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: l10n.jobTypeLabel,
                          prefixIcon: const Icon(Icons.home_repair_service_outlined),
                          errorText: state.showValidationErrors && !state.hasCategory
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
                        onChanged: state.isSubmitting ? null : cubit.selectCategory,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _SectionTitle(number: '3', title: l10n.descriptionLabel),
                      const SizedBox(height: AppSpacing.sm),
                      TextFormField(
                        key: const Key('create_job_description_field'),
                        initialValue: state.description,
                        minLines: 3,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        textInputAction: TextInputAction.newline,
                        enabled: !state.isSubmitting,
                        decoration: InputDecoration(
                          labelText: l10n.descriptionLabel,
                          alignLabelWithHint: true,
                          prefixIcon: const Padding(
                            padding: EdgeInsets.only(bottom: 54),
                            child: Icon(Icons.notes_outlined),
                          ),
                        ),
                        onChanged: cubit.setDescription,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _SectionTitle(number: '4', title: l10n.selectTechnicianLabel),
                      const SizedBox(height: AppSpacing.sm),
                      if (state.isLoadingTechnicians && state.technicians.isEmpty)
                        const _LoadingOption()
                      else if (state.technicianOptionsFailed)
                        _OptionError(
                          message: l10n.createJobOptionsFailedMessage,
                          onRetry: cubit.loadOptions,
                        )
                      else if (state.technicians.isEmpty)
                        _OptionEmpty(message: l10n.noActiveTechniciansMessage)
                      else
                        DropdownButtonFormField<String>(
                          key: const Key('create_job_technician_dropdown'),
                          initialValue: state.selectedTechnicianId,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: l10n.selectTechnicianLabel,
                            prefixIcon: const Icon(Icons.badge_outlined),
                            errorText: state.showValidationErrors && !state.hasTechnician
                                ? l10n.validationRequiredField
                                : null,
                          ),
                          selectedItemBuilder: (context) => state.technicians
                              .map((e) => Align(
                                    alignment: AlignmentDirectional.centerStart,
                                    child: Text(e.displayName, overflow: TextOverflow.ellipsis),
                                  ))
                              .toList(),
                          items: <DropdownMenuItem<String>>[
                            for (final Employee employee in state.technicians)
                              DropdownMenuItem<String>(
                                value: employee.id,
                                child: Text(
                                  employee.employeeCode == null || employee.employeeCode!.trim().isEmpty
                                      ? employee.displayName
                                      : '${employee.displayName} · ${employee.employeeCode}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: state.isSubmitting ? null : cubit.selectTechnician,
                        ),
                      if (selectedCustomer != null ||
                          state.selectedCategory != null ||
                          selectedTechnician != null) ...<Widget>[
                        const SizedBox(height: AppSpacing.xl),
                        Text(
                          l10n.createJobReviewTitle,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.primaryDark,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Container(
                          key: const Key('create_job_selection_review'),
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: AppRadius.card,
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              if (selectedCustomer != null)
                                _SelectionReview(
                                  icon: Icons.person_outline,
                                  text: selectedCustomer.name,
                                  detail: selectedCustomer.phone,
                                ),
                              if (selectedCustomer != null &&
                                  state.selectedCategory != null)
                                const SizedBox(height: AppSpacing.sm),
                              if (state.selectedCategory != null)
                                _SelectionReview(
                                  icon: Icons.home_repair_service_outlined,
                                  text: mapper.jobTypeLabel(state.selectedCategory!),
                                ),
                              if (selectedTechnician != null) ...<Widget>[
                                const SizedBox(height: AppSpacing.sm),
                                _SelectionReview(
                                  icon: Icons.assignment_ind_outlined,
                                  text: selectedTechnician.displayName,
                                  detail: selectedTechnician.employeeCode,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                _SubmitBar(
                  state: state,
                  onSubmit: () => cubit.submit(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Customer? _findCustomer(List<Customer> items, String? id) {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  Employee? _findTechnician(List<Employee> items, String? id) {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }
}

class _CustomerPicker extends StatefulWidget {
  const _CustomerPicker({required this.customers, required this.selectedId});
  final List<Customer> customers;
  final String? selectedId;

  @override
  State<_CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends State<_CustomerPicker> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final media = MediaQuery.of(context);
    final bottomInset = media.viewInsets.bottom;
    final needle = query.trim().toLowerCase();
    final visible = widget.customers.where((customer) =>
      customer.name.toLowerCase().contains(needle) ||
      (customer.phone?.toLowerCase().contains(needle) ?? false));
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        bottomInset + AppSpacing.lg,
      ),
      child: SizedBox(
        height: (media.size.height - bottomInset) * .78,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(l10n.selectCustomerLabel, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const Key('create_job_customer_search'),
              autofocus: true,
              onChanged: (value) => setState(() => query = value),
              decoration: InputDecoration(
                hintText: l10n.searchCustomersHint,
                prefixIcon: const Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: visible.isEmpty
                  ? Center(child: Text(needle.isEmpty ? l10n.customersEmptyTitle : l10n.customersNoResultsTitle))
                  : ListView.separated(
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: visible.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final customer = visible.elementAt(index);
                        return ListTile(
                          key: Key('create_job_customer_option_${customer.id}'),
                          contentPadding: EdgeInsets.zero,
                          leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                          title: Text(customer.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: customer.phone == null || customer.phone!.trim().isEmpty
                              ? Text(customer.address, maxLines: 1, overflow: TextOverflow.ellipsis)
                              : Text(customer.phone!, maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: widget.selectedId == customer.id
                              ? const Icon(Icons.check_circle, color: AppColors.primary)
                              : null,
                          onTap: () => Navigator.of(context).pop(customer),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.title, required this.subtitle});
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.lg),
    decoration: BoxDecoration(
      color: AppColors.primarySurface,
      borderRadius: AppRadius.card,
      border: Border.all(color: AppColors.border),
    ),
    child: Row(children: <Widget>[
      const CircleAvatar(backgroundColor: AppColors.surface, child: Icon(Icons.assignment_outlined, color: AppColors.primary)),
      const SizedBox(width: AppSpacing.md),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.primaryDark, fontWeight: FontWeight.w700)),
        const SizedBox(height: AppSpacing.xs),
        Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
      ])),
    ]),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.number, required this.title});
  final String number;
  final String title;
  @override
  Widget build(BuildContext context) => Row(children: <Widget>[
    Container(width: 28, height: 28, alignment: Alignment.center,
      decoration: const BoxDecoration(color: AppColors.goldSurface, shape: BoxShape.circle),
      child: Text(number, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: AppColors.primaryDark, fontWeight: FontWeight.bold))),
    const SizedBox(width: AppSpacing.sm),
    Expanded(child: Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
  ]);
}

class _CustomerSelectionTile extends StatelessWidget {
  const _CustomerSelectionTile({super.key, required this.customer, required this.hasError, required this.onTap});
  final Customer? customer;
  final bool hasError;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    borderRadius: AppRadius.control,
    child: InkWell(
      onTap: onTap,
      borderRadius: AppRadius.control,
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(borderRadius: AppRadius.control, border: Border.all(color: hasError ? AppColors.error : AppColors.border)),
        child: Row(children: <Widget>[
          const Icon(Icons.person_search_outlined, color: AppColors.primary),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
            Text(customer?.name ?? context.l10n.selectCustomerLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: customer == null ? FontWeight.normal : FontWeight.w600)),
            if (customer != null) Text((customer!.phone?.trim().isNotEmpty ?? false) ? customer!.phone! : customer!.address, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
          ])),
          const Icon(Icons.expand_more_rounded, color: AppColors.textSecondary),
        ]),
      ),
    ),
  );
}

class _SelectionReview extends StatelessWidget {
  const _SelectionReview({required this.icon, required this.text, this.detail});
  final IconData icon;
  final String text;
  final String? detail;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(color: AppColors.background, borderRadius: AppRadius.bannerDirectional),
    child: Row(children: <Widget>[
      Icon(icon, color: AppColors.goldDeep),
      const SizedBox(width: AppSpacing.sm),
      Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
      if (detail != null && detail!.trim().isNotEmpty)
        Flexible(
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: AppSpacing.sm),
            child: Text(
              detail!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ),
    ]),
  );
}

class _LoadingOption extends StatelessWidget {
  const _LoadingOption();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(AppSpacing.lg),
    child: Center(child: CircularProgressIndicator()),
  );
}

class _OptionError extends StatelessWidget {
  const _OptionError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(color: AppColors.errorSurface, borderRadius: AppRadius.bannerDirectional),
    child: Row(children: <Widget>[
      const Icon(Icons.error_outline, color: AppColors.error),
      const SizedBox(width: AppSpacing.sm),
      Expanded(child: Text(message, style: Theme.of(context).textTheme.bodySmall)),
      IconButton(onPressed: onRetry, tooltip: context.l10n.retryButton, icon: const Icon(Icons.refresh)),
    ]),
  );
}

class _OptionEmpty extends StatelessWidget {
  const _OptionEmpty({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(color: AppColors.background, borderRadius: AppRadius.bannerDirectional),
    child: Row(children: <Widget>[
      const Icon(Icons.info_outline, color: AppColors.textSecondary),
      const SizedBox(width: AppSpacing.sm),
      Expanded(child: Text(message, style: Theme.of(context).textTheme.bodyMedium)),
    ]),
  );
}

class _FieldError extends StatelessWidget {
  const _FieldError({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(start: AppSpacing.md, top: AppSpacing.xs),
    child: Text(message, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.error)),
  );
}

class _SubmitBar extends StatelessWidget {
  const _SubmitBar({required this.state, required this.onSubmit});
  final CreateJobState state;
  final VoidCallback onSubmit;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
    decoration: BoxDecoration(color: AppColors.surface, border: Border(top: BorderSide(color: AppColors.border))),
    child: SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        key: const Key('create_and_assign_job_button'),
        onPressed: state.isSubmitting ? null : onSubmit,
        icon: state.isSubmitting
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.add_task_rounded),
        label: Text(context.l10n.createAndAssignJobButton),
      ),
    ),
  );
}
