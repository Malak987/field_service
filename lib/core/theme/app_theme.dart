import 'package:field_service/core/theme/app_colors.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_radius.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';

/// Builds the light and dark [ThemeData] of the application.
///
/// Scope: one consistent starting point shared by both modes — Material 3
/// colour roles, control shapes and field spacing — so that feature teams
/// extend the theme here instead of overriding styles widget by widget.
abstract final class AppTheme {
  /// The light theme.
  static ThemeData get light => _build(Brightness.light);

  /// The dark theme.
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;
    final ColorScheme colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: brightness,
      error: AppColors.error,
    );
    final Color borderColor = isDark
        ? AppColors.borderDark
        : AppColors.borderLight;
    final Color cardColor = isDark ? AppColors.cardDark : AppColors.cardLight;
    final Color secondaryTextColor = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondaryLight;

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: isDark
          ? AppColors.surfaceDark
          : AppColors.surfaceLight,

      // --- Typography ------------------------------------------------------
      textTheme: TextTheme(
        headlineMedium: AppTextStyles.headlineMedium.copyWith(
          color: colorScheme.onSurface,
        ),
        titleLarge: AppTextStyles.titleLarge.copyWith(
          color: colorScheme.onSurface,
        ),
        titleMedium: AppTextStyles.titleMedium.copyWith(
          color: colorScheme.onSurface,
        ),
        titleSmall: AppTextStyles.titleSmall.copyWith(
          color: colorScheme.onSurface,
        ),
        bodyLarge: AppTextStyles.bodyLarge.copyWith(
          color: colorScheme.onSurface,
        ),
        bodyMedium: AppTextStyles.bodyMedium.copyWith(
          color: secondaryTextColor,
        ),
        bodySmall: AppTextStyles.bodySmall.copyWith(
          color: secondaryTextColor,
        ),
        labelLarge: AppTextStyles.buttonLabel,
      ),

      // --- App bar ---------------------------------------------------------
      appBarTheme: AppBarThemeData(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: cardColor,
        foregroundColor: colorScheme.onSurface,
      ),

      // --- Cards and containers -------------------------------------------
      cardTheme: CardThemeData(
        elevation: 0,
        color: cardColor,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.card,
          side: BorderSide(
            color: borderColor,
            width: AppDimensions.borderWidth,
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: borderColor,
        thickness: AppDimensions.borderWidth,
        space: AppDimensions.borderWidth,
      ),

      // --- Inputs ----------------------------------------------------------
      // Sized for one-handed use on site: tall fields, clear focus state.
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: cardColor,
        contentPadding: AppSpacing.inputContentPadding,
        border: OutlineInputBorder(
          borderRadius: AppRadius.control,
          borderSide: BorderSide(
            color: borderColor,
            width: AppDimensions.borderWidth,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.control,
          borderSide: BorderSide(
            color: borderColor,
            width: AppDimensions.borderWidth,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.control,
          borderSide: BorderSide(
            color: colorScheme.primary,
            width: AppDimensions.focusedBorderWidth,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.control,
          borderSide: BorderSide(
            color: colorScheme.error,
            width: AppDimensions.borderWidth,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadius.control,
          borderSide: BorderSide(
            color: colorScheme.error,
            width: AppDimensions.focusedBorderWidth,
          ),
        ),
        errorMaxLines: 2,
      ),

      // --- Buttons ---------------------------------------------------------
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(AppDimensions.buttonHeight),
          padding: AppSpacing.buttonPadding,
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadius.control,
          ),
          textStyle: AppTextStyles.buttonLabel,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(AppDimensions.buttonHeight),
          padding: AppSpacing.buttonPadding,
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadius.control,
          ),
          side: BorderSide(
            color: borderColor,
            width: AppDimensions.borderWidth,
          ),
          textStyle: AppTextStyles.buttonLabel,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: AppTextStyles.linkLabel,
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadius.control,
          ),
        ),
      ),
    );
  }
}
