import 'package:field_service/core/deep_linking/auth_deep_link_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class AuthenticationRemoteDataSource {
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  });

  Future<AuthResponse> signUp({
    required String fullName,
    required String email,
    required String password,
  });

  Future<void> sendPasswordResetEmail({required String email});

  Future<UserResponse> updatePassword({required String newPassword});

  /// Runs the non-destructive `delete-account` preview for the current session.
  Future<Object?> previewAccountDeletion();

  /// Confirms deletion of the current authenticated account through the
  /// deployed `delete-account` Edge Function.
  Future<void> confirmAccountDeletion();

  User? get currentUser;

  Future<void> signOut();

  /// Removes this device's persisted session without making a remote sign-out
  /// request. Used only after a confirmed deletion or invalid session.
  Future<void> clearLocalSession();

  Stream<AuthState> get onAuthStateChange;
}

class AuthenticationRemoteDataSourceImpl
    implements AuthenticationRemoteDataSource {
  AuthenticationRemoteDataSourceImpl(this.supabase);

  final SupabaseClient supabase;

  @override
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) {
    return supabase.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  @override
  Future<AuthResponse> signUp({
    required String fullName,
    required String email,
    required String password,
  }) {
    // Security: never send or accept a `role` attribute from the client.
    // Role assignment is strictly managed on the backend (`employees.role`).
    //
    // `emailRedirectTo` is where Supabase sends the user when they tap the
    // "confirm your email" link. On mobile/desktop it opens the app through the
    // `fieldservice://auth-callback` deep link; on web it returns to the app's
    // own origin. The value is centralized in [AuthDeepLinkConfig].
    return supabase.auth.signUp(
      email: email.trim(),
      password: password,
      emailRedirectTo: AuthDeepLinkConfig.emailConfirmationRedirectTo,
      data: <String, dynamic>{'full_name': fullName.trim()},
    );
  }

  @override
  Future<void> sendPasswordResetEmail({required String email}) {
    // `redirectTo` is where Supabase sends the user when they tap the recovery
    // link. On mobile/desktop it opens the app through the
    // `fieldservice://reset-password` deep link; on web it returns to the
    // app's own origin. The value is centralized in [AuthDeepLinkConfig].
    return supabase.auth.resetPasswordForEmail(
      email.trim(),
      redirectTo: AuthDeepLinkConfig.passwordResetRedirectTo,
    );
  }

  @override
  Future<UserResponse> updatePassword({required String newPassword}) {
    return supabase.auth.updateUser(UserAttributes(password: newPassword));
  }

  @override
  Future<Object?> previewAccountDeletion() async {
    final FunctionResponse response = await _invokeAccountDeletionFunction(
      body: const <String, bool>{'dry_run': true},
    );
    return response.data;
  }

  @override
  Future<void> confirmAccountDeletion() async {
    await _invokeAccountDeletionFunction(
      body: const <String, bool>{'confirm_delete': true},
    );
  }

  Future<FunctionResponse> _invokeAccountDeletionFunction({
    required Map<String, bool> body,
  }) async {
    // The function identifies and authorizes the caller from the current JWT.
    // Do not send a user id: it must never be possible for a client to choose
    // another account for deletion. The Supabase client supplies the current
    // session Authorization header automatically.
    if (supabase.auth.currentSession == null) {
      throw const AuthException('No authenticated session is available.');
    }

    final FunctionResponse response = await supabase.functions.invoke(
      'delete-account',
      body: body,
    );
    if (response.status < 200 || response.status >= 300) {
      throw StateError(
        'delete-account responded with an unsuccessful status: ${response.status}',
      );
    }
    return response;
  }

  @override
  User? get currentUser => supabase.auth.currentUser;

  @override
  Future<void> signOut() {
    return supabase.auth.signOut();
  }

  @override
  Future<void> clearLocalSession() {
    return supabase.auth.signOut(scope: SignOutScope.local);
  }

  @override
  Stream<AuthState> get onAuthStateChange => supabase.auth.onAuthStateChange;
}
