import 'package:drift/native.dart';
import 'package:field_service/app/app.dart';
import 'package:field_service/app/di/injection.dart';
import 'package:field_service/app/router/app_router.dart';
import 'package:field_service/app/router/app_routes.dart';
import 'package:field_service/core/database/app_database.dart';
import 'package:field_service/core/network/connectivity_service.dart';
import 'package:field_service/core/network/network_info.dart';
import 'package:field_service/core/sync/sync_manager.dart';
import 'package:field_service/features/authentication/domain/entities/app_user.dart';
import 'package:field_service/features/authentication/domain/repositories/authentication_repository.dart';
import 'package:field_service/features/customers/data/datasources/customers_remote_data_source.dart';
import 'package:field_service/features/customers/data/models/customer_model.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/repositories/jobs_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_authentication_repository.dart';

/// Uses the production DI graph, routes, cubits, customer repository, Drift
/// tables and durable sync queue. Only the external auth/network is replaced.
class AppTestHarness {
  final TestAuthenticationRepository authentication =
      TestAuthenticationRepository();
  late GoRouter router;
  AppDatabase? database;

  Future<void> configure({
    AppUser? user,
    String initialLocation = AppRoutes.root,
    bool withCustomers = false,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await configureDependencies();
    authentication.currentUser = user;
    await sl.unregister<AuthenticationRepository>();
    sl.registerSingleton<AuthenticationRepository>(authentication);

    await sl.unregister<JobsRepository>();
    sl.registerSingleton<JobsRepository>(_EmptyJobsRepository());

    if (withCustomers) {
      database = AppDatabase(NativeDatabase.memory());
      await sl.unregister<AppDatabase>();
      sl.registerSingleton<AppDatabase>(database!, dispose: (db) => db.close());
      await sl.unregister<NetworkInfo>();
      sl.registerSingleton<NetworkInfo>(_OfflineNetworkInfo());
      await sl.unregister<CustomersRemoteDataSource>();
      sl.registerSingleton<CustomersRemoteDataSource>(
        _UnusedCustomersRemoteDataSource(),
      );
    }

    router = AppRouter(initialLocation: initialLocation).router;
  }

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(FieldServiceApp(router: router));
    await tester.pumpAndSettle();
  }

  Future<void> dispose() async {
    router.dispose();
    if (database != null) {
      await sl<SyncManager>().dispose();
      await sl<ConnectivityService>().dispose();
    }
    await resetDependencies();
    await authentication.dispose();
  }
}

class _OfflineNetworkInfo implements NetworkInfo {
  @override
  Future<bool> get isConnected async => false;

  @override
  Stream<bool> get onConnectionChanged => Stream<bool>.value(false);
}

class _UnusedCustomersRemoteDataSource implements CustomersRemoteDataSource {
  @override
  Future<List<CustomerModel>> fetchAll() async => <CustomerModel>[];

  @override
  Future<void> upsertRow(Map<String, Object?> row) async =>
      throw StateError('Offline UI tests must not push customer writes.');

  @override
  Future<bool> updateRow({
    required String id,
    required Map<String, Object?> changes,
  }) async =>
      throw StateError('Offline UI tests must not push customer writes.');

  @override
  Future<bool> deleteRow(String id) async =>
      throw StateError('Offline UI tests must not push customer writes.');
}

class _EmptyJobsRepository implements JobsRepository {
  @override
  Future<List<Job>> getJobs() async => <Job>[];

  @override
  Future<Job> getJobById(String id) async => throw UnimplementedError();

  @override
  Future<void> updateJobStatus({
    required String jobId,
    required String status,
  }) async => throw UnimplementedError();
}
