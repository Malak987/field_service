import 'package:field_service/features/authentication/domain/repositories/authentication_repository.dart';

/// Updates the current user's password during a valid recovery session.
class UpdatePassword {
  const UpdatePassword(this.repository);

  final AuthenticationRepository repository;

  Future<void> call({required String newPassword}) {
    return repository.updatePassword(newPassword: newPassword);
  }
}
