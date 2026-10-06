import 'package:field_service/features/jobs/domain/repositories/jobs_repository.dart';

/// Ids of job files whose queued upload is currently in the `failed` state
/// (awaiting a retry). Drives the "Upload failed" badge and the Retry action
/// in the Before Photos section — using only states the existing sync queue
/// already tracks.
class GetFailedJobFileIds {
  const GetFailedJobFileIds(this._repository);

  final JobsRepository _repository;

  Future<Set<String>> call() {
    return _repository.failedJobFileIds();
  }
}
