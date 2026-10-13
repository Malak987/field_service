import 'package:field_service/app/di/injection.dart';
import 'package:field_service/app/router/app_routes.dart';
import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_colors.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_radius.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/core/widgets/app_bottom_nav.dart';
import 'package:field_service/core/widgets/app_page_body.dart';
import 'package:field_service/core/widgets/app_standard_page_header.dart';
import 'package:field_service/core/widgets/app_state_views.dart';
import 'package:field_service/core/widgets/app_status_badge.dart';
import 'package:field_service/core/widgets/app_surface_panel.dart';
import 'package:field_service/features/authentication/presentation/cubit/authentication_cubit.dart';
import 'package:field_service/features/authentication/presentation/widgets/auth_logo.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_category.dart';
import 'package:field_service/features/jobs/domain/entities/job_status.dart';
import 'package:field_service/features/jobs/presentation/cubit/jobs_cubit.dart';
import 'package:field_service/features/jobs/presentation/cubit/jobs_state.dart';
import 'package:field_service/features/jobs/presentation/utils/job_label_mapper.dart';
import 'package:field_service/features/jobs/presentation/widgets/job_status_badge.dart';
import 'package:field_service/features/jobs/presentation/widgets/jobs_list_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// The jobs index for both roles.
///
/// Role visibility remains entirely in the existing JobsCubit/query/RLS path.
/// This page only provides a responsive way to search, filter and open jobs
/// already available in the presentation state.
class JobsPage extends StatelessWidget {
  const JobsPage({super.key, this.categoryFilter});

  /// Existing optional `?category=` filter used by the category shortcuts.
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

  /// The existing role-aware navigation selection remains tied to the category
  /// query. An administrator's unfiltered list intentionally highlights none.
  int? get _navIndex {
    if (!widget.isAdmin) {
      return AppNavDestinations.jobsIndex(isAdmin: false);
    }
    return switch (_categoryFilter) {
      JobCategory.kitchenRenovation => AppNavDestinations.jobsIndex(
        isAdmin: true,
      ),
      JobCategory.homeRenovation => 2,
      _ => null,
    };
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
    if (_categoryFilter.isEmpty) {
      return jobs;
    }
    return jobs
        .where((Job job) => job.jobType == _categoryFilter)
        .toList();
  }

