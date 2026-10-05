import 'package:field_service/app/router/app_router.dart';
import 'package:field_service/core/localization/locale_cubit.dart';
import 'package:get_it/get_it.dart';

/// Registers dependencies owned by the application shell.
///
/// Routing and the locale state: `FieldServiceApp` reads the persisted
/// language through [LocaleCubit] (SharedPreferences loads are non-blocking
/// and failure-tolerant, so startup never waits on disk).
///
/// Called from `configureDependencies()` in `lib/app/di/injection.dart`.
void registerAppModule(GetIt sl) {
  // Lazy: the router is built when the root widget asks for it, and exactly
  // once for the whole application lifetime.
  sl.registerLazySingleton<AppRouter>(AppRouter.new);

  // Factory: one cubit instance owned by the root widget; features read it
  // from the widget tree (LanguageSwitcher), not from the locator.
  sl.registerFactory<LocaleCubit>(LocaleCubit.new);
}
