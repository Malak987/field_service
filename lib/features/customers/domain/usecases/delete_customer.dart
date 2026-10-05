import 'package:field_service/features/customers/domain/repositories/customers_repository.dart';

/// Use case: delete a customer (local removal + queued `delete` operation).
///
/// Throws [CustomerLinkedToJobsException] when local jobs reference the
/// customer; the remote FK constraint remains the final protection for jobs
/// the device does not know about yet.
class DeleteCustomer {
  const DeleteCustomer(this._repository);

  final CustomersRepository _repository;

  Future<void> call(String id) => _repository.deleteCustomer(id);
}
