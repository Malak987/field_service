import 'package:field_service/features/jobs/domain/entities/new_customer_draft.dart';
import 'package:field_service/features/jobs/domain/entities/technician_job_creation.dart';
import 'package:field_service/features/jobs/domain/repositories/jobs_repository.dart';

/// Use case: a technician registers a NEW customer and creates a job for
/// them — one logical unit, one server-side transaction.
///
/// The server is authoritative for everything the client must not invent:
/// the assignee (resolved from the caller's own auth identity), the job
/// number, `status = 'assigned'`, every timestamp and the `job_created` /
/// `job_assigned` events.
///
/// [idempotencyKey] identifies the FORM, not the attempt: pass the same key
/// for every retry so the stable job id (and the queued operation) are
/// reused and a lost acknowledgement can never produce a second job.
class CreateTechnicianCustomerAndJob {
  const CreateTechnicianCustomerAndJob(this._repository);

  final JobsRepository _repository;

  Future<TechnicianJobCreation> call({
    required NewCustomerDraft customer,
    required String jobType,
    String? description,
    required String idempotencyKey,
  }) {
    return _repository.createTechnicianCustomerAndJob(
      customer: customer,
      jobType: jobType,
      description: description,
      idempotencyKey: idempotencyKey,
    );
  }
}
