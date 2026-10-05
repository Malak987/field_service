import 'package:field_service/core/utils/logger.dart';
import 'package:field_service/features/authentication/data/datasources/authentication_remote_data_source.dart';
import 'package:field_service/features/authentication/data/models/app_user_model.dart';
import 'package:field_service/features/authentication/domain/entities/app_user.dart';
import 'package:field_service/features/authentication/domain/entities/auth_session_event.dart';
import 'package:field_service/features/authentication/domain/repositories/authentication_repository.dart';
import 'package:field_service/features/authentication/presentation/utils/authentication_error_mapper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthenticationRepositoryImpl implements AuthenticationRepository {
  AuthenticationRepositoryImpl({
    required AuthenticationRemoteDataSource remoteDataSource,
    required SupabaseClient supabase,
  }) : _remoteDataSource = remoteDataSource,
       _supabase = supabase;

  final AuthenticationRemoteDataSource _remoteDataSource;
  final SupabaseClient _supabase;

  @override
  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async {
    final AuthResponse response = await _remoteDataSource.signIn(
      email: email,
      password: password,
    );

    final User? user = response.user;

    if (user == null) {
      throw const AuthException(
        'Invalid login credentials',
        code: 'invalid_credentials',
      );
    }

    return _getAppUser(user);
  }

  @override
  Future<AppUser?> signUp({
    required String fullName,
    required String email,
    required String password,
  }) async {
    final AuthResponse response = await _remoteDataSource.signUp(
      fullName: fullName,
      email: email,
      password: password,
    );

    final User? user = response.user;
    if (user == null) {
      throw const AuthException('Unable to create user account.');
    }

    // Supabase returns a user with an empty identities list when email
    // enumeration protection is active and the email is already registered.
    final List<UserIdentity>? identities = user.identities;
    if (identities != null && identities.isEmpty) {
      throw const AuthException(
        'User already registered',
        code: 'user_already_exists',
      );
    }

    // If email verification is enabled or no session was established yet,
    // registration succeeded and awaits confirmation / admin activation.
    if (response.session == null) {
      return null;
    }

    // When a session exists immediately, check if an active employee record is
    // already linked. If not (e.g. awaiting admin role/profile activation),
    // sign out the temporary session cleanly so the user returns to Sign In.
    try {
      final AppUserModel appUser = await _getAppUser(user);
      return appUser;
    } on AuthException {
      await _safeSignOut();
      return null;
    }
  }

  @override
  Future<void> sendPasswordResetEmail({
    required String email,
  }) {
    return _remoteDataSource.sendPasswordResetEmail(email: email);
  }

  @override
  Future<void> updatePassword({
    required String newPassword,
  }) async {
    final User? user = _remoteDataSource.currentUser;
    if (user == null) {
      throw const AuthException(
        'Recovery session expired.',
        code: AuthenticationErrorMapper.codeRecoveryExpired,
      );
    }

    await _remoteDataSource.updatePassword(newPassword: newPassword);

    // End the temporary password-recovery session so the user returns cleanly
    // to the login screen to sign in with their new password.
    await _safeSignOut();
  }

  @override
  Future<AppUser?> getCurrentUser() async {
    final User? user = _remoteDataSource.currentUser;

    if (user == null) {
      return null;
    }

    return _getAppUser(user);
  }

  @override
  Future<void> signOut() {
    return _remoteDataSource.signOut();
  }

  @override
  Stream<AuthSessionEvent> watchAuthStateChanges() {
    return _remoteDataSource.onAuthStateChange.map((AuthState data) {
      switch (data.event) {
        case AuthChangeEvent.initialSession:
          return AuthSessionEvent.initialSession;
        case AuthChangeEvent.signedIn:
          return AuthSessionEvent.signedIn;
        case AuthChangeEvent.signedOut:
          return AuthSessionEvent.signedOut;
        case AuthChangeEvent.passwordRecovery:
          return AuthSessionEvent.passwordRecovery;
        case AuthChangeEvent.tokenRefreshed:
          return AuthSessionEvent.tokenRefreshed;
        case AuthChangeEvent.userUpdated:
        case AuthChangeEvent.mfaChallengeVerified:
        // ignore: deprecated_member_use
        case AuthChangeEvent.userDeleted:
          return AuthSessionEvent.userUpdated;
      }
    });
  }

  Future<AppUserModel> _getAppUser(User user) async {
    // IMPORTANT: `employees.id` is the employee primary key whereas
    // `employees.auth_user_id` references `auth.users.id`.
    final Map<String, dynamic>? employee = await _supabase
        .from('employees')
        .select(
          'id, auth_user_id, employee_code, name, phone, email, role, is_active',
        )
        .eq('auth_user_id', user.id)
        .maybeSingle();

    if (employee == null) {
      await _safeSignOut();
      throw const AuthException(
        'Employee profile was not found.',
        code: AuthenticationErrorMapper.codeEmployeeNotFound,
      );
    }

    final bool isActive = employee['is_active'] as bool? ?? false;

    if (!isActive) {
      await _safeSignOut();
      throw const AuthException(
        'This employee account is inactive.',
        code: AuthenticationErrorMapper.codeEmployeeInactive,
      );
    }

    final AppUserModel appUser = AppUserModel.fromMap(
      map: employee,
      authUserId: user.id,
      email: user.email ?? '',
    );

    if (!appUser.hasValidRole) {
      await _safeSignOut();
      throw const AuthException(
        'Invalid employee role.',
        code: AuthenticationErrorMapper.codeInvalidRole,
      );
    }

    return appUser;
  }

  Future<void> _safeSignOut() async {
    try {
      await _remoteDataSource.signOut();
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Failed to clear Supabase session after employee validation refusal.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
