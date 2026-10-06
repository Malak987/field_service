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
  /// Returns the jobs the current authenticated user is allowed to see.
  Future<List<Job>> getJobs();

  /// Returns a single job by [id].
  ///
  /// Throws when the job does not exist or is not accessible to the caller
  /// (the latter is enforced by RLS).
  Future<Job> getJobById(String id);

  /// Updates the `status` column of the job with [jobId].
  Future<void> updateJobStatus({
    required String jobId,
    required String status,
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
  /// atomically by the server (`start_job` RPC).
  ///
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
