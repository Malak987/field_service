import 'package:field_service/features/employees/domain/entities/employee.dart';
import 'package:field_service/features/employees/domain/repositories/employees_repository.dart';

/// Use case: the assignee options of the admin Create Job screen.
///
/// Returns exactly the ACTIVE technicians — inactive employees and admins are
/// never selectable. The `create_job` RPC re-validates the choice server-side.
class GetActiveTechnicians {
  const GetActiveTechnicians(this._repository);

  final EmployeesRepository _repository;

  Future<List<Employee>> call() => _repository.getActiveTechnicians();
}
