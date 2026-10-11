import 'package:field_service/app/di/injection.dart';
import 'package:field_service/app/router/app_routes.dart';
import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_radius.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/core/widgets/app_bottom_nav.dart';
import 'package:field_service/core/widgets/app_page_body.dart';
import 'package:field_service/core/widgets/app_section_header.dart';
import 'package:field_service/core/widgets/app_state_views.dart';
import 'package:field_service/features/authentication/domain/entities/app_user.dart';
import 'package:field_service/features/authentication/presentation/cubit/authentication_cubit.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_category.dart';
import 'package:field_service/features/jobs/domain/entities/job_status.dart';
import 'package:field_service/features/jobs/presentation/cubit/jobs_cubit.dart';
import 'package:field_service/features/jobs/presentation/cubit/jobs_state.dart';
import 'package:field_service/features/jobs/presentation/utils/job_label_mapper.dart';
import 'package:field_service/features/jobs/presentation/widgets/dashboard_category_card.dart';
import 'package:field_service/features/jobs/presentation/widgets/job_status_badge.dart';
import 'package:field_service/features/jobs/presentation/widgets/jobs_error_state.dart';
import 'package:field_service/features/jobs/presentation/widgets/jobs_list_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// Technician home (route `/` for technician roles).
///
/// Layout follows the one question a technician has when opening the app:
/// *what do I do next?* So the work itself comes first and everything else is
/// context around it:
///
/// 1. greeting — plain text on the canvas, not a card;
/// 2. a single compact status strip (real counts, hairline separated);
/// 3. the current job — the only prominent card on the screen, with its action;
/// 4. the remaining assigned jobs as a quiet list;
/// 5. category shortcuts;
/// 6. the two secondary entries at the end, so creating a customer and job is
///    reachable but never louder than the queue it feeds.
///
/// Customer management stays admin-only — no tile, no route (the router guard
/// refuses `/customers` for technicians regardless of this screen).
class TechnicianHomePage extends StatelessWidget {
  const TechnicianHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppUser? user = context.read<AuthenticationCubit?>()?.state.user;
    final bool isLoading = context.select<AuthenticationCubit, bool>(
      (AuthenticationCubit cubit) => cubit.state.isLoading,
    );

    return BlocProvider<JobsCubit>(
      create: (_) => sl<JobsCubit>()..loadJobs(),
      child: AppPageBody(
        appBar: AppBar(
          title: Text(l10n.technicianHomeTitle),
          actions: <Widget>[
            IconButton(
              tooltip: l10n.logoutButton,
              icon: const Icon(
                Icons.logout_outlined,
                size: AppDimensions.iconMd,
              ),
              onPressed: isLoading
                  ? null
                  : () => context.read<AuthenticationCubit>().signOut(),
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
        ),
        bottomNavigationBar: const AppBottomNav(
          isAdmin: false,
          selectedIndex: 0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _Greeting(user: user),
            const SizedBox(height: AppSpacing.xl),
            const _StatusStrip(),
            const SizedBox(height: AppSpacing.xxl),
            const _JobSections(),
            const SizedBox(height: AppSpacing.xxl),
            const _CategoryShortcuts(),
            const SizedBox(height: AppSpacing.xxl),
            const _SecondaryActions(),
          ],
        ),
      ),
    );
  }
}

/// The welcome line. Open text on the cream canvas: the previous boxed header
/// card (avatar + name + a decorative hammer icon) spent 88px of a phone
/// screen on chrome before showing any work.
class _Greeting extends StatelessWidget {
  const _Greeting({required this.user});

  final AppUser? user;

