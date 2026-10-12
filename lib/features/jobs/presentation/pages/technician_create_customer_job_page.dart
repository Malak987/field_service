import 'package:field_service/app/di/injection.dart';
import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_radius.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/features/authentication/domain/entities/app_user.dart';
import 'package:field_service/features/authentication/presentation/cubit/authentication_cubit.dart';
import 'package:field_service/features/jobs/domain/entities/accessible_customer.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_category.dart';
import 'package:field_service/features/jobs/presentation/cubit/technician_job_form_cubit.dart';
import 'package:field_service/features/jobs/presentation/cubit/technician_job_form_state.dart';
import 'package:field_service/features/jobs/presentation/utils/job_label_mapper.dart';
import 'package:field_service/features/jobs/presentation/utils/technician_job_error_mapper.dart';
import 'package:field_service/features/jobs/presentation/utils/technician_job_form_validators.dart';
import 'package:field_service/features/jobs/presentation/widgets/accessible_customer_picker.dart';
import 'package:field_service/features/jobs/presentation/widgets/technician_job_form_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// Technician "Create Customer & Job" screen (route `/jobs/technician-create`).
///
/// One form, two sections:
/// 1. the customer — either a NEW one (registered here) or an EXISTING one
///    the technician is already entitled to work for,
/// 2. the job — category, description and the assignee, which is ALWAYS the
///    signed-in technician (shown read-only; the server resolves it from the
///    auth identity, so there is no way to assign work to somebody else).
///
/// The page is deliberately thin: [TechnicianCustomerFields] owns the field
/// rendering, [TechnicianJobFormValidators] the rules and
/// [TechnicianJobFormCubit] the submission. Success reports the REAL
/// database-generated job number; an offline submission is reported as
/// queued, never as saved on the server.
class TechnicianCreateCustomerJobPage extends StatelessWidget {
  const TechnicianCreateCustomerJobPage({super.key, this.cubit});

  /// Test/DI seam (same convention as `CreateCustomerPage`).
  final TechnicianJobFormCubit? cubit;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<TechnicianJobFormCubit>(
      create: (_) => cubit ?? sl<TechnicianJobFormCubit>(),
      child: const _TechnicianJobForm(),
    );
  }
}

class _TechnicianJobForm extends StatefulWidget {
  const _TechnicianJobForm();

  @override
  State<_TechnicianJobForm> createState() => _TechnicianJobFormState();
}

