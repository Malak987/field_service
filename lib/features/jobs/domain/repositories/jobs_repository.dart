import 'dart:typed_data';

import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_customer_info.dart';
import 'package:field_service/features/jobs/domain/entities/job_file.dart';

/// Domain contract for accessing job data.
///
/// Visibility (which jobs the current user may see) is enforced by **Supabase
/// RLS**, not by this contract. The implementation therefore issues the same
/// query for every role: RLS on `public.jobs` filters technicians to their own
/// assignments and lets admins see all jobs.
abstract interface class JobsRepository {
  /// Maximum length of a technician work description (trimmed characters).
  /// Shared by the domain validation ([SaveWorkDescription] use case), the
  /// data-layer pre-flight guard and the mirrored server-side rule — one
  /// value, never silently truncated client-side.
  static const int maxWorkDescriptionLength = 4000;

  /// Returns the jobs the current authenticated user is allowed to see.
  Future<List<Job>> getJobs();

  /// Returns a single job by [id].
  ///
  /// Throws when the job does not exist or is not accessible to the caller
  /// (the latter is enforced by RLS).
  Future<Job> getJobById(String id);

  /// Updates the `status` column of the job with [jobId].
  Future<void> updateJobStatus({required String jobId, required String status});

  /// Creates a new job AND assigns it in one step — the admin's workflow.
  ///
  /// Backed by the `create_job` SECURITY DEFINER RPC, the ONLY job-creation
  /// path. The server verifies that the caller is an active admin, that
  /// [jobType] is one of the two supported `JobCategory` values, that the
  /// customer exists and that [assignedEmployeeId] is an ACTIVE technician.
  /// It generates the job number, sets `status = 'assigned'` and stamps
  /// `assigned_at` with database time (the client never sends a timestamp),
  /// appends the `job_created` / `job_assigned` events and returns the
  /// authoritative row.
  ///
  /// This call is deliberately NOT offline-queued: the job number, the
  /// assignment timestamp and the returned row are all server-authoritative,
  /// and the admin picks from live customer/technician lists — so creation
  /// either lands on the server or reports an error the admin can retry.
  /// The offline-first sync queue remains the one path for the technician's
  /// execution actions (Start Job, Before Photos).
  ///
  /// Throws when the server refuses the creation (non-admin caller,
  /// unsupported category, unknown customer, invalid assignee, network).
  Future<Job> createJob({
    required String customerId,
    required String jobType,
    String? description,
    required String assignedEmployeeId,
  });

  /// The customer information belonging to the job with [jobId] — and to
  /// that job only.
  ///
  /// Backed by the `get_job_customer(job_id)` SECURITY DEFINER RPC: the
  /// server verifies that the job is assigned to the caller's *active*
  /// employee (or that the caller is an active admin) and returns just the
  /// display fields Job Details needs. The global `customers` table stays
  /// admin-only in RLS; there is deliberately no customer-by-id path here.
  ///
  /// Returns `null` when the caller is not entitled to the job's customer
  /// (another technician's job, inactive employee, …) or when the job has no
  /// resolvable customer.
  Future<JobCustomerInfo?> getJobCustomerInfo(String jobId);

  /// Starts the job with [jobId]: `assigned → in_progress`, automatic
  /// server-generated `started_at`, plus a `job_started` event — all applied
  /// atomically by the server (`start_job` RPC).  ///
  /// Offline-first: the start is persisted as a `job` [SyncOperation] in the
  /// durable sync queue and returns immediately; the shared sync engine
  /// pushes it when connectivity exists (which may be right away). The
  /// client never sends a timestamp — the authoritative `started_at` comes
  /// from the database and is visible on the next load of the job.
  ///
  /// Throws [JobAlreadyStartedException] when a start for this job is
  /// already queued/in flight (duplicate-start guard) — the server-side RPC
  /// is the final backstop and never creates a second `job_started` event.
  Future<void> startJob(String jobId);

