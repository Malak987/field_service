import 'package:flutter/material.dart';

/// The application's colour palette — the single source of truth for colour.
///
/// Technicians use this app indoors and outdoors, in bright daylight and in dim
/// rooms, so colours are defined once here and consumed through [ColorScheme] in
/// `app_theme.dart`. Widgets must never hardcode a `Color(0x...)` literal.
///
/// Phase 3 status: a starting palette with light and dark values. It is
/// intentionally small; brand refinements happen in `app_theme.dart` without
/// touching call sites.
abstract final class AppColors {
  /// Brand colour. Everything else is derived from it via
  /// `ColorScheme.fromSeed`.
  static const Color primary = Color(0xFF1B4B8F);

  // --- Semantic colours ----------------------------------------------------
  // Used by job status indicators, sync state and form validation later on.

  /// Completed / synced / valid.
  static const Color success = Color(0xFF2E7D32);

  /// Waiting, pending sync, deadline approaching.
  static const Color warning = Color(0xFFED6C02);

  /// Failure, destructive action, invalid input.
  static const Color error = Color(0xFFD32F2F);

  /// Neutral emphasis, hints and informational banners.
  static const Color info = Color(0xFF0288D1);

  // --- Neutral surfaces and separators -------------------------------------

  /// Page background in light mode (slightly off-white to let cards stand out).
  static const Color surfaceLight = Color(0xFFF6F7F9);

  /// Page background in dark mode.
  static const Color surfaceDark = Color(0xFF14161A);

  /// Hairline borders and dividers in light mode.
  static const Color borderLight = Color(0xFFE1E4E9);

  /// Hairline borders and dividers in dark mode.
  static const Color borderDark = Color(0xFF2A2F38);
}
