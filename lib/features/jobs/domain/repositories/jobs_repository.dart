import 'package:field_service/features/jobs/domain/entities/job.dart';

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
}
