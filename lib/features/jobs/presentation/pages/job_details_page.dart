import 'dart:typed_data';

import 'package:field_service/app/di/injection.dart';
import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/features/authentication/presentation/cubit/authentication_cubit.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_file.dart';
import 'package:field_service/features/jobs/domain/entities/job_status.dart';
import 'package:field_service/features/jobs/presentation/cubit/jobs_cubit.dart';
import 'package:field_service/features/jobs/presentation/cubit/jobs_state.dart';
import 'package:field_service/features/jobs/presentation/utils/job_label_mapper.dart';
import 'package:field_service/features/jobs/presentation/utils/jobs_date_format.dart';
import 'package:field_service/features/jobs/presentation/services/photo_picker.dart';
import 'package:field_service/features/jobs/presentation/widgets/after_photos_section.dart';
import 'package:field_service/features/jobs/presentation/widgets/before_photos_section.dart';
import 'package:field_service/features/jobs/presentation/widgets/complete_job_section.dart';
import 'package:field_service/features/jobs/presentation/widgets/job_activity_section.dart';
import 'package:field_service/features/jobs/presentation/widgets/job_details_fields.dart';
import 'package:field_service/features/jobs/presentation/widgets/job_details_header.dart';
import 'package:field_service/features/jobs/presentation/widgets/job_section_heading.dart';
import 'package:field_service/features/jobs/presentation/widgets/job_status_badge.dart';
import 'package:field_service/features/jobs/presentation/widgets/job_workflow_step.dart';
import 'package:field_service/features/jobs/presentation/widgets/workflow_progress.dart';
import 'package:field_service/features/jobs/presentation/widgets/signature_section.dart';
import 'package:field_service/features/jobs/presentation/widgets/job_start_button.dart';
import 'package:field_service/features/jobs/presentation/widgets/work_description_section.dart';
import 'package:field_service/features/jobs/presentation/widgets/jobs_empty_state.dart';
import 'package:field_service/features/jobs/presentation/widgets/jobs_error_state.dart';
import 'package:field_service/features/jobs/presentation/widgets/jobs_loading_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Job details (route `/jobs/:id`) — the field-work hub.
///
/// Presents the data that exists in `public.jobs`, the customer information
/// belonging to THIS job, and — once the job is `in_progress` — its Before
/// Photos.
///
/// Layout: the job's identity and its workflow progress first, then the
/// non-step information (job record, customer, customer request), then the
/// numbered execution steps in their fixed order (2 before photos,
/// 3 work description, 4 after photos, 5 signature, 6 review and complete),
/// and finally the activity log. The status pill lives in the app bar so the
/// current status stays visible at every scroll position, and the page carries
/// no second title: the header block below IS the title.
///
/// Rebuild model: the shell (this file's `build`) only decides WHICH sections
/// exist — it listens to the load state and the job's status. Every section
/// then subscribes to its own slice of [JobsState] via `buildWhen`, so a
/// capture, a description save or an upload-state change rebuilds exactly one
/// section. Captured bytes stay cached in `BeforePhotoTile`, which reloads only
/// when the file itself changes — never on a rebuild.
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
    return Scaffold(
      // No page title: this page's identity is the job number in the header
      // below, and a second heading would only repeat it. The back button
      // stays, and the status pill lives in the bar so it remains readable
      // while the technician scrolls the workflow.
      appBar: const _JobDetailsAppBar(),
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
          // The shell decides WHICH sections exist — the load state and the
          // job's status, nothing else. Each section below listens to its own
          // slice of the state, so adding a photo, saving a description or an
          // upload-state change rebuilds that one section instead of the whole
          // page.
          buildWhen: (JobsState previous, JobsState current) =>
              previous.status != current.status ||
              previous.selectedJob?.id != current.selectedJob?.id ||
              previous.selectedJob?.status.value !=
                  current.selectedJob?.status.value,
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

                final bool isAssigned = job.status.value == JobStatus.assigned;
                final bool isActive =
                    job.status.value == JobStatus.inProgress ||
                    job.status.value == JobStatus.started;
                final bool isCompleted =
                    job.status.value == JobStatus.completed;

                // Every section carries its own top margin inside its body, so
                // a section that renders nothing leaves no gap behind it.
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
                    const _JobSummary(),
                    // Step 1: only the technician receives the Start Job
                    // action. Other roles see a read-only state; after start,
                    // the authoritative server timestamp replaces the button.
                    if (isAssigned ||
                        (isActive && job.startedAt != null) ||
                        isCompleted)
                      _StartStep(
                        isTechnician: isTechnician,
                        onStart: () => _onStartJob(context, cubit, job.id),
                      ),
                    const _JobInformationCard(),
                    const _CustomerCard(),
                    const _CustomerRequestCard(),
                    // Execution steps: visible once the job has been started.
                    // Capture is offered only while `in_progress`; afterwards
                    // the captured evidence stays visible read-only, and an
                    // `assigned` job shows no execution section at all rather
                    // than an empty one.
                    if (job.status.value != JobStatus.assigned) ...<Widget>[
                      _BeforePhotosStep(
                        isTechnician: isTechnician,
                        onAdd: () =>
                            _onAddBeforePhoto(context, cubit, job.id),
                        onRetry: cubit.retryFailedBeforePhotos,
                        loadBytes: cubit.readPhotoBytes,
                      ),
                      _WorkDescriptionStep(
                        isTechnician: isTechnician,
                        onSave: (String text) => _onSaveWorkDescription(
                          context,
                          cubit,
                          job.id,
                          text,
                        ),
                      ),
                      _AfterPhotosStep(
                        isTechnician: isTechnician,
                        onAdd: () => _onAddAfterPhoto(context, cubit, job.id),
                        onRetry: cubit.retryFailedAfterPhotos,
                        loadBytes: cubit.readPhotoBytes,
                      ),
                      _SignatureStep(
                        isTechnician: isTechnician,
                        onCapture: (Uint8List pngBytes) => _onCaptureSignature(
                          context,
                          cubit,
                          job.id,
                          pngBytes,
                        ),
                        onRetry: cubit.retryFailedSignature,
                        loadBytes: cubit.readPhotoBytes,
                        onDrawingChanged: _onSignatureDrawingChanged,
                      ),
                      // Closed jobs retain a read-only Step 6 marker so the
                      // completed workflow remains a visible six-stage path.
                      if (isCompleted) const _CompletionMarkerStep(),
                      // Complete Job — the FINAL workflow step: shown only
                      // to the assigned technician while `in_progress` (the
                      // `complete_job` RPC enforces exactly the same rules).
                      // The checklist reflects what the CLIENT knows; the
                      // server re-validates everything itself and may still
                      // refuse (e.g. a capture still awaiting sync). On
                      // success the authoritative row flips this screen to
                      // the completed read-only state.
                      if (isTechnician &&
                          job.status.value == JobStatus.inProgress)
                        _CompletionStep(
                          onComplete: () =>
                              _onCompleteJob(context, cubit, job.id),
                          // All three retry actions share the single
                          // `retryFailedSyncs` mechanism — any one of them
                          // retries every failed upload.
                          onRetry: cubit.retryFailedBeforePhotos,
                        ),
                    ],
                    const _ActivityCard(),
                  ],
                );
            }
          },
        ),
      ),
    );
  }

  /// Freezes the page scroll for exactly the window in which a finger draws on
  /// the signature pad. Two state flips per drawing session (down, up) — never
  /// one per stroke — so the pad never rebuilds the page while it is drawn on.
  void _onSignatureDrawingChanged(bool drawing) {
    if (drawing == _signatureDrawing) {
      return;
    }
    setState(() => _signatureDrawing = drawing);
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

}

