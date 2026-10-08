// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:typed_data';

import 'package:field_service/core/utils/logger.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_customer_info.dart';
import 'package:field_service/features/jobs/domain/entities/job_file.dart';
import 'package:field_service/features/jobs/domain/entities/job_status.dart';
import 'package:field_service/features/jobs/domain/repositories/jobs_repository.dart';
import 'package:field_service/features/jobs/domain/usecases/add_after_photo.dart';
import 'package:field_service/features/jobs/domain/usecases/capture_customer_signature.dart';
import 'package:field_service/features/jobs/domain/usecases/complete_job.dart';
import 'package:field_service/features/jobs/domain/usecases/add_before_photo.dart';
import 'package:field_service/features/jobs/domain/usecases/get_failed_job_file_ids.dart';
import 'package:field_service/features/jobs/domain/usecases/get_job_by_id.dart';
import 'package:field_service/features/jobs/domain/usecases/get_job_customer_info.dart';
import 'package:field_service/features/jobs/domain/usecases/get_jobs.dart';
import 'package:field_service/features/jobs/domain/usecases/read_job_file_bytes.dart';
import 'package:field_service/features/jobs/domain/usecases/retry_failed_syncs.dart';
import 'package:field_service/features/jobs/domain/usecases/save_work_description.dart';
import 'package:field_service/features/jobs/domain/usecases/start_job.dart';
import 'package:field_service/features/jobs/domain/usecases/update_job_status.dart';
import 'package:field_service/features/jobs/domain/usecases/watch_after_photos.dart';
import 'package:field_service/features/jobs/domain/usecases/watch_before_photos.dart';
import 'package:field_service/features/jobs/domain/usecases/watch_signature.dart';
import 'package:field_service/features/jobs/presentation/cubit/jobs_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Outcome of an Add Before Photo attempt (typed so the page can pick the
/// right message without inspecting exceptions).
enum AddBeforePhotoOutcome {
  /// The photo was copied into app-owned storage, registered locally with an
  /// automatic capture timestamp and its upload queued (and nudged).
  added,

  /// A registration is already in flight — a repeated tap stays silent.
  inFlight,

  /// The photo could not be registered locally (see the logged error).
  failed,
}

/// Outcome of an Add After Photo attempt (typed so the page can pick the
/// right message without inspecting exceptions). Same semantics as
/// [AddBeforePhotoOutcome] — the after photo shares the exact offline-first
/// capture path, only the `file_type` and the server event differ.
enum AddAfterPhotoOutcome {
  /// The photo was copied into app-owned storage, registered locally with an
  /// automatic capture timestamp and its upload queued (and nudged).
  added,

  /// A registration is already in flight — a repeated tap stays silent.
  inFlight,

  /// The photo could not be registered locally (see the logged error).
  failed,
}

/// Outcome of a Customer Signature capture attempt (typed so the page can
/// pick the right feedback without inspecting exceptions). Same semantics
/// as the photo outcomes — the signature shares the exact offline-first
/// capture path (`file_type = 'signature'`).
enum CaptureSignatureOutcome {
  /// The rendered PNG was persisted locally with an automatic capture
  /// timestamp and its upload queued (and nudged).
  captured,

  /// The drawing was empty — nothing was stored; the validation error is
  /// published in [JobsState.signatureError].
  invalid,

  /// A capture is already being persisted — a repeated tap stays silent.
  inFlight,

  /// The signature could not be persisted locally (see the logged error).
  failed,
}

/// Inline validation error of the signature pad.
enum SignatureFieldError {
  /// The customer confirmed an empty drawing.
  empty,
}

/// Outcome of a Complete Job attempt (typed so the page can pick the right
/// feedback without inspecting exceptions).
enum CompleteJobOutcome {
  /// The server confirmed the completion: the authoritative job row
  /// (status `completed` + server-generated `completed_at`) replaced the
  /// local one and exactly one `job_completed` event exists server-side.
  completed,

  /// The server refused the completion — the reason is published in
  /// [JobsState.completionError]. The job stays `in_progress`.
  rejected,

  /// No internet connection — completion is authoritative and online-only,
  /// so nothing was marked completed locally. The job stays `in_progress`.
  offline,

  /// A completion request is already in flight — a repeated tap stays
  /// silent (no snackbar, no duplicate request).
  inFlight,

  /// The request could not be submitted (see the logged error).
  failed,
}

/// Why the last Complete Job attempt did not succeed — surfaced to the UI
/// as a localized explanation. Every value except [offline] mirrors a
/// server-side refusal (`complete_job` RPC); the server remains the
/// authority, the client never decides these itself.
enum JobCompletionError {
  /// No internet connection — the completion was never sent.
  offline,

