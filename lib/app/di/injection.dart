import 'package:field_service/app/di/modules/app_module.dart';
import 'package:field_service/app/di/modules/authentication_module.dart';
import 'package:field_service/app/di/modules/core_module.dart';
import 'package:field_service/app/di/modules/customers_module.dart';
import 'package:field_service/app/di/modules/jobs_module.dart';
import 'package:field_service/app/di/modules/offline_module.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';

/// The single service locator of the application.
///
/// Rules of use:
/// * [configureDependencies] is called exactly once, from `main()`.
/// * Widgets never read [sl] — Cubits and entry points receive their
///   dependencies through constructors, and `sl<X>()` is only called at
///   composition points.
/// * Every layer/feature exposes its own `register...Module(GetIt)` function,
///   so this file never becomes a dumping ground of registrations.
final GetIt sl = GetIt.instance;

/// Builds the dependency graph.
///
/// Registration order matters once: the offline module must exist before
/// feature modules register their sync handlers into its registry, and the
/// Supabase client (core module) must exist before the feature data sources
/// resolve it.
Future<void> configureDependencies() async {
  registerAppModule(sl);
  registerCoreModule(sl);
  registerOfflineModule(sl);
  registerAuthenticationModule(sl);
  registerJobsModule(sl);
  registerCustomersModule(sl);
}

/// Disposes and clears the graph.
///
/// Tests call this between cases so each one gets a clean container; production
/// code never needs it because a real app process lives once.
@visibleForTesting
Future<void> resetDependencies() => sl.reset(dispose: true);
