import 'package:field_service/app/di/injection.dart';
import 'package:field_service/core/constants/app_constants.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/localization/locale_cubit.dart';
import 'package:field_service/core/theme/app_theme.dart';
import 'package:field_service/features/authentication/presentation/cubit/authentication_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// Root widget of the application.
///
/// Wires routing, theming, localization (`en` / `de`), and top-level
/// session/locale state together.
class FieldServiceApp extends StatelessWidget {
  const FieldServiceApp({
    required this.router,
    this.localeCubit,
    this.authenticationCubit,
    super.key,
  });

  /// Router created by the dependency graph.
  final GoRouter router;

  /// Optional injected [LocaleCubit] (useful for widget tests).
  final LocaleCubit? localeCubit;

  /// Optional injected [AuthenticationCubit] (useful for widget tests).
  final AuthenticationCubit? authenticationCubit;

  LocaleCubit _resolveLocaleCubit() {
    if (localeCubit != null) {
      return localeCubit!;
    }
    if (sl.isRegistered<LocaleCubit>()) {
      return sl<LocaleCubit>();
    }
    return LocaleCubit();
  }

  AuthenticationCubit? _resolveAuthenticationCubit() {
    if (authenticationCubit != null) {
      return authenticationCubit;
    }
    if (sl.isRegistered<AuthenticationCubit>()) {
      try {
        return sl<AuthenticationCubit>()..checkCurrentUser();
      } catch (_) {
        // In minimal unit tests where Supabase was not initialized, fall back
        // gracefully so the shell can still render.
        return null;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final LocaleCubit resolvedLocaleCubit = _resolveLocaleCubit();
    final AuthenticationCubit? resolvedAuthCubit =
        _resolveAuthenticationCubit();

    return MultiBlocProvider(
      providers: <BlocProvider<dynamic>>[
        BlocProvider<LocaleCubit>.value(value: resolvedLocaleCubit),
        if (resolvedAuthCubit != null)
          BlocProvider<AuthenticationCubit>(
            create: (_) => resolvedAuthCubit,
          ),
      ],
      child: BlocBuilder<LocaleCubit, Locale>(
        builder: (BuildContext context, Locale activeLocale) {
          return MaterialApp.router(
            title: AppConstants.appName,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: ThemeMode.system,
            locale: activeLocale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            routerConfig: router,
          );
        },
      ),
    );
  }
}
