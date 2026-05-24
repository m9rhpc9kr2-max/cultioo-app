import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'dart:io';
import 'dart:ui' as ui;

import 'cultioo_desktop_layout.dart';

/// Trade Republic styled continuous value slider.
/// - iOS: native CNSlider with optional CNSliderController
/// - Android/Desktop: premium animated slider — morphing pill thumb,
///   glow track, floating value label during drag
class TradeRepublicValueSlider extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;
  final Color? activeColor;
  final Color? inactiveColor;
  final Color? thumbColor;
  final double trackHeight;
  final double thumbRadius;
  final bool enableHaptics;

  /// Label to display in the floating bubble during drag.
  /// Defaults to the raw numeric value.
  final String Function(double value)? labelBuilder;

  /// Optional controller for programmatic updates (uses CNSliderController on iOS)
  final CNSliderController? controller;

  const TradeRepublicValueSlider({
    super.key,
    required this.value,
    this.min = 0.0,
    this.max = 1.0,
    this.divisions,
    this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.activeColor,
    this.inactiveColor,
    this.thumbColor,
    this.trackHeight = 5.0,
    this.thumbRadius = 11.0,
    this.enableHaptics = true,
    this.controller,
    this.labelBuilder,
  });

  @override
  State<TradeRepublicValueSlider> createState() =>
      _TradeRepublicValueSliderState();
}

