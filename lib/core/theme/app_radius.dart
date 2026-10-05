import 'package:flutter/widgets.dart';

/// Centralized corner radius tokens for buttons, inputs, cards, and badges.
///
/// Changing a token here updates the corner roundness across the entire
/// application without editing individual screens.
abstract final class AppRadius {
  // --- Raw radius values (in logical pixels) -------------------------------

  /// 6px — subtle rounding for small chips and tags.
  static const double xs = 6;

  /// 8px — compact controls and inline banners.
  static const double sm = 8;

  /// 12px — standard radius for inputs and buttons.
  static const double md = 12;

  /// 16px — standard radius for cards and form containers.
  static const double lg = 16;

  /// 20px — prominent containers and modals.
  static const double xl = 20;

  /// 999px — pill/circular elements.
  static const double pill = 999;

  // --- BorderRadius objects (for Material InputBorder / ShapeBorder) -------

  /// Standard input & button border radius (`12px`).
  static const BorderRadius control = BorderRadius.all(Radius.circular(md));

  /// Standard card / form container border radius (`16px`).
  static const BorderRadius card = BorderRadius.all(Radius.circular(lg));

  /// Alert banner border radius (`12px`).
  static const BorderRadius banner = BorderRadius.all(Radius.circular(md));

  /// Logo badge border radius (`20px`).
  static const BorderRadius logoBadge = BorderRadius.all(Radius.circular(xl));

  /// Pill border radius (`999px`).
  static const BorderRadius circular = BorderRadius.all(Radius.circular(pill));

  // --- Directional BorderRadius objects (RTL/LTR ready) --------------------

  /// Directional control border radius (`12px`).
  static const BorderRadiusDirectional controlDirectional =
      BorderRadiusDirectional.all(Radius.circular(md));

  /// Directional card border radius (`16px`).
  static const BorderRadiusDirectional cardDirectional =
      BorderRadiusDirectional.all(Radius.circular(lg));

  /// Directional banner border radius (`12px`).
  static const BorderRadiusDirectional bannerDirectional =
      BorderRadiusDirectional.all(Radius.circular(md));
}
