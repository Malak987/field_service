import 'dart:async';

import 'package:field_service/features/authentication/domain/entities/account_deletion_preview.dart';
import 'package:field_service/features/authentication/domain/entities/app_user.dart';
import 'package:field_service/features/authentication/domain/entities/auth_session_event.dart';
import 'package:field_service/features/authentication/domain/repositories/authentication_repository.dart';

const AppUser adminUser = AppUser(
  id: 'auth-admin-1',
  email: 'admin@example.com',
  role: 'admin',
);
const AppUser technicianUser = AppUser(
  id: 'auth-technician-1',
  email: 'technician@example.com',
  role: 'technician',
);

/// Test double only. Production always uses AuthenticationRepositoryImpl.
class TestAuthenticationRepository implements AuthenticationRepository {
  AppUser? currentUser;
  int signOutCalls = 0;
  int clearLocalSessionCalls = 0;
  int currentUserCalls = 0;
  int signInCalls = 0;
  int accountDeletionPreviewCalls = 0;
  int accountDeletionConfirmCalls = 0;
  Object? signOutError;
  Object? accountDeletionPreviewError;
  Object? accountDeletionConfirmError;
  AccountDeletionPreview accountDeletionPreview =
      const AccountDeletionPreview();
  Future<AppUser?>? pendingLookup;
  Future<AppUser>? pendingSignIn;
  Completer<void>? pendingSignOut;
  Completer<void>? pendingAccountDeletionPreview;
  Completer<void>? pendingAccountDeletionConfirm;
  bool emitSignOutEvent = true;

  final StreamController<AuthSessionEvent> events =
      StreamController<AuthSessionEvent>.broadcast(sync: true);

  @override
  Future<AppUser?> getCurrentUser() {
    currentUserCalls++;
    return pendingLookup ?? Future<AppUser?>.value(currentUser);
  }

  @override
  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async {
    signInCalls++;
    if (pendingSignIn != null) {
      return pendingSignIn!;
    }
    currentUser = email == adminUser.email ? adminUser : technicianUser;
    events.add(AuthSessionEvent.signedIn);
    return currentUser!;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    if (pendingSignOut != null) {
      await pendingSignOut!.future;
    }
    if (signOutError != null) {
      throw signOutError!;
    }
    currentUser = null;
    if (emitSignOutEvent) {
      events.add(AuthSessionEvent.signedOut);
    }
  }

  @override
  Future<AppUser?> signUp({
    required String fullName,
    required String email,
    required String password,
  }) async => null;

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {}

  @override
  Future<void> updatePassword({required String newPassword}) async {
    await signOut();
  }

  @override
  Future<AccountDeletionPreview> previewAccountDeletion() async {
    accountDeletionPreviewCalls++;
    if (pendingAccountDeletionPreview != null) {
      await pendingAccountDeletionPreview!.future;
    }
    if (accountDeletionPreviewError != null) {
      throw accountDeletionPreviewError!;
    }
    return accountDeletionPreview;
  }

  @override
  Future<void> confirmAccountDeletion() async {
    accountDeletionConfirmCalls++;
    if (pendingAccountDeletionConfirm != null) {
      await pendingAccountDeletionConfirm!.future;
    }
    if (accountDeletionConfirmError != null) {
      throw accountDeletionConfirmError!;
    }
  }

  @override
  Future<void> clearLocalSession() async {
    clearLocalSessionCalls++;
    currentUser = null;
    if (emitSignOutEvent) {
      events.add(AuthSessionEvent.signedOut);
    }
  }

  @override
  Stream<AuthSessionEvent> watchAuthStateChanges() => events.stream;

  Future<void> dispose() => events.close();
}
