import 'package:field_service/core/utils/logger.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_status.dart';
import 'package:field_service/features/jobs/domain/usecases/get_job_by_id.dart';
import 'package:field_service/features/jobs/domain/usecases/get_jobs.dart';
import 'package:field_service/features/jobs/domain/usecases/update_job_status.dart';
import 'package:field_service/features/jobs/presentation/cubit/jobs_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Presentation state for the Jobs feature.
///
/// Registered as a **factory** in the DI container: the list page and each
/// details page own their own instance. All data access goes through use
/// cases — there are no Supabase calls in this layer.
class JobsCubit extends Cubit<JobsState> {
  JobsCubit({
    required this._getJobs,
    required this._getJobById,
    required this._updateJobStatus,
  }) : super(const JobsState());

  final GetJobs _getJobs;
  final GetJobById _getJobById;
  final UpdateJobStatus _updateJobStatus;

  /// Loads the jobs visible to the current user.
  ///
  /// RLS on `public.jobs` already scopes the result: technicians receive only
  /// their own assignments, admins receive all jobs. No role branching here.
  Future<void> loadJobs() async {
    emit(state.copyWith(status: JobsStatus.loading, clearError: true));

    try {
      final List<Job> jobs = await _getJobs();
      emit(state.copyWith(status: JobsStatus.success, jobs: jobs));
    } catch (error, stackTrace) {
      AppLogger.warning('Failed to load jobs.', error: error, stackTrace: stackTrace);
      emit(
        state.copyWith(status: JobsStatus.failure, error: error),
      );
    }
  }

  /// Loads a single job by [id] into [JobsState.selectedJob].
  Future<void> loadJobById(String id) async {
    emit(
      state.copyWith(
        status: JobsStatus.loading,
        clearError: true,
        clearSelectedJob: true,
      ),
    );

    try {
      final Job job = await _getJobById(id);
      emit(
        state.copyWith(
          status: JobsStatus.success,
          selectedJob: job,
          clearError: true,
        ),
      );
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Failed to load job details.',
        error: error,
        stackTrace: stackTrace,
      );
      emit(
        state.copyWith(status: JobsStatus.failure, error: error),
      );
    }
  }

  /// Updates the status of the job with [jobId] to [status].
  ///
  /// On success the loaded job (list and/or details) is updated in place so
  /// the UI reflects the new status without a full reload.
  Future<void> updateJobStatus({
    required String jobId,
    required String status,
  }) async {
    try {
      await _updateJobStatus(jobId: jobId, status: status);
      _applyStatusUpdate(jobId, status);
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Failed to update job status.',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  void _applyStatusUpdate(String jobId, String status) {
    final Job? selectedJob = state.selectedJob;
    if (selectedJob != null && selectedJob.id == jobId) {
      final Job updated = selectedJob.copyWith(
        status: JobStatus(status),
        updatedAt: DateTime.now().toUtc(),
      );
      emit(
        state.copyWith(
          selectedJob: updated,
          jobs: _replaceJob(state.jobs, updated),
        ),
      );
      return;
    }

    emit(
      state.copyWith(
        jobs: _mapStatus(state.jobs, jobId, status),
      ),
    );
  }

  static List<Job> _replaceJob(List<Job> jobs, Job replacement) {
    return jobs
        .map((Job job) => job.id == replacement.id ? replacement : job)
        .toList();
  }

  static List<Job> _mapStatus(List<Job> jobs, String jobId, String status) {
    return jobs.map((Job job) {
      return job.id == jobId
          ? job.copyWith(
              status: JobStatus(status),
              updatedAt: DateTime.now().toUtc(),
            )
          : job;
    }).toList();
  }
}
