import 'dart:async';

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
  int currentUserCalls = 0;
  int signInCalls = 0;
  Object? signOutError;
  Future<AppUser?>? pendingLookup;
  Future<AppUser>? pendingSignIn;
  Completer<void>? pendingSignOut;
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
  Stream<AuthSessionEvent> watchAuthStateChanges() => events.stream;

  Future<void> dispose() => events.close();
}