  /// The server has no before photo for this job.
  missingBeforePhoto,

  /// The server has no (non-blank) work description for this job.
  missingWorkDescription,

  /// The server has no after photo for this job.
  missingAfterPhoto,

  /// The server has no customer signature for this job.
  missingSignature,

  /// The job is not assigned to this technician.
  notAssigned,

  /// The job is not currently in progress.
  invalidStatus,

  /// The caller is not an active technician (admins never complete jobs).
  unauthorized,

  /// A refusal this client build does not recognize.
  unknown,

  /// The server reported a required file missing WHILE the local copy of
  /// exactly that file kind still exists but is not `synced` (pending,
  /// in flight or failed) — i.e. the artifact is on its way (or needs the
  /// existing Retry) rather than truly absent. The server stays the
  /// authority; this only makes the explanation honest.
  stillSyncing,
}

/// Outcome of a Save Work Description attempt (typed so the page/section can
/// pick the right feedback without inspecting exceptions).
enum SaveWorkDescriptionOutcome {
  /// The save was accepted: the trimmed text is the new local value and the
  /// operation is queued/being pushed to the server.
  saved,

  /// The text is invalid (empty/blank or too long). Nothing was queued; the
  /// validation error is published in [JobsState.workDescriptionError].
  invalid,

  /// A save is already being submitted — a repeated tap stays silent.
  inFlight,

  /// The save could not be submitted (see the logged error).
  failed,
}

/// Inline validation error of the Work Description field.
enum WorkDescriptionFieldError { empty, tooLong }

/// Outcome of a Start Job attempt (typed so the page can pick the right
/// message without inspecting exceptions).
enum StartJobOutcome {
  /// The start was accepted: the local state is now `in_progress` and the
  /// operation is queued/being pushed to the server.
  started,

  /// The job is already started (or a start is already queued/in flight).
  /// Nothing was enqueued; no duplicate can ever occur.
  alreadyStarted,

  /// The request is already being submitted — a repeated tap that should
  /// stay silent (no snackbar).
  inFlight,

  /// The start could not be submitted (see the logged error).
  failed,
}

/// Presentation state for the Jobs feature.
///
/// Registered as a **factory** in the DI container: the list page and each
/// details page own their own instance. All data access goes through use
/// cases — there are no Supabase calls in this layer.
class JobsCubit extends Cubit<JobsState> {
  JobsCubit({
    required this._getJobs,
    required this._getJobById,
    required this._getJobCustomerInfo,
    required this._updateJobStatus,
    required this._startJob,
    required this._saveWorkDescription,
    required AddBeforePhoto addBeforePhoto,
    required WatchBeforePhotos watchBeforePhotos,
    required AddAfterPhoto addAfterPhoto,
    required WatchAfterPhotos watchAfterPhotos,
    required CaptureCustomerSignature captureCustomerSignature,
    required WatchSignature watchSignature,
    required CompleteJob completeJob,
    required ReadJobFileBytes readJobFileBytes,
    required RetryFailedSyncs retryFailedSyncs,
    required GetFailedJobFileIds getFailedJobFileIds,
  }) : _addBeforePhoto = addBeforePhoto,
       _watchBeforePhotos = watchBeforePhotos,
       _addAfterPhoto = addAfterPhoto,
       _watchAfterPhotos = watchAfterPhotos,
       _captureCustomerSignature = captureCustomerSignature,
       _watchSignature = watchSignature,
       _completeJob = completeJob,
       _readJobFileBytes = readJobFileBytes,
       _retryFailedSyncs = retryFailedSyncs,
       _getFailedJobFileIds = getFailedJobFileIds,
       super(const JobsState());

  final GetJobs _getJobs;
  final GetJobById _getJobById;
  final GetJobCustomerInfo _getJobCustomerInfo;
  final UpdateJobStatus _updateJobStatus;
  final StartJob _startJob;
  final SaveWorkDescription _saveWorkDescription;
  final AddBeforePhoto _addBeforePhoto;
  final WatchBeforePhotos _watchBeforePhotos;
  final AddAfterPhoto _addAfterPhoto;
  final WatchAfterPhotos _watchAfterPhotos;
  final CaptureCustomerSignature _captureCustomerSignature;
  final WatchSignature _watchSignature;
  final CompleteJob _completeJob;
  final ReadJobFileBytes _readJobFileBytes;
  final RetryFailedSyncs _retryFailedSyncs;
  final GetFailedJobFileIds _getFailedJobFileIds;

