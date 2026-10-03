import 'package:field_service/app/di/modules/app_module.dart';
import 'package:field_service/app/di/modules/core_module.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:field_service/app/di/modules/authentication_module.dart';


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
/// Phase 3 registers the application shell plus the cross-cutting abstractions
/// that already exist. Feature modules are appended as they are implemented:
///
/// ```dart
/// registerAuthenticationModule(sl); // later phase
/// registerJobsModule(sl);           // later phase
/// ```
///
/// The function is asynchronous on purpose: later phases must open the local
/// database and read persisted settings (auth session, theme choice) before the
/// first frame, using `registerSingletonAsync`.
Future<void> configureDependencies() async {
  registerAppModule(sl);
  registerCoreModule(sl);
  registerAuthenticationModule(sl);
}
/// Disposes and clears the graph.
///
/// Tests call this between cases so each one gets a clean container; production
/// code never needs it because a real app process lives once.
@visibleForTesting
Future<void> resetDependencies() => sl.reset(dispose: true);
