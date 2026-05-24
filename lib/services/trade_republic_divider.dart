import 'package:flutter/material.dart';
import 'cultioo_desktop_layout.dart';
import 'trade_republic_theme.dart';

/// Trade Republic styled divider
///
/// A subtle, thin divider consistent with the design language.
/// Use between sections in bottom sheets, lists, etc.
class TradeRepublicDivider extends StatelessWidget {
  final double height;
  final double thickness;
  final EdgeInsets? margin;
  final Color? color;

  const TradeRepublicDivider({
    super.key,
    this.height = 1,
    this.thickness = 1,
    this.margin,
    this.color,
  });

  /// A divider with more spacing above and below
  factory TradeRepublicDivider.spaced({
    Key? key,
    Color? color,
  }) {
    return TradeRepublicDivider(
      key: key,
      color: color,
      margin: const EdgeInsets.symmetric(vertical: 16),
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ??
        TradeRepublicTheme.textColor(context).withValues(alpha: 0.06);

    return Container(
      margin: margin ??
          EdgeInsets.symmetric(
            vertical: CultiooDesktopLayout.isDesktopPlatform ? 6 : 8,
          ),
      height: thickness,
      decoration: BoxDecoration(
        color: effectiveColor,
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }
}
