import 'package:field_service/core/theme/app_colors.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_radius.dart';
import 'package:field_service/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';

/// Builds the light and dark [ThemeData] of the application.
///
/// Scope: one consistent design system shared by both modes — brand colour
/// roles, the [AppTextStyles] hierarchy, control shapes and field spacing —
/// so that feature pages consume the theme instead of overriding styles
/// widget by widget.
///
/// Brand: burgundy ([AppColors.primary]) with a warm gold accent
/// ([AppColors.goldAccent]) on a cream light / charcoal dark surface. Touch
/// targets stay large and text styles stay readable because the app is used
/// on site, often with gloves or in bright sunlight.
abstract final class AppTheme {
  /// Corner radius shared by cards, fields and buttons.
  static const double _radius = AppRadius.md;

  /// The light theme.
  static ThemeData get light => _build(Brightness.light);

  /// The dark theme.
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;
    final Color brand = isDark
        ? AppColors.primaryDarkVariant
        : AppColors.primary;
    final Color accent = isDark
        ? AppColors.goldAccentDarkVariant
        : AppColors.goldAccent;
    final Color onBrand = isDark
        ? const Color(0xFF331216)
        : const Color(0xFFFFFFFF);
    final Color onAccent = const Color(0xFF2F2010);
    final Color borderColor = isDark
        ? AppColors.borderDark
        : AppColors.borderLight;
    final Color cardSurface = isDark ? AppColors.cardDark : AppColors.cardLight;
    final Color onSurfaceColor = isDark
        ? const Color(0xFFEDEDED)
        : const Color(0xFF211A17);
    final Color onSurfaceVariantColor = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondaryLight;
    final BorderRadius radius = BorderRadius.circular(_radius);

    // Material 3 generates the full set of neutral/tonal roles from the
    // burgundy seed; the brand-critical roles are then pinned so the brand
    // colour is exact in both modes.
    final ColorScheme colorScheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: brightness,
        ).copyWith(
          primary: brand,
          onPrimary: onBrand,
          secondary: accent,
          onSecondary: onAccent,
          surface: cardSurface,
          onSurface: onSurfaceColor,
          onSurfaceVariant: onSurfaceVariantColor,
          outline: borderColor,
          outlineVariant: borderColor,
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: isDark
          ? AppColors.surfaceDark
          : AppColors.surfaceLight,
      textTheme: _textTheme(),

      // --- App bar ---------------------------------------------------------
      appBarTheme: AppBarThemeData(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: isDark
            ? AppColors.surfaceDark
            : AppColors.surfaceLight,
        foregroundColor: onSurfaceColor,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: _textTheme().titleLarge,
      ),

      // --- Cards and containers -------------------------------------------
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: cardSurface,
        surfaceTintColor: Colors.transparent,
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

      // --- Dialogs & sheets -------------------------------------------------
      dialogTheme: DialogThemeData(
        backgroundColor: cardSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cardSurface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(_radius)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark
            ? const Color(0xFF2E2E2E)
            : const Color(0xFF332723),
        contentTextStyle: AppTextStyles.bodyMedium.copyWith(
          color: const Color(0xFFF7F3EE),
        ),
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),

      // --- Bottom navigation (role shells) ----------------------------------
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 0,
        backgroundColor: cardSurface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: isDark
            ? AppColors.primarySurfaceDark
            : AppColors.primarySurfaceLight,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) => AppTextStyles.bodySmall.copyWith(
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? brand
                : onSurfaceVariantColor,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) => IconThemeData(
            size: AppDimensions.iconLg,
            color: states.contains(WidgetState.selected)
                ? brand
                : onSurfaceVariantColor,
          ),
        ),
      ),

      // --- Floating action button -------------------------------------------
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: brand,
        foregroundColor: onBrand,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),

      // --- Inputs ----------------------------------------------------------
      // Sized for one-handed use on site: tall fields, clear focus state.
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: cardSurface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        labelStyle: AppTextStyles.bodyLarge,
        hintStyle: AppTextStyles.bodyLarge.copyWith(
          color: onSurfaceVariantColor,
        ),
        errorStyle: AppTextStyles.bodySmall.copyWith(color: colorScheme.error),
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
          borderSide: BorderSide(color: brand, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: colorScheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: colorScheme.error, width: 1.6),
        ),
      ),

      // --- Buttons ---------------------------------------------------------
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          // Full-width, thumb-friendly primary action.
          minimumSize: const Size.fromHeight(AppDimensions.buttonHeight),
          backgroundColor: brand,
          foregroundColor: onBrand,
          disabledBackgroundColor: isDark
              ? const Color(0xFF3A3A3A)
              : borderColor,
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: AppTextStyles.buttonLabel,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(AppDimensions.buttonHeight),
          foregroundColor: brand,
          shape: RoundedRectangleBorder(borderRadius: radius),
          side: BorderSide(color: borderColor),
          textStyle: AppTextStyles.buttonLabel,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: brand,
          minimumSize: const Size(
            AppDimensions.buttonHeightCompact,
            AppDimensions.buttonHeightCompact,
          ),
          textStyle: AppTextStyles.linkLabel,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size.square(AppDimensions.buttonHeightCompact),
          iconSize: AppDimensions.iconMd,
        ),
      ),
    );
  }

  /// The [AppTextStyles] hierarchy mapped onto the Material [TextTheme]
  /// slots, so every widget that reads `Theme.of(context).textTheme` gets the
  /// same sizes and weights without importing the token class. Styles keep no
  /// colour here — Material resolves `onSurface` / `onSurfaceVariant` from
  /// the colour scheme, which keeps dark mode correct automatically.
  static TextTheme _textTheme() {
    return const TextTheme(
      headlineMedium: AppTextStyles.headlineMedium,
      titleLarge: AppTextStyles.titleLarge,
      titleMedium: AppTextStyles.titleMedium,
      titleSmall: AppTextStyles.titleSmall,
      bodyLarge: AppTextStyles.bodyLarge,
      bodyMedium: AppTextStyles.bodyMedium,
      bodySmall: AppTextStyles.bodySmall,
      labelLarge: AppTextStyles.buttonLabel,
      labelMedium: AppTextStyles.linkLabel,
    );
  }
}
