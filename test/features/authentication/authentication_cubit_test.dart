import 'dart:async';

import 'package:field_service/features/authentication/domain/entities/app_user.dart';
import 'package:field_service/features/authentication/domain/entities/auth_session_event.dart';
import 'package:field_service/features/authentication/domain/usecases/get_current_user.dart';
import 'package:field_service/features/authentication/domain/usecases/sign_in.dart';
import 'package:field_service/features/authentication/domain/usecases/sign_out.dart';
import 'package:field_service/features/authentication/domain/usecases/watch_auth_state_changes.dart';
import 'package:field_service/features/authentication/presentation/cubit/authentication_cubit.dart';
import 'package:field_service/features/authentication/presentation/cubit/authentication_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_authentication_repository.dart';

void main() {
  late TestAuthenticationRepository repository;
  late AuthenticationCubit cubit;

  setUp(() {
    repository = TestAuthenticationRepository()..currentUser = adminUser;
    cubit = AuthenticationCubit(
      signIn: SignIn(repository),
      signOut: SignOut(repository),
      getCurrentUser: GetCurrentUser(repository),
      watchAuthStateChanges: WatchAuthStateChanges(repository),
    );
  });

  tearDown(() async {
    await cubit.close();
    await repository.dispose();
  });

  test(
    'signOut calls the existing use case/repository and clears user',
    () async {
      await cubit.checkCurrentUser();
      expect(cubit.state.isAuthenticated, isTrue);
      await cubit.signOut();
      expect(repository.signOutCalls, 1);
      expect(repository.currentUser, isNull);
      expect(cubit.state.status, AuthenticationStatus.unauthenticated);
      expect(cubit.state.user, isNull);
    },
  );

  test(
    'successful signOut updates state even if the auth event is delayed',
    () async {
      repository.emitSignOutEvent = false;
      await cubit.checkCurrentUser();
      await cubit.signOut();
      expect(cubit.state.status, AuthenticationStatus.unauthenticated);
      expect(cubit.state.user, isNull);
    },
  );

  test('an out-of-band signedOut event updates the shared state', () async {
    await cubit.checkCurrentUser();
    repository.events.add(AuthSessionEvent.signedOut);
    expect(cubit.state.status, AuthenticationStatus.unauthenticated);
    expect(cubit.state.user, isNull);
  });

  test('late startup lookup cannot undo an explicit logout', () async {
    final lookup = Completer<AppUser?>();
    repository.pendingLookup = lookup.future;
    final restoring = cubit.checkCurrentUser();
    await cubit.signOut();
    lookup.complete(adminUser);
    await restoring;
    expect(cubit.state.status, AuthenticationStatus.unauthenticated);
    expect(cubit.state.user, isNull);
  });

  test('late lookup cannot undo an out-of-band signedOut', () async {
    final lookup = Completer<AppUser?>();
    repository.pendingLookup = lookup.future;
    final restoring = cubit.checkCurrentUser();
    repository.events.add(AuthSessionEvent.signedOut);
    lookup.complete(adminUser);
    await restoring;
    expect(cubit.state.status, AuthenticationStatus.unauthenticated);
    expect(cubit.state.user, isNull);
  });

  test(
    'late form signIn cannot restore a session ended in the meantime',
    () async {
      final login = Completer<AppUser>();
      repository.pendingSignIn = login.future;
      final signingIn = cubit.signIn(email: adminUser.email, password: 'test');
      await cubit.signOut();
      login.complete(adminUser);
      await signingIn;
      expect(cubit.state.status, AuthenticationStatus.unauthenticated);
      expect(cubit.state.user, isNull);
    },
  );

  test('recovery wins over an in-flight employee lookup', () async {
    final lookup = Completer<AppUser?>();
    repository.pendingLookup = lookup.future;
    final restoring = cubit.checkCurrentUser();
    repository.events.add(AuthSessionEvent.passwordRecovery);
    lookup.complete(adminUser);
    await restoring;
    expect(cubit.state.status, AuthenticationStatus.passwordRecovery);
    expect(cubit.state.user, isNull);
  });

  test(
    'double logout calls are coalesced while the real request is pending',
    () async {
      await cubit.checkCurrentUser();
      final pending = Completer<void>();
      repository.pendingSignOut = pending;
      final signingOut = cubit.signOut();
      await cubit.signOut();
      repository.events.add(AuthSessionEvent.signedIn);
      expect(repository.signOutCalls, 1);
      expect(repository.currentUserCalls, 1);
      expect(cubit.state.user, adminUser);
      expect(cubit.state.isLoading, isTrue);
      pending.complete();
      await signingOut;
      expect(cubit.state.status, AuthenticationStatus.unauthenticated);
    },
  );

  test(
    'failed logout retains the authenticated employee for a retry',
    () async {
      await cubit.checkCurrentUser();
      repository.signOutError = StateError('network failure');
      await cubit.signOut();
      expect(cubit.state.status, AuthenticationStatus.failure);
      expect(cubit.state.user, adminUser);
      expect(repository.currentUser, adminUser);
      repository.signOutError = null;
      await cubit.signOut();
      expect(repository.signOutCalls, 2);
      expect(cubit.state.status, AuthenticationStatus.unauthenticated);
    },
  );

  test('disposing the owner ignores a late lookup result', () async {
    final lookup = Completer<AppUser?>();
    repository.pendingLookup = lookup.future;
    final restoring = cubit.checkCurrentUser();
    await cubit.close();
    lookup.complete(adminUser);
    await expectLater(restoring, completes);
  });
}
