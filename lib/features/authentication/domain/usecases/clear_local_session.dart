import 'package:field_service/features/authentication/domain/repositories/authentication_repository.dart';

/// Clears only this device's persisted Supabase session after the server has
/// deleted the account or rejected an expired session. It never deletes jobs,
/// customers, employee records, files, or other application data.
class ClearLocalSession {
  const ClearLocalSession(this.repository);

  final AuthenticationRepository repository;

  Future<void> call() => repository.clearLocalSession();
}
