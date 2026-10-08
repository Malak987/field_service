import 'package:field_service/features/jobs/data/models/job_customer_info_model.dart';
import 'package:field_service/features/jobs/data/models/job_model.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_customer_info.dart';
import 'package:field_service/features/jobs/domain/repositories/jobs_repository.dart';
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
  Future<void> updateJobStatus({required String jobId, required String status});

  /// Calls the `get_job_customer(job_id)` SECURITY DEFINER RPC and maps the
  /// (at most one) returned row.
  ///
  /// Authorization happens server-side inside the function: it returns zero
  /// rows unless the job is assigned to the caller's active employee (or the
  /// caller is an active admin). This data source never reads
  /// `public.customers` directly — that table remains admin-only in RLS.
  Future<JobCustomerInfo?> getJobCustomerInfo(String jobId);

  /// Calls the `create_job(...)` SECURITY DEFINER RPC — the ONLY write path
  /// for creating and assigning a job (admin action).
  ///
  /// The server verifies that the caller is an active admin, that the
  /// category is one of the two supported values, that the customer exists
  /// and that the assignee is an ACTIVE technician. It generates the
  /// `job_number`, sets `status = 'assigned'`, stamps `assigned_at` /
  /// `created_at` / `updated_at` server-side, appends the `job_created` and
  /// `job_assigned` events, and returns the inserted row. The client sends
  /// NO timestamp.
  ///
  /// Throws for refused creations (non-admin caller, unsupported category,
  /// unknown customer, invalid assignee); the caller decides how to surface
  /// that.
  Future<Job> createJob({
    required String customerId,
    required String jobType,
    String? description,
    required String assignedEmployeeId,
  });

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

  /// Calls the `save_work_description(job_id, work_description)` SECURITY
  /// DEFINER RPC — the ONLY write path for the technician's work
  /// description.
  ///
  /// The server resolves the caller from `auth.uid()` (never from a
  /// client-supplied employee id), requires an active ASSIGNED technician,
  /// requires the job to be `in_progress`, validates and TRIMs the text,
  /// stores it with `updated_at = now()` and appends exactly one
  /// `work_description_added` event per effective change (a replayed save
  /// of the same text succeeds without a second event). Returns the updated
  /// job row.
  ///
  /// Throws for refused saves (admin caller, another technician's job, job
  /// not in progress, invalid text); the caller decides how to surface that.
  Future<Job> saveWorkDescription({
    required String jobId,
    required String workDescription,
  });

  /// Calls the `complete_job(job_id)` SECURITY DEFINER RPC — the ONLY
  /// completion path and the FINAL workflow step.
  ///
  /// The client sends ONLY the job id. The server resolves the caller from
  /// `auth.uid()` (active technician only — admins are refused), requires
  /// the job to be assigned to that technician and `in_progress`, and
  /// re-validates EVERY completion condition itself (before photo, work
  /// description, after photo, customer signature). On success it applies
  /// `status = 'completed'`, the server-generated `completed_at` and
  /// exactly one `job_completed` event atomically and returns the updated
  /// job row; a replayed call observes the completed job and returns it
  /// unchanged (no duplicate event).
  ///
  /// Throws [JobCompletionRejectedException] when the server refuses the
  /// completion (reason mapped from the RPC's error code), so the caller
  /// can explain WHY.
  Future<Job> completeJob(String jobId);
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
      'description, work_description, status, assigned_at, started_at, '
      'completed_at, created_at, updated_at, expires_at, '
      'customers(name), employees(name)';

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
  Future<Job> createJob({
    required String customerId,
    required String jobType,
    String? description,
    required String assignedEmployeeId,
  }) async {
    // The RPC returns the inserted job row (SETOF jobs, exactly one row on
    // success). The client sends only the form facts — every timestamp, the
    // job number and the events are created server-side.
    final List<dynamic> rows = await supabase.rpc(
      'create_job',
      params: <String, dynamic>{
        'p_customer_id': customerId,
        'p_job_type': jobType,
        'p_description': description,
        'p_assigned_employee_id': assignedEmployeeId,
      },
    );

    if (rows.isEmpty) {
      throw StateError('create_job returned no row.');
    }

    return JobModel.fromMap(rows.first as Map<String, dynamic>);
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

  @override
  Future<Job> saveWorkDescription({
    required String jobId,
    required String workDescription,
  }) async {
    // The RPC returns the updated job row (SETOF jobs, exactly one row).
    // The client sends ONLY the job id and the text — the employee identity
    // is resolved server-side from auth.uid() and the authoritative save
    // time is the database's `now()`, never a client value.
    final List<dynamic> rows = await supabase.rpc(
      'save_work_description',
      params: <String, dynamic>{
        'p_job_id': jobId,
        'p_work_description': workDescription,
      },
    );

    if (rows.isEmpty) {
      throw StateError('save_work_description returned no row for job: $jobId');
    }

    return JobModel.fromMap(rows.first as Map<String, dynamic>);
  }

  @override
  Future<Job> completeJob(String jobId) async {
    // The RPC returns the updated job row (SETOF jobs, exactly one row).
    // The client sends ONLY the job id — the server resolves the caller,
    // re-validates every completion condition and generates `completed_at`
    // and the `job_completed` event itself. No identity, no timestamp, no
    // `has_*` flag ever travels with the request.
    try {
      final List<dynamic> rows = await supabase.rpc(
        'complete_job',
        params: <String, dynamic>{'p_job_id': jobId},
      );

      if (rows.isEmpty) {
        throw StateError('complete_job returned no row for job: $jobId');
      }

      return JobModel.fromMap(rows.first as Map<String, dynamic>);
    } on PostgrestException catch (error) {
      // Map the RPC's stable error codes onto the typed domain refusal so
      // the UI can explain WHY the completion was rejected.
      throw JobCompletionRejectedException(
        reason: _completionRejectReason(error.code),
        serverMessage: error.message,
      );
    }
  }

  /// Maps `complete_job` error codes (see `complete_job_setup.sql`) onto
  /// [CompletionRejectReason]. Unknown codes stay [unknown] — a refusal is
  /// never silently treated as success.
  static CompletionRejectReason _completionRejectReason(String? code) {
    return switch (code) {
      _sqlMissingBeforePhoto => CompletionRejectReason.missingBeforePhoto,
      _sqlMissingWorkDescription =>
        CompletionRejectReason.missingWorkDescription,
      _sqlMissingAfterPhoto => CompletionRejectReason.missingAfterPhoto,
      _sqlMissingSignature => CompletionRejectReason.missingSignature,
      _sqlNotAssigned => CompletionRejectReason.notAssigned,
      _sqlInvalidStatus => CompletionRejectReason.invalidStatus,
      _sqlUnauthorizedRole => CompletionRejectReason.unauthorized,
      // No auth session / no active employee — also "not authorized".
      '28000' => CompletionRejectReason.unauthorized,
      _ => CompletionRejectReason.unknown,
    };
  }

  // The RPC's refusal codes — one place, mirrored from the SQL migration.
  static const String _sqlMissingBeforePhoto = 'F0001';
  static const String _sqlMissingWorkDescription = 'F0002';
  static const String _sqlMissingAfterPhoto = 'F0003';
  static const String _sqlMissingSignature = 'F0004';
  static const String _sqlNotAssigned = 'F0005';
  static const String _sqlInvalidStatus = 'F0006';
  static const String _sqlUnauthorizedRole = 'F0007';
}
