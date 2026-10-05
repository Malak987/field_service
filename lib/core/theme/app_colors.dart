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

  // --- Elevated card surfaces ----------------------------------------------

  /// Card / form-container background in light mode (pure white so it stands
  /// out from [surfaceLight]).
  static const Color cardLight = Color(0xFFFFFFFF);

  /// Card / form-container background in dark mode (raised above
  /// [surfaceDark]).
  static const Color cardDark = Color(0xFF1D2129);

  /// Secondary text (hints, captions, requirement lines) in light mode.
  static const Color textSecondaryLight = Color(0xFF6B7280);

  /// Secondary text in dark mode.
  static const Color textSecondaryDark = Color(0xFF9CA3AF);

  // --- Tinted status surfaces -------------------------------------------------
  // Background washes behind success/warning/error/primary chips, banners and
  // badges. The alpha channel keeps them readable over both card tones, so
  // each semantic colour gets a light and a dark variant.

  /// Success wash (synced, completed) in light mode.
  static const Color successSurfaceLight = Color(0x142E7D32);

  /// Success wash in dark mode.
  static const Color successSurfaceDark = Color(0x332E7D32);

  /// Warning wash (pending, deadline approaching) in light mode.
  static const Color warningSurfaceLight = Color(0x14ED6C02);

  /// Warning wash in dark mode.
  static const Color warningSurfaceDark = Color(0x33ED6C02);

  /// Error wash (failures, destructive confirmations) in light mode.
  static const Color errorSurfaceLight = Color(0x14D32F2F);

  /// Error wash in dark mode.
  static const Color errorSurfaceDark = Color(0x33D32F2F);

  /// Primary/info wash (selected states, informational chips) in light mode.
  static const Color primarySurfaceLight = Color(0x141B4B8F);

  /// Primary/info wash in dark mode.
  static const Color primarySurfaceDark = Color(0x331B4B8F);
}
