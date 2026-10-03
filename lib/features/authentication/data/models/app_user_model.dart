import 'package:field_service/features/authentication/domain/entities/app_user.dart';

class AppUserModel extends AppUser {
  const AppUserModel({
    required super.id,
    required super.email,
    required super.role,
    super.employeeId,
  });

  factory AppUserModel.fromMap({
    required Map<String, dynamic> map,
    required String authUserId,
    required String email,
  }) {
    return AppUserModel(
      id: authUserId,
      email: email,
      role: map['role'] as String? ?? 'technician',
      employeeId: map['id'] as String?,
    );
  }
}