  /// Active before-photos watch (one job at a time — the details page).
  StreamSubscription<List<JobFile>>? _photoSubscription;
  String? _watchedJobId;

  /// Active after-photos watch (one job at a time — the details page).
  StreamSubscription<List<JobFile>>? _afterPhotoSubscription;
  String? _watchedAfterJobId;

  /// Active signature watch (one job at a time — the details page).
  StreamSubscription<List<JobFile>>? _signatureSubscription;
  String? _watchedSignatureJobId;

  /// Loads the jobs visible to the current user.
  ///
  /// RLS on `public.jobs` already scopes the result: technicians receive only
  /// their own assignments, admins receive all jobs. No role branching here.
  Future<void> loadJobs() async {
    emit(state.copyWith(status: JobsStatus.loading, clearError: true));

    try {
      final List<Job> jobs = await _getJobs();
      emit(state.copyWith(status: JobsStatus.success, jobs: jobs));
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Failed to load jobs.',
        error: error,
        stackTrace: stackTrace,
      );
      emit(state.copyWith(status: JobsStatus.failure, error: error));
    }
  }

  /// Loads a single job by [id] into [JobsState.selectedJob], together with
  /// the customer information belonging to that job into
  /// [JobsState.selectedJobCustomer].
  ///
  /// Access model:
  /// * [GetJobById] is scoped by **Supabase RLS** on `public.jobs` — a
  ///   technician can only load jobs assigned to their employee. Any other
  ///   job id is invisible and this load fails with an error state.
  /// * [GetJobCustomerInfo] goes through the `get_job_customer` SECURITY
  ///   DEFINER RPC, which returns the job's customer only when the caller is
  ///   entitled to it. It never returns rows from the global (admin-only)
  ///   `customers` table for anything but the single job being opened, and
  ///   it does not accept a customer id at all.
  ///
  /// A `null` [JobCustomerInfo] therefore means "not entitled / not present"
  /// and is a valid, empty customer section — not an error.
  Future<void> loadJobById(String id) async {
    _stopWatchingBeforePhotos();
    _stopWatchingAfterPhotos();
    _stopWatchingSignature();
    emit(
      state.copyWith(
        status: JobsStatus.loading,
        clearError: true,
        clearSelectedJob: true,
        clearSelectedJobCustomer: true,
        clearBeforePhotos: true,
        clearAfterPhotos: true,
        clearSignature: true,
        clearCompletionError: true,
      ),
    );

    try {
      final Job job = await _getJobById(id);

      // Independent lookup: a missing/unauthorized customer must not blank
      // the job itself. The RPC is the only customer read path here.
      JobCustomerInfo? customer;
      try {
        customer = await _getJobCustomerInfo(id);
      } catch (error, stackTrace) {
        AppLogger.warning(
          'Job customer lookup failed; showing the job without it.',
          error: error,
          stackTrace: stackTrace,
        );
        customer = null;
      }

      emit(
        state.copyWith(
          status: JobsStatus.success,
          selectedJob: job,
          selectedJobCustomer: customer,
          clearSelectedJobCustomer: customer == null,
          clearError: true,
        ),
      );
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Failed to load job details.',
        error: error,
        stackTrace: stackTrace,
      );
      emit(
        state.copyWith(
          status: JobsStatus.failure,
          error: error,
          clearSelectedJobCustomer: true,
        ),
      );
    }
  }

  /// Updates the status of the job with [jobId] to [status].
  ///
  /// On success the loaded job (list and/or details) is updated in place so
  /// the UI reflects the new status without a full reload.
  Future<void> updateJobStatus({
    required String jobId,
    required String status,
  }) async {
    try {
      await _updateJobStatus(jobId: jobId, status: status);
      _applyStatusUpdate(jobId, status);
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Failed to update job status.',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Starts the job with [jobId]: `assigned → in_progress`.
  ///
  /// Offline-first and double-start-safe:
  /// * The guard below rejects anything that is not `assigned`, so an
  ///   already-started job can never be submitted twice from this device.
  /// * [StartJob] persists the start in the durable sync queue (and nudges
  ///   the shared sync engine), so it works with no connectivity; the server
  ///   RPC applies status + server-generated `started_at` + `job_started`
  ///   event atomically and is itself idempotent against replays.
  /// * On acceptance, the local state flips immediately. No client timestamp
  ///   is invented: `started_at` stays unset locally until the job is next
  ///   loaded from the server, which then carries the authoritative value.
  Future<StartJobOutcome> startJob(String jobId) async {
    if (isClosed) {
      return StartJobOutcome.failed;
    }

    // A start for this job is already being submitted: swallow the tap.
    if (state.startingJobIds.contains(jobId)) {
      return StartJobOutcome.inFlight;
    }

    final Job? job = _jobById(jobId);
    if (job == null) {
      return StartJobOutcome.failed;
    }
    // Only an `assigned` job can be started. Anything else (in_progress,
    // completed, …) is reported as already started — never re-submitted.
    if (job.status.value != JobStatus.assigned) {
      return StartJobOutcome.alreadyStarted;
    }

    emit(
      state.copyWith(startingJobIds: <String>{...state.startingJobIds, jobId}),
    );

    try {
      await _startJob(jobId);
      if (!isClosed) {
        // Optimistic local flip; the server is authoritative and the
        // authoritative `started_at` arrives with the next load.
        _applyStatusUpdate(jobId, JobStatus.inProgress);
        emit(
          state.copyWith(
            startingJobIds: state.startingJobIds.difference(<String>{jobId}),
          ),
        );
        // Integration point: the workflow must transition on this very
        // screen (no restart/re-navigation). Best-effort fetch of the
        // authoritative row so the server-generated `started_at` becomes
        // visible as soon as the push has landed. Offline — or until the
        // queued push reaches the server — this silently keeps the
        // optimistic state; the client never invents a timestamp.
        unawaited(_refreshStartedJob(jobId));
      }
      return StartJobOutcome.started;
    } on JobAlreadyStartedException {
      if (!isClosed) {
        emit(
          state.copyWith(
            startingJobIds: state.startingJobIds.difference(<String>{jobId}),
          ),
        );
      }
      return StartJobOutcome.alreadyStarted;
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Failed to start job.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!isClosed) {
        emit(
          state.copyWith(
            startingJobIds: state.startingJobIds.difference(<String>{jobId}),
          ),
        );
      }
      return StartJobOutcome.failed;
    }
  }

  /// Best-effort authoritative refresh after a successful start.
  ///
  /// The start is pushed through the durable queue; online, the server
  /// applies it almost immediately and this fetch returns the row with the
  /// database-generated `started_at`, completing the on-screen transition.
  /// A reload that still reports `assigned` raced the push — the optimistic
  /// `in_progress` state is kept rather than regressing the UI. Any failure
  /// (offline) is swallowed: the optimistic state stays and the
  /// authoritative row arrives with the next normal load.
  Future<void> _refreshStartedJob(String jobId) async {
    try {
      final Job authoritative = await _getJobById(jobId);
      if (isClosed) {
        return;
      }
      if (authoritative.status.value == JobStatus.assigned) {
        return;
      }
      final Job? selected = state.selectedJob;
      emit(
        state.copyWith(
          selectedJob: selected != null && selected.id == jobId
              ? authoritative
              : selected,
          jobs: _replaceJob(state.jobs, authoritative),
        ),
      );
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Authoritative refresh after Start Job skipped (offline or race).',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  // --- Work Description ------------------------------------------------------

  /// Saves the technician's work description for [jobId] (what was actually
  /// done — separate from the admin's customer request in `description`).
  ///
  /// Offline-first and double-tap-safe, same conventions as [startJob]:
  /// * [SaveWorkDescription] validates (trim, non-empty, max length) and
  ///   persists the text in the durable sync queue; the shared engine pushes
  ///   it when connectivity exists. The server RPC is the authority for
  ///   caller identity, ownership, `in_progress` state and the event time.
  /// * On acceptance the local state updates immediately (optimistic) — no
  ///   client timestamp is invented; the authoritative `occurred_at` lives
  ///   server-side in the `work_description_added` event.
  Future<SaveWorkDescriptionOutcome> saveWorkDescription(
    String jobId,
    String text,
  ) async {
    if (isClosed) {
      return SaveWorkDescriptionOutcome.failed;
    }
    if (state.isSavingWorkDescription) {
      return SaveWorkDescriptionOutcome.inFlight;
    }

    final Job? job = _jobById(jobId);
    if (job == null) {
      return SaveWorkDescriptionOutcome.failed;
    }

    // Domain validation first: invalid text never enters the queue. The
    // inline field error is published for the section widget.
    String clean;
    try {
      clean = SaveWorkDescription.validate(text);
    } on ArgumentError {
      emit(
        state.copyWith(
          workDescriptionError: text.trim().isEmpty
              ? WorkDescriptionFieldError.empty
              : WorkDescriptionFieldError.tooLong,
        ),
      );
      return SaveWorkDescriptionOutcome.invalid;
    }

    emit(
      state.copyWith(
        isSavingWorkDescription: true,
        clearWorkDescriptionError: true,
      ),
    );

    try {
      await _saveWorkDescription(jobId: jobId, workDescription: clean);
      if (!isClosed) {
        // Optimistic local update; the server is authoritative and replays
        // of the same text are idempotent (no duplicate event).
        _applyWorkDescription(jobId, clean);
        emit(state.copyWith(isSavingWorkDescription: false));
      }
      return SaveWorkDescriptionOutcome.saved;
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Failed to queue the work description.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!isClosed) {
        emit(state.copyWith(isSavingWorkDescription: false));
      }
      return SaveWorkDescriptionOutcome.failed;
    }
  }

  void _applyWorkDescription(String jobId, String workDescription) {
    final Job? selectedJob = state.selectedJob;
    if (selectedJob != null && selectedJob.id == jobId) {
      final Job updated = selectedJob.copyWith(
        workDescription: workDescription,
        updatedAt: DateTime.now().toUtc(),
      );
      emit(
        state.copyWith(
          selectedJob: updated,
          jobs: _replaceJob(state.jobs, updated),
        ),
      );
      return;
    }

    emit(
      state.copyWith(
        jobs: state.jobs
            .map(
              (Job job) => job.id == jobId
                  ? job.copyWith(
                      workDescription: workDescription,
                      updatedAt: DateTime.now().toUtc(),
                    )
                  : job,
            )
            .toList(),
      ),
    );
  }

  // --- Before Photos -------------------------------------------------------

  /// Subscribes to the before photos of [jobId] (repository watch stream):
  /// a newly captured photo appears immediately, its badge flips from
  /// pending to synced when the shared sync engine confirms the upload, and
  /// failed uploads surface via the sync queue's failed state.
  ///
  /// Safe to call repeatedly: only the first call per job subscribes; a
  /// different job re-subscribes.
  void watchBeforePhotos(String jobId) {
    if (isClosed || _watchedJobId == jobId) {
      return;
    }

    _stopWatchingBeforePhotos();
    _watchedJobId = jobId;
    _photoSubscription = _watchBeforePhotos(jobId).listen(
      (List<JobFile> photos) async {
        if (isClosed) {
          return;
        }
        emit(state.copyWith(beforePhotos: photos));
        await _refreshFailedPhotoIds();
      },
      onError: (Object error, StackTrace stackTrace) {
        AppLogger.warning(
          'Before photos watch failed.',
          error: error,
          stackTrace: stackTrace,
        );
      },
    );
  }

  /// Registers a captured before photo for [jobId].
  ///
  /// Offline-first: the picked image is copied into app-owned storage and
  /// queued in the durable sync queue immediately — the call returns without
  /// network. The capture timestamp is recorded automatically; the server is
  /// authoritative for ownership and the `in_progress` rule and stays
  /// idempotent across retries.
  Future<AddBeforePhotoOutcome> addBeforePhoto({
    required String jobId,
    required String pickedFilePath,
  }) async {
    if (isClosed) {
      return AddBeforePhotoOutcome.failed;
    }
    if (state.isAddingBeforePhoto) {
      return AddBeforePhotoOutcome.inFlight;
    }

    emit(state.copyWith(isAddingBeforePhoto: true));
    try {
      await _addBeforePhoto(jobId: jobId, pickedFilePath: pickedFilePath);
      if (!isClosed) {
        emit(state.copyWith(isAddingBeforePhoto: false));
      }
      await _refreshFailedPhotoIds();
      return AddBeforePhotoOutcome.added;
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Failed to register a before photo.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!isClosed) {
        emit(state.copyWith(isAddingBeforePhoto: false));
      }
      return AddBeforePhotoOutcome.failed;
    }
  }

  /// Re-queues failed uploads (e.g. after being offline) and nudges the
  /// shared sync engine — the Retry action of the Before Photos section.
  Future<void> retryFailedBeforePhotos() async {
    if (isClosed) {
      return;
    }
    try {
      await _retryFailedSyncs();
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Retrying failed syncs did not succeed.',
        error: error,
        stackTrace: stackTrace,
      );
    }
    await _refreshFailedPhotoIds();
  }

  // --- After Photos --------------------------------------------------------

  /// Subscribes to the after photos of [jobId] (repository watch stream) —
  /// the same contract as [watchBeforePhotos] for `file_type = 'after'`: a
  /// newly captured photo appears immediately, its badge flips from pending
  /// to synced when the shared sync engine confirms the upload, and failed
  /// uploads surface via the sync queue's failed state.
  ///
  /// Safe to call repeatedly: only the first call per job subscribes; a
  /// different job re-subscribes.
  void watchAfterPhotos(String jobId) {
    if (isClosed || _watchedAfterJobId == jobId) {
      return;
    }

    _stopWatchingAfterPhotos();
    _watchedAfterJobId = jobId;
    _afterPhotoSubscription = _watchAfterPhotos(jobId).listen(
      (List<JobFile> photos) async {
        if (isClosed) {
          return;
        }
        emit(state.copyWith(afterPhotos: photos));
        await _refreshFailedPhotoIds();
      },
      onError: (Object error, StackTrace stackTrace) {
        AppLogger.warning(
          'After photos watch failed.',
          error: error,
          stackTrace: stackTrace,
        );
      },
    );
  }

  /// Registers a captured after photo for [jobId].
  ///
  /// Offline-first: the picked image is copied into app-owned storage and
  /// queued in the durable sync queue immediately — the call returns without
  /// network. The capture timestamp is recorded automatically; the server is
  /// authoritative for ownership, role and the `in_progress` rule and stays
  /// idempotent across retries.
  Future<AddAfterPhotoOutcome> addAfterPhoto({
    required String jobId,
    required String pickedFilePath,
  }) async {
    if (isClosed) {
      return AddAfterPhotoOutcome.failed;
    }
    if (state.isAddingAfterPhoto) {
      return AddAfterPhotoOutcome.inFlight;
    }

    emit(state.copyWith(isAddingAfterPhoto: true));
    try {
      await _addAfterPhoto(jobId: jobId, pickedFilePath: pickedFilePath);
      if (!isClosed) {
        emit(state.copyWith(isAddingAfterPhoto: false));
      }
      await _refreshFailedPhotoIds();
      return AddAfterPhotoOutcome.added;
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Failed to register an after photo.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!isClosed) {
        emit(state.copyWith(isAddingAfterPhoto: false));
      }
      return AddAfterPhotoOutcome.failed;
    }
  }

  /// Re-queues failed uploads and nudges the shared sync engine — the Retry
  /// action of the After Photos section (same shared queue as before
  /// photos; file ids are stable, so retries never duplicate anything).
  Future<void> retryFailedAfterPhotos() async {
    if (isClosed) {
      return;
    }
    try {
      await _retryFailedSyncs();
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Retrying failed syncs did not succeed.',
        error: error,
        stackTrace: stackTrace,
      );
    }
    await _refreshFailedPhotoIds();
  }

  /// The displayable bytes of [file] (local storage first, then Supabase
  /// Storage for backend-only photos). `null` when unavailable — the tile
  /// shows a placeholder.
  Future<Uint8List?> readPhotoBytes(JobFile file) {
    return _readJobFileBytes(file);
  }

  /// Re-reads which job photos currently sit in the `failed` sync state and
  /// publishes them for both sections. The sync queue tracks failures by the
  /// stable file id only — each section matches them against its own photos,
  /// so a before photo never badges an after photo and vice versa.
  Future<void> _refreshFailedPhotoIds() async {
    if (isClosed) {
      return;
    }
    try {
      final Set<String> failed = await _getFailedJobFileIds();
      if (!isClosed) {
        emit(
          state.copyWith(
            beforePhotoFailedIds: failed,
            afterPhotoFailedIds: failed,
            signatureFailedIds: failed,
          ),
        );
      }
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Failed to read failed job file ids.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _stopWatchingBeforePhotos() {
    _watchedJobId = null;
    final StreamSubscription<List<JobFile>>? subscription = _photoSubscription;
    _photoSubscription = null;
    unawaited(subscription?.cancel());
  }

  void _stopWatchingAfterPhotos() {
    _watchedAfterJobId = null;
    final StreamSubscription<List<JobFile>>? subscription =
        _afterPhotoSubscription;
    _afterPhotoSubscription = null;
    unawaited(subscription?.cancel());
  }

  // --- Customer Signature ----------------------------------------------------

  /// Subscribes to the customer signature of [jobId] (repository watch
  /// stream) — the same contract as the photo watches for `file_type =
  /// 'signature'`: a newly captured signature appears immediately (even
  /// offline) and its badge flips to synced when the shared sync engine
  /// confirms the upload.
  ///
  /// Safe to call repeatedly: only the first call per job subscribes; a
  /// different job re-subscribes.
  void watchSignature(String jobId) {
    if (isClosed || _watchedSignatureJobId == jobId) {
      return;
    }

    _stopWatchingSignature();
    _watchedSignatureJobId = jobId;
    _signatureSubscription = _watchSignature(jobId).listen(
      (List<JobFile> files) async {
        if (isClosed) {
          return;
        }
        emit(state.copyWith(signatureFiles: files));
        await _refreshFailedPhotoIds();
      },
      onError: (Object error, StackTrace stackTrace) {
        AppLogger.warning(
          'Signature watch failed.',
          error: error,
          stackTrace: stackTrace,
        );
      },
    );
  }

  /// Persists the customer's signature for [jobId].
  ///
  /// [signatureImage] — the PNG bytes rendered from the on-screen drawing.
  /// Offline-first: the bytes are copied into app-owned storage and queued
  /// in the durable sync queue immediately — the call returns without
  /// network. The capture timestamp is recorded automatically; the server
  /// is authoritative for ownership, role and the `in_progress` rule and
  /// stays idempotent across retries.
  Future<CaptureSignatureOutcome> captureCustomerSignature({
    required String jobId,
    required Uint8List signatureImage,
  }) async {
    if (isClosed) {
      return CaptureSignatureOutcome.failed;
    }
    if (state.isCapturingSignature) {
      return CaptureSignatureOutcome.inFlight;
    }
    if (signatureImage.isEmpty) {
      // An empty drawing never enters storage or the queue; the pad shows
      // the inline "signature required" error.
      emit(state.copyWith(signatureError: SignatureFieldError.empty));
      return CaptureSignatureOutcome.invalid;
    }

    emit(state.copyWith(isCapturingSignature: true, clearSignatureError: true));
    try {
      await _captureCustomerSignature(
        jobId: jobId,
        signatureImage: signatureImage,
      );
      if (!isClosed) {
        emit(state.copyWith(isCapturingSignature: false));
      }
      await _refreshFailedPhotoIds();
      return CaptureSignatureOutcome.captured;
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Failed to capture the customer signature.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!isClosed) {
        emit(state.copyWith(isCapturingSignature: false));
      }
      return CaptureSignatureOutcome.failed;
    }
  }

  /// Re-queues failed uploads and nudges the shared sync engine — the Retry
  /// action of the Customer Signature section (same shared queue as the
  /// photos; file ids are stable, so retries never duplicate anything).
  Future<void> retryFailedSignature() async {
    if (isClosed) {
      return;
    }
    try {
      await _retryFailedSyncs();
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Retrying failed syncs did not succeed.',
        error: error,
        stackTrace: stackTrace,
      );
    }
    await _refreshFailedPhotoIds();
  }

  void _stopWatchingSignature() {
    _watchedSignatureJobId = null;
    final StreamSubscription<List<JobFile>>? subscription =
        _signatureSubscription;
    _signatureSubscription = null;
    unawaited(subscription?.cancel());
  }

  // --- Complete Job --------------------------------------------------------------

  /// Completes the job with [jobId]: `in_progress → completed` — the FINAL
  /// workflow step.
  ///
  /// Authoritative and online-only (see [CompleteJob]): the server RPC
  /// re-validates every completion condition itself and applies the status,
  /// the server-generated `completed_at` and exactly one `job_completed`
  /// event atomically. The client only decides WHEN to ask:
  /// * a tap is swallowed while a request is already in flight
  ///   ([CompleteJobOutcome.inFlight]) — the button also disables itself;
  /// * without connectivity the repository throws
  ///   [JobCompletionOfflineException] and the job deliberately stays
  ///   `in_progress` — no local completion, no invented event;
  /// * a server refusal publishes the typed reason in
  ///   [JobsState.completionError] (a missing photo that has not been
  ///   synced yet is exactly this case — the server only counts what it
  ///   has registered).
  ///
  /// On success the AUTHORITATIVE row returned by the RPC replaces the
  /// local job (selected + list): the status badge flips to completed, the
  /// Completed Date field shows the server timestamp, and every
  /// `in_progress`-gated workflow control disappears by itself.
  Future<CompleteJobOutcome> completeJob(String jobId) async {
    if (isClosed) {
      return CompleteJobOutcome.failed;
    }
    if (state.isCompletingJob) {
      return CompleteJobOutcome.inFlight;
    }

    final Job? job = _jobById(jobId);
    // Only a loaded, still-in-progress job can be completed from this
    // screen. Anything else is reported as failed — never submitted.
    if (job == null || job.status.value != JobStatus.inProgress) {
      return CompleteJobOutcome.failed;
    }

    emit(state.copyWith(isCompletingJob: true, clearCompletionError: true));

    try {
      final Job completed = await _completeJob(jobId);
      if (!isClosed) {
        final Job? selected = state.selectedJob;
        emit(
          state.copyWith(
            isCompletingJob: false,
            selectedJob: selected != null && selected.id == jobId
                ? completed
                : selected,
            jobs: _replaceJob(state.jobs, completed),
          ),
        );
      }
      return CompleteJobOutcome.completed;
    } on JobCompletionOfflineException {
      if (!isClosed) {
        emit(
          state.copyWith(
            isCompletingJob: false,
            completionError: JobCompletionError.offline,
          ),
        );
      }
      return CompleteJobOutcome.offline;
    } on JobCompletionRejectedException catch (error, stackTrace) {
      AppLogger.warning(
        'The server refused to complete the job.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!isClosed) {
        emit(
          state.copyWith(
            isCompletingJob: false,
            completionError: _completionErrorFor(error.reason, state: state),
          ),
        );
      }
      return CompleteJobOutcome.rejected;
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Failed to complete the job.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!isClosed) {
        emit(
          state.copyWith(
            isCompletingJob: false,
            completionError: JobCompletionError.unknown,
          ),
        );
      }
      return CompleteJobOutcome.failed;
    }
  }

  /// Maps the server's typed refusal onto the presentation error.
  ///
  /// Defensive refinement (server stays authoritative, nothing is bypassed):
  /// when the server reports a required FILE missing but the local state
  /// still holds exactly that file kind not yet `synced` (pending, in
  /// flight or failed), the honest explanation is "still syncing / needs
  /// retry" — the artifact exists on this device and has simply not been
  /// registered server-side yet.
  static JobCompletionError _completionErrorFor(
    CompletionRejectReason r, {
    required JobsState state,
  }) {
    bool unsynced(List<JobFile> files) {
      return files.any(
        (JobFile file) => file.syncState != JobFileSyncState.synced,
      );
    }

    switch (r) {
      case CompletionRejectReason.missingBeforePhoto:
        return unsynced(state.beforePhotos)
            ? JobCompletionError.stillSyncing
            : JobCompletionError.missingBeforePhoto;
      case CompletionRejectReason.missingAfterPhoto:
        return unsynced(state.afterPhotos)
            ? JobCompletionError.stillSyncing
            : JobCompletionError.missingAfterPhoto;
      case CompletionRejectReason.missingSignature:
        return unsynced(state.signatureFiles)
            ? JobCompletionError.stillSyncing
            : JobCompletionError.missingSignature;
      case CompletionRejectReason.missingWorkDescription:
        return JobCompletionError.missingWorkDescription;
      case CompletionRejectReason.notAssigned:
        return JobCompletionError.notAssigned;
      case CompletionRejectReason.invalidStatus:
        return JobCompletionError.invalidStatus;
      case CompletionRejectReason.unauthorized:
        return JobCompletionError.unauthorized;
      case CompletionRejectReason.unknown:
        return JobCompletionError.unknown;
    }
  }

  @override
  Future<void> close() {
    _stopWatchingBeforePhotos();
    _stopWatchingAfterPhotos();
    _stopWatchingSignature();
    return super.close();
  }

  /// Finds the job with [id] in the selected job or the loaded list.
  Job? _jobById(String jobId) {
    final Job? selected = state.selectedJob;
    if (selected != null && selected.id == jobId) {
      return selected;
    }
    for (final Job job in state.jobs) {
      if (job.id == jobId) {
        return job;
      }
    }
    return null;
  }

  void _applyStatusUpdate(String jobId, String status) {
    final Job? selectedJob = state.selectedJob;
    if (selectedJob != null && selectedJob.id == jobId) {
      final Job updated = selectedJob.copyWith(
        status: JobStatus(status),
        updatedAt: DateTime.now().toUtc(),
      );
      emit(
        state.copyWith(
          selectedJob: updated,
          jobs: _replaceJob(state.jobs, updated),
        ),
      );
      return;
    }

    emit(state.copyWith(jobs: _mapStatus(state.jobs, jobId, status)));
  }

  static List<Job> _replaceJob(List<Job> jobs, Job replacement) {
    return jobs
        .map((Job job) => job.id == replacement.id ? replacement : job)
        .toList();
  }

  static List<Job> _mapStatus(List<Job> jobs, String jobId, String status) {
    return jobs.map((Job job) {
      return job.id == jobId
          ? job.copyWith(
              status: JobStatus(status),
              updatedAt: DateTime.now().toUtc(),
            )
          : job;
    }).toList();
  }
}
