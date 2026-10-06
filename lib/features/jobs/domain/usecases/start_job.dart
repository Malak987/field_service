import 'package:field_service/features/jobs/domain/repositories/jobs_repository.dart';

/// Use case: start the job with [jobId].
///
/// Offline-first contract (mirrors the Customers write path): the call
/// persists the start as a [SyncOperation] in the durable queue and returns
/// immediately — the local UI flips `assigned → in_progress` at once, and
/// the shared sync engine pushes the `start_job` RPC as soon as there is
/// internet. The authoritative `started_at` is generated server-side by the
/// database; no client-provided timestamp ever travels with the operation.
///
/// Throws [JobAlreadyStartedException] when a start for this job is already
/// queued or in flight, so the same job can never be started twice.
class StartJob {
  const StartJob(this._repository);

  final JobsRepository _repository;

  Future<void> call(String jobId) => _repository.startJob(jobId);
}
