import 'package:equatable/equatable.dart';
import 'package:field_service/features/jobs/domain/entities/job_status.dart';

/// Domain entity representing a row in `public.jobs`.
///
/// Fields map 1:1 to the real database columns (no invented columns):
///
/// | Entity field            | Column                 |
/// |-------------------------|------------------------|
/// | [id]                    | `id` (uuid)            |
/// | [jobNumber]             | `job_number` (bigint)  |
/// | [customerId]            | `customer_id` (uuid)   |
/// | [customerName]          | join → `customers.name`|
/// | [assignedEmployeeId]    | `assigned_employee_id` |
/// | [assignedEmployeeName]  | join → `employees.name`|
/// | [jobType]               | `job_type` (text)      |
/// | [description]           | `description` (text)   |
/// | [status]                | `status` (text)        |
/// | [assignedAt]            | `assigned_at`          |
/// | [startedAt]             | `started_at`           |
/// | [completedAt]           | `completed_at`         |
/// | [createdAt]             | `created_at`           |
/// | [updatedAt]             | `updated_at`           |
/// | [expiresAt]             | `expires_at`           |
///
/// [customerName] and [assignedEmployeeName] are denormalized display values
/// resolved by the Data layer (via the PostgREST `customers(name)` /
/// `employees(name)` embeds). They are `null` when the join yields nothing.
class Job extends Equatable {
  const Job({
    required this.id,
    required this.jobNumber,
    required this.customerId,
    this.customerName,
    this.assignedEmployeeId,
    this.assignedEmployeeName,
    required this.jobType,
    this.description,
    required this.status,
    this.assignedAt,
    this.startedAt,
    this.completedAt,
    required this.createdAt,
    required this.updatedAt,
    required this.expiresAt,
  });

  /// `jobs.id`
  final String id;

  /// `jobs.job_number` (bigint → int).
  final int jobNumber;

  /// `jobs.customer_id` (FK → `customers.id`).
  final String customerId;

  /// `customers.name` for the joined customer (display only, may be null).
  final String? customerName;

  /// `jobs.assigned_employee_id` (FK → `employees.id`), nullable.
  final String? assignedEmployeeId;

  /// `employees.name` for the assigned technician (display only, may be null).
  final String? assignedEmployeeName;

  /// `jobs.job_type` (free text).
  final String jobType;

  /// `jobs.description` (free text), nullable.
  final String? description;

  /// `jobs.status` wrapped in a flexible [JobStatus].
  final JobStatus status;

  /// `jobs.assigned_at`, nullable.
  final DateTime? assignedAt;

  /// `jobs.started_at`, nullable.
  final DateTime? startedAt;

  /// `jobs.completed_at`, nullable.
  final DateTime? completedAt;

  /// `jobs.created_at`.
  final DateTime createdAt;

  /// `jobs.updated_at`.
  final DateTime updatedAt;

  /// `jobs.expires_at`.
  final DateTime expiresAt;

  Job copyWith({
    String? id,
    int? jobNumber,
    String? customerId,
    String? customerName,
    String? assignedEmployeeId,
    String? assignedEmployeeName,
    String? jobType,
    String? description,
    JobStatus? status,
    DateTime? assignedAt,
    DateTime? startedAt,
    DateTime? completedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? expiresAt,
  }) {
    return Job(
      id: id ?? this.id,
      jobNumber: jobNumber ?? this.jobNumber,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      assignedEmployeeId: assignedEmployeeId ?? this.assignedEmployeeId,
      assignedEmployeeName: assignedEmployeeName ?? this.assignedEmployeeName,
      jobType: jobType ?? this.jobType,
      description: description ?? this.description,
      status: status ?? this.status,
      assignedAt: assignedAt ?? this.assignedAt,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    id,
    jobNumber,
    customerId,
    customerName,
    assignedEmployeeId,
    assignedEmployeeName,
    jobType,
    description,
    status,
    assignedAt,
    startedAt,
    completedAt,
    createdAt,
    updatedAt,
    expiresAt,
  ];
}
