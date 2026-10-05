import 'package:equatable/equatable.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';

/// Lifecycle of a jobs request.
enum JobsStatus { initial, loading, success, failure }

/// Presentation state for [JobsCubit].
///
/// Serves both surfaces that share one cubit contract:
/// * the **list** page reads [jobs],
/// * the **details** page reads [selectedJob].
class JobsState extends Equatable {
  const JobsState({
    this.status = JobsStatus.initial,
    this.jobs = const <Job>[],
    this.selectedJob,
    this.error,
  });

  /// Current lifecycle of the last (or in-flight) request.
  final JobsStatus status;

  /// Jobs list (list page).
  final List<Job> jobs;

  /// Single job (details page), once loaded.
  final Job? selectedJob;

  /// Last error, if [status] is [JobsStatus.failure].
  final Object? error;

  JobsState copyWith({
    JobsStatus? status,
    List<Job>? jobs,
    Job? selectedJob,
    Object? error,
    bool clearError = false,
    bool clearSelectedJob = false,
  }) {
    return JobsState(
      status: status ?? this.status,
      jobs: jobs ?? this.jobs,
      selectedJob:
          clearSelectedJob ? null : (selectedJob ?? this.selectedJob),
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  List<Object?> get props => <Object?>[status, jobs, selectedJob, error];
}
