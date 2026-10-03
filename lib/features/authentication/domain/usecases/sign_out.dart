import 'package:field_service/features/authentication/domain/repositories/authentication_repository.dart';

class SignOut {
  const SignOut(this.repository);

  final AuthenticationRepository repository;

  Future<void> call() {
    return repository.signOut();
  }
}