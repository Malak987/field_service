import 'package:field_service/features/authentication/domain/entities/app_user.dart';

abstract interface class AuthenticationRepository {
  Future<AppUser> signIn({
    required String email,
    required String password,
  });

  Future<AppUser?> getCurrentUser();

  Future<void> signOut();
}