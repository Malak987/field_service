import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/repositories/jobs_repository.dart';

/// Use case: create a job and assign it to a technician in one step — the
/// admin's workflow (Create → Assign → Monitor).
///
/// The server is authoritative for everything the client must not invent:
/// job number, `status = 'assigned'`, the `assigned_at` timestamp and the
/// `job_created` / `job_assigned` events.
class CreateJob {
  const CreateJob(this._repository);

  final JobsRepository _repository;

  Future<Job> call({
    required String customerId,
    required String jobType,
    String? description,
    required String assignedEmployeeId,
  }) {
    return _repository.createJob(
      customerId: customerId,
      jobType: jobType,
      description: description,
      assignedEmployeeId: assignedEmployeeId,
    );
  }
}
