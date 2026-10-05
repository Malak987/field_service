import 'package:field_service/features/authentication/domain/entities/auth_session_event.dart';
import 'package:field_service/features/authentication/domain/repositories/authentication_repository.dart';

/// Observes authentication lifecycle events such as password recovery deep links.
class WatchAuthStateChanges {
  const WatchAuthStateChanges(this.repository);

  final AuthenticationRepository repository;

  Stream<AuthSessionEvent> call() {
    return repository.watchAuthStateChanges();
  }
}
