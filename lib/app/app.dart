import 'package:field_service/app/di/injection.dart';
import 'package:field_service/app/router/app_routes.dart';
import 'package:field_service/core/constants/app_constants.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/localization/locale_cubit.dart';
import 'package:field_service/core/theme/app_theme.dart';
import 'package:field_service/features/authentication/presentation/cubit/authentication_cubit.dart';
import 'package:field_service/features/authentication/presentation/cubit/authentication_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// Root widget of the application.
///
/// Authentication and locale live above the router. DI owns the single
/// authentication cubit; every route (including the gate) observes it.
class FieldServiceApp extends StatefulWidget {
  const FieldServiceApp({required this.router, super.key});

  final GoRouter router;

  @override
  State<FieldServiceApp> createState() => _FieldServiceAppState();
}

class _FieldServiceAppState extends State<FieldServiceApp> {
  late final AuthenticationCubit _authenticationCubit;

  @override
  void initState() {
    super.initState();
    _authenticationCubit = sl<AuthenticationCubit>();
    // Start restoration even when the initial URL is not the root gate.
    // Do this once, not on rebuilds or when a feature route is opened.
    _authenticationCubit.checkCurrentUser();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<AuthenticationCubit>.value(
      // The singleton is disposed by DI, never by an individual route.
      value: _authenticationCubit,
      child: MultiBlocListener(
        listeners: [
          BlocListener<AuthenticationCubit, AuthenticationState>(
            listenWhen: (previous, current) =>
                previous.user != null &&
                current.user == null &&
                current.status != AuthenticationStatus.passwordRecovery,
            // Also discard imperative (push) pages. A refresh alone can retain
            // a customer page above `/`, where the gate is now offstage.
            listener: (_, _) => widget.router.go(AppRoutes.root),
          ),
          BlocListener<AuthenticationCubit, AuthenticationState>(
            listenWhen: (previous, current) =>
                previous.status != current.status ||
                previous.user != current.user,
            // Feature routes observe this same app-scoped session via guards.
            listener: (_, _) => widget.router.refresh(),
          ),
        ],
        child: BlocProvider<LocaleCubit>(
          create: (_) => sl<LocaleCubit>()..loadSavedLocale(),
          child: Builder(
            builder: (BuildContext context) {
              final Locale locale = context.watch<LocaleCubit>().state;

              return MaterialApp.router(
                title: AppConstants.appName,
                debugShowCheckedModeBanner: false,
                theme: AppTheme.light,
                darkTheme: AppTheme.dark,
                themeMode: ThemeMode.system,
                routerConfig: widget.router,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                locale: locale,
              );
            },
          ),
        ),
      ),
    );
  }
}
