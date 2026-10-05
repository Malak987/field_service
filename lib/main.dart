import 'package:field_service/app/app.dart';
import 'package:field_service/app/di/injection.dart';
import 'package:field_service/app/router/app_router.dart';
import 'package:field_service/core/utils/logger.dart';
import 'package:flutter/widgets.dart';

/// Application entry point.
///
/// Its responsibilities are deliberately limited to:
/// 1. binding the Flutter engine,
/// 2. building the dependency graph,
/// 3. starting the root widget.
///
/// No business logic, no data access and no configuration values live here.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Phase 3 registers the application shell only (routing + core abstractions).
  // Feature modules register themselves in `lib/app/di/modules` as they are
  // implemented in later phases.
  await configureDependencies();
  AppLogger.info('Dependency graph configured.');

  runApp(FieldServiceApp(router: sl<AppRouter>().router));
}
