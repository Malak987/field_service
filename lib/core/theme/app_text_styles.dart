import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

/// Centralized typography scale used across the application.
///
/// Consumed by `AppTheme` to populate the Material `TextTheme` and control
/// styles, keeping font sizes, weights, and line heights in one place.
abstract final class AppTextStyles {
  /// Main screen title (e.g., Login / Register header).
  ///
  /// Kept at 22px on purpose: a field-service screen has to fit a greeting,
  /// a job list and an action without the heading eating the viewport.
  static const TextStyle headlineMedium = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    height: 1.25,
    letterSpacing: -0.2,
  );

  /// Prominent figures in a dashboard or a summary row.
  ///
  /// Tabular figures prevent a changing count (for example, 9 → 10 jobs) from
  /// making an otherwise stable stat layout visibly jump.
  static const TextStyle metric = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w700,
    height: 1.1,
    letterSpacing: -0.35,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  );

  /// Section title / app bar title.
  static const TextStyle titleLarge = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w700,
    height: 1.3,
    letterSpacing: -0.1,
  );

  /// Card title / important label.
  static const TextStyle titleMedium = TextStyle(
    fontSize: 15.5,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );

  /// Subtitle / small heading — also the section-label size, where the slight
  /// tracking separates a label from the content it heads without resorting
  /// to all-caps.
  static const TextStyle titleSmall = TextStyle(
    fontSize: 13.5,
    fontWeight: FontWeight.w700,
    height: 1.4,
    letterSpacing: 0.1,
  );

  /// Primary body copy and input text.
  static const TextStyle bodyLarge = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.45,
  );

  /// Secondary body copy and subtitles.
  static const TextStyle bodyMedium = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.45,
  );

  /// Helper text, captions, and password requirement items.
  static const TextStyle bodySmall = TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w400,
    height: 1.4,
    letterSpacing: 0.05,
  );

  /// Compact status labels, chips and metadata badges.
  static const TextStyle badgeLabel = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: 0.1,
  );

  /// Primary and secondary button label style.
  static const TextStyle buttonLabel = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.2,
    letterSpacing: 0.1,
  );

  /// Compact button / link label style.
  static const TextStyle linkLabel = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );
}
