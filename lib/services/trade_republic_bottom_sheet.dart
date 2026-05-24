import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'trade_republic_theme.dart';
import 'cultioo_desktop_layout.dart';
import '../services/app_localizations.dart';

import 'drag_handle.dart';
import 'pointer_safe.dart';
// ═══ Desktop right column: multi-sheet stack + tab strip ═══════════════════

/// Shown when no sheet is open in the desktop panel.
class DesktopSheetPlaceholder extends StatelessWidget {
  const DesktopSheetPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ColoredBox(
      color: Colors.transparent,
      child: Center(
        child: Icon(
          CupertinoIcons.sidebar_right,
          size: 44,
          color: isDark ? Colors.white24 : Colors.black26,
        ),
      ),
    );
  }
}

class _DesktopSheetTabEntry {
  _DesktopSheetTabEntry({
    required this.id,
    required this.title,
    required this.child,
    required this.maxHeight,
    required this.isDismissible,
    required this.backgroundColor,
    required this.persistenceKey,
    required this.completer,
    required this.screenWidth,
  });

  final String id;
  final String title;
  final Widget child;
  final double? maxHeight;
  final bool isDismissible;
  final Color? backgroundColor;
  final String? persistenceKey;
  final Completer<Object?> completer;
  final double screenWidth;
}

/// Holds open desktop panel sheets; [IndexedStack] keeps all mounted for fast switching.
class CultiooDesktopSheetStackController extends ChangeNotifier {
  CultiooDesktopSheetStackController._();
  static final CultiooDesktopSheetStackController instance =
      CultiooDesktopSheetStackController._();

  bool _panelAttached = false;
  bool get panelAttached => _panelAttached;

  final List<_DesktopSheetTabEntry> _entries = [];
  int _selectedIndex = 0;

  List<_DesktopSheetTabEntry> get entries => List.unmodifiable(_entries);

  int get selectedIndex =>
      _entries.isEmpty ? 0 : _selectedIndex.clamp(0, _entries.length - 1);

  void setPanelAttached(bool attached) {
    _panelAttached = attached;
    if (!attached) {
      _disposeAllEntries();
    }
    notifyListeners();
  }

  void _disposeAllEntries() {
    for (final e in _entries) {
      if (!e.completer.isCompleted) {
        e.completer.complete(null);
      }
    }
    _entries.clear();
    _selectedIndex = 0;
  }

  Future<T?> pushSheet<T>({
    required BuildContext context,
    required Widget child,
    required String title,
    double? maxHeight,
    bool isDismissible = true,
    Color? backgroundColor,
    String? persistenceKey,
  }) {
    final c = Completer<Object?>();
    final entry = _DesktopSheetTabEntry(
      id: 'ds_${DateTime.now().microsecondsSinceEpoch}_${_entries.length}',
      title: title,
      child: child,
      maxHeight: maxHeight,
      isDismissible: isDismissible,
      backgroundColor: backgroundColor,
      persistenceKey: persistenceKey,
      completer: c,
      screenWidth: MediaQuery.sizeOf(context).width,
    );
    _entries.add(entry);
    _selectedIndex = _entries.length - 1;
    notifyListeners();
    return c.future.then((v) => v as T?);
  }

  void select(int index) {
    if (index >= 0 && index < _entries.length) {
      _selectedIndex = index;
      notifyListeners();
    }
  }

  void closeEntry(_DesktopSheetTabEntry entry, [Object? result]) {
    if (!entry.completer.isCompleted) {
      entry.completer.complete(result);
    }
    _entries.remove(entry);
    if (_entries.isEmpty) {
      _selectedIndex = 0;
    } else {
      _selectedIndex = _selectedIndex.clamp(0, _entries.length - 1);
    }
    notifyListeners();
  }
}

class CultiooDesktopSheetPanelHost extends StatefulWidget {
  final bool isDark;

  const CultiooDesktopSheetPanelHost({super.key, required this.isDark});

  @override
  State<CultiooDesktopSheetPanelHost> createState() =>
      _CultiooDesktopSheetPanelHostState();
}

class _CultiooDesktopSheetPanelHostState extends State<CultiooDesktopSheetPanelHost> {
  final CultiooDesktopSheetStackController _c =
      CultiooDesktopSheetStackController.instance;

  @override
  void initState() {
    super.initState();
    _c.setPanelAttached(true);
  }