class _TradeRepublicValueSliderState extends State<TradeRepublicValueSlider>
    with SingleTickerProviderStateMixin {
  static final bool _isIOS = Platform.isIOS;
  double? _lastHapticValue;
  bool _isDragging = false;

  // Animates the thumb: 0 = resting circle, 1 = pressed pill
  late final AnimationController _pressAnim;
  late final Animation<double> _pressT;

  @override
  void initState() {
    super.initState();
    _pressAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _pressT = CurvedAnimation(parent: _pressAnim, curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    _pressAnim.dispose();
    super.dispose();
  }

  void _startDrag(double x, double trackLeft, double trackWidth) {
    _isDragging = true;
    _pressAnim.forward();
    _lastHapticValue = null;
    widget.onChangeStart?.call(widget.value);
    if (widget.enableHaptics) HapticFeedback.lightImpact();
    _updateValue(x, trackLeft, trackWidth);
  }

  void _updateValue(double dx, double trackLeft, double trackWidth) {
    final raw = (dx - trackLeft) / trackWidth;
    double v = widget.min + raw.clamp(0.0, 1.0) * (widget.max - widget.min);
    if (widget.divisions != null) {
      final step = (widget.max - widget.min) / widget.divisions!;
      v = ((v / step).round() * step).clamp(widget.min, widget.max);
      if (_lastHapticValue != v && widget.enableHaptics) {
        HapticFeedback.selectionClick();
      }
    }
    _lastHapticValue = v;
    widget.onChanged?.call(v);
  }

  void _endDrag() {
    _isDragging = false;
    _pressAnim.reverse();
    widget.onChangeEnd?.call(widget.value);
    if (widget.enableHaptics) HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _isIOS ? _buildIOSSlider() : _buildModernSlider(isDark);
  }

  // ── iOS: native CNSlider ──────────────────────────────────────────────────

  Widget _buildIOSSlider() {
    final normalized =
        ((widget.value - widget.min) / (widget.max - widget.min)).clamp(0.0, 1.0);

    return CNSlider(
      value: normalized,
      controller: widget.controller,
      onChanged: (v) {
        if (widget.onChanged == null) return;
        _triggerHaptic(widget.min + v * (widget.max - widget.min));
        widget.onChanged!(widget.min + v * (widget.max - widget.min));
      },
    );
  }

  // ── Non-iOS: premium animated slider ─────────────────────────────────────

  Widget _buildModernSlider(bool isDark) {
    final activeColor =
        widget.activeColor ?? (isDark ? Colors.white : Colors.black);
    final inactiveColor = widget.inactiveColor ??
        (isDark
            ? Colors.white.withOpacity(0.10)
            : Colors.black.withOpacity(0.07));
    final thumbColor = widget.thumbColor ?? activeColor;
    // Inner dot color (contrast against thumb)
    final dotColor = isDark ? Colors.black : Colors.white;
    final desk = CultiooDesktopLayout.isDesktopPlatform;
    final trackH = desk ? 4.0 : widget.trackHeight;
    final thumbR = desk ? 9.0 : widget.thumbRadius;

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        // Reserve space for pill-thumb stretching on both sides
        final pillHalfWidth = thumbR * 1.8;
        final trackLeft = pillHalfWidth;
        final trackRight = totalWidth - pillHalfWidth;
        final trackWidth = trackRight - trackLeft;

        final normalized =
            ((widget.value - widget.min) / (widget.max - widget.min))
                .clamp(0.0, 1.0);

        final label = widget.labelBuilder != null
            ? widget.labelBuilder!(widget.value)
            : widget.value.toStringAsFixed(
                widget.divisions != null ? 0 : 1,
              );

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (d) =>
              _startDrag(d.localPosition.dx, trackLeft, trackWidth),
          onHorizontalDragUpdate: (d) =>
              _updateValue(d.localPosition.dx, trackLeft, trackWidth),
          onHorizontalDragEnd: (_) => _endDrag(),
          onTapDown: (d) {
            if (widget.enableHaptics) HapticFeedback.selectionClick();
            _updateValue(d.localPosition.dx, trackLeft, trackWidth);
          },
          child: SizedBox(
            // Extra height for floating label
            height: desk ? 54 : 64,
            width: totalWidth,
            child: AnimatedBuilder(
              animation: _pressT,
              builder: (context, _) => CustomPaint(
                painter: _PremiumSliderPainter(
                  value: normalized,
                  pressT: _pressT.value,
                  trackHeight: trackH,
                  thumbRadius: thumbR,
                  pillHalfWidth: pillHalfWidth,
                  activeColor: activeColor,
                  inactiveColor: inactiveColor,
                  thumbColor: thumbColor,
                  dotColor: dotColor,
                  isDark: isDark,
                  divisions: widget.divisions,
                  label: label,
                  isDragging: _isDragging,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _triggerHaptic(double value) {
    if (!widget.enableHaptics || !_isIOS) return;
    if (widget.divisions != null) {
      final step = (widget.max - widget.min) / widget.divisions!;
      final snapped = (value / step).round() * step;
      if (_lastHapticValue != snapped) {
        HapticFeedback.selectionClick();
        _lastHapticValue = snapped;
      }
    } else if (value == widget.min || value == widget.max) {
      if (_lastHapticValue != value) {
        HapticFeedback.lightImpact();
        _lastHapticValue = value;
      }
    }
  }
}

// ── Premium painter ───────────────────────────────────────────────────────────

class _PremiumSliderPainter extends CustomPainter {
  final double value;      // 0..1
  final double pressT;     // 0=resting, 1=pressed (animated)
  final double trackHeight;
  final double thumbRadius;
  final double pillHalfWidth;
  final Color activeColor;
  final Color inactiveColor;
  final Color thumbColor;
  final Color dotColor;
  final bool isDark;
  final bool isDragging;
  final int? divisions;
  final String label;

  const _PremiumSliderPainter({
    required this.value,
    required this.pressT,
    required this.trackHeight,
    required this.thumbRadius,
    required this.pillHalfWidth,
    required this.activeColor,
    required this.inactiveColor,
    required this.thumbColor,
    required this.dotColor,
    required this.isDark,
    required this.isDragging,
    required this.divisions,
    required this.label,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Track sits in the lower 44px; top 20px reserved for floating label
    const labelAreaHeight = 20.0;
    final trackCy = labelAreaHeight + (size.height - labelAreaHeight) / 2;
    final trackLeft = pillHalfWidth;
    final trackRight = size.width - pillHalfWidth;
    final trackWidth = trackRight - trackLeft;
    final thumbX = trackLeft + value * trackWidth;

    // ── Inactive track ────────────────────────────────────────────────────
    final tr = Radius.circular(trackHeight);
    final inactiveRRect = RRect.fromLTRBR(
      trackLeft, trackCy - trackHeight / 2,
      trackRight, trackCy + trackHeight / 2,
      tr,
    );
    canvas.drawRRect(inactiveRRect, Paint()..color = inactiveColor);

    // ── Active track with gradient ────────────────────────────────────────
    if (value > 0.001) {
      final activeRect = Rect.fromLTRB(
        trackLeft, trackCy - trackHeight / 2,
        thumbX, trackCy + trackHeight / 2,
      );
      final gradPaint = Paint()
        ..shader = ui.Gradient.linear(
          Offset(trackLeft, 0),
          Offset(thumbX, 0),
          [activeColor.withOpacity(0.55), activeColor],
        );
      canvas.drawRRect(
        RRect.fromRectAndRadius(activeRect, tr),
        gradPaint,
      );

      // Subtle glow on active track (only when pressed)
      if (pressT > 0.01) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(activeRect, tr),
          Paint()
            ..color = activeColor.withOpacity(0.18 * pressT)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
      }
    }

    // ── Division ticks ────────────────────────────────────────────────────
    if (divisions != null && divisions! > 1) {
      for (int i = 1; i < divisions!; i++) {
        final x = trackLeft + (i / divisions!) * trackWidth;
        final tickNorm = i / divisions!;
        final isActive = tickNorm < value;
        canvas.drawLine(
          Offset(x, trackCy - trackHeight * 2.0),
          Offset(x, trackCy + trackHeight * 2.0),
          Paint()
            ..color = (isActive ? dotColor : inactiveColor).withOpacity(0.5)
            ..strokeWidth = 1.5
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    // ── Thumb ─────────────────────────────────────────────────────────────
    // Morph: circle (pressT=0) → horizontal pill (pressT=1)
    final thumbW = thumbRadius * 2 + pressT * thumbRadius * 1.4;
    final thumbH = thumbRadius * 2 - pressT * thumbRadius * 0.3;
    final thumbRRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(thumbX, trackCy),
        width: thumbW,
        height: thumbH,
      ),
      Radius.circular(thumbH / 2),
    );

    // Thumb shadow
    canvas.drawRRect(
      thumbRRect.inflate(2),
      Paint()
        ..color = Colors.black.withOpacity(0.10 + 0.10 * pressT)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 + 4 * pressT),
    );

    // Thumb fill
    canvas.drawRRect(thumbRRect, Paint()..color = thumbColor);

    // Inner dot (contrast pip inside thumb)
    final dotRadius = thumbRadius * 0.22 * (1 - pressT * 0.6);
    if (dotRadius > 1) {
      canvas.drawCircle(
        Offset(thumbX, trackCy),
        dotRadius,
        Paint()..color = dotColor.withOpacity(0.35),
      );
    }

    // ── Floating label above thumb ────────────────────────────────────────
    if (pressT > 0.01) {
      _drawLabel(canvas, size, thumbX, trackCy, labelAreaHeight);
    }
  }

  void _drawLabel(Canvas canvas, Size size, double thumbX, double trackCy,
      double labelAreaHeight) {
    const fontSize = 11.0;
    const hPad = 8.0;
    const vPad = 3.0;
    const pillR = 6.0;

    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: dotColor,
          letterSpacing: -0.2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final labelW = tp.width + hPad * 2;
    final labelH = tp.height + vPad * 2;
    // keep pill inside horizontal bounds
    final cx = thumbX.clamp(labelW / 2 + 4, size.width - labelW / 2 - 4);
    final cy = (trackCy - thumbRadius - 6 - labelH / 2).clamp(0.0, trackCy - thumbRadius - 4);

    final pillRect =
        Rect.fromCenter(center: Offset(cx, cy), width: labelW, height: labelH);
    canvas.drawRRect(
      RRect.fromRectAndRadius(pillRect, const Radius.circular(pillR)),
      Paint()
        ..color = thumbColor.withOpacity(pressT)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 * pressT),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(pillRect, const Radius.circular(pillR)),
      Paint()..color = thumbColor.withOpacity(pressT),
    );

    tp.paint(
      canvas,
      Offset(cx - tp.width / 2, cy - tp.height / 2),
    );
  }

  @override
  bool shouldRepaint(_PremiumSliderPainter old) =>
      old.value != value ||
      old.pressT != pressT ||
      old.activeColor != activeColor ||
      old.inactiveColor != inactiveColor ||
      old.thumbColor != thumbColor ||
      old.label != label;
}