  String get _displayName {
    final String? name = user?.name;
    if (name != null && name.trim().isNotEmpty) {
      return name.trim();
    }
    return user?.email ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          _displayName.isNotEmpty
              ? l10n.welcomeNameLabel(_displayName)
              : l10n.welcomeTechnician,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: context.textStyles.headlineMedium,
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          l10n.roleTechnicianLabel,
          style: context.textStyles.bodySmall?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Real counts in one hairline-separated strip.
///
/// One bordered surface with three vertical rules instead of four tiles: the
/// numbers stay comparable at a glance and the screen keeps its calm. Nothing
/// here is invented — every figure is counted from the jobs the existing
/// RLS-scoped query returned.
class _StatusStrip extends StatelessWidget {
  const _StatusStrip();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return BlocBuilder<JobsCubit, JobsState>(
      builder: (BuildContext context, JobsState state) {
        if (state.status != JobsStatus.success) {
          // No data, no numbers. A strip of zeros would be a fabricated
          // metric, so the strip stays a hairline placeholder until real
          // counts exist.
          return const SizedBox.shrink();
        }

        final List<Job> jobs = state.jobs;
        final int assigned = jobs
            .where((Job j) => j.status.value == JobStatus.assigned)
            .length;
        final int inProgress = jobs
            .where(
              (Job j) =>
                  j.status.value == JobStatus.inProgress ||
                  j.status.value == JobStatus.started,
            )
            .length;
        final int completed = jobs
            .where((Job j) => j.status.value == JobStatus.completed)
            .length;

        return Container(
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: AppRadius.card,
            border: Border.all(color: context.colors.outlineVariant),
          ),
          child: IntrinsicHeight(
            child: Row(
              children: <Widget>[
                _StatusCell(label: l10n.totalJobsLabel, value: jobs.length),
                const _StatusDivider(),
                _StatusCell(label: l10n.statusAssigned, value: assigned),
                const _StatusDivider(),
                _StatusCell(label: l10n.statusInProgress, value: inProgress),
                const _StatusDivider(),
                _StatusCell(label: l10n.statusCompleted, value: completed),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StatusDivider extends StatelessWidget {
  const _StatusDivider();

  @override
  Widget build(BuildContext context) => VerticalDivider(
    width: 1,
    thickness: 1,
    color: context.colors.outlineVariant,
  );
}

class _StatusCell extends StatelessWidget {
  const _StatusCell({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        label: '$label: $value',
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: AppSpacing.md,
          ),
          child: Column(
            children: <Widget>[
              Text(
                '$value',
                style: context.textStyles.titleLarge?.copyWith(
                  color: context.colors.primary,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                label,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: context.textStyles.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The work itself: the job that needs action, then everything still assigned.
class _JobSections extends StatelessWidget {
  const _JobSections();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return BlocBuilder<JobsCubit, JobsState>(
      builder: (BuildContext context, JobsState state) {
        final JobsCubit cubit = context.read<JobsCubit>();

        switch (state.status) {
          case JobsStatus.initial:
          case JobsStatus.loading:
            return AppLoadingStateView(label: l10n.jobsLoadingLabel);
          case JobsStatus.failure:
            return JobsErrorState(onRetry: cubit.loadJobs);
          case JobsStatus.success:
            final List<Job> jobs = state.jobs;
            if (jobs.isEmpty) {
              return const _NoAssignedJobs();
            }

            final List<Job> inProgress = jobs
                .where(
                  (Job j) =>
                      j.status.value == JobStatus.inProgress ||
                      j.status.value == JobStatus.started,
                )
                .toList();
            final List<Job> assigned = jobs
                .where((Job j) => j.status.value == JobStatus.assigned)
                .toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (final Job job in inProgress) ...<Widget>[
                  AppSectionHeader(title: l10n.currentJobTitle),
                  _CurrentJobCard(job: job),
                  const SizedBox(height: AppSpacing.xl),
                ],
                if (assigned.isNotEmpty) ...<Widget>[
                  AppSectionHeader(
                    title: l10n.myJobsTitle,
                    showRule: false,
                  ),
                  for (final Job job in assigned) ...<Widget>[
                    JobsListItem(
                      job: job,
                      showAssignedTechnician: false,
                      showNextAction: true,
                      onTap: () => _openJob(context, job.id),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                ],
              ],
            );
        }
      },
    );
  }

  void _openJob(BuildContext context, String jobId) {
    context.goNamed(
      'jobDetails',
      pathParameters: <String, String>{'id': jobId},
    );
  }
}

/// The featured job. The one card allowed to be loud: a burgundy accent edge
/// marks it as the thing to act on, and the action is a full-width button so
/// it is tappable with a glove on.
class _CurrentJobCard extends StatelessWidget {
  const _CurrentJobCard({required this.job});

  final Job job;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final JobLabelMapper mapper = JobLabelMapper(l10n);

    void open() => context.goNamed(
      'jobDetails',
      pathParameters: <String, String>{'id': job.id},
    );

    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: context.colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: open,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Accent edge — the only place the brand colour fills a surface.
              Container(width: 4, color: context.colors.primary),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              '#${job.jobNumber}',
                              style: context.textStyles.titleLarge,
                            ),
                          ),
                          JobStatusBadge(
                            label: mapper.statusLabel(job.status),
                            status: job.status,
                          ),
                        ],
                      ),
                      if ((job.customerName ?? '').isNotEmpty) ...<Widget>[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          job.customerName!,
                          style: context.textStyles.titleMedium,
                        ),
                      ],
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        mapper.jobTypeLabel(job.jobType),
                        style: context.textStyles.bodySmall?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          key: Key('continue_job_${job.id}'),
                          onPressed: open,
                          icon: const Icon(
                            Icons.arrow_forward_rounded,
                            size: AppDimensions.iconMd,
                          ),
                          label: Text(l10n.continueJobButton),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Category shortcuts. The counts are real; when the list has not loaded the
/// card shows no number at all rather than a zero.
class _CategoryShortcuts extends StatelessWidget {
  const _CategoryShortcuts();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return BlocBuilder<JobsCubit, JobsState>(
      builder: (BuildContext context, JobsState state) {
        final bool hasData = state.status == JobsStatus.success;
        final List<Job> jobs = hasData ? state.jobs : const <Job>[];
        final int kitchen = jobs
            .where((Job job) => job.jobType == JobCategory.kitchenRenovation)
            .length;
        final int home = jobs
            .where((Job job) => job.jobType == JobCategory.homeRenovation)
            .length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AppSectionHeader(title: l10n.categoriesTitle),
            DashboardCategoryCard(
              key: const Key('category_card_kitchen'),
              title: l10n.jobCategoryKitchenRenovation,
              icon: Icons.kitchen_outlined,
              jobCount: hasData ? kitchen : null,
              countLabel: l10n.jobsCountLabel,
              semanticLabel:
                  '${l10n.jobCategoryKitchenRenovation}'
                  '${hasData ? ', ${l10n.jobsCountLabel(kitchen)}' : ''}',
              isKitchen: true,
              onTap: () => context.go(
                '${AppRoutes.jobs}?category=${JobCategory.kitchenRenovation}',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            DashboardCategoryCard(
              key: const Key('category_card_home_renovation'),
              title: l10n.jobCategoryHomeRenovation,
              icon: Icons.house_siding_outlined,
              jobCount: hasData ? home : null,
              countLabel: l10n.jobsCountLabel,
              semanticLabel:
                  '${l10n.jobCategoryHomeRenovation}'
                  '${hasData ? ', ${l10n.jobsCountLabel(home)}' : ''}',
              isKitchen: false,
              onTap: () => context.go(
                '${AppRoutes.jobs}?category=${JobCategory.homeRenovation}',
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The two secondary entries. Outlined, side by side, and placed after the
/// work: reachable in one tap, never louder than the queue.
class _SecondaryActions extends StatelessWidget {
  const _SecondaryActions();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: <Widget>[
        _SecondaryAction(
          buttonKey: const Key('nav_create_customer_job'),
          icon: Icons.person_add_alt_1_outlined,
          label: l10n.technicianCreateJobEntryTitle,
          onTap: () => context.push(AppRoutes.jobTechnicianCreate),
        ),
        _SecondaryAction(
          buttonKey: const Key('nav_jobs'),
          icon: Icons.event_note_outlined,
          label: l10n.viewJobsButton,
          onTap: () => context.go(AppRoutes.jobs),
        ),
      ],
    );
  }
}

class _SecondaryAction extends StatelessWidget {
  const _SecondaryAction({
    required this.buttonKey,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  /// Lives on the button itself — putting it on this wrapper too would make
  /// `find.byKey` match two widgets for one destination.
  final Key buttonKey;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      key: buttonKey,
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        alignment: AlignmentDirectional.centerStart,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      ),
      icon: Icon(icon, size: AppDimensions.iconMd),
      label: Flexible(
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

/// Empty state — quiet, not apologetic, and honest: nothing has been assigned
/// yet. Kept inside a bordered surface so it does not look like a gap in the
/// layout.
class _NoAssignedJobs extends StatelessWidget {
  const _NoAssignedJobs();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return Container(
      key: const Key('tech_jobs_empty'),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: context.colors.outlineVariant),
      ),
      child: AppEmptyStateView(
        icon: Icons.event_note_outlined,
        title: l10n.noAssignedJobsTitle,
        message: l10n.noAssignedJobsSubtitle,
      ),
    );
  }
}
