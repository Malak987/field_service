import 'package:field_service/app/router/app_router.dart';
import 'package:get_it/get_it.dart';

/// Registers dependencies owned by the application shell.
///
/// Today that is routing only; theming, localisation and app-level lifecycle
/// services are registered here when they are introduced.
///
/// Called from `configureDependencies()` in `lib/app/di/injection.dart`.
void registerAppModule(GetIt sl) {
  // Lazy: the router is built when the root widget asks for it, and exactly
  // once for the whole application lifetime.
  sl.registerLazySingleton<AppRouter>(AppRouter.new);
}
