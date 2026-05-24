import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'trade_republic_tap.dart';

/// Specification for one swipe action (leading or trailing).
///
/// A spec describes how the action looks and what it does when committed.
/// Optional `activeIcon` / `activeLabel` allow the icon and label to
/// change while [isActive] is true (e.g. "Pin" → "Unpin").
class TradeRepublicSwipeSpec {
  /// Icon shown while [isActive] is false.
  final IconData icon;

  /// Label shown while [isActive] is false.
  final String label;

  /// Icon shown while [isActive] is true.
  final IconData? activeIcon;

  /// Label shown while [isActive] is true.
  final String? activeLabel;

  /// Whether the action is currently in the "active" state.
  /// Controls which icon/label is rendered.
  final bool isActive;

  /// Called when the swipe crosses the commit threshold (or is flung).
  final VoidCallback onActivate;

  /// Background colour of the reveal area. Defaults to monochrome:
  /// black on light theme, white on dark theme.
  final Color? backgroundColor;

  /// Foreground colour for icon + label. Defaults to the inverse of
  /// [backgroundColor] for max contrast.
  final Color? foregroundColor;

  /// Visual rotation applied to the icon (radians). Useful for the
  /// classic "pinned" look (negative ~ -0.5).
  final double iconRotation;

  const TradeRepublicSwipeSpec({
    required this.icon,
    required this.label,
    required this.onActivate,
    this.activeIcon,
    this.activeLabel,
    this.isActive = false,
    this.backgroundColor,
    this.foregroundColor,
    this.iconRotation = 0,
  });

  IconData get effectiveIcon => isActive ? (activeIcon ?? icon) : icon;
  String get effectiveLabel => isActive ? (activeLabel ?? label) : label;
}

/// Trade-Republic-style swipe-to-action for list rows.
///
/// Supports an optional [leading] action (revealed by swiping right) and
/// an optional [trailing] action (revealed by swiping left). The reveal
/// grows from the edge with the drag, snaps back smoothly, and emits a
/// single haptic when the commit threshold is crossed (and a second one
/// when actually committed).
///
/// Example:
/// ```dart
/// TradeRepublicSwipeAction(
///   leading: TradeRepublicSwipeSpec(
///     icon: CupertinoIcons.pin_fill,
///     label: 'Pin',
///     activeIcon: CupertinoIcons.pin_slash_fill,
///     activeLabel: 'Unpin',
///     isActive: isPinned,
///     onActivate: togglePin,
///     iconRotation: -0.5,
///   ),
///   trailing: TradeRepublicSwipeSpec(
///     icon: CupertinoIcons.delete,
///     label: 'Delete',
///     onActivate: deleteItem,
///     backgroundColor: const Color(0xFFFF3B30),
///   ),
///   onTap: openItem,
///   child: row,
/// );
/// ```
class TradeRepublicSwipeAction extends StatefulWidget {
  /// Foreground content (the row that gets swiped).
  final Widget child;

  /// Action revealed by swiping right (positive drag).
  final TradeRepublicSwipeSpec? leading;

  /// Action revealed by swiping left (negative drag).
  final TradeRepublicSwipeSpec? trailing;

  /// Tap callback for the foreground row.
  final VoidCallback? onTap;

  /// Drag distance (px) at which an action commits. Same value used in
  /// both directions.
  final double commitThreshold;

  /// Corner radius of both the foreground row and the reveal clips.
  final double borderRadius;

  /// Outer margin of the whole component.
  final EdgeInsetsGeometry margin;

  /// Background colour applied to the foreground row so the reveal
  /// cannot bleed through translucent children. Defaults to the theme
  /// surface colour (white on light, black on dark).
  final Color? foregroundColor;

  const TradeRepublicSwipeAction({
    super.key,
    required this.child,
    this.leading,
    this.trailing,
    this.onTap,
    this.commitThreshold = 92,
    this.borderRadius = 20,
    this.margin = const EdgeInsets.only(bottom: 16),
    this.foregroundColor,
  });

  @override
  State<TradeRepublicSwipeAction> createState() =>
      _TradeRepublicSwipeActionState();
}

