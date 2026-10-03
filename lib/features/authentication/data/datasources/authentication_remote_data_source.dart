import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class AuthenticationRemoteDataSource {
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  });

  User? get currentUser;

  Future<void> signOut();
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
      email: email,
      password: password,
    );
  }

  @override
  User? get currentUser => supabase.auth.currentUser;

  @override
  Future<void> signOut() {
    return supabase.auth.signOut();
  }
}