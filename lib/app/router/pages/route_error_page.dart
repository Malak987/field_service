import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Shown by the router when a location cannot be resolved.
class RouteErrorPage extends StatelessWidget {
  const RouteErrorPage({required this.location, this.error, super.key});

  /// The location that could not be resolved.
  final String location;

  /// Exception raised while resolving [location], when available.
  final Exception? error;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.pageNotFoundTitle)),
      body: Center(
        child: Padding(
          padding: AppSpacing.pagePadding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.link_off,
                size: AppDimensions.iconXl,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(location, style: theme.textTheme.titleMedium),
              if (error != null) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
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
