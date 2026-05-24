import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A tap wrapper that provides haptic feedback and a subtle scale animation
/// similar to Trade Republic's tap interactions.
class TradeRepublicTap extends StatefulWidget {
  final Widget? child;
  final VoidCallback? onTap;
  final VoidCallback? onTapCancel;
  final VoidCallback? onLongPress;
  final GestureTapDownCallback? onTapDown;
  final GestureTapUpCallback? onTapUp;
  final GestureDragDownCallback? onPanDown;
  final GestureDragStartCallback? onPanStart;
  final Color? hoverColor;
  final GestureDragStartCallback? onHorizontalDragStart;
  final GestureDragUpdateCallback? onHorizontalDragUpdate;
  final GestureDragEndCallback? onHorizontalDragEnd;
  final GestureDragUpdateCallback? onVerticalDragUpdate;
  final GestureDragEndCallback? onVerticalDragEnd;
  final GestureDragUpdateCallback? onPanUpdate;
  final GestureDragEndCallback? onPanEnd;
  final VoidCallback? onDoubleTap;
  final GestureTapDownCallback? onSecondaryTapDown;
  final GestureLongPressStartCallback? onLongPressStart;
  final GestureLongPressMoveUpdateCallback? onLongPressMoveUpdate;
  final GestureLongPressEndCallback? onLongPressEnd;
  final BorderRadius? borderRadius;
  final Color? splashColor;
  final Color? highlightColor;
  final bool enableHaptic;
  final double scaleFactor;
  final Duration duration;
  final HitTestBehavior behavior;

  const TradeRepublicTap({
    super.key,
    this.child,
    this.onTap,
    this.onTapCancel,
    this.onLongPress,
    this.onTapDown,
    this.onTapUp,
    this.onPanDown,
    this.onPanStart,
    this.hoverColor,
    this.onHorizontalDragStart,
    this.onHorizontalDragUpdate,
    this.onHorizontalDragEnd,
    this.onVerticalDragUpdate,
    this.onVerticalDragEnd,
    this.onPanUpdate,
    this.onPanEnd,
    this.onDoubleTap,
    this.onSecondaryTapDown,
    this.onLongPressStart,
    this.onLongPressMoveUpdate,
    this.onLongPressEnd,
    this.borderRadius,
    this.splashColor,
    this.highlightColor,
    this.enableHaptic = true,
    this.scaleFactor = 0.97,
    this.duration = const Duration(milliseconds: 100),
    this.behavior = HitTestBehavior.opaque,
  });

  @override
  State<TradeRepublicTap> createState() => _TradeRepublicTapState();
}

class _TradeRepublicTapState extends State<TradeRepublicTap>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: widget.scaleFactor,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    if (widget.onTap != null) {
      _controller.forward();
    }
    widget.onTapDown?.call(details);
  }

  void _onTapUp(TapUpDetails details) {
    _controller.reverse();
    widget.onTapUp?.call(details);
  }

  void _onTapCancel() {
    _controller.reverse();
    widget.onTapCancel?.call();
  }

  void _onTap() {
    if (widget.onTap == null) return;
    if (widget.enableHaptic) {
      HapticFeedback.lightImpact();
    }
    widget.onTap!();
  }

  @override
  Widget build(BuildContext context) {
    Widget content = AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) => Transform.scale(
        scale: _scaleAnimation.value,
        child: child,
      ),
      child: widget.child ?? const SizedBox.shrink(),
    );

    if (widget.borderRadius != null) {
      content = ClipRRect(
        borderRadius: widget.borderRadius!,
        child: content,
      );
    }

    return GestureDetector(
      behavior: widget.behavior,
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      onTap: _onTap,
      onLongPress: widget.onLongPress,
      onHorizontalDragStart: widget.onHorizontalDragStart,
      onHorizontalDragUpdate: widget.onHorizontalDragUpdate,
      onHorizontalDragEnd: widget.onHorizontalDragEnd,
      onVerticalDragUpdate: widget.onVerticalDragUpdate,
      onVerticalDragEnd: widget.onVerticalDragEnd,
      onPanDown: widget.onPanDown,
      onPanStart: widget.onPanStart,
      onPanUpdate: widget.onPanUpdate,
      onPanEnd: widget.onPanEnd,
      onDoubleTap: widget.onDoubleTap,
      onSecondaryTapDown: widget.onSecondaryTapDown,
      onLongPressStart: widget.onLongPressStart,
      onLongPressMoveUpdate: widget.onLongPressMoveUpdate,
      onLongPressEnd: widget.onLongPressEnd,
      child: content,
    );
  }
}
