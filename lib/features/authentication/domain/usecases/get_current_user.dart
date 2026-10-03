import 'package:field_service/features/authentication/domain/entities/app_user.dart';
import 'package:field_service/features/authentication/domain/repositories/authentication_repository.dart';

class GetCurrentUser {
  const GetCurrentUser(this.repository);

  final AuthenticationRepository repository;

  Future<AppUser?> call() {
    return repository.getCurrentUser();
  }
}