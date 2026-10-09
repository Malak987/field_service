import 'dart:typed_data';

import 'package:field_service/app/di/injection.dart';
import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_colors.dart';
import 'package:field_service/core/theme/app_radius.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/features/authentication/presentation/cubit/authentication_cubit.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_customer_info.dart';
import 'package:field_service/features/jobs/domain/entities/job_file.dart';
import 'package:field_service/features/jobs/domain/entities/job_status.dart';
import 'package:field_service/features/jobs/presentation/cubit/jobs_cubit.dart';
import 'package:field_service/features/jobs/presentation/cubit/jobs_state.dart';
import 'package:field_service/features/jobs/presentation/utils/job_label_mapper.dart';
import 'package:field_service/features/jobs/presentation/utils/jobs_date_format.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/features/jobs/presentation/services/photo_picker.dart';
import 'package:field_service/features/jobs/presentation/widgets/after_photos_section.dart';
import 'package:field_service/features/jobs/presentation/widgets/before_photos_section.dart';
import 'package:field_service/features/jobs/presentation/widgets/complete_job_section.dart';
import 'package:field_service/features/jobs/presentation/widgets/job_detail_field.dart';
import 'package:field_service/features/jobs/presentation/widgets/signature_section.dart';
import 'package:field_service/features/jobs/presentation/widgets/job_start_button.dart';
import 'package:field_service/features/jobs/presentation/widgets/job_status_badge.dart';
import 'package:field_service/features/jobs/presentation/widgets/work_description_section.dart';
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

class _JobDetailsView extends StatefulWidget {
  const _JobDetailsView({required this.jobId});

  final String jobId;

  @override
  State<_JobDetailsView> createState() => _JobDetailsViewState();
}

