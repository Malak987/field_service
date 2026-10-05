import 'package:flutter/widgets.dart';

/// Centralized spacing scale used across all features and reusable widgets.
///
/// Using a single spacing scale prevents arbitrary numbers (`EdgeInsets.all(17)`)
/// and ensures directional (`EdgeInsetsDirectional`) layouts work seamlessly
/// across LTR (English, German) and future RTL (Arabic) locales.
abstract final class AppSpacing {
  // --- Raw spacing tokens (in logical pixels) ------------------------------

  /// 2px — hairline gap.
  static const double xxs = 2;

  /// 4px — tight inline spacing.
  static const double xs = 4;

  /// 8px — small gap between related elements.
  static const double sm = 8;

  /// 12px — compact vertical spacing between controls.
  static const double md = 12;

  /// 16px — standard spacing between form fields and inside cards.
  static const double lg = 16;

  /// 20px — comfortable section padding.
  static const double xl = 20;

  /// 24px — standard screen padding and card inner padding.
  static const double xxl = 24;

  /// 32px — major vertical separation between sections.
  static const double xxxl = 32;

  /// 40px — hero / header vertical separation.
  static const double huge = 40;

  // --- Reusable directional EdgeInsets presets -----------------------------

  /// Standard page outer padding (`24px` all around).
  static const EdgeInsetsDirectional pagePadding = EdgeInsetsDirectional.all(
    xxl,
  );

  /// Compact page padding on narrow mobile screens (`16px` horizontal, `24px` vertical).
  static const EdgeInsetsDirectional pagePaddingCompact =
      EdgeInsetsDirectional.symmetric(
        horizontal: lg,
        vertical: xxl,
      );

  /// Inner padding of the authentication form container (`24px` all around).
  static const EdgeInsetsDirectional formContainerPadding =
      EdgeInsetsDirectional.all(xxl);

  /// Inner padding of the authentication form container on tablet/desktop (`32px`).
  static const EdgeInsetsDirectional formContainerPaddingLarge =
      EdgeInsetsDirectional.all(xxxl);

  /// Standard text input content padding (`16px` start/end, `14px` top/bottom).
  static const EdgeInsetsDirectional inputContentPadding =
      EdgeInsetsDirectional.symmetric(
        horizontal: lg,
        vertical: 14,
      );

  /// Standard alert banner padding (`16px` horizontal, `12px` vertical).
  static const EdgeInsetsDirectional bannerPadding =
      EdgeInsetsDirectional.symmetric(
        horizontal: lg,
        vertical: md,
      );

  /// Button internal horizontal padding.
  static const EdgeInsetsDirectional buttonPadding =
      EdgeInsetsDirectional.symmetric(
        horizontal: xxl,
        vertical: md,
      );
}
