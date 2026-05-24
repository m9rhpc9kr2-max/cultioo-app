import 'package:flutter/material.dart';
import 'cultioo_desktop_layout.dart';
import 'trade_republic_theme.dart';

/// Trade Republic styled section header
///
/// A consistent section title with optional subtitle and trailing action.
/// Use this to separate sections in bottom sheets, pages, or lists.
///
/// Example:
/// ```dart
/// TradeRepublicSectionHeader(
///   title: 'Personal data',
///   subtitle: 'Edit your profile',
///   trailing: Icon(Icons.edit),
/// )
/// ```
class TradeRepublicSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? leading;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final TextStyle? titleStyle;
  final TextStyle? subtitleStyle;

  const TradeRepublicSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.leading,
    this.padding = const EdgeInsets.only(bottom: 12),
    this.onTap,
    this.titleStyle,
    this.subtitleStyle,
  });

  @override
  Widget build(BuildContext context) {
    const defBottom = EdgeInsets.only(bottom: 12);
    final effectivePadding =
        CultiooDesktopLayout.isDesktopPlatform && padding == defBottom
            ? const EdgeInsets.only(bottom: 8)
            : padding;

    Widget header = Padding(
      padding: effectivePadding,
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            SizedBox(width: CultiooDesktopLayout.isDesktopPlatform ? 8 : 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title.toUpperCase(),
                  style: titleStyle ?? TradeRepublicTheme.titleMedium(context),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: subtitleStyle ?? TradeRepublicTheme.bodySmall(context),
                  ),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );

    if (onTap != null) {
      header = GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: header,
      );
    }

    return header;
  }
}
