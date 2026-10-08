import 'package:field_service/core/network/connectivity_network_info.dart';
import 'package:field_service/core/network/network_info.dart';
import 'package:field_service/core/network/supabase/supabase_client.dart';
import 'package:get_it/get_it.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Registers cross-cutting infrastructure that every feature may depend on.
///
/// Feature modules use the [SupabaseClient] registered here (initialized in
/// `main()` before the graph is built) — features never reach for
/// `Supabase.instance` themselves, which keeps backend wiring in one place
/// and keeps data sources unit-testable with fakes.
///
/// Note that repositories and data sources are registered by their *feature*
/// module, not here: only genuinely shared infrastructure belongs to core.
void registerCoreModule(GetIt sl) {
  sl.registerLazySingleton<NetworkInfo>(ConnectivityNetworkInfo.new);

  // The shared, already-initialized Supabase client (auth + PostgREST).
  sl.registerLazySingleton<SupabaseClient>(() => SupabaseClientProvider.client);
}
