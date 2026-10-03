import 'package:flutter/material.dart';

/// Shortcuts for the `Theme.of(context)` family.
///
/// These keep widget code readable (`context.textStyles.titleMedium` instead of
/// `Theme.of(context).textTheme.titleMedium`) without introducing a global theme
/// accessor: everything still resolves through the inherited widget, so themes
/// and tests behave exactly as in plain Flutter.
extension BuildContextX on BuildContext {
  /// The active [ThemeData].
  ThemeData get theme => Theme.of(this);

  /// The active [ColorScheme].
  ColorScheme get colors => theme.colorScheme;

  /// The active [TextTheme].
  TextTheme get textStyles => theme.textTheme;

  /// Whether the active theme is dark.
  bool get isDarkMode => theme.brightness == Brightness.dark;

  /// Current viewport size, without the space taken by the keyboard.
  Size get screenSize => MediaQuery.sizeOf(this);
}
