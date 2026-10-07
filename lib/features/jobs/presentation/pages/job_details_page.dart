import 'package:field_service/app/di/injection.dart';
import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/features/authentication/presentation/cubit/authentication_cubit.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_customer_info.dart';
import 'package:field_service/features/jobs/domain/entities/job_status.dart';
import 'package:field_service/features/jobs/presentation/cubit/jobs_cubit.dart';
import 'package:field_service/features/jobs/presentation/cubit/jobs_state.dart';
import 'package:field_service/features/jobs/presentation/utils/job_label_mapper.dart';
import 'package:field_service/features/jobs/presentation/utils/jobs_date_format.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/features/jobs/presentation/services/photo_picker.dart';
import 'package:field_service/features/jobs/presentation/widgets/before_photos_section.dart';
import 'package:field_service/features/jobs/presentation/widgets/job_detail_field.dart';
import 'package:field_service/features/jobs/presentation/widgets/job_start_button.dart';
import 'package:field_service/features/jobs/presentation/widgets/job_status_badge.dart';
import 'package:field_service/features/jobs/presentation/widgets/jobs_empty_state.dart';
import 'package:field_service/features/jobs/presentation/widgets/jobs_error_state.dart';
import 'package:field_service/features/jobs/presentation/widgets/jobs_loading_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Job details (route `/jobs/:id`).
///
/// Presents the data that exists in `public.jobs`, the customer information
/// belonging to THIS job, and — once the job is `in_progress` — its Before
/// Photos.
///
/// Customer access model:
/// * The customer section is fed exclusively by the `get_job_customer`
///   SECURITY DEFINER RPC (via [JobsCubit.loadJobById]) — the server returns
///   it only for jobs the current user is entitled to. The global
///   `customers` table (admin-only in RLS) is never read here, and there is
///   no create/edit/delete/search action for customers on this page for any
///   role. Admins manage customers through the Customers feature.
///
/// Start Job model (technicians only — the admin creates/assigns/monitors):
/// * While the job is `assigned`, the ASSIGNED TECHNICIAN's page shows
///   [JobStartButton]; tapping it queues the start in the durable sync queue
///   (works offline) and flips the local state to `in_progress` immediately.
///   Admins never see the button — they see the job fields (status, started
///   date, assignee) as monitoring information. The server-side `start_job`
///   RPC is the authority: it refuses admins outright, applies the status,
///   the database-generated `started_at` and the `job_started` event
///   atomically, and never twice. Once started, the button disappears and
///   the Start Date field shows the server timestamp once the job is
///   (re)loaded.
///
/// Before Photos model:
/// * The section appears once the job is started. While it is `in_progress`,
///   **Add Before Photo** opens a camera-first source sheet; the picked image
///   is copied into app-owned storage immediately (offline-safe), registered
///   locally with an automatic capture timestamp and its upload is queued in
///   the durable sync queue. The shared sync engine uploads the bytes to
///   Supabase Storage (upsert on a stable path) and registers the file via
///   the idempotent `register_job_file` RPC, which also appends exactly one
///   `before_photo_captured` event. Retries can therefore never duplicate a
///   photo, an object or an event, and the capture timestamp is preserved.
/// * Completed/cancelled jobs show their existing before photos read-only;
///   `assigned` jobs show no photo capture at all. The server enforces all
///   of this regardless of the UI.
class JobDetailsPage extends StatelessWidget {
  const JobDetailsPage({super.key, required this.jobId});

  /// The `:id` path parameter of the `/jobs/:id` route.
  final String jobId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<JobsCubit>(
      create: (_) => sl<JobsCubit>()..loadJobById(jobId),
      child: _JobDetailsView(jobId: jobId),
    );
  }
}

class _JobDetailsView extends StatelessWidget {
  const _JobDetailsView({required this.jobId});

