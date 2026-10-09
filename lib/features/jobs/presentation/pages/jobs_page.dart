import 'package:field_service/app/di/injection.dart';
import 'package:field_service/app/router/app_routes.dart';
import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_colors.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_radius.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/core/widgets/app_bottom_nav.dart';
import 'package:field_service/core/widgets/language_switcher.dart';
import 'package:field_service/features/authentication/presentation/cubit/authentication_cubit.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_category.dart';
import 'package:field_service/features/jobs/domain/entities/job_status.dart';
import 'package:field_service/features/jobs/presentation/cubit/jobs_cubit.dart';
import 'package:field_service/features/jobs/presentation/cubit/jobs_state.dart';
import 'package:field_service/features/jobs/presentation/utils/job_label_mapper.dart';
import 'package:field_service/features/jobs/presentation/widgets/jobs_empty_state.dart';
import 'package:field_service/features/jobs/presentation/widgets/jobs_error_state.dart';
import 'package:field_service/features/jobs/presentation/widgets/jobs_list_card.dart';
import 'package:field_service/features/jobs/presentation/widgets/jobs_loading_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// Jobs list for both roles. Role visibility remains governed by existing RLS;
/// this page only filters the jobs already loaded into presentation state.
class JobsPage extends StatelessWidget {
  const JobsPage({super.key, this.categoryFilter});

  /// Existing optional `?category=` filter used by Admin category shortcuts.
  final String? categoryFilter;

  @override
  Widget build(BuildContext context) {
    final bool isAdmin =
        context.read<AuthenticationCubit?>()?.state.user?.isAdmin ?? false;

    return BlocProvider<JobsCubit>(
      create: (_) => sl<JobsCubit>()..loadJobs(),
      child: _JobsPageView(isAdmin: isAdmin, categoryFilter: categoryFilter),
    );
  }
}

class _JobsPageView extends StatefulWidget {
  const _JobsPageView({required this.isAdmin, this.categoryFilter});

  final bool isAdmin;
  final String? categoryFilter;

  @override
  State<_JobsPageView> createState() => _JobsPageViewState();
}

class _JobsPageViewState extends State<_JobsPageView> {
  final TextEditingController _searchController = TextEditingController();
  String _statusFilter = '';
  String _categoryFilter = '';

  int get _navIndex {
    // The administrator has dedicated Jobs and Customers tabs; category
    // filtering remains available within the jobs list, not in the app shell.
    return 1;
  }

  @override
  void initState() {
    super.initState();
    _categoryFilter = widget.categoryFilter ?? '';
  }

