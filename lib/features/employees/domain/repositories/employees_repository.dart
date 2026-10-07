import 'package:field_service/features/employees/domain/entities/employee.dart';

/// Domain contract for accessing employee data.
///
/// The app only ever needs the assignee options for the admin Create Job
/// screen, so this contract is intentionally that narrow. Authorization stays
/// server-side: the existing employees RLS decides which rows the caller may
/// see (active admins: all rows), and the `create_job` RPC re-validates the
/// chosen assignee (active technician) regardless of what the client sends.
abstract interface class EmployeesRepository {
  /// The ACTIVE technicians, ordered by name.
  ///
  /// Inactive employees, admins and arbitrary users are never part of the
  /// result — a job can only be assigned to an active technician.
  Future<List<Employee>> getActiveTechnicians();
}
