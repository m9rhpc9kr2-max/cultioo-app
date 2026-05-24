import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';

/// Reusable Trade Republic styled drag handle for bottom sheets
/// Features a subtle bounce pulse animation on appear
class DragHandle extends StatefulWidget {
  const DragHandle({super.key});

  @override
  State<DragHandle> createState() => _DragHandleState();
}

class _DragHandleState extends State<DragHandle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _widthAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _widthAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 18.0, end: 40.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 40.0, end: 26.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 25,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 26.0, end: 34.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 20,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 34.0, end: 32.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 20,
      ),
    ]).animate(_controller);

    // Start the bounce after a small delay so it syncs with the sheet
    Future.delayed(const Duration(milliseconds: 250), () {
      if (mounted) {
        HapticFeedback.selectionClick();
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Never show drag handle on desktop platforms
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      return const SizedBox.shrink();
    }

    final brightness = Theme.of(context).brightness;
    final isLight = brightness == Brightness.light;

    return Center(
      child: AnimatedBuilder(
        animation: _widthAnimation,
        builder: (context, child) {
          return Container(
            width: _widthAnimation.value,
            height: 8,
            margin: const EdgeInsets.only(top: 12, bottom: 6),
            decoration: BoxDecoration(
              color: (isLight ? Colors.black : Colors.white),
              borderRadius: BorderRadius.circular(25),
            ),
          );
        },
      ),
    );
  }
}
