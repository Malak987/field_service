import 'package:field_service/features/jobs/domain/entities/technician_job_creation.dart';
import 'package:field_service/features/jobs/domain/repositories/jobs_repository.dart';

/// Use case: a technician creates a job for an EXISTING customer.
///
/// Access is decided by the server, never by the UI: the
/// `technician_create_job_for_customer` RPC refuses (42501) any customer
/// that is not already linked to one of the caller's own jobs, so a job can
/// never be attached to a customer this technician may not work for.
///
/// [idempotencyKey] identifies the FORM (see
/// [CreateTechnicianCustomerAndJob]) so retries reuse the stable job id.
class CreateTechnicianJobForCustomer {
  const CreateTechnicianJobForCustomer(this._repository);

  final JobsRepository _repository;

  Future<TechnicianJobCreation> call({
    required String customerId,
    required String jobType,
    String? description,
    required String idempotencyKey,
  }) {
    return _repository.createTechnicianJobForCustomer(
      customerId: customerId,
      jobType: jobType,
      description: description,
      idempotencyKey: idempotencyKey,
    );
  }
}