  @override
  void dispose() {
    _c.setPanelAttached(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_c.entries.length > 1)
              _DesktopSheetTabStrip(isDark: widget.isDark),
            Expanded(
              child: _c.entries.isEmpty
                  ? const DesktopSheetPlaceholder()
                  : IndexedStack(
                      index: _c.selectedIndex,
                      sizing: StackFit.expand,
                      children: [
                        for (final e in _c.entries)
                          _DesktopStackedSheetPage(
                            key: ValueKey<String>(e.id),
                            entry: e,
                            isDark: widget.isDark,
                          ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _DesktopSheetTabStrip extends StatelessWidget {
  final bool isDark;

  const _DesktopSheetTabStrip({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final c = CultiooDesktopSheetStackController.instance;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CultiooDesktopLayout.topBarHorizontal,
        CultiooDesktopLayout.topBarVertical,
        CultiooDesktopLayout.topBarHorizontal,
        CultiooDesktopLayout.topBarVertical,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < c.entries.length; i++)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _DesktopSheetTabChip(
                  isDark: isDark,
                  label: c.entries[i].title,
                  isSelected: i == c.selectedIndex,
                  onTap: () => c.select(i),
                  onClose: c.entries[i].isDismissible
                      ? () => c.closeEntry(c.entries[i], null)
                      : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Desktop tab chip styling aligned with main-window desktop tabs (main.dart).
class _DesktopSheetTabChip extends StatelessWidget {
  final bool isDark;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onClose;

  const _DesktopSheetTabChip({
    required this.isDark,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final unselectedColor = isDark ? Colors.white70 : Colors.black54;
    final borderRadius = BorderRadius.circular(10);
    final ink = isDark ? Colors.white : Colors.black;
    final selBg = TradeRepublicTheme.selectionContainerBackground(context);
    final selFg = TradeRepublicTheme.selectionContainerForeground(context);

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        hoverColor: ink.withValues(alpha: 0.07),
        splashColor: ink.withValues(alpha: 0.12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? selBg : ink.withValues(alpha: 0.04),
            borderRadius: borderRadius,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                CupertinoIcons.rectangle_stack_fill,
                size: 15,
                color: isSelected ? selFg : unselectedColor,
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: onClose != null ? 152 : 176,
                ),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? selFg : unselectedColor,
                  ),
                ),
              ),
              if (onClose != null) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onClose,
                  child: Icon(
                    CupertinoIcons.xmark,
                    size: 12,
                    color: isSelected ? selFg : unselectedColor,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopStackedSheetPage extends StatelessWidget {
  final _DesktopSheetTabEntry entry;
  final bool isDark;

  const _DesktopStackedSheetPage({
    super.key,
    required this.entry,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final brightness =
        isDark ? Brightness.dark : Brightness.light;
    final isLight = brightness == Brightness.light;
    final bgColor = entry.backgroundColor ??
        (isDark ? Colors.transparent : const Color(0xFFFFFFFF));
    const borderRadius = 16.0;
    const shadow = BoxShadow(color: Colors.transparent, blurRadius: 0);
    const contentPadding = EdgeInsets.fromLTRB(14, 4, 14, 14);
    final screenHeight = MediaQuery.sizeOf(context).height;
    final desktopMaxHeight = math.min(
      entry.maxHeight ?? double.infinity,
      screenHeight,
    );

    final sheetBody = TradeRepublicBottomSheetScope(
      forceTransparentDarkSurfaces: isDark,
      child: _DesktopSheetContent(
        embeddedInPanel: true,
        maxHeight: desktopMaxHeight,
        isDismissible: entry.isDismissible,
        persistenceKey: entry.persistenceKey,
        isMacOS: Platform.isMacOS,
        isWindows: Platform.isWindows,
        bgColor: bgColor,
        borderRadius: borderRadius,
        shadow: shadow,
        contentPadding: contentPadding,
        isLight: isLight,
        screenWidth: entry.screenWidth,
        child: entry.child,
      ),
    );

    // One route per tab so `Navigator.pop` inside modal content still targets this sheet.
    return Navigator(
      pages: [
        MaterialPage<void>(
          key: ValueKey<String>('${entry.id}_page'),
          name: entry.id,
          child: sheetBody,
        ),
      ],
      // ignore: deprecated_member_use — single-page mini-nav; migrate to onDidRemovePage when stable in our SDK pin.
      onPopPage: (route, result) {
        final didPop = route.didPop(result);
        if (didPop) {
          CultiooDesktopSheetStackController.instance.closeEntry(entry, result);
        }
        return didPop;
      },
    );
  }
}

class TradeRepublicBottomSheetScope extends InheritedWidget {
  final bool forceTransparentDarkSurfaces;

  const TradeRepublicBottomSheetScope({
    super.key,
    required this.forceTransparentDarkSurfaces,
    required super.child,
  });

  static TradeRepublicBottomSheetScope? of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<TradeRepublicBottomSheetScope>();
  }

  @override
  bool updateShouldNotify(TradeRepublicBottomSheetScope oldWidget) {
    return forceTransparentDarkSurfaces !=
        oldWidget.forceTransparentDarkSurfaces;
  }
}

/// Trade Republic styled bottom sheet with rounded corners on top AND bottom
/// Features glass morphism effect, spring bounce animation and drag handle
/// Adapted for iOS (native feel) and macOS (centered dialog style)
class TradeRepublicBottomSheet {
  // Cache platform checks
  static final bool _isIOS = Platform.isIOS;
  static final bool _isMacOS = Platform.isMacOS;
  static final bool _isWindows = Platform.isWindows;
  static final bool _isDesktop =
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  /// Shows a Trade Republic styled bottom sheet
  ///
  /// - iOS: Full-width, native-style rounded corners, smooth spring
  /// - Desktop: third-column panel (nested navigator), not a full-window sheet
  /// - macOS (fallback): centered dialog when panel navigator is unavailable
  /// - Android: Full-width floating bottom sheet
  static Future<T?> show<T>({
    required BuildContext context,
    required Widget child,
    double? maxHeight,
    bool isDismissible = true,
    bool enableDrag = true,
    bool useRootNavigator = false,
    Color? backgroundColor,
    double bottomPadding = 10.0,
    double horizontalPadding = 10.0,
    bool showDragHandle = false,
    String? persistenceKey,
    bool avoidKeyboard = true,
    /// Tab label in the desktop panel when several sheets are open.
    String? sheetTitle,
    /// Optional content padding wrapping the child.
    EdgeInsetsGeometry? contentPadding,
  }) {
    Widget effectiveChild = child;
    if (contentPadding != null) {
      effectiveChild = Padding(padding: contentPadding, child: effectiveChild);
    }
    if (_isIOS) HapticFeedback.mediumImpact();
    if (_isDesktop &&
        CultiooDesktopSheetStackController.instance.panelAttached) {
      final n = CultiooDesktopSheetStackController.instance.entries.length + 1;
      final label = (sheetTitle != null && sheetTitle.trim().isNotEmpty)
          ? sheetTitle.trim()
          : 'Sheet $n';
      return CultiooDesktopSheetStackController.instance.pushSheet<T>(
        context: context,
        child: effectiveChild,
        title: label,
        maxHeight: maxHeight,
        isDismissible: isDismissible,
        backgroundColor: backgroundColor,
        persistenceKey: persistenceKey,
      );
    }
    return Navigator.of(context, rootNavigator: useRootNavigator).push<T>(
      _BouncingBottomSheetRoute<T>(
        child: effectiveChild,
        maxHeight: maxHeight,
        isDismissible: isDismissible,
        enableDrag: _isDesktop ? false : enableDrag,
        backgroundColor: backgroundColor,
        bottomPadding: bottomPadding,
        horizontalPadding: horizontalPadding,
        showDragHandle: showDragHandle,
        persistenceKey: persistenceKey,
        avoidKeyboard: avoidKeyboard,
        isIOS: _isIOS,
        isMacOS: _isMacOS,
        isWindows: _isWindows,
        isDesktop: _isDesktop,
      ),
    );
  }

  /// Hides any open Trade Republic bottom sheet
  static void hide(BuildContext context) {
    Navigator.of(context).pop();
  }

  /// Shows a Trade Republic bottom sheet with a title and content
  static Future<T?> showWithTitle<T>({
    required BuildContext context,
    required String title,
    required Widget content,
    List<Widget>? actions,
    double? maxHeight,
    bool isDismissible = true,
    bool enableDrag = true,
  }) {
    return show<T>(
      context: context,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      maxHeight: maxHeight,
      sheetTitle: title,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title.toUpperCase(),
            style: TradeRepublicTheme.titleLarge(context).copyWith(
              letterSpacing: 0.35,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: _isDesktop ? 14 : 20),
          Flexible(child: SingleChildScrollView(child: content)),
          if (actions != null && actions.isNotEmpty) ...[
            SizedBox(height: _isDesktop ? 14 : 20),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < actions.length; i++) ...[
                  actions[i],
                  if (i < actions.length - 1) SizedBox(height: _isDesktop ? 8 : 12),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Right-hand desktop column: stacked sheets + tab strip when several are open.
  static Widget buildDesktopPanelHost({
    required double width,
    required bool isDark,
  }) {
    final bg = isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
    return SizedBox(
      width: width,
      child: Builder(
        builder: (context) => DecoratedBox(
          decoration: BoxDecoration(
            color: bg,
            border: CultiooDesktopLayout.desktopSheetPanelLeftBorder(context),
          ),
          child: CultiooDesktopSheetPanelHost(isDark: isDark),
        ),
      ),
    );
  }
}

// ─── Custom Route with spring bounce ───────────────────────────────────────

class _BouncingBottomSheetRoute<T> extends PopupRoute<T> {
  final Widget child;
  final double? maxHeight;
  final bool isDismissible;
  final bool enableDrag;
  final Color? backgroundColor;
  final double bottomPadding;
  final double horizontalPadding;
  final bool showDragHandle;
  final String? persistenceKey;
  final bool avoidKeyboard;
  final bool isIOS;
  final bool isMacOS;
  final bool isWindows;
  final bool isDesktop;

  _BouncingBottomSheetRoute({
    required this.child,
    this.maxHeight,
    this.isDismissible = true,
    this.enableDrag = true,
    this.backgroundColor,
    this.bottomPadding = 20.0,
    this.horizontalPadding = 20.0,
    this.showDragHandle = true,
    this.persistenceKey,
    this.avoidKeyboard = true,
    this.isIOS = false,
    this.isMacOS = false,
    this.isWindows = false,
    this.isDesktop = false,
  });

  @override
  Duration get transitionDuration => Duration(
    milliseconds: isDesktop
        ? 300
        : isIOS
        ? 500
        : 750,
  );

  @override
  Duration get reverseTransitionDuration => Duration(
    milliseconds: isDesktop
        ? 200
        : isIOS
        ? 350
        : 450,
  );

  @override
  bool get barrierDismissible => isDismissible;

  @override
  String? get barrierLabel => 'Dismiss';

  @override
  Color get barrierColor => Colors.black.withValues(alpha: isDesktop ? 0.38 : 0.54);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final isForward =
        animation.status == AnimationStatus.forward ||
        animation.status == AnimationStatus.completed;

    if (isDesktop) {
      // Desktop: docked panel — slide in from the right (not centered dialog).
      final curved = CurvedAnimation(
        parent: animation,
        curve: isForward ? Curves.easeOutCubic : Curves.easeInCubic,
        reverseCurve: Curves.easeInCubic,
      );
      final slide = Tween<Offset>(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(curved);

      return FadeTransition(
        opacity: curved,
        child: SlideTransition(position: slide, child: child),
      );
    }

    if (isIOS) {
      // iOS: Smooth native-like slide up with gentle deceleration
      final curvedAnimation = CurvedAnimation(
        parent: animation,
        curve: isForward ? Curves.easeOutCubic : Curves.easeInCubic,
        reverseCurve: Curves.easeInCubic,
      );

      final slideAnimation = Tween<Offset>(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).animate(curvedAnimation);

      final fadeAnimation = CurvedAnimation(
        parent: animation,
        curve: const Interval(0, 0.5, curve: Curves.easeOut),
      );

      return FadeTransition(
        opacity: fadeAnimation,
        child: SlideTransition(position: slideAnimation, child: child),
      );
    }

    // Android: Spring bounce (existing behavior)
    final curvedAnimation = CurvedAnimation(
      parent: animation,
      curve: isForward ? const _SpringCurve() : Curves.easeIn,
      reverseCurve: Curves.easeIn,
    );

    final slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(curvedAnimation);

    final scaleAnimation = Tween<double>(
      begin: 0.85,
      end: 1.0,
    ).animate(curvedAnimation);

    final fadeAnimation = CurvedAnimation(
      parent: animation,
      curve: const Interval(0, 0.4, curve: Curves.easeOut),
    );

    return FadeTransition(
      opacity: fadeAnimation,
      child: SlideTransition(
        position: slideAnimation,
        child: ScaleTransition(
          scale: scaleAnimation,
          alignment: Alignment.bottomCenter,
          child: child,
        ),
      ),
    );
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final brightness = Theme.of(context).brightness;
    final isLight = brightness == Brightness.light;
    final bottomSafePadding = MediaQuery.of(context).padding.bottom;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final shortestSide = MediaQuery.of(context).size.shortestSide;
    final isIPad = isIOS && shortestSide >= 600;

    // Platform-specific values
    final borderRadius = isDesktop ? 20.0 : (isIPad ? 34.0 : (isIOS ? 44.0 : 30.0));
    final sheetMaxWidth = isDesktop ? 440.0 : (isIPad ? 720.0 : double.infinity);
    final effectiveHorizontalPadding = isDesktop
        ? horizontalPadding
      : isIPad
        ? math.max((screenWidth - sheetMaxWidth) / 2, horizontalPadding)
        : horizontalPadding;
    final effectiveBottomPadding = isDesktop ? keyboardHeight : 10.0 + keyboardHeight;
    final topPadding = isDesktop
      ? 0.0
      : isIPad
        ? MediaQuery.of(context).padding.top + 20
        : MediaQuery.of(context).padding.top + 20;
    final contentPadding = isIPad
      ? const EdgeInsets.fromLTRB(20, 6, 20, 20)
      : isIOS
        ? const EdgeInsets.fromLTRB(20, 6, 20, 20)
        : const EdgeInsets.fromLTRB(20, 6, 20, 20);
    // Background color — always use solid color, never transparent
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = backgroundColor ??
        (isDark ? const Color.fromARGB(255, 8, 8, 8) : const Color(0xFFFFFFFF));

    // Shadow — desktop uses no shadow (flat, border-only look)
    final shadow = isDesktop
        ? BoxShadow(color: Colors.transparent, blurRadius: 0)
        : BoxShadow(
            color: Colors.black.withValues(alpha: isIOS ? 0.15 : 0.25),
            blurRadius: isIOS ? 20 : 30,
            offset: const Offset(0, -5),
          );

    if (isDesktop) {
      // On desktop, always cap maxHeight at 85% of screen height regardless of what callers pass
      final desktopMaxHeight = math.min(
        maxHeight ?? double.infinity,
        screenHeight * 0.85,
      );
      return TradeRepublicBottomSheetScope(
        forceTransparentDarkSurfaces: isDark,
        child: _DesktopSheetContent(
          maxHeight: desktopMaxHeight,
          isDismissible: isDismissible,
          persistenceKey: persistenceKey,
          isMacOS: isMacOS,
          isWindows: isWindows,
          bgColor: bgColor,
          borderRadius: borderRadius,
          shadow: shadow,
          contentPadding: contentPadding,
          isLight: isLight,
          screenWidth: screenWidth,
          child: child,
        ),
      );
    }

    return GestureDetector(
      onTap: isDismissible ? () => Navigator.of(context).pop() : null,
      behavior: HitTestBehavior.opaque,
      child: Material(
        type: MaterialType.transparency,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {},
            child: _DraggableSheet(
              enableDrag: enableDrag,
              onDismiss: () => Navigator.of(context).pop(),
              child: Padding(
                padding: EdgeInsets.only(
                  top: topPadding,
                  left: effectiveHorizontalPadding,
                  right: effectiveHorizontalPadding,
                  bottom: effectiveBottomPadding,
                ),
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: sheetMaxWidth,
                    maxHeight: maxHeight ?? screenHeight * 0.85,
                  ),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.all(
                      Radius.circular(borderRadius),
                    ),
                    boxShadow: [shadow],
                  ),
                  child: TradeRepublicBottomSheetScope(
                    forceTransparentDarkSurfaces: isDark,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Drag handle sits OUTSIDE content padding at the very top
                        if (showDragHandle && !isDesktop) const DragHandle(),
                        Flexible(
                          child: Padding(
                            padding: contentPadding,
                            child: child,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Draggable wrapper for swipe-to-dismiss ────────────────────────────────

class _DraggableSheet extends StatefulWidget {
  final Widget child;
  final bool enableDrag;
  final VoidCallback onDismiss;

  const _DraggableSheet({
    required this.child,
    required this.enableDrag,
    required this.onDismiss,
  });

  @override
  State<_DraggableSheet> createState() => _DraggableSheetState();
}

class _DraggableSheetState extends State<_DraggableSheet>
    with SingleTickerProviderStateMixin {
  double _dragOffset = 0;
  late AnimationController _snapBack;

  @override
  void initState() {
    super.initState();
    _snapBack =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 300),
        )..addListener(() {
          setState(() {
            _dragOffset = _dragOffset * (1 - _snapBack.value);
          });
        });
  }

  @override
  void dispose() {
    _snapBack.dispose();
    super.dispose();
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (!widget.enableDrag) return;
    setState(() {
      _dragOffset = (_dragOffset + details.delta.dy).clamp(0.0, 500.0);
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (!widget.enableDrag) return;
    // Dismiss if dragged more than 80px or velocity is high enough (iOS feels snappier)
    if (_dragOffset > 80 || details.velocity.pixelsPerSecond.dy > 500) {
      if (Platform.isIOS) HapticFeedback.lightImpact();
      widget.onDismiss();
    } else {
      if (Platform.isIOS) HapticFeedback.selectionClick();
      // Snap back with animation
      _snapBack.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragUpdate: widget.enableDrag ? _onVerticalDragUpdate : null,
      onVerticalDragEnd: widget.enableDrag ? _onVerticalDragEnd : null,
      child: Transform.translate(
        offset: Offset(0, _dragOffset),
        child: widget.child,
      ),
    );
  }
}

// ─── Desktop Sheet Content (supports maximize) ────────────────────────────

class _DesktopSheetContent extends StatefulWidget {
  final Widget child;
  /// When true, sheet fills the fixed-width right column (not a floating window).
  final bool embeddedInPanel;
  final double? maxHeight;
  final bool isDismissible;
  final String? persistenceKey;
  final bool isMacOS;
  final bool isWindows;
  final Color bgColor;
  final double borderRadius;
  final BoxShadow shadow;
  final EdgeInsets contentPadding;
  final bool isLight;
  final double screenWidth;

  const _DesktopSheetContent({
    required this.child,
    this.embeddedInPanel = false,
    required this.isDismissible,
    required this.isMacOS,
    required this.isWindows,
    required this.bgColor,
    required this.borderRadius,
    required this.shadow,
    required this.contentPadding,
    required this.isLight,
    required this.screenWidth,
    this.maxHeight,
    this.persistenceKey,
  });

  @override
  State<_DesktopSheetContent> createState() => _DesktopSheetContentState();
}

class _DesktopSheetContentState extends State<_DesktopSheetContent> {
  // Single global preference: all bottom sheets share the same maximized state
  static bool _globalMaximized = false;
  static bool _prefsLoaded = false;

  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    _isMaximized = _globalMaximized;
    if (!_prefsLoaded) {
      _loadPref();
    }
  }

  Future<void> _loadPref() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool('tr_sheet_maximized') ?? false;
    _globalMaximized = saved;
    _prefsLoaded = true;
    if (mounted && saved != _isMaximized) {
      setState(() => _isMaximized = saved);
    }
  }

  /// Right-docked panel: default narrow; maximized uses more of the main area.
  double get _normalMaxWidth =>
      math.min(420.0, math.max(widget.screenWidth * 0.32, 300.0));
  double get _maximizedMaxWidth =>
      math.min(640.0, math.max(widget.screenWidth * 0.48, 360.0));
  double get _currentMaxWidth => _isMaximized ? _maximizedMaxWidth : _normalMaxWidth;

  void _toggleMaximize() {
    setState(() {
      _isMaximized = !_isMaximized;
      _globalMaximized = _isMaximized;
    });
    SharedPreferences.getInstance().then(
      (prefs) => prefs.setBool('tr_sheet_maximized', _globalMaximized),
    );
  }

  Widget _embeddedChrome(BuildContext context) {
    // Inner panel navigator has a single page-based route (`isFirst` →
    // [RoutePopDisposition.bubble]); [Navigator.maybePop] then returns false
    // without popping. [Navigator.pop] still runs [onPopPage] and closes the sheet.
    void closeEmbedded() {
      if (!widget.isDismissible) return;
      Navigator.of(context).pop();
    }

    if (widget.isMacOS) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(6, 8, 8, 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: _MacOSCloseButton(
            onTap: closeEmbedded,
          ),
        ),
      );
    }
    if (widget.isWindows) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(6, 8, 8, 4),
        child: Align(
          alignment: Alignment.centerRight,
          child: _WindowsCloseButton(
            onTap: closeEmbedded,
            isLight: widget.isLight,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 8, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: _DesktopGenericCloseButton(
          onTap: closeEmbedded,
          isLight: widget.isLight,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embeddedInPanel) {
      return Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape &&
              widget.isDismissible) {
            Navigator.of(context).pop();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Material(
          color: widget.bgColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _embeddedChrome(context),
              Expanded(
                child: Padding(
                  padding: widget.contentPadding,
                  child: ScrollConfiguration(
                    behavior: const _DesktopScrollBehavior(),
                    child: widget.child,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape &&
            widget.isDismissible) {
          Navigator.of(context).pop();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.isDismissible ? () => Navigator.of(context).pop() : null,
        behavior: HitTestBehavior.opaque,
        child: Material(
          type: MaterialType.transparency,
          child: Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: EdgeInsets.only(
                right: 12,
                top: 8,
                bottom: math.max(
                  8,
                  MediaQuery.of(context).padding.bottom,
                ),
              ),
              child: GestureDetector(
                onTap: () {},
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOutCubic,
                  width: _currentMaxWidth,
                  height: _isMaximized
                      ? MediaQuery.of(context).size.height - 24
                      : null,
                  constraints: BoxConstraints(
                    maxHeight: _isMaximized
                        ? MediaQuery.of(context).size.height - 24
                        : (widget.maxHeight ??
                            MediaQuery.of(context).size.height * 0.78),
                  ),
                  decoration: BoxDecoration(
                    color: widget.bgColor,
                    borderRadius: BorderRadius.horizontal(
                      left: Radius.circular(widget.borderRadius),
                    ),
                    border: CultiooDesktopLayout.isDesktopPlatform
                        ? null
                        : Border.all(
                            color: CultiooDesktopLayout.hairlineColor(context),
                            width: CultiooDesktopLayout.hairlineWidth,
                          ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 24,
                        offset: const Offset(-6, 0),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: widget.contentPadding,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.isMacOS)
                          Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 8),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _MacOSCloseButton(
                                    onTap: () => Navigator.of(context).pop(),
                                  ),
                                  const SizedBox(width: 8),
                                  _MacOSMaximizeButton(
                                    onTap: _toggleMaximize,
                                    isMaximized: _isMaximized,
                                  ),
                                ],
                              ),
                            ),
                          )
                        else if (widget.isWindows)
                          Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 8),
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _WindowsMaximizeButton(
                                    onTap: _toggleMaximize,
                                    isLight: widget.isLight,
                                    isMaximized: _isMaximized,
                                  ),
                                  const SizedBox(width: 2),
                                  _WindowsCloseButton(
                                    onTap: () => Navigator.of(context).pop(),
                                    isLight: widget.isLight,
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 8),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _DesktopGenericCloseButton(
                                    onTap: () => Navigator.of(context).pop(),
                                    isLight: widget.isLight,
                                  ),
                                  const SizedBox(width: 8),
                                  _DesktopGenericMaximizeButton(
                                    onTap: _toggleMaximize,
                                    isLight: widget.isLight,
                                    isMaximized: _isMaximized,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        Flexible(
                          child: RepaintBoundary(
                            child: ScrollConfiguration(
                              behavior: const _DesktopScrollBehavior(),
                              child: widget.child,
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
        ),
      ),
    );
  }
}

// ─── macOS Close Button (traffic light style) ─────────────────────────────

class _MacOSCloseButton extends StatefulWidget {
  final VoidCallback onTap;
  const _MacOSCloseButton({required this.onTap});

  @override
  State<_MacOSCloseButton> createState() => _MacOSCloseButtonState();
}

class _MacOSCloseButtonState extends State<_MacOSCloseButton>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.85,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
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
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => _controller.forward(),
        onTapUp: (_) {
          _controller.reverse();
          widget.onTap();
        },
        onTapCancel: () => _controller.reverse(),
        child: AnimatedBuilder(
          animation: _scaleAnimation,
          builder: (context, child) {
            return Transform.scale(scale: _scaleAnimation.value, child: child);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isHovered
                  ? const Color(0xFFFF5F57) // macOS red (match cultioo_app)
                  : const Color(0xFFFF5F57).withValues(alpha: 0.55),
              boxShadow: _isHovered
                  ? [
                      BoxShadow(
                        color: const Color(0xFFFF5F57).withValues(alpha: 0.4),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: _isHovered
                ? const Center(
                    child: Icon(
                      CupertinoIcons.xmark,
                      size: 8,
                      color: Color(0xFF4A0002),
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

// ─── macOS Maximize Button (green traffic light) ──────────────────────────

class _MacOSMaximizeButton extends StatefulWidget {
  final VoidCallback onTap;
  final bool isMaximized;
  const _MacOSMaximizeButton({required this.onTap, required this.isMaximized});

  @override
  State<_MacOSMaximizeButton> createState() => _MacOSMaximizeButtonState();
}

class _MacOSMaximizeButtonState extends State<_MacOSMaximizeButton>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.85,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
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
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => _controller.forward(),
        onTapUp: (_) {
          _controller.reverse();
          widget.onTap();
        },
        onTapCancel: () => _controller.reverse(),
        child: AnimatedBuilder(
          animation: _scaleAnimation,
          builder: (context, child) {
            return Transform.scale(scale: _scaleAnimation.value, child: child);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isHovered
                  ? const Color(0xFF28C840) // macOS green (match cultioo_app)
                  : const Color(0xFF28C840).withValues(alpha: 0.55),
              boxShadow: _isHovered
                  ? [
                      BoxShadow(
                        color: const Color(0xFF28C840).withValues(alpha: 0.4),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: _isHovered
                ? Center(
                    child: widget.isMaximized
                        ? const Icon(
                            CupertinoIcons.arrow_down_right_arrow_up_left,
                            size: 8,
                            color: Color(0xFF004A00),
                          )
                        : const Icon(
                            CupertinoIcons.arrow_up_left_arrow_down_right,
                            size: 8,
                            color: Color(0xFF004A00),
                          ),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

// ─── Linux / generic desktop window controls (right-docked sheet) ───────────

class _DesktopGenericCloseButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool isLight;

  const _DesktopGenericCloseButton({
    required this.onTap,
    required this.isLight,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: AppLocalizations.of(context)?.close ?? 'Close',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Icon(
              CupertinoIcons.xmark,
              size: 15,
              color: isLight ? Colors.black54 : Colors.white70,
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopGenericMaximizeButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool isLight;
  final bool isMaximized;

  const _DesktopGenericMaximizeButton({
    required this.onTap,
    required this.isLight,
    required this.isMaximized,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isMaximized ? 'Restore' : 'Expand',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Icon(
              isMaximized
                  ? CupertinoIcons.arrow_down_right_arrow_up_left
                  : CupertinoIcons.arrow_up_left_arrow_down_right,
              size: 15,
              color: isLight ? Colors.black54 : Colors.white70,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Windows Close Button ──────────────────────────────────────────────────

class _WindowsCloseButton extends StatefulWidget {
  final VoidCallback onTap;
  final bool isLight;
  const _WindowsCloseButton({required this.onTap, required this.isLight});

  @override
  State<_WindowsCloseButton> createState() => _WindowsCloseButtonState();
}

class _WindowsCloseButtonState extends State<_WindowsCloseButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
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
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 32,
          height: 24,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: _isHovered
                ? (widget.isLight
                    ? Colors.black.withValues(alpha: 0.14)
                    : Colors.white.withValues(alpha: 0.18))
                : Colors.transparent,
          ),
          child: Center(
            child: Icon(
              CupertinoIcons.xmark,
              size: 12,
              color: Theme.of(context).colorScheme.onSurface.withValues(
                alpha: _isHovered ? 0.87 : 0.54
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Windows Maximize Button ───────────────────────────────────────────────

class _WindowsMaximizeButton extends StatefulWidget {
  final VoidCallback onTap;
  final bool isLight;
  final bool isMaximized;
  const _WindowsMaximizeButton({
    required this.onTap,
    required this.isLight,
    required this.isMaximized,
  });

  @override
  State<_WindowsMaximizeButton> createState() => _WindowsMaximizeButtonState();
}

class _WindowsMaximizeButtonState extends State<_WindowsMaximizeButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
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
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 32,
          height: 24,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: _isHovered
                ? (widget.isLight
                    ? Colors.black.withValues(alpha: 0.14)
                    : Colors.white.withValues(alpha: 0.18))
                : Colors.transparent,
          ),
          child: Center(
            child: Icon(
              widget.isMaximized
                  ? CupertinoIcons.arrow_down_right_arrow_up_left
                  : CupertinoIcons.square,
              size: 14,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: _isHovered ? 0.87 : 0.54),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Spring curve with overshoot ───────────────────────────────────────────

// ─── Desktop scroll behavior ─────────────────────────────────────────────

/// Desktop scroll behavior for bottom sheet dialogs.
/// - Uses platform-default physics (BouncingScrollPhysics on macOS) so
///   trackpad momentum and overscroll work exactly as macOS users expect.
/// - Suppresses the native overlay scrollbar to avoid per-frame repaints
///   that cause scroll jank inside the sheet.
/// - Enables all pointer devices so mouse-drag and trackpad both scroll.
class _DesktopScrollBehavior extends ScrollBehavior {
  const _DesktopScrollBehavior();

  // No getScrollPhysics override → Flutter uses BouncingScrollPhysics on
  // macOS and ClampingScrollPhysics on Windows/Linux by default.

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
  };

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) =>
      child; // suppress overlay scrollbar — repaints on every frame → jank
}

/// A spring-like curve that overshoots then settles back.
/// Creates a satisfying bounce effect for bottom sheets.
class _SpringCurve extends Curve {
  const _SpringCurve();

  @override
  double transformInternal(double t) {
    // Damped spring: gentle overshoot then settle
    const damping = 5.5;
    const frequency = 1.5;
    final decay = math.exp(-damping * t);
    final oscillation = math.cos(frequency * math.pi * t);
    return 1.0 - decay * oscillation;
  }
}
