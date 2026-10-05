import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/repositories/jobs_repository.dart';

/// Use case: fetch the jobs visible to the current user.
///
/// Filtering by role is the responsibility of Supabase RLS, so this use case
/// simply delegates to the repository.
class GetJobs {
  const GetJobs(this._repository);

  final JobsRepository _repository;

  Future<List<Job>> call() => _repository.getJobs();
}