  List<Job> _visibleJobs(List<Job> jobs, AppLocalizations l10n) {
    final String query = _searchController.text.trim().toLowerCase();
    final JobLabelMapper mapper = JobLabelMapper(l10n);

    return _categoryJobs(jobs).where((Job job) {
      if (_statusFilter.isNotEmpty && job.status.value != _statusFilter) {
        return false;
      }
      if (query.isEmpty) {
        return true;
      }
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

    return AppNavigationScaffold(
      appBar: AppBar(
        title: Text(widget.isAdmin ? l10n.jobsTitle : l10n.myJobsTitle),
        actions: <Widget>[
          IconButton(
            tooltip: l10n.logoutButton,
            icon: const Icon(
              Icons.logout_outlined,
              size: AppDimensions.iconMd,
            ),
            onPressed: () => context.read<AuthenticationCubit?>()?.signOut(),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      navigation: AppNavSpec(
        isAdmin: widget.isAdmin,
        selectedIndex: _navIndex,
      ),
      // Preserve the existing admin-only creation route and refresh behaviour.
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
      child: BlocBuilder<JobsCubit, JobsState>(
        builder: (BuildContext context, JobsState state) {
          final JobsCubit cubit = context.read<JobsCubit>();
          final bool hasSnapshot = state.status == JobsStatus.success;
          final List<Job> jobs = hasSnapshot ? state.jobs : const <Job>[];
          final List<Job> visibleJobs = hasSnapshot
              ? _visibleJobs(jobs, l10n)
              : const <Job>[];
          final bool showControls = hasSnapshot && jobs.isNotEmpty;

          return AppContentWidth(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final double width = constraints.maxWidth;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: AppPageGutter.withVertical(
                    width,
                    top: AppSpacing.xl,
                    bottom: AppSpacing.md,
                  ),
                  child: _JobsHeader(
                    title: widget.isAdmin ? l10n.jobsTitle : l10n.myJobsTitle,
                    subtitle: l10n.searchJobsHint,
                    countLabel: hasSnapshot
                        ? l10n.jobsCountLabel(jobs.length)
                        : null,
                  ),
                ),
                if (showControls)
                  Padding(
                    padding: AppPageGutter.withVertical(
                      width,
                      top: AppSpacing.xs,
                      bottom: AppSpacing.md,
                    ),
                    child: _JobsListControls(
                      searchController: _searchController,
                      searchText: _searchController.text,
                      statusFilter: _statusFilter,
                      categoryFilter: _categoryFilter,
                      availableStatuses: _uniqueStatuses(jobs),
                      isFiltered: _hasActiveFilters,
                      onSearchChanged: (_) => setState(() {}),
                      onStatusChanged: (String value) =>
                          setState(() => _statusFilter = value),
                      onCategoryChanged: (String value) =>
                          setState(() => _categoryFilter = value),
                      onClear: _clearFilters,
                    ),
                  ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: cubit.loadJobs,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: AppPageGutter.withVertical(
                        width,
                        top: AppSpacing.md,
                        bottom: widget.isAdmin ? 104 : AppSpacing.xxl,
                      ),
                      children: <Widget>[
                        if (hasSnapshot && showControls) ...<Widget>[
                          _JobsSummary(jobs: visibleJobs),
                          const SizedBox(height: AppSpacing.lg),
                        ],
                        switch (state.status) {
                          JobsStatus.initial || JobsStatus.loading =>
                            AppSurfacePanel(
                              divideRows: false,
                              children: <Widget>[
                                AppLoadingStateView(
                                  label: l10n.jobsLoadingLabel,
                                ),
                              ],
                            ),
                          JobsStatus.failure => AppSurfacePanel(
                            divideRows: false,
                            children: <Widget>[
                              AppErrorStateView(
                                title: l10n.jobsErrorTitle,
                                message: l10n.jobsErrorSubtitle,
                                retryLabel: l10n.tryAgainButton,
                                onRetry: cubit.loadJobs,
                              ),
                            ],
                          ),
                          JobsStatus.success when jobs.isEmpty =>
                            const _JobsEmptyPanel(),
                          JobsStatus.success when visibleJobs.isEmpty =>
                            _NoMatchingJobs(onClear: _clearFilters),
                          JobsStatus.success => _JobsListGrid(
                            jobs: visibleJobs,
                            isAdmin: widget.isAdmin,
                            onTap: (Job job) => context.goNamed(
                              'jobDetails',
                              pathParameters: <String, String>{'id': job.id},
                            ),
                          ),
                        },
                      ],
                    ),
                  ),
                ),
                  ],
                );
              },
            ),
          );
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

class _JobsHeader extends StatelessWidget {
  const _JobsHeader({
    required this.title,
    required this.subtitle,
    required this.countLabel,
  });

  final String title;
  final String subtitle;
  final String? countLabel;

  @override
  Widget build(BuildContext context) => AppStandardPageHeader(
    logoAssetName: AuthLogo.assetName,
    title: title,
    subtitle: subtitle,
    supporting: countLabel == null
        ? null
        : AppStatusBadge(
            icon: Icons.assignment_outlined,
            label: countLabel!,
            tone: AppStatusTone.brand,
          ),
  );
}

/// Search and filters are one control surface. Search remains the first control
/// on a phone while tablet/wide layouts keep the status field beside it.
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

    final Widget search = TextField(
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
    );
    final Widget status = DropdownButtonFormField<String>(
      key: const Key('jobs_status_filter'),
      value: statusFilter,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: l10n.filterStatusLabel,
        prefixIcon: const Icon(Icons.tune_rounded),
      ),
      items: <DropdownMenuItem<String>>[
        for (final String value in statuses)
          DropdownMenuItem<String>(
            value: value,
            child: Text(
              value.isEmpty
                  ? l10n.allStatusesLabel
                  : mapper.statusLabel(JobStatus(value)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (String? value) => onStatusChanged(value ?? ''),
    );

    return AppSurfacePanel(
      divideRows: false,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final bool useInlineSearch =
                  constraints.maxWidth >= AppDimensions.tabletBreakpoint;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (useInlineSearch)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(flex: 3, child: search),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(flex: 2, child: status),
                      ],
                    )
                  else ...<Widget>[
                    search,
                    const SizedBox(height: AppSpacing.sm),
                    status,
                  ],
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          l10n.filterCategoryLabel,
                          style: context.textStyles.titleSmall,
                        ),
                      ),
                      if (isFiltered)
                        TextButton.icon(
                          key: const Key('jobs_clear_filters'),
                          onPressed: onClear,
                          icon: const Icon(
                            Icons.filter_alt_off_outlined,
                            size: AppDimensions.iconSm,
                          ),
                          label: Text(l10n.clearFiltersButton),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
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
                        selected:
                            categoryFilter == JobCategory.kitchenRenovation,
                        onSelected: () =>
                            onCategoryChanged(JobCategory.kitchenRenovation),
                      ),
                      _CategoryFilterChip(
                        label: l10n.jobCategoryHomeRenovation,
                        selected: categoryFilter == JobCategory.homeRenovation,
                        onSelected: () =>
                            onCategoryChanged(JobCategory.homeRenovation),
                      ),
                    ],
                  ),
                  if (isFiltered) ...<Widget>[
                    const SizedBox(height: AppSpacing.md),
                    _ActiveFilters(
                      searchText: searchText,
                      statusFilter: statusFilter,
                      categoryFilter: categoryFilter,
                      mapper: mapper,
                      searchController: searchController,
                      onSearchChanged: onSearchChanged,
                      onStatusChanged: onStatusChanged,
                      onCategoryChanged: onCategoryChanged,
                      clearSearchTooltip: l10n.clearSearchButton,
                      clearFilterTooltip: l10n.clearFiltersButton,
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ActiveFilters extends StatelessWidget {
  const _ActiveFilters({
    required this.searchText,
    required this.statusFilter,
    required this.categoryFilter,
    required this.mapper,
    required this.searchController,
    required this.onSearchChanged,
    required this.onStatusChanged,
    required this.onCategoryChanged,
    required this.clearSearchTooltip,
    required this.clearFilterTooltip,
  });

  final String searchText;
  final String statusFilter;
  final String categoryFilter;
  final JobLabelMapper mapper;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<String> onCategoryChanged;
  final String clearSearchTooltip;
  final String clearFilterTooltip;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: <Widget>[
        if (searchText.trim().isNotEmpty)
          _ActiveFilterChip(
            chipKey: const Key('jobs_filter_chip_search'),
            icon: Icons.search_rounded,
            label: searchText.trim(),
            removeTooltip: clearSearchTooltip,
            onRemove: () {
              searchController.clear();
              onSearchChanged('');
            },
          ),
        if (statusFilter.isNotEmpty)
          _ActiveFilterChip(
            chipKey: const Key('jobs_filter_chip_status'),
            icon: Icons.tune_rounded,
            label: mapper.statusLabel(JobStatus(statusFilter)),
            removeTooltip: clearFilterTooltip,
            onRemove: () => onStatusChanged(''),
          ),
        if (categoryFilter.isNotEmpty)
          _ActiveFilterChip(
            chipKey: const Key('jobs_filter_chip_category'),
            icon: Icons.category_outlined,
            label: mapper.jobTypeLabel(categoryFilter),
            removeTooltip: clearFilterTooltip,
            onRemove: () => onCategoryChanged(''),
          ),
      ],
    );
  }
}

class _ActiveFilterChip extends StatelessWidget {
  const _ActiveFilterChip({
    required this.chipKey,
    required this.icon,
    required this.label,
    required this.removeTooltip,
    required this.onRemove,
  });

