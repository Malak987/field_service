import 'package:equatable/equatable.dart';
import 'package:field_service/features/admin/domain/entities/admin_account_status.dart';

/// One employee row as the admin management screen sees it.
///
/// Produced by the `admin_list_employees()` / `admin_set_employee_status()`
/// RPCs (admin-only, enforced server-side). The name is the REAL
/// `employees.name` — no synthetic identity is invented here; [displayName]
/// falls back to the employee code only when the backend row is incomplete,
/// exactly like the existing [Employee] entity of the Employees feature.
class ManagedEmployee extends Equatable {
  const ManagedEmployee({
    required this.id,
    required this.name,
    required this.role,
    required this.status,
    this.employeeCode,
    this.email,
    this.phone,
    this.blockedAt,
    this.deletedAt,
    this.assignedJobs = 0,
    this.completedJobs = 0,
  });

  /// `employees.id` (uuid) — the id every management RPC takes.
  final String id;

  /// `employees.name` — the authoritative display name.
  final String name;

  /// `employees.role` — `admin` or `technician`.
  final String role;

  /// Derived lifecycle state (`account_status`, with `is_active` as fallback).
  final AdminAccountStatus status;

  /// `employees.employee_code`, when present.
  final String? employeeCode;

  /// `employees.email`.
  final String? email;

  /// `employees.phone`.
  final String? phone;

  /// When the account was blocked (server timestamp).
  final DateTime? blockedAt;

  /// When the account was soft deleted (server timestamp).
  final DateTime? deletedAt;

  /// `COUNT(jobs)` currently assigned to this employee (history included).
  final int assignedJobs;

  /// Of those, how many are `completed`.
  final int completedJobs;

  bool get isTechnician => role.toLowerCase() == 'technician';
  bool get isAdmin => role.toLowerCase() == 'admin';
  bool get isDeleted => status.isDeleted;
  bool get isBlocked => status.isBlocked;
  bool get isActive => status.isActive;

  /// Whether this row may be blocked / unblocked / soft deleted at all.
  ///
  /// Technicians only (“administrator accounts are deliberately out of scope”
  /// in the migration) and never a soft deleted, already-deleted row.
  bool get isManageable => isTechnician && !isDeleted;

  /// Blocking is offered for an active technician.
  bool get canBeBlocked => isManageable && !isBlocked;

  /// Unblocking is offered for a blocked technician that is NOT deleted
  /// (a soft deleted technician is never reactivated — server-enforced too).
  bool get canBeReactivated => isManageable && isBlocked;

  /// Soft deleting is offered while the technician is not deleted yet.
  bool get canBeDeleted => isManageable;

  /// `employees.name` exactly as stored, or the employee code / id when the
  /// row is unexpectedly incomplete (never an invented human name).
  String get displayName {
    final String trimmed = name.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
    final String code = employeeCode?.trim() ?? '';
    return code.isNotEmpty ? code : id;
  }

  ManagedEmployee copyWith({
    String? name,
    String? role,
    AdminAccountStatus? status,
    String? employeeCode,
    String? email,
    String? phone,
    DateTime? blockedAt,
    DateTime? deletedAt,
    int? assignedJobs,
    int? completedJobs,
  }) {
    return ManagedEmployee(
      id: id,
      name: name ?? this.name,
      role: role ?? this.role,
      status: status ?? this.status,
      employeeCode: employeeCode ?? this.employeeCode,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      blockedAt: blockedAt ?? this.blockedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      assignedJobs: assignedJobs ?? this.assignedJobs,
      completedJobs: completedJobs ?? this.completedJobs,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    id,
    name,
    role,
    status,
    employeeCode,
    email,
    phone,
    blockedAt,
    deletedAt,
    assignedJobs,
    completedJobs,
  ];
}
