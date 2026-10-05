import 'package:flutter/material.dart';

/// Centralized typography scale used across the application.
///
/// Consumed by `AppTheme` to populate the Material `TextTheme` and control
/// styles, keeping font sizes, weights, and line heights in one place.
abstract final class AppTextStyles {
  /// Main screen title (e.g., Login / Register header).
  static const TextStyle headlineMedium = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w700,
    height: 1.25,
    letterSpacing: -0.3,
  );

  /// Section title.
  static const TextStyle titleLarge = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  /// Card title / important label.
  static const TextStyle titleMedium = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );

  /// Subtitle / small heading.
  static const TextStyle titleSmall = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.4,
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
  );

  /// Primary and secondary button label style.
  static const TextStyle buttonLabel = TextStyle(
    fontSize: 15.5,
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
