import 'dart:async';

import 'package:field_service/app/app.dart';
import 'package:field_service/app/di/injection.dart';
import 'package:field_service/app/router/app_router.dart';
import 'package:field_service/core/deep_linking/auth_deep_link_config.dart';
import 'package:field_service/core/network/supabase/supabase_config.dart';
import 'package:field_service/core/sync/sync_manager.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
    // Centralized deep-link handling. The Supabase client observes the
    // OS-level deep-link stream (cold, warm and background starts, via its
    // built-in `AppLinks` observer) and exchanges a detected auth callback for
    // a session. Only the URIs declared in [AuthDeepLinkConfig]
    // (fieldservice://auth-callback and fieldservice://reset-password) are
    // treated as auth callbacks. The matching native URL-type registrations
    // live in AndroidManifest.xml and Info.plist.
    authOptions: FlutterAuthClientOptions(
      detectSessionInUriPredicate: AuthDeepLinkConfig.isAuthCallbackUriPredicate,
    ),
  );

  await configureDependencies();

  // Start the offline-first sync engine: it recovers interrupted operations,
  // subscribes to connectivity and flushes the queue when (or as soon as)
  // usable internet is available. Deliberately **not awaited** — the app
  // must be usable immediately, offline or online; the first internet probe
  // runs in the background.
  unawaited(sl<SyncManager>().start());

  runApp(
    FieldServiceApp(
      router: sl<AppRouter>().router,
    ),
  );
}