/// The status pill in the app bar — the one page-level fact that stays useful
/// while the technician scrolls the steps below.
///
/// It subscribes to the loaded job only, so the bar never rebuilds for a photo
/// upload or a description save.
class _JobDetailsAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const _JobDetailsAppBar();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<JobsCubit, JobsState>(
      // Only the status pill changes up here: the bar must never rebuild for a
      // photo upload, a description save or a capture.
      buildWhen: (JobsState previous, JobsState current) =>
          previous.selectedJob?.id != current.selectedJob?.id ||
          previous.selectedJob?.status.value !=
              current.selectedJob?.status.value,
      builder: (BuildContext context, JobsState state) {
        final Job? job = state.selectedJob;

        return AppBar(
          actions: <Widget>[
            if (job != null) ...<Widget>[
              JobStatusBadge(
                label: JobLabelMapper(context.l10n).statusLabel(job.status),
                status: job.status,
              ),
              const SizedBox(width: AppSpacing.lg),
            ],
          ],
        );
      },
    );
  }
}

/// Header plus workflow progress: the two blocks that read the job identity and
/// the four evidence facts, and that must therefore change together.
///
/// They share one builder on purpose — two builders reading the same facts
/// would only double the subscriptions without isolating anything.
class _JobSummary extends StatelessWidget {
  const _JobSummary();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return BlocBuilder<JobsCubit, JobsState>(
      buildWhen: (JobsState previous, JobsState current) =>
          previous.selectedJob != current.selectedJob ||
          previous.selectedJobCustomer != current.selectedJobCustomer ||
          previous.beforePhotos.isNotEmpty !=
              current.beforePhotos.isNotEmpty ||
          previous.afterPhotos.isNotEmpty != current.afterPhotos.isNotEmpty ||
          previous.signatureFiles.isNotEmpty !=
              current.signatureFiles.isNotEmpty,
      builder: (BuildContext context, JobsState state) {
        final Job? job = state.selectedJob;
        if (job == null) {
          return const SizedBox.shrink();
        }

        // Workflow progress is presentation-only and derived from the
        // job/file facts already loaded by the existing Cubit.
        final String status = job.status.value;
        final bool showProgress =
            status == JobStatus.assigned ||
            status == JobStatus.inProgress ||
            status == JobStatus.started ||
            status == JobStatus.completed;
        final int completed = _completedSteps(state);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            JobDetailsHeader(
              job: job,
              mapper: JobLabelMapper(l10n),
              state: state,
            ),
            if (showProgress) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              WorkflowProgress(
                completed: completed,
                total: 6,
                label: l10n.workflowProgressLabel(completed, 6),
                title: l10n.workflowProgressTitle,
              ),
            ],
          ],
        );
      },
    );
  }
}

