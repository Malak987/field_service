import 'package:flutter/widgets.dart';

/// Centralized corner radius tokens for buttons, inputs, cards, and badges.
///
/// Changing a token here updates the corner roundness across the entire
/// application without editing individual screens.
abstract final class AppRadius {
  // --- Raw radius values (in logical pixels) -------------------------------
  //
  // Deliberately restrained: a business tool reads as precise when corners are
  // tight. Inputs and compact controls sit at 10, sections and cards at 12,
  // and only overlays (dialogs, sheets) reach 16. Nothing here is a pill
  // except the elements that are genuinely pill-shaped (badges, filter chips).

  /// 4px — subtle rounding for small chips and tags.
  static const double xs = 4;

  /// 6px — compact controls and inline banners.
  static const double sm = 6;

  /// 8px — compact banners and small containers.
  static const double md = 8;

  /// 10px — standard radius for inputs and buttons.
  static const double field = 10;

  /// 12px — standard radius for cards, sections and large containers.
  static const double lg = 12;

  /// 16px — overlays only: dialogs, bottom sheets, the auth logo badge.
  static const double xl = 16;

  /// 999px — pill/circular elements.
  static const double pill = 999;

  // --- BorderRadius objects (for Material InputBorder / ShapeBorder) -------

  /// Standard input & button border radius (`10px`).
  static const BorderRadius control = BorderRadius.all(Radius.circular(field));

  /// Banner / small-container border radius (`8px`).
  static const BorderRadius banner = BorderRadius.all(Radius.circular(md));

  /// Standard card / large container border radius (`12px`).
  static const BorderRadius card = BorderRadius.all(Radius.circular(lg));

  /// Logo badge border radius (`16px`).
  static const BorderRadius logoBadge = BorderRadius.all(Radius.circular(xl));

  /// Pill border radius (`999px`).
  static const BorderRadius circular = BorderRadius.all(Radius.circular(pill));

  // --- Directional BorderRadius objects (RTL/LTR ready) --------------------

  /// Directional control border radius (`10px`).
  static const BorderRadiusDirectional controlDirectional =
      BorderRadiusDirectional.all(Radius.circular(field));

  /// Directional card border radius (`12px`).
  static const BorderRadiusDirectional cardDirectional =
      BorderRadiusDirectional.all(Radius.circular(lg));

  /// Directional banner border radius (`8px`).
  static const BorderRadiusDirectional bannerDirectional =
      BorderRadiusDirectional.all(Radius.circular(md));
}
