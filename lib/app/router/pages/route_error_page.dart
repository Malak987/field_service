import 'package:field_service/app/router/app_routes.dart';
import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_radius.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Shown by the router when a location cannot be resolved.
///
/// This covers broken deep links and malformed parameters (for example a job id
/// that does not exist), which matters in the field where technicians open links
/// from messages.
///
/// Fully localized: a technician working in German must not be met with an
/// English dead end. The offending location stays visible in a monospace run
/// because it is a diagnostic, not copy — but it is never the headline.
class RouteErrorPage extends StatelessWidget {
  const RouteErrorPage({required this.location, this.error, super.key});

  /// The location that could not be resolved.
  final String location;

  /// Exception raised while resolving [location], when available.
  final Exception? error;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.pageNotFoundTitle)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: AppSpacing.pagePadding,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppDimensions.authFormMaxWidth,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Icon(
                    Icons.link_off_rounded,
                    size: AppDimensions.iconXl,
                    color: context.colors.outline,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    l10n.pageNotFoundTitle,
                    textAlign: TextAlign.center,
                    style: context.textStyles.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    l10n.pageNotFoundSubtitle,
                    textAlign: TextAlign.center,
                    style: context.textStyles.bodyMedium?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  // The raw location in a monospace run: it is a diagnostic the
                  // user may have to read back over the phone.
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    decoration: BoxDecoration(
                      color: context.colors.surface,
                      borderRadius: AppRadius.bannerDirectional,
                      border: Border.all(color: context.colors.outlineVariant),
                    ),
                    child: Text(
                      location,
                      textAlign: TextAlign.center,
                      style: context.textStyles.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (error != null) ...<Widget>[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      error.toString(),
                      textAlign: TextAlign.center,
                      style: context.textStyles.bodySmall?.copyWith(
                        color: context.colors.outline,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xxl),
                  FilledButton.icon(
                    onPressed: () => context.go(AppRoutes.root),
                    icon: const Icon(
                      Icons.home_outlined,
                      size: AppDimensions.iconMd,
                    ),
                    label: Text(l10n.pageNotFoundAction),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
