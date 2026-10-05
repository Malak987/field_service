import 'package:field_service/features/authentication/domain/entities/app_user.dart';
import 'package:field_service/features/authentication/domain/entities/auth_session_event.dart';

abstract interface class AuthenticationRepository {
  Future<AppUser> signIn({
    required String email,
    required String password,
  });

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
  Future<void> sendPasswordResetEmail({
    required String email,
  });

  /// Updates the authenticated user's password during a recovery session.
  Future<void> updatePassword({
    required String newPassword,
  });

  Future<AppUser?> getCurrentUser();

  Future<void> signOut();

  /// Emits domain-level authentication lifecycle changes (including password
  /// recovery deep-link sessions).
  Stream<AuthSessionEvent> watchAuthStateChanges();
}
