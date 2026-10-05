import 'package:field_service/features/customers/domain/entities/customer.dart';
import 'package:field_service/features/customers/domain/repositories/customers_repository.dart';

/// Use case: update a customer (local write + queued `update` operation).
class UpdateCustomer {
  const UpdateCustomer(this._repository);

  final CustomersRepository _repository;

  Future<void> call(Customer customer) =>
      _repository.updateCustomer(customer);
}
