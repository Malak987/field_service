import 'package:field_service/app/di/injection.dart';
import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_colors.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_radius.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/core/widgets/app_page_body.dart';
import 'package:field_service/core/widgets/app_standard_page_header.dart';
import 'package:field_service/core/widgets/app_surface_panel.dart';
import 'package:field_service/features/authentication/presentation/widgets/auth_logo.dart';
import 'package:field_service/features/customers/domain/entities/customer.dart';
import 'package:field_service/features/employees/domain/entities/employee.dart';
import 'package:field_service/features/jobs/domain/entities/job_category.dart';
import 'package:field_service/features/jobs/presentation/cubit/create_job_cubit.dart';
import 'package:field_service/features/jobs/presentation/cubit/create_job_state.dart';
import 'package:field_service/features/jobs/presentation/utils/job_label_mapper.dart';
import 'package:field_service/features/jobs/presentation/widgets/job_form_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

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
    if (customer != null && context.mounted) {
      cubit.selectCustomer(customer.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // The logo-led identity block below is the page title. Keeping this
      // chrome-only preserves the automatic back affordance without repeating
      // the page name on a compact phone viewport.
      appBar: AppBar(),
      body: BlocConsumer<CreateJobCubit, CreateJobState>(
        listenWhen: (CreateJobState previous, CreateJobState current) =>
            previous.createdJob != current.createdJob ||
            previous.error != current.error,
        listener: (BuildContext context, CreateJobState state) {
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
        builder: (BuildContext context, CreateJobState state) {
          final AppLocalizations l10n = context.l10n;
          final CreateJobCubit cubit = context.read<CreateJobCubit>();
          final JobLabelMapper mapper = JobLabelMapper(l10n);
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
                  child: LayoutBuilder(
                    builder:
                        (BuildContext context, BoxConstraints constraints) {
                          final EdgeInsetsDirectional pagePadding =
                              AppPageGutter.forWidth(constraints.maxWidth);

                          return Align(
                            alignment: Alignment.topCenter,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxWidth: AppDimensions.contentMaxWidth,
                              ),
                              child: ListView(
                                keyboardDismissBehavior:
                                    ScrollViewKeyboardDismissBehavior.onDrag,
                                padding: pagePadding,
                                children: <Widget>[
                                  _CreateJobHeader(
                                    title: l10n.createJobButton,
                                    subtitle: l10n.createJobIntro,
                                  ),
                                  const SizedBox(height: AppSpacing.xxl),
                                  JobFormSection(
                                    number: '1',
                                    icon: Icons.person_search_outlined,
                                    title: l10n.selectCustomerLabel,
                                    child:
                                        state.isLoadingCustomers &&
                                            state.customers.isEmpty
                                        ? const _LoadingOption()
                                        : state.customerOptionsFailed
                                        ? _OptionError(
                                            message:
                                                l10n.createJobOptionsFailedMessage,
                                            onRetry: cubit.loadOptions,
                                          )
                                        : state.customers.isEmpty
                                        ? _OptionEmpty(
                                            message: l10n.customersEmptyTitle,
                                          )
                                        : Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: <Widget>[
                                              _CustomerSelectionTile(
                                                key: const Key(
                                                  'create_job_customer_dropdown',
                                                ),
                                                customer: selectedCustomer,
                                                hasError:
                                                    state.showValidationErrors &&
                                                    !state.hasCustomer,
                                                onTap: state.isSubmitting
                                                    ? null
                                                    : () => _selectCustomer(
                                                        context,
                                                        cubit,
                                                        state,
                                                      ),
                                              ),
                                              if (state.showValidationErrors &&
                                                  !state.hasCustomer)
                                                _FieldError(
                                                  message: l10n
                                                      .validationRequiredField,
                                                ),
                                            ],
                                          ),
                                  ),
                                  const SizedBox(height: AppSpacing.xl),
                                  JobFormSection(
                                    number: '2',
                                    icon: Icons.home_repair_service_outlined,
                                    title: l10n.jobTypeLabel,
                                    child: _JobTypeSelector(
                                      key: const Key(
                                        'create_job_category_dropdown',
                                      ),
                                      selectedCategory: state.selectedCategory,
                                      mapper: mapper,
                                      hasError:
                                          state.showValidationErrors &&
                                          !state.hasCategory,
                                      onSelected: state.isSubmitting
                                          ? null
                                          : cubit.selectCategory,
                                      validationMessage:
                                          l10n.validationRequiredField,
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.xl),
                                  JobFormSection(
                                    number: '3',
                                    icon: Icons.notes_outlined,
                                    title: l10n.descriptionLabel,
                                    child: TextFormField(
                                      key: const Key(
                                        'create_job_description_field',
                                      ),
                                      initialValue: state.description,
                                      minLines: 3,
                                      maxLines: 5,
                                      textCapitalization:
                                          TextCapitalization.sentences,
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
                                  ),
                                  const SizedBox(height: AppSpacing.xl),
                                  JobFormSection(
                                    number: '4',
                                    icon: Icons.engineering_outlined,
                                    title: l10n.selectTechnicianLabel,
                                    child:
                                        state.isLoadingTechnicians &&
                                            state.technicians.isEmpty
                                        ? const _LoadingOption()
                                        : state.technicianOptionsFailed
                                        ? _OptionError(
                                            message:
                                                l10n.createJobOptionsFailedMessage,
                                            onRetry: cubit.loadOptions,
                                          )
                                        : state.technicians.isEmpty
                                        ? _OptionEmpty(
                                            message:
                                                l10n.noActiveTechniciansMessage,
                                          )
                                        : _TechnicianSelectionField(
                                            selectedTechnician:
                                                selectedTechnician,
                                            state: state,
                                            onChanged: state.isSubmitting
                                                ? null
                                                : cubit.selectTechnician,
                                          ),
                                  ),
                                  if (selectedCustomer != null ||
                                      state.selectedCategory != null ||
                                      selectedTechnician != null) ...<Widget>[
                                    const SizedBox(height: AppSpacing.xxl),
                                    _ReviewSection(
                                      title: l10n.createJobReviewTitle,
                                      customer: selectedCustomer,
                                      category: state.selectedCategory,
                                      technician: selectedTechnician,
                                      mapper: mapper,
                                    ),
                                  ],
                                  const SizedBox(height: AppSpacing.xxl),
                                ],
                              ),
                            ),
                          );
                        },
                  ),
                ),
                _SubmitBar(
                  state: state,
                  onSubmit: () {
                    cubit.submit();
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Customer? _findCustomer(List<Customer> items, String? id) {
    for (final Customer item in items) {
      if (item.id == id) {
        return item;
      }
    }
    return null;
  }

  Employee? _findTechnician(List<Employee> items, String? id) {
    for (final Employee item in items) {
      if (item.id == id) {
        return item;
      }
    }
    return null;
  }
}

/// Searchable picker for the existing offline-first customer options.
///
/// It only returns the selected [Customer]; filtering and assignment remain in
/// the existing Cubit, so the established customer data flow is unchanged.
class _CustomerPicker extends StatefulWidget {
  const _CustomerPicker({required this.customers, required this.selectedId});

  final List<Customer> customers;
  final String? selectedId;

  @override
  State<_CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends State<_CustomerPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final MediaQueryData media = MediaQuery.of(context);
    final double bottomInset = media.viewInsets.bottom;
    final String needle = _query.trim().toLowerCase();
    final List<Customer> visible = widget.customers
        .where(
          (Customer customer) =>
              customer.name.toLowerCase().contains(needle) ||
              (customer.phone?.toLowerCase().contains(needle) ?? false),
        )
        .toList();

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
            Row(
              children: <Widget>[
                Container(
                  width: AppDimensions.buttonHeightCompact,
                  height: AppDimensions.buttonHeightCompact,
                  decoration: const BoxDecoration(
                    color: AppColors.primarySurface,
                    borderRadius: AppRadius.banner,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.person_search_outlined,
                    size: AppDimensions.iconMd,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    l10n.selectCustomerLabel,
                    style: context.textStyles.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              key: const Key('create_job_customer_search'),
              autofocus: true,
              onChanged: (String value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: l10n.searchCustomersHint,
                prefixIcon: const Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: visible.isEmpty
                  ? Center(
                      child: Text(
                        needle.isEmpty
                            ? l10n.customersEmptyTitle
                            : l10n.customersNoResultsTitle,
                      ),
                    )
                  : Material(
                      color: context.colors.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: AppRadius.card,
                        side: BorderSide(color: context.colors.outlineVariant),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: ListView.separated(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        itemCount: visible.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          color: context.colors.outlineVariant,
                        ),
                        itemBuilder: (BuildContext context, int index) {
                          final Customer customer = visible[index];
                          return _CustomerPickerRow(
                            key: Key(
                              'create_job_customer_option_${customer.id}',
                            ),
                            customer: customer,
                            selected: widget.selectedId == customer.id,
                            onTap: () => Navigator.of(context).pop(customer),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateJobHeader extends StatelessWidget {
  const _CreateJobHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => AppStandardPageHeader(
    logoAssetName: AuthLogo.assetName,
    title: title,
    subtitle: subtitle,
  );
}

class _CustomerSelectionTile extends StatelessWidget {
  const _CustomerSelectionTile({
    super.key,
    required this.customer,
    required this.hasError,
    required this.onTap,
  });

  final Customer? customer;
  final bool hasError;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool selected = customer != null;
    final Color borderColor = hasError
        ? AppColors.error
        : selected
        ? AppColors.primary
        : context.colors.outlineVariant;

    return Semantics(
      button: true,
      label: selected ? customer!.name : context.l10n.selectCustomerLabel,
      child: Material(
        color: selected ? AppColors.primarySurface : context.colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.card,
          side: BorderSide(
            color: borderColor,
            width: selected ? AppDimensions.focusedBorderWidth : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 84),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: <Widget>[
                  Container(
                    width: AppDimensions.buttonHeightCompact,
                    height: AppDimensions.buttonHeightCompact,
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.primary
                          : AppColors.primarySurface,
                      borderRadius: AppRadius.banner,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      selected
                          ? Icons.person_rounded
                          : Icons.person_search_outlined,
                      size: AppDimensions.iconMd,
                      color: selected
                          ? AppColors.onBrand
                          : AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          selected
                              ? customer!.name
                              : context.l10n.selectCustomerLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.textStyles.titleSmall?.copyWith(
                            color: selected ? AppColors.primaryDark : null,
                          ),
                        ),
                        if (selected) ...<Widget>[
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            _customerDetail(customer!),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: context.textStyles.bodySmall?.copyWith(
                              color: context.colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.expand_more_rounded,
                    size: AppDimensions.iconLg,
                    color: selected
                        ? AppColors.primary
                        : context.colors.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _customerDetail(Customer customer) {
    final String phone = customer.phone?.trim() ?? '';
    if (phone.isNotEmpty) {
      return phone;
    }
    final String city = customer.cityLine;
    return city.isEmpty ? customer.address : '${customer.address} · $city';
  }
}

class _JobTypeSelector extends StatelessWidget {
  const _JobTypeSelector({
    super.key,
    required this.selectedCategory,
    required this.mapper,
    required this.hasError,
    required this.onSelected,
    required this.validationMessage,
  });

  final String? selectedCategory;
  final JobLabelMapper mapper;
  final bool hasError;
  final ValueChanged<String?>? onSelected;
  final String validationMessage;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool twoColumns = constraints.maxWidth >= 560;
        final List<Widget> cards = <Widget>[
          _JobTypeCard(
            label: mapper.jobTypeLabel(JobCategory.kitchenRenovation),
            icon: Icons.kitchen_outlined,
            selected: selectedCategory == JobCategory.kitchenRenovation,
            enabled: onSelected != null,
            onTap: () => onSelected?.call(JobCategory.kitchenRenovation),
          ),
          _JobTypeCard(
            label: mapper.jobTypeLabel(JobCategory.homeRenovation),
            icon: Icons.house_siding_outlined,
            selected: selectedCategory == JobCategory.homeRenovation,
            enabled: onSelected != null,
            onTap: () => onSelected?.call(JobCategory.homeRenovation),
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
            if (hasError) _FieldError(message: validationMessage),
          ],
        );
      },
    );
  }
}

class _JobTypeCard extends StatelessWidget {
  const _JobTypeCard({
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

class _TechnicianSelectionField extends StatelessWidget {
  const _TechnicianSelectionField({
    required this.selectedTechnician,
    required this.state,
    required this.onChanged,
  });

  final Employee? selectedTechnician;
  final CreateJobState state;
  final ValueChanged<String?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final bool selected = selectedTechnician != null;

    return Material(
      color: selected ? AppColors.primarySurface : context.colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.card,
        side: BorderSide(
          color: state.showValidationErrors && !state.hasTechnician
              ? AppColors.error
              : selected
              ? AppColors.primary
              : context.colors.outlineVariant,
          width: selected ? AppDimensions.focusedBorderWidth : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xs),
        child: DropdownButtonFormField<String>(
          key: const Key('create_job_technician_dropdown'),
          initialValue: state.selectedTechnicianId,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: selected
                ? l10n.assignedTechnicianLabel
                : l10n.selectTechnicianLabel,
            prefixIcon: Icon(
              selected ? Icons.engineering_rounded : Icons.badge_outlined,
              color: selected ? AppColors.primary : null,
            ),
            errorText: state.showValidationErrors && !state.hasTechnician
                ? l10n.validationRequiredField
                : null,
          ),
          selectedItemBuilder: (BuildContext context) => state.technicians
              .map(
                (Employee employee) => Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    employee.displayName,
                    overflow: TextOverflow.ellipsis,
                    style: context.textStyles.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              )
              .toList(),
          items: <DropdownMenuItem<String>>[
            for (final Employee employee in state.technicians)
              DropdownMenuItem<String>(
                value: employee.id,
                child: Text(
                  employee.employeeCode == null ||
                          employee.employeeCode!.trim().isEmpty
                      ? employee.displayName
                      : '${employee.displayName} · ${employee.employeeCode}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _ReviewSection extends StatelessWidget {
  const _ReviewSection({
    required this.title,
    required this.customer,
    required this.category,
    required this.technician,
    required this.mapper,
  });

  final String title;
  final Customer? customer;
  final String? category;
  final Employee? technician;
  final JobLabelMapper mapper;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: context.textStyles.titleMedium),
        const SizedBox(height: AppSpacing.md),
        AppSurfacePanel(
          key: const Key('create_job_selection_review'),
          divideRows: false,
          padding: const EdgeInsets.all(AppSpacing.md),
          children: <Widget>[
            if (customer != null)
              _SelectionReview(
                icon: Icons.person_outline_rounded,
                text: customer!.name,
                detail: _reviewCustomerDetail(customer!),
              ),
            if (customer != null && category != null)
              const SizedBox(height: AppSpacing.sm),
            if (category != null)
              _SelectionReview(
                icon: category == JobCategory.kitchenRenovation
                    ? Icons.kitchen_outlined
                    : Icons.house_siding_outlined,
                text: mapper.jobTypeLabel(category!),
              ),
            if (technician != null) ...<Widget>[
              if (customer != null || category != null)
                const SizedBox(height: AppSpacing.sm),
              _SelectionReview(
                icon: Icons.engineering_outlined,
                text: technician!.displayName,
                detail: technician!.employeeCode,
              ),
            ],
          ],
        ),
      ],
    );
  }

  String? _reviewCustomerDetail(Customer customer) {
    final String phone = customer.phone?.trim() ?? '';
    return phone.isEmpty ? customer.address : phone;
  }
}

class _SelectionReview extends StatelessWidget {
  const _SelectionReview({
    required this.icon,
    required this.text,
    this.detail,
  });

  final IconData icon;
  final String text;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: const BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: AppRadius.banner,
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              color: AppColors.goldSurface,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: AppDimensions.iconSm, color: AppColors.goldDeep),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textStyles.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (detail != null && detail!.trim().isNotEmpty) ...<Widget>[
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                detail!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: context.textStyles.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CustomerPickerRow extends StatelessWidget {
  const _CustomerPickerRow({
    super.key,
    required this.customer,
    required this.selected,
    required this.onTap,
  });

  final Customer customer;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primarySurface : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: AppDimensions.buttonHeightCompact,
                height: AppDimensions.buttonHeightCompact,
                decoration: const BoxDecoration(
                  color: AppColors.surfaceMuted,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.person_outline_rounded,
                  size: AppDimensions.iconMd,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      customer.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textStyles.titleSmall,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      _detail(customer),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textStyles.bodySmall?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_circle_rounded,
                  size: AppDimensions.iconLg,
                  color: AppColors.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _detail(Customer customer) {
    final String phone = customer.phone?.trim() ?? '';
    return phone.isEmpty ? customer.address : phone;
  }
}

class _LoadingOption extends StatelessWidget {
  const _LoadingOption();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 96,
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _OptionError extends StatelessWidget {
  const _OptionError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.only(
        start: AppSpacing.md,
        top: AppSpacing.xs,
        bottom: AppSpacing.xs,
        end: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.errorSurface,
        borderRadius: AppRadius.banner,
        border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.error_outline_rounded,
            size: AppDimensions.iconMd,
            color: AppColors.error,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(message, style: context.textStyles.bodySmall),
          ),
          IconButton(
            onPressed: onRetry,
            tooltip: context.l10n.retryButton,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
    );
  }
}

class _OptionEmpty extends StatelessWidget {
  const _OptionEmpty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: AppRadius.banner,
        border: Border.all(color: context.colors.outlineVariant),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.info_outline_rounded,
            size: AppDimensions.iconMd,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(message, style: context.textStyles.bodyMedium)),
        ],
      ),
    );
  }
}

class _FieldError extends StatelessWidget {
  const _FieldError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: AppSpacing.md,
        top: AppSpacing.xs,
      ),
      child: Text(
        message,
        style: context.textStyles.bodySmall?.copyWith(color: AppColors.error),
      ),
    );
  }
}

class _SubmitBar extends StatelessWidget {
  const _SubmitBar({required this.state, required this.onSubmit});

  final CreateJobState state;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: context.colors.outlineVariant)),
        ),
        child: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              return Align(
                alignment: Alignment.center,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AppDimensions.contentMaxWidth,
                  ),
                  child: Padding(
                    padding: AppPageGutter.withVertical(
                      constraints.maxWidth,
                      top: AppSpacing.sm,
                      bottom: AppSpacing.md,
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        key: const Key('create_and_assign_job_button'),
                        // Required-field validation still happens in the Cubit
                        // after the existing deliberate submit tap. Only an
                        // in-flight request disables this primary action.
                        onPressed: state.isSubmitting ? null : onSubmit,
                        icon: state.isSubmitting
                            ? const SizedBox(
                                width: AppDimensions.iconSm,
                                height: AppDimensions.iconSm,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(
                                Icons.add_task_rounded,
                                size: AppDimensions.iconMd,
                              ),
                        label: Text(context.l10n.createAndAssignJobButton),
                      ),
                    ),
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
