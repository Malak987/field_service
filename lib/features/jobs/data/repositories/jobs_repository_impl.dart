import 'package:field_service/features/jobs/data/datasources/jobs_remote_data_source.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/repositories/jobs_repository.dart';

/// Data-layer implementation of [JobsRepository].
///
/// Thin delegation to [JobsRemoteDataSource]. All Supabase access lives in
/// the data source; this class contains no queries.
class JobsRepositoryImpl implements JobsRepository {
  JobsRepositoryImpl({required this._remoteDataSource});

  final JobsRemoteDataSource _remoteDataSource;

  @override
  Future<List<Job>> getJobs() {
    return _remoteDataSource.getJobs();
  }

  @override
  Future<Job> getJobById(String id) {
    return _remoteDataSource.getJobById(id);
  }

  @override
  Future<void> updateJobStatus({
    required String jobId,
    required String status,
  }) {
    return _remoteDataSource.updateJobStatus(
      jobId: jobId,
      status: status,
    );
  }
}