  /// Saves the TECHNICIAN's [workDescription] (what was actually done) for
  /// the job with [jobId] — a separate field from the admin's customer
  /// request (`description`), which is never touched here.
  ///
  /// Offline-first, same convention as [startJob]: the trimmed text is
  /// persisted as a `job` [SyncOperation] in the durable sync queue (the
  /// queue row IS the local copy — it survives process restarts) and the
  /// method returns immediately; the shared sync engine pushes it when
  /// connectivity exists. The server (`save_work_description` RPC) is the
  /// authority: it resolves the caller from the auth identity (no
  /// client-supplied employee id), requires the job's assigned active
  /// technician, requires `in_progress`, trims/validates the text, stamps
  /// `updated_at`/the event time with `now()` and appends exactly one
  /// `work_description_added` event per effective change — replaying the
  /// same queued operation never duplicates the event.
  ///
  /// Throws [ArgumentError] for an empty/blank or over-length description
  /// (client-side pre-flight; the server re-validates regardless).
  Future<void> saveWorkDescription({
    required String jobId,
    required String workDescription,
  });

  // --- Before photos -----------------------------------------------------------

  /// Captures a before photo for the job with [jobId].
  ///
  /// Offline-first and identity-stable, reusing the existing offline
  /// architecture:
  /// 1. the picked image ([pickedFilePath], typically a temporary
  ///    camera/gallery path) is copied **immediately** into app-owned
  ///    storage — the temporary path is never relied upon again;
  /// 2. a local `job_files` row is created with the stable client-generated
  ///    file id and an automatic capture timestamp ([DateTime.now] — never
  ///    user-entered, never replaced by a later upload time);
  /// 3. the upload is queued in the durable sync queue and the shared sync
  ///    engine is nudged.
  ///
  /// The server side (`register_job_file` RPC) is authoritative: it refuses
  /// jobs the caller does not own and jobs that are not `in_progress`, and
  /// its idempotent insert guarantees retries never duplicate the file row
  /// or the `before_photo_captured` event.
  ///
  /// Returns the stable file id of the registered photo.
  Future<String> addBeforePhoto({
    required String jobId,
    required String pickedFilePath,
  });

  /// The before photos of [jobId]: local rows (including pending uploads)
  /// merged with backend-registered photos, deduplicated by file id and
  /// ordered by capture time. Offline-safe: when the backend is unreachable,
  /// the local photos are still returned.
  Future<List<JobFile>> getBeforePhotos(String jobId);

  /// Reactive variant of [getBeforePhotos]: emits immediately from the local
  /// database and again whenever local rows change (new capture, upload
  /// confirmed, …).
  Stream<List<JobFile>> watchBeforePhotos(String jobId);

  // --- After photos ------------------------------------------------------------

  /// Captures an after photo for the job with [jobId] — the finished-site
  /// counterpart of [addBeforePhoto], sharing the exact same offline-first
  /// path (stable local copy → automatic capture timestamp → durable sync
  /// queue → Storage upload → `register_job_file` RPC). The server refuses
  /// registrations that are not the assigned technician's, not `in_progress`
  /// or not of type `after`, and stays idempotent across retries (one row,
  /// one `after_photo_captured` event).
  ///
  /// Returns the stable file id of the registered photo.
  Future<String> addAfterPhoto({
    required String jobId,
    required String pickedFilePath,
  });

  /// The after photos of [jobId] — same merge semantics as
  /// [getBeforePhotos], filtered to `file_type = 'after'`.
  Future<List<JobFile>> getAfterPhotos(String jobId);

  /// Reactive variant of [getAfterPhotos].
  Stream<List<JobFile>> watchAfterPhotos(String jobId);

  // --- Customer signature ------------------------------------------------------

  /// Captures the customer's signature for the job with [jobId]: the PNG
  /// rendered from the on-screen drawing ([signatureImage]) is stored
  /// locally with a stable file id + automatic capture timestamp and its
  /// upload is queued in the durable sync queue — the exact offline-first
  /// path the photos use, with `file_type = 'signature'`.
  ///
  /// The server side (`register_job_file` RPC) is authoritative: it refuses
  /// callers who are not the assigned active technician, jobs that are not
  /// `in_progress` and mismatched storage paths, and its idempotent insert
  /// guarantees retries never duplicate the file row or the
  /// `signature_captured` event.
  ///
  /// Throws [ArgumentError] when [signatureImage] is empty — an empty
  /// signature is never queued.
  ///
  /// Returns the stable file id of the registered signature.
  Future<String> captureCustomerSignature({
    required String jobId,
    required Uint8List signatureImage,
  });

  /// The signature file(s) of [jobId] — same merge semantics as
  /// [getBeforePhotos], filtered to `file_type = 'signature'`.
  Future<List<JobFile>> getSignatureFiles(String jobId);

