import 'package:field_service/features/authentication/domain/entities/app_user.dart';
import 'package:field_service/features/authentication/domain/repositories/authentication_repository.dart';

class SignIn {
  const SignIn(this.repository);

  final AuthenticationRepository repository;

  Future<AppUser> call({
    required String email,
    required String password,
  }) {
    return repository.signIn(
      email: email,
      password: password,
    );
  }
}