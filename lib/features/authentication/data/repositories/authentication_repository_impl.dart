import 'dart:convert';

import 'package:field_service/core/utils/logger.dart';
import 'package:field_service/features/authentication/data/datasources/authentication_remote_data_source.dart';
import 'package:field_service/features/authentication/data/models/app_user_model.dart';
import 'package:field_service/features/authentication/domain/entities/account_deletion_failure.dart';
import 'package:field_service/features/authentication/domain/entities/account_deletion_preview.dart';
import 'package:field_service/features/authentication/domain/entities/app_user.dart';
import 'package:field_service/features/authentication/domain/entities/auth_session_event.dart';
import 'package:field_service/features/authentication/domain/repositories/authentication_repository.dart';
import 'package:field_service/features/authentication/presentation/utils/authentication_error_mapper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthenticationRepositoryImpl implements AuthenticationRepository {
  AuthenticationRepositoryImpl({
    required this._remoteDataSource,
    required this._supabase,
  });

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
  Future<void> sendPasswordResetEmail({required String email}) {
    return _remoteDataSource.sendPasswordResetEmail(email: email);
  }

  @override
  Future<void> updatePassword({required String newPassword}) async {
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
  Future<AccountDeletionPreview> previewAccountDeletion() async {
    try {
      final Object? data = await _remoteDataSource.previewAccountDeletion();
      return AccountDeletionPreview.fromFunctionData(data);
    } on FunctionException catch (error, stackTrace) {
      // Handle Supabase Function errors before the general mapper so preview
      // diagnostics remain available in the app log without leaking secrets.
      final AccountDeletionFailure failure = _mapFunctionFailure(error);
      _logPreviewFunctionFailure(failure, stackTrace);
      throw failure;
    } catch (error) {
      throw _mapAccountDeletionFailure(error);
    }
  }

  @override
  Future<void> confirmAccountDeletion() async {
    try {
      // The remote source invokes only the authenticated caller's
      // `delete-account` Edge Function. It deliberately performs no local,
      // database, job, customer, photo, or signature deletion.
      await _remoteDataSource.confirmAccountDeletion();
    } catch (error) {
      throw _mapAccountDeletionFailure(error);
    }
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
  Future<void> signOut() async {
    final User? user = _remoteDataSource.currentUser;
    if (user != null) {
      await _clearCachedAppUser(user.id);
    }
    return _remoteDataSource.signOut();
  }

  @override
  Future<void> clearLocalSession() async {
    final User? user = _remoteDataSource.currentUser;
    if (user != null) {
      await _clearCachedAppUser(user.id);
    }
    return _remoteDataSource.clearLocalSession();
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

  AccountDeletionFailure _mapAccountDeletionFailure(Object error) {
    if (error is AccountDeletionFailure) {
      return error;
    }
    if (error is AuthException) {
      return const AccountDeletionFailure(
        AccountDeletionFailureKind.sessionInvalid,
      );
    }
    if (error is FunctionException) {
      return _mapFunctionFailure(error);
    }
    return const AccountDeletionFailure(AccountDeletionFailureKind.requestFailed);
  }

  AccountDeletionFailure _mapFunctionFailure(FunctionException error) {
    final AccountDeletionFailureKind kind;
    if (error.status == 401) {
      kind = AccountDeletionFailureKind.sessionInvalid;
    } else if (error.status == 409 && _isLastActiveAdmin(error.details)) {
      kind = AccountDeletionFailureKind.lastActiveAdmin;
    } else {
      kind = AccountDeletionFailureKind.requestFailed;
    }

    return AccountDeletionFailure(
      kind,
      status: error.status,
      reasonPhrase: _sanitizeLogText(error.reasonPhrase),
      details: _sanitizeFunctionDetails(error.details),
    );
  }

  void _logPreviewFunctionFailure(
      AccountDeletionFailure failure,
      StackTrace stackTrace,
      ) {
    AppLogger.warning(
      'delete-account dry-run failed: '
          'status=${failure.status ?? 'unknown'}; '
          'reasonPhrase=${failure.reasonPhrase ?? 'none'}; '
          'details=${failure.details ?? 'none'}',
      error: failure,
      stackTrace: stackTrace,
    );
  }

  String? _sanitizeFunctionDetails(Object? details) {
    if (details == null) {
      return null;
    }

    if (details is String) {
      try {
        return _sanitizeFunctionDetails(jsonDecode(details));
      } on FormatException {
        return _sanitizeLogText(details);
      }
    }

    final Object? sanitized = _sanitizeLogValue(details);
    if (sanitized is String) {
      return _sanitizeLogText(sanitized);
    }
    try {
      return _truncateLogText(jsonEncode(sanitized));
    } on JsonUnsupportedObjectError {
      return '[non-serializable response details]';
    }
  }

  Object? _sanitizeLogValue(Object? value) {
    if (value is Map) {
      return <String, Object?>{
        for (final MapEntry<dynamic, dynamic> entry in value.entries)
          entry.key.toString(): _isSensitiveLogKey(entry.key.toString())
              ? '[REDACTED]'
              : _sanitizeLogValue(entry.value),
      };
    }
    if (value is Iterable) {
      return value.map(_sanitizeLogValue).toList(growable: false);
    }
    if (value is String) {
      return _sanitizeLogText(value);
    }
    return value;
  }

  bool _isSensitiveLogKey(String key) =>
      const <String>{
        'authorization',
        'access_token',
        'apikey',
        'api_key',
        'service_role',
        'refresh_token',
      }.contains(key.toLowerCase());

  String? _sanitizeLogText(String? value) {
    if (value == null) {
      return null;
    }
    final String redactedFields = value.replaceAllMapped(
      RegExp(
        r'''(["']?(?:authorization|access_token|apikey|api_key|service_role|refresh_token)["']?\s*[:=]\s*)(?:"[^"]*"|'[^']*'|[^,\s}\]]+)''',
        caseSensitive: false,
      ),
          (Match match) => '${match.group(1)}[REDACTED]',
    );
    final String redactedBearer = redactedFields.replaceAllMapped(
      RegExp(r'Bearer\s+[A-Za-z0-9._~+/=-]+', caseSensitive: false),
          (Match _) => 'Bearer [REDACTED]',
    );
    return _truncateLogText(redactedBearer);
  }

  String _truncateLogText(String value) {
    const int maximumLogLength = 2048;
    return value.length <= maximumLogLength
        ? value
        : '${value.substring(0, maximumLogLength)}…[truncated]';
  }

  bool _isLastActiveAdmin(Object? details) {
    if (details is Map) {
      return details.values.any(_isLastActiveAdmin);
    }
    if (details is Iterable) {
      return details.any(_isLastActiveAdmin);
    }
    if (details is String) {
      final String value = details.trim();
      if (value == 'last_active_admin') {
        return true;
      }
      try {
        return _isLastActiveAdmin(jsonDecode(value));
      } on FormatException {
        return value.contains('last_active_admin');
      }
    }
    return false;
  }

  static const String _cachedProfilePrefix = 'cached_employee_profile_';

  Future<void> _saveCachedAppUser(AppUserModel user) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final Map<String, dynamic> data = <String, dynamic>{
        'id': user.employeeId,
        'employee_code': user.employeeCode,
        'name': user.name,
        'phone': user.phone,
        'email': user.email,
        'role': user.role,
        'is_active': user.isActive,
      };
      await prefs.setString('$_cachedProfilePrefix${user.id}', jsonEncode(data));
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Failed to cache employee profile locally.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<AppUserModel?> _getCachedAppUser(String authUserId) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? jsonStr = prefs.getString('$_cachedProfilePrefix$authUserId');
      if (jsonStr == null || jsonStr.isEmpty) {
        return null;
      }
      final Map<String, dynamic> map = Map<String, dynamic>.from(
        jsonDecode(jsonStr) as Map,
      );
      return AppUserModel.fromMap(
        map: map,
        authUserId: authUserId,
        email: map['email'] as String? ?? '',
      );
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Failed to read cached employee profile.',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<void> _clearCachedAppUser(String authUserId) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_cachedProfilePrefix$authUserId');
    } catch (_) {}
  }

  Future<AppUserModel> _getAppUser(User user) async {
    Map<String, dynamic>? employee;
    try {
      // IMPORTANT: `employees.id` is the employee primary key whereas
      // `employees.auth_user_id` references `auth.users.id`.
      employee = await _supabase
          .from('employees')
          .select(
            'id, auth_user_id, employee_code, name, phone, email, role, is_active',
          )
          .eq('auth_user_id', user.id)
          .maybeSingle();
    } catch (error, stackTrace) {
      // Network failure or offline mode: try to restore the trusted local profile if available.
      AppLogger.warning(
        'Network query for employee profile failed. Attempting offline fallback.',
        error: error,
        stackTrace: stackTrace,
      );
      final AppUserModel? cached = await _getCachedAppUser(user.id);
      if (cached != null) {
        return cached;
      }
      // No local cached profile available for this account: rethrow so UI explains connection is required.
      rethrow;
    }

    if (employee == null) {
      await _clearCachedAppUser(user.id);
      await _safeSignOut();
      throw const AuthException(
        'Employee profile was not found.',
        code: AuthenticationErrorMapper.codeEmployeeNotFound,
      );
    }

    final bool isActive = employee['is_active'] as bool? ?? false;

    if (!isActive) {
      await _clearCachedAppUser(user.id);
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
      await _clearCachedAppUser(user.id);
      await _safeSignOut();
      throw const AuthException(
        'Invalid employee role.',
        code: AuthenticationErrorMapper.codeInvalidRole,
      );
    }

    // Save/update the trusted employee profile locally for offline restoration.
    await _saveCachedAppUser(appUser);

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