  final Key chipKey;
  final IconData icon;
  final String label;
  final String removeTooltip;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => InputChip(
    key: chipKey,
    avatar: Icon(icon, size: AppDimensions.iconSm, color: AppColors.primaryDark),
    label: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: context.textStyles.bodySmall?.copyWith(
        color: AppColors.primaryDark,
        fontWeight: FontWeight.w600,
      ),
    ),
    deleteIcon: const Icon(Icons.close_rounded, size: AppDimensions.iconSm),
    deleteButtonTooltipMessage: removeTooltip,
    onDeleted: onRemove,
    backgroundColor: AppColors.primarySurface,
    side: const BorderSide(color: AppColors.primary),
    shape: const StadiumBorder(),
  );
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
    labelStyle: context.textStyles.bodySmall?.copyWith(
      color: selected
          ? AppColors.primaryDark
          : context.colors.onSurfaceVariant,
      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
    ),
    side: BorderSide(
      color: selected ? AppColors.primary : context.colors.outlineVariant,
    ),
    shape: const StadiumBorder(),
  );
}

/// Shows only figures calculated from the currently visible filtered list.
class _JobsSummary extends StatelessWidget {
  const _JobsSummary({required this.jobs});

  final List<Job> jobs;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final JobLabelMapper mapper = JobLabelMapper(l10n);
    final Map<String, int> counts = <String, int>{};
    for (final Job job in jobs) {
      counts.update(
        job.status.value,
        (int count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    final List<String> statuses = counts.keys.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          l10n.jobsCountLabel(jobs.length),
          style: context.textStyles.titleSmall,
        ),
        if (statuses.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              for (final String status in statuses)
                _StatusCountBadge(
                  label: mapper.statusLabel(JobStatus(status)),
                  count: counts[status]!,
                  status: JobStatus(status),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _StatusCountBadge extends StatelessWidget {
  const _StatusCountBadge({
    required this.label,
    required this.count,
    required this.status,
  });

  final String label;
  final int count;
  final JobStatus status;

  @override
  Widget build(BuildContext context) {
    final (Color foreground, Color background) = JobStatusBadge.styleFor(
      context,
      status,
    );

    return Semantics(
      label: '$label: $count',
      child: Container(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: const BorderRadius.all(Radius.circular(999)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(_iconFor(status), size: AppDimensions.iconSm, color: foreground),
            const SizedBox(width: AppSpacing.xs),
            Text(
              '$label · $count',
              style: context.textStyles.labelSmall?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(JobStatus value) => switch (value.value) {
    JobStatus.assigned => Icons.assignment_outlined,
    JobStatus.started || JobStatus.inProgress => Icons.pending_actions_rounded,
    JobStatus.completed => Icons.check_circle_outline_rounded,
    JobStatus.cancelled => Icons.cancel_outlined,
    _ => Icons.info_outline_rounded,
  };
}

class _JobsListGrid extends StatelessWidget {
  const _JobsListGrid({
    required this.jobs,
    required this.isAdmin,
    required this.onTap,
  });

  final List<Job> jobs;
  final bool isAdmin;
  final ValueChanged<Job> onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool useTwoColumns =
            constraints.maxWidth >= AppDimensions.tabletBreakpoint;
        final double itemWidth = useTwoColumns
            ? (constraints.maxWidth - AppSpacing.md) / 2
            : constraints.maxWidth;

        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: <Widget>[
            for (final Job job in jobs)
              SizedBox(
                width: itemWidth,
                child: JobsListCard(
                  key: ValueKey<String>('job_card_${job.id}'),
                  job: job,
                  isAdmin: isAdmin,
                  onTap: () => onTap(job),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _JobsEmptyPanel extends StatelessWidget {
  const _JobsEmptyPanel();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    return AppSurfacePanel(
      divideRows: false,
      children: <Widget>[
        AppEmptyStateView(
          icon: Icons.event_note_outlined,
          title: l10n.jobsEmptyTitle,
          message: l10n.jobsEmptySubtitle,
        ),
      ],
    );
  }
}

class _NoMatchingJobs extends StatelessWidget {
  const _NoMatchingJobs({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return AppSurfacePanel(
      divideRows: false,
      children: <Widget>[
        AppEmptyStateView(
          icon: Icons.search_off_rounded,
          title: l10n.noJobsMatchTitle,
          message: l10n.noJobsMatchSubtitle,
          action: OutlinedButton.icon(
            onPressed: onClear,
            icon: const Icon(
              Icons.filter_alt_off_outlined,
              size: AppDimensions.iconSm,
            ),
            label: Text(l10n.clearFiltersButton),
          ),
        ),
      ],
    );
  }
}
