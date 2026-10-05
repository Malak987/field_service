import 'package:equatable/equatable.dart';

/// Authenticated domain user entity combining Supabase Auth identity with the
/// authoritative `employees` record.
class AppUser extends Equatable {
  const AppUser({
    required this.id,
    required this.email,
    required this.role,
    this.employeeId,
    this.employeeCode,
    this.name,
    this.phone,
    this.isActive = true,
  });

  /// Supabase Auth user ID (`auth.users.id` / `employees.auth_user_id`).
  final String id;

  /// User's email address.
  final String email;

  /// Authoritative role from `employees.role` (`admin` or `technician`).
  final String role;

  /// Primary key of the employee row (`employees.id`).
  final String? employeeId;

  /// Human-readable employee code (`employees.employee_code`).
  final String? employeeCode;

  /// Full name from `employees.name`.
  final String? name;

  /// Phone number from `employees.phone`.
  final String? phone;

  /// Whether the employee record is active (`employees.is_active`).
  final bool isActive;

  bool get isAdmin => role.toLowerCase() == 'admin';
  bool get isTechnician => role.toLowerCase() == 'technician';
  bool get hasValidRole => isAdmin || isTechnician;

  @override
  List<Object?> get props => <Object?>[
    id,
    email,
    role,
    employeeId,
    employeeCode,
    name,
    phone,
    isActive,
  ];
}
