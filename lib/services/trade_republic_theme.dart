import 'package:flutter/material.dart';

import 'cultioo_desktop_layout.dart';

/// Shared Trade Republic design constants
/// Use these everywhere for a consistent, normalized look
class TradeRepublicTheme {
  TradeRepublicTheme._();

  /// Native macOS / Windows / Linux (not web): tighter chrome than phones.
  static bool get _desktopCompact => CultiooDesktopLayout.isDesktopPlatform;

  // ─── Border Radius ───────────────────────────────────────
  static const double radiusSmall = 10.0;
  static const double radiusMedium = 14.0;
  static const double radiusLarge = 18.0;
  static const double radiusXL = 24.0;

  static final BorderRadius borderRadiusSmall =
      BorderRadius.circular(radiusSmall);
  static final BorderRadius borderRadiusMedium =
      BorderRadius.circular(radiusMedium);
  static final BorderRadius borderRadiusLarge =
      BorderRadius.circular(radiusLarge);
  static final BorderRadius borderRadiusXL = BorderRadius.circular(radiusXL);

  /// Cards, text fields — smaller radius on desktop.
  static BorderRadius get surfaceBorderRadius => BorderRadius.circular(
        _desktopCompact ? radiusMedium : radiusLarge,
      );

  // ─── Spacing ─────────────────────────────────────────────
  static const double spacingXS = 4.0;
  static const double spacingS = 8.0;
  static const double spacingM = 12.0;
  static const double spacingL = 16.0;
  static const double spacingXL = 20.0;
  static const double spacingXXL = 24.0;

  // ─── Colors ──────────────────────────────────────────────
  /// Dark mode background (bottom sheets, cards)
  static const Color darkBackground = Color(0xFF000000);

  /// Dark mode card/surface color (strict monochrome).
  static const Color darkSurface = Color(0xFF000000);

  /// Dark mode elevated surface
  static const Color darkElevated = Color(0xFF000000);

  /// Light mode background
  static const Color lightBackground = Colors.white;

  /// Light mode surface
  static const Color lightSurface = Colors.white;

  /// Accent color in strict monochrome mode
  static const Color accentGreen = Colors.black;

  /// Destructive actions remain monochrome in this style
  static const Color destructiveRed = Colors.black;

  // ─── Helpers ─────────────────────────────────────────────

  /// Get the main text color for current brightness
  static Color textColor(BuildContext context) {
    return _isLight(context) ? Colors.black : Colors.white;
  }

  /// Get a subdued text color (for hints, labels, placeholders)
  static Color hintColor(BuildContext context, {double opacity = 0.4}) {
    return textColor(context).withValues(alpha: opacity);
  }

  /// Get the fill color for text fields / cards
  static Color fillColor(BuildContext context, {double opacity = 0.05}) {
    return textColor(context).withValues(alpha: opacity);
  }

  /// Get the surface/card background
  static Color surfaceColor(BuildContext context) {
    return _isLight(context) ? lightSurface : darkSurface;
  }

  /// Get the main background
  static Color backgroundColor(BuildContext context) {
    return _isLight(context) ? lightBackground : darkBackground;
  }

  /// Get icon color with default opacity
  static Color iconColor(BuildContext context, {double opacity = 0.5}) {
    return textColor(context).withValues(alpha: opacity);
  }

  /// Get the selection accent color — white in dark mode, black in light mode
  static Color selectedColor(BuildContext context) => textColor(context);

  /// Subtle highlight (e.g. list hint). Prefer [selectionContainerBackground] for
  /// a clear “selected” chip / row (solid inverted fill).
  static Color selectedBackgroundColor(BuildContext context) =>
      textColor(context).withValues(alpha: 0.10);

  /// Solid fill for a **selected** chip, row, or tab (Trade Republic inverted).
  /// Light mode → black; dark mode → white.
  static Color selectionContainerBackground(BuildContext context) =>
      _isLight(context) ? Colors.black : Colors.white;

  /// Text and icons on [selectionContainerBackground].
  static Color selectionContainerForeground(BuildContext context) =>
      _isLight(context) ? Colors.white : Colors.black;

  /// Is the current theme light?
  static bool _isLight(BuildContext context) {
    return Theme.of(context).brightness == Brightness.light;
  }

  /// Convenience: is light mode
  static bool isLight(BuildContext context) => _isLight(context);

  // ─── Text Styles ─────────────────────────────────────────

  /// Large title style (e.g., bottom sheet title)
  static TextStyle titleLarge(BuildContext context) => TextStyle(
      fontSize: _desktopCompact ? 24 : 28,
      fontWeight: FontWeight.w800,
      letterSpacing: _desktopCompact ? -0.65 : -0.8,
        color: textColor(context),
      );

  /// Medium title style (e.g., section headers)
  static TextStyle titleMedium(BuildContext context) => TextStyle(
      fontSize: _desktopCompact ? 18 : 22,
      fontWeight: FontWeight.w800,
      letterSpacing: _desktopCompact ? -0.55 : -0.7,
        color: textColor(context),
      );

  /// Small title / label style
  static TextStyle titleSmall(BuildContext context) => TextStyle(
      fontSize: _desktopCompact ? 14 : 15,
      fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: textColor(context),
      );

  /// Body text
  static TextStyle bodyMedium(BuildContext context) => TextStyle(
        fontSize: _desktopCompact ? 14 : 16,
        fontWeight: FontWeight.w500,
        color: textColor(context),
      );

  /// Small body / caption text
  static TextStyle bodySmall(BuildContext context) => TextStyle(
        fontSize: _desktopCompact ? 12 : 13,
        fontWeight: FontWeight.w400,
        color: hintColor(context, opacity: 0.6),
      );

  /// Input text style (inside text fields)
  static TextStyle inputStyle(BuildContext context) => TextStyle(
        fontSize: _desktopCompact ? 13 : 16,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.2,
        color: textColor(context),
      );

  /// Hint style for inputs
  static TextStyle inputHintStyle(BuildContext context) => TextStyle(
        fontSize: _desktopCompact ? 13 : 16,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.2,
        color: hintColor(context, opacity: 0.3),
      );

  /// Text fields: tighter corner than cards on desktop.
  static BorderRadius get inputSurfaceBorderRadius => BorderRadius.circular(
        _desktopCompact ? radiusSmall : radiusLarge,
      );
}
