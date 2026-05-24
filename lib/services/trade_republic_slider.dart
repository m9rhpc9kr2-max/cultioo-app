import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'dart:io';
import 'dart:ui';

import 'cultioo_desktop_layout.dart';

/// Trade Republic styled segmented slider/switch - Premium modern design
/// Features smooth animations, depth, and ultra-clean aesthetics
class TradeRepublicSlider extends StatefulWidget {
  /// The labels for each segment
  final List<String> labels;

  /// Currently selected index
  final int selectedIndex;

  /// Callback when selection changes
  final ValueChanged<int> onChanged;

  /// Optional fixed width for each segment
  final double? segmentWidth;

  /// Height of the slider
  final double height;

  /// Border radius
  final double borderRadius;

  /// Enable haptic feedback
  final bool enableHaptics;

  /// Use glass morphism effect
  final bool useGlassMorphism;

  const TradeRepublicSlider({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
    this.segmentWidth,
    this.height = 52.0,
    this.borderRadius = 16.0,
    this.enableHaptics = true,
    this.useGlassMorphism = false,
  }) : assert(labels.length >= 2, 'At least 2 labels are required');

  @override
  State<TradeRepublicSlider> createState() => _TradeRepublicSliderState();
}

class _TradeRepublicSliderState extends State<TradeRepublicSlider>
    with SingleTickerProviderStateMixin {
  late AnimationController _slideController;
  int? _pressedIndex;
  int? _hoveredIndex;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _slideController.forward();
  }

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // iOS: Use native CNSegmentedControl
    if (Platform.isIOS) {
      // If an explicit width is given use it; otherwise shrink-wrap to available width.
      if (widget.segmentWidth != null) {
        final totalW = widget.segmentWidth! * widget.labels.length;
        return SizedBox(
          width: totalW,
          height: widget.height,
          child: CNSegmentedControl(
            labels: widget.labels,
            selectedIndex: widget.selectedIndex,
            onValueChanged: (index) {
              if (widget.enableHaptics) HapticFeedback.selectionClick();
              widget.onChanged(index);
            },
          ),
        );
      }
      return LayoutBuilder(
        builder: (context, constraints) {
          final totalW = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : widget.labels.length * 80.0;
          return SizedBox(
            width: totalW,
            height: widget.height,
            child: CNSegmentedControl(
              labels: widget.labels,
              selectedIndex: widget.selectedIndex,
              onValueChanged: (index) {
                if (widget.enableHaptics) HapticFeedback.selectionClick();
                widget.onChanged(index);
              },
            ),
          );
        },
      );
    }

    final brightness = Theme.of(context).brightness;
    final isLight = brightness == Brightness.light;
    final desk = CultiooDesktopLayout.isDesktopPlatform;
    final effH = desk ? 44.0 : widget.height;
    final effR = desk ? 12.0 : widget.borderRadius;

    // If an explicit width is given use it; otherwise fit the available width.
    if (widget.segmentWidth != null) {
      final segmentWidth = widget.segmentWidth!;
      final totalWidth = segmentWidth * widget.labels.length;
      return _buildSlider(
        context,
        isLight: isLight,
        segmentWidth: segmentWidth,
        totalWidth: totalWidth,
        sliderHeight: effH,
        sliderBorderRadius: effR,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : widget.labels.length * 80.0;
        final segmentWidth = totalWidth / widget.labels.length;
        return _buildSlider(
          context,
          isLight: isLight,
          segmentWidth: segmentWidth,
          totalWidth: totalWidth,
          sliderHeight: effH,
          sliderBorderRadius: effR,
        );
      },
    );
  }

  Widget _buildSlider(
    BuildContext context, {
    required bool isLight,
    required double segmentWidth,
    required double totalWidth,
    double? sliderHeight,
    double? sliderBorderRadius,
  }) {
    final h = sliderHeight ?? widget.height;
    final br = sliderBorderRadius ?? widget.borderRadius;
    final desk = CultiooDesktopLayout.isDesktopPlatform;
    final fsSel = desk ? 13.5 : 15.5;
    final fsUn = desk ? 13.0 : 15.0;

    // Selected segment: inverted (light → black pill / white label)
    final selectedBackgroundColor = isLight ? Colors.black : Colors.white;
    final selectedTextColor = isLight ? Colors.white : Colors.black;
    final unselectedTextColor = isLight
        ? const Color.fromARGB(255, 103, 103, 103)
        : Colors.white.withValues(alpha: 0.45);

    Widget slider = Container(
      width: totalWidth,
      height: h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(br),
      ),
      child: Stack(
        children: [
          // Animated sliding indicator
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOutCubic,
            left: widget.selectedIndex * segmentWidth + 4,
            top: 4,
            child: Container(
              width: segmentWidth - 8,
              height: h - 8,
              decoration: BoxDecoration(
                color: selectedBackgroundColor,
                borderRadius: BorderRadius.circular((br - 4).clamp(4.0, br)),
              ),
            ),
          ),
          // Interactive buttons with hover & press states
          Row(
            children: List.generate(widget.labels.length, (index) {
              final isSelected = widget.selectedIndex == index;
              final isPressed = _pressedIndex == index;
              final isHovered = _hoveredIndex == index;
              
              return MouseRegion(
                onEnter: (_) => setState(() => _hoveredIndex = index),
                onExit: (_) => setState(() => _hoveredIndex = null),
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTapDown: (_) => setState(() => _pressedIndex = index),
                  onTapUp: (_) => setState(() => _pressedIndex = null),
                  onTapCancel: () => setState(() => _pressedIndex = null),
                  onTap: () {
                    if (index != widget.selectedIndex) {
                      if (widget.enableHaptics) {
                        HapticFeedback.selectionClick();
                      }
                      widget.onChanged(index);
                    }
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    width: segmentWidth,
                    height: h,
                    decoration: BoxDecoration(
                      color: !isSelected && isHovered
                          ? (isLight ? Colors.black : Colors.white).withValues(alpha: 0.03)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(br),
                    ),
                    child: AnimatedScale(
                      scale: isPressed ? 0.96 : 1.0,
                      duration: const Duration(milliseconds: 150),
                      curve: Curves.easeOut,
                      child: Container(
                        alignment: Alignment.center,
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeInOut,
                          style: TextStyle(
                            color: isSelected
                                ? selectedTextColor
                                : unselectedTextColor,
                            fontSize: isSelected ? fsSel : fsUn,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            letterSpacing: isSelected ? -0.4 : -0.3,
                            height: 1.2,
                          ),
                          child: Text(
                            widget.labels[index],
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );

    // Apply glass morphism if enabled
    if (widget.useGlassMorphism) {
      slider = ClipRRect(
        borderRadius: BorderRadius.circular(br),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: slider,
        ),
      );
    }

    return slider;
  }
}

/// A variant of TradeRepublicSlider that expands to fill available width
class TradeRepublicSliderExpanded extends StatefulWidget {
  /// The labels for each segment
  final List<String> labels;

  /// Currently selected index
  final int selectedIndex;

  /// Callback when selection changes
  final ValueChanged<int> onChanged;

  /// Height of the slider
  final double height;

  /// Border radius
  final double borderRadius;

  /// Enable haptic feedback
  final bool enableHaptics;

  /// Horizontal padding inside the container
  final double horizontalPadding;

  const TradeRepublicSliderExpanded({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
    this.height = 52.0,
    this.borderRadius = 16.0,
    this.enableHaptics = true,
    this.horizontalPadding = 16.0,
  }) : assert(labels.length >= 2, 'At least 2 labels are required');

  @override
  State<TradeRepublicSliderExpanded> createState() => _TradeRepublicSliderExpandedState();
}

class _TradeRepublicSliderExpandedState extends State<TradeRepublicSliderExpanded> {
  int? _pressedIndex;
  int? _hoveredIndex;

  @override
  Widget build(BuildContext context) {
    // iOS: Use native CNSegmentedControl
    if (Platform.isIOS) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: widget.horizontalPadding),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SizedBox(
              width: constraints.maxWidth.isFinite ? constraints.maxWidth : 300,
              height: widget.height,
              child: CNSegmentedControl(
                labels: widget.labels,
                selectedIndex: widget.selectedIndex,
                onValueChanged: (index) {
                  if (widget.enableHaptics) HapticFeedback.selectionClick();
                  widget.onChanged(index);
                },
              ),
            );
          },
        ),
      );
    }

    final brightness = Theme.of(context).brightness;
    final isLight = brightness == Brightness.light;
    final desk = CultiooDesktopLayout.isDesktopPlatform;
    final effH = desk ? 44.0 : widget.height;
    final effR = desk ? 12.0 : widget.borderRadius;
    final fsSel = desk ? 13.5 : 15.5;
    final fsUn = desk ? 13.0 : 15.0;

    final selectedBackgroundColor = isLight ? Colors.black : Colors.white;
    final selectedTextColor = isLight ? Colors.white : Colors.black;
    final unselectedTextColor = isLight
        ? const Color.fromARGB(255, 104, 104, 104)
        : Colors.white.withValues(alpha: 0.45);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: widget.horizontalPadding),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final segmentWidth = constraints.maxWidth / widget.labels.length;

          return Container(
            height: effH,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(effR),
            ),
            child: Stack(
              children: [
                // Premium animated sliding indicator
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOutCubic,
                  left: widget.selectedIndex * segmentWidth + 4,
                  top: 4,
                  child: Container(
                    width: segmentWidth - 8,
                    height: effH - 8,
                    decoration: BoxDecoration(
                      color: selectedBackgroundColor,
                      borderRadius: BorderRadius.circular((effR - 4).clamp(4.0, effR)),
                    ),
                  ),
                ),
                // Interactive buttons with premium states
                Row(
                  children: List.generate(widget.labels.length, (index) {
                    final isSelected = widget.selectedIndex == index;
                    final isPressed = _pressedIndex == index;
                    final isHovered = _hoveredIndex == index;
                    
                    return Expanded(
                      child: MouseRegion(
                        onEnter: (_) => setState(() => _hoveredIndex = index),
                        onExit: (_) => setState(() => _hoveredIndex = null),
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTapDown: (_) => setState(() => _pressedIndex = index),
                          onTapUp: (_) => setState(() => _pressedIndex = null),
                          onTapCancel: () => setState(() => _pressedIndex = null),
                          onTap: () {
                            if (index != widget.selectedIndex) {
                              if (widget.enableHaptics) {
                                HapticFeedback.selectionClick();
                              }
                              widget.onChanged(index);
                            }
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOut,
                            height: effH,
                            decoration: BoxDecoration(
                              color: !isSelected && isHovered
                                  ? (isLight ? Colors.black : Colors.white).withValues(alpha: 0.03)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(effR),
                            ),
                            child: AnimatedScale(
                              scale: isPressed ? 0.96 : 1.0,
                              duration: const Duration(milliseconds: 150),
                              curve: Curves.easeOut,
                              child: Container(
                                alignment: Alignment.center,
                                child: AnimatedDefaultTextStyle(
                                  duration: const Duration(milliseconds: 250),
                                  curve: Curves.easeInOut,
                                  style: TextStyle(
                                    color: isSelected
                                        ? selectedTextColor
                                        : unselectedTextColor,
                                    fontSize: isSelected ? fsSel : fsUn,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    letterSpacing: isSelected ? -0.4 : -0.3,
                                    height: 1.2,
                                  ),
                                  child: Text(
                                    widget.labels[index],
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Trade Republic Continuous Slider  — Premium linear value picker
// Animated thumb, always-visible floating value pill, haptic feedback
// ──────────────────────────────────────────────────────────────────────────────

/// Trade Republic styled continuous (linear) slider.
/// Shows a floating value pill above the thumb at all times.
class TradeRepublicContinuousSlider extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;

  /// Returns the string shown inside the floating value pill.
  final String Function(double) labelBuilder;
  final bool enableHaptics;

  const TradeRepublicContinuousSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.labelBuilder,
    this.divisions,
    this.enableHaptics = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? Colors.white : Colors.black;

    // iOS: native CNSlider feel
    if (Platform.isIOS) {
      return CNSlider(
        value: (value - min) / (max - min),
        onChanged: (v) {
          if (enableHaptics) HapticFeedback.selectionClick();
          onChanged(min + v * (max - min));
        },
      );
    }

    final desk = CultiooDesktopLayout.isDesktopPlatform;
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: desk ? 4.0 : 6.0,
        activeTrackColor: primaryColor,
        inactiveTrackColor: primaryColor.withValues(alpha: 0.1),
        overlayShape: SliderComponentShape.noOverlay,
        thumbShape: _TRLinearThumbShape(isDark: isDark, compact: desk),
        trackShape: const _TRLinearTrackShape(),
        showValueIndicator: ShowValueIndicator.onDrag,
        valueIndicatorShape: const _TRLinearValueIndicatorShape(),
        valueIndicatorColor: primaryColor,
        valueIndicatorTextStyle: TextStyle(
          color: isDark ? Colors.black : Colors.white,
          fontSize: desk ? 11.5 : 13,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          height: 1.0,
        ),
      ),
      child: Slider(
        value: value,
        min: min,
        max: max,
        divisions: divisions,
        label: labelBuilder(value),
        onChanged: (v) {
          if (enableHaptics) HapticFeedback.selectionClick();
          onChanged(v);
        },
      ),
    );
  }
}

// ── Custom Thumb ─────────────────────────────────────────────────────────────

class _TRLinearThumbShape extends SliderComponentShape {
  final bool isDark;
  final bool compact;
  const _TRLinearThumbShape({
    required this.isDark,
    this.compact = false,
  });

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      Size.fromRadius(compact ? 11.0 : 14.0);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    final base = compact ? 9.5 : 12.0;
    final bump = compact ? 2.0 : 3.0;
    final radius = base + activationAnimation.value * bump;
    final thumbColor = isDark ? Colors.white : Colors.black;
    final dotColor = isDark
        ? Colors.black.withValues(alpha: 0.4)
        : Colors.white.withValues(alpha: 0.4);

    // Main thumb circle
    canvas.drawCircle(center, radius, Paint()..color = thumbColor);

    // Small center dot for depth
    canvas.drawCircle(
      center,
      2.5 + activationAnimation.value * 0.8,
      Paint()..color = dotColor,
    );
  }
}

// ── Custom Track ─────────────────────────────────────────────────────────────

class _TRLinearTrackShape extends RoundedRectSliderTrackShape {
  const _TRLinearTrackShape();

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final h = sliderTheme.trackHeight ?? 6.0;
    final top = offset.dy + (parentBox.size.height - h) / 2;
    return Rect.fromLTWH(offset.dx, top, parentBox.size.width, h);
  }
}

// ── Floating Value Pill (always visible above thumb) ─────────────────────────

class _TRLinearValueIndicatorShape extends SliderComponentShape {
  const _TRLinearValueIndicatorShape();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(1, 1);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    final pillColor = sliderTheme.valueIndicatorColor ?? Colors.black;

    labelPainter.layout();
    final tw = labelPainter.width;
    final th = labelPainter.height;

    const pillH = 32.0;
    final pillW = tw + 22.0;
    const arrowH = 7.0;
    // Distance from thumb center to bottom of pill
    const liftAbove = 15.0 + pillH + arrowH;

    // Clamp so pill never overflows the track left/right
    final pillLeft =
        (center.dx - pillW / 2).clamp(0.0, parentBox.size.width - pillW);
    final pillTop = center.dy - liftAbove;

    // Pill background
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(pillLeft, pillTop, pillW, pillH),
        const Radius.circular(10),
      ),
      Paint()..color = pillColor,
    );

    // Small downward arrow connecting pill to thumb
    final arrowX = center.dx.clamp(pillLeft + 8, pillLeft + pillW - 8);
    final arrowPath = Path()
      ..moveTo(arrowX - 5, pillTop + pillH)
      ..lineTo(arrowX + 5, pillTop + pillH)
      ..lineTo(arrowX, pillTop + pillH + arrowH)
      ..close();
    canvas.drawPath(arrowPath, Paint()..color = pillColor);

    // Value text centred inside pill
    labelPainter.paint(
      canvas,
      Offset(
        pillLeft + (pillW - tw) / 2,
        pillTop + (pillH - th) / 2,
      ),
    );
  }
}
