import 'package:field_service/features/employees/data/models/employee_model.dart';
import 'package:field_service/features/employees/domain/entities/employee.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Remote data source contract for the `public.employees` table.
///
/// Visibility is enforced entirely by the **existing employees RLS**:
/// active admins read all rows, every other user only their own. The data
/// source therefore issues plain filtered queries and never re-implements
/// authorization on the client.
abstract interface class EmployeesRemoteDataSource {
  /// All ACTIVE technicians, ordered by name — the assignee options of the
  /// admin Create Job screen. Inactive employees and admins are filtered out
  /// server-side by the query; RLS additionally scopes who may run it at all.
  Future<List<Employee>> getActiveTechnicians();
}

class EmployeesRemoteDataSourceImpl implements EmployeesRemoteDataSource {
  EmployeesRemoteDataSourceImpl(this.supabase);

  final SupabaseClient supabase;

  @override
  Future<List<Employee>> getActiveTechnicians() async {
    // NB: postgrest-dart `.order()` defaults to DESCENDING — pass
    // `ascending: true` explicitly for a name A→Z list.
    final List<Map<String, dynamic>> rows = await supabase
        .from('employees')
        .select('id, name, employee_code, role, is_active')
        .eq('is_active', true)
        .eq('role', 'technician')
        .order('name', ascending: true);

    return rows.map(EmployeeModel.fromMap).toList();
  }
}
