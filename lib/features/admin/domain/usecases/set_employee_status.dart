import 'package:field_service/features/admin/domain/entities/admin_account_status.dart';
import 'package:field_service/features/admin/domain/entities/managed_employee.dart';
import 'package:field_service/features/admin/domain/repositories/admin_repository.dart';

/// Use case: block / unblock / soft delete one technician account.
///
/// The three transitions map 1:1 onto `admin_set_employee_status(...)`:
/// [AdminAccountStatus.blocked], [AdminAccountStatus.active] (unblock) and
/// [AdminAccountStatus.deleted] (SOFT delete — the row, its Auth account and
/// its whole work history stay in the database).
class SetEmployeeStatus {
  const SetEmployeeStatus(this._repository);

  final AdminRepository _repository;

  Future<ManagedEmployee> call({
    required String employeeId,
    required AdminAccountStatus status,
  }) => _repository.setEmployeeStatus(employeeId: employeeId, status: status);
}
