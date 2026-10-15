import 'package:field_service/features/authentication/domain/entities/account_deletion_preview.dart';
import 'package:field_service/features/authentication/domain/repositories/authentication_repository.dart';

/// Coordinates the two explicit account-deletion calls owned by the backend.
///
/// A preview is always non-destructive. The confirm call is available only to
/// presentation code after the user has reviewed that preview and confirms.
class RequestAccountDeletion {
  const RequestAccountDeletion(this.repository);

  final AuthenticationRepository repository;

  Future<AccountDeletionPreview> preview() =>
      repository.previewAccountDeletion();

  Future<void> confirm() => repository.confirmAccountDeletion();
}
