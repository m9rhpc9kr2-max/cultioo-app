import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'cultioo_spinner.dart';
import 'pointer_safe.dart';

bool get _isDesktop =>
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.windows ||
    defaultTargetPlatform == TargetPlatform.linux;

/// Primary label buttons: default height (compact on phone + desktop).
const double _kButtonHeightDefault = 48;
const double _kButtonHeightLegacyTall = 56;

/// Trade Republic styled button with clean, minimal design
/// Supports both label-only and icon-only variants
/// Compatible with iOS, Android, macOS, and web
class TradeRepublicButton extends StatefulWidget {
  final String? label;
  final VoidCallback? onPressed;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? tint; // For CNButton compatibility
  final Widget? icon;
  final bool isLoading;
  final bool isDestructive;
  final bool isSecondary;
  final double? width;
  final double height;
  final EdgeInsets? padding;
  final BorderRadius? borderRadius;
  final bool showShadow;

  const TradeRepublicButton({
    super.key,
    this.label,
    this.onPressed,
    this.backgroundColor,
    this.foregroundColor,
    this.tint,
    this.icon,
    this.isLoading = false,
    this.isDestructive = false,
    this.isSecondary = false,
    this.width,
    this.height = _kButtonHeightDefault,
    this.padding,
    this.borderRadius,
    this.showShadow = true,
  });

  /// Creates an icon-only button (circular)
  factory TradeRepublicButton.icon({
    Key? key,
    required Widget icon,
    VoidCallback? onPressed,
    Color? backgroundColor,
    Color? foregroundColor,
    Color? tint,
    double size = 40,
    bool isSecondary = false,
  }) {
    return _TradeRepublicIconButton(
      key: key,
      iconWidget: icon,
      onPressed: onPressed,
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      tint: tint,
      size: size,
      isSecondary: isSecondary,
    );
  }

  @override
  State<TradeRepublicButton> createState() => _TradeRepublicButtonState();
}

