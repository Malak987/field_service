import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/theme/app_colors.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_radius.dart';
import 'package:flutter/material.dart';

/// Branded emblem displayed at the top of authentication screens.
class AuthLogo extends StatelessWidget {
  const AuthLogo({this.icon = Icons.handyman_outlined, super.key});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final bool isDark = context.isDarkMode;
    final ColorScheme colors = context.colors;
    final Color accent = isDark
        ? AppColors.goldAccentDarkVariant
        : AppColors.goldAccent;

    // Brand mark: solid burgundy badge (lightened variant in dark mode for
    // contrast) with the theme's `onPrimary` glyph and a gold ring — the
    // same pairing the rest of the app uses for brand moments.
    return Center(
      child: Container(
        width: AppDimensions.authLogoContainerSize,
        height: AppDimensions.authLogoContainerSize,
        decoration: BoxDecoration(
          color: colors.primary,
          borderRadius: AppRadius.logoBadge,
          border: Border.all(color: accent.withValues(alpha: 0.9), width: 1.5),
        ),
        alignment: AlignmentDirectional.center,
        child: Icon(
          icon,
          size: AppDimensions.authLogoIconSize,
          color: colors.onPrimary,
        ),
      ),
    );
  }
}
