// cultioo_spinner.dart — logo · floating side dots · Trade Republic style
// ignore_for_file: library_private_types_in_public_api

import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'cultioo_desktop_layout.dart';

Color _ink(bool isDark) => isDark ? Colors.white : Colors.black;
String _logoAsset(bool isDark) =>
    isDark ? 'logo/cultioo_3_logo_white.png' : 'logo/cultioo_3_logo_dark.png';

// ════════════════════════════════════════════════════════════════════════════
// PUBLIC: Pull-to-refresh sliver
// ════════════════════════════════════════════════════════════════════════════

class CultiooSliverRefreshControl extends StatelessWidget {
  final Future<void> Function() onRefresh;
  const CultiooSliverRefreshControl({super.key, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    // Use standard iOS/macOS refresh control spinner
    return CupertinoSliverRefreshControl(
      onRefresh: onRefresh,
      refreshTriggerPullDistance: 80.0,
      refreshIndicatorExtent: 60.0,
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// PUBLIC: Inline loading indicator — Apple style spinner
// ════════════════════════════════════════════════════════════════════════════

class CultiooLoadingIndicator extends StatelessWidget {
  final double size;
  const CultiooLoadingIndicator({super.key, this.size = 80});

  @override
  Widget build(BuildContext context) {
    // Use standard iOS/macOS activity indicator
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: CupertinoActivityIndicator(
          radius: CultiooDesktopLayout.isDesktopPlatform ? 10.0 : 14.0,
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// PRIVATE: Simple pull-to-refresh indicator — pulsating logo only
// ════════════════════════════════════════════════════════════════════════════

class _SimplePullRefreshIndicator extends StatefulWidget {
  final RefreshIndicatorMode state;
  final double pulledExtent;
  final double triggerDistance;

  const _SimplePullRefreshIndicator({
    required this.state,
    required this.pulledExtent,
    required this.triggerDistance,
  });

  @override
  State<_SimplePullRefreshIndicator> createState() => _SimplePullRefreshIndicatorState();
}

class _SimplePullRefreshIndicatorState extends State<_SimplePullRefreshIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );
  }

  @override
  void didUpdateWidget(_SimplePullRefreshIndicator old) {
    super.didUpdateWidget(old);
    switch (widget.state) {
      case RefreshIndicatorMode.refresh:
        if (!_pulseCtrl.isAnimating) _pulseCtrl.repeat(reverse: true);
      case RefreshIndicatorMode.done:
        _pulseCtrl.stop();
      default:
        _pulseCtrl.stop();
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final progress = (widget.pulledExtent / widget.triggerDistance).clamp(0.0, 1.0);
    final clampedH = widget.pulledExtent.clamp(0.0, 80.0);
    final isRefreshing = widget.state == RefreshIndicatorMode.refresh;

    return SizedBox(
      height: clampedH,
      child: Center(
        child: AnimatedBuilder(
          animation: _pulseCtrl,
          builder: (context, child) {
            final scale = isRefreshing
                ? 0.72 + (1.0 - 0.72) * Curves.easeInOut.transform(_pulseCtrl.value)
                : 0.5 + (progress * 0.5);
            final opacity = isRefreshing
                ? 0.40 + (1.0 - 0.40) * Curves.easeInOut.transform(_pulseCtrl.value)
                : progress;

            return Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: Transform.scale(
                scale: scale,
                child: child,
              ),
            );
          },
          child: Image.asset(
            _logoAsset(isDark),
            width: 56,
            height: 56,
            filterQuality: FilterQuality.medium,
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// PRIVATE: Pull-to-refresh indicator — floating dots + logo (UNUSED - kept for reference)
// ════════════════════════════════════════════════════════════════════════════

// ignore: unused_element
class _PullRefreshIndicator extends StatefulWidget {
  final RefreshIndicatorMode state;
  final double pulledExtent;
  final double triggerDistance;

  const _PullRefreshIndicator({
    required this.state,
    required this.pulledExtent,
    required this.triggerDistance,
  });

  @override
  State<_PullRefreshIndicator> createState() => _PullRefreshIndicatorState();
}

class _PullRefreshIndicatorState extends State<_PullRefreshIndicator>
    with TickerProviderStateMixin {
  late final AnimationController _rotCtrl;
  late final AnimationController _snapCtrl;
  bool _hasSnapped = false;

  @override
  void initState() {
    super.initState();
    _rotCtrl = AnimationController(
      duration: const Duration(milliseconds: 1100),
      vsync: this,
    );
    _snapCtrl = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
  }

  @override
  void didUpdateWidget(_PullRefreshIndicator old) {
    super.didUpdateWidget(old);
    switch (widget.state) {
      case RefreshIndicatorMode.drag:
        _hasSnapped = false;
        _rotCtrl.stop();
      case RefreshIndicatorMode.armed:
        if (!_hasSnapped) {
          _hasSnapped = true;
          _snapCtrl.forward(from: 0).then((_) {
            if (mounted && !_rotCtrl.isAnimating) _rotCtrl.repeat();
          });
        }
      case RefreshIndicatorMode.refresh:
        if (!_rotCtrl.isAnimating) _rotCtrl.repeat();
      case RefreshIndicatorMode.done:
        _rotCtrl.stop();
        _hasSnapped = false;
      default:
        _rotCtrl.stop();
        _hasSnapped = false;
    }
  }

  @override
  void dispose() {
    _rotCtrl.dispose();
    _snapCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = _ink(isDark);
    final p = (widget.pulledExtent / widget.triggerDistance).clamp(0.0, 1.0);
    final clampedH = widget.pulledExtent.clamp(0.0, 120.0);

    const canvas = 120.0;

    return SizedBox(
      height: clampedH,
      child: Center(
        child: AnimatedBuilder(
          animation: Listenable.merge([_rotCtrl, _snapCtrl]),
          builder: (context, child) {
            final spinning  = _rotCtrl.isAnimating;
            final rotVal    = _rotCtrl.value;
            final snapScale = 1.0 + sin(_snapCtrl.value * pi) * 0.10;
            final logoT     = ((p - 0.20) / 0.80).clamp(0.0, 1.0);
            // Drag: grows + rotates 180°. Loading: fixed at 180° + pulse. Release: returns to 0°.
            final logoBase  = spinning ? 1.0 : Curves.easeOutBack.transform(logoT);
            final logoPulse = spinning ? (1.0 + sin(rotVal * 2 * pi) * 0.06) : 1.0;
            final logoScale = (logoBase * snapScale * logoPulse).clamp(0.0, 1.5);
            final logoAngle = spinning ? pi : p * pi;

            return SizedBox(
              width:  canvas,
              height: canvas,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size(canvas, canvas),
                    painter: _RefreshPainter(
                      progress:   p,
                      rotVal:     rotVal,
                      isSpinning: spinning,
                      ink:        ink,
                    ),
                  ),
                  if (logoT > 0)
                    Opacity(
                      opacity: logoT.clamp(0.0, 1.0),
                      child: Transform.scale(
                        scale: logoScale,
                        child: Transform.rotate(
                          angle: logoAngle,
                          child: child,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
          child: Image.asset(
            _logoAsset(isDark),
            width:  56,
            height: 56,
            filterQuality: FilterQuality.medium,
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// PAINTERS
// ════════════════════════════════════════════════════════════════════════════

/// Floating side dots only — no ring, no arc, no comet.
class _RefreshPainter extends CustomPainter {
  final double progress;
  final double rotVal;
  final bool   isSpinning;
  final Color  ink;

  const _RefreshPainter({
    required this.progress,
    required this.rotVal,
    required this.isSpinning,
    required this.ink,
  });

  // [nx 0..1, phase 0..1, radius]
  static const List<List<double>> _dots = [
    [0.14, 0.00, 2.6],
    [0.20, 0.40, 1.8],
    [0.10, 0.70, 2.1],
    [0.86, 0.20, 2.6],
    [0.80, 0.60, 1.8],
    [0.90, 0.85, 2.1],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final dotPaint = Paint()..style = PaintingStyle.fill;
    for (final d in _dots) {
      final nx = d[0];
      final po = d[1];
      final dr = d[2];
      final x  = nx * size.width;
      double y, opacity;

      if (isSpinning) {
        final t = ((rotVal + po) % 1.0);
        y       = size.height * (0.95 - t * 0.90);
        opacity = sin(t * pi).clamp(0.0, 1.0) * 0.45;
      } else {
        final thr = po * 0.50;
        if (progress <= thr) continue;
        final lp = ((progress - thr) / (1.0 - thr)).clamp(0.0, 1.0);
        y        = size.height * (0.85 - lp * 0.60);
        opacity  = (lp * 1.5).clamp(0.0, 0.40);
      }

      dotPaint.color = ink.withValues(alpha: opacity);
      canvas.drawCircle(Offset(x, y), dr, dotPaint);
    }
  }

  @override
  bool shouldRepaint(_RefreshPainter old) =>
      old.progress   != progress   ||
      old.rotVal     != rotVal     ||
      old.isSpinning != isSpinning ||
      old.ink        != ink;
}

/// Hairline ghost ring — unused, kept for reference.
// ignore: unused_element
class _TrackPainter extends CustomPainter {
  final Color ink;
  final double strokeWidth;
  const _TrackPainter({required this.ink, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      size.width / 2 - strokeWidth / 2,
      Paint()
        ..color = ink.withValues(alpha: 0.09)
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_TrackPainter old) => old.ink != ink;
}

/// Sweeping comet — unused, kept for reference.
// ignore: unused_element
class _CometPainter extends CustomPainter {
  final double angle;
  final Color ink;
  final double strokeWidth;
  const _CometPainter(
      {required this.angle, required this.ink, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - strokeWidth / 2;
    const tail  = pi * 0.72;
    const steps = 24;
    final paint = Paint()
      ..style    = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < steps; i++) {
      final frac = i / steps;
      paint
        ..color      = ink.withValues(alpha: frac * 0.56)
        ..strokeWidth = strokeWidth * (0.18 + frac * 0.82);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r),
        angle - tail * frac,
        tail / steps,
        false, paint,
      );
    }
    canvas.drawCircle(
      Offset(center.dx + cos(angle) * r, center.dy + sin(angle) * r),
      strokeWidth * 0.9,
      Paint()..color = ink.withValues(alpha: 0.88),
    );
  }

  @override
  bool shouldRepaint(_CometPainter old) =>
      old.angle != angle || old.ink != ink;
}
