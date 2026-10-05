import 'package:flutter/material.dart';

/// The application's colour palette — the single source of truth for colour.
///
/// Technicians use this app indoors and outdoors, in bright daylight and in dim
/// rooms, so colours are defined once here and consumed through [ColorScheme] in
/// `app_theme.dart`. Widgets must never hardcode a `Color(0x...)` literal.
abstract final class AppColors {
  /// Brand colour. Everything else is derived from it via
  /// `ColorScheme.fromSeed`.
  static const Color primary = Color(0xFF1B4B8F);

  /// Darker shade of the primary brand colour for gradients and pressed states.
  static const Color primaryDark = Color(0xFF123363);

  /// Subtle primary container background in light mode.
  static const Color primarySurfaceLight = Color(0xFFEAF0F9);

  /// Subtle primary container background in dark mode.
  static const Color primarySurfaceDark = Color(0xFF1D2C45);

  // --- Semantic colours ----------------------------------------------------
  // Used by job status indicators, sync state and form validation.

  /// Completed / synced / valid.
  static const Color success = Color(0xFF2E7D32);

  /// Subtle background for success banners in light mode.
  static const Color successSurfaceLight = Color(0xFFEBF5EC);

  /// Subtle background for success banners in dark mode.
  static const Color successSurfaceDark = Color(0xFF192E1B);

  /// Waiting, pending sync, deadline approaching.
  static const Color warning = Color(0xFFED6C02);

  /// Subtle background for warning banners in light mode.
  static const Color warningSurfaceLight = Color(0xFFFFF4E5);

  /// Subtle background for warning banners in dark mode.
  static const Color warningSurfaceDark = Color(0xFF332211);

  /// Failure, destructive action, invalid input.
  static const Color error = Color(0xFFD32F2F);

  /// Subtle background for error banners in light mode.
  static const Color errorSurfaceLight = Color(0xFFFDECEA);

  /// Subtle background for error banners in dark mode.
  static const Color errorSurfaceDark = Color(0xFF361B1B);

  /// Neutral emphasis, hints and informational banners.
  static const Color info = Color(0xFF0288D1);

  // --- Neutral surfaces and separators -------------------------------------

  /// Page background in light mode (slightly off-white to let cards stand out).
  static const Color surfaceLight = Color(0xFFF6F7F9);

  /// Card / form container background in light mode.
  static const Color cardLight = Color(0xFFFFFFFF);

  /// Page background in dark mode.
  static const Color surfaceDark = Color(0xFF14161A);

  /// Card / form container background in dark mode.
  static const Color cardDark = Color(0xFF1D2026);

  /// Hairline borders and dividers in light mode.
  static const Color borderLight = Color(0xFFE1E4E9);

  /// Hairline borders and dividers in dark mode.
  static const Color borderDark = Color(0xFF2A2F38);

  /// Muted secondary text in light mode.
  static const Color textSecondaryLight = Color(0xFF5A6474);

  /// Muted secondary text in dark mode.
  static const Color textSecondaryDark = Color(0xFFA0AAB8);
}
