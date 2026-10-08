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

  User? get currentUser;

  Future<void> signOut();

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
  User? get currentUser => supabase.auth.currentUser;

  @override
  Future<void> signOut() {
    return supabase.auth.signOut();
  }

  @override
  Stream<AuthState> get onAuthStateChange => supabase.auth.onAuthStateChange;
}
