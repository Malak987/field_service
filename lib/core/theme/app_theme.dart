import 'package:field_service/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// Builds the light and dark [ThemeData] of the application.
///
/// Scope: one consistent starting point shared by both modes — Material 3
/// colour roles, control shapes and field spacing — so that feature teams
/// extend the theme here instead of overriding styles widget by widget.
///
/// It is deliberately not a finished design system: no custom fonts, no
/// component library beyond what Material 3 provides. Touch targets stay large
/// and text styles stay readable because the app is used on site, often with
/// gloves or in bright sunlight.
abstract final class AppTheme {
  /// Corner radius shared by cards, fields and buttons.
  static const double _radius = 12;

  /// The light theme.
  static ThemeData get light => _build(Brightness.light);

  /// The dark theme.
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;
    final ColorScheme colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: brightness,
    );
    final Color borderColor = isDark
        ? AppColors.borderDark
        : AppColors.borderLight;
    final BorderRadius radius = BorderRadius.circular(_radius);

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: isDark
          ? AppColors.surfaceDark
          : AppColors.surfaceLight,

      // --- App bar ---------------------------------------------------------
      appBarTheme: AppBarThemeData(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
      ),

      // --- Cards and containers -------------------------------------------
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: borderColor),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: borderColor,
        thickness: 1,
        space: 1,
      ),

      // --- Inputs ----------------------------------------------------------
      // Sized for one-handed use on site: tall fields, clear focus state.
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: colorScheme.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: colorScheme.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: colorScheme.error),
        ),
      ),

      // --- Buttons ---------------------------------------------------------
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          // Full-width, thumb-friendly primary action.
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: radius),
          side: BorderSide(color: borderColor),
        ),
      ),
    );
  }
}
