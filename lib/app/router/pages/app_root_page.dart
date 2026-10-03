import 'package:field_service/core/constants/app_constants.dart';
import 'package:flutter/material.dart';

/// Development placeholder for the application entry route (`/`).
///
/// Phase 3 status: **temporary, not a product screen.**
/// The real root of the application will decide between the authentication
/// flow, the admin area and the technician area once those exist. Until then
/// this page exists only because a router needs at least one route, and it
/// doubles as proof that theming, routing and dependency injection are wired.
///
/// It contains no business logic and must be deleted when the shell is built.
class AppRootPage extends StatelessWidget {
  const AppRootPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(AppConstants.appName, style: theme.textTheme.headlineMedium),
              const SizedBox(height: 12),
              Text(
                'Phase 3 — clean architecture foundation is in place.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