class _TechnicianJobFormState extends State<_TechnicianJobForm> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TechnicianCustomerFieldControllers _customer =
      TechnicianCustomerFieldControllers();
  final TextEditingController _description = TextEditingController();

  @override
  void dispose() {
    _customer.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit(BuildContext context) async {
    final TechnicianJobFormCubit cubit = context.read<TechnicianJobFormCubit>();
    final TechnicianJobFormState state = cubit.state;

    // The form owns the text rules; the cubit owns the selections. Validating
    // first means an incomplete customer never reaches the queue.
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    if (state.isNewCustomerMode) {
      await cubit.submitNewCustomerAndJob(
        customer: _customer.draft,
        description: _description.text,
      );
    } else {
      await cubit.submitJobForExistingCustomer(
        description: _description.text,
      );
    }
  }

  Future<void> _pickExistingCustomer(
    BuildContext context,
    TechnicianJobFormCubit cubit,
    TechnicianJobFormState state,
  ) async {
    final AccessibleCustomer? customer = await showModalBottomSheet<
      AccessibleCustomer
    >(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext _) => AccessibleCustomerPicker(
        customers: state.accessibleCustomers,
        selectedId: state.selectedCustomerId,
      ),
    );

    if (customer != null && context.mounted) {
      cubit.selectCustomer(customer.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.technicianCreateJobTitle)),
      body: BlocConsumer<TechnicianJobFormCubit, TechnicianJobFormState>(
        listenWhen: (
          TechnicianJobFormState previous,
          TechnicianJobFormState current,
        ) =>
            previous.createdJob != current.createdJob ||
            previous.queuedJobId != current.queuedJobId ||
            previous.error != current.error,
        listener: (BuildContext context, TechnicianJobFormState state) {
          final Job? created = state.createdJob;
          if (created != null) {
            // Success is only reported once the SERVER confirmed it — and it
            // carries the real, database-generated job number.
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(l10n.technicianCreateJobSuccess(created.jobNumber)),
              ),
            );
            context.goNamed(
              'jobDetails',
              pathParameters: <String, String>{'id': created.id},
            );
            return;
          }

          if (state.queuedJobId != null) {
            // Offline: saved on this device, awaiting the shared sync engine.
            // Deliberately NOT worded as a server confirmation.
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.technicianCreateJobQueued)),
            );
            context.pop();
            return;
          }

          if (state.error != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  TechnicianJobErrorMapper.messageFor(state.error, context),
                ),
              ),
            );
          }
        },
        builder: (BuildContext context, TechnicianJobFormState state) {
          final TechnicianJobFormCubit cubit =
              context.read<TechnicianJobFormCubit>();

          return SafeArea(
            child: Column(
              children: <Widget>[
                Expanded(
                  child: Form(
                    key: _formKey,
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
                          title: l10n.technicianCreateJobTitle,
                          subtitle: l10n.technicianCreateJobSubtitle,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        _ModeSelector(
                          key: const Key('technician_job_mode_selector'),
                          mode: state.mode,
                          enabled: !state.isSubmitting,
                          onChanged: cubit.selectMode,
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        TechnicianJobFormSection(
                          number: '1',
                          title: l10n.technicianJobCustomerSection,
                          child: state.isNewCustomerMode
                              ? TechnicianCustomerFields(
                                  controllers: _customer,
                                  enabled: !state.isSubmitting,
                                )
                              : _ExistingCustomerSection(
                                  state: state,
                                  cubit: cubit,
                                  onPick: () => _pickExistingCustomer(
                                    context,
                                    cubit,
                                    state,
                                  ),
                                ),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        TechnicianJobFormSection(
                          number: '2',
                          title: l10n.technicianJobDetailsSection,
                          child: _JobFields(
                            state: state,
                            onCategoryChanged: cubit.selectCategory,
                            descriptionController: _description,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _SubmitBar(
                  isSubmitting: state.isSubmitting,
                  onSubmit: () => _submit(context),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The two job fields plus the read-only assignee.
///
/// The assignee is the signed-in technician and cannot be changed — the
/// server resolves it from the auth identity anyway, so offering a selector
/// here would only invite a refusal.
class _JobFields extends StatelessWidget {
  const _JobFields({
    required this.state,
    required this.onCategoryChanged,
    required this.descriptionController,
  });

  final TechnicianJobFormState state;
  final ValueChanged<String?> onCategoryChanged;
  final TextEditingController descriptionController;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final JobLabelMapper mapper = JobLabelMapper(l10n);
    final AppUser? user = context.read<AuthenticationCubit?>()?.state.user;
    final String assignee = _assigneeLabel(user, l10n);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        DropdownButtonFormField<String>(
          key: const Key('technician_job_category_dropdown'),
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
          onChanged: state.isSubmitting ? null : onCategoryChanged,
        ),
        const SizedBox(height: AppSpacing.md),
        TechnicianFormField(
          key: const Key('technician_job_description_field'),
          controller: descriptionController,
          label: l10n.descriptionLabel,
          hint: l10n.technicianJobDescriptionHint,
          icon: Icons.notes_outlined,
          enabled: !state.isSubmitting,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          textCapitalization: TextCapitalization.sentences,
          minLines: 3,
          maxLines: 5,
          validator: (String? value) =>
              TechnicianJobFormValidators.validateJobDescription(value, l10n),
        ),
        const SizedBox(height: AppSpacing.md),
        // Read-only on purpose: the assignee is the signed-in technician and
        // is resolved by the server from the auth identity. No controller is
        // created here so a rebuild never leaks one.
        InputDecorator(
          key: const Key('technician_job_assignee_field'),
          decoration: InputDecoration(
            labelText: l10n.technicianJobAssignedToLabel,
            helperText: l10n.technicianJobAssignedToHint,
            prefixIcon: const Icon(Icons.badge_outlined),
          ),
          child: Text(assignee),
        ),
      ],
    );
  }

  /// The technician's own display name (never an invented identity).
  static String _assigneeLabel(AppUser? user, AppLocalizations l10n) {
    final String? name = user?.name?.trim();
    if (name != null && name.isNotEmpty) {
      return name;
    }
    final String? code = user?.employeeCode?.trim();
    if (code != null && code.isNotEmpty) {
      return code;
    }
    return user?.email ?? l10n.roleTechnicianLabel;
  }
}

/// "New customer" vs. "existing customer" — the form's only branching
/// decision, rendered as one segmented control.
class _ModeSelector extends StatelessWidget {
  const _ModeSelector({
    super.key,
    required this.mode,
    required this.enabled,
    required this.onChanged,
  });

  final TechnicianJobCustomerMode mode;
  final bool enabled;
  final ValueChanged<TechnicianJobCustomerMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return SegmentedButton<TechnicianJobCustomerMode>(
      segments: <ButtonSegment<TechnicianJobCustomerMode>>[
        ButtonSegment<TechnicianJobCustomerMode>(
          value: TechnicianJobCustomerMode.newCustomer,
          label: Text(l10n.technicianJobCustomerModeNew),
          icon: const Icon(Icons.person_add_alt_outlined),
        ),
        ButtonSegment<TechnicianJobCustomerMode>(
          value: TechnicianJobCustomerMode.existingCustomer,
          label: Text(l10n.technicianJobCustomerModeExisting),
          icon: const Icon(Icons.person_outline_rounded),
        ),
      ],
      selected: <TechnicianJobCustomerMode>{mode},
      onSelectionChanged: enabled
          ? (Set<TechnicianJobCustomerMode> selection) =>
                onChanged(selection.first)
          : null,
    );
  }
}

/// The existing-customer part of section 1: the selector tile plus the
/// honest loading / failed / empty states of the server-scoped read.
class _ExistingCustomerSection extends StatelessWidget {
  const _ExistingCustomerSection({
    required this.state,
    required this.cubit,
    required this.onPick,
  });

  final TechnicianJobFormState state;
  final TechnicianJobFormCubit cubit;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AccessibleCustomer? selected = state.accessibleCustomers
        .where((AccessibleCustomer c) => c.id == state.selectedCustomerId)
        .firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AccessibleCustomerTile(
          key: const Key('technician_existing_customer_tile'),
          customer: selected,
          hasError: state.showValidationErrors && !state.hasExistingCustomer,
          onTap: state.isSubmitting ? null : onPick,
        ),
        if (state.showValidationErrors && !state.hasExistingCustomer)
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: AppSpacing.md,
              top: AppSpacing.xs,
            ),
            child: Text(
              l10n.validationRequiredField,
              style: context.textStyles.bodySmall?.copyWith(
                color: context.colors.error,
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        if (state.isLoadingCustomers)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (state.customersFailed)
          _Notice(
            icon: Icons.error_outline,
            color: context.colors.error,
            message: l10n.technicianAccessibleCustomersError,
            action: IconButton(
              onPressed: cubit.loadAccessibleCustomers,
              tooltip: l10n.retryButton,
              icon: const Icon(Icons.refresh),
            ),
          )
        else if (state.accessibleCustomers.isEmpty)
          _Notice(
            icon: Icons.info_outline,
            color: context.colors.onSurfaceVariant,
            message: l10n.technicianAccessibleCustomersEmptySubtitle,
          ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.color,
    required this.message,
    this.action,
  });

  final IconData icon;
  final Color color;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, color: color, size: AppDimensions.iconMd),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(message, style: context.textStyles.bodySmall),
        ),
        if (action != null) action!,
      ],
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.colors.primaryContainer,
        borderRadius: AppRadius.card,
        border: Border.all(color: context.colors.outlineVariant),
      ),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            backgroundColor: context.colors.surface,
            child: Icon(
              Icons.assignment_add,
              color: context.colors.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: context.textStyles.titleMedium?.copyWith(
                    color: context.colors.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  subtitle,
                  style: context.textStyles.bodySmall?.copyWith(
                    color: context.colors.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SubmitBar extends StatelessWidget {
  const _SubmitBar({required this.isSubmitting, required this.onSubmit});

  final bool isSubmitting;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(top: BorderSide(color: context.colors.outlineVariant)),
      ),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          key: const Key('technician_create_customer_job_button'),
          onPressed: isSubmitting ? null : onSubmit,
          icon: isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add_task_rounded),
          label: Text(l10n.technicianCreateJobButton),
        ),
      ),
    );
  }
}
