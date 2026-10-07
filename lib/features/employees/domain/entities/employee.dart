import 'package:equatable/equatable.dart';

/// Domain entity representing a row in `public.employees`.
///
/// Only the fields the app actually needs are mapped; the authoritative row
/// stays in Supabase (`public.employees` is the single source of truth for
/// employee identities — the UI never invents or hardcodes names).
/// Visibility is enforced by the existing employees RLS: an active admin can
/// read all employee rows, any other user only their own — so the technician
/// selector (admin-only Create Job screen) resolves server-side to exactly
/// the rows the admin is entitled to see.
class Employee extends Equatable {
  const Employee({
    required this.id,
    required this.name,
    required this.role,
    this.employeeCode,
    this.isActive = true,
  });

  /// `employees.id` (uuid).
  final String id;

  /// `employees.name` — the authoritative display name.
  final String name;

  /// `employees.role` — `admin` or `technician`.
  final String role;

  /// `employees.employee_code` (e.g. `TECH-001`), when present.
  final String? employeeCode;

  /// `employees.is_active`.
  final bool isActive;

  bool get isTechnician => role.toLowerCase() == 'technician';
  bool get isAdmin => role.toLowerCase() == 'admin';

  /// Whether [name] is missing/empty — a data problem the backend should
  /// fix, surfaced (not hidden) by [displayName] falling back to the code.
  bool get hasMissingName => name.trim().isEmpty;

  /// The label shown in the UI: `employees.name` exactly as stored.
  ///
  /// Only when a row unexpectedly has an empty/null name does this fall back
  /// to the stable `employee_code` (e.g. `TECH-001`) — never an invented
  /// human name. The fallback condition is logged where the options are
  /// loaded, so the underlying data problem stays visible.
  String get displayName {
    final String trimmedName = name.trim();
    if (trimmedName.isNotEmpty) {
      return trimmedName;
    }
    final String trimmedCode = employeeCode?.trim() ?? '';
    return trimmedCode.isNotEmpty ? trimmedCode : id;
  }

  @override
  List<Object?> get props => <Object?>[
    id,
    name,
    role,
    employeeCode,
    isActive,
  ];
}
