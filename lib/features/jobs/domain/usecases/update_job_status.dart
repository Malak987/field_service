import 'package:field_service/features/jobs/domain/repositories/jobs_repository.dart';

/// Use case: update the status of a job.
class UpdateJobStatus {
  const UpdateJobStatus(this._repository);

  final JobsRepository _repository;

  Future<void> call({
    required String jobId,
    required String status,
  }) {
    return _repository.updateJobStatus(jobId: jobId, status: status);
  }
}