class _JobDetailsViewState extends State<_JobDetailsView> {
  /// True while a finger is touching the signature pad. The page's own
  /// scrolling is frozen for exactly that window (see [SignaturePad]), so
  /// every movement inside the pad becomes ink — never page scrolling.
  bool _signatureDrawing = false;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final JobLabelMapper mapper = JobLabelMapper(l10n);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.jobDetailsTitle)),
      body: BlocListener<JobsCubit, JobsState>(
        // (Re)subscribe the before/after-photos watches whenever this job
        // becomes the loaded one. The cubit guards against duplicate
        // subscriptions.
        listenWhen: (JobsState previous, JobsState current) =>
            current.selectedJob?.id == widget.jobId &&
            previous.selectedJob?.id != widget.jobId,
        listener: (BuildContext context, JobsState state) {
          context.read<JobsCubit>().watchBeforePhotos(widget.jobId);
          context.read<JobsCubit>().watchAfterPhotos(widget.jobId);
          context.read<JobsCubit>().watchSignature(widget.jobId);
        },
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
            final bool isTechnician =
                context
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
                  onRetry: () => cubit.loadJobById(widget.jobId),
                );

              case JobsStatus.success:
                final Job? job = state.selectedJob;
                if (job == null) {
                  return const JobsEmptyState();
                }

                // Workflow step facts — purely presentational derivation
                // from the existing JobsState; every rule itself stays
                // enforced by the cubit/repository/server.
                final bool isCompleted =
                    job.status.value == JobStatus.completed;
                final bool stepStarted = job.status.value != JobStatus.assigned;
                final bool hasBeforePhoto = state.beforePhotos.isNotEmpty;
                final bool hasWorkDescription = (job.workDescription ?? '')
                    .trim()
                    .isNotEmpty;
                final bool hasAfterPhoto = state.afterPhotos.isNotEmpty;
                final bool hasSignature = state.signatureFiles.isNotEmpty;

                return ListView(
                  // Frozen while a finger draws on the signature pad: every
                  // touch INSIDE the pad becomes ink, never page movement;
                  // the moment the finger lifts, normal scrolling returns
                  // (wired through SignatureSection -> SignaturePad).
                  physics: _signatureDrawing
                      ? const NeverScrollableScrollPhysics()
                      : null,
                  padding: AppSpacing.pagePadding,
                  children: <Widget>[
                    _buildHeaderCard(context, job, mapper, state),
                    // Workflow action area (technicians only): the Start Job
                    // button while `assigned`; once started it is replaced by
                    // the explicit "Started: <timestamp>" line (server-generated
                    // time, shown as soon as the authoritative row is back).
                    // The button is gone for good — no second start is ever
                    // possible. Admins never get the button: they monitor the
                    // job, the `start_job` RPC refuses them server-side.
                    if ((isTechnician &&
                            job.status.value == JobStatus.assigned) ||
                        (job.status.value == JobStatus.inProgress &&
                            job.startedAt != null)) ...<Widget>[
                      const SizedBox(height: AppSpacing.lg),
                      _workflowCard(
                        step: 1,
                        done: stepStarted,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            if (isTechnician)
                              JobStartButton(
                                job: job,
                                isStarting: state.startingJobIds.contains(
                                  job.id,
                                ),
                                onPressed: () =>
                                    _onStartJob(context, cubit, job.id),
                              ),
                            if (job.status.value == JobStatus.inProgress &&
                                job.startedAt != null)
                              _StartedAtLine(startedAt: job.startedAt!),
                          ],
                        ),
                      ),
                    ],
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
                    // Customer Request — the admin's job description, in
                    // its OWN card: visually separated from the technician's
                    // Work Description step below. The two never share a
                    // surface.
                    if ((job.description ?? '').trim().isNotEmpty) ...<Widget>[
                      const SizedBox(height: AppSpacing.lg),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                l10n.customerRequestLabel,
                                style: context.textStyles.titleMedium,
                              ),
                              const SizedBox(height: AppSpacing.md),
                              Text(
                                job.description!,
                                style: context.textStyles.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
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
                      _workflowCard(
                        step: 2,
                        done: hasBeforePhoto,
                        child: BeforePhotosSection(
                          photos: state.beforePhotos,
                          failedIds: state.beforePhotoFailedIds,
                          // Capture is a technician execution action; admins
                          // view the photos read-only (monitoring).
                          canAdd:
                              isTechnician &&
                              job.status.value == JobStatus.inProgress,
                          isAdding: state.isAddingBeforePhoto,
                          onAdd: () =>
                              _onAddBeforePhoto(context, cubit, job.id),
                          onRetry: cubit.retryFailedBeforePhotos,
                          loadBytes: cubit.readPhotoBytes,
                        ),
                      ),
                      // Work Description: the technician's record of the work
                      // actually performed — separate from the admin's
                      // customer request (Job Information card above).
                      // Editable ONLY by the assigned technician while the job
                      // is `in_progress`; admins and closed jobs get the
                      // read-only view (the server enforces the same rule).
                      const SizedBox(height: AppSpacing.lg),
                      _workflowCard(
                        step: 3,
                        done: hasWorkDescription,
                        child: WorkDescriptionSection(
                          initialText: job.workDescription ?? '',
                          canEdit:
                              isTechnician &&
                              job.status.value == JobStatus.inProgress,
                          isSaving: state.isSavingWorkDescription,
                          error: state.workDescriptionError,
                          onSave: (String text) => _onSaveWorkDescription(
                            context,
                            cubit,
                            job.id,
                            text,
                          ),
                        ),
                      ),
                      // After Photos: the finished-site record. Visible once
                      // the job has been started; capture is offered only
                      // while `in_progress` (assigned technician). Admins and
                      // closed jobs view the captured photos read-only; the
                      // server refuses any write outside that window.
                      const SizedBox(height: AppSpacing.lg),
                      _workflowCard(
                        step: 4,
                        done: hasAfterPhoto,
                        child: AfterPhotosSection(
                          photos: state.afterPhotos,
                          failedIds: state.afterPhotoFailedIds,
                          // Capture is a technician execution action; admins
                          // view the photos read-only (monitoring).
                          canAdd:
                              isTechnician &&
                              job.status.value == JobStatus.inProgress,
                          isAdding: state.isAddingAfterPhoto,
                          onAdd: () => _onAddAfterPhoto(context, cubit, job.id),
                          onRetry: cubit.retryFailedAfterPhotos,
                          loadBytes: cubit.readPhotoBytes,
                        ),
                      ),
                      // Customer Signature: captured ONLY by the assigned
                      // technician while `in_progress` (the server enforces
                      // the same rule); everyone else — admins monitoring,
                      // closed jobs — sees the captured signature (or the
                      // "nothing yet" note) read-only.
                      const SizedBox(height: AppSpacing.lg),
                      _workflowCard(
                        step: 5,
                        done: hasSignature,
                        child: SignatureSection(
                          signature: state.signatureFiles.isEmpty
                              ? null
                              : state.signatureFiles.last,
                          failedIds: state.signatureFailedIds,
                          canCapture:
                              isTechnician &&
                              job.status.value == JobStatus.inProgress,
                          isCapturing: state.isCapturingSignature,
                          error: state.signatureError,
                          onCapture: (Uint8List pngBytes) =>
                              _onCaptureSignature(
                                context,
                                cubit,
                                job.id,
                                pngBytes,
                              ),
                          onRetry: cubit.retryFailedSignature,
                          loadBytes: cubit.readPhotoBytes,
                          // Freeze the page scroll while the customer
                          // draws; normal scrolling resumes on lift.
                          onDrawingChanged: (bool drawing) {
                            if (drawing == _signatureDrawing) {
                              return;
                            }
                            setState(() => _signatureDrawing = drawing);
                          },
                        ),
                      ),
                      // Complete Job — the FINAL workflow step: shown only
                      // to the assigned technician while `in_progress` (the
                      // `complete_job` RPC enforces exactly the same rules).
                      // The checklist reflects what the CLIENT knows; the
                      // server re-validates everything itself and may still
                      // refuse (e.g. a capture still awaiting sync). On
                      // success the authoritative row flips this screen to
                      // the completed read-only state.
                      if (isTechnician &&
                          job.status.value == JobStatus.inProgress) ...<Widget>[
                        const SizedBox(height: AppSpacing.lg),
                        _workflowCard(
                          step: 6,
                          done: isCompleted,
                          // Sync-readiness gate: a local file alone does
                          // not satisfy the server — every required file
                          // must be `synced` (registered server-side)
                          // before completion is offered. Both facts come
                          // from the EXISTING sync plumbing: the files'
                          // `syncState` plus the failed-ids set.
                          child: CompleteJobSection(
                            hasBeforePhoto: state.beforePhotos.isNotEmpty,
                            hasWorkDescription: (job.workDescription ?? '')
                                .trim()
                                .isNotEmpty,
                            hasAfterPhoto: state.afterPhotos.isNotEmpty,
                            hasSignature: state.signatureFiles.isNotEmpty,
                            hasPendingUploads: _requiredFilePending(state),
                            hasFailedUploads: _requiredFileFailed(state),
                            isCompleting: state.isCompletingJob,
                            onComplete: () =>
                                _onCompleteJob(context, cubit, job.id),
                            // All three retry actions share the single
                            // `retryFailedSyncs` mechanism — any one of
                            // them retries every failed upload.
                            onRetry: cubit.retryFailedBeforePhotos,
                          ),
                        ),
                      ],
                    ],
                  ],
                );
            }
          },
        ),
      ),
    );
  }

  /// The header card: job number, category and customer name on the left,
  /// the status badge on the right — the at-a-glance identity of the job.
  /// A completed job additionally carries a calm success banner with the
  /// server-authoritative completion time.
  Widget _buildHeaderCard(
    BuildContext context,
    Job job,
    JobLabelMapper mapper,
    JobsState state,
  ) {
    final AppLocalizations l10n = context.l10n;
    final String? customerName = state.selectedJobCustomer?.name;
    final bool isCompleted = job.status.value == JobStatus.completed;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '#${job.jobNumber}',
                        style: context.textStyles.titleLarge,
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        mapper.jobTypeLabel(job.jobType),
                        style: context.textStyles.bodyMedium?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                      if (customerName != null &&
                          customerName.isNotEmpty) ...<Widget>[
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          children: <Widget>[
                            Icon(
                              Icons.person_outline_rounded,
                              size: AppDimensions.iconSm,
                              color: context.colors.onSurfaceVariant,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Expanded(
                              child: Text(
                                customerName,
                                style: context.textStyles.titleSmall,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                JobStatusBadge(
                  label: mapper.statusLabel(job.status),
                  status: job.status,
                ),
              ],
            ),
            if (isCompleted && job.completedAt != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: AppColors.successSurface,
                  borderRadius: AppRadius.control,
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(
                      Icons.check_circle_rounded,
                      size: AppDimensions.iconMd,
                      color: AppColors.success,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        l10n.jobCompletedAt(
                          formatJobDate(job.completedAt!, context),
                        ),
                        style: context.textStyles.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// One numbered workflow step card: step indicator on top, then the
  /// section's own content (title / status / content / action all stay
  /// where they already were inside the section widget).
  Widget _workflowCard({
    required int step,
    required bool done,
    required Widget child,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _stepHeader(step: step, done: done),
            const SizedBox(height: AppSpacing.md),
            child,
          ],
        ),
      ),
    );
  }

  /// The small "Step N" indicator: a filled check circle for a finished
  /// step, an outlined number for an open one.
  Widget _stepHeader({required int step, required bool done}) {
    final AppLocalizations l10n = context.l10n;

    return Row(
      children: <Widget>[
        Container(
          width: AppDimensions.iconLg,
          height: AppDimensions.iconLg,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done
                ? AppColors.success
                : context.colors.surfaceContainerHighest,
          ),
          alignment: Alignment.center,
          child: done
              ? Icon(
                  Icons.check_rounded,
                  size: AppDimensions.iconSm,
                  // Crisp glyph on the filled success circle in both modes.
                  color: AppColors.surface,
                )
              : Text(
                  '$step',
                  style: context.textStyles.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          l10n.stepLabel(step),
          style: context.textStyles.labelSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: context.colors.onSurfaceVariant,
          ),
        ),
      ],
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

  /// Submits the Work Description save and reports the outcome.
  ///
  /// Empty/too-long text surfaces as an inline field error (published by
  /// the cubit); success/failure get a snackbar. `l10n` and the messenger
  /// are captured before the await so the async gap never touches a stale
  /// [BuildContext].
  Future<void> _onSaveWorkDescription(
    BuildContext context,
    JobsCubit cubit,
    String jobId,
    String text,
  ) async {
    final AppLocalizations l10n = context.l10n;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    final SaveWorkDescriptionOutcome outcome = await cubit.saveWorkDescription(
      jobId,
      text,
    );

    final String? message = switch (outcome) {
      SaveWorkDescriptionOutcome.saved => l10n.workDescriptionSavedMessage,
      SaveWorkDescriptionOutcome.failed =>
        l10n.workDescriptionSaveFailedMessage,
      // Validation is inline (state.workDescriptionError); a repeated tap
      // while already submitting stays silent.
      SaveWorkDescriptionOutcome.invalid => null,
      SaveWorkDescriptionOutcome.inFlight => null,
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

  /// Captures an after photo: same camera-first flow as
  /// [_onAddBeforePhoto] — only the registration target differs
  /// (`file_type = 'after'`, server event `after_photo_captured`).
  Future<void> _onAddAfterPhoto(
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

    final AddAfterPhotoOutcome outcome = await cubit.addAfterPhoto(
      jobId: jobId,
      pickedFilePath: picked.path,
    );

    if (outcome == AddAfterPhotoOutcome.failed) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.addAfterPhotoFailedError)),
      );
    }
  }

  /// Persists the drawn customer signature and reports the outcome.
  ///
  /// An empty drawing surfaces as the inline pad error (published by the
  /// cubit); success/failure get a snackbar. `l10n` and the messenger are
  /// captured before the await so the async gap never touches a stale
  /// [BuildContext].
  Future<void> _onCaptureSignature(
    BuildContext context,
    JobsCubit cubit,
    String jobId,
    Uint8List pngBytes,
  ) async {
    final AppLocalizations l10n = context.l10n;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    final CaptureSignatureOutcome outcome = await cubit
        .captureCustomerSignature(jobId: jobId, signatureImage: pngBytes);

    final String? message = switch (outcome) {
      CaptureSignatureOutcome.captured => l10n.signatureSavedMessage,
      CaptureSignatureOutcome.failed => l10n.signatureSaveFailedMessage,
      // Validation is inline (state.signatureError); a repeated tap while
      // already persisting stays silent.
      CaptureSignatureOutcome.invalid => null,
      CaptureSignatureOutcome.inFlight => null,
    };

    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// Submits the FINAL workflow step and reports the outcome once.
  ///
  /// The server is the authority: it re-validates every completion
  /// condition and the cubit publishes the typed refusal in
  /// [JobsState.completionError] — mapped here to a localized explanation.
  /// `l10n` and the messenger are captured before the await so the async
  /// gap never touches a stale [BuildContext].
  Future<void> _onCompleteJob(
    BuildContext context,
    JobsCubit cubit,
    String jobId,
  ) async {
    final AppLocalizations l10n = context.l10n;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    final CompleteJobOutcome outcome = await cubit.completeJob(jobId);

    final String? message = switch (outcome) {
      CompleteJobOutcome.completed => l10n.jobCompletedMessage,
      CompleteJobOutcome.offline => l10n.internetRequiredToCompleteJob,
      CompleteJobOutcome.rejected => _completionErrorMessage(
        l10n,
        cubit.state.completionError,
      ),
      CompleteJobOutcome.failed => l10n.unableToCompleteJobError,
      // A repeated tap while already submitting stays silent.
      CompleteJobOutcome.inFlight => null,
    };

    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// A required file (before/after photo, signature) exists locally but
  /// its upload has NOT been confirmed yet (`syncState` still `pending`,
  /// which covers queued and in-flight queue operations) and its id is not
  /// in the failed set — completion must wait for the shared sync engine.
  static bool _requiredFilePending(JobsState state) {
    return <JobFile>[
      ...state.beforePhotos,
      ...state.afterPhotos,
      ...state.signatureFiles,
    ].any(
      (JobFile file) =>
          file.syncState != JobFileSyncState.synced &&
          !state.beforePhotoFailedIds.contains(file.id),
    );
  }

  /// A required file's upload sits in the queue's `failed` state (existing
  /// failed-ids plumbing): completion stays disabled until the shared Retry
  /// succeeds.
  static bool _requiredFileFailed(JobsState state) {
    return <JobFile>[
      ...state.beforePhotos,
      ...state.afterPhotos,
      ...state.signatureFiles,
    ].any(
      (JobFile file) =>
          file.syncState != JobFileSyncState.synced &&
          state.beforePhotoFailedIds.contains(file.id),
    );
  }

  /// Localized explanation of a server-side completion refusal.
  String _completionErrorMessage(
    AppLocalizations l10n,
    JobCompletionError? error,
  ) {
    return switch (error) {
      // The server lacks a file this device still has in flight (or
      // failed): explain the sync situation instead of a bare "missing".
      JobCompletionError.stillSyncing => l10n.waitingForFileSync,
      JobCompletionError.missingBeforePhoto => l10n.missingBeforePhotoError,
      JobCompletionError.missingWorkDescription =>
        l10n.missingWorkDescriptionError,
      JobCompletionError.missingAfterPhoto => l10n.missingAfterPhotoError,
      JobCompletionError.missingSignature => l10n.missingSignatureError,
      // Ownership/status/role refusals and unknowns share the safe,
      // non-specific message — the details stay in the logs.
      JobCompletionError.notAssigned ||
      JobCompletionError.invalidStatus ||
      JobCompletionError.unauthorized ||
      JobCompletionError.unknown ||
      null => l10n.unableToCompleteJobError,
      // Covered above before the call, kept defensive.
      JobCompletionError.offline => l10n.internetRequiredToCompleteJob,
    };
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
  Widget _buildJobFields(BuildContext context, Job job, JobLabelMapper mapper) {
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
    add(l10n.assignedTechnicianLabel, job.assignedEmployeeName);
    add(
      l10n.assignedDateLabel,
      job.assignedAt == null ? null : formatJobDate(job.assignedAt!, context),
    );
    add(
      l10n.startDateLabel,
      job.startedAt == null ? null : formatJobDate(job.startedAt!, context),
    );
    add(
      l10n.completedDateLabel,
      job.completedAt == null ? null : formatJobDate(job.completedAt!, context),
    );
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
        const Icon(Icons.access_time_rounded, size: AppDimensions.iconMd),
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
