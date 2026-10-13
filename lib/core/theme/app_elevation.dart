import 'package:flutter/material.dart';

/// Elevation and shadow policy for the Heimwerk interface.
///
/// The product uses borders, tonal separation and generous spacing for normal
/// content; cards deliberately sit at [surface] elevation and never cast a
/// shadow. Shadows are reserved for controls that visibly float above the
/// work surface, such as the FAB and modal overlays.
abstract final class AppElevation {
  /// Default for cards, panels and list sections.
  static const double surface = 0;

  /// Floating action controls above scrollable content.
  static const double floating = 2;

  /// Menus, dialogs and bottom sheets.
  static const double overlay = 12;

  /// A restrained shadow for custom floating widgets that cannot use Material
  /// elevation. This must not be applied to regular cards or form sections.
  static const List<BoxShadow> floatingShadow = <BoxShadow>[
    BoxShadow(
      color: Color(0x240F0B09),
      blurRadius: 12,
      offset: Offset(0, 4),
    ),
  ];
}
