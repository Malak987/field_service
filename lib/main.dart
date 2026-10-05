import 'dart:async';

import 'package:field_service/app/app.dart';
import 'package:field_service/app/di/injection.dart';
import 'package:field_service/app/router/app_router.dart';
import 'package:field_service/core/deep_linking/auth_deep_link_config.dart';
import 'package:field_service/core/network/supabase/supabase_config.dart';
import 'package:field_service/core/sync/sync_manager.dart';
import 'package:field_service/core/utils/logger.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Application entry point.
///
/// Its responsibilities are deliberately limited to:
/// 1. binding the Flutter engine,
/// 2. initializing the Supabase client (session persistence + deep links),
/// 3. building the dependency graph,
/// 4. starting the offline sync engine,
/// 5. starting the root widget.
///
/// No business logic, no data access and no configuration values live here.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The Supabase client is initialized before the DI graph so every lazy
  // `sl<SupabaseClient>()` resolution finds a ready client. The deep-link
  // predicate keeps the app exchanging *only* the callbacks it registered
  // (see AuthDeepLinkConfig) for a session.
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
    authOptions: FlutterAuthClientOptions(
      detectSessionInUriPredicate:
          AuthDeepLinkConfig.isAuthCallbackUriPredicate,
    ),
  );

  await configureDependencies();
  AppLogger.info('Dependency graph configured.');

  // The sync engine: crash recovery, connectivity watching and queue pushing.
  // `start` is explicitly non-blocking by design — the app is fully usable
  // (offline-first) long before the first network probe resolves.
  unawaited(sl<SyncManager>().start());

  runApp(FieldServiceApp(router: sl<AppRouter>().router));
}
