import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';

/// Shared spacing and limits for Cultioo **desktop** (macOS / Windows / Linux).
class CultiooDesktopLayout {
  CultiooDesktopLayout._();

  /// macOS / Windows / Linux (not web, not iOS/Android).
  static bool get isDesktopPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);

  /// Inner canvas (toolbars / slivers) — pure monochrome so no gray “mat” behind content.
  static Color contentCanvasColor(bool isDark) =>
      isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF);

  /// Desktop chrome: slightly smaller type than phone while keeping relative a11y scaling.
  static const double desktopUiTextScaleFactor = 0.88;

  static TextScaler desktopUiTextScaler(BuildContext context) {
    final t = MediaQuery.textScalerOf(context);
    final parent = t.scale(14.0) / 14.0;
    return TextScaler.linear(parent * desktopUiTextScaleFactor);
  }

  /// Standard page padding: mobile keeps safe-area top; desktop uses compact top.
  static EdgeInsets pageContentPadding(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    if (isDesktopPlatform) {
      return EdgeInsets.fromLTRB(
        mainHorizontalPadding,
        12,
        mainHorizontalPadding,
        0,
      );
    }
    return EdgeInsets.fromLTRB(24, topInset + 24, 24, 0);
  }

  /// Wider top for dense headers (e.g. chat) on desktop.
  static EdgeInsets pageContentPaddingDesktopTop(
    BuildContext context, {
    double desktopTop = 20,
  }) {
    final topInset = MediaQuery.paddingOf(context).top;
    if (isDesktopPlatform) {
      return EdgeInsets.fromLTRB(
        mainHorizontalPadding,
        desktopTop,
        mainHorizontalPadding,
        0,
      );
    }
    return EdgeInsets.fromLTRB(24, topInset + 24, 24, 0);
  }

  static const ScrollPhysics _clamp = ClampingScrollPhysics(
    parent: AlwaysScrollableScrollPhysics(),
  );

  static const ScrollPhysics _bounce = BouncingScrollPhysics(
    parent: AlwaysScrollableScrollPhysics(),
  );

  /// Clamps on desktop or very wide layouts; bounce on phones.
  static ScrollPhysics adaptiveScrollPhysics(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 900;
    if (isDesktopPlatform || wide) return _clamp;
    return _bounce;
  }

  /// Slightly tighter cards on desktop (native app feel).
  static double cardCornerRadius() => isDesktopPlatform ? 14.0 : 22.0;

  /// Horizontal padding inside the main (middle) column.
  static const double mainHorizontalPadding = 16;

  /// Outer gutter from window edge to the main workspace (sidebar → content).
  static const double windowHorizontalGutter = 10;

  /// Desktop tab bar (window tab strip).
  static const double topBarHorizontal = 14;
  static const double topBarVertical = 8;

  /// Max width of the centered main column (tabs + page).
  static const double mainColumnMaxWidth = 1380;

  /// Max width for split-view panes (readable line length).
  static const double splitMaxContentWidth = mainColumnMaxWidth;

  /// Rounded “chrome” strip behind the tab bar (0 = flat minimalist shell).
  static const double chromeSurfaceRadius = 0;

  /// Rounded main content card under the tabs.
  static const double mainSurfaceRadius = 0;

  /// Vertical gap between tab strip card and content card.
  static const double chromeToContentGap = 0;

  // ─── Unified hairline (desktop only — use from [Builder] / widget [context]) ─

  /// Single logical stroke width for all desktop separators.
  static const double hairlineWidth = 1.0;

  /// One neutral hairline for light/dark (slightly stronger than legacy 0.06/0.07).
  static Color hairlineColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return (isDark ? Colors.white : Colors.black).withValues(alpha: 0.12);
  }

  static Border hairlineBorderAll(BuildContext context) =>
      Border.all(color: hairlineColor(context), width: hairlineWidth);

  static Border hairlineBorderBottom(BuildContext context) => Border(
        bottom: BorderSide(
          color: hairlineColor(context),
          width: hairlineWidth,
        ),
      );

  /// Sidebar edge — intentionally none (flat native shell).
  static Border? sidebarRightEdgeBorder(BuildContext context) => null;

  /// Right sheet column — no separator line.
  static Border? desktopSheetPanelLeftBorder(BuildContext context) => null;

  /// Main workspace — no outer frame stroke.
  static Border? workspaceFrameBorder(BuildContext context) => null;
}