  @override
  void didUpdateWidget(covariant _JobsPageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.categoryFilter != widget.categoryFilter) {
      _categoryFilter = widget.categoryFilter ?? '';
      _statusFilter = '';
      _searchController.clear();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _clearFilters() {
    setState(() {
      _searchController.clear();
      _statusFilter = '';
      _categoryFilter = '';
    });
  }

  List<Job> _categoryJobs(List<Job> jobs) {
    if (_categoryFilter.isEmpty) return jobs;
    return jobs.where((Job job) => job.jobType == _categoryFilter).toList();
  }

  List<Job> _visibleJobs(List<Job> jobs, AppLocalizations l10n) {
    final String query = _searchController.text.trim().toLowerCase();
    final JobLabelMapper mapper = JobLabelMapper(l10n);
    return _categoryJobs(jobs).where((Job job) {
      if (_statusFilter.isNotEmpty && job.status.value != _statusFilter) {
        return false;
      }
      if (query.isEmpty) return true;
      final String searchable = <String?>[
        job.jobNumber.toString(),
        job.customerName,
        job.jobType,
        mapper.jobTypeLabel(job.jobType),
        job.status.value,
        mapper.statusLabel(job.status),
        job.description,
        if (widget.isAdmin) job.assignedEmployeeName,
      ].whereType<String>().join(' ').toLowerCase();
      return searchable.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isAdmin ? l10n.jobsTitle : l10n.myJobsTitle),
        actions: <Widget>[
          const Padding(
            padding: EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.sm),
            child: Center(child: LanguageSwitcher()),
          ),
          IconButton(
            tooltip: l10n.logoutButton,
            icon: const Icon(Icons.logout_outlined, size: AppDimensions.iconMd),
            onPressed: () =>
                context.read<AuthenticationCubit?>()?.signOut(),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      // Keep the existing admin create/assign workflow and post-create refresh.
      floatingActionButton: widget.isAdmin
          ? FloatingActionButton.extended(
              key: const Key('create_job_fab'),
              onPressed: () async {
                await context.push(AppRoutes.jobCreate);
                if (context.mounted) {
                  context.read<JobsCubit>().loadJobs();
                }
              },
              icon: const Icon(Icons.add_rounded, size: AppDimensions.iconMd),
              label: Text(l10n.createJobButton),
            )
          : null,
      bottomNavigationBar: AppBottomNav(
        isAdmin: widget.isAdmin,
        selectedIndex: _navIndex,
      ),
      body: BlocBuilder<JobsCubit, JobsState>(
        builder: (BuildContext context, JobsState state) {
          final JobsCubit cubit = context.read<JobsCubit>();
          switch (state.status) {
            case JobsStatus.initial:
            case JobsStatus.loading:
              return const JobsLoadingView();
            case JobsStatus.failure:
              return JobsErrorState(onRetry: cubit.loadJobs);
            case JobsStatus.success:
              final List<Job> visibleJobs = _visibleJobs(state.jobs, l10n);
              return RefreshIndicator(
                onRefresh: cubit.loadJobs,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsetsDirectional.fromSTEB(
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.lg,
                    widget.isAdmin ? 104 : AppSpacing.xxl,
                  ),
                  children: <Widget>[
                    _JobsListControls(
                      searchController: _searchController,
                      searchText: _searchController.text,
                      statusFilter: _statusFilter,
                      categoryFilter: _categoryFilter,
                      availableStatuses: _uniqueStatuses(state.jobs),
                      isFiltered: _hasActiveFilters,
                      onSearchChanged: (String value) => setState(() {}),
                      onStatusChanged: (String value) =>
                          setState(() => _statusFilter = value),
                      onCategoryChanged: (String value) =>
                          setState(() => _categoryFilter = value),
                      onClear: _clearFilters,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _JobsSummary(jobs: visibleJobs),
                    const SizedBox(height: AppSpacing.lg),
                    if (state.jobs.isEmpty)
                      const JobsEmptyState()
                    else if (visibleJobs.isEmpty)
                      _NoMatchingJobs(onClear: _clearFilters)
                    else
                      for (int index = 0; index < visibleJobs.length; index++) ...<Widget>[
                        JobsListCard(
                          key: ValueKey<String>('job_card_${visibleJobs[index].id}'),
                          job: visibleJobs[index],
                          isAdmin: widget.isAdmin,
                          onTap: () => context.goNamed(
                            'jobDetails',
                            pathParameters: <String, String>{
                              'id': visibleJobs[index].id,
                            },
                          ),
                        ),
                        if (index != visibleJobs.length - 1)
                          const SizedBox(height: AppSpacing.sm),
                      ],
                  ],
                ),
              );
          }
        },
      ),
    );
  }

  bool get _hasActiveFilters =>
      _searchController.text.trim().isNotEmpty ||
      _statusFilter.isNotEmpty ||
      _categoryFilter.isNotEmpty;

  List<String> _uniqueStatuses(List<Job> jobs) => jobs
      .map((Job job) => job.status.value)
      .where((String status) => status.isNotEmpty)
      .toSet()
      .toList()
    ..sort();
}

class _JobsListControls extends StatelessWidget {
  const _JobsListControls({
    required this.searchController,
    required this.searchText,
    required this.statusFilter,
    required this.categoryFilter,
    required this.availableStatuses,
    required this.isFiltered,
    required this.onSearchChanged,
    required this.onStatusChanged,
    required this.onCategoryChanged,
    required this.onClear,
  });

  final TextEditingController searchController;
  final String searchText;
  final String statusFilter;
  final String categoryFilter;
  final List<String> availableStatuses;
  final bool isFiltered;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<String> onCategoryChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final JobLabelMapper mapper = JobLabelMapper(l10n);
    final List<String> statuses = <String>{
      '',
      ...availableStatuses,
      if (statusFilter.isNotEmpty) statusFilter,
    }.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TextField(
          key: const Key('jobs_search_field'),
          controller: searchController,
          onChanged: onSearchChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: l10n.searchJobsHint,
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: searchText.isEmpty
                ? null
                : IconButton(
                    key: const Key('jobs_clear_search'),
                    tooltip: l10n.clearButton,
                    onPressed: () {
                      searchController.clear();
                      onSearchChanged('');
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                l10n.filterCategoryLabel,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            if (isFiltered)
              TextButton.icon(
                key: const Key('jobs_clear_filters'),
                onPressed: onClear,
                icon: const Icon(Icons.filter_alt_off_outlined),
                label: Text(l10n.clearFiltersButton),
              ),
          ],
        ),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: <Widget>[
            _CategoryFilterChip(
              label: l10n.allCategoriesLabel,
              selected: categoryFilter.isEmpty,
              onSelected: () => onCategoryChanged(''),
            ),
            _CategoryFilterChip(
              label: l10n.jobCategoryKitchenRenovation,
              selected: categoryFilter == JobCategory.kitchenRenovation,
              onSelected: () =>
                  onCategoryChanged(JobCategory.kitchenRenovation),
            ),
            _CategoryFilterChip(
              label: l10n.jobCategoryHomeRenovation,
              selected: categoryFilter == JobCategory.homeRenovation,
              onSelected: () => onCategoryChanged(JobCategory.homeRenovation),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        DropdownButtonFormField<String>(
          key: const Key('jobs_status_filter'),
          value: statusFilter,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: l10n.filterStatusLabel,
            prefixIcon: const Icon(Icons.tune_rounded),
          ),
          items: statuses
              .map(
                (String status) => DropdownMenuItem<String>(
                  value: status,
                  child: Text(
                    status.isEmpty ? l10n.allStatusesLabel : mapper.statusLabel(
                      // The mapper is intentionally passed only the raw status
                      // value returned by the loaded jobs.
                      _status(status),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: (String? value) => onStatusChanged(value ?? ''),
        ),
      ],
    );
  }

  JobStatus _status(String value) => JobStatus(value);
}

class _CategoryFilterChip extends StatelessWidget {
  const _CategoryFilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) => ChoiceChip(
    label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    selected: selected,
    onSelected: (_) => onSelected(),
    selectedColor: AppColors.primarySurface,
    labelStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
      color: selected ? AppColors.primaryDark : AppColors.textSecondary,
      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
    ),
    side: BorderSide(color: selected ? AppColors.primary : AppColors.border),
    shape: RoundedRectangleBorder(borderRadius: AppRadius.circular),
  );
}

class _JobsSummary extends StatelessWidget {
  const _JobsSummary({required this.jobs});

  final List<Job> jobs;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final JobLabelMapper mapper = JobLabelMapper(l10n);
    final Map<String, int> counts = <String, int>{};
    for (final Job job in jobs) {
      counts.update(job.status.value, (int count) => count + 1, ifAbsent: () => 1);
    }
    final List<String> statusValues = counts.keys.toList()..sort();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l10n.jobsCountLabel(jobs.length),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (statusValues.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: <Widget>[
                  for (final String status in statusValues)
                    _StatusCountChip(
                      label: mapper.statusLabel(JobStatus(status)),
                      count: counts[status]!,
                      status: JobStatus(status),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusCountChip extends StatelessWidget {
  const _StatusCountChip({
    required this.label,
    required this.count,
    required this.status,
  });

  final String label;
  final int count;
  final JobStatus status;

  @override
  Widget build(BuildContext context) {
    final (Color foreground, Color background) = _statusColors(status);
    return Semantics(
      label: '$label: $count',
      child: Container(
        constraints: const BoxConstraints(minHeight: 32),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: AppRadius.circular,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(_statusIcon(status), size: AppDimensions.iconSm, color: foreground),
            const SizedBox(width: AppSpacing.xs),
            Text(
              '$label · $count',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _statusIcon(JobStatus status) => switch (status.value) {
    JobStatus.assigned => Icons.assignment_outlined,
    JobStatus.started || JobStatus.inProgress => Icons.pending_actions_rounded,
    JobStatus.completed => Icons.check_circle_outline_rounded,
    JobStatus.cancelled => Icons.cancel_outlined,
    _ => Icons.info_outline_rounded,
  };

  static (Color, Color) _statusColors(JobStatus status) =>
      switch (status.value) {
        JobStatus.assigned => (AppColors.primary, AppColors.primarySurface),
        JobStatus.started || JobStatus.inProgress =>
          (AppColors.goldDeep, AppColors.goldSurface),
        JobStatus.completed => (AppColors.primaryDark, AppColors.primarySurface),
        JobStatus.cancelled =>
          (AppColors.textSecondary, AppColors.background),
        _ => (AppColors.textSecondary, AppColors.background),
      };
}

class _NoMatchingJobs extends StatelessWidget {
  const _NoMatchingJobs({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
      child: Column(
        children: <Widget>[
          Icon(Icons.search_off_rounded, size: AppDimensions.iconXl, color: AppColors.textSecondary),
          const SizedBox(height: AppSpacing.md),
          Text(l10n.noJobsMatchTitle, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(l10n.noJobsMatchSubtitle, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: onClear,
            icon: const Icon(Icons.filter_alt_off_outlined),
            label: Text(l10n.clearFiltersButton),
          ),
        ],
      ),
    );
  }
}
