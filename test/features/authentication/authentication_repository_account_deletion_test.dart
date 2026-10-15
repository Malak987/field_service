import 'package:field_service/features/authentication/data/datasources/authentication_remote_data_source.dart';
import 'package:field_service/features/authentication/data/repositories/authentication_repository_impl.dart';
import 'package:field_service/features/authentication/domain/entities/account_deletion_failure.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('preview preserves sanitized FunctionException diagnostics', () async {
    final _PreviewFailureRemoteDataSource remoteDataSource =
    _PreviewFailureRemoteDataSource(
      const FunctionsHttpException(
        status: 409,
        reasonPhrase: 'Conflict',
        details: <String, Object?>{
          'code': 'last_active_admin',
          'message': 'Add another active administrator first.',
          'access_token': 'do-not-log-this-token',
          'nested': <String, String>{'apikey': 'do-not-log-this-key'},
        },
      ),
    );
    final AuthenticationRepositoryImpl repository =
    AuthenticationRepositoryImpl(
      remoteDataSource: remoteDataSource,
      supabase: SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
      ),
    );

    try {
      await repository.previewAccountDeletion();
      fail('Expected AccountDeletionFailure.');
    } on AccountDeletionFailure catch (failure) {
      expect(failure.kind, AccountDeletionFailureKind.lastActiveAdmin);
      expect(failure.status, 409);
      expect(failure.reasonPhrase, 'Conflict');
      expect(failure.details, contains('last_active_admin'));
      expect(failure.details, contains('[REDACTED]'));
      expect(failure.details, isNot(contains('do-not-log-this-token')));
      expect(failure.details, isNot(contains('do-not-log-this-key')));
    }

    expect(remoteDataSource.confirmCalls, 0);
    expect(remoteDataSource.signOutCalls, 0);
    expect(remoteDataSource.clearLocalSessionCalls, 0);
  });
}

class _PreviewFailureRemoteDataSource
    implements AuthenticationRemoteDataSource {
  _PreviewFailureRemoteDataSource(this.previewError);

  final FunctionException previewError;
  int confirmCalls = 0;
  int signOutCalls = 0;
  int clearLocalSessionCalls = 0;

  @override
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async => throw UnimplementedError();

  @override
  Future<AuthResponse> signUp({
    required String fullName,
    required String email,
    required String password,
  }) async => throw UnimplementedError();

  @override
  Future<void> sendPasswordResetEmail({required String email}) async =>
      throw UnimplementedError();

  @override
  Future<UserResponse> updatePassword({required String newPassword}) async =>
      throw UnimplementedError();

  @override
  Future<Object?> previewAccountDeletion() async => throw previewError;

  @override
  Future<void> confirmAccountDeletion() async {
    confirmCalls++;
  }

  @override
  User? get currentUser => null;

  @override
  Future<void> signOut() async {
    signOutCalls++;
  }

  @override
  Future<void> clearLocalSession() async {
    clearLocalSessionCalls++;
  }

  @override
  Stream<AuthState> get onAuthStateChange => const Stream<AuthState>.empty();
}