class _TradeRepublicButtonState extends State<TradeRepublicButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnim;
  bool _isPressed = false;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: _isDesktop ? 0.99 : 0.97).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    if (widget.onPressed != null && !widget.isLoading) {
      Future.microtask(() {
        if (mounted) setState(() => _isPressed = true);
        _animController.forward();
      });
    }
  }

  void _handleTapUp(TapUpDetails details) {
    Future.microtask(() {
      if (mounted) setState(() => _isPressed = false);
      _animController.reverse();
    });
  }

  void _handleTapCancel() {
    Future.microtask(() {
      if (mounted) setState(() => _isPressed = false);
      _animController.reverse();
    });
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isLight = brightness == Brightness.light;
    final isEnabled = widget.onPressed != null && !widget.isLoading;

    final effectiveHeight = _resolveLabelButtonHeight(widget.height);
    // Icon-only buttons (no label, no explicit width) → square + circular
    final isSmallIconOnly = widget.label == null && widget.icon != null && widget.width == null;
    final borderRadius = widget.borderRadius ?? (
        isSmallIconOnly
            ? BorderRadius.circular(effectiveHeight / 2)
            : BorderRadius.circular(_isDesktop ? 10 : 16));
    // Desktop: constrain *implicit* width (null) for centered modals.
    // If callers pass `double.infinity`, keep it so parents like `SizedBox(width: double.infinity)`
    // can still build a full-width bar (e.g. driver scan sheets).
    const desktopMaxWidth = 200.0;
    final effectiveWidth = isSmallIconOnly
        ? effectiveHeight
        : (widget.width == null && _isDesktop)
            ? desktopMaxWidth
            : widget.width;

    final labelFontSize = _isDesktop ? 13.0 : 15.0;
    final labelIconSize = _isDesktop ? 17.0 : 18.0;
    final loadingIndicatorSize = _isDesktop ? 16.0 : 18.0;
    final horizontalContentPadding = _isDesktop ? 18.0 : 20.0;

    final buttonChild = AnimatedBuilder(
      animation: _scaleAnim,
      builder: (context, child) {
        final hovered = _isHovered && isEnabled;
        final pressed = _isPressed && isEnabled;

        Color baseBg;
        Color baseFg;

        if (widget.isSecondary || widget.isDestructive) {
          baseBg = isLight ? Colors.black.withValues(alpha: 0.05) : Colors.transparent;
          baseFg = isLight ? Colors.black : Colors.white;
        } else {
          baseBg = isLight ? Colors.black : Colors.white;
          baseFg = isLight ? Colors.white : Colors.black;
        }

        if (widget.backgroundColor != null) baseBg = widget.backgroundColor!;
        if (widget.foregroundColor != null) baseFg = widget.foregroundColor!;

        var renderedBg = baseBg;
        var renderedFg = baseFg;

        if (pressed) {
          renderedBg = (widget.isSecondary || widget.isDestructive)
              ? (isLight
                  ? Colors.black.withValues(alpha: 0.12)
                  : Colors.white.withValues(alpha: 0.14))
              : baseBg.withValues(alpha: 0.82);
        } else if (hovered) {
          renderedBg = (widget.isSecondary || widget.isDestructive)
              ? (isLight
                  ? Colors.black.withValues(alpha: 0.09)
                  : Colors.white.withValues(alpha: 0.09))
              : baseBg.withValues(alpha: 0.90);
        }

        if (!isEnabled) {
          renderedBg = renderedBg.withValues(alpha: 0.45);
          renderedFg = renderedFg.withValues(alpha: 0.55);
        }

        return Transform.scale(
          scale: _scaleAnim.value,
          child: MouseRegion(
            cursor: isEnabled
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            onEnter: (_) {
              scheduleAfterPointerUpdate(() {
                if (!mounted) return;
                setState(() => _isHovered = true);
              });
            },
            onExit: (_) {
              scheduleAfterPointerUpdate(() {
                if (!mounted) return;
                setState(() => _isHovered = false);
              });
            },
            child: GestureDetector(
              onTapDown: _handleTapDown,
              onTapUp: _handleTapUp,
              onTapCancel: _handleTapCancel,
                onTap: isEnabled ? widget.onPressed : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: effectiveWidth,
                height: effectiveHeight,
                padding:
                  widget.padding ??
                  (isSmallIconOnly
                    ? EdgeInsets.zero
                    : EdgeInsets.symmetric(horizontal: horizontalContentPadding)),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: renderedBg,
                  borderRadius: borderRadius,
                ),
                child: widget.isLoading
                    ? SizedBox(
                        width: loadingIndicatorSize,
                        height: loadingIndicatorSize,
                        child: CultiooLoadingIndicator(size: loadingIndicatorSize),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (widget.icon != null) ...[
                            IconTheme(
                              data: IconThemeData(
                                color: renderedFg,
                                size: labelIconSize,
                              ),
                              child: widget.icon!,
                            ),
                            if (widget.label != null) SizedBox(width: 6),
                          ],
                          if (widget.label != null)
                            Flexible(
                              child: Text(
                                widget.label!,
                                style: TextStyle(
                                  color: renderedFg,
                                  fontSize: labelFontSize,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.2,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
              ),
            ),
          ),
        );
      },
    );

    if (_isDesktop && widget.width == null && !isSmallIconOnly) {
      return Align(alignment: Alignment.center, child: buttonChild);
    }
    return buttonChild;
  }

  /// Slightly shorter on phone; extra compact on desktop for the default sizes.
  static double _resolveLabelButtonHeight(double height) {
    if (_isDesktop) {
      if (height == _kButtonHeightLegacyTall || height == _kButtonHeightDefault) {
        return 32;
      }
      return height;
    }
    if (height == _kButtonHeightLegacyTall) {
      return _kButtonHeightDefault;
    }
    if (height == _kButtonHeightDefault) {
      return 44;
    }
    return height;
  }
}

/// Icon-only variant of TradeRepublicButton
class _TradeRepublicIconButton extends TradeRepublicButton {
  final Widget iconWidget;
  final double size;

  const _TradeRepublicIconButton({
    super.key,
    required this.iconWidget,
    super.onPressed,
    super.backgroundColor,
    super.foregroundColor,
    super.tint,
    this.size = 40,
    super.isSecondary,
  }) : super(icon: iconWidget);

  @override
  State<TradeRepublicButton> createState() => _TradeRepublicIconButtonState();
}

class _TradeRepublicIconButtonState extends State<_TradeRepublicIconButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnim;
  bool _isPressed = false;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: _isDesktop ? 0.95 : 0.92).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    if (widget.onPressed != null) {
      Future.microtask(() {
        if (mounted) setState(() => _isPressed = true);
        _animController.forward();
      });
    }
  }

  void _handleTapUp(TapUpDetails details) {
    Future.microtask(() {
      if (mounted) setState(() => _isPressed = false);
      _animController.reverse();
    });
  }

  void _handleTapCancel() {
    Future.microtask(() {
      if (mounted) setState(() => _isPressed = false);
      _animController.reverse();
    });
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isLight = brightness == Brightness.light;
    final isEnabled = widget.onPressed != null;

    final effectiveSize = _isDesktop
        ? (widget.size == 44
            ? 32.0
            : widget.size == 40
                ? 30.0
                : widget.size == 38
                    ? 30.0
                    : widget.size)
        : (widget.size == 44
            ? 40.0
            : widget.size == 40
                ? 38.0
                : widget.size);

    return AnimatedBuilder(
      animation: _scaleAnim,
      builder: (context, child) {
        final hovered = _isHovered && isEnabled;
        final pressed = _isPressed && isEnabled;

        Color baseBg;
        Color baseFg;

        if (widget.isSecondary) {
          baseBg = isLight ? Colors.black.withValues(alpha: 0.05) : Colors.transparent;
          baseFg = isLight ? Colors.black : Colors.white;
        } else {
          baseBg = isLight ? Colors.black : Colors.white;
          baseFg = isLight ? Colors.white : Colors.black;
        }

        if (widget.backgroundColor != null) baseBg = widget.backgroundColor!;
        if (widget.foregroundColor != null) baseFg = widget.foregroundColor!;

        var renderedBg = baseBg;
        var renderedFg = baseFg;

        if (pressed) {
          renderedBg = widget.isSecondary
              ? (isLight
                  ? Colors.black.withValues(alpha: 0.12)
                  : Colors.white.withValues(alpha: 0.14))
              : baseBg.withValues(alpha: 0.82);
        } else if (hovered) {
          renderedBg = widget.isSecondary
              ? (isLight
                  ? Colors.black.withValues(alpha: 0.09)
                  : Colors.white.withValues(alpha: 0.09))
              : baseBg.withValues(alpha: 0.90);
        }

        if (!isEnabled) {
          renderedBg = renderedBg.withValues(alpha: 0.45);
          renderedFg = renderedFg.withValues(alpha: 0.55);
        }

        return Transform.scale(
          scale: _scaleAnim.value,
          child: MouseRegion(
            cursor: isEnabled
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            onEnter: (_) {
              scheduleAfterPointerUpdate(() {
                if (!mounted) return;
                setState(() => _isHovered = true);
              });
            },
            onExit: (_) {
              scheduleAfterPointerUpdate(() {
                if (!mounted) return;
                setState(() => _isHovered = false);
              });
            },
            child: GestureDetector(
              onTapDown: _handleTapDown,
              onTapUp: _handleTapUp,
              onTapCancel: _handleTapCancel,
              onTap: widget.onPressed,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: effectiveSize,
                height: effectiveSize,
                decoration: BoxDecoration(
                  color: renderedBg,
                  borderRadius: BorderRadius.circular(effectiveSize / 2),
                ),
                child: Center(
                  child: IconTheme(
                    data: IconThemeData(
                      color: renderedFg,
                      size: _isDesktop ? 16.5 : 18.0,
                    ),
                    child: widget.iconWidget,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Helper extension to create Trade Republic buttons matching iOS CNButton API
extension TradeRepublicButtonHelper on TradeRepublicButton {
  /// Creates a Trade Republic button that matches CNButton parameters
  static Widget fromCNButton({
    required String label,
    required VoidCallback? onPressed,
    Color? tint,
    bool isLight = true,
  }) {
    return TradeRepublicButton(
      label: label,
      onPressed: onPressed,
      backgroundColor: tint ?? (isLight ? Colors.black : Colors.white),
      foregroundColor: isLight ? Colors.white : Colors.black,
    );
  }

  /// Creates a Trade Republic icon button that matches CNButton.icon parameters
  static Widget iconFromCN({
    required Widget icon,
    required VoidCallback? onPressed,
    Color? tint,
    bool isLight = true,
    double size = 40,
  }) {
    return TradeRepublicButton.icon(
      icon: icon,
      onPressed: onPressed,
      backgroundColor: tint ?? (isLight ? Colors.black : Colors.white),
      foregroundColor: isLight ? Colors.white : Colors.black,
      size: size,
    );
  }
}
