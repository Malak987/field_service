import 'package:field_service/features/customers/domain/entities/customer.dart';
import 'package:field_service/features/customers/domain/repositories/customers_repository.dart';

/// Use case: one customer as a live local stream.
///
/// Stream (not a one-shot `Future`) so the details screen re-renders when a
/// local edit or a completed sync push updates the row's sync status —
/// without ever depending on a network round-trip.
class GetCustomerById {
  const GetCustomerById(this._repository);

  final CustomersRepository _repository;

  Stream<Customer?> call(String id) => _repository.watchCustomerById(id);
}
