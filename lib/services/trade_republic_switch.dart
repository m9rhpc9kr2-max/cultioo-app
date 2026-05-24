import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'dart:io';

import 'cultioo_desktop_layout.dart';

/// Trade Republic styled toggle switch.
///
/// On iOS uses the native CNSwitch (system green when on, system gray when off
/// — iOS only exposes the on-tint colour). On all other platforms a custom
/// pill switch is rendered with: On = green, Off = red (overridable via
/// [selectedColor] / [unselectedColor]).
class TradeRepublicSwitch extends StatefulWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  /// Kept for API compatibility — not rendered in the pill switch.
  final String selectedLabel;
  final String unselectedLabel;

  /// Background color when the switch is ON. Defaults to green.
  final Color? selectedColor;

  /// Background color when the switch is OFF. Defaults to red.
  final Color? unselectedColor;

  /// Logical track height. The track width is `size * 1.7`.
  final double size;

  const TradeRepublicSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.selectedLabel = 'Y',
    this.unselectedLabel = 'N',
    this.selectedColor,
    this.unselectedColor,
    this.size = 44,
  });

  @override
  State<TradeRepublicSwitch> createState() => _TradeRepublicSwitchState();
}

class _TradeRepublicSwitchState extends State<TradeRepublicSwitch> {
  static final bool _isIOS = Platform.isIOS;
  CNSwitchController? _controller;

  @override
  void initState() {
    super.initState();
    if (_isIOS) {
      _controller = CNSwitchController();
    }
  }

  void _handleTap() {
    if (widget.onChanged != null) {
      HapticFeedback.lightImpact();
      widget.onChanged!(!widget.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    // iOS: use the native system switch (green on-tint, system gray off).
    if (_isIOS) {
      const onColor = Color(0xFF34C759); // iOS system green
      return CNSwitch(
        value: widget.value,
        onChanged: (val) => widget.onChanged?.call(val),
        controller: _controller,
        color: widget.selectedColor ?? onColor,
      );
    }

    // Match previous sizing: the old implementation rendered as a circle of
    // dimension `size`. The pill switch reuses the same height so the widget
    // keeps roughly the same vertical footprint in existing layouts.
    final trackHeight = CultiooDesktopLayout.isDesktopPlatform && widget.size == 44
        ? 30.0
        : (CultiooDesktopLayout.isDesktopPlatform && widget.size == 36
            ? 28.0
            : widget.size * 0.72);
    final trackWidth = trackHeight * 1.7;
    final thumbSize = trackHeight - 4;

    const onColor = Color(0xFF34C759); // iOS system green
    const offColor = Color(0xFFFF3B30); // iOS system red

    final bgColor = widget.value
        ? (widget.selectedColor ?? onColor)
        : (widget.unselectedColor ?? offColor);

    final isDisabled = widget.onChanged == null;

    return Opacity(
      opacity: isDisabled ? 0.5 : 1.0,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: isDisabled ? null : _handleTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          width: trackWidth,
          height: trackHeight,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(trackHeight / 2),
          ),
          child: Stack(
            children: [
              AnimatedAlign(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment:
                    widget.value ? Alignment.centerRight : Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Container(
                    width: thumbSize,
                    height: thumbSize,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 3,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
