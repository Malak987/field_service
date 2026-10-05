import 'package:field_service/features/jobs/data/models/job_model.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Remote data source contract for the `public.jobs` table.
///
/// Row → domain mapping happens inside the implementation; callers receive
/// fully-built domain [Job]s (never raw maps).
///
/// Visibility (which jobs the current user may see) is enforced entirely by
/// **Supabase RLS** — this data source issues the same query for every role.
abstract interface class JobsRemoteDataSource {
  /// Selects all jobs visible to the current user, ordered by `created_at`
  /// descending, joined with `customers(name)` / `employees(name)`.
  Future<List<Job>> getJobs();

  /// Selects a single job by [id].
  ///
  /// Throws a [StateError] when the job does not exist or is not accessible
  /// to the caller (RLS).
  Future<Job> getJobById(String id);

  /// Updates `status` (and `updated_at`) of the job with [jobId].
  Future<void> updateJobStatus({
    required String jobId,
    required String status,
  });
}

class JobsRemoteDataSourceImpl implements JobsRemoteDataSource {
  JobsRemoteDataSourceImpl(this.supabase);

  final SupabaseClient supabase;

  /// Select clause covering exactly the real columns of `public.jobs` plus
  /// the two display-name embeds.
  ///
  /// `customers(name)` / `employees(name)` rely on the default FK constraint
  /// names (`jobs_customer_id_fkey` / `jobs_assigned_employee_id_fkey`),
  /// which PostgREST resolves to the relation names `customers` / `employees`.
  static const String _selectClause =
      'id, job_number, customer_id, assigned_employee_id, job_type, '
      'description, status, assigned_at, started_at, completed_at, '
      'created_at, updated_at, expires_at, customers(name), employees(name)';

  @override
  Future<List<Job>> getJobs() async {
    final List<Map<String, dynamic>> rows = await supabase
        .from('jobs')
        .select(_selectClause)
        .order('created_at', ascending: false);

    return rows.map(JobModel.fromMap).toList();
  }

  @override
  Future<Job> getJobById(String id) async {
    final Map<String, dynamic>? row = await supabase
        .from('jobs')
        .select(_selectClause)
        .eq('id', id)
        .maybeSingle();

    if (row == null) {
      throw StateError('Job not found: $id');
    }

    return JobModel.fromMap(row);
  }

  @override
  Future<void> updateJobStatus({
    required String jobId,
    required String status,
  }) {
    return supabase
        .from('jobs')
        .update(<String, dynamic>{
          'status': status,
          'updated_at': DateTime.now().toUtc(),
        })
        .eq('id', jobId)
        .select();
  }
}
