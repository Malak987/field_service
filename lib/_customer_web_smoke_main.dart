import 'dart:async';

import 'package:field_service/app/app.dart';
import 'package:field_service/app/di/injection.dart';
import 'package:field_service/app/router/app_router.dart';
import 'package:field_service/core/database/app_database.dart';
import 'package:field_service/core/database/app_database_factory.dart';
import 'package:field_service/core/network/network_info.dart';
import 'package:field_service/features/authentication/domain/entities/app_user.dart';
import 'package:field_service/features/authentication/domain/entities/auth_session_event.dart';
import 'package:field_service/features/authentication/domain/repositories/authentication_repository.dart';
import 'package:field_service/features/customers/data/datasources/customers_remote_data_source.dart';
import 'package:field_service/features/customers/data/models/customer_model.dart';
import 'package:flutter/widgets.dart';

const _admin = AppUser(
  id: 'chrome-smoke-admin',
  email: 'admin@example.test',
  role: 'admin',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureDependencies();

  await sl.unregister<AuthenticationRepository>();
  sl.registerSingleton<AuthenticationRepository>(_AdminAuthentication());

  await sl.unregister<NetworkInfo>();
  sl.registerSingleton<NetworkInfo>(_OfflineNetworkInfo());

  await sl.unregister<CustomersRemoteDataSource>();
  sl.registerSingleton<CustomersRemoteDataSource>(_UnusedRemote());

  await sl.unregister<AppDatabase>();
  final database = AppDatabase(
    const AppDatabaseFactory(databaseName: 'field_service_web_smoke').open(),
  );
  sl.registerSingleton<AppDatabase>(database);
  await database.select(database.customersTable).get();

  runApp(FieldServiceApp(router: sl<AppRouter>().router));
}

class _AdminAuthentication implements AuthenticationRepository {
  @override
  Future<AppUser?> getCurrentUser() async => _admin;

  @override
  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async => _admin;

  @override
  Future<AppUser?> signUp({
    required String fullName,
    required String email,
    required String password,
  }) async => null;

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {}

  @override
  Future<void> updatePassword({required String newPassword}) async {}

  @override
  Future<void> signOut() async {}

  @override
  Stream<AuthSessionEvent> watchAuthStateChanges() => const Stream.empty();
}

class _OfflineNetworkInfo implements NetworkInfo {
  @override
  Future<bool> get isConnected async => false;

  @override
  Stream<bool> get onConnectionChanged => Stream<bool>.value(false);
}

class _UnusedRemote implements CustomersRemoteDataSource {
  @override
  Future<List<CustomerModel>> fetchAll() async => <CustomerModel>[];

  @override
  Future<void> upsertRow(Map<String, Object?> row) async =>
      throw StateError('Offline Chrome smoke test must not call Supabase.');

  @override
  Future<bool> updateRow({
    required String id,
    required Map<String, Object?> changes,
  }) async =>
      throw StateError('Offline Chrome smoke test must not call Supabase.');

  @override
  Future<bool> deleteRow(String id) async =>
      throw StateError('Offline Chrome smoke test must not call Supabase.');
}
