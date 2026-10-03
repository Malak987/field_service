import 'package:field_service/core/constants/app_constants.dart';
import 'package:field_service/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Root widget of the application.
///
/// It wires the three application-shell concerns together — routing, theming
/// and app-level metadata — and does nothing else. The [GoRouter] is injected
/// (see `lib/app/di`) instead of being read from the service locator here, so
/// that the widget stays testable and free of global lookups.
class FieldServiceApp extends StatelessWidget {
  const FieldServiceApp({required this.router, super.key});

  /// Router created by the dependency graph.
  final GoRouter router;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      // Light and dark are supported from day one; the user-facing switch
      // arrives with the settings feature.
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}
