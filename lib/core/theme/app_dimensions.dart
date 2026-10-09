/// Centralized sizing and responsive breakpoint tokens.
///
/// If button height, icon size, border thickness, or form width needs to change
/// across the application, edit it here once.
abstract final class AppDimensions {
  // --- Controls & Buttons --------------------------------------------------

  /// Standard height of primary and secondary action buttons (`52px`).
  static const double buttonHeight = 52;

  /// Compact control height (`44px`) for toolbar/header controls — also the
  /// minimum accessible touch target.
  static const double buttonHeightCompact = 44;

  /// Size of the loading spinner inside a button (`22px`).
  static const double buttonSpinnerSize = 22;

  /// Stroke width of the loading spinner (`2.2px`).
  static const double spinnerStrokeWidth = 2.2;

  // --- Borders -------------------------------------------------------------

  /// Standard border thickness for inputs, cards, and dividers (`1px`).
  static const double borderWidth = 1.0;

  /// Focused input border thickness (`1.6px`).
  static const double focusedBorderWidth = 1.6;

  // --- Icons & Logos -------------------------------------------------------

  /// Small inline icon size (`16px`) — e.g. password requirement checklist.
  static const double iconSm = 16;

  /// Standard field and button icon size (`20px`).
  static const double iconMd = 20;

  /// Prominent icon size (`24px`).
  static const double iconLg = 24;

  /// Empty-state / error illustration icon size (`48px`).
  static const double iconXl = 48;

  /// Rendered width of the brand logo on authentication screens (`148px`).
  /// The asset keeps its own aspect ratio (≈ 0.92 height/width).
  static const double authLogoWidth = 148;

  // --- Responsive Layout Constraints ---------------------------------------

  /// Maximum width of the authentication form column (`440px`).
  static const double authFormMaxWidth = 440;

  /// Breakpoint below which compact mobile spacing is used (`380px`).
  static const double compactMobileBreakpoint = 380;

  /// Breakpoint above which tablet/desktop padding applies (`600px`).
  static const double tabletBreakpoint = 600;
}
