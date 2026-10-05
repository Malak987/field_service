import 'package:field_service/app/router/app_router.dart';
import 'package:field_service/core/localization/locale_cubit.dart';
import 'package:get_it/get_it.dart';

/// Registers dependencies owned by the application shell.
///
/// Called from `configureDependencies()` in `lib/app/di/injection.dart`.
void registerAppModule(GetIt sl) {
  sl.registerLazySingleton<AppRouter>(AppRouter.new);
  sl.registerLazySingleton<LocaleCubit>(
    () => LocaleCubit()..loadSavedLocale(),
  );
}
