import 'package:field_service/features/authentication/domain/entities/app_user.dart';

class AppUserModel extends AppUser {
  const AppUserModel({
    required super.id,
    required super.email,
    required super.role,
    super.employeeId,
    super.employeeCode,
    super.name,
    super.phone,
    super.isActive = true,
  });

  factory AppUserModel.fromMap({
    required Map<String, dynamic> map,
    required String authUserId,
    required String email,
  }) {
    final String rawRole = (map['role'] as String? ?? '').trim().toLowerCase();
    final String resolvedEmail = email.isNotEmpty
        ? email
        : (map['email'] as String? ?? '');

    return AppUserModel(
      id: authUserId,
      email: resolvedEmail,
      role: rawRole,
      employeeId: map['id'] as String?,
      employeeCode: map['employee_code'] as String?,
      name: map['name'] as String?,
      phone: map['phone'] as String?,
      isActive: map['is_active'] as bool? ?? false,
    );
  }
}
