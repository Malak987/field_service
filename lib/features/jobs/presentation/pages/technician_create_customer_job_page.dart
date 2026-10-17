import 'package:field_service/app/di/injection.dart';
import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_colors.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_radius.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/core/widgets/app_page_body.dart';
import 'package:field_service/core/widgets/app_standard_page_header.dart';
import 'package:field_service/features/authentication/domain/entities/app_user.dart';
import 'package:field_service/features/authentication/presentation/cubit/authentication_cubit.dart';
import 'package:field_service/features/authentication/presentation/widgets/auth_logo.dart';
import 'package:field_service/features/jobs/domain/entities/accessible_customer.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_category.dart';
import 'package:field_service/features/jobs/presentation/cubit/technician_job_form_cubit.dart';
import 'package:field_service/features/jobs/presentation/cubit/technician_job_form_state.dart';
import 'package:field_service/features/jobs/presentation/utils/job_label_mapper.dart';
import 'package:field_service/features/jobs/presentation/utils/technician_job_error_mapper.dart';
import 'package:field_service/features/jobs/presentation/utils/technician_job_form_validators.dart';
import 'package:field_service/features/jobs/presentation/widgets/accessible_customer_picker.dart';
import 'package:field_service/features/jobs/presentation/widgets/job_form_section.dart';
import 'package:field_service/features/jobs/presentation/widgets/technician_job_form_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// Technician "Create Customer & Job" screen (route `/jobs/technician-create`).
///
/// The technician may register a new customer on site or choose only a customer
/// already returned by the server-scoped accessible-customer read. The resulting
/// job is always assigned to the signed-in technician; no employee selector is
/// presented and the server enforces that same boundary.
///
/// Rebuild model: the page State never calls `setState`. Every section below is
/// its own small widget that subscribes to exactly the slice of the Cubit state
/// it renders (`BlocSelector` over value-equal records), and the scroll content
/// is built once and reused, so keyboard animation frames, typing and
/// selections only rebuild the leaf that actually changed.
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

  /// Built once. The enclosing [LayoutBuilder] re-runs on every keyboard
  /// animation frame (the body height changes); because these are the *same*
  /// widget instances (and the same list instance, so the sliver delegate does
  /// not rebuild), Flutter skips rebuilding them.
  late final List<Widget> _formChildren = <Widget>[
    const _TechnicianJobHeader(),
    const SizedBox(height: AppSpacing.xxl),
    const _CustomerModeSelector(),
    const SizedBox(height: AppSpacing.xl),
    _CustomerSection(controllers: _customer),
    const SizedBox(height: AppSpacing.xl),
    _JobDetailsSection(descriptionController: _description),
    const SizedBox(height: AppSpacing.xxl),
  ];

  late final Widget _submitBar = _SubmitBar(onSubmit: _submit);

  @override
  void dispose() {
    _customer.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final TechnicianJobFormCubit cubit = context.read<TechnicianJobFormCubit>();

    // The form owns text validation; the Cubit owns selections and submission.
    // This leaves the established offline queue and server rules untouched.
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    if (cubit.state.isNewCustomerMode) {
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

  void _onStateChanged(BuildContext context, TechnicianJobFormState state) {
    final AppLocalizations l10n = context.l10n;
    final Job? created = state.createdJob;
    if (created != null) {
      // A job number is only shown after the server has confirmed it.
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
      // Offline creation is honestly labelled as local/queued, never as
      // server-confirmed. The existing sync engine owns the later push.
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // The logo-led form header below carries the page title. The app bar
      // remains navigation chrome and keeps the automatic back affordance.
      appBar: AppBar(),
      body: BlocListener<TechnicianJobFormCubit, TechnicianJobFormState>(
        listenWhen:
            (TechnicianJobFormState previous, TechnicianJobFormState current) =>
        previous.createdJob != current.createdJob ||
            previous.queuedJobId != current.queuedJobId ||
            previous.error != current.error,
        listener: _onStateChanged,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final EdgeInsetsDirectional pagePadding =
              AppPageGutter.forWidth(constraints.maxWidth);

              return Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AppDimensions.contentMaxWidth,
                  ),
                  child: Column(
                    children: <Widget>[
                      Expanded(
                        child: Form(
                          key: _formKey,
                          child: ListView(
                            keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: pagePadding,
                            children: _formChildren,
                          ),
                        ),
                      ),
                      _submitBar,
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _TechnicianJobHeader extends StatelessWidget {
  const _TechnicianJobHeader();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    return AppStandardPageHeader(
      logoAssetName: AuthLogo.assetName,
      title: l10n.technicianCreateJobTitle,
      subtitle: l10n.technicianCreateJobSubtitle,
    );
  }
}

// ---------------------------------------------------------------------------
// Customer mode (New / Existing)
// ---------------------------------------------------------------------------

/// Rebuilds only when the mode or the submitting flag changes.
class _CustomerModeSelector extends StatelessWidget {
  const _CustomerModeSelector();

  @override
  Widget build(BuildContext context) {
    return BlocSelector<
        TechnicianJobFormCubit,
        TechnicianJobFormState,
        ({TechnicianJobCustomerMode mode, bool enabled})
    >(
      selector: (TechnicianJobFormState s) =>
      (mode: s.mode, enabled: !s.isSubmitting),
      builder: (
          BuildContext context,
          ({TechnicianJobCustomerMode mode, bool enabled}) v,
          ) {
        return _CustomerModePanel(
          key: const Key('technician_job_mode_selector'),
          mode: v.mode,
          enabled: v.enabled,
          onChanged: context.read<TechnicianJobFormCubit>().selectMode,
        );
      },
    );
  }
}

/// The existing New/Existing customer choice, framed as its own quiet decision
/// surface. It keeps the exact same state and callback contract as the prior
/// segmented control.
class _CustomerModePanel extends StatelessWidget {
  const _CustomerModePanel({
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

    return Material(
      color: AppColors.surfaceMuted,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.card,
        side: BorderSide(color: context.colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            // German mode labels are intentionally kept readable on compact
            // phones; their decorative icons return once there is room.
            final bool showIcons = constraints.maxWidth >= 360;

            return SegmentedButton<TechnicianJobCustomerMode>(
              segments: <ButtonSegment<TechnicianJobCustomerMode>>[
                ButtonSegment<TechnicianJobCustomerMode>(
                  value: TechnicianJobCustomerMode.newCustomer,
                  label: Text(l10n.technicianJobCustomerModeNew),
                  icon: showIcons
                      ? const Icon(Icons.person_add_alt_outlined)
                      : null,
                ),
                ButtonSegment<TechnicianJobCustomerMode>(
                  value: TechnicianJobCustomerMode.existingCustomer,
                  label: Text(l10n.technicianJobCustomerModeExisting),
                  icon: showIcons
                      ? const Icon(Icons.person_outline_rounded)
                      : null,
                ),
              ],
              selected: <TechnicianJobCustomerMode>{mode},
              onSelectionChanged: enabled
                  ? (Set<TechnicianJobCustomerMode> selection) =>
                  onChanged(selection.first)
                  : null,
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section 1: customer
// ---------------------------------------------------------------------------

/// Static section frame; only the inner body switches on [isNewCustomerMode].
class _CustomerSection extends StatelessWidget {
  const _CustomerSection({required this.controllers});

  final TechnicianCustomerFieldControllers controllers;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return JobFormSection(
      number: '1',
      icon: Icons.person_outline_rounded,
      title: l10n.technicianJobCustomerSection,
      child: BlocSelector<TechnicianJobFormCubit, TechnicianJobFormState, bool>(
        selector: (TechnicianJobFormState s) => s.isNewCustomerMode,
        builder: (BuildContext context, bool isNewCustomerMode) {
          return isNewCustomerMode
              ? _NewCustomerFields(controllers: controllers)
              : const _ExistingCustomerSection();
        },
      ),
    );
  }
}

/// New-customer inputs only depend on the submitting flag; typing and
/// selection changes never reach this widget.
class _NewCustomerFields extends StatelessWidget {
  const _NewCustomerFields({required this.controllers});

  final TechnicianCustomerFieldControllers controllers;

  @override
  Widget build(BuildContext context) {
    return BlocSelector<TechnicianJobFormCubit, TechnicianJobFormState, bool>(
      selector: (TechnicianJobFormState s) => !s.isSubmitting,
      builder: (BuildContext context, bool enabled) {
        return TechnicianCustomerFields(
          controllers: controllers,
          enabled: enabled,
        );
      },
    );
  }
}

Future<void> _pickExistingCustomer(BuildContext context) async {
  final TechnicianJobFormCubit cubit = context.read<TechnicianJobFormCubit>();
  // Read at tap time so the sheet always gets the latest list.
  final TechnicianJobFormState state = cubit.state;

  final AccessibleCustomer? customer =
  await showModalBottomSheet<AccessibleCustomer>(
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

typedef _ExistingCustomerView = ({
AccessibleCustomer? selected,
bool enabled,
bool showError,
bool isLoading,
bool failed,
bool isEmpty,
});

/// Existing-customer selector plus its actual loading, error and empty states.
class _ExistingCustomerSection extends StatelessWidget {
  const _ExistingCustomerSection();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return BlocSelector<
        TechnicianJobFormCubit,
        TechnicianJobFormState,
        _ExistingCustomerView
    >(
      selector: (TechnicianJobFormState s) => (
      selected: s.accessibleCustomers
          .where((AccessibleCustomer c) => c.id == s.selectedCustomerId)
          .firstOrNull,
      enabled: !s.isSubmitting,
      showError: s.showValidationErrors && !s.hasExistingCustomer,
      isLoading: s.isLoadingCustomers,
      failed: s.customersFailed,
      isEmpty: s.accessibleCustomers.isEmpty,
      ),
      builder: (BuildContext context, _ExistingCustomerView v) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AccessibleCustomerTile(
              key: const Key('technician_existing_customer_tile'),
              customer: v.selected,
              hasError: v.showError,
              onTap: v.enabled ? () => _pickExistingCustomer(context) : null,
            ),
            if (v.showError)
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: AppSpacing.md,
                  top: AppSpacing.xs,
                ),
                child: Text(
                  l10n.validationRequiredField,
                  style: context.textStyles.bodySmall?.copyWith(
                    color: AppColors.error,
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            if (v.isLoading)
              const SizedBox(
                height: 48,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (v.failed)
              _Notice(
                icon: Icons.error_outline_rounded,
                tone: _NoticeTone.error,
                message: l10n.technicianAccessibleCustomersError,
                action: IconButton(
                  onPressed: context
                      .read<TechnicianJobFormCubit>()
                      .loadAccessibleCustomers,
                  tooltip: l10n.retryButton,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              )
            else if (v.isEmpty)
                _Notice(
                  icon: Icons.info_outline_rounded,
                  tone: _NoticeTone.neutral,
                  message: l10n.technicianAccessibleCustomersEmptySubtitle,
                ),
          ],
        );
      },
    );
  }
}

enum _NoticeTone { neutral, error }

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.tone,
    required this.message,
    this.action,
  });

  final IconData icon;
  final _NoticeTone tone;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final bool isError = tone == _NoticeTone.error;
    final Color foreground = isError
        ? AppColors.error
        : context.colors.onSurfaceVariant;

    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.only(
        start: AppSpacing.md,
        top: AppSpacing.xs,
        bottom: AppSpacing.xs,
        end: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: isError ? AppColors.errorSurface : AppColors.surfaceMuted,
        borderRadius: AppRadius.banner,
        border: Border.all(
          color: isError
              ? AppColors.error.withValues(alpha: 0.25)
              : context.colors.outlineVariant,
        ),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, color: foreground, size: AppDimensions.iconMd),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: context.textStyles.bodySmall?.copyWith(color: foreground),
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section 2: job details
// ---------------------------------------------------------------------------

/// Static frame. Category, description and assignee each own their rebuilds,
/// so choosing a category never touches the description or assignee, and
/// toggling `isSubmitting` never rebuilds the assignee card.
class _JobDetailsSection extends StatelessWidget {
  const _JobDetailsSection({required this.descriptionController});

  final TextEditingController descriptionController;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return JobFormSection(
      number: '2',
      icon: Icons.home_repair_service_outlined,
      title: l10n.technicianJobDetailsSection,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _JobCategoryField(),
          const SizedBox(height: AppSpacing.lg),
          _JobDescriptionField(controller: descriptionController),
          const SizedBox(height: AppSpacing.lg),
          const _AssigneeCard(),
        ],
      ),
    );
  }
}

/// Caches the [JobLabelMapper] per localization instance instead of creating a
/// new one on every selection rebuild.
class _JobCategoryField extends StatefulWidget {
  const _JobCategoryField();

  @override
  State<_JobCategoryField> createState() => _JobCategoryFieldState();
}

class _JobCategoryFieldState extends State<_JobCategoryField> {
  AppLocalizations? _l10n;
  late JobLabelMapper _mapper;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final AppLocalizations l10n = context.l10n;
    if (!identical(l10n, _l10n)) {
      _l10n = l10n;
      _mapper = JobLabelMapper(l10n);
    }
  }

  @override
  Widget build(BuildContext context) {
    final String validationMessage = context.l10n.validationRequiredField;

    return BlocSelector<
        TechnicianJobFormCubit,
        TechnicianJobFormState,
        ({String? category, bool hasError, bool enabled})
    >(
      selector: (TechnicianJobFormState s) => (
      category: s.selectedCategory,
      hasError: s.showValidationErrors && !s.hasCategory,
      enabled: !s.isSubmitting,
      ),
      builder: (
          BuildContext context,
          ({String? category, bool hasError, bool enabled}) v,
          ) {
        return _JobCategorySelector(
          key: const Key('technician_job_category_dropdown'),
          selectedCategory: v.category,
          mapper: _mapper,
          hasError: v.hasError,
          enabled: v.enabled,
          onSelected: context.read<TechnicianJobFormCubit>().selectCategory,
          validationMessage: validationMessage,
        );
      },
    );
  }
}

/// Optional description. Rebuilds only when the submitting flag flips.
class _JobDescriptionField extends StatelessWidget {
  const _JobDescriptionField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return BlocSelector<TechnicianJobFormCubit, TechnicianJobFormState, bool>(
      selector: (TechnicianJobFormState s) => !s.isSubmitting,
      builder: (BuildContext context, bool enabled) {
        final AppLocalizations l10n = context.l10n;
        return TechnicianFormField(
          key: const Key('technician_job_description_field'),
          controller: controller,
          label: l10n.descriptionLabel,
          hint: l10n.technicianJobDescriptionHint,
          icon: Icons.notes_outlined,
          enabled: enabled,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          textCapitalization: TextCapitalization.sentences,
          minLines: 3,
          maxLines: 5,
          validator: (String? value) =>
              TechnicianJobFormValidators.validateJobDescription(value, l10n),
        );
      },
    );
  }
}

class _JobCategorySelector extends StatelessWidget {
  const _JobCategorySelector({
    super.key,
    required this.selectedCategory,
    required this.mapper,
    required this.hasError,
    required this.enabled,
    required this.onSelected,
    required this.validationMessage,
  });

  final String? selectedCategory;
  final JobLabelMapper mapper;
  final bool hasError;
  final bool enabled;
  final ValueChanged<String?> onSelected;
  final String validationMessage;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool twoColumns = constraints.maxWidth >= 560;
        final List<Widget> cards = <Widget>[
          _JobCategoryCard(
            label: mapper.jobTypeLabel(JobCategory.kitchenRenovation),
            icon: Icons.kitchen_outlined,
            selected: selectedCategory == JobCategory.kitchenRenovation,
            enabled: enabled,
            onTap: () => onSelected(JobCategory.kitchenRenovation),
          ),
          _JobCategoryCard(
            label: mapper.jobTypeLabel(JobCategory.homeRenovation),
            icon: Icons.house_siding_outlined,
            selected: selectedCategory == JobCategory.homeRenovation,
            enabled: enabled,
            onTap: () => onSelected(JobCategory.homeRenovation),
          ),
        ];

        final Widget selector = twoColumns
            ? Row(
          children: <Widget>[
            Expanded(child: cards[0]),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: cards[1]),
          ],
        )
            : Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            cards[0],
            const SizedBox(height: AppSpacing.md),
            cards[1],
          ],
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            selector,
            if (hasError)
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: AppSpacing.md,
                  top: AppSpacing.xs,
                ),
                child: Text(
                  validationMessage,
                  style: context.textStyles.bodySmall?.copyWith(
                    color: AppColors.error,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _JobCategoryCard extends StatelessWidget {
  const _JobCategoryCard({
    required this.label,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected ? AppColors.primarySurface : context.colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.card,
          side: BorderSide(
            color: selected ? AppColors.primary : context.colors.outlineVariant,
            width: selected ? AppDimensions.focusedBorderWidth : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: SizedBox(
            height: 144,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        width: AppDimensions.buttonHeightCompact,
                        height: AppDimensions.buttonHeightCompact,
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.primary
                              : AppColors.goldSurface,
                          borderRadius: AppRadius.banner,
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          icon,
                          size: AppDimensions.iconLg,
                          color: selected
                              ? AppColors.onBrand
                              : AppColors.goldDeep,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        size: AppDimensions.iconLg,
                        color: selected
                            ? AppColors.primary
                            : context.colors.onSurfaceVariant,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.textStyles.titleMedium?.copyWith(
                      color: selected ? AppColors.primaryDark : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Read-only assignment fact. It does not subscribe to the form Cubit, so no
/// form interaction rebuilds it.
class _AssigneeCard extends StatelessWidget {
  const _AssigneeCard();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppUser? user = context.read<AuthenticationCubit?>()?.state.user;
    final String assignee = _assigneeLabel(user, l10n);

    return Container(
      key: const Key('technician_job_assignee_field'),
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.goldSurface,
        borderRadius: AppRadius.banner,
        border: Border.all(color: AppColors.goldAccent),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.assignment_ind_outlined,
            size: AppDimensions.iconMd,
            color: AppColors.goldDeep,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  l10n.technicianJobAssignedToLabel,
                  style: context.textStyles.titleSmall?.copyWith(
                    color: AppColors.goldDeep,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(assignee, style: context.textStyles.bodyMedium),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  l10n.technicianJobAssignedToHint,
                  style: context.textStyles.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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

// ---------------------------------------------------------------------------
// Submit bar
// ---------------------------------------------------------------------------

class _SubmitBar extends StatelessWidget {
  const _SubmitBar({required this.onSubmit});

  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return Material(
      color: context.colors.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: context.colors.outlineVariant)),
        ),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) => Padding(
            padding: AppPageGutter.withVertical(
              constraints.maxWidth,
              top: AppSpacing.sm,
              bottom: AppSpacing.md,
            ),
            child: SizedBox(
              width: double.infinity,
              child:
              BlocSelector<
                  TechnicianJobFormCubit,
                  TechnicianJobFormState,
                  bool
              >(
                selector: (TechnicianJobFormState s) => s.isSubmitting,
                builder: (BuildContext context, bool isSubmitting) {
                  return FilledButton.icon(
                    key: const Key('technician_create_customer_job_button'),
                    onPressed: isSubmitting ? null : onSubmit,
                    icon: isSubmitting
                        ? const SizedBox(
                      width: AppDimensions.iconSm,
                      height: AppDimensions.iconSm,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                        : const Icon(
                      Icons.add_task_rounded,
                      size: AppDimensions.iconMd,
                    ),
                    label: Text(l10n.technicianCreateJobButton),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}