  /// Reactive variant of [getSignatureFiles].
  Stream<List<JobFile>> watchSignatureFiles(String jobId);

  // --- Complete Job ------------------------------------------------------------

  /// Completes the job with [jobId]: `in_progress → completed`, the FINAL
  /// workflow step.
  ///
  /// Authoritative and online-only BY DESIGN — unlike the capture steps,
  /// completion is NOT queued offline:
  /// * the decision depends on server-side facts (registered before/after
  ///   photos, the stored work description, the registered signature), and
  ///   only the server knows whether those have actually landed;
  /// * the `complete_job` RPC re-validates EVERY condition itself, applies
  ///   `status = 'completed'`, the server-generated `completed_at` and
  ///   exactly one `job_completed` event atomically, and is idempotent
  ///   against retries (a replay observes the completed job and returns it
  ///   unchanged — no second event, `completed_at` never reset).
  ///
  /// The client sends ONLY the job id — never an employee id, never a
  /// timestamp, never `has_*` flags. Returns the authoritative job row.
  ///
  /// Throws [JobCompletionOfflineException] when there is no internet
  /// connection — the job stays `in_progress`; nothing is marked completed
  /// locally and no local event is invented. Throws
  /// [JobCompletionRejectedException] when the server refuses the
  /// completion (see [CompletionRejectReason]).
  Future<Job> completeJob(String jobId);

  /// The displayable image bytes of [file] — from app-owned storage when the
  /// file exists locally, otherwise downloaded from Supabase Storage (whose
  /// object policies enforce the same job ownership). `null` when the bytes
  /// are no longer available.
  Future<Uint8List?> readPhotoBytes(JobFile file);

  /// Ids of job files whose queued upload is currently `failed` (drives the
  /// "Upload failed" badge and Retry action). Existing sync-queue states
  /// only — no parallel status system.
  Future<Set<String>> failedJobFileIds();

  /// Re-queues all failed sync operations and nudges the shared sync engine
  /// (the Retry action). Uses the existing `SyncProcessor`.
  Future<void> retryFailedSyncs();
}

/// Raised by [JobsRepository.startJob] when the job already has an
/// unfinished start operation in the sync queue, so the UI can explain
/// instead of enqueueing a duplicate. The server-side RPC stays
/// authoritative: it never applies a start twice regardless.
class JobAlreadyStartedException implements Exception {
  const JobAlreadyStartedException(this.jobId);

  final String jobId;

  @override
  String toString() => 'JobAlreadyStartedException($jobId)';
}

/// WHY the server refused a Complete Job request — mapped 1:1 from the
/// `complete_job` RPC's error codes so the UI can explain the rejection.
/// The server is the authority: the client never decides these itself.
enum CompletionRejectReason {
  /// No `job_files` row with `file_type = 'before'` exists for the job.
  missingBeforePhoto,

  /// `jobs.work_description` is null or blank after trimming.
  missingWorkDescription,

  /// No `job_files` row with `file_type = 'after'` exists for the job.
  missingAfterPhoto,

  /// No `job_files` row with `file_type = 'signature'` exists for the job.
  missingSignature,

  /// The job is not assigned to the authenticated technician.
  notAssigned,

  /// The job is not currently `in_progress` (assigned, cancelled, ...).
  invalidStatus,

  /// The caller is not an active technician (e.g. an admin — admins never
  /// complete jobs, they monitor read-only).
  unauthorized,

  /// A refusal this client build does not recognize.
  unknown,
}

/// Raised by [JobsRepository.completeJob] when the `complete_job` RPC
/// refuses the completion. Carries the machine-readable [reason] (mapped
/// from the server's error code) plus the server's own message for logs.
class JobCompletionRejectedException implements Exception {
  const JobCompletionRejectedException({
    required this.reason,
    this.serverMessage,
  });

  final CompletionRejectReason reason;

  /// The raw server message — diagnostics only, never shown unfiltered.
  final String? serverMessage;

  @override
  String toString() =>
      'JobCompletionRejectedException($reason, $serverMessage)';
}

/// Raised by [JobsRepository.completeJob] when there is no internet
/// connection. Completion is authoritative and online-only: nothing is
/// marked completed locally and no local `job_completed` event is invented
/// — the job stays `in_progress` until the server confirms.
class JobCompletionOfflineException implements Exception {
  const JobCompletionOfflineException();

  @override
  String toString() => 'JobCompletionOfflineException()';
}
