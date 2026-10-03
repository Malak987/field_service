import 'package:field_service/core/network/connectivity_network_info.dart';
import 'package:field_service/core/network/network_info.dart';
import 'package:get_it/get_it.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Registers cross-cutting infrastructure that every feature may depend on.
///
/// Phase 3 status: only connectivity is registered, because it is the one core
/// abstraction that is meaningful without Supabase, a database schema or a sync
/// engine. Nothing consumes it yet; the offline sync phase will.
///
/// Later phases append their registrations here, for example:
///
/// ```dart
/// sl.registerSingletonAsync<AppDatabase>(AppDatabase.open);
/// sl.registerSingleton<FileStorage>(LocalFileStorage());
/// sl.registerSingleton<SyncQueue>(DriftSyncQueue(sl<AppDatabase>()));
/// sl.registerSingleton<SyncProcessor>(OfflineSyncProcessor(...));
/// ```
///
/// Note that repositories and data sources are registered by their *feature*
/// module, not here: only genuinely shared infrastructure belongs to core.
void registerCoreModule(GetIt sl) {
  sl.registerLazySingleton<NetworkInfo>(
    ConnectivityNetworkInfo.new,
  );

  sl.registerLazySingleton<SupabaseClient>(
        () => Supabase.instance.client,
  );
}