import 'package:field_service/features/customers/domain/entities/customer.dart';
import 'package:field_service/features/customers/domain/repositories/customers_repository.dart';

/// Use case: the live local customer list.
///
/// Reads Drift, never the network (offline-first rule); the repository
/// already merged everything the backend knows about.
class GetCustomers {
  const GetCustomers(this._repository);

  final CustomersRepository _repository;

  Stream<List<Customer>> call() => _repository.watchCustomers();
}
