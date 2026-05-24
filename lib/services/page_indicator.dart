import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';

class PageIndicator extends StatefulWidget {
  final int currentPage;
  final int pageCount;
  final PageController pageController;
  final ValueChanged<int>? onTap;

  const PageIndicator({
    super.key,
    required this.currentPage,
    required this.pageCount,
    required this.pageController,
    this.onTap,
  });

  @override
  State<PageIndicator> createState() => _PageIndicatorState();
}

class _PageIndicatorState extends State<PageIndicator> {
  int? _pressedIndex;
  double _dragOffset = 0;

  void _navigateTo(int index) {
    if (widget.onTap != null) {
      widget.onTap!(index);
    } else {
      widget.pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? Colors.white : Colors.black;

    return GestureDetector(
      onLongPressStart: (details) {
        HapticFeedback.mediumImpact();
        setState(() {
          _pressedIndex = widget.currentPage;
          _dragOffset = 0;
        });
      },
      onLongPressMoveUpdate: (details) {
        setState(() {
          _dragOffset = details.localOffsetFromOrigin.dx;
        });
        const dotSpacing = 16.0;
        final dragPages = (_dragOffset / dotSpacing).round();
        final targetPage =
            (widget.currentPage + dragPages).clamp(0, widget.pageCount - 1);
        if (targetPage != _pressedIndex) {
          HapticFeedback.selectionClick();
          _pressedIndex = targetPage;
        }
      },
      onLongPressEnd: (details) {
        if (_pressedIndex != null && _pressedIndex != widget.currentPage) {
          _navigateTo(_pressedIndex!);
        }
        setState(() {
          _pressedIndex = null;
          _dragOffset = 0;
        });
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            decoration: BoxDecoration(
              color: ink.withOpacity(0.07),
              borderRadius: BorderRadius.circular(32),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(widget.pageCount, (index) {
                final isActive = widget.currentPage == index;
                final isPressed = _pressedIndex == index;
                final scale = isPressed ? 1.35 : 1.0;

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (index != widget.currentPage) {
                      HapticFeedback.selectionClick();
                      _navigateTo(index);
                    }
                  },
                  child: AnimatedScale(
                    scale: scale,
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeInOut,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeInOut,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: isActive ? 22 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: isActive
                            ? ink.withOpacity(0.90)
                            : isPressed
                                ? ink.withOpacity(0.55)
                                : ink.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}