/// The job's own record — rebuilt only when the job row itself changes.
class _JobInformationCard extends StatelessWidget {
  const _JobInformationCard();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<JobsCubit, JobsState>(
      buildWhen: (JobsState previous, JobsState current) =>
          previous.selectedJob != current.selectedJob,
      builder: (BuildContext context, JobsState state) {
        final Job? job = state.selectedJob;
        if (job == null) {
          return const SizedBox.shrink();
        }

        return _SectionBody(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  JobSectionHeading(
                    icon: Icons.assignment_outlined,
                    title: context.l10n.jobInformationTitle,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  JobDetailsFields(
                    job: job,
                    mapper: JobLabelMapper(context.l10n),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The customer belonging to THIS job — the only customer surface a technician
/// has. Rebuilt only when the customer payload (or its fallback name) changes.
class _CustomerCard extends StatelessWidget {
  const _CustomerCard();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<JobsCubit, JobsState>(
      buildWhen: (JobsState previous, JobsState current) =>
          previous.selectedJobCustomer != current.selectedJobCustomer ||
          previous.selectedJob?.customerName !=
              current.selectedJob?.customerName,
      builder: (BuildContext context, JobsState state) {
        return _SectionBody(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  JobSectionHeading(
                    icon: Icons.person_outline_rounded,
                    title: context.l10n.customerLabel,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  JobCustomerFields(state: state),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The admin's request, in its own card: the written job that leads into the
/// execution steps below. An absent request renders nothing at all rather than
/// an empty box, and editing a work description never rebuilds this card.
class _CustomerRequestCard extends StatelessWidget {
  const _CustomerRequestCard();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<JobsCubit, JobsState>(
      buildWhen: (JobsState previous, JobsState current) =>
          previous.selectedJob?.description != current.selectedJob?.description,
      builder: (BuildContext context, JobsState state) {
        final String? description = state.selectedJob?.description;
        if (description == null || description.trim().isEmpty) {
          return const SizedBox.shrink();
        }

        return _SectionBody(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  JobSectionHeading(
                    icon: Icons.chat_bubble_outline_rounded,
                    title: context.l10n.customerRequestLabel,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(description, style: context.textStyles.bodyMedium),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Step 1 — Start Job for the assigned technician, and the server timestamp
/// with which that step ends for everyone else.
class _StartStep extends StatelessWidget {
  const _StartStep({required this.isTechnician, required this.onStart});

  final bool isTechnician;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return BlocBuilder<JobsCubit, JobsState>(
      buildWhen: (JobsState previous, JobsState current) =>
          previous.selectedJob != current.selectedJob ||
          previous.startingJobIds != current.startingJobIds,
      builder: (BuildContext context, JobsState state) {
        final Job? job = state.selectedJob;
        if (job == null) {
          return const SizedBox.shrink();
        }

        final String status = job.status.value;
        final bool isAssigned = status == JobStatus.assigned;
        final bool isActive =
            status == JobStatus.inProgress || status == JobStatus.started;
        final bool isCompleted = status == JobStatus.completed;
        final bool stepDone = isActive || isCompleted;

        return _SectionBody(
          child: JobWorkflowStep(
            step: 1,
            done: stepDone,
            current: isAssigned,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (isTechnician)
                  JobStartButton(
                    job: job,
                    isStarting: state.startingJobIds.contains(job.id),
                    onPressed: onStart,
                  ),
                if (isAssigned && !isTechnician)
                  Text(
                    l10n.statusAssigned,
                    style: context.textStyles.bodyMedium,
                  ),
                if ((isActive || isCompleted) && job.startedAt != null)
                  StartedAtLine(startedAt: job.startedAt!)
                else if (isCompleted)
                  Text(
                    l10n.statusStarted,
                    style: context.textStyles.bodyMedium,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Step 2 — Before Photos: the site's state before the work, captured while the
/// job is `in_progress`. Rebuilt only by its own facts: the photo list, its
/// failed ids, the add-in-flight flag, the job status (capture permission) and
/// the current-step marker.
class _BeforePhotosStep extends StatelessWidget {
  const _BeforePhotosStep({
    required this.isTechnician,
    required this.onAdd,
    required this.onRetry,
    required this.loadBytes,
  });

  final bool isTechnician;
  final VoidCallback onAdd;
  final VoidCallback onRetry;
  final Future<Uint8List?> Function(JobFile file) loadBytes;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<JobsCubit, JobsState>(
      buildWhen: (JobsState previous, JobsState current) =>
          !identical(previous.beforePhotos, current.beforePhotos) ||
          previous.beforePhotoFailedIds != current.beforePhotoFailedIds ||
          previous.isAddingBeforePhoto != current.isAddingBeforePhoto ||
          previous.selectedJob?.status.value !=
              current.selectedJob?.status.value ||
          _currentStep(previous) != _currentStep(current),
      builder: (BuildContext context, JobsState state) {
        return _SectionBody(
          child: JobWorkflowStep(
            step: 2,
            done: state.beforePhotos.isNotEmpty,
            current: _currentStep(state) == 2,
            child: BeforePhotosSection(
              photos: state.beforePhotos,
              failedIds: state.beforePhotoFailedIds,
              // Capture is a technician execution action; admins view the
              // photos read-only (monitoring).
              canAdd:
                  isTechnician &&
                  state.selectedJob?.status.value == JobStatus.inProgress,
              isAdding: state.isAddingBeforePhoto,
              onAdd: onAdd,
              onRetry: onRetry,
              loadBytes: loadBytes,
            ),
          ),
        );
      },
    );
  }
}

/// Step 3 — the technician's record of the work actually performed, separate
/// from the admin's Customer Request card above.
class _WorkDescriptionStep extends StatelessWidget {
  const _WorkDescriptionStep({
    required this.isTechnician,
    required this.onSave,
  });

  final bool isTechnician;
  final ValueChanged<String> onSave;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<JobsCubit, JobsState>(
      buildWhen: (JobsState previous, JobsState current) =>
          previous.selectedJob?.workDescription !=
              current.selectedJob?.workDescription ||
          previous.isSavingWorkDescription != current.isSavingWorkDescription ||
          previous.workDescriptionError != current.workDescriptionError ||
          previous.selectedJob?.status.value !=
              current.selectedJob?.status.value ||
          _currentStep(previous) != _currentStep(current),
      builder: (BuildContext context, JobsState state) {
        final Job? job = state.selectedJob;
        if (job == null) {
          return const SizedBox.shrink();
        }

        return _SectionBody(
          child: JobWorkflowStep(
            step: 3,
            done: (job.workDescription ?? '').trim().isNotEmpty,
            current: _currentStep(state) == 3,
            child: WorkDescriptionSection(
              initialText: job.workDescription ?? '',
              // Editable ONLY by the assigned technician while the job is
              // `in_progress`; admins and closed jobs get the read-only view
              // (the server enforces the same rule).
              canEdit:
                  isTechnician && job.status.value == JobStatus.inProgress,
              isSaving: state.isSavingWorkDescription,
              error: state.workDescriptionError,
              onSave: onSave,
            ),
          ),
        );
      },
    );
  }
}

/// Step 4 — After Photos: the finished site, captured while the job is
/// `in_progress` and read-only afterwards.
class _AfterPhotosStep extends StatelessWidget {
  const _AfterPhotosStep({
    required this.isTechnician,
    required this.onAdd,
    required this.onRetry,
    required this.loadBytes,
  });

  final bool isTechnician;
  final VoidCallback onAdd;
  final VoidCallback onRetry;
  final Future<Uint8List?> Function(JobFile file) loadBytes;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<JobsCubit, JobsState>(
      buildWhen: (JobsState previous, JobsState current) =>
          !identical(previous.afterPhotos, current.afterPhotos) ||
          previous.afterPhotoFailedIds != current.afterPhotoFailedIds ||
          previous.isAddingAfterPhoto != current.isAddingAfterPhoto ||
          previous.selectedJob?.status.value !=
              current.selectedJob?.status.value ||
          _currentStep(previous) != _currentStep(current),
      builder: (BuildContext context, JobsState state) {
        return _SectionBody(
          child: JobWorkflowStep(
            step: 4,
            done: state.afterPhotos.isNotEmpty,
            current: _currentStep(state) == 4,
            child: AfterPhotosSection(
              photos: state.afterPhotos,
              failedIds: state.afterPhotoFailedIds,
              // Capture is a technician execution action; admins view the
              // photos read-only (monitoring).
              canAdd:
                  isTechnician &&
                  state.selectedJob?.status.value == JobStatus.inProgress,
              isAdding: state.isAddingAfterPhoto,
              onAdd: onAdd,
              onRetry: onRetry,
              loadBytes: loadBytes,
            ),
          ),
        );
      },
    );
  }
}

/// Step 5 — the customer's signature, captured by the assigned technician while
/// the job is `in_progress` and read-only for everyone else afterwards.
class _SignatureStep extends StatelessWidget {
  const _SignatureStep({
    required this.isTechnician,
    required this.onCapture,
    required this.onRetry,
    required this.loadBytes,
    required this.onDrawingChanged,
  });

  final bool isTechnician;
  final Future<void> Function(Uint8List pngBytes) onCapture;
  final VoidCallback onRetry;
  final Future<Uint8List?> Function(JobFile file) loadBytes;
  final ValueChanged<bool> onDrawingChanged;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<JobsCubit, JobsState>(
      buildWhen: (JobsState previous, JobsState current) =>
          !identical(previous.signatureFiles, current.signatureFiles) ||
          previous.signatureFailedIds != current.signatureFailedIds ||
          previous.isCapturingSignature != current.isCapturingSignature ||
          previous.signatureError != current.signatureError ||
          previous.selectedJob?.status.value !=
              current.selectedJob?.status.value ||
          _currentStep(previous) != _currentStep(current),
      builder: (BuildContext context, JobsState state) {
        return _SectionBody(
          child: JobWorkflowStep(
            step: 5,
            done: state.signatureFiles.isNotEmpty,
            current: _currentStep(state) == 5,
            child: SignatureSection(
              signature: state.signatureFiles.isEmpty
                  ? null
                  : state.signatureFiles.last,
              failedIds: state.signatureFailedIds,
              canCapture:
                  isTechnician &&
                  state.selectedJob?.status.value == JobStatus.inProgress,
              isCapturing: state.isCapturingSignature,
              error: state.signatureError,
              onCapture: onCapture,
              onRetry: onRetry,
              loadBytes: loadBytes,
              // Freeze the page scroll while the customer draws; normal
              // scrolling resumes on lift.
              onDrawingChanged: onDrawingChanged,
            ),
          ),
        );
      },
    );
  }
}

/// Step 6 marker for a closed job: the workflow keeps its six visible stages
/// after completion, with the authoritative completion timestamp.
class _CompletionMarkerStep extends StatelessWidget {
  const _CompletionMarkerStep();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return BlocBuilder<JobsCubit, JobsState>(
      buildWhen: (JobsState previous, JobsState current) =>
          previous.selectedJob?.completedAt != current.selectedJob?.completedAt,
      builder: (BuildContext context, JobsState state) {
        final DateTime? completedAt = state.selectedJob?.completedAt;

        return _SectionBody(
          child: JobWorkflowStep(
            step: 6,
            done: true,
            current: false,
            child: Text(
              completedAt == null
                  ? l10n.statusCompleted
                  : l10n.jobCompletedAt(
                      formatJobDateTime(completedAt, context),
                    ),
              style: context.textStyles.bodyMedium,
            ),
          ),
        );
      },
    );
  }
}

/// Step 6 — the final action, with the completion checklist fed by the real
/// data states (never by the presence of a widget or of a local file).
class _CompletionStep extends StatelessWidget {
  const _CompletionStep({required this.onComplete, required this.onRetry});

  final VoidCallback onComplete;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<JobsCubit, JobsState>(
      buildWhen: (JobsState previous, JobsState current) =>
          previous.isCompletingJob != current.isCompletingJob ||
          previous.completionError != current.completionError ||
          previous.selectedJob?.workDescription !=
              current.selectedJob?.workDescription ||
          _currentStep(previous) != _currentStep(current) ||
          _completionGate(previous) != _completionGate(current),
      builder: (BuildContext context, JobsState state) {
        final Job? job = state.selectedJob;
        if (job == null) {
          return const SizedBox.shrink();
        }

        return _SectionBody(
          child: JobWorkflowStep(
            step: 6,
            done: false,
            current: _currentStep(state) == 6,
            // Sync-readiness gate: a local file alone does not satisfy the
            // server — every required file must be `synced` (registered
            // server-side) before completion is offered. Both facts come from
            // the EXISTING sync plumbing: the files' `syncState` plus the
            // failed-ids set.
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
              onComplete: onComplete,
              onRetry: onRetry,
            ),
          ),
        );
      },
    );
  }
}

/// The job's activity log — the last block on the page, built from the
/// lifecycle timestamps and the captured files' own capture times and sync
/// states. It renders nothing when there is no event yet.
class _ActivityCard extends StatelessWidget {
  const _ActivityCard();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<JobsCubit, JobsState>(
      buildWhen: (JobsState previous, JobsState current) =>
          previous.selectedJob != current.selectedJob ||
          !identical(previous.beforePhotos, current.beforePhotos) ||
          !identical(previous.afterPhotos, current.afterPhotos) ||
          !identical(previous.signatureFiles, current.signatureFiles) ||
          previous.beforePhotoFailedIds != current.beforePhotoFailedIds ||
          previous.afterPhotoFailedIds != current.afterPhotoFailedIds ||
          previous.signatureFailedIds != current.signatureFailedIds,
      builder: (BuildContext context, JobsState state) {
        final Job? job = state.selectedJob;
        if (job == null) {
          return const SizedBox.shrink();
        }

        // Nothing to log yet — no lifecycle timestamp and no captured file.
        // The frame is skipped entirely so the page never ends on an empty gap.
        final bool hasEvent =
            job.assignedAt != null ||
            job.startedAt != null ||
            job.completedAt != null ||
            state.beforePhotos.isNotEmpty ||
            state.afterPhotos.isNotEmpty ||
            state.signatureFiles.isNotEmpty;
        if (!hasEvent) {
          return const SizedBox.shrink();
        }

        return _SectionBody(
          child: JobActivitySection(
            job: job,
            beforePhotos: state.beforePhotos,
            afterPhotos: state.afterPhotos,
            signatureFiles: state.signatureFiles,
            failedIds: <String>{
              ...state.beforePhotoFailedIds,
              ...state.afterPhotoFailedIds,
              ...state.signatureFailedIds,
            },
          ),
        );
      },
    );
  }
}

/// The top margin every section of this page carries — inside the section, so a
/// section that renders nothing leaves no gap behind it.
class _SectionBody extends StatelessWidget {
  const _SectionBody({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.lg),
    child: child,
  );
}

/// The step the technician is expected to do next, derived from the facts this
/// page already holds. Presentation-only: it enables nothing and disables
/// nothing — the workflow rules live in the cubit and are re-checked by the
/// server on every write.
int _currentStep(JobsState state) {
  final Job? job = state.selectedJob;
  if (job == null) {
    return 0;
  }
  final String status = job.status.value;
  final bool isActive =
      status == JobStatus.inProgress || status == JobStatus.started;

  if (status == JobStatus.assigned) {
    return 1;
  }
  if (!isActive) {
    return 0;
  }
  if (state.beforePhotos.isEmpty) {
    return 2;
  }
  if ((job.workDescription ?? '').trim().isEmpty) {
    return 3;
  }
  if (state.afterPhotos.isEmpty) {
    return 4;
  }
  if (state.signatureFiles.isEmpty) {
    return 5;
  }
  return 6;
}

/// How many of the six stages are complete, from the same facts the frames
/// show.
int _completedSteps(JobsState state) {
  final Job? job = state.selectedJob;
  if (job == null) {
    return 0;
  }
  final int evidence = <bool>[
    state.beforePhotos.isNotEmpty,
    (job.workDescription ?? '').trim().isNotEmpty,
    state.afterPhotos.isNotEmpty,
    state.signatureFiles.isNotEmpty,
  ].where((bool done) => done).length;
  final String status = job.status.value;

  if (status == JobStatus.completed) {
    return 2 + evidence;
  }
  if (status == JobStatus.inProgress || status == JobStatus.started) {
    return 1 + evidence;
  }
  return 0;
}

/// A required file (before/after photo, signature) exists locally but its
/// upload has NOT been confirmed yet (`syncState` still `pending`, which covers
/// queued and in-flight queue operations) and its id is not in the failed set —
/// completion must wait for the shared sync engine.
bool _requiredFilePending(JobsState state) {
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
bool _requiredFileFailed(JobsState state) {
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

/// A comparable fingerprint of everything the completion checklist reads, so
/// the checklist rebuilds when one of its own inputs changes and stays put for
/// anything else.
(String, String, String, String, String) _completionGate(JobsState state) => (
  state.beforePhotos.isEmpty ? '-' : '+',
  state.afterPhotos.isEmpty ? '-' : '+',
  state.signatureFiles.isEmpty ? '-' : '+',
  (state.selectedJob?.workDescription ?? '').trim().isEmpty ? '-' : '+',
  '${_requiredFilePending(state)}/${_requiredFileFailed(state)}',
);
