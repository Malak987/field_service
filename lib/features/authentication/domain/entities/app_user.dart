import 'package:equatable/equatable.dart';

class AppUser extends Equatable {
  const AppUser({
    required this.id,
    required this.email,
    required this.role,
    this.employeeId,
  });

  final String id;
  final String email;
  final String role;
  final String? employeeId;

  bool get isAdmin => role == 'admin';
  bool get isTechnician => role == 'technician';

  @override
  List<Object?> get props => [
    id,
    email,
    role,
    employeeId,
  ];
}