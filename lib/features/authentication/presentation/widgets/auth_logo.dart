import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:flutter/material.dart';

/// Branded emblem displayed at the top of authentication screens.
///
/// Uses the final brand asset (`assets/brand/logo.png`): the burgundy house /
/// wrench mark with the HEIMWERK wordmark and gold tagline. The asset already
/// ships with a transparent background, so it sits cleanly on the cream canvas.
class AuthLogo extends StatelessWidget {
  const AuthLogo({super.key});

  /// Bundled brand logo asset, relative to the pubspec `assets/` root.
  static const String assetName = 'assets/brand/logo.png';

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return Center(
      child: Image.asset(
        assetName,
        width: AppDimensions.authLogoWidth,
        fit: BoxFit.contain,
        // The wordmark is part of the bitmap; give screen readers the brand
        // name instead of skipping the image.
        semanticLabel: l10n.appName,
      ),
    );
  }
}