class _TradeRepublicSwipeActionState extends State<TradeRepublicSwipeAction>
    with SingleTickerProviderStateMixin {
  /// Signed horizontal drag offset.
  /// Positive = swiping right (reveals leading).
  /// Negative = swiping left  (reveals trailing).
  double _drag = 0;

  /// Tracks whether the drag passed the commit threshold for the
  /// currently active direction. Used to emit haptics on cross/uncross.
  bool _crossedCommit = false;

  AnimationController? _settle;
  Animation<double>? _settleAnim;

  @override
  void initState() {
    super.initState();
    _settle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    )..addListener(() {
        final a = _settleAnim;
        if (a == null || !mounted) return;
        setState(() => _drag = a.value);
      });
  }

  @override
  void dispose() {
    _settle?.dispose();
    _settle = null;
    super.dispose();
  }

  bool get _hasLeading => widget.leading != null;
  bool get _hasTrailing => widget.trailing != null;

  void _onDragStart(DragStartDetails _) {
    _settle?.stop();
    _crossedCommit = false;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final delta = details.primaryDelta ?? 0;
    var next = _drag + delta;

    // Clamp direction: if no spec for that side, do not allow drag past 0.
    if (next > 0 && !_hasLeading) next = 0;
    if (next < 0 && !_hasTrailing) next = 0;

    // Rubber-band past the commit threshold for tactile pull feel.
    final threshold = widget.commitThreshold;
    if (next.abs() > threshold) {
      final overshoot = next.abs() - threshold;
      next = next.sign * (threshold + overshoot * 0.35);
    }

    final crossed = next.abs() >= threshold;
    if (crossed != _crossedCommit) {
      HapticFeedback.selectionClick();
      _crossedCommit = crossed;
    }

    setState(() => _drag = next);
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final threshold = widget.commitThreshold;
    final committedRight =
        _hasLeading && (_drag >= threshold || velocity > 1200);
    final committedLeft =
        _hasTrailing && (_drag <= -threshold || velocity < -1200);

    if (committedRight) {
      HapticFeedback.mediumImpact();
      widget.leading!.onActivate();
    } else if (committedLeft) {
      HapticFeedback.mediumImpact();
      widget.trailing!.onActivate();
    }
    _animateTo(0);
  }

  void _animateTo(double target) {
    final ctrl = _settle;
    if (ctrl == null) return;
    _settleAnim = Tween<double>(begin: _drag, end: target).animate(
      CurvedAnimation(parent: ctrl, curve: Curves.easeOutCubic),
    );
    ctrl
      ..reset()
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final pageBg =
        widget.foregroundColor ?? (isLight ? Colors.white : Colors.black);
    final defaultReveal = isLight ? Colors.black : Colors.white;
    final defaultRevealFg = isLight ? Colors.white : Colors.black;

    final progress = (_drag.abs() / widget.commitThreshold).clamp(0.0, 1.0);
    final committed = _drag.abs() >= widget.commitThreshold;

    final showLeading = _drag > 0 && _hasLeading;
    final showTrailing = _drag < 0 && _hasTrailing;

    return Container(
      margin: widget.margin,
      child: Stack(
        children: [
          // Leading reveal grows from the LEFT edge.
          if (showLeading)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: _drag,
              child: _Reveal(
                spec: widget.leading!,
                progress: progress,
                committed: committed,
                alignment: Alignment.centerLeft,
                radius: widget.borderRadius,
                defaultBg: defaultReveal,
                defaultFg: defaultRevealFg,
              ),
            ),

          // Trailing reveal grows from the RIGHT edge.
          if (showTrailing)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: -_drag,
              child: _Reveal(
                spec: widget.trailing!,
                progress: progress,
                committed: committed,
                alignment: Alignment.centerRight,
                radius: widget.borderRadius,
                defaultBg: defaultReveal,
                defaultFg: defaultRevealFg,
              ),
            ),

          // Foreground row. Solid background prevents reveal bleed-through.
          Transform.translate(
            offset: Offset(_drag, 0),
            child: TradeRepublicTap(
              onTap: widget.onTap,
              onHorizontalDragStart: _onDragStart,
              onHorizontalDragUpdate: _onDragUpdate,
              onHorizontalDragEnd: _onDragEnd,
              child: Container(
                color: pageBg,
                child: widget.child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Internal reveal panel: a coloured strip with an icon + label,
/// clipped to the parent width and aligned to the swipe edge.
class _Reveal extends StatelessWidget {
  final TradeRepublicSwipeSpec spec;
  final double progress;
  final bool committed;
  final Alignment alignment;
  final double radius;
  final Color defaultBg;
  final Color defaultFg;

  const _Reveal({
    required this.spec,
    required this.progress,
    required this.committed,
    required this.alignment,
    required this.radius,
    required this.defaultBg,
    required this.defaultFg,
  });

  @override
  Widget build(BuildContext context) {
    final bg = spec.backgroundColor ?? defaultBg;
    final fg = spec.foregroundColor ?? defaultFg;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        color: bg,
        alignment: alignment,
        child: OverflowBox(
          minWidth: 0,
          maxWidth: double.infinity,
          alignment: alignment,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Opacity(
              opacity: progress,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedScale(
                    scale: committed ? 1.18 : 1.0,
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutBack,
                    child: Transform.rotate(
                      angle: spec.iconRotation,
                      child: Icon(spec.effectiveIcon, color: fg, size: 18),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    spec.effectiveLabel,
                    style: TextStyle(
                      color: fg,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.1,
                    ),
                    softWrap: false,
                    overflow: TextOverflow.clip,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
