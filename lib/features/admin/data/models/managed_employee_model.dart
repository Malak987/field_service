import 'package:field_service/features/admin/domain/entities/admin_account_status.dart';
import 'package:field_service/features/admin/domain/entities/managed_employee.dart';

/// Data-layer mapping of one `admin_list_employees()` /
/// `admin_set_employee_status()` row.
///
/// Server column → entity field:
///
/// | Column           | Field            |
/// |------------------|------------------|
/// | `id`             | [id]             |
/// | `name`           | [name]           |
/// | `employee_code`  | [employeeCode]   |
/// | `email`          | [email]          |
/// | `phone`          | [phone]          |
/// | `role`           | [role]           |
/// | `is_active`      | flag / fallback  |
/// | `account_status` | [status]         |
/// | `blocked_at`     | [blockedAt]      |
/// | `deleted_at`     | [deletedAt]      |
/// | `assigned_jobs`  | [assignedJobs]   |
/// | `completed_jobs` | [completedJobs]  |
class ManagedEmployeeModel extends ManagedEmployee {
  const ManagedEmployeeModel({
    required super.id,
    required super.name,
    required super.role,
    required super.status,
    super.employeeCode,
    super.email,
    super.phone,
    super.blockedAt,
    super.deletedAt,
    super.assignedJobs,
    super.completedJobs,
  });

  factory ManagedEmployeeModel.fromRow(Map<String, dynamic> row) {
    final bool? isActive = row['is_active'] as bool?;

    return ManagedEmployeeModel(
      id: row['id'] as String,
      name: row['name'] as String? ?? '',
      role: row['role'] as String? ?? '',
      employeeCode: row['employee_code'] as String?,
      email: row['email'] as String?,
      phone: row['phone'] as String?,
      status: AdminAccountStatus.fromRemote(
        row['account_status'] as String?,
        isActive: isActive,
      ),
      blockedAt: parseNullableTimestamp(row['blocked_at']),
      deletedAt: parseNullableTimestamp(row['deleted_at']),
      assignedJobs: _parseCount(row['assigned_jobs']),
      completedJobs: _parseCount(row['completed_jobs']),
    );
  }

  static int _parseCount(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }
}

/// PostgREST returns timestamps as ISO-8601 strings; tests/fakes may provide a
/// real [DateTime]. `null` (or a missing column) maps to `null`; anything else
/// is a programming error and must surface instead of corrupting a row.
DateTime? parseNullableTimestamp(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is DateTime) {
    return value;
  }
  if (value is String) {
    final String trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return DateTime.parse(trimmed);
  }
  throw FormatException('Unexpected timestamp value: $value');
}
