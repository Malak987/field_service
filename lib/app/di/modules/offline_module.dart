import 'package:field_service/core/database/app_database.dart';
import 'package:field_service/core/database/app_database_factory.dart';
import 'package:field_service/core/network/connectivity_service.dart';
import 'package:field_service/core/network/network_info.dart';
import 'package:field_service/core/sync/drift_sync_queue.dart';
import 'package:field_service/core/sync/sync_handler.dart';
import 'package:field_service/core/sync/sync_manager.dart';
import 'package:field_service/core/sync/sync_processor.dart';
import 'package:field_service/core/sync/sync_queue.dart';
import 'package:field_service/core/sync/sync_status_cubit.dart';
import 'package:field_service/core/storage/app_file_storage.dart';
import 'package:field_service/core/storage/file_storage.dart';
import 'package:field_service/core/storage/local_file_storage.dart';
import 'package:field_service/core/storage/local_job_retention_cleaner.dart';
import 'package:field_service/features/authentication/domain/repositories/authentication_repository.dart';
import 'package:get_it/get_it.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Composition root of the offline-first foundation.
///
/// Registers the local database, the sync queue, the connectivity service,
/// the sync engine and the file storage. Feature modules (customers, jobs,
/// job files) register their [SyncOperationHandler]s into the shared
/// [SyncHandlerRegistry] from their own modules — the registry starts empty
/// on purpose: an unhandled entity type fails loudly in the queue instead of
/// being silently dropped or fake-synced.
String? _resolveCurrentUserId(GetIt sl) {
  try {
    final String? supabaseUid = sl<SupabaseClient>().auth.currentUser?.id;
    if (supabaseUid != null && supabaseUid.isNotEmpty) return supabaseUid;
  } catch (_) {}
  try {
    final dynamic authRepo = sl<AuthenticationRepository>();
    final dynamic user = authRepo.currentUser;
    if (user != null) return user.id?.toString();
  } catch (_) {}
  return null;
}

void registerOfflineModule(GetIt sl) {
  // --- Local database -----------------------------------------------------
  // The factory decides *how* the database is opened (platform file via
  // path_provider, shared across isolates); the class owns the schema.
  sl.registerLazySingleton<AppDatabase>(
    () => AppDatabase(AppDatabaseFactory().open()),
  );

  // --- Sync queue ----------------------------------------------------------
  sl.registerLazySingleton<SyncQueue>(
    () => DriftSyncQueue(
      sl<AppDatabase>(),
      currentUserId: () => _resolveCurrentUserId(sl),
    ),
  );

  // --- Connectivity ----------------------------------------------------------
  // NetworkInfo (interface + reachability probe) is registered by the core
  // module; ConnectivityService turns it into a managed state stream.
  sl.registerLazySingleton<ConnectivityService>(
    () => ConnectivityService(networkInfo: sl<NetworkInfo>()),
  );

  // --- Sync engine ------------------------------------------------------------
  // The mutable registry is the singleton; the read-only contract view points
  // at the same instance so feature modules can `register(...)` their handlers
  // while the manager only ever looks handlers up.
  sl.registerLazySingleton<MutableSyncHandlerRegistry>(
    MutableSyncHandlerRegistry.new,
  );

  sl.registerLazySingleton<SyncHandlerRegistry>(
    () => sl<MutableSyncHandlerRegistry>(),
  );

  sl.registerLazySingleton<SyncManager>(
    () => SyncManager(
      queue: sl<SyncQueue>(),
      connectivity: sl<ConnectivityService>(),
      handlers: sl<SyncHandlerRegistry>(),
      currentUserId: () => _resolveCurrentUserId(sl),
    ),
  );

  // The engine's *contract* points at the one engine instance: features may
  // nudge it after an enqueue (`processPendingOperations`) but must never
  // construct their own sync loop.
  sl.registerLazySingleton<SyncProcessor>(() => sl<SyncManager>());

  // --- File storage -------------------------------------------------------------
  sl.registerLazySingleton<FileStorage>(AppFileStorage.new);

  // Constructed for the reviewed retention flow, but intentionally not
  // scheduled/run until owner-approved staging validation is complete.
  sl.registerLazySingleton<LocalJobRetentionCleaner>(
    () => LocalJobRetentionCleaner(
      database: sl<AppDatabase>(),
      fileStorage: sl<FileStorage>(),
      currentUserId: () => _resolveCurrentUserId(sl),
    ),
  );

  sl.registerLazySingleton<LocalFileStorage>(
    () => LocalFileStorage(
      fileStorage: sl<FileStorage>(),
      database: sl<AppDatabase>(),
      syncQueue: sl<SyncQueue>(),
    ),
  );

  // --- UI state --------------------------------------------------------------------
  // Factory: every consumer (badge, admin screen, ...) owns its own cubit.
  sl.registerFactory<SyncStatusCubit>(
    () => SyncStatusCubit(syncManager: sl<SyncManager>()),
  );
}
