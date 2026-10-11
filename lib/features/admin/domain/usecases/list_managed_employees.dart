import 'package:field_service/features/admin/domain/entities/managed_employee.dart';
import 'package:field_service/features/admin/domain/repositories/admin_repository.dart';

/// Use case: the technician management list (admin-only, server-enforced).
class ListManagedEmployees {
  const ListManagedEmployees(this._repository);

  final AdminRepository _repository;

  Future<List<ManagedEmployee>> call() => _repository.listEmployees();
}
