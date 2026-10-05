import 'package:field_service/app/di/injection.dart';
import 'package:field_service/core/constants/app_constants.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/localization/locale_cubit.dart';
import 'package:field_service/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// Root widget of the application.
///
/// It wires the application-shell concerns together — routing, theming,
/// localization and app-level metadata — and does nothing else. The
/// [GoRouter] is injected (see `lib/app/di`) instead of being read from the
/// service locator here, so that the widget stays testable and free of
/// global lookups; the locale source (`LocaleCubit`) lives above the router
/// so every feature screen — and the `LanguageSwitcher` — shares one
/// language state that also drives `MaterialApp.router.locale`.
class FieldServiceApp extends StatelessWidget {
  const FieldServiceApp({required this.router, super.key});

  /// Router created by the dependency graph.
  final GoRouter router;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<LocaleCubit>(
      create: (_) => sl<LocaleCubit>()..loadSavedLocale(),
      child: Builder(
        builder: (BuildContext context) {
          final Locale locale = context.watch<LocaleCubit>().state;

          return MaterialApp.router(
            title: AppConstants.appName,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            // Light and dark are supported from day one; the user-facing
            // switch arrives with the settings feature.
            themeMode: ThemeMode.system,
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: locale,
          );
        },
      ),
    );
  }
}
