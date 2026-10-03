import 'package:field_service/features/authentication/data/datasources/authentication_remote_data_source.dart';
import 'package:field_service/features/authentication/data/models/app_user_model.dart';
import 'package:field_service/features/authentication/domain/entities/app_user.dart';
import 'package:field_service/features/authentication/domain/repositories/authentication_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthenticationRepositoryImpl
    implements AuthenticationRepository {
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
    final response = await _remoteDataSource.signIn(
      email: email,
      password: password,
    );

    final user = response.user;

    if (user == null) {
      throw const AuthException('Unable to sign in.');
    }

    return _getAppUser(user);
  }

  @override
  Future<AppUser?> getCurrentUser() async {
    final user = _remoteDataSource.currentUser;

    if (user == null) {
      return null;
    }

    return _getAppUser(user);
  }

  @override
  Future<void> signOut() {
    return _remoteDataSource.signOut();
  }

  Future<AppUserModel> _getAppUser(User user) async {
    final employee = await _supabase
        .from('employees')
        .select('id, employee_code, name, role, is_active')
        .eq('auth_user_id', user.id)
        .maybeSingle();

    if (employee == null) {
      throw const AuthException(
        'Employee profile was not found.',
      );
    }

    final isActive = employee['is_active'] as bool? ?? false;

    if (!isActive) {
      throw const AuthException(
        'This employee account is inactive.',
      );
    }

    return AppUserModel.fromMap(
      map: employee,
      authUserId: user.id,
      email: user.email ?? '',
    );
  }
}