import 'package:flutter/material.dart';
import 'dart:io';
// For min/max if needed

class SplashScreen extends StatefulWidget {
  final VoidCallback onInitComplete;

  const SplashScreen({super.key, required this.onInitComplete});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  
  // New animations for the "opening walls" effect
  late Animation<Offset> _leftWallAnimation;
  late Animation<Offset> _rightWallAnimation;
  
  // Custom curve for movement - Apple-like fluid spring/ease
  final Curve _moveCurve = const Cubic(0.2, 0.0, 0.2, 1.0); // Smooth easing

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500), // Fast animation (1.5 seconds)
      vsync: this,
    );

    // 1. Fade in Logo (0.0 -> 0.2)
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.2, curve: Curves.easeOutQuad),
      ),
    );

    // 2. Scale up Logo slightly (intro pulse)
    _scaleAnimation = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.3, curve: Curves.easeOutBack),
      ),
    );

    // 3. Walls opening (slide out to sides) - 0.4 -> 1.0
    // Starts slow, accelerates, then decelerates
    _leftWallAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(-1.0, 0.0),
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Interval(0.4, 1.0, curve: _moveCurve),
      ),
    );

    _rightWallAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(1.0, 0.0),
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Interval(0.4, 1.0, curve: _moveCurve),
      ),
    );
    
    _controller.forward();

    // Wait for animation to complete
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        widget.onInitComplete();
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? Colors.black : Colors.white;

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final screenHeight = constraints.maxHeight;
        final topPadding = MediaQuery.of(context).padding.top;

        // Target Position (macOS Sidebar)
        final targetTop = topPadding + 48.0; 
        final targetLeft = 24.0;
        final targetHeight = 75.0;

        // Start Position (Center)
        // Center of screen minus half of logo size
        // We'll calculate a "start height" assuming the logo has roughly a 3.5:1 aspect ratio
        // If width is 600, height is roughly 170.
        // We want the CENTER of the logo to be at the CENTER of the screen.
        final startHeight = 170.0;
        final startWidth = 600.0; // This is the constraint width, actual image width might vary
        
        final startTop = (screenHeight - startHeight) / 2;
        // Since we align left/top in Positioned, we need (ScreenW - LogoW) / 2
        final startLeft = (screenWidth - startWidth) / 2;

        return Stack(
          children: [
            // Left Wall
            SlideTransition(
              position: _leftWallAnimation,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: screenWidth / 2 + 1, // +1 overlap to prevent hairline gap
                  height: double.infinity,
                  decoration: BoxDecoration(
                    color: backgroundColor,
                  ),
                ),
              ),
            ),
            
            // Right Wall
            SlideTransition(
              position: _rightWallAnimation,
              child: Align(
                alignment: Alignment.centerRight,
                child: Container(
                  width: screenWidth / 2 + 1, // +1 overlap
                  height: double.infinity,
                  decoration: BoxDecoration(
                    color: backgroundColor,
                  ),
                ),
              ),
            ),
            
            // Logo Animation Layer
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                // Calculate move progress (starts at 0.4, lasts until 1.0)
                // Range 0.4 -> 1.0 = 0.6 total duration
                double t = ((_controller.value - 0.4) / 0.6).clamp(0.0, 1.0);
                t = _moveCurve.transform(t);

                // Interpolate position
                double currentLeft = startLeft + (targetLeft - startLeft) * t;
                double currentTop = startTop + (targetTop - startTop) * t;
                
                // Interpolate size
                // We transition from using Height 170 to Height 75
                double currentHeight = startHeight + (targetHeight - startHeight) * t;
                // Transition width constraint as well to keep aspect ratio safe
                double currentWidth = startWidth + (280.0 - startWidth) * t; 

                // Opacity logic (same as fade animation)
                double opacity = _fadeAnimation.value;
                
                if (!Platform.isMacOS && t > 0) {
                   currentTop = startTop + (-200 - startTop) * t;
                   opacity = 1.0 - t; 
                }

                // Interpolate Alignment: Center -> Left
                final Alignment currentAlignment = Alignment.lerp(
                  Alignment.center, 
                  Alignment.centerLeft, 
                  t
                )!;

                return Positioned(
                  left: currentLeft,
                  top: currentTop,
                  height: currentHeight,
                  width: currentWidth, 
                  child: Opacity(
                    opacity: opacity,
                    child: Transform.scale(
                      scale: t == 0 ? _scaleAnimation.value : 1.0,
                      alignment: Alignment.center,
                      child: Image.asset(
                        isDark
                            ? 'logo/cultioo_word_transparent_darkmode.png'
                            : 'logo/cultioo_word_transparent_whitemode.png',
                        fit: BoxFit.contain,
                        alignment: currentAlignment,
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}
