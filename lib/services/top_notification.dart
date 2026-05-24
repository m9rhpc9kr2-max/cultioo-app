import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../services/app_localizations.dart';

enum NotificationType { success, error, warning, info }

class TopNotification {
  static OverlayEntry? _currentOverlay;
  static bool _isShowing = false;
  static VoidCallback? _currentDismissCallback;
  static bool _isDismissing = false;

  static void show(
    BuildContext context, {
    required String message,
    NotificationType type = NotificationType.info,
    Duration duration = const Duration(seconds: 3),
    String? title,
    IconData? customIcon,
  }) {
    // If already dismissing, wait and retry
    if (_isDismissing) {
      Future.delayed(const Duration(milliseconds: 50), () {
        show(context, message: message, type: type, duration: duration, title: title, customIcon: customIcon);
      });
      return;
    }

    // Remove previous immediately (no animation) to avoid doubles
    if (_isShowing && _currentOverlay != null) {
      _forceRemove();
    }

    _isShowing = true;

    final overlay = Overlay.of(context);
    final overlayEntry = OverlayEntry(
      builder: (context) => TopNotificationWidget(
        message: message,
        type: type,
        title: title,
        customIcon: customIcon,
        onDismiss: () {},
        onDismissAnimated: (callback) => _currentDismissCallback = callback,
      ),
    );

    _currentOverlay = overlayEntry;
    overlay.insert(overlayEntry);

    // Auto hide after duration
    Future.delayed(duration, () {
      if (_currentOverlay == overlayEntry && _isShowing) {
        hide();
      }
    });
  }

  /// Force-remove without animation (used when replacing with new notification)
  static void _forceRemove() {
    _currentDismissCallback = null;
    try {
      _currentOverlay?.remove();
    } catch (_) {}
    _currentOverlay = null;
    _isShowing = false;
    _isDismissing = false;
  }

  static void hide() {
    if (_currentOverlay != null && _isShowing && !_isDismissing) {
      if (_currentDismissCallback != null) {
        _isDismissing = true;
        _currentDismissCallback!();
        _currentDismissCallback = null;
      } else {
        _forceRemove();
      }
    }
  }

  /// Called by the widget after dismiss animation completes
  static void _onDismissComplete() {
    try {
      _currentOverlay?.remove();
    } catch (_) {}
    _currentOverlay = null;
    _isShowing = false;
    _isDismissing = false;
    _currentDismissCallback = null;
  }

  // Convenience methods
  static void success(BuildContext context, String message, {String? title}) {
    show(
      context,
      message: message,
      type: NotificationType.success,
      title: title,
    );
  }

  static void error(BuildContext context, String message, {String? title}) {
    show(context, message: message, type: NotificationType.error, title: title);
  }

  static void warning(BuildContext context, String message, {String? title}) {
    show(
      context,
      message: message,
      type: NotificationType.warning,
      title: title,
    );
  }

  static void info(BuildContext context, String message, {String? title}) {
    show(context, message: message, type: NotificationType.info, title: title);
  }
}

class TopNotificationWidget extends StatefulWidget {
  final String message;
  final NotificationType type;
  final String? title;
  final IconData? customIcon;
  final VoidCallback onDismiss;
  final Function(VoidCallback)? onDismissAnimated;

  const TopNotificationWidget({
    super.key,
    required this.message,
    required this.type,
    this.title,
    this.customIcon,
    required this.onDismiss,
    this.onDismissAnimated,
  });

  @override
  State<TopNotificationWidget> createState() => _TopNotificationWidgetState();
}

class _TopNotificationWidgetState extends State<TopNotificationWidget>
    with TickerProviderStateMixin {
  late AnimationController _slideController;
  late AnimationController _fadeController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    // Softer, shorter animation duration for appearance
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    // Smooth slide animation from top
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, -1.0), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _slideController,
            curve: Curves.easeOutQuart, // Smooth curve like when disappearing
          ),
        );

    // Smooth fade animation
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _fadeController,
        curve: Curves.easeOutCubic, // Smooth curve like when disappearing
      ),
    );

    // Register dismiss callback
    widget.onDismissAnimated?.call(_dismiss);

    // Immediate start for smoother animation
    _slideController.forward();
    _fadeController.forward();
  }

  @override
  void dispose() {
    _slideController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  void _dismiss() async {
    if (!mounted) return;

    // Nur nach oben sliden, ohne auszublenden
    await _slideController.animateTo(
      0.0,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInQuart,
    );

    // Clean up via static method
    TopNotification._onDismissComplete();
  }

  Color _getBackgroundColor() {
    switch (widget.type) {
      case NotificationType.success:
        return Colors.green.shade600;
      case NotificationType.error:
        return Colors.red.shade600;
      case NotificationType.warning:
        return Colors.orange.shade600;
      case NotificationType.info:
        return Colors.blue.shade600;
    }
  }

  IconData _getIcon() {
    if (widget.customIcon != null) return widget.customIcon!;

    switch (widget.type) {
      case NotificationType.success:
        return CupertinoIcons.checkmark_circle_fill;
      case NotificationType.error:
        return CupertinoIcons.exclamationmark_circle_fill;
      case NotificationType.warning:
        return CupertinoIcons.exclamationmark_triangle_fill;
      case NotificationType.info:
        return CupertinoIcons.info_circle_fill;
    }
  }

  String _getDefaultTitle() {
    switch (widget.type) {
      case NotificationType.success:
        return AppLocalizations.of(context)?.success ?? 'Success';
      case NotificationType.error:
        return AppLocalizations.of(context)?.errorTitle ?? 'Error';
      case NotificationType.warning:
        return AppLocalizations.of(context)?.warningTitle ?? 'Warning';
      case NotificationType.info:
        return 'Information';
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusBarHeight = MediaQuery.of(context).padding.top;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: _dismiss,
              onVerticalDragEnd: (details) {
                if (details.velocity.pixelsPerSecond.dy < -200) {
                  _dismiss();
                }
              },
              child: Container(
                padding: EdgeInsets.only(
                  top: statusBarHeight + 25,
                  left: 16,
                  right: 14,
                  bottom: 14,
                ),
                decoration: BoxDecoration(
                  color: _getBackgroundColor(),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Icon
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(_getIcon(), color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 10),

                    // Content
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.title ?? _getDefaultTitle(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.message,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.95),
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            softWrap: true,
                          ),
                        ],
                      ),
                    ),

                    // Close button
                    GestureDetector(
                      onTap: _dismiss,
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          CupertinoIcons.xmark,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
