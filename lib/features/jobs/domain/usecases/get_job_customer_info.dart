import 'package:field_service/features/jobs/domain/entities/job_customer_info.dart';
import 'package:field_service/features/jobs/domain/repositories/jobs_repository.dart';

/// Use case: the customer information belonging to one specific job.
///
/// The authorization decision lives server-side in the `get_job_customer`
/// SECURITY DEFINER RPC (job must be assigned to the caller's active
/// employee, or the caller must be an active admin). This use case only
/// forwards the job id — there is intentionally no customer-by-id variant,
/// so a caller can never pivot from an arbitrary customer id to data.
class GetJobCustomerInfo {
  const GetJobCustomerInfo(this._repository);

  final JobsRepository _repository;

  Future<JobCustomerInfo?> call(String jobId) =>
      _repository.getJobCustomerInfo(jobId);
}
