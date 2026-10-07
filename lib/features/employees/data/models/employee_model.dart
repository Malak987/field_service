import 'package:field_service/features/employees/domain/entities/employee.dart';

/// Data-layer mapping for a `public.employees` row.
///
/// Extends the domain [Employee] (per the existing architecture convention)
/// and provides [fromMap] for PostgREST row maps. The name is mapped exactly
/// as stored — no synthetic names are ever invented here; the entity's
/// `displayName` owns the (logged) fallback for unexpectedly empty rows.
class EmployeeModel extends Employee {
  const EmployeeModel({
    required super.id,
    required super.name,
    required super.role,
    super.employeeCode,
    required super.isActive,
  });

  factory EmployeeModel.fromMap(Map<String, dynamic> map) {
    return EmployeeModel(
      id: map['id'] as String,
      name: map['name'] as String? ?? '',
      role: map['role'] as String? ?? '',
      employeeCode: map['employee_code'] as String?,
      isActive: map['is_active'] as bool? ?? false,
    );
  }
}
