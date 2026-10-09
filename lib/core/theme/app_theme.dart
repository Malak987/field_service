import 'package:field_service/core/theme/app_colors.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_radius.dart';
import 'package:field_service/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';

/// Builds the single fixed brand [ThemeData] of the application.
///
/// The app deliberately ships ONE theme — a premium, warm "European field
/// service" identity: burgundy brand colour, warm gold accents, cream page
/// background and white surfaces. There is no dark mode and no theme toggle:
/// every screen uses exactly this visual identity, in every brightness
/// environment.
///
/// Brand roles are pinned from [AppColors] (never derived), so the brand
/// colour is exact. Feature pages consume the theme instead of overriding
/// styles widget by widget.
abstract final class AppTheme {
  /// Corner radius shared by inputs and buttons.
  static const double _radius = AppRadius.field;

  /// The one and only application theme.
  static ThemeData get light => _build();

  static ThemeData _build() {
    const Color brand = AppColors.primary;
    const Color brandPressed = AppColors.primaryDark;
    const Color accent = AppColors.goldAccent;
    const Color borderColor = AppColors.border;
    const Color cardSurface = AppColors.surface;
    const Color onSurfaceColor = AppColors.textPrimary;
    const Color onSurfaceVariantColor = AppColors.textSecondary;
    final BorderRadius radius = BorderRadius.circular(_radius);

    // Material 3 generates the full set of neutral/tonal roles from the
    // burgundy seed; the brand-critical roles are then pinned so the brand
    // colour is exact everywhere.
    final ColorScheme colorScheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.light,
        ).copyWith(
          primary: brand,
          onPrimary: const Color(0xFFFFFFFF),
          secondary: accent,
          onSecondary: const Color(0xFF2F2010),
          surface: cardSurface,
          onSurface: onSurfaceColor,
          onSurfaceVariant: onSurfaceVariantColor,
          outline: borderColor,
          outlineVariant: borderColor,
          error: AppColors.error,
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,

      scaffoldBackgroundColor: AppColors.background,
      textTheme: _textTheme(),

      // --- App bar ---------------------------------------------------------
      appBarTheme: AppBarThemeData(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: AppColors.primaryDark,
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
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: const BorderSide(color: borderColor),
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cardSurface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.lg),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF332723),
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
        indicatorColor: AppColors.primarySurface,
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
        foregroundColor: colorScheme.onPrimary,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),

      // --- Progress indicators ----------------------------------------------
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: brand,
        linearTrackColor: borderColor,
      ),

      // --- Text selection ---------------------------------------------------
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: brand,
        selectionColor: accent.withValues(alpha: 0.35),
        selectionHandleColor: brand,
      ),

      // --- Inputs ----------------------------------------------------------
      // Sized for one-handed use on site: tall white fields on the cream
      // canvas, hairline borders and a clear burgundy focus state.
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: cardSurface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        labelStyle: AppTextStyles.bodyLarge.copyWith(
          color: onSurfaceVariantColor,
        ),
        floatingLabelStyle: AppTextStyles.bodyMedium.copyWith(
          color: onSurfaceVariantColor,
        ),
        hintStyle: AppTextStyles.bodyLarge.copyWith(
          color: onSurfaceVariantColor,
        ),
        helperStyle: AppTextStyles.bodySmall.copyWith(
          color: onSurfaceVariantColor,
        ),
        errorStyle: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
        prefixIconColor: onSurfaceVariantColor,
        suffixIconColor: onSurfaceVariantColor,
        border: OutlineInputBorder(
          borderRadius: radius,
          borderSide: const BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: const BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(
            color: brand,
            width: AppDimensions.focusedBorderWidth,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(
            color: AppColors.error,
            width: AppDimensions.focusedBorderWidth,
          ),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: const BorderSide(color: borderColor),
        ),
      ),

      // --- Buttons ---------------------------------------------------------
      filledButtonTheme: FilledButtonThemeData(
        style:
            FilledButton.styleFrom(
              // Full-width, thumb-friendly primary action.
              minimumSize: const Size.fromHeight(AppDimensions.buttonHeight),
              backgroundColor: brand,
              foregroundColor: colorScheme.onPrimary,
              disabledForegroundColor: colorScheme.onPrimary.withValues(
                alpha: 0.85,
              ),
              disabledBackgroundColor: brand.withValues(alpha: 0.45),
              shape: RoundedRectangleBorder(borderRadius: radius),
              textStyle: AppTextStyles.buttonLabel,
            ).copyWith(
              // Pressed state deepens the burgundy instead of washing it out.
              overlayColor: WidgetStateProperty.resolveWith((
                Set<WidgetState> states,
              ) {
                if (states.contains(WidgetState.pressed)) {
                  return brandPressed;
                }
                return null;
              }),
            ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(AppDimensions.buttonHeight),
          foregroundColor: brand,
          backgroundColor: cardSurface,
          disabledForegroundColor: onSurfaceVariantColor,
          shape: RoundedRectangleBorder(borderRadius: radius),
          side: const BorderSide(color: borderColor),
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
          foregroundColor: onSurfaceColor,
        ),
      ),
    );
  }

  /// The [AppTextStyles] hierarchy mapped onto the Material [TextTheme]
  /// slots, so every widget that reads `Theme.of(context).textTheme` gets the
  /// same sizes and weights without importing the token class. Styles keep no
  /// colour here — Material resolves `onSurface` / `onSurfaceVariant` from
  /// the fixed colour scheme.
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
