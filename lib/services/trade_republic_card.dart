import 'package:flutter/material.dart';
import 'cultioo_desktop_layout.dart';
import 'pointer_safe.dart';
import 'trade_republic_theme.dart';
import 'trade_republic_bottom_sheet.dart';

EdgeInsets _defaultTradeRepublicCardPadding() {
  return EdgeInsets.all(
    CultiooDesktopLayout.isDesktopPlatform ? 10.0 : 16.0,
  );
}

/// When [flat] is true, [TradeRepublicCard] uses transparent fills so content
/// sits on a single sheet background (e.g. minimalist desktop order details).
class TradeRepublicCardFlatScope extends InheritedWidget {
  const TradeRepublicCardFlatScope({
    super.key,
    required this.flat,
    required super.child,
  });

  final bool flat;

  static bool flatOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<TradeRepublicCardFlatScope>()
            ?.flat ??
        false;
  }

  @override
  bool updateShouldNotify(TradeRepublicCardFlatScope oldWidget) =>
      flat != oldWidget.flat;
}

/// Trade Republic styled card / container
///
/// A consistent container with rounded corners, proper padding,
/// and dark/light mode colors.
///
/// Variants:
/// - `TradeRepublicCard(...)` — standard card with subtle background
/// - `TradeRepublicCard.elevated(...)` — card with shadow
/// - `TradeRepublicCard.outlined(...)` — card with subtle border
/// - `TradeRepublicCard.transparent(...)` — no background, just padding + radius
class TradeRepublicCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final EdgeInsets? margin;
  final Color? backgroundColor;
  final BorderRadius? borderRadius;
  final List<BoxShadow>? boxShadow;
  final Border? border;
  final double? width;
  final double? height;
  final VoidCallback? onTap;

  const TradeRepublicCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.backgroundColor,
    this.borderRadius,
    this.boxShadow,
    this.border,
    this.width,
    this.height,
    this.onTap,
  });

  /// Elevated card with shadow
  factory TradeRepublicCard.elevated({
    Key? key,
    required Widget child,
    EdgeInsets? padding,
    EdgeInsets? margin,
    Color? backgroundColor,
    BorderRadius? borderRadius,
    double? width,
    double? height,
    VoidCallback? onTap,
  }) {
    return _TradeRepublicElevatedCard(
      key: key,
      padding: padding,
      margin: margin,
      backgroundColor: backgroundColor,
      borderRadius: borderRadius,
      width: width,
      height: height,
      onTap: onTap,
      child: child,
    );
  }

  /// Card with subtle border, no fill
  factory TradeRepublicCard.outlined({
    Key? key,
    required Widget child,
    EdgeInsets? padding,
    EdgeInsets? margin,
    Color? borderColor,
    BorderRadius? borderRadius,
    double? width,
    double? height,
    VoidCallback? onTap,
  }) {
    return _TradeRepublicOutlinedCard(
      key: key,
      padding: padding,
      margin: margin,
      borderColor: borderColor,
      borderRadius: borderRadius,
      width: width,
      height: height,
      onTap: onTap,
      child: child,
    );
  }

  /// Transparent card — just padding & borderRadius, no background
  factory TradeRepublicCard.transparent({
    Key? key,
    required Widget child,
    EdgeInsets? padding,
    EdgeInsets? margin,
    BorderRadius? borderRadius,
    double? width,
    double? height,
    VoidCallback? onTap,
  }) {
    return TradeRepublicCard(
      key: key,
      padding: padding,
      margin: margin,
      backgroundColor: Colors.transparent,
      borderRadius: borderRadius,
      width: width,
      height: height,
      onTap: onTap,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final inBottomSheet =
        TradeRepublicBottomSheetScope.of(context)
            ?.forceTransparentDarkSurfaces ??
        false;
    final flat = TradeRepublicCardFlatScope.flatOf(context);
    final baseSurface = Colors.transparent;
    final effectiveBg =
        backgroundColor ??
        (inBottomSheet || flat ? Colors.transparent : baseSurface);
    final effectiveRadius =
        borderRadius ?? TradeRepublicTheme.borderRadiusLarge;
    final effectivePadding = padding ?? _defaultTradeRepublicCardPadding();

    Widget card = Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        color: effectiveBg,
        borderRadius: effectiveRadius,
      ),
      child: Padding(
        padding: effectivePadding,
        child: child,
      ),
    );

    if (onTap != null) {
      card = _TappableCard(
        onTap: onTap!,
        borderRadius: effectiveRadius,
        child: card,
      );
    }

    return card;
  }

}

/// Internal: elevated card with shadow
class _TradeRepublicElevatedCard extends TradeRepublicCard {
  const _TradeRepublicElevatedCard({
    super.key,
    required super.child,
    super.padding,
    super.margin,
    super.backgroundColor,
    super.borderRadius,
    super.width,
    super.height,
    super.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveBg = backgroundColor ?? Colors.transparent;
    final effectiveRadius =
        borderRadius ?? TradeRepublicTheme.borderRadiusLarge;
    final effectivePadding = padding ?? _defaultTradeRepublicCardPadding();

    Widget card = Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        color: effectiveBg,
        borderRadius: effectiveRadius,
      ),
      child: Padding(
        padding: effectivePadding,
        child: child,
      ),
    );

    if (onTap != null) {
      card = _TappableCard(
        onTap: onTap!,
        borderRadius: effectiveRadius,
        child: card,
      );
    }

    return card;
  }

}

/// Internal: outlined card with border
class _TradeRepublicOutlinedCard extends TradeRepublicCard {
  final Color? borderColor;

  const _TradeRepublicOutlinedCard({
    super.key,
    required super.child,
    super.padding,
    super.margin,
    this.borderColor,
    super.borderRadius,
    super.width,
    super.height,
    super.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveRadius =
        borderRadius ?? TradeRepublicTheme.borderRadiusLarge;
    final effectivePadding = padding ?? _defaultTradeRepublicCardPadding();
    final baseSurface = Colors.transparent;

    Widget card = Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        color: backgroundColor ?? baseSurface,
        borderRadius: effectiveRadius,
      ),
      child: Padding(
        padding: effectivePadding,
        child: child,
      ),
    );

    if (onTap != null) {
      card = _TappableCard(
        onTap: onTap!,
        borderRadius: effectiveRadius,
        child: card,
      );
    }

    return card;
  }
}

/// Tappable wrapper that adds MouseRegion hover tint
class _TappableCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final BorderRadius borderRadius;

  const _TappableCard({
    required this.child,
    required this.onTap,
    required this.borderRadius,
  });

  @override
  State<_TappableCard> createState() => _TappableCardState();
}

class _TappableCardState extends State<_TappableCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        scheduleAfterPointerUpdate(() {
          if (!mounted) return;
          setState(() => _hovered = true);
        });
      },
      onExit: (_) {
        scheduleAfterPointerUpdate(() {
          if (!mounted) return;
          setState(() => _hovered = false);
        });
      },
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(horizontal: 6),
          foregroundDecoration: _hovered
              ? BoxDecoration(
                  color: (isLight ? Colors.black : Colors.white)
                      .withValues(alpha: 0.04),
                  borderRadius: widget.borderRadius,
                )
              : null,
          child: widget.child,
        ),
      ),
    );
  }
}
