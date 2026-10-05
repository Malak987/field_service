import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/repositories/jobs_repository.dart';

/// Use case: fetch a single job by its id.
class GetJobById {
  const GetJobById(this._repository);

  final JobsRepository _repository;

  Future<Job> call(String id) => _repository.getJobById(id);
}
