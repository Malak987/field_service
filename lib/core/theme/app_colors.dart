import 'package:flutter/material.dart';

/// The application's colour palette — the single source of truth for colour.
///
/// The app ships with ONE fixed brand theme (no light/dark variants): a warm,
/// premium European field-service identity built on burgundy, warm gold and a
/// cream background. Widgets must never hardcode a `Color(0x...)` literal;
/// they consume colours through [ColorScheme] in `app_theme.dart` or through
/// the tokens below for brand moments the scheme does not cover.
abstract final class AppColors {
  // --- Brand core -----------------------------------------------------------

  /// Brand colour — primary burgundy. Primary buttons, main CTAs, selected
  /// navigation and primary accents.
  static const Color primary = Color(0xFF7B1E28);

  /// Brand colour — deep burgundy. Pressed states, strong headings and
  /// deeper visual accents.
  static const Color primaryDark = Color(0xFF5C151D);

  /// Warm gold accent — logo highlights, small highlights, selected
  /// indicators and decorative details. Never the base colour of a button.
  static const Color goldAccent = Color(0xFFC89F6A);

  /// Deep gold for text/icons on light gold washes (contrast-safe accent).
  static const Color goldDeep = Color(0xFF8A6A3B);

  // --- Neutrals -------------------------------------------------------------

  /// Page background (warm cream so white surfaces stand out).
  static const Color background = Color(0xFFF6F1E7);

  /// Elevated card / input / dialog surface (pure white).
  static const Color surface = Color(0xFFFFFFFF);

  /// Primary text (headings, body copy, input values).
  ///
  /// A near-black neutral (not a warm brown) so long German body copy stays
  /// crisp on the cream canvas: contrast against [background] is ~12.4:1 and
  /// against [surface] ~14.9:1.
  static const Color textPrimary = Color(0xFF242424);

  /// Secondary text (hints, captions, subtitles, helper text).
  /// Contrast ~7.3:1 on [surface] — still above the AAA body threshold.
  static const Color textSecondary = Color(0xFF55504B);

  /// Tertiary text: metadata, timestamps, unit suffixes. Only ever used at
  /// `bodySmall` size or larger, where it still clears 4.5:1 on [surface].
  static const Color textTertiary = Color(0xFF7A736C);

  /// Hairline borders and dividers (warm neutral).
  static const Color border = Color(0xFFE5DDD2);

  /// Stronger border for separating major sections and for the hairline under
  /// a light app bar, where [border] alone disappears against [background].
  static const Color borderStrong = Color(0xFFD8CFC2);

  /// Muted surface: table headers, inset panels, disabled field fills. One
  /// step below [surface] so a section can be inset without a second card.
  static const Color surfaceMuted = Color(0xFFFBF8F2);

  /// Foreground that always sits on top of [primary] / [primaryDark].
  static const Color onBrand = Color(0xFFFFFFFF);

  /// Burgundy wash strong enough to carry a selected row or an active filter
  /// chip without becoming a second card.
  static const Color brandContainer = Color(0x1F7B1E28);

  // --- Semantic colours -----------------------------------------------------
  // Used by job status indicators, sync state and form validation.

  /// Completed / synced / valid.
  static const Color success = Color(0xFF2E7D32);

  /// Waiting, pending sync, deadline approaching.
  static const Color warning = Color(0xFFED6C02);

  /// Failure, destructive action, invalid input.
  static const Color error = Color(0xFFD32F2F);

  /// Neutral emphasis, hints and informational banners.
  static const Color info = Color(0xFF0288D1);

  // --- Tinted status surfaces ----------------------------------------------
  // Background washes behind success/warning/error/primary chips, banners and
  // badges. The alpha channel keeps them readable over the white surface.

  /// Success wash (synced, completed).
  static const Color successSurface = Color(0x142E7D32);

  /// Warning wash (pending, deadline approaching).
  static const Color warningSurface = Color(0x14ED6C02);

  /// Error wash (failures, destructive confirmations).
  static const Color errorSurface = Color(0x14D32F2F);

  /// Primary wash (selected states, informational chips).
  static const Color primarySurface = Color(0x147B1E28);

  /// Gold wash (accent chips, timeline markers).
  static const Color goldSurface = Color(0x1AC89F6A);
}
