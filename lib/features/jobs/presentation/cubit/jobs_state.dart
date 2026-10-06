import 'package:equatable/equatable.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_customer_info.dart';
import 'package:field_service/features/jobs/domain/entities/job_file.dart';

/// Lifecycle of a jobs request.
enum JobsStatus { initial, loading, success, failure }

/// Presentation state for [JobsCubit].
///
/// Serves both surfaces that share one cubit contract:
/// * the **list** page reads [jobs],
/// * the **details** page reads [selectedJob].
class JobsState extends Equatable {
  const JobsState({
    this.status = JobsStatus.initial,
    this.jobs = const <Job>[],
    this.selectedJob,
    this.selectedJobCustomer,
    this.startingJobIds = const <String>{},
    this.beforePhotos = const <JobFile>[],
    this.beforePhotoFailedIds = const <String>{},
    this.isAddingBeforePhoto = false,
    this.error,
  });

  /// Current lifecycle of the last (or in-flight) request.
  final JobsStatus status;

  /// Jobs list (list page).
  final List<Job> jobs;

  /// Single job (details page), once loaded.
  final Job? selectedJob;

  /// The customer information belonging to [selectedJob] (details page).
  ///
  /// Loaded through the `get_job_customer` RPC, so it only ever holds data
  /// for a job the current user is entitled to. `null` while unresolved, or
  /// when the user is not entitled to the job's customer (another
  /// technician's job, inactive employee) — the page then shows no customer
  /// section at all, never a partial/global list.
  final JobCustomerInfo? selectedJobCustomer;

  /// Jobs whose `start_job` request is currently being submitted
  /// (queued / being pushed). Drives the Start button's busy + disabled
  /// state and prevents double taps from enqueueing twice.
  final Set<String> startingJobIds;

  /// Before photos of [selectedJob], ordered by capture time: local rows
  /// (including pending uploads) merged with backend-registered photos.
  /// Fed by the repository's watch stream — a new capture appears
  /// immediately and flips to `synced` once the upload is confirmed.
  final List<JobFile> beforePhotos;

  /// Ids of before photos whose queued upload currently sits in the
  /// `failed` sync state (drives the "Upload failed" badge + Retry).
  final Set<String> beforePhotoFailedIds;

  /// A before photo is currently being registered locally (copying bytes +
  /// enqueueing the upload). Drives the add button's busy/disabled state so
  /// a double tap cannot register the same pick twice.
  final bool isAddingBeforePhoto;

  /// Last error, if [status] is [JobsStatus.failure].
  final Object? error;

  JobsState copyWith({
    JobsStatus? status,
    List<Job>? jobs,
    Job? selectedJob,
    JobCustomerInfo? selectedJobCustomer,
    Set<String>? startingJobIds,
    List<JobFile>? beforePhotos,
    Set<String>? beforePhotoFailedIds,
    bool? isAddingBeforePhoto,
    Object? error,
    bool clearError = false,
    bool clearSelectedJob = false,
    bool clearSelectedJobCustomer = false,
    bool clearBeforePhotos = false,
  }) {
    return JobsState(
      status: status ?? this.status,
      jobs: jobs ?? this.jobs,
      selectedJob:
          clearSelectedJob ? null : (selectedJob ?? this.selectedJob),
      selectedJobCustomer: clearSelectedJobCustomer
          ? null
          : (selectedJobCustomer ?? this.selectedJobCustomer),
      startingJobIds: startingJobIds ?? this.startingJobIds,
      beforePhotos: clearBeforePhotos
          ? const <JobFile>[]
          : (beforePhotos ?? this.beforePhotos),
      beforePhotoFailedIds: clearBeforePhotos
          ? const <String>{}
          : (beforePhotoFailedIds ?? this.beforePhotoFailedIds),
      isAddingBeforePhoto: isAddingBeforePhoto ?? this.isAddingBeforePhoto,
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  List<Object?> get props =>
      <Object?>[
        status,
        jobs,
        selectedJob,
        selectedJobCustomer,
        startingJobIds,
        beforePhotos,
        beforePhotoFailedIds,
        isAddingBeforePhoto,
        error,
      ];
}
