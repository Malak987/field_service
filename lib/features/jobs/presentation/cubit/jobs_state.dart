import 'package:equatable/equatable.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_customer_info.dart';
import 'package:field_service/features/jobs/domain/entities/job_file.dart';
import 'package:field_service/features/jobs/presentation/cubit/jobs_cubit.dart';

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
    this.afterPhotos = const <JobFile>[],
    this.afterPhotoFailedIds = const <String>{},
    this.isAddingAfterPhoto = false,
    this.signatureFiles = const <JobFile>[],
    this.signatureFailedIds = const <String>{},
    this.isCapturingSignature = false,
    this.signatureError,
    this.isCompletingJob = false,
    this.completionError,
    this.isSavingWorkDescription = false,
    this.workDescriptionError,
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

  /// After photos of [selectedJob], ordered by capture time: local rows
  /// (including pending uploads) merged with backend-registered photos.
  /// Fed by the repository's watch stream — a new capture appears
  /// immediately and flips to `synced` once the upload is confirmed.
  final List<JobFile> afterPhotos;

  /// Ids of after photos whose queued upload currently sits in the
  /// `failed` sync state (drives the "Upload failed" badge + Retry).
  final Set<String> afterPhotoFailedIds;

  /// An after photo is currently being registered locally (copying bytes +
  /// enqueueing the upload). Drives the add button's busy/disabled state so
  /// a double tap cannot register the same pick twice.
  final bool isAddingAfterPhoto;

  /// The customer signature file(s) of [selectedJob] (`file_type =
  /// 'signature'`), ordered by capture time — local rows (including pending
  /// uploads) merged with backend-registered ones. Fed by the repository's
  /// watch stream; the UI shows the latest entry.
  final List<JobFile> signatureFiles;

  /// Ids of signature files whose queued upload currently sits in the
  /// `failed` sync state (drives the "Upload failed" badge + Retry).
  final Set<String> signatureFailedIds;

  /// A signature capture is currently being persisted locally (writing the
  /// rendered PNG + enqueueing the upload). Drives the Save button's
  /// busy/disabled state so a double tap cannot register twice.
  final bool isCapturingSignature;

  /// Inline validation error of the signature pad — `null` when valid. Set
  /// by a rejected (empty) capture, cleared by the next attempt.
  final SignatureFieldError? signatureError;

  /// A Complete Job request is currently being submitted to the server.
  /// Drives the Complete button's busy/disabled state so a double tap can
  /// never submit the completion twice.
  final bool isCompletingJob;

  /// Why the last Complete Job attempt did not succeed — `null` when there
  /// is nothing to report (or it is being cleared by a new attempt).
  /// `offline` means the device has no connection and the job deliberately
  /// stayed `in_progress`; the other values mirror the server's refusal.
  final JobCompletionError? completionError;

  /// A work description save is currently being submitted (validation done,
  /// queueing/pushing). Drives the Save button's busy/disabled state.
  final bool isSavingWorkDescription;

  /// Inline validation error of the Work Description field — `null` when
  /// the field is valid. Set by a rejected save, cleared by the next one.
  final WorkDescriptionFieldError? workDescriptionError;

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
    List<JobFile>? afterPhotos,
    Set<String>? afterPhotoFailedIds,
    bool? isAddingAfterPhoto,
    List<JobFile>? signatureFiles,
    Set<String>? signatureFailedIds,
    SignatureFieldError? signatureError,
    bool clearSignatureError = false,
    bool? isCapturingSignature,
    bool? isCompletingJob,
    JobCompletionError? completionError,
    bool clearCompletionError = false,
    bool? isSavingWorkDescription,
    WorkDescriptionFieldError? workDescriptionError,
    bool clearWorkDescriptionError = false,
    Object? error,
    bool clearError = false,
    bool clearSelectedJob = false,
    bool clearSelectedJobCustomer = false,
    bool clearBeforePhotos = false,
    bool clearAfterPhotos = false,
    bool clearSignature = false,
  }) {
    return JobsState(
      status: status ?? this.status,
      jobs: jobs ?? this.jobs,
      selectedJob: clearSelectedJob ? null : (selectedJob ?? this.selectedJob),
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
      afterPhotos: clearAfterPhotos
          ? const <JobFile>[]
          : (afterPhotos ?? this.afterPhotos),
      afterPhotoFailedIds: clearAfterPhotos
          ? const <String>{}
          : (afterPhotoFailedIds ?? this.afterPhotoFailedIds),
      isAddingAfterPhoto: isAddingAfterPhoto ?? this.isAddingAfterPhoto,
      signatureFiles: clearSignature
          ? const <JobFile>[]
          : (signatureFiles ?? this.signatureFiles),
      signatureFailedIds: clearSignature
          ? const <String>{}
          : (signatureFailedIds ?? this.signatureFailedIds),
      isCapturingSignature: isCapturingSignature ?? this.isCapturingSignature,
      signatureError: clearSignatureError
          ? null
          : (signatureError ?? this.signatureError),
      isCompletingJob: isCompletingJob ?? this.isCompletingJob,
      completionError: clearCompletionError
          ? null
          : (completionError ?? this.completionError),
      isSavingWorkDescription:
          isSavingWorkDescription ?? this.isSavingWorkDescription,
      workDescriptionError: clearWorkDescriptionError
          ? null
          : (workDescriptionError ?? this.workDescriptionError),
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  List<Object?> get props => <Object?>[
    status,
    jobs,
    selectedJob,
    selectedJobCustomer,
    startingJobIds,
    beforePhotos,
    beforePhotoFailedIds,
    isAddingBeforePhoto,
    afterPhotos,
    afterPhotoFailedIds,
    isAddingAfterPhoto,
    signatureFiles,
    signatureFailedIds,
    isCapturingSignature,
    signatureError,
    isCompletingJob,
    completionError,
    isSavingWorkDescription,
    workDescriptionError,
    error,
  ];
}
