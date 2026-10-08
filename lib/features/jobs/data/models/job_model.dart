import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_status.dart';

/// Data-layer mapping for a `public.jobs` row.
///
/// Extends the domain [Job] (per the existing architecture convention) and
/// provides [fromMap] for PostgREST row maps.
///
/// The `customers(name)` / `employees(name)` embeds arrive as maps:
/// `{'customers': {'name': '...'}, 'employees': {'name': '...'}}` (each null
/// when there is no matching row).
class JobModel extends Job {
  const JobModel({
    required super.id,
    required super.jobNumber,
    required super.customerId,
    super.customerName,
    super.assignedEmployeeId,
    super.assignedEmployeeName,
    required super.jobType,
    super.description,
    super.workDescription,
    required super.status,
    super.assignedAt,
    super.startedAt,
    super.completedAt,
    required super.createdAt,
    required super.updatedAt,
    required super.expiresAt,
  });

  factory JobModel.fromMap(Map<String, dynamic> map) {
    final customers = map['customers'];
    final employees = map['employees'];

    return JobModel(
      id: map['id'] as String,
      jobNumber: (map['job_number'] as num).toInt(),
      customerId: map['customer_id'] as String,
      customerName: customers is Map<String, dynamic>
          ? customers['name'] as String?
          : null,
      assignedEmployeeId: map['assigned_employee_id'] as String?,
      assignedEmployeeName: employees is Map<String, dynamic>
          ? employees['name'] as String?
          : null,
      jobType: map['job_type'] as String,
      description: map['description'] as String?,
      workDescription: map['work_description'] as String?,
      status: JobStatus(map['status'] as String),
      assignedAt: _parseDate(map['assigned_at']),
      startedAt: _parseDate(map['started_at']),
      completedAt: _parseDate(map['completed_at']),
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      expiresAt: DateTime.parse(map['expires_at'] as String),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.parse(value);
    return null;
  }
}
