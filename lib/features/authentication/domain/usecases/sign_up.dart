import 'package:field_service/features/authentication/domain/entities/app_user.dart';
import 'package:field_service/features/authentication/domain/repositories/authentication_repository.dart';

/// Registers a new employee account without exposing any role selection to the
/// client.
class SignUp {
  const SignUp(this.repository);

  final AuthenticationRepository repository;

  Future<AppUser?> call({
    required String fullName,
    required String email,
    required String password,
  }) {
    return repository.signUp(
      fullName: fullName,
      email: email,
      password: password,
    );
  }
}
