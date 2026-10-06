// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:typed_data';

import 'package:field_service/core/utils/logger.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_customer_info.dart';
import 'package:field_service/features/jobs/domain/entities/job_file.dart';
import 'package:field_service/features/jobs/domain/entities/job_status.dart';
import 'package:field_service/features/jobs/domain/repositories/jobs_repository.dart';
import 'package:field_service/features/jobs/domain/usecases/add_before_photo.dart';
import 'package:field_service/features/jobs/domain/usecases/get_failed_job_file_ids.dart';
import 'package:field_service/features/jobs/domain/usecases/get_job_by_id.dart';
import 'package:field_service/features/jobs/domain/usecases/get_job_customer_info.dart';
import 'package:field_service/features/jobs/domain/usecases/get_jobs.dart';
import 'package:field_service/features/jobs/domain/usecases/read_job_file_bytes.dart';
import 'package:field_service/features/jobs/domain/usecases/retry_failed_syncs.dart';
import 'package:field_service/features/jobs/domain/usecases/start_job.dart';
import 'package:field_service/features/jobs/domain/usecases/update_job_status.dart';
import 'package:field_service/features/jobs/domain/usecases/watch_before_photos.dart';
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
    required AddBeforePhoto addBeforePhoto,
    required WatchBeforePhotos watchBeforePhotos,
    required ReadJobFileBytes readJobFileBytes,
    required RetryFailedSyncs retryFailedSyncs,
    required GetFailedJobFileIds getFailedJobFileIds,
  }) : _addBeforePhoto = addBeforePhoto,
       _watchBeforePhotos = watchBeforePhotos,
       _readJobFileBytes = readJobFileBytes,
       _retryFailedSyncs = retryFailedSyncs,
       _getFailedJobFileIds = getFailedJobFileIds,
       super(const JobsState());

  final GetJobs _getJobs;
  final GetJobById _getJobById;
  final GetJobCustomerInfo _getJobCustomerInfo;
  final UpdateJobStatus _updateJobStatus;
  final StartJob _startJob;
  final AddBeforePhoto _addBeforePhoto;
  final WatchBeforePhotos _watchBeforePhotos;
  final ReadJobFileBytes _readJobFileBytes;
  final RetryFailedSyncs _retryFailedSyncs;
  final GetFailedJobFileIds _getFailedJobFileIds;

  /// Active before-photos watch (one job at a time — the details page).
  StreamSubscription<List<JobFile>>? _photoSubscription;
  String? _watchedJobId;

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
      AppLogger.warning('Failed to load jobs.', error: error, stackTrace: stackTrace);
      emit(
        state.copyWith(status: JobsStatus.failure, error: error),
      );
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
    emit(
      state.copyWith(
        status: JobsStatus.loading,
        clearError: true,
        clearSelectedJob: true,
        clearSelectedJobCustomer: true,
        clearBeforePhotos: true,
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
      state.copyWith(
        startingJobIds: <String>{...state.startingJobIds, jobId},
      ),
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

  /// The displayable bytes of [file] (local storage first, then Supabase
  /// Storage for backend-only photos). `null` when unavailable — the tile
  /// shows a placeholder.
  Future<Uint8List?> readPhotoBytes(JobFile file) {
    return _readJobFileBytes(file);
  }

  /// Re-reads which before photos currently sit in the `failed` sync state
  /// and publishes them.
  Future<void> _refreshFailedPhotoIds() async {
    if (isClosed) {
      return;
    }
    try {
      final Set<String> failed = await _getFailedJobFileIds();
      if (!isClosed) {
        emit(state.copyWith(beforePhotoFailedIds: failed));
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
    final StreamSubscription<List<JobFile>>? subscription =
        _photoSubscription;
    _photoSubscription = null;
    unawaited(subscription?.cancel());
  }

  @override
  Future<void> close() {
    _stopWatchingBeforePhotos();
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

    emit(
      state.copyWith(
        jobs: _mapStatus(state.jobs, jobId, status),
      ),
    );
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
