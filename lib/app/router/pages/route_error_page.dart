import 'package:flutter/material.dart';

/// Shown by the router when a location cannot be resolved.
///
/// This covers broken deep links and malformed parameters (for example a job id
/// that does not exist), which matters in the field where technicians open links
/// from messages.
///
/// Phase 3 status: **temporary** — replaced by the product's error screen, but
/// the route-level error handling itself is permanent.
class RouteErrorPage extends StatelessWidget {
  const RouteErrorPage({required this.location, this.error, super.key});

  /// The location that could not be resolved.
  final String location;

  /// Exception raised while resolving [location], when available.
  final Exception? error;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Page not found')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.link_off, size: 40, color: theme.colorScheme.outline),
              const SizedBox(height: 16),
              Text(location, style: theme.textTheme.titleMedium),
              if (error != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  error.toString(),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
