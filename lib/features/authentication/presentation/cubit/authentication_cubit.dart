import 'dart:async';

import 'package:field_service/core/utils/logger.dart';
import 'package:field_service/features/authentication/domain/entities/app_user.dart';
import 'package:field_service/features/authentication/domain/entities/auth_session_event.dart';
import 'package:field_service/features/authentication/domain/usecases/get_current_user.dart';
import 'package:field_service/features/authentication/domain/usecases/send_password_reset_email.dart';
import 'package:field_service/features/authentication/domain/usecases/sign_in.dart';
import 'package:field_service/features/authentication/domain/usecases/sign_out.dart';
import 'package:field_service/features/authentication/domain/usecases/sign_up.dart';
import 'package:field_service/features/authentication/domain/usecases/update_password.dart';
import 'package:field_service/features/authentication/domain/usecases/watch_auth_state_changes.dart';
import 'package:field_service/features/authentication/presentation/cubit/authentication_state.dart';
import 'package:field_service/features/authentication/presentation/utils/authentication_error_mapper.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class AuthenticationCubit extends Cubit<AuthenticationState> {
  AuthenticationCubit({
    required this._signIn,
    required this._signOut,
    required this._getCurrentUser,
    this._signUp,
    this._sendPasswordResetEmail,
    this._updatePassword,
    WatchAuthStateChanges? watchAuthStateChanges,
  }) : super(const AuthenticationState()) {
    if (watchAuthStateChanges != null) {
      _authSubscription = watchAuthStateChanges().listen(
        _onAuthSessionEvent,
        onError: (Object error, StackTrace stackTrace) {
          AppLogger.warning(
            'Auth state stream emitted an error.',
            error: error,
            stackTrace: stackTrace,
          );
        },
      );
    }
  }

  final SignIn _signIn;
  final SignOut _signOut;
  final GetCurrentUser _getCurrentUser;
  final SignUp? _signUp;
  final SendPasswordResetEmail? _sendPasswordResetEmail;
  final UpdatePassword? _updatePassword;

  StreamSubscription<AuthSessionEvent>? _authSubscription;

  // Invalidate in-flight employee lookups when the session ends. Otherwise a
  // slow startup/signedIn lookup can emit authenticated *after* signedOut.
  int _sessionRevision = 0;
  bool _signOutInProgress = false;

  void _onAuthSessionEvent(AuthSessionEvent event) {
    if (isClosed) {
      return;
    }

    switch (event) {
      case AuthSessionEvent.passwordRecovery:
        _sessionRevision++;
        // Supabase only emits this after the recovery deep link has been
        // exchanged for a real session, so this is the safe moment to show the
        // "set a new password" screen. Navigating earlier (e.g. on the raw
        // incoming URI) would violate the "only after the session exists" rule.
        emit(
          state.copyWith(
            status: AuthenticationStatus.passwordRecovery,
            clearUser: true,
            clearErrorCode: true,
            clearMessage: true,
          ),
        );
        break;

      case AuthSessionEvent.signedIn:
        // Re-resolve the current user. This is what makes a **cold-start email
        // confirmation** work: the session only exists once the OS deep link
        // has been exchanged, which can happen *after* the startup check already
        // resolved to `unauthenticated`.
        //
        // We skip this when we already hold a user (a normal form login already
        // emitted `authenticated`) and never while a password recovery is in
        // progress, so a recovery is never turned into a full sign-in.
        if (!_signOutInProgress &&
            !state.isAuthenticated &&
            state.status != AuthenticationStatus.passwordRecovery) {
          unawaited(checkCurrentUser());
        }
        break;

      case AuthSessionEvent.signedOut:
        _sessionRevision++;
        // Session dropped out of band (expired on another device, etc.).
        emit(
          state.copyWith(
            status: AuthenticationStatus.unauthenticated,
            clearUser: true,
            clearErrorCode: true,
            clearMessage: true,
          ),
        );
        break;

      case AuthSessionEvent.initialSession:
      case AuthSessionEvent.tokenRefreshed:
      case AuthSessionEvent.userUpdated:
        // No presentation change required.
        break;
    }
  }

  Future<void> checkCurrentUser() async {
    // Do not interrupt an active password-recovery flow initiated by a deep link.
    if (isClosed ||
        _signOutInProgress ||
        state.status == AuthenticationStatus.passwordRecovery) {
      return;
    }
    final int sessionRevision = _sessionRevision;

    emit(
      state.copyWith(
        status: AuthenticationStatus.loading,
        clearErrorCode: true,
        clearMessage: true,
      ),
    );

    try {
      final AppUser? user = await _getCurrentUser();

      // If a password-recovery deep link arrived while the employee lookup was
      // in flight, never clobber the recovery state with a normal session
      // state (recovery must stay in the foreground until the password is set).
      if (isClosed ||
          sessionRevision != _sessionRevision ||
          state.status == AuthenticationStatus.passwordRecovery) {
        return;
      }

      if (user == null) {
        emit(
          state.copyWith(
            status: AuthenticationStatus.unauthenticated,
            clearUser: true,
            clearErrorCode: true,
            clearMessage: true,
          ),
        );
        return;
      }

      emit(
        state.copyWith(
          status: AuthenticationStatus.authenticated,
          user: user,
          clearErrorCode: true,
          clearMessage: true,
        ),
      );
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Failed to restore authenticated employee session.',
        error: error,
        stackTrace: stackTrace,
      );
      // Same guard as above: a late-arriving recovery must win over the
      // employee-lookup failure.
      if (isClosed ||
          _signOutInProgress ||
          state.status == AuthenticationStatus.passwordRecovery) {
        return;
      }
      _emitFailure(error, clearUser: true);
    }
  }

  Future<void> signIn({required String email, required String password}) async {
    if (isClosed || _signOutInProgress) {
      return;
    }
    final int sessionRevision = _sessionRevision;
    emit(
      state.copyWith(
        status: AuthenticationStatus.loading,
        clearErrorCode: true,
        clearMessage: true,
      ),
    );

    try {
      final AppUser user = await _signIn(email: email, password: password);

      if (isClosed ||
          sessionRevision != _sessionRevision ||
          state.status == AuthenticationStatus.passwordRecovery) {
        return;
      }

      emit(
        state.copyWith(
          status: AuthenticationStatus.authenticated,
          user: user,
          clearErrorCode: true,
          clearMessage: true,
        ),
      );
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Sign-in attempt failed.',
        error: error,
        stackTrace: stackTrace,
      );
      _emitFailure(error, clearUser: true);
    }
  }

  Future<void> signUp({
    required String fullName,
    required String email,
    required String password,
  }) async {
    final SignUp? signUpUseCase = _signUp;
    if (signUpUseCase == null) {
      _emitFailure(AuthErrorCode.unexpected, clearUser: true);
      return;
    }

    emit(
      state.copyWith(
        status: AuthenticationStatus.loading,
        clearErrorCode: true,
        clearMessage: true,
      ),
    );

    try {
      final AppUser? user = await signUpUseCase(
        fullName: fullName,
        email: email,
        password: password,
      );

      if (user != null) {
        emit(
          state.copyWith(
            status: AuthenticationStatus.authenticated,
            user: user,
            clearErrorCode: true,
            clearMessage: true,
          ),
        );
      } else {
        emit(
          state.copyWith(
            status: AuthenticationStatus.registrationSuccess,
            clearUser: true,
            clearErrorCode: true,
            clearMessage: true,
          ),
        );
      }
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Registration attempt failed.',
        error: error,
        stackTrace: stackTrace,
      );
      _emitFailure(error, clearUser: true);
    }
  }

  Future<void> sendPasswordResetEmail({required String email}) async {
    final SendPasswordResetEmail? useCase = _sendPasswordResetEmail;
    if (useCase == null) {
      _emitFailure(AuthErrorCode.unexpected);
      return;
    }

    emit(
      state.copyWith(
        status: AuthenticationStatus.loading,
        clearErrorCode: true,
        clearMessage: true,
      ),
    );

    try {
      await useCase(email: email);

      emit(
        state.copyWith(
          status: AuthenticationStatus.passwordResetEmailSent,
          clearErrorCode: true,
          clearMessage: true,
        ),
      );
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Password reset email request failed.',
        error: error,
        stackTrace: stackTrace,
      );
      _emitFailure(error);
    }
  }

  Future<void> updatePassword({required String newPassword}) async {
    final UpdatePassword? useCase = _updatePassword;
    if (useCase == null) {
      _emitFailure(AuthErrorCode.unexpected);
      return;
    }

    emit(
      state.copyWith(
        status: AuthenticationStatus.loading,
        clearErrorCode: true,
        clearMessage: true,
      ),
    );

    try {
      await useCase(newPassword: newPassword);

      emit(
        state.copyWith(
          status: AuthenticationStatus.passwordResetSuccess,
          clearUser: true,
          clearErrorCode: true,
          clearMessage: true,
        ),
      );
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Password update failed.',
        error: error,
        stackTrace: stackTrace,
      );
      _emitFailure(error);
    }
  }

  Future<void> signOut() async {
    if (isClosed || _signOutInProgress) {
      return;
    }
    _signOutInProgress = true;
    _sessionRevision++;
    emit(
      state.copyWith(
        status: AuthenticationStatus.loading,
        clearErrorCode: true,
        clearMessage: true,
      ),
    );

    try {
      await _signOut();
      if (isClosed) {
        return;
      }

      emit(
        state.copyWith(
          status: AuthenticationStatus.unauthenticated,
          clearUser: true,
          clearErrorCode: true,
          clearMessage: true,
        ),
      );
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Sign-out failed.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!isClosed) {
        _emitFailure(error);
      }
    } finally {
      _signOutInProgress = false;
    }
  }

  /// Clears transient error or success banners when switching between
  /// unauthenticated screens (e.g. Login ↔ Register ↔ Forgot Password).
  void clearFeedback() {
    if (state.status == AuthenticationStatus.failure ||
        state.status == AuthenticationStatus.passwordResetEmailSent ||
        state.status == AuthenticationStatus.passwordResetSuccess ||
        state.status == AuthenticationStatus.registrationSuccess) {
      emit(
        state.copyWith(
          status: AuthenticationStatus.unauthenticated,
          clearErrorCode: true,
          clearMessage: true,
        ),
      );
    }
  }

  /// Explicitly places the cubit in password recovery mode when `/reset-password`
  /// is opened.
  void enterPasswordRecoveryMode() {
    if (state.status != AuthenticationStatus.passwordRecovery) {
      emit(
        state.copyWith(
          status: AuthenticationStatus.passwordRecovery,
          clearErrorCode: true,
          clearMessage: true,
        ),
      );
    }
  }

  void _emitFailure(Object error, {bool clearUser = false}) {
    final AuthErrorCode code = AuthenticationErrorMapper.mapErrorToCode(error);
    final String safeMessage = AuthenticationErrorMapper.toFallbackMessage(
      error,
    );

    emit(
      state.copyWith(
        status: AuthenticationStatus.failure,
        errorCode: code,
        message: safeMessage,
        clearUser: clearUser,
      ),
    );
  }

  @override
  Future<void> close() async {
    _sessionRevision++;
    await _authSubscription?.cancel();
    return super.close();
  }
}
