import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/repositories/jobs_repository.dart';

/// Use case: complete the job with [jobId] — the FINAL workflow step
/// (`in_progress → completed`).
///
/// Authoritative and online-only by design: the `complete_job` RPC
/// re-validates every completion condition server-side (before photo, work
/// description, after photo, customer signature), applies the status, the
/// server-generated `completed_at` and exactly one `job_completed` event
/// atomically, and is idempotent against retries. The client sends only the
/// job id — never an employee id, timestamp or `has_*` flag.
///
/// Offline, completion is NOT queued: the repository throws
/// [JobCompletionOfflineException] and the job stays `in_progress` until
/// the server can confirm. See [JobsRepository.completeJob].
class CompleteJob {
  const CompleteJob(this._repository);

  final JobsRepository _repository;

  Future<Job> call(String jobId) => _repository.completeJob(jobId);
}