  final String jobId;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final JobLabelMapper mapper = JobLabelMapper(l10n);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.jobDetailsTitle)),
      body: BlocListener<JobsCubit, JobsState>(
        // (Re)subscribe the before-photos watch whenever this job becomes
        // the loaded one. The cubit guards against duplicate subscriptions.
        listenWhen: (JobsState previous, JobsState current) =>
            current.selectedJob?.id == jobId &&
            previous.selectedJob?.id != jobId,
        listener: (BuildContext context, JobsState state) =>
            context.read<JobsCubit>().watchBeforePhotos(jobId),
        child: BlocBuilder<JobsCubit, JobsState>(
        builder: (BuildContext context, JobsState state) {
          final JobsCubit cubit = context.read<JobsCubit>();

          // Role comes exclusively from the authenticated session. The
          // business workflow: the admin CREATES, ASSIGNS and MONITORS jobs;
          // ONLY the assigned technician EXECUTES them (Start Job, Before
          // Photos, …). Admins therefore never see the technician actions —
          // they see the same job data as monitoring information. The server
          // (`start_job` / `register_job_file` RPCs) enforces this even if
          // the UI were bypassed.
          final bool isTechnician = context
                  .read<AuthenticationCubit?>()
                  ?.state
                  .user
                  ?.isTechnician ??
              false;

          switch (state.status) {
            case JobsStatus.initial:
            case JobsStatus.loading:
              return const JobsLoadingView();

            case JobsStatus.failure:
              return JobsErrorState(
                onRetry: () => cubit.loadJobById(jobId),
              );

            case JobsStatus.success:
              final Job? job = state.selectedJob;
              if (job == null) {
                return const JobsEmptyState();
              }

              return ListView(
                padding: AppSpacing.pagePadding,
                children: <Widget>[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Row(
                        children: <Widget>[
                          Text(
                            '#${job.jobNumber}',
                            style: context.textStyles.titleLarge,
                          ),
                          const Spacer(),
                          JobStatusBadge(
                            label: mapper.statusLabel(job.status),
                            status: job.status,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  // Workflow action area (technicians only): the Start Job
                  // button while `assigned`; once started it is replaced by
                  // the explicit "Started: <timestamp>" line (server-generated
                  // time, shown as soon as the authoritative row is back).
                  // The button is gone for good — no second start is ever
                  // possible. Admins never get the button: they monitor the
                  // job, the `start_job` RPC refuses them server-side.
                  if (isTechnician)
                    JobStartButton(
                      job: job,
                      isStarting: state.startingJobIds.contains(job.id),
                      onPressed: () => _onStartJob(context, cubit, job.id),
                    ),
                  if (job.status.value == JobStatus.inProgress &&
                      job.startedAt != null)
                    _StartedAtLine(startedAt: job.startedAt!),
                  if (job.status.value == JobStatus.assigned ||
                      (job.status.value == JobStatus.inProgress &&
                          job.startedAt != null))
                    const SizedBox(height: AppSpacing.lg),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            l10n.jobInformationTitle,
                            style: context.textStyles.titleMedium,
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          _buildJobFields(context, job, mapper),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            l10n.customerLabel,
                            style: context.textStyles.titleMedium,
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          _buildCustomerFields(context, state),
                        ],
                      ),
                    ),
                  ),
                  // Before Photos: visible once the job has been started.
                  // Capture is offered only while `in_progress`; afterwards
                  // the captured photos stay visible read-only. `assigned`
                  // jobs get no photo surface at all.
                  if (job.status.value != JobStatus.assigned) ...<Widget>[
                    const SizedBox(height: AppSpacing.lg),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: BeforePhotosSection(
                          photos: state.beforePhotos,
                          failedIds: state.beforePhotoFailedIds,
                          // Capture is a technician execution action; admins
                          // view the photos read-only (monitoring).
                          canAdd: isTechnician &&
                              job.status.value == JobStatus.inProgress,
                          isAdding: state.isAddingBeforePhoto,
                          onAdd: () => _onAddBeforePhoto(
                            context,
                            cubit,
                            job.id,
                          ),
                          onRetry: cubit.retryFailedBeforePhotos,
                          loadBytes: cubit.readPhotoBytes,
                        ),
                      ),
                    ),
                  ],
                ],
              );
          }
        },
      ),
      ),
    );
  }

  /// Submits the Start Job action and reports the outcome once.
  ///
  /// `l10n` and the messenger are captured before the await so the async gap
  /// never touches a stale [BuildContext].
  Future<void> _onStartJob(
    BuildContext context,
    JobsCubit cubit,
    String jobId,
  ) async {
    final AppLocalizations l10n = context.l10n;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    final StartJobOutcome outcome = await cubit.startJob(jobId);

    final String? message = switch (outcome) {
      StartJobOutcome.started => l10n.jobStartedMessage,
      StartJobOutcome.alreadyStarted => l10n.jobAlreadyStartedMessage,
      StartJobOutcome.failed => l10n.startJobFailedMessage,
      // A repeated tap while already submitting stays silent.
      StartJobOutcome.inFlight => null,
    };

    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// Captures a before photo: camera-first source sheet → pick → register.
  ///
  /// The picked bytes are copied into app-owned storage by the repository
  /// immediately; registration is offline-safe and the upload is queued in
  /// the durable sync queue. Raw platform errors are mapped to localized
  /// messages; nothing from the plugin reaches the user unfiltered.
  ///
  /// `l10n`/messenger/picker are captured before awaits so async gaps never
  /// touch a stale [BuildContext].
  Future<void> _onAddBeforePhoto(
    BuildContext context,
    JobsCubit cubit,
    String jobId,
  ) async {
    final AppLocalizations l10n = context.l10n;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final PhotoPicker picker = sl<PhotoPicker>();

    final PhotoPickSource? source = await _showPhotoSourceSheet(context);
    if (source == null) {
      return; // The sheet was dismissed — nothing to do.
    }

    PickedPhoto? picked;
    try {
      picked = await picker.pick(source: source);
    } on PhotoPickException catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(_pickErrorMessage(l10n, error.failure))),
      );
      return;
    }

    if (picked == null) {
      return; // The user cancelled the camera/gallery — not an error.
    }

    final AddBeforePhotoOutcome outcome = await cubit.addBeforePhoto(
      jobId: jobId,
      pickedFilePath: picked.path,
    );

    if (outcome == AddBeforePhotoOutcome.failed) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.addBeforePhotoFailedError)),
      );
    }
  }

  /// Camera-first source sheet: **Take Photo** first, gallery second.
  Future<PhotoPickSource?> _showPhotoSourceSheet(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return showModalBottomSheet<PhotoPickSource>(
      context: context,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                key: const Key('take_photo_option'),
                leading: const Icon(Icons.photo_camera_rounded),
                title: Text(l10n.takePhotoButton),
                onTap: () =>
                    Navigator.of(sheetContext).pop(PhotoPickSource.camera),
              ),
              ListTile(
                key: const Key('choose_from_gallery_option'),
                leading: const Icon(Icons.photo_library_rounded),
                title: Text(l10n.chooseFromGalleryButton),
                onTap: () =>
                    Navigator.of(sheetContext).pop(PhotoPickSource.gallery),
              ),
            ],
          ),
        );
      },
    );
  }

  String _pickErrorMessage(AppLocalizations l10n, PhotoPickFailure failure) {
    return switch (failure) {
      PhotoPickFailure.cameraUnavailable => l10n.cameraUnavailableError,
      PhotoPickFailure.accessDenied => l10n.photoAccessDeniedError,
      PhotoPickFailure.invalidImage => l10n.invalidImageError,
      PhotoPickFailure.unknown => l10n.addBeforePhotoFailedError,
    };
  }

  /// Builds the ordered, role-independent job fields. Fields whose value is
  /// not yet available (null in the database) are simply omitted.
  Widget _buildJobFields(
    BuildContext context,
    Job job,
    JobLabelMapper mapper,
  ) {
    final AppLocalizations l10n = context.l10n;

    final List<Widget> fields = <Widget>[];

    void add(String label, String? value) {
      if (value == null || value.isEmpty) {
        return;
      }
      if (fields.isNotEmpty) {
        fields.add(const SizedBox(height: AppSpacing.lg));
      }
      fields.add(JobDetailField(label: label, value: value));
    }

    add(l10n.jobNumberLabel, '#${job.jobNumber}');
    add(l10n.jobTypeLabel, mapper.jobTypeLabel(job.jobType));
    add(l10n.statusLabel, mapper.statusLabel(job.status));
    add(l10n.descriptionLabel, job.description);
    add(l10n.assignedTechnicianLabel, job.assignedEmployeeName);
    add(l10n.assignedDateLabel, job.assignedAt == null ? null : formatJobDate(job.assignedAt!, context));
    add(l10n.startDateLabel, job.startedAt == null ? null : formatJobDate(job.startedAt!, context));
    add(l10n.completedDateLabel, job.completedAt == null ? null : formatJobDate(job.completedAt!, context));
    add(l10n.createdAtLabel, formatJobDate(job.createdAt, context));
    add(l10n.expiresAtLabel, formatJobDate(job.expiresAt, context));

    if (fields.isEmpty) {
      return const JobsEmptyState();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: fields,
    );
  }

  /// Builds the customer section from the per-job [JobsState.selectedJobCustomer].
  ///
  /// This is the ONLY customer surface a technician ever sees: read-only
  /// display fields for the single job being opened. There are deliberately
  /// no create/edit/delete/search actions and no list — those live in the
  /// admin-only Customers feature. When the RPC returned nothing (another
  /// technician's job, inactive employee, missing customer) the section
  /// shows a short note instead of data.
  Widget _buildCustomerFields(BuildContext context, JobsState state) {
    final AppLocalizations l10n = context.l10n;
    final JobCustomerInfo? customer = state.selectedJobCustomer;

    if (customer == null) {
      return Text(
        l10n.customerInfoUnavailable,
        style: context.textStyles.bodyMedium,
      );
    }

    final List<Widget> fields = <Widget>[];

    void add(String label, String? value) {
      if (value == null || value.isEmpty) {
        return;
      }
      if (fields.isNotEmpty) {
        fields.add(const SizedBox(height: AppSpacing.lg));
      }
      fields.add(JobDetailField(label: label, value: value));
    }

    add(l10n.customerNameLabel, customer.name);
    add(l10n.customerPhoneLabel, customer.phone);
    add(l10n.customerAddressLabel, customer.address);
    add(l10n.customerCityLabel, customer.city);
    add(l10n.customerPostalCodeLabel, customer.postalCode);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: fields,
    );
  }
}

/// The workflow-state line shown in place of the Start Job button once the
/// job is `in_progress`: "Started: `<server timestamp>`". Purely presentational
/// — the value comes from `jobs.started_at` (database-generated), formatted
/// with the project's existing date convention.
class _StartedAtLine extends StatelessWidget {
  const _StartedAtLine({required this.startedAt});

  final DateTime startedAt;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return Row(
      children: <Widget>[
        const Icon(
          Icons.access_time_rounded,
          size: AppDimensions.iconMd,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            l10n.jobStartedAt(formatJobDate(startedAt, context)),
            style: context.textStyles.bodyMedium,
          ),
        ),
      ],
    );
  }
}
