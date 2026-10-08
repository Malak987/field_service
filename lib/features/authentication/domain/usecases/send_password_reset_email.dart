import 'package:field_service/features/authentication/domain/repositories/authentication_repository.dart';

/// Requests a Supabase password recovery email for the given address.
class SendPasswordResetEmail {
  const SendPasswordResetEmail(this.repository);

  final AuthenticationRepository repository;

  Future<void> call({required String email}) {
    return repository.sendPasswordResetEmail(email: email);
  }
}
