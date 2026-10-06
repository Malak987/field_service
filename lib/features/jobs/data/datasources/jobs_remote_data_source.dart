import 'package:field_service/features/jobs/data/models/job_customer_info_model.dart';
import 'package:field_service/features/jobs/data/models/job_model.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_customer_info.dart';
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

  /// Calls the `get_job_customer(job_id)` SECURITY DEFINER RPC and maps the
  /// (at most one) returned row.
  ///
  /// Authorization happens server-side inside the function: it returns zero
  /// rows unless the job is assigned to the caller's active employee (or the
  /// caller is an active admin). This data source never reads
  /// `public.customers` directly — that table remains admin-only in RLS.
  Future<JobCustomerInfo?> getJobCustomerInfo(String jobId);

  /// Calls the `start_job(job_id)` SECURITY DEFINER RPC — the ONLY write
  /// path for starting a job.
  ///
  /// The server verifies ownership (`auth.uid()` → active employee →
  /// `jobs.assigned_employee_id`), applies `status = 'in_progress'` with
  /// database-generated `started_at`/`updated_at`, appends the `job_started`
  /// event — atomically — and returns the updated job row. The call is
  /// idempotent: an already-`in_progress` job comes back unchanged (no
  /// second event, `started_at` untouched), which makes sync retries safe.
  ///
  /// Throws for refused starts (not the assigned employee, unassigned job,
  /// invalid state); the caller decides how to surface that.
  Future<Job> startJob(String jobId);
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

  @override
  Future<JobCustomerInfo?> getJobCustomerInfo(String jobId) async {
    // The RPC returns a row-set with zero or one rows. Zero rows means the
    // caller is not entitled to this job's customer (the function is the
    // authorizer) — surface that as `null`, never as an exception.
    final List<dynamic> rows = await supabase.rpc(
      'get_job_customer',
      params: <String, dynamic>{'p_job_id': jobId},
    );

    if (rows.isEmpty) {
      return null;
    }

    return JobCustomerInfoModel.fromRpcRow(rows.first as Map<String, dynamic>);
  }

  @override
  Future<Job> startJob(String jobId) async {
    // The RPC returns the updated job row (SETOF jobs, exactly one row on
    // success). The client sends ONLY the job id — every timestamp and the
    // event itself are created server-side, so retries and offline replays
    // can never inject or reset a `started_at`.
    final List<dynamic> rows = await supabase.rpc(
      'start_job',
      params: <String, dynamic>{'p_job_id': jobId},
    );

    if (rows.isEmpty) {
      throw StateError('start_job returned no row for job: $jobId');
    }

    return JobModel.fromMap(rows.first as Map<String, dynamic>);
  }
}
