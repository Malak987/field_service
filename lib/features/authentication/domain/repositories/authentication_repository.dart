import 'package:field_service/features/authentication/domain/entities/account_deletion_preview.dart';
import 'package:field_service/features/authentication/domain/entities/app_user.dart';
import 'package:field_service/features/authentication/domain/entities/auth_session_event.dart';

abstract interface class AuthenticationRepository {
  Future<AppUser> signIn({required String email, required String password});

  /// Registers a new user account.
  ///
  /// Never accepts a role parameter from the client. Role assignment is
  /// strictly controlled by the backend (`employees.role`).
  ///
  /// Returns an [AppUser] when a session and active employee profile are
  /// immediately available, or `null` when email confirmation / administrator
  /// activation is required before signing in.
  Future<AppUser?> signUp({
    required String fullName,
    required String email,
    required String password,
  });

  /// Sends a password recovery link to [email].
  Future<void> sendPasswordResetEmail({required String email});

  /// Updates the authenticated user's password during a recovery session.
  Future<void> updatePassword({required String newPassword});

  /// Runs the non-destructive `delete-account` preview for the current session.
  /// No account or application data is changed by this call.
  Future<AccountDeletionPreview> previewAccountDeletion();

  /// Confirms deletion of the authenticated sign-in account through the
  /// backend-owned workflow. The mobile app must not delete local or backend
  /// records itself.
  Future<void> confirmAccountDeletion();

  Future<AppUser?> getCurrentUser();

  Future<void> signOut();

  /// Clears only this device's persisted authentication session after account
  /// deletion succeeds or the server rejects an invalid session.
  Future<void> clearLocalSession();

  /// Emits domain-level authentication lifecycle changes (including password
  /// recovery deep-link sessions).
  Stream<AuthSessionEvent> watchAuthStateChanges();
}
