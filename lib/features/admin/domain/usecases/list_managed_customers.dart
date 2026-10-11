import 'package:field_service/features/admin/domain/entities/managed_customer.dart';
import 'package:field_service/features/admin/domain/repositories/admin_repository.dart';

/// Use case: the customer management list (admin-only, server-enforced).
class ListManagedCustomers {
  const ListManagedCustomers(this._repository);

  final AdminRepository _repository;

  Future<List<ManagedCustomer>> call({String? search}) =>
      _repository.listCustomers(search: search);
}
