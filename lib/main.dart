import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'dart:ui';
import 'dart:convert';
import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:app_links/app_links.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:image/image.dart' as img;
import 'services/page_indicator.dart';
import 'utils/number_formatters.dart';
import 'dart:math';
import 'components/payment_methods_modal.dart';
import 'components/transaction_history_modal.dart';
import 'services/device_storage.dart';
import 'components/checkout_modal.dart';
import 'components/order_details_modal.dart';
import 'components/profile_edit_modal.dart';
import 'components/addresses_modal.dart';
import 'components/product_details_modal.dart';
import 'components/cart_modal.dart';
import 'components/change_password_modal.dart';
import 'components/seller_profile_modal.dart';
import 'components/groups_modal.dart';
import 'components/find_users_modal.dart';
import 'components/chat_overview_page.dart';
import 'services/cultioo_spinner.dart';
import 'services/app_localizations.dart';
import 'services/api_service.dart';
import 'services/settings_service.dart';
import 'services/trade_republic_widgets.dart';
import 'services/desktop_sheet_navigator.dart';
import 'services/cultioo_desktop_layout.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'package:image_picker/image_picker.dart';

// Safe wrapper for SharedPreferences that handles platform errors
class SafePrefs {
  static SharedPreferences? _cachedInstance;
  static bool _isInitializing = false;
  static final List<Completer<SharedPreferences?>> _waitingCompleters = [];

  static Future<SharedPreferences?> getInstance() async {
    // Return cached instance if available
    if (_cachedInstance != null) {
      return _cachedInstance;
    }

    // If already initializing, wait for that initialization to complete
    if (_isInitializing) {
      final completer = Completer<SharedPreferences?>();
      _waitingCompleters.add(completer);
      return completer.future;
    }

    _isInitializing = true;

    try {
      // Ensure Flutter bindings are initialized
      WidgetsFlutterBinding.ensureInitialized();

      // Add a small delay to ensure platform channels are ready
      await Future.delayed(const Duration(milliseconds: 100));

      _cachedInstance = await SharedPreferences.getInstance();

      // Complete all waiting futures
      for (var completer in _waitingCompleters) {
        completer.complete(_cachedInstance);
      }
      _waitingCompleters.clear();

      return _cachedInstance;
    } catch (e) {
      if (!e.toString().contains('channel-error')) {
        debugPrint('⚠️ SharedPreferences unavailable: $e');
      }

      // Complete all waiting futures with null
      for (var completer in _waitingCompleters) {
        completer.complete(null);
      }
      _waitingCompleters.clear();

      return null;
    } finally {
      _isInitializing = false;
    }
  }

  static Future<String?> getString(String key, [String? defaultValue]) async {
    try {
      final prefs = await getInstance();
      return prefs?.getString(key) ?? defaultValue;
    } catch (e) {
      return defaultValue;
    }
  }

  static Future<bool> getBool(String key, [bool defaultValue = false]) async {
    try {
      final prefs = await getInstance();
      return prefs?.getBool(key) ?? defaultValue;
    } catch (e) {
      return defaultValue;
    }
  }

  static Future<int> getInt(String key, [int defaultValue = 0]) async {
    try {
      final prefs = await getInstance();
      return prefs?.getInt(key) ?? defaultValue;
    } catch (e) {
      return defaultValue;
    }
  }

  static Future<List<String>> getStringList(String key) async {
    try {
      final prefs = await getInstance();
      return prefs?.getStringList(key) ?? [];
    } catch (e) {
      return [];
    }
  }

  static Future<bool> setString(String key, String value) async {
    try {
      final prefs = await getInstance();
      return await prefs?.setString(key, value) ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> setBool(String key, bool value) async {
    try {
      final prefs = await getInstance();
      return await prefs?.setBool(key, value) ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> setInt(String key, int value) async {
    try {
      final prefs = await getInstance();
      return await prefs?.setInt(key, value) ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> setStringList(String key, List<String> value) async {
    try {
      final prefs = await getInstance();
      return await prefs?.setStringList(key, value) ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> remove(String key) async {
    try {
      final prefs = await getInstance();
      return await prefs?.remove(key) ?? false;
    } catch (e) {
      return false;
    }
  }

  // Clear the cached instance (useful for testing)
  static void clearCache() {
    _cachedInstance = null;
  }
}

void _printSimulationLoginsToTerminal() {
  if (kReleaseMode) return;

  const rows = <Map<String, String>>[
    {
      'role': 'Buyer',
      'email': 'support@cultioo.com',
      'username': 'lucas.weber',
      'password': 'Demo2026!',
    },
    {
      'role': 'Seller',
      'email': 'support@cultioo.com',
      'username': 'elena.kraus',
      'password': 'Demo2026!',
    },
    {
      'role': 'Driver',
      'email': 'support@cultioo.com',
      'username': 'marco.stein',
      'password': 'Demo2026!',
    },
    {
      'role': 'Reviewer',
      'email': 'support@cultioo.com',
      'username': 'demo_reviewer',
      'password': 'ReviewApp2025!',
    },
  ];

  debugPrint('');
  debugPrint('================= CULTIOO SIMULATION LOGINS =================');
  for (final r in rows) {
    debugPrint(
      '[${r['role']}] email: ${r['email']} | username: ${r['username']} | passwort: ${r['password']}',
    );
  }
  debugPrint('==============================================================');
  debugPrint('');
}

void main() async {
  // Ensure Flutter bindings are initialized before anything else
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase BEFORE anything else
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('✅ Firebase initialized successfully');
  } catch (e) {
    debugPrint('❌ Firebase initialization failed: $e');
  }

  // Pre-initialize SharedPreferences to avoid channel errors
  try {
    await SafePrefs.getInstance();
  } catch (e) {
    // Silently handle initialization errors
    debugPrint('SharedPreferences initialization delayed: $e');
  }

  // Print simulation login credentials in terminal for screenshot workflow
  _printSimulationLoginsToTerminal();

  // Hide overflow indicators and debug features
  if (kReleaseMode) {
    FlutterError.onError = (FlutterErrorDetails details) {
      // In release mode, don't show the red error screen
      // Just log the error instead
      debugPrint(details.toString());
    };
  }

  runApp(const MyApp());
}

bool _isCultiooDesktopTarget() =>
    Platform.isMacOS || Platform.isWindows || Platform.isLinux;

/// Desktop Cultioo: compact body; nav titles slightly larger for scanability.
CupertinoThemeData _cupertinoThemeForCultiooDesktop(
  Brightness brightness,
  Color primaryColor,
) {
  final labelColor =
      brightness == Brightness.dark ? CupertinoColors.white : CupertinoColors.black;
  const body = TextStyle(
    fontSize: 13.5,
    height: 1.38,
    letterSpacing: -0.15,
  );
  return CupertinoThemeData(
    brightness: brightness,
    primaryColor: primaryColor,
    textTheme: CupertinoTextThemeData(
      primaryColor: primaryColor,
      textStyle: body.copyWith(color: labelColor),
      actionTextStyle: body.copyWith(
        color: primaryColor,
        fontWeight: FontWeight.w600,
      ),
      tabLabelTextStyle: body.copyWith(
        fontSize: 12.5,
        fontWeight: FontWeight.w500,
        color: labelColor.withValues(alpha: 0.88),
      ),
      navTitleTextStyle: body.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: labelColor,
      ),
      navLargeTitleTextStyle: body.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.4,
        color: labelColor,
      ),
      pickerTextStyle: body.copyWith(color: labelColor),
      dateTimePickerTextStyle: body.copyWith(color: labelColor),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();

  // Static method to access current date format from other widgets
  static String? getCurrentDateFormat() {
    final fmt = _MyHomePageState._instance?._dateFormat ?? 'dd.MM.yyyy';
    if (fmt == 'system') {
      return _MyHomePageState._instance?._resolveDateFormat() ?? 'dd.MM.yyyy';
    }
    return fmt;
  }

  // Static method to format date from other widgets
  static String formatDateGlobally(DateTime date, [String? format]) {
    final dateFormat = format ?? getCurrentDateFormat()!;
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();

    switch (dateFormat) {
      case 'MM/dd/yyyy':
        return '$month/$day/$year';
      case 'yyyy-MM-dd':
        return '$year-$month-$day';
      case 'dd-MM-yyyy':
        return '$day-$month-$year';
      case 'dd/MM/yyyy':
        return '$day/$month/$year';
      case 'dd.MM.yyyy':
      default:
        return '$day.$month.$year';
    }
  }

  /// Update the app locale from any page (e.g. settings_page.dart)
  static void setLocale(String languageCode) {
    _MyAppState._instance?._updateLocale(languageCode);
  }

  /// Reload all app settings (theme, text scale, locale) from SharedPreferences
  static void reloadSettings() {
    _MyAppState._instance?._loadAppSettings();
  }
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  ThemeMode _themeMode = ThemeMode.system;
  double _textScaleFactor =
      SettingsService.getTextScaleFactor('system');
  Locale? _locale; // null = system default
  bool _followSystemLocale = true;
  bool _followSystemTextScale = true;

  static _MyAppState? _instance;

  @override
  void initState() {
    super.initState();
    _instance = this;
    WidgetsBinding.instance.addObserver(this);
    _loadAppSettings();
    // Rebuild after first frame: MediaQuery/Engine then often report
    // the correct system brightness more reliably than on the very first build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_themeMode == ThemeMode.system) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _instance = null;
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    // Rebuild when system brightness changes
    if (_themeMode == ThemeMode.system) {
      setState(() {});
    }
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    super.didChangeLocales(locales);
    if (_followSystemLocale) {
      setState(() {});
    }
    // Refresh in-app strings that mirror device locale (language = system).
    final home = _MyHomePageState._instance;
    if (home != null && home.mounted) {
      unawaited(home._loadAppearanceSettings());
    }
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (!_followSystemTextScale) return;
    final next = SettingsService.getTextScaleFactor('system');
    if (next != _textScaleFactor) {
      setState(() => _textScaleFactor = next);
    }
  }

  static void updateTheme() {
    _instance?._loadAppSettings();
  }

  static void updateTextScale() {
    _instance?._loadAppSettings();
  }

  static void updateLocale(String languageCode) {
    _instance?._updateLocale(languageCode);
  }

  String _normalizeLanguageCode(String value) {
    final normalized = value.trim().replaceAll('-', '_').toLowerCase();
    if (normalized.isEmpty || normalized == 'system') return 'system';
    return normalized.split('_').first;
  }

  void _updateLocale(String languageCode) {
    final normalizedLanguage = _normalizeLanguageCode(languageCode);
    setState(() {
      _followSystemLocale = normalizedLanguage == 'system';
      if (normalizedLanguage == 'system') {
        _locale = null; // Use system default
      } else {
        _locale = Locale(normalizedLanguage);
      }
    });
  }

  Future<void> _loadAppSettings() async {
    try {
      final settings = await SettingsService.loadLocalSettings();
      final themeMode = settings['theme'] ?? 'system';
      final textSize = (settings['textSize'] ?? 'system').toString();
      final language = _normalizeLanguageCode(
        (settings['language'] ?? 'system').toString(),
      );
      setState(() {
        _themeMode = _getThemeModeFromString(themeMode);
        _followSystemTextScale = textSize == 'system';
        _textScaleFactor = SettingsService.getTextScaleFactor(
          _followSystemTextScale ? 'system' : textSize,
        );
        _followSystemLocale = language == 'system';
        if (language == 'system') {
          _locale = null;
        } else {
          _locale = Locale(language);
        }
      });
    } catch (e) {
      //debugPrint(' Error loading app settings: $e');
    }
  }

  ThemeMode _getThemeModeFromString(String mode) {
    switch (mode) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }

  Brightness _resolveAmbientBrightness(BuildContext context) {
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    final mq = MediaQuery.maybeOf(context);
    // MediaQuery (from View-Root) follows the current window/device brightness;
    // Fallback: PlatformDispatcher (e.g., very early during startup).
    return mq?.platformBrightness ?? dispatcher.platformBrightness;
  }

  @override
  Widget build(BuildContext context) {
    // Determine actual brightness based on theme mode
    Brightness actualBrightness;
    if (_themeMode == ThemeMode.system) {
      actualBrightness = _resolveAmbientBrightness(context);
    } else {
      actualBrightness = _themeMode == ThemeMode.dark
          ? Brightness.dark
          : Brightness.light;
    }

    final primaryColor = actualBrightness == Brightness.dark
        ? CupertinoColors.white
        : CupertinoColors.black;

    return CupertinoApp(
      title: 'Cultioo',
      locale: _locale,
      theme: _isCultiooDesktopTarget()
          ? _cupertinoThemeForCultiooDesktop(actualBrightness, primaryColor)
          : CupertinoThemeData(
              brightness: actualBrightness,
              primaryColor: primaryColor,
            ),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) {
        final mq = MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(_textScaleFactor));
        final isDark = CupertinoTheme.of(context).brightness == Brightness.dark;
        final keyboardVisible = Platform.isIOS && mq.viewInsets.bottom > 0;
        final isDesktop = _isCultiooDesktopTarget();
        final labelColor = isDark ? Colors.white : Colors.black87;

        Widget appChild = child!;
        if (isDesktop) {
          final scheme = ColorScheme(
            brightness: isDark ? Brightness.dark : Brightness.light,
            primary: isDark ? Colors.white : Colors.black,
            onPrimary: isDark ? Colors.black : Colors.white,
            secondary: isDark ? Colors.white : Colors.black,
            onSecondary: isDark ? Colors.black : Colors.white,
            error: const Color(0xFFB00020),
            onError: Colors.white,
            surface: isDark ? const Color(0xFF050506) : Colors.white,
            onSurface: isDark ? Colors.white : Colors.black,
          );
          appChild = Theme(
            data: ThemeData(
              useMaterial3: true,
              brightness: isDark ? Brightness.dark : Brightness.light,
              colorScheme: scheme,
              tooltipTheme: TooltipThemeData(
                waitDuration: const Duration(milliseconds: 350),
                showDuration: const Duration(seconds: 4),
                textStyle: TextStyle(
                  fontSize: 12,
                  height: 1.25,
                  color: isDark ? Colors.black : Colors.white,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.92)
                      : Colors.black.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              textTheme: TextTheme(
                bodyLarge: TextStyle(
                  fontSize: 13.5,
                  height: 1.38,
                  color: labelColor,
                ),
                bodyMedium: TextStyle(
                  fontSize: 13.5,
                  height: 1.38,
                  color: labelColor,
                ),
                bodySmall: TextStyle(
                  fontSize: 12.5,
                  height: 1.32,
                  color: labelColor.withValues(alpha: 0.82),
                ),
                titleMedium: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: labelColor,
                ),
                labelLarge: TextStyle(fontSize: 13.5, color: labelColor),
              ),
            ),
            child: DefaultTextStyle.merge(
              style: TextStyle(
                fontSize: 13.5,
                height: 1.38,
                color: labelColor,
              ),
              child: appChild,
            ),
          );
        }

        return MediaQuery(
          data: mq,
          child: Stack(
            children: [
              appChild,
              if (keyboardVisible)
                Positioned(
                  right: 12,
                  bottom: mq.viewInsets.bottom + 8,
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      FocusManager.instance.primaryFocus?.unfocus();
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                        child: Container(
                          height: 36,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withOpacity(0.14)
                                : Colors.white.withOpacity(0.78),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white.withOpacity(0.18)
                                  : Colors.black.withOpacity(0.08),
                              width: 0.5,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                CupertinoIcons.keyboard_chevron_compact_down,
                                size: 17,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Done',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
      home: const MyHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with TickerProviderStateMixin {
  static _MyHomePageState? _instance;

  final PageController _pageController = PageController();
  final PageController _favoritesPageController = PageController();
  int _currentPage = 0;
  int _activeDesktopTab = 0;
  final List<int> _desktopTabPages = [0];
  bool _isDesktopSplitView = false;
  int _desktopSplitLeftTab = 0;
  int _desktopSplitRightTab = 0;
  double _desktopSplitRatio = 0.5;

  // Scroll controller for search animation
  final ScrollController _scrollController = ScrollController();
  late AnimationController _searchAnimationController;
  late Animation<double> _searchAnimation;
  final bool _isSearchCollapsed = false;
  bool _isSearchExpanded = false;

  // Auth state
  bool _isLoggedIn = false;
  String _userEmail = '';
  String _userName = '';
  String _userUsername = ''; // Username for display
  String? _userPhone;
  DateTime? _userBirthDate;
  String _accessToken = '';
  Map<String, dynamic>? _currentUser;
  String? _profileImageSrc;

  // 2FA and Biometric Authentication
  bool _has2FAEnabled = false;
  String? _user2FACode;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  bool _isLoading = false;
  bool _isModalOpen = false;
  bool _isTransitioningToAnotherModal = false;
  final LocalAuthentication _localAuth = LocalAuthentication();
  final TextEditingController _2faController = TextEditingController();

  // Auto-login 2FA variables
  Map<String, dynamic>? _tempLoginResult;
  String? _pendingAutoLoginToken;
  String? _pendingAutoLoginProvider;

  // Login form controllers
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isPasswordVisible = false;

  // User data for manual input
  Map<String, String> userData = {
    'name': 'Not specified',
    'street': 'Not specified',
    'houseNumber': 'Not specified',
    'postalCode': 'Not specified',
    'city': 'Not specified',
    'country': 'Not specified',
  };

  // Extended user data
  DateTime? _lastLogin;
  DateTime? _createdAt;
  bool _isBusiness = false;
  String? _stripeAccountId;
  String? _stripeCustomerId;
  String? _businessName;
  bool _isGoogleConnected = false;
  bool _isAppleConnected = false;

  // Getters for SecurityVerificationModal
  bool get biometricAvailable => _biometricAvailable;
  bool get biometricEnabled => _biometricEnabled;
  LocalAuthentication get localAuth => _localAuth;

  // Animation controllers removed to prevent lag
  String? _businessAddress;
  String? _businessPhone;
  String? _businessEmail;
  String? _businessDescription;
  String? _businessCompany;
  String? _businessSize;
  String? _businessCountry;

  // Products state
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _filteredProducts = [];
  List<Map<String, dynamic>> _categories = [];
  int _visibleProductCount = 10;
  final LinkedHashMap<String, Uint8List> _dataImageBytesCache =
      LinkedHashMap<String, Uint8List>();
  static const int _maxDataImageCacheEntries = 24;

  // Shopping Cart
  final List<Map<String, dynamic>> _cartItems = [];
  int _cartItemCount = 0;
  Timer? _cartLoadTimer; // Debounce timer for cart loading

  // Rate limiting for API calls
  DateTime? _lastFollowedUsersLoad;
  Timer? _followedUsersLoadTimer;
  DateTime? _lastProductsLoad;
  Timer? _productsLoadTimer;
  static const Duration _apiCooldown = Duration(seconds: 10);

  // Favorites
  List<int> _favoriteProductIds = [];

  // Following users
  List<Map<String, dynamic>> _followedUsers = [];
  bool _isLoadingFollowedUsers = false;

  // Favorites page tab control
  int _selectedFavoriteTab = 0; // 0 = Products, 1 = Following

  // Notification settings for followed sellers
  final Map<String, bool> _sellerNotificationSettings = {};

  // Deep link subscription (using app_links)
  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  Future<void> _loadFavoritesFromServer() async {
    if (!ApiService.isLoggedIn) return;

    try {
      // Lade echte Favoriten vom Server
      final response = await ApiService.getFavorites();

      if (response['success'] == true) {
        final favorites = response['favorites'] as List<dynamic>? ?? [];

        setState(() {
          _favoriteProductIds = favorites
              .map(
                (fav) =>
                    int.tryParse(fav['product_id']?.toString() ?? '') ??
                    fav['id'] as int? ??
                    0,
              )
              .where((id) => id > 0)
              .toList();
        });

        // Save in SharedPreferences for offline fallback
        await _saveFavoritesToPrefs();

        // debugPrint('✅ Loaded ${_favoriteProductIds.length} favorites from server');
      } else {
        throw Exception('Invalid response from favorites API');
      }
    } catch (e) {
      // debugPrint('❌ Error loading server favorites: $e');

      // Fallback: Load from SharedPreferences if server is unavailable
      await _loadFavoritesFromPrefs();

      // Show user-friendly error message
      if (mounted) {
        _showBottomMessage(
          AppLocalizations.of(context)!.couldNotSyncFavoritesUsingOfflineData,
          isError: true,
        );
      }
    }
  }

  // Static fallback categories if API fails
  static const List<String> _fallbackCategories = [
    "Fruits & Vegetables",
    "Dairy & Eggs",
    "Meat & Sausages",
    "Bakery Products",
    "Jams & Spreads",
    "Honey",
    "Cereal Products",
    "Beverages",
    "Spices & Oils",
    "Fish & Seafood",
    "Cheese",
    "Snacks & Sweets",
    "Ice Cream",
    "Bakery Products (frozen)",
    "Soups & Ready Meals",
    "Salads & Delicacies",
    "Plants & Herbs",
    "Non-Food",
    "Canned & Preserved",
    "Pasta & Noodles",
    "Sauces & Dips",
    "Vegan & Vegetarian",
    "Organic Products",
    "Regional Specialties",
    "Gift Items",
  ];

  String _searchQuery = '';
  final Set<String> _selectedCategories = {};
  final Set<String> _selectedIncoterms = {};
  String _sortOption =
      'name_asc'; // name_asc, name_desc, price_asc, price_desc, unit
  double _searchRadius = 50.0; // Search radius in km
  bool _isLoadingProducts = false;
  final TextEditingController _searchController = TextEditingController();

  // Payment methods and transactions from API
  List<Map<String, dynamic>> _paymentMethods = [];
  List<Map<String, dynamic>> _transactions = [];

  // Orders sorting and filtering
  String _ordersSortOption =
      'date_desc'; // date_desc, date_asc, price_desc, price_asc, status
  String _selectedOrderMonth = ''; // Will be set to last month on init
  bool _showAwaitingOnly = false; // filter to show only awaiting orders
  Future<Map<String, dynamic>>?
  _ordersFuture; // cached to prevent FutureBuilder restart on every rebuild
  final Set<dynamic> _dismissedOrderIds =
      {}; // locally dismissed (closed) order IDs

  // Appearance settings
  String _themeMode = 'system'; // 'light', 'dark', 'system'
  String _textSize = 'system'; // 'system', 'small', 'medium', 'large'
  String _language = 'system'; // 'system', 'en', 'de'
  String _numberFormat = 'system'; // 'system', 'en', 'de'
  String _currency = 'system'; // 'system', 'usd', 'eur'
  double _exchangeRate = 1.0; // USD to EUR exchange rate
  Map<String, String> _localizedStrings = {};
  String _distanceUnit = 'system'; // 'system', 'km', 'miles'
  String _weightUnit = 'system'; // 'system', 'kg', 'lbs'
  String _dateFormat =
      'system'; // 'system', 'dd.MM.yyyy', 'MM/dd/yyyy', 'yyyy-MM-dd', etc.

  // User location for distance calculations
  double? _userLatitude;
  double? _userLongitude;

  // Dock settings
  bool _isDockEnabled = true;

  // CNTabBar index (synced with _currentPage)
  int _tabIndex = 0;

  // Splash screen state for macOS
  bool _showSplashScreen = true;
  double _splashOpacity = 1.0;
  double _logoScale = 1.0;
  double _sidebarWidth = 0.0;

  /// Narrow icon rail only (no labels / profile card — native desktop strip).
  static const double _kDesktopSidebarWidth = 72;

  double get _desktopSidebarOuterWidth => _kDesktopSidebarWidth;

  // Desktop right panel (detail / bottom sheets) — resizable, persisted
  static const double _desktopRightPanelMinWidth = 340;
  static const double _desktopRightPanelDefaultWidth = 520;
  double _desktopRightPanelWidth = _desktopRightPanelDefaultWidth;

  // Hide tab bar when modals are open
  final bool _hideTabBar = false;
  StreamSubscription<String>? _fcmTokenRefreshSubscription;
  bool _pushInitialized = false;
  bool _pushMessageListenerBound = false;

  @override
  void initState() {
    super.initState();
    _instance = this;

    // Initialize deep link listener
    _initDeepLinkListener();

    // Initialize modern search animation controller mit verbesserter Performance
    _searchAnimationController = AnimationController(
      duration: const Duration(
        milliseconds: 250,
      ), // Slightly faster for responsive feeling
      vsync: this,
    );

    _searchAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _searchAnimationController,
        curve: Curves.easeInOutQuart, // Noch sanftere Kurve
      ),
    );

    // Add scroll listener for search animation
    _scrollController.addListener(_onScroll);

    // Set default order month to all (so orders are always visible)
    _selectedOrderMonth = 'all';

    // Start splash screen animation for macOS
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      _startSplashAnimation();
    }

    // Skip auto-login check, go straight to initialization
    _initializeAuth();

    _initializePushNotifications();

    if (defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux) {
      _loadDesktopChromePrefs();
    }
  }

  Future<void> _loadDesktopChromePrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final w = prefs.getDouble('cultioo_desktop_right_panel_width');
      setState(() {
        if (w != null && w >= _desktopRightPanelMinWidth && w <= 980) {
          _desktopRightPanelWidth = w;
        }
      });
    } catch (_) {}
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final maxW = _maxRightPanelWidth(context);
      if (_desktopRightPanelWidth > maxW) {
        setState(() => _desktopRightPanelWidth = maxW);
      }
    });
  }

  Future<void> _saveDesktopRightPanelWidth() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(
        'cultioo_desktop_right_panel_width',
        _desktopRightPanelWidth,
      );
    } catch (_) {}
  }

  double _maxRightPanelWidth(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;
    const minMain = 340.0;
    const leftHandle = 6.0;
    const rightHandle = 8.0;
    final sidebarW =
        _showSplashScreen ? _sidebarWidth : _desktopSidebarOuterWidth;
    final reserved = sidebarW + leftHandle + rightHandle + minMain;
    return (screenW - reserved).clamp(_desktopRightPanelMinWidth, 960);
  }

  Widget _buildRightPanelResizeHandle(bool isDark) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: (details) {
        final maxW = _maxRightPanelWidth(context);
        setState(() {
          _desktopRightPanelWidth = (_desktopRightPanelWidth + details.delta.dx)
              .clamp(_desktopRightPanelMinWidth, maxW);
        });
      },
      onHorizontalDragEnd: (_) => _saveDesktopRightPanelWidth(),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: SizedBox(
          width: 8,
          child: Center(
            child: Container(
              width: 2,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withOpacity(0.12)
                    : Colors.black.withOpacity(0.10),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Modern smooth scroll listener for search bar animation
  void _onScroll() {
    // AppBar background is solid - no scroll-driven animation needed
  }

  // Handle search expansion with bounce effect
  void _toggleSearchExpansion() {
    // Haptic Feedback for better user experience
    HapticFeedback.lightImpact();

    setState(() {
      _isSearchExpanded = !_isSearchExpanded;
    });

    // Keine Animation mehr, damit sich nichts verschiebt
    // if (_isSearchExpanded) {
    //   _searchAnimationController.forward();
    // } else {
    //   _searchAnimationController.reverse();
    // }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _2faController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    _searchAnimationController.dispose();
    _cartLoadTimer?.cancel(); // Cancel any pending cart load timer
    _followedUsersLoadTimer
        ?.cancel(); // Cancel any pending followed users timer
    _productsLoadTimer?.cancel(); // Cancel any pending products timer
    _fcmTokenRefreshSubscription?.cancel();
    _dataImageBytesCache.clear();
    _linkSubscription?.cancel(); // Cancel deep link listener
    _instance = null; // Clear the instance
    super.dispose();
  }

  String _pushPlatformLabel() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      default:
        return 'unknown';
    }
  }

  Future<void> _initializePushNotifications() async {
    if (_pushInitialized) return;
    _pushInitialized = true;

    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);

      if (!_pushMessageListenerBound) {
        _pushMessageListenerBound = true;
        FirebaseMessaging.onMessage.listen((message) {
          debugPrint('📩 Foreground push received: ${message.messageId ?? 'no-id'}');
        });
      }

      _fcmTokenRefreshSubscription?.cancel();
      _fcmTokenRefreshSubscription = messaging.onTokenRefresh.listen((newToken) {
        ApiService.registerDevicePushToken(
          token: newToken,
          platform: _pushPlatformLabel(),
        );
      });

      await _syncPushTokenForCurrentUser();
    } catch (e) {
      debugPrint('⚠️ Push initialization failed: $e');
    }
  }

  Future<void> _syncPushTokenForCurrentUser() async {
    if (!ApiService.isLoggedIn || !_isLoggedIn) return;

    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;

      await ApiService.registerDevicePushToken(
        token: token,
        platform: _pushPlatformLabel(),
      );
    } catch (e) {
      debugPrint('⚠️ Failed to sync push token: $e');
    }
  }

  Future<void> _unregisterPushTokenForCurrentUser() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;
      await ApiService.unregisterDevicePushToken(token);
    } catch (e) {
      debugPrint('⚠️ Failed to unregister push token: $e');
    }
  }

  Uint8List? _decodeDataImageCached(String dataUrl) {
    final cached = _dataImageBytesCache[dataUrl];
    if (cached != null) {
      // Refresh recency (simple LRU)
      _dataImageBytesCache.remove(dataUrl);
      _dataImageBytesCache[dataUrl] = cached;
      return cached;
    }

    try {
      final commaIndex = dataUrl.indexOf(',');
      if (commaIndex < 0 || commaIndex >= dataUrl.length - 1) return null;

      final rawBase64 = dataUrl
          .substring(commaIndex + 1)
          .replaceAll(RegExp(r'\s+'), '');
      if (rawBase64.isEmpty) return null;

      final bytes = base64Decode(rawBase64);
      _dataImageBytesCache[dataUrl] = bytes;

      while (_dataImageBytesCache.length > _maxDataImageCacheEntries) {
        _dataImageBytesCache.remove(_dataImageBytesCache.keys.first);
      }
      return bytes;
    } catch (_) {
      return null;
    }
  }

  // Splash screen animation for macOS
  void _startSplashAnimation() async {
    // Wait a moment to show the splash
    await Future.delayed(const Duration(milliseconds: 800));

    // Start scaling logo and fading
    setState(() {
      _logoScale = 0.6;
      _splashOpacity = 0.8;
    });

    await Future.delayed(const Duration(milliseconds: 400));

    // Move logo to sidebar position and start revealing sidebar
    setState(() {
      _sidebarWidth = 250.0;
    });

    await Future.delayed(const Duration(milliseconds: 600));

    // Hide splash screen
    setState(() {
      _showSplashScreen = false;
    });
  }

  // Show notification message at top instead of bottom sheet
  void _showBottomMessage(
    String message, {
    bool isError = false,
    bool isSuccess = false,
  }) {
    // For success messages, we'll use the regular notification with green color
    if (isError) {
      TopNotification.error(context, message);
    } else {
      TopNotification.success(context, message);
    }
  }

  bool _flagIsEnabled(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value == 1;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == '1' || normalized == 'true' || normalized == 'yes';
    }
    return false;
  }

  Future<void> _refresh2FAStateFromServer() async {
    try {
      final profileResponse = await ApiService.getUserProfile();
      final user = profileResponse?['user'];
      if (user == null) return;

      final has2FA = _flagIsEnabled(user['has_2fa_enabled']);
      final code = user['twofa']?.toString();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('has_2fa_enabled', has2FA);
      if (has2FA && code != null && code.isNotEmpty) {
        await prefs.setString('user_2fa_code', code);
      } else {
        await prefs.remove('user_2fa_code');
      }

      if (!mounted) return;
      setState(() {
        _has2FAEnabled = has2FA;
        _user2FACode = has2FA ? code : null;
      });
    } catch (_) {
      // Keep current local state if profile refresh fails.
    }
  }

  Future<void> _initializeAuth() async {
    debugPrint('🔄 Starting app initialization...');

    try {
      // Phase 1: Critical initialization (no network)
      await _checkBiometricAvailability();
      debugPrint('✅ Biometric availability checked');
    } catch (e) {
      debugPrint('⚠️ Failed to check biometric availability: $e');
    }

    try {
      await _loadStoredCredentials();
      debugPrint('✅ Credentials loaded');
    } catch (e) {
      debugPrint('⚠️ Failed to load credentials: $e');
    }

    try {
      await _loadAppearanceSettings();
      debugPrint('✅ Appearance settings loaded');
    } catch (e) {
      debugPrint('⚠️ Failed to load appearance settings: $e');
    }

    // Check if Google was connected before
    try {
      final isGoogleLogin = await DeviceStorage.getBool('is_google_login');
      final isAppleLogin = await DeviceStorage.getBool('is_apple_login');
      setState(() {
        _isGoogleConnected = isGoogleLogin;
        _isAppleConnected = isAppleLogin;
      });
    } catch (e) {
      debugPrint('⚠️ Failed to check Google connection: $e');
    }

    // Load user location for radius filtering
    try {
      await _loadUserLocation();
      debugPrint('✅ User location loaded');
    } catch (e) {
      debugPrint('⚠️ Failed to load user location: $e');
    }

    // Load favorites immediately (important for UI)
    try {
      await _loadFavoritesFromPrefs();
    } catch (e) {
      debugPrint('⚠️ Failed to load favorites from prefs: $e');
    }

    // Load followed users from cache immediately (important for UI)
    try {
      await _loadFollowedUsersFromPrefs();
    } catch (e) {
      debugPrint('⚠️ Failed to load followed users from prefs: $e');
    }

    // Load dismissed order IDs so cancelled orders stay hidden after restart
    try {
      await _loadDismissedOrderIds();
    } catch (e) {
      debugPrint('⚠️ Failed to load dismissed order IDs: $e');
    }

    // Phase 2: Authentication
    try {
      await _tryAutoLogin();
      debugPrint('✅ Auto-login attempt completed');
    } catch (e) {
      debugPrint('⚠️ Auto-login failed: $e');
    }

    // Phase 3: User data (only if needed)
    if (_isLoggedIn) {
      _loadUserData();
      // Nach Login sofort Server-Favoriten laden
      _loadFavoritesFromServer();
      // Load followed users immediately after login
      _loadFollowedUsersFromServer();
      // Calculate product count for business users
      Future.delayed(const Duration(milliseconds: 200), () {
        _calculateUserProductCount();
      });
    }

    // Phase 4: Background data loading with larger delays
    Future.delayed(const Duration(milliseconds: 500), () async {
      await _loadDataSequentially();
    });

    // Rate-limited followed users loading - only if logged in and after longer delay
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && _isLoggedIn && ApiService.isLoggedIn) {
        _loadFollowedUsersFromServer();
      }
    });

    // Phase 6: Load seller notification settings last
    Future.delayed(const Duration(seconds: 3), () {
      _loadSellerNotificationSettings();
    });
  }

  Future<void> _loadDataSequentially() async {
    try {
      // Load products first (non-blocking)
      _loadProducts();

      // Wait longer between API calls to prevent rate limiting and improve performance
      await Future.delayed(const Duration(seconds: 2));

      // Load cart count only if logged in
      if (_isLoggedIn) {
        _loadCartCount();
        await Future.delayed(const Duration(seconds: 1));
      }

      // Load favorites from local storage (no API call)
      _loadFavoritesFromPrefs();
    } catch (e) {
      //debugPrint('Error in sequential data loading: $e');
    }
  }

  Future<void> _loadAppearanceSettings() async {
    if (!mounted) return;
    try {
      final settings = await SettingsService.loadLocalSettings();
      if (!mounted) return;
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _themeMode = settings['theme'] ?? 'system';
        _textSize = settings['textSize'] ?? 'system';
        _language = settings['language'] ?? 'system';
        _numberFormat = settings['numberFormat'] ?? 'system';
        _currency = settings['currency'] ?? 'system';
        _isDockEnabled = settings['dockEnabled'] ?? true;
        _localizedStrings = SettingsService.getLocalizedStrings(
          _resolveLanguage(),
        );
        _distanceUnit = prefs.getString('distance_unit') ?? 'system';
        _weightUnit = prefs.getString('weight_unit') ?? 'system';
        _dateFormat = prefs.getString('date_format') ?? 'system';
      });

      if (!mounted) return;
      setNumberFormatStyleIndex(_resolveNumberFormat() == 'de' ? 1 : 0);

      if (_resolveCurrency() == 'eur') {
        await _loadExchangeRate();
      }

      //debugPrint('📱 Appearance settings loaded: theme=$_themeMode, textSize=$_textSize, language=$_language, numberFormat=$_numberFormat, currency=$_currency, dock=$_isDockEnabled');
    } catch (e) {
      //debugPrint('❌ Error loading appearance settings: $e');
    }
  }

  // Load user location for distance calculations
  Future<void> _loadUserLocation() async {
    try {
      // Try to get from addresses first (using selected address)
      if (_isLoggedIn) {
        final addresses = await ApiService.getUserAddresses();
        if (addresses.isNotEmpty) {
          for (final address in addresses) {
            if (address['isSelected'] == 1) {
              final lat = address['lat'];
              final lng = address['lng'];
              if (lat != null && lng != null) {
                setState(() {
                  _userLatitude = double.tryParse(lat.toString()) ?? 0.0;
                  _userLongitude = double.tryParse(lng.toString()) ?? 0.0;
                });
                debugPrint(
                  '📍 User location loaded from selected address: $_userLatitude, $_userLongitude',
                );
                return;
              }
            }
          }
        }
      }

      // Fallback: Use a default location (can be replaced with GPS in the future)
      // For now, use Berlin as default
      setState(() {
        _userLatitude = 52.5200;
        _userLongitude = 13.4050;
      });
      debugPrint(
        '📍 Using default location (Berlin): $_userLatitude, $_userLongitude',
      );
    } catch (e) {
      debugPrint('⚠️ Error loading user location: $e');
      // Fallback to Berlin
      setState(() {
        _userLatitude = 52.5200;
        _userLongitude = 13.4050;
      });
    }
  }

  // Load current USD to EUR exchange rate
  Future<void> _loadExchangeRate() async {
    try {
      // Simple fallback exchange rate - in production you'd use a real API
      // You could use APIs like:
      // - exchangerate-api.com
      // - fixer.io
      // - currencylayer.com
      // - xe.com API

      // For now, use a reasonable fixed rate (updates can be added later)
      setState(() {
        _exchangeRate = 0.85; // 1 USD = 0.85 EUR
      });
      //debugPrint('💱 Exchange rate set: 1 USD = $_exchangeRate EUR');
    } catch (e) {
      //debugPrint('💱 Error loading exchange rate: $e');
      // Fallback exchange rate
      setState(() {
        _exchangeRate = 0.85; // 1 USD = 0.85 EUR
      });
    }
  }

  Future<void> _loadUserData() async {
    // Check if user is logged in
    if (_currentUser != null) {
      await _loadPaymentMethods();
    }
  }

  Future<void> _loadPaymentMethods() async {
    try {
      debugPrint('📊 Loading payment methods...');
      // Use ApiService for consistency
      final paymentMethods = await ApiService.getPaymentMethods();
      setState(() {
        _paymentMethods = paymentMethods;
      });
      debugPrint('✅ Payment Methods loaded: ${_paymentMethods.length}');

      // Debug: Print payment methods details
      for (var i = 0; i < _paymentMethods.length; i++) {
        final method = _paymentMethods[i];
        debugPrint(
          '   📋 Method $i: ${method['type']} - ${method['card']?['brand']} *${method['card']?['last4']}',
        );
      }
    } catch (e) {
      debugPrint('❌ Error loading payment methods: $e');
      // Bei Fehler leere Liste setzen
      setState(() {
        _paymentMethods = [];
      });
    }
  }

  // Deep link handler for Google OAuth callback (using app_links package)
  void _initDeepLinkListener() async {
    try {
      _appLinks = AppLinks();

      // Handle initial deep link when app is opened from terminated state
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _handleDeepLinkUri(initialUri);
      }

      // Handle deep links when app is already running
      _linkSubscription = _appLinks.uriLinkStream.listen(
        (Uri uri) {
          _handleDeepLinkUri(uri);
        },
        onError: (err) {
          debugPrint('❌ Deep link error: $err');
        },
      );

      debugPrint('✅ Deep link listener initialized (app_links)');
    } catch (e) {
      debugPrint('❌ Failed to initialize deep link listener: $e');
    }
  }

  void _handleDeepLinkUri(Uri uri) {
    debugPrint('🔗 Deep link received: ${uri.toString()}');

    // Handle auth callback
    if (uri.scheme == 'cultioo' &&
        uri.host == 'auth' &&
        uri.path == '/callback') {
      _handleAuthCallback(uri);
      return;
    }

    // Handle other deep links (products, etc.)
    _handleDeepLink(uri.toString());
  }

  Future<void> _handleAuthCallback(Uri uri) async {
    try {
      debugPrint('🔗 Auth callback received: ${uri.toString()}');

      final encodedData = uri.queryParameters['data'];
      if (encodedData == null) {
        debugPrint('❌ No data in auth callback');
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final decoded = jsonDecode(Uri.decodeComponent(encodedData));
      debugPrint('✅ Successfully decoded auth data');
      debugPrint('   Success: ${decoded['success']}');

      setState(() {
        _isLoading = false;
      });

      if (decoded['success'] == true) {
        await _handleSocialLoginSuccess(
          Map<String, dynamic>.from(decoded as Map),
          provider: 'google',
        );

        if (mounted) {
          final l10n = AppLocalizations.of(context)!;
          TopNotification.success(
            context,
            decoded['isNewUser'] == true
                ? l10n.accountCreatedSuccess
                : l10n.signedInWithGoogle,
          );
        }
      } else {
        // Handle error with detailed message
        final errorMessage =
            decoded['error'] ?? AppLocalizations.of(context)!.signInFailed;
        debugPrint('❌ Google Sign-in error: $errorMessage');

        if (mounted) {
          TopNotification.error(context, errorMessage);
        }
      }
    } catch (e) {
      debugPrint('❌ Error handling auth callback: $e');
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)!.signInFailedWithError(e.toString()),
        );
      }
    }
  }

  void _handleDeepLink(String link) async {
    debugPrint('🔗 Deep link received: $link');

    // Handle OAuth callback from Google Sign-In
    if (link.startsWith('cultioo://auth-callback')) {
      try {
        final uri = Uri.parse(link);
        final dataParam = uri.queryParameters['data'];

        if (dataParam != null) {
          // Decode base64 data
          final jsonString = utf8.decode(base64.decode(dataParam));
          final data = jsonDecode(jsonString);

          debugPrint('✅ OAuth callback received via deep link');

          if (data is Map<String, dynamic> && data['success'] == true) {
            await _handleSocialLoginSuccess(data, provider: 'google');

            if (mounted) {
              TopNotification.success(
                context,
                AppLocalizations.of(context)!.signedInSuccess,
              );
            }
          } else {
            final errorMessage = (data is Map<String, dynamic>)
                ? (data['error']?.toString() ??
                      data['message']?.toString() ??
                      AppLocalizations.of(context)!.signInFailed)
                : AppLocalizations.of(context)!.signInFailed;
            debugPrint('❌ OAuth callback error payload: $errorMessage');
            if (mounted) {
              TopNotification.error(context, errorMessage);
            }
          }
        }
      } catch (e) {
        debugPrint('❌ Error handling OAuth callback: $e');
        if (mounted) {
          TopNotification.error(
            context,
            AppLocalizations.of(context)!.signInFailed,
          );
        }
      }
      return;
    }

    if (link.startsWith('cultioo://auth/callback')) {
      try {
        final uri = Uri.parse(link);
        final success = uri.queryParameters['success'] == 'true';

        if (success) {
          final username = uri.queryParameters['username'] ?? '';
          final email = uri.queryParameters['email'] ?? '';
          final name = uri.queryParameters['name'] ?? '';
          final phone = uri.queryParameters['phone'] ?? '';
          final has2FA = uri.queryParameters['has_2fa_enabled'] == 'true';
          final accessToken = uri.queryParameters['accessToken'] ?? '';
          final refreshToken = uri.queryParameters['refreshToken'] ?? '';

          debugPrint('✅ Google Sign-In successful via deep link');
          debugPrint('   Username: $username');
          debugPrint('   Email: $email');

          // Store tokens and update state
          await DeviceStorage.setString('access_token', accessToken);
          await DeviceStorage.setString('auth_token', accessToken);
          await DeviceStorage.setString('refresh_token', refreshToken);
          await DeviceStorage.setString('username', username);
          await DeviceStorage.setString('stored_username', email.isNotEmpty ? email : username);
          await DeviceStorage.setString('stored_password', 'GOOGLE_AUTH');
          await DeviceStorage.setBool('auto_login_enabled', true);
          await DeviceStorage.setBool('is_google_login', true);
          await DeviceStorage.setBool('is_apple_login', false);

          // Update API service with new session
          await ApiService.saveTokenForLogin(accessToken);

          setState(() {
            _isLoggedIn = true;
            _userEmail = email;
            _userName = name;
            _userUsername = username;
            _userPhone = phone.isNotEmpty ? phone : null;
            _has2FAEnabled = has2FA;
            _accessToken = accessToken;
            _isGoogleConnected = true;
          });

          // Load user data
          await _loadRealData();
          await _loadFavoritesFromServer();
          await _loadFollowedUsersFromServer();

          // Show success message
          if (mounted) {
            _showBottomMessage(
              AppLocalizations.of(context)!.signedInWithGoogle,
              isSuccess: true,
            );
          }
        }
      } catch (e) {
        debugPrint('❌ Error handling deep link: $e');
        if (mounted) {
          _showBottomMessage(
            AppLocalizations.of(context)!.signInFailed,
            isError: true,
          );
        }
      }
    }
  }

  // Load real data from Stripe and user profile
  Future<void> _loadRealData() async {
    debugPrint('🔄 _loadRealData() CALLED - Starting to load user profile...');

    try {
      // Load user profile
      debugPrint('📡 Calling ApiService.getUserProfile()...');
      final profileResponse = await ApiService.getUserProfile();
      debugPrint('📡 getUserProfile() response: $profileResponse');
      final localBiometricEnabled = await DeviceStorage.getBool(
        'biometric_enabled',
      );

      if (profileResponse != null && profileResponse['user'] != null) {
        final user = profileResponse['user'];

        debugPrint('🔍 DEBUG: Profile Response from Server:');
        debugPrint('  - name: ${user['name']}');
        debugPrint('  - email: ${user['email']}');
        debugPrint('  - username: ${user['username']}');
        debugPrint('  - phone: ${user['phone']}');
        debugPrint('  - birthdate: ${user['birthdate']}');

        setState(() {
          _userEmail = user['email'] ?? _userEmail;
          _userName = user['name'] ?? _userName;
          _userUsername = user['username'] ?? _userUsername;
          _userPhone = user['phone'];

          debugPrint('🔍 DEBUG: After setState:');
          debugPrint('  - _userName: $_userName');
          debugPrint('  - _userEmail: $_userEmail');
          debugPrint('  - _userUsername: $_userUsername');
          debugPrint('  - _userPhone: $_userPhone');

          // Parse birthdate
          if (user['birthdate'] != null) {
            try {
              _userBirthDate = DateTime.parse(user['birthdate']);
            } catch (e) {
              //debugPrint('Error parsing birth date: $e');
            }
          }

          // Extended user data
          // _profilePic = user['profilePic']; // Temporarily disabled

          // Parse lastLogin from database
          if (user['lastLogin'] != null) {
            try {
              _lastLogin = DateTime.parse(user['lastLogin']);
              //debugPrint('🔍 lastLogin from database: ${user['lastLogin']} -> parsed: $_lastLogin');
            } catch (e) {
              //debugPrint('Fehler beim Parsen des letzten Logins: $e');
              _lastLogin = DateTime.now();
            }
          } else {
            //debugPrint('🔍 No lastLogin in database, using current time');
            _lastLogin = DateTime.now();
          }

          // Parse createdAt
          if (user['createdAt'] != null) {
            try {
              _createdAt = DateTime.parse(user['createdAt']);
            } catch (e) {
              //debugPrint('Fehler beim Parsen des Erstellungsdatums: $e');
            }
          }

          _isBusiness = user['isBusiness'] == 1 || user['isBusiness'] == true;
          debugPrint('🔍 _loadRealData - isBusiness set to: $_isBusiness');
          debugPrint(
            '🔍 _loadRealData - isBusiness from server: ${user['isBusiness']}',
          );
          debugPrint(
            '🔍 _loadRealData - isBusiness type: ${user['isBusiness'].runtimeType}',
          );

          // Stripe Daten
          _stripeAccountId = user['stripeAccountId'];
          _stripeCustomerId = user['stripeCustomerId'];

          // Business Daten
          _businessName = user['businessName'];
          _businessAddress = user['businessAddress'];
          _businessPhone = user['businessPhone'];
          _businessEmail = user['businessEmail'];
          _businessDescription = user['businessDescription'];
          _businessCompany = user['business_company'];
          _businessSize = user['business_size'];
          _businessCountry = user['business_country'];

          // Biometric and 2FA settings
          final serverBiometricRaw = user['biometric_enabled'];
          _biometricEnabled =
              serverBiometricRaw == null
              ? localBiometricEnabled
              : _flagIsEnabled(serverBiometricRaw);
          _has2FAEnabled = _flagIsEnabled(user['has_2fa_enabled']);
          _user2FACode = user['twofa'];

          // Location data removed to prevent lag

          // IMPORTANT: Set _currentUser for Payment Methods Loading
          _currentUser = user;
          _profileImageSrc = _normalizeProfileImageSource(
            user['profileImage'] ?? user['profilePic'] ?? user['profile_image'],
          );
        });

        // Calculate product count for business users (after setState)
        await _calculateUserProductCount();

        //debugPrint('🔍 DEBUG: Loaded user data from API:');
        //debugPrint('   📧 Email: $_userEmail');
        //debugPrint('   👤 Name: $_userName');
        //debugPrint('   📱 Phone: $_userPhone');
        //debugPrint('   🏠 Address: $_userAddress');
        //debugPrint('   🏢 Business: $_isBusiness');
        //debugPrint('   🔒 Biometric: $_biometricEnabled');
        //debugPrint('   🔐 2FA: $_has2FAEnabled');
      }

      // Load real payment methods
      final paymentMethods = await ApiService.getPaymentMethods();
      setState(() {
        _paymentMethods = paymentMethods;
      });

      // Load real transactions
      final transactions = await ApiService.getTransactions();
      setState(() {
        _transactions = transactions;
      });

      debugPrint(
        '✅ Real data loaded: ${_paymentMethods.length} payment methods, ${_transactions.length} transactions',
      );
      debugPrint(
        '✅ User data: Name=$_userName, Email=$_userEmail, Business=$_isBusiness',
      );
      debugPrint('✅ Business: $_businessName');
      debugPrint('✅ Stripe Customer: $_stripeCustomerId');
    } catch (e) {
      debugPrint('❌ Fehler beim Laden der echten Daten: $e');

      if (mounted) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)!.errorLoadingUserData(e.toString()),
        );
      }
    }
  }

  // Login with username and password
  void _login() async {
    debugPrint('🔄 Login started for user: ${_usernameController.text.trim()}');
    debugPrint('🔍 DEBUG: Login called from: ${StackTrace.current}');

    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      TopNotification.error(
        context,
        AppLocalizations.of(context)!.enterUsernamePassword,
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      debugPrint('📡 Trying API login...');

      // Try real login via API
      final loginResult = await ApiService.login(username, password);

      debugPrint('✅ API login response received: ${loginResult.toString()}');

      if (loginResult['success']) {
        // Check if 2FA is required AND has a valid code
        if (loginResult['requiresTwoFactor'] == true &&
            loginResult['twoFactorCode'] != null &&
            loginResult['twoFactorCode'].toString().isNotEmpty) {
          //debugPrint('🔐 2FA required, showing dialog');
          setState(() {
            _isLoading = false;
            _user2FACode = loginResult['twoFactorCode'];
            _has2FAEnabled = true;
          });
          _show2FALoginDialog(loginResult);
          return;
        }

        // If we have user data, it means login is complete
        if (loginResult['user'] != null) {
          // Debug: Print user data to check 2FA fields
          //debugPrint('🔍 User data from server: ${loginResult['user']}');

          // Check if user has 2FA enabled from server
          var userHas2FA =
              loginResult['user']['has_2fa_enabled'] == true ||
              loginResult['user']['has_2fa_enabled'] == 1;
          var user2FACode = loginResult['user']['twofa'];

          // If server doesn't provide 2FA data, check stored code first
          if (!userHas2FA ||
              user2FACode == null ||
              user2FACode.toString().isEmpty) {
            try {
              final prefs = await SharedPreferences.getInstance();
              String? storedCode = prefs.getString('user_2fa_code');
              bool storedHas2FA = prefs.getBool('has_2fa_enabled') ?? false;

              if (storedCode != null && storedHas2FA) {
                //debugPrint('🔐 Using stored 2FA code: $storedCode');
                userHas2FA = true;
                user2FACode = storedCode;
              } else {
                //debugPrint('🔒 No 2FA code found - 2FA disabled');
                userHas2FA = false;
                user2FACode = null;
              }
            } catch (e) {
              debugPrint('⚠️ Failed to load 2FA from SharedPreferences: $e');
              // If SharedPreferences fails, assume no 2FA
              userHas2FA = false;
              user2FACode = null;
            }
          }

          //debugPrint('🔍 Final 2FA Check: userHas2FA=$userHas2FA, user2FACode=$user2FACode');

          // Only show 2FA if both conditions are met: user has 2FA AND there's a valid code
          if (userHas2FA &&
              user2FACode != null &&
              user2FACode.toString().isNotEmpty) {
            //debugPrint('🔐 2FA required, showing dialog');
            setState(() {
              _isLoading = false;
              _user2FACode = user2FACode;
              _has2FAEnabled = true;
            });
            _show2FALoginDialog(loginResult);
            return;
          } else {
            //debugPrint('🔓 No 2FA required - proceeding with direct login');
          }

          // Complete login if no 2FA required — but first verify via email OTP
          final userEmail = (loginResult['user']['email'] ?? '').toString();
          final userName = (loginResult['user']['username'] ?? username)
              .toString();
          
          debugPrint('🔍 Checking email verification skip for user: "$userName"');
          
          // Skip email verification for demo_reviewer
          if (userName.toLowerCase().trim() == 'demo_reviewer') {
            debugPrint('🔓 Skipping email verification for demo_reviewer');
            await _completeLogin(loginResult);
            return;
          }
          
          // Store result temporarily so the modal can complete login
          setState(() {
            _tempLoginResult = loginResult;
          });
          // Send the email code first; only open OTP modal on success
          await ApiService.sendLoginEmailCode(userName);
          _showLoginEmailVerificationModal(userEmail, userName);
        }
      } else {
        debugPrint('❌ Login result success=false');
        throw Exception(
          'Login failed: ${loginResult['message'] ?? AppLocalizations.of(context)!.invalidCredentials}',
        );
      }
    } catch (e) {
      debugPrint('❌ Login Fehler: $e');
      debugPrint('❌ Stack trace: ${StackTrace.current}');

      if (mounted) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)!.loginFailedWithError(e.toString()),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      //debugPrint('🔄 Login completed');
    }
  }

  // GOOGLE SIGN-IN - Direct redirect (simple, no polling needed)
  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
    });

    try {
      debugPrint('🔵 Starting Google Sign-In...');

      // Open Google OAuth directly
      final googleAuthUrl = '${ApiService.baseUrl}/auth/google-login';

      debugPrint('🌐 Opening: $googleAuthUrl');

      final uri = Uri.parse(googleAuthUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(
          uri,
          mode: Platform.isMacOS
              ? LaunchMode.externalApplication
              : LaunchMode.inAppBrowserView,
        );
      }
    } catch (e) {
      debugPrint('❌ Error: $e');

      if (mounted) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)!.signInFailed,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _signUpWithGoogle() async {
    await _signInWithGoogle();
  }

  bool _isSocialAuthProvider(String? provider) {
    final normalized = (provider ?? '').toLowerCase();
    return normalized == 'google' || normalized == 'apple';
  }

  Future<void> _handleSocialLoginSuccess(
    Map<String, dynamic> rawLoginResult, {
    required String provider,
  }) async {
    final loginResult = Map<String, dynamic>.from(rawLoginResult);
    loginResult['authProvider'] = provider;

    final user = loginResult['user'];
    final username =
        loginResult['username']?.toString() ?? user?['username']?.toString();
    final twoFactorCode =
        loginResult['twoFactorCode']?.toString() ?? user?['twofa']?.toString();
    final userHas2FA =
        user?['has_2fa_enabled'] == true || user?['has_2fa_enabled'] == 1;
    final requiresTwoFactor =
        loginResult['requiresTwoFactor'] == true ||
        (userHas2FA && twoFactorCode != null && twoFactorCode.isNotEmpty);

    if (requiresTwoFactor && username != null && username.isNotEmpty) {
      loginResult['requiresTwoFactor'] = true;
      loginResult['username'] = username;
      if (twoFactorCode != null && twoFactorCode.isNotEmpty) {
        loginResult['twoFactorCode'] = twoFactorCode;
      }

      setState(() {
        _isLoading = false;
        _tempLoginResult = loginResult;
        _has2FAEnabled = true;
        _user2FACode = twoFactorCode;
      });
      _show2FALoginDialog(loginResult);
      return;
    }

    await _completeLogin(loginResult);
  }

  Future<void> _signInWithApple() async {
    if (!Platform.isIOS) {
      TopNotification.error(context, 'Apple Sign-In is only available on iOS');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final isAvailable = await SignInWithApple.isAvailable();
      if (!isAvailable) {
        throw Exception('Apple Sign-In is not available on this device');
      }

      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      final fullName = [
        credential.givenName,
        credential.familyName,
      ].where((e) => e != null && e.trim().isNotEmpty).join(' ').trim();

      final loginResult = await ApiService.appleNativeSignIn(
        identityToken: credential.identityToken,
        authorizationCode: credential.authorizationCode,
        userIdentifier: credential.userIdentifier ?? '',
        email: credential.email,
        fullName: fullName.isEmpty ? null : fullName,
      );

      if (loginResult['success'] == true) {
        await _handleSocialLoginSuccess(loginResult, provider: 'apple');

        if (mounted) {
          TopNotification.success(context, 'Signed in with Apple');
        }
      } else {
        throw Exception(loginResult['message'] ?? 'Apple Sign-In failed');
      }
    } catch (e) {
      if (mounted) {
        TopNotification.error(
          context,
          e.toString().replaceAll('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _generateRandomString(int length) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    return List.generate(
      length,
      (index) => chars[random.nextInt(chars.length)],
    ).join();
  }

  Future<void> _completeLogin(Map<String, dynamic> loginResult) async {
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    debugPrint('🔄 COMPLETING LOGIN');
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    debugPrint('📦 loginResult keys: ${loginResult.keys.toList()}');
    debugPrint('📦 loginResult: $loginResult');

    // Check if user data is present, if not, we need to handle it differently
    if (loginResult['user'] == null) {
      debugPrint('❌ No user data in loginResult, cannot complete login');
      debugPrint('🔍 DEBUG: loginResult keys: ${loginResult.keys.toList()}');
      debugPrint('🔍 DEBUG: Full loginResult: $loginResult');

      if (mounted) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)!.loginFailedNoUserData,
        );
      }
      return;
    }

    debugPrint('✅ User data found, proceeding with login completion');
    debugPrint('👤 User data from server: ${loginResult['user']}');
    debugPrint('👤 Username: ${loginResult['user']['username']}');
    debugPrint('👤 Email: ${loginResult['user']['email']}');
    debugPrint('👤 Name: ${loginResult['user']['name']}');
    debugPrint('👤 Phone: ${loginResult['user']['phone']}');
    debugPrint('👤 Birthdate: ${loginResult['user']['birthdate']}');

    setState(() {
      _isLoggedIn = true;
      _userEmail = loginResult['user']['email'] ?? '';
      _userName = loginResult['user']['name'] ?? '';
      _userUsername = loginResult['user']['username'] ?? '';
      _userPhone = loginResult['user']['phone'];

      // Parse birthdate from login
      if (loginResult['user']['birthdate'] != null) {
        try {
          _userBirthDate = DateTime.parse(loginResult['user']['birthdate']);
        } catch (e) {
          debugPrint('❌ Error parsing birthdate: $e');
        }
      }

      _accessToken = loginResult['accessToken'] ?? '';
      _currentUser = loginResult['user'];
      _profileImageSrc = _normalizeProfileImageSource(
        loginResult['user']['profileImage'] ??
            loginResult['user']['profilePic'] ??
            loginResult['user']['profile_image'],
      );
      _isBusiness =
          loginResult['user']['isBusiness'] == 1 ||
          loginResult['user']['isBusiness'] == true;
      _tempLoginResult = null;
    });

    debugPrint('🔍 State updated in _completeLogin:');
    debugPrint('  _isLoggedIn: $_isLoggedIn');
    debugPrint('  _userEmail: $_userEmail');
    debugPrint('  _userName: $_userName');
    debugPrint('  _userPhone: $_userPhone');
    debugPrint('  _userBirthDate: $_userBirthDate');
    debugPrint('  _isBusiness: $_isBusiness');
    debugPrint('  isBusiness from server: ${loginResult['user']['isBusiness']}');
    debugPrint(
      '  isBusiness type: ${loginResult['user']['isBusiness'].runtimeType}',
    );
    debugPrint('  _currentUser: $_currentUser');
    debugPrint(
      '  _accessToken: ${_accessToken.substring(0, min(30, _accessToken.length))}...',
    );
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

    // Token is already saved in ApiService.login() - DO NOT save again!
    // Saving again would create a NEW session ID and invalidate the previous one
    if (_accessToken.isNotEmpty) {
      debugPrint('✅ Setting access token in ApiService...');
      ApiService.setAccessToken(_accessToken);
      debugPrint('✅ Token active in ApiService memory');
      await _syncPushTokenForCurrentUser();
    } else {
      debugPrint('❌ ERROR: Empty access token!');
    }

    // Save credentials for auto-login with error handling
    try {
      debugPrint('💾 Attempting to save credentials to DeviceStorage...');
      final prefs = await SharedPreferences.getInstance();
      final username = _usernameController.text.trim();
      final password = _passwordController.text.trim();

      // CRITICAL: Clear old token FIRST to prevent stale data
      debugPrint('🗑️ Clearing old authentication data from DeviceStorage...');
      await DeviceStorage.remove('access_token');
      await DeviceStorage.remove('auth_token');
      debugPrint('✅ Old tokens cleared from DeviceStorage');

      final explicitProvider = (loginResult['authProvider'] ?? '')
          .toString()
          .toLowerCase();
      final isGoogleLogin = explicitProvider == 'google';
      final isAppleLogin = explicitProvider == 'apple';
      final isSocialLogin = isGoogleLogin || isAppleLogin;

      // Ensure we have valid credentials to save
      if (isSocialLogin) {
        // Save social login credentials
        final userEmail = loginResult['user']['email'] ?? '';
        await DeviceStorage.setString('stored_username', userEmail);
        await DeviceStorage.setString(
          'stored_password',
          isAppleLogin ? 'APPLE_AUTH' : 'GOOGLE_AUTH',
        );
        await DeviceStorage.setString('access_token', _accessToken);
        await DeviceStorage.setString('auth_token', _accessToken);
        await DeviceStorage.setBool('auto_login_enabled', true);
        await DeviceStorage.setBool('is_google_login', isGoogleLogin);
        await DeviceStorage.setBool('is_apple_login', isAppleLogin);

        final userHas2FA = _flagIsEnabled(loginResult['user']?['has_2fa_enabled']);
        final user2FACode =
            loginResult['twoFactorCode'] ?? loginResult['user']?['twofa'];
        if (userHas2FA &&
            user2FACode != null &&
            user2FACode.toString().isNotEmpty) {
          await prefs.setBool('has_2fa_enabled', true);
          await prefs.setString('user_2fa_code', user2FACode.toString());
          setState(() {
            _has2FAEnabled = true;
            _user2FACode = user2FACode.toString();
          });
        } else {
          await prefs.setBool('has_2fa_enabled', false);
          await prefs.remove('user_2fa_code');
          setState(() {
            _has2FAEnabled = false;
            _user2FACode = null;
          });
        }
        debugPrint('💾 Social credentials saved successfully ($explicitProvider)');
      } else if (username.isNotEmpty && password.isNotEmpty) {
        await DeviceStorage.setString('stored_username', username);
        await DeviceStorage.setString('stored_password', password);
        await DeviceStorage.setString(
          'access_token',
          _accessToken,
        ); // Save access token for API calls
        await DeviceStorage.setString('auth_token', _accessToken);
        await DeviceStorage.setBool('auto_login_enabled', true);
        await DeviceStorage.setBool('is_google_login', false);
        await DeviceStorage.setBool('is_apple_login', false);
        debugPrint('💾 Credentials saved successfully');

        // Save 2FA data from login response
        if (loginResult['user'] != null) {
          debugPrint(
            '🔍 DEBUG: Checking 2FA data in loginResult: ${loginResult['user']}',
          );

            var userHas2FA = _flagIsEnabled(loginResult['user']['has_2fa_enabled']);
          var user2FACode = loginResult['user']['twofa'];

          debugPrint('🔍 DEBUG: userHas2FA=$userHas2FA, user2FACode=$user2FACode');

          if (userHas2FA &&
              user2FACode != null &&
              user2FACode.toString().isNotEmpty) {
            await prefs.setBool('has_2fa_enabled', true);
            await prefs.setString('user_2fa_code', user2FACode.toString());
            debugPrint(
              '💾 Saved 2FA data: has_2fa_enabled=true, user_2fa_code=$user2FACode',
            );

            setState(() {
              _has2FAEnabled = true;
              _user2FACode = user2FACode.toString();
            });
          } else {
            await prefs.setBool('has_2fa_enabled', false);
            await prefs.remove('user_2fa_code');
            debugPrint(
              '💾 Cleared 2FA data: userHas2FA=$userHas2FA, user2FACode=$user2FACode',
            );

            setState(() {
              _has2FAEnabled = false;
              _user2FACode = '';
            });
          }
        } else {
          debugPrint('🔍 DEBUG: No user data found in loginResult');
        }
      } else {
        debugPrint('⚠️ Empty credentials, skipping save');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to save credentials to SharedPreferences: $e');
      // Continue with login even if we can't save credentials
      // This is not a critical error
    }

    debugPrint('💾 Saved credentials for auto-login');
    debugPrint(
      '🔍 DEBUG: Saved access token: ${_accessToken.isNotEmpty ? "TOKEN_SAVED" : "TOKEN_EMPTY"}',
    );
    if (_accessToken.isNotEmpty) {
      debugPrint(
        '🔍 DEBUG: Saved token length: ${_accessToken.length}, first 20 chars: ${_accessToken.substring(0, _accessToken.length > 20 ? 20 : _accessToken.length)}...',
      );
    }

    //debugPrint(' Login successful, loading user data...');

    // Load real payment methods after successful login (with error handling)
    try {
      await _loadPaymentMethods();
    } catch (e) {
      debugPrint('⚠️ Failed to load payment methods: $e');
    }

    try {
      await _loadRealData();
    } catch (e) {
      debugPrint('⚠️ Failed to load real data: $e');
    }

    // Load cart count after login
    try {
      _loadCartCount();
    } catch (e) {
      debugPrint('⚠️ Failed to load cart count: $e');
    }

    // Reset orders future so Orders page reloads fresh after login
    _ordersFuture = null;

    // Load dismissed orders state for the current user only
    try {
      await _loadDismissedOrderIds(username: _userUsername);
    } catch (e) {
      debugPrint('⚠️ Failed to reload dismissed order IDs after login: $e');
    }

    // Load favorites after successful login
    Future.delayed(const Duration(milliseconds: 500), () {
      try {
        _loadFavoritesFromServer();
      } catch (e) {
        debugPrint('⚠️ Failed to load favorites: $e');
      }
    });

    // Clear mock data and load followed users after successful login
    Future.delayed(const Duration(seconds: 2), () {
      // Only load if not already loading and enough time has passed
      if (mounted && !_isLoadingFollowedUsers) {
        // Load from cache first (don't clear it!), then try to sync with server
        try {
          _loadFollowedUsersFromPrefs().then((_) {
            _loadFollowedUsersFromServer();
          });
        } catch (e) {
          debugPrint('⚠️ Failed to load followed users: $e');
        }
      }
    });

    // Clear controllers only after everything is saved
    _usernameController.clear();
    _passwordController.clear();
    _2faController.clear();

    if (mounted) {
      TopNotification.success(
        context,
        AppLocalizations.of(
          context,
        )!.loggedInAs(loginResult['user']['name'] ?? 'User'),
      );
    }
  }

  // 2FA login specifically for auto-login scenarios
  Future<void> _show2FALoginForAutoLogin() async {
    //debugPrint('🔐 Showing 2FA verification for auto-login');

    try {
      final storedUsername = await DeviceStorage.getString('stored_username');
      final storedPassword = await DeviceStorage.getString('stored_password');

      if (storedUsername == null || storedPassword == null) {
        //debugPrint(' No stored credentials found for auto-login 2FA');
        setState(() {
          // Show login screen if no credentials
        });
        return;
      }

      setState(() {
        _isLoading = true;
      });

      try {
        // Attempt login to get 2FA code from backend
        final response = await ApiService.login(storedUsername, storedPassword);

        setState(() {
          _isLoading = false;
        });

        if (response['success'] == true &&
            response['requiresTwoFactor'] == true) {
          // Show 2FA dialog for manual verification - no auto-submit for security
          _show2FALoginDialog(response);
        } else if (response['success'] == true) {
          // If somehow login succeeded without 2FA, complete it
          await _completeLogin(response);
        } else {
          // Login failed - show error and go to login screen
          //debugPrint(' Auto-login failed: ${response['message']}');
          setState(() {
            // Show login screen on failure
          });
          TopNotification.error(
            context,
            AppLocalizations.of(context)!.autoLoginFailed,
          );
        }
      } catch (e) {
        setState(() {
          _isLoading = false;
        });
        //debugPrint(' Error during auto-login 2FA: $e');
        TopNotification.error(
          context,
          AppLocalizations.of(context)!.connectionError,
        );
      }
    } catch (e) {
      debugPrint(
        '⚠️ Failed to access SharedPreferences in _show2FALoginForAutoLogin: $e',
      );
      // If SharedPreferences fails, just show login screen
      setState(() {
        // Show login screen
      });
    }
  }

  void _showToken2FAAutoLoginDialog() {
    final expectedCode = (_user2FACode ?? '').toString();
    final token = (_pendingAutoLoginToken ?? '').toString();
    if (expectedCode.isEmpty || token.isEmpty) {
      _show2FALoginForAutoLogin();
      return;
    }

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      useRootNavigator: true,
      isDismissible: false,
      maxHeight: 500,
      child: SecurityVerificationModal(
        expectedCode: expectedCode,
        isAutoLogin: true,
        onSubmit: (String code) async {
          final normalizedInput = code.replaceAll('-', '').trim();
          final normalizedExpected = expectedCode.replaceAll('-', '').trim();
          if (normalizedInput != normalizedExpected) {
            HapticFeedback.heavyImpact();
            if (mounted) {
              TopNotification.error(
                context,
                AppLocalizations.of(context)!.invalid2FACode,
              );
            }
            return;
          }

          final rootNav = Navigator.of(context, rootNavigator: true);
          if (rootNav.canPop()) {
            rootNav.pop();
          }
          await _performTokenAutoLogin(
            token,
            authProvider: _pendingAutoLoginProvider,
          );
        },
        onCancel: () {
          final rootNav = Navigator.of(context, rootNavigator: true);
          if (rootNav.canPop()) {
            rootNav.pop();
          }
        },
      ),
    );
  }

  Future<void> _show2FALogin() async {
    // First, attempt to validate credentials without completing login
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      TopNotification.error(
        context,
        AppLocalizations.of(context)!.enterUsernamePassword,
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Attempt login to get 2FA requirement
      final response = await ApiService.login(
        _usernameController.text,
        _passwordController.text,
      );

      setState(() {
        _isLoading = false;
      });

      if (response['success'] == true &&
          response['requiresTwoFactor'] == true) {
        // Show 2FA dialog if 2FA is required
        _show2FALoginDialog(response);
      } else if (response['success'] == true) {
        // If login successful without 2FA, just complete login
        await _completeLogin(response);
      } else {
        // Show error message
        TopNotification.error(
          context,
          response['message'] ?? AppLocalizations.of(context)!.loginFailed,
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      TopNotification.error(
        context,
        AppLocalizations.of(context)!.errorDuringLogin(e.toString()),
      );
    }
  }

  void _show2FALoginDialog(Map<String, dynamic> loginResult) {
    //debugPrint('🔍 DEBUG: _show2FALoginDialog called, setting tempLoginResult');
    //debugPrint('🔍 DEBUG: loginResult received: $loginResult');

    setState(() {
      _tempLoginResult = loginResult;
      _isLoading = false; // Ensure loading state is cleared
    });

    // Extract the 2FA code from the backend response
    String? backendCode =
        loginResult['twoFactorCode'] ?? loginResult['user']?['twofa'];
    //debugPrint('🔍 DEBUG: Backend 2FA code: $backendCode');
    //debugPrint('🔍 DEBUG: About to show modal bottom sheet');

    // Use post frame callback to ensure the widget tree is ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        //debugPrint('🔍 DEBUG: Actually showing modal now');
        // Show the new TwoFactorModal instead of the old screen
        TradeRepublicBottomSheet.show(
              context: context,
              showDragHandle: true,
              useRootNavigator: true,
              isDismissible: false, // Prevent closing during login process
              maxHeight: 500,
              child: SecurityVerificationModal(
                expectedCode: backendCode, // Pass expected code for reference
                isAutoLogin: true, // Indicate this is for auto-login
                onSubmit: (String code) async {
                  //debugPrint('🔍 DEBUG: Manual code entered: $code');
                  final rootNav = Navigator.of(context, rootNavigator: true);
                  if (rootNav.canPop()) {
                    rootNav.pop();
                  }
                  await _authenticate2FA(code);
                },
                onCancel: () {
                  final rootNav = Navigator.of(context, rootNavigator: true);
                  if (rootNav.canPop()) {
                    rootNav.pop();
                  }
                  // Cancel 2FA: Go to app but stay logged out
                  //debugPrint('🚫 2FA cancelled by user - staying logged out');
                  setState(() {
                    _tempLoginResult = null;
                    _isLoggedIn = false; // Ensure user stays logged out
                    _userEmail = '';
                    _userName = '';
                    _accessToken = '';
                    _currentUser = null;
                    _profileImageSrc = null;
                    _isLoading = false;
                  });

                  // Clear any stored auto-login credentials to prevent auto-login next time
                  _clearStoredCredentials();

                  // Show message that user cancelled login
                  TopNotification.error(
                    context,
                    AppLocalizations.of(context)!.loginCancelled,
                  );
                },
              ),
            )
            .then((value) {
              //debugPrint('🔍 DEBUG: Modal closed');
            })
            .catchError((error) {
              //debugPrint(' DEBUG: Error showing modal: $error');
            });
      } else {
        //debugPrint(' DEBUG: Widget not mounted, cannot show modal');
      }
    });
  }

  // Animation functions removed to prevent lag

  // 2FA and Biometric Authentication Methods
  Future<void> _checkBiometricAvailability() async {
    try {
      //debugPrint('🔍 Checking biometric availability...');
      final isAvailable = await _localAuth.canCheckBiometrics;
      final availableBiometrics = await _localAuth.getAvailableBiometrics();

      setState(() {
        _biometricAvailable = isAvailable && availableBiometrics.isNotEmpty;
      });

      //debugPrint('🔒 Biometric check results:');
      //debugPrint('   - canCheckBiometrics: $isAvailable');
      //debugPrint('   - availableBiometrics: $availableBiometrics');
      //debugPrint('   - _biometricAvailable: $_biometricAvailable');
    } catch (e) {
      //debugPrint('❌ Error checking biometric availability: $e');
      setState(() {
        _biometricAvailable = false;
      });
    }
  }

  Future<void> _loadStoredCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedUsername = await DeviceStorage.getString('stored_username');
      final storedPassword = await DeviceStorage.getString('stored_password');
      final stored2FACode = prefs.getString('user_2fa_code');
      final biometricEnabled = await DeviceStorage.getBool('biometric_enabled');
      final has2FA = prefs.getBool('has_2fa_enabled') ?? false;

      setState(() {
        _user2FACode = stored2FACode;
        _biometricEnabled = biometricEnabled;
        _has2FAEnabled = has2FA;
      });

      if (storedUsername != null) {
        _usernameController.text = storedUsername;
      }
      if (storedPassword != null) {
        _passwordController.text = storedPassword;
      }

      //debugPrint('📱 Loaded stored credentials: username=$storedUsername, password=${storedPassword != null}, 2FA=${stored2FACode != null}, biometric=$biometricEnabled, autoLogin=$autoLoginEnabled');
    } catch (e) {
      //debugPrint(' Error loading stored credentials: $e');
    }
  }

  Future<void> _tryAutoLogin() async {
    debugPrint('🔄 Checking auto-login with device-specific storage...');

    final autoLoginEnabled = await DeviceStorage.getBool('auto_login_enabled');
    final storedUsername = await DeviceStorage.getString('stored_username');
    final storedPassword = await DeviceStorage.getString('stored_password');
    final biometricEnabled = await DeviceStorage.getBool('biometric_enabled');
    final isGoogleLogin = await DeviceStorage.getBool('is_google_login');
    final isAppleLogin = await DeviceStorage.getBool('is_apple_login');
    final storedAccessToken = await DeviceStorage.getString('access_token');
    final storedLegacyAuthToken = await DeviceStorage.getString('auth_token');
    final effectiveToken = (storedAccessToken != null && storedAccessToken.isNotEmpty)
      ? storedAccessToken
      : ((storedLegacyAuthToken != null && storedLegacyAuthToken.isNotEmpty)
          ? storedLegacyAuthToken
          : null);

    // Update local state to match DeviceStorage
    _biometricEnabled = biometricEnabled;

    debugPrint('📱 Device-specific auto-login data:');
    debugPrint('  Enabled: $autoLoginEnabled');
    debugPrint('  Username: $storedUsername');
    debugPrint('  Has password: ${storedPassword != null}');
    debugPrint('  Is Google: $isGoogleLogin');
    debugPrint('  Is Apple: $isAppleLogin');
    debugPrint('  Biometric: $biometricEnabled');
    debugPrint('  Has stored token: ${effectiveToken != null}');

    // Load stored token into ApiService memory for auto-login
    if (effectiveToken != null && effectiveToken.isNotEmpty) {
      debugPrint('🔄 Loading stored token into ApiService memory...');
      await ApiService.saveToken(
        effectiveToken,
      ); // Keep session for auto-login
      debugPrint('✅ Token loaded into memory');
    }

    if (autoLoginEnabled &&
        ((effectiveToken != null && effectiveToken.isNotEmpty) ||
            (storedUsername != null && storedPassword != null))) {
      debugPrint('🔐 Auto-login available, showing authentication choice...');
      setState(() {
        _pendingAutoLoginToken = effectiveToken;
        _pendingAutoLoginProvider = isAppleLogin
            ? 'apple'
            : (isGoogleLogin ? 'google' : null);
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isLoggedIn) {
          _showAutoLoginAuthChoice();
        }
      });
      return;
    } else {
      // No auto-login, show normal login screen
      debugPrint('ℹ️ Auto-login not available for this device');
      setState(() {
        // Authentication state management simplified to prevent lag
      });
    }
  }

  // Auto-login for any provider using stored JWT (no password/OTP prompt)
  Future<void> _performTokenAutoLogin(
    String accessToken, {
    String? authProvider,
  }) async {
    setState(() {
      _isLoading = true;
    });

    try {
      await ApiService.saveToken(accessToken);
      final profile = await ApiService.getUserProfile();

      if (profile == null || profile['user'] == null) {
        throw Exception('Session invalid');
      }

      final user = profile['user'] as Map<String, dynamic>;
      final syntheticLoginResult = {
        'success': true,
        'authProvider': authProvider,
        'accessToken': accessToken,
        'user': {
          ...user,
          'name':
              user['name'] ??
              '${user['firstname'] ?? ''} ${user['lastname'] ?? ''}'.trim(),
        },
      };

      await _completeLogin(syntheticLoginResult);
      if (mounted) {
        setState(() {
          _pendingAutoLoginToken = null;
          _pendingAutoLoginProvider = null;
        });
      }
    } catch (e) {
      debugPrint('❌ Token auto-login failed: $e');
      await DeviceStorage.remove('access_token');
      await DeviceStorage.setBool('auto_login_enabled', false);
      await DeviceStorage.setBool('is_google_login', false);
      await DeviceStorage.setBool('is_apple_login', false);
      setState(() {
        _isLoading = false;
        _pendingAutoLoginToken = null;
        _pendingAutoLoginProvider = null;
      });
    }
  }

  void _showAutoLoginAuthChoice() {
    //debugPrint('🎭 _showAutoLoginAuthChoice() called - showing authentication choice dialog');
    final isDark = Theme.of(context).brightness == Brightness.dark;
    TradeRepublicBottomSheet.show(
      context: context,
      useRootNavigator: true,
      isDismissible: false, // Prevent dismissing to force authentication
      enableDrag: false, // No drag for security
      showDragHandle: true,
      maxHeight: 450,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Row(
                children: [
                  Icon(
                    CupertinoIcons.person_fill,
                    color: isDark ? Colors.white : Colors.black,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context)!.chooseAuthMethod,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : Colors.black,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            Text(
              AppLocalizations.of(context)!.howWouldYouLikeToLogIn,
              style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 32),

            // Authentication Options
            Column(
              children: [
                // Biometric Option (if available)
                if (_biometricEnabled && _biometricAvailable)
                  TradeRepublicButton(
                    onPressed: () {
                      final rootNav = Navigator.of(
                        context,
                        rootNavigator: true,
                      );
                      if (rootNav.canPop()) {
                        rootNav.pop();
                      }
                      _performBiometricAutoLogin();
                    },
                    label: AppLocalizations.of(context)!.useBiometric,
                    icon: const Icon(CupertinoIcons.lock_fill),
                    width: double.infinity,
                    height: 56,
                  ),

                if (_biometricEnabled && _biometricAvailable)
                  const SizedBox(height: 16),

                // 2FA Option (if available)
                if (_has2FAEnabled)
                  TradeRepublicButton(
                    onPressed: () {
                      final rootNav = Navigator.of(
                        context,
                        rootNavigator: true,
                      );
                      if (rootNav.canPop()) {
                        rootNav.pop();
                      }
                      if ((_pendingAutoLoginToken ?? '').isNotEmpty &&
                          (_user2FACode ?? '').isNotEmpty) {
                        _showToken2FAAutoLoginDialog();
                      } else {
                        _show2FALoginForAutoLogin();
                      }
                    },
                    label: AppLocalizations.of(context)!.use2FACode,
                    icon: const Icon(CupertinoIcons.lock_shield),
                    width: double.infinity,
                    height: 56,
                  ),

                if (_has2FAEnabled) const SizedBox(height: 16),

                // Password Option (always available)
                TradeRepublicButton(
                  onPressed: () {
                    final rootNav = Navigator.of(context, rootNavigator: true);
                    if (rootNav.canPop()) {
                      rootNav.pop();
                    }
                    _showAutoLoginPasswordModal();
                  },
                  label: AppLocalizations.of(context)!.signInWithPassword,
                  icon: const Icon(CupertinoIcons.lock),
                  isSecondary: true,
                  width: double.infinity,
                  height: 56,
                ),
              ],
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  /// Password bottom sheet shown when the user chooses "Sign in with password"
  /// in the auto-login choice sheet.  Cancelling logs the user out completely.
  void _showAutoLoginPasswordModal() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final passwordController = TextEditingController();
    bool isPasswordVisible = false;
    bool isLoggingIn = false;

    // Helper: perform a full logout without confirmation
    void doLogout() {
      _usernameController.clear();
      _passwordController.clear();
      _clearStoredCredentials().then((_) {
        if (mounted) {
          setState(() {
            _isLoggedIn = false;
            _userEmail = '';
            _userName = '';
            _userUsername = '';
            _accessToken = '';
            _has2FAEnabled = false;
            _user2FACode = null;
            _biometricEnabled = false;
            _currentUser = null;
            _profileImageSrc = null;
            _currentPage = 0;
            _tabIndex = 0;
          });
          _pageController.jumpToPage(0);
        }
      });
    }

    TradeRepublicBottomSheet.show(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      isDismissible: false,
      enableDrag: false,
      maxHeight: 380,
      child: StatefulBuilder(
        builder: (ctx, setModalState) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                child: Row(
                  children: [
                    Icon(
                      CupertinoIcons.lock_fill,
                      color: isDark ? Colors.white : Colors.black,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        AppLocalizations.of(context)!.signInWithPassword,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : Colors.black,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Stored username label
              FutureBuilder<String?>(
                future: DeviceStorage.getString('stored_username'),
                builder: (_, snap) {
                  final username = snap.data ?? '';
                  if (username.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      username,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: (isDark ? Colors.white : Colors.black)
                            .withOpacity(0.55),
                      ),
                    ),
                  );
                },
              ),

              // Password field
              StatefulBuilder(
                builder: (_, setFieldState) => TradeRepublicTextField(
                  controller: passwordController,
                  hintText:
                      AppLocalizations.of(context)?.password ?? 'Password',
                  obscureText: !isPasswordVisible,
                  keyboardType: TextInputType.visiblePassword,
                  suffixIcon: GestureDetector(
                    onTap: () => setFieldState(
                      () => isPasswordVisible = !isPasswordVisible,
                    ),
                    child: Icon(
                      isPasswordVisible
                          ? CupertinoIcons.eye_slash
                          : CupertinoIcons.eye,
                      size: 20,
                      color: (isDark ? Colors.white : Colors.black).withOpacity(
                        0.4,
                      ),
                    ),
                  ),
                  onSubmitted: (_) async {
                    if (isLoggingIn) return;
                    setModalState(() => isLoggingIn = true);
                    try {
                      final storedUsername =
                          await DeviceStorage.getString('stored_username') ??
                          '';
                      final loginResult = await ApiService.login(
                        storedUsername,
                        passwordController.text.trim(),
                      );
                      if (loginResult['success'] == true) {
                        await _completeLogin(loginResult);
                        if (ctx.mounted) Navigator.of(ctx).pop();
                      } else {
                        throw Exception(
                          loginResult['message'] ?? 'Login failed',
                        );
                      }
                    } catch (e) {
                      if (ctx.mounted) {
                        setModalState(() => isLoggingIn = false);
                        TopNotification.error(
                          context,
                          e.toString().replaceAll('Exception: ', ''),
                        );
                      }
                    }
                  },
                ),
              ),

              const SizedBox(height: 20),

              // Sign in button
              TradeRepublicButton(
                label: AppLocalizations.of(context)!.signIn,
                isLoading: isLoggingIn,
                width: double.infinity,
                onPressed: isLoggingIn
                    ? null
                    : () async {
                        if (passwordController.text.trim().isEmpty) {
                          TopNotification.error(
                            context,
                            AppLocalizations.of(context)!.enterUsernamePassword,
                          );
                          return;
                        }
                        setModalState(() => isLoggingIn = true);
                        try {
                          final storedUsername =
                              await DeviceStorage.getString(
                                'stored_username',
                              ) ??
                              '';
                          final loginResult = await ApiService.login(
                            storedUsername,
                            passwordController.text.trim(),
                          );
                          if (loginResult['success'] == true) {
                            await _completeLogin(loginResult);
                            if (ctx.mounted) Navigator.of(ctx).pop();
                          } else {
                            throw Exception(
                              loginResult['message'] ?? 'Login failed',
                            );
                          }
                        } catch (e) {
                          if (ctx.mounted) {
                            setModalState(() => isLoggingIn = false);
                            TopNotification.error(
                              context,
                              e.toString().replaceAll('Exception: ', ''),
                            );
                          }
                        }
                      },
              ),

              const SizedBox(height: 12),

              // Cancel = logout
              TradeRepublicButton(
                label: AppLocalizations.of(context)!.cancel,
                isSecondary: true,
                isDestructive: true,
                width: double.infinity,
                onPressed: () {
                  Navigator.of(ctx).pop();
                  doLogout();
                },
              ),
            ],
          );
        },
      ),
    ).whenComplete(() {
      // If sheet dismissed without completing login, log out
      if (!_isLoggedIn) doLogout();
    });
  }

  Future<void> _performBiometricAutoLogin() async {
    try {
      //debugPrint('🔐 Starting biometric auto-login...');

      final bool didAuthenticate = await _localAuth.authenticate(
        localizedReason: AppLocalizations.of(
          context,
        )!.authenticateToAccessYourAccount,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );

      if (didAuthenticate) {
        //debugPrint(' Biometric authentication successful, proceeding with direct login');
        final token = (_pendingAutoLoginToken ?? '').toString();
        if (token.isNotEmpty) {
          await _performTokenAutoLogin(
            token,
            authProvider: _pendingAutoLoginProvider,
          );
        } else {
          // Biometric success means user is already authenticated
          // Skip 2FA and complete login directly
          await _performBiometricCompleteLogin();
        }
      } else {
        //debugPrint(' Biometric authentication failed, showing login screen');
        // If biometric fails and 2FA is available, offer 2FA as fallback
        final prefs = await SharedPreferences.getInstance();
        final has2FA = prefs.getBool('has_2fa_enabled') ?? false;

        if (has2FA) {
          //debugPrint('🔐 Biometric failed, falling back to 2FA verification');
          await _show2FALoginForAutoLogin();
        } else {
          setState(() {
            // Authentication state management simplified to prevent lag
          });
        }
      }
    } catch (e) {
      //debugPrint(' Biometric auto-login error: $e');
      // Fallback to 2FA if available, otherwise show login screen
      final prefs = await SharedPreferences.getInstance();
      final has2FA = prefs.getBool('has_2fa_enabled') ?? false;

      if (has2FA) {
        //debugPrint('🔐 Biometric error, falling back to 2FA verification');
        await _show2FALoginForAutoLogin();
      } else {
        setState(() {
          // Authentication state management simplified
        });
      }
    }
  }

  void _showAuthMethodChoice() {
    //debugPrint('🎭 _showAuthMethodChoice() called - showing authentication choice dialog');
    final isDark = Theme.of(context).brightness == Brightness.dark;
    TradeRepublicBottomSheet.show(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      maxHeight: 400,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Row(
                children: [
                  Icon(
                    CupertinoIcons.person_fill,
                    color: isDark ? Colors.white : Colors.black,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context)!.chooseAuthMethod,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : Colors.black,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context)!.howToSignIn,
              style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.grey[300] : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 32),

            // Biometric Option (if available and enabled)
            if (_biometricAvailable && _biometricEnabled) ...[
              _buildAuthChoiceButton(
                context: context,
                title: AppLocalizations.of(context)!.useBiometric,
                subtitle: AppLocalizations.of(context)!.fingerprintOrFaceId,
                icon: CupertinoIcons.lock_fill,
                color: Colors.black,
                onTap: () async {
                  Navigator.of(context).pop();
                  await _authenticateWithBiometric();
                },
              ),
              const SizedBox(height: 8),
            ],

            // 2FA Option
            _buildAuthChoiceButton(
              context: context,
              title: AppLocalizations.of(context)!.use2FACode,
              subtitle: AppLocalizations.of(context)!.enterAuthCode,
              icon: CupertinoIcons.lock_shield,
              color: Colors.green,
              onTap: () async {
                Navigator.of(context).pop();
                await _show2FALogin();
              },
            ),

            // Manual Login Option
            _buildAuthChoiceButton(
              context: context,
              title: AppLocalizations.of(context)!.manualLogin,
              subtitle: AppLocalizations.of(context)!.signInSubtitle,
              icon: CupertinoIcons.arrow_right_square,
              color: Colors.orange,
              onTap: () {
                Navigator.of(context).pop();
                setState(() {
                  // Authentication state management simplified
                });
              },
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildAuthChoiceButton({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return TradeRepublicListTile.navigation(
      title: title,
      subtitle: subtitle,
      leading: Icon(icon, color: color, size: 20),
      onTap: onTap,
    );
  }

  Future<void> _performBiometricCompleteLogin() async {
    final storedUsername = await DeviceStorage.getString('stored_username');
    final storedPassword = await DeviceStorage.getString('stored_password');

    if (storedUsername != null && storedPassword != null) {
      //debugPrint('🔄 Performing biometric complete login for: $storedUsername');
      debugPrint('🔍 DEBUG: Using real backend API');

      // Set the controllers with stored values for auto-login
      _usernameController.text = storedUsername;
      _passwordController.text = storedPassword;

      try {
        // Try real login via API - works with both email and username
        //debugPrint('🌐 Calling ApiService.login with credentials: $storedUsername');
        final loginResult = await ApiService.login(
          storedUsername,
          storedPassword,
        );
        //debugPrint('🔍 DEBUG: Login API response: $loginResult');

        if (loginResult['success']) {
          // Check if this is a 2FA response (no complete user data yet)
          if (loginResult['requiresTwoFactor'] == true) {
            //debugPrint('✅ Biometric login: 2FA required but biometric bypasses it - auto-verifying with stored code');

            // For biometric login, automatically verify with the expected 2FA code
            final expectedCode = loginResult['twoFactorCode'];
            final username = loginResult['username'];

            if (expectedCode != null && username != null) {
              //debugPrint('🔐 Auto-verifying 2FA with code: $expectedCode for user: $username');

              try {
                final verifyResult = await ApiService.verify2FA(
                  username,
                  expectedCode,
                );
                //debugPrint('🔍 DEBUG: 2FA verify result: $verifyResult');

                if (verifyResult['success']) {
                  //debugPrint('✅ Biometric login: 2FA auto-verification successful');
                  await _completeLogin(verifyResult);
                } else {
                  //debugPrint('❌ Biometric login: 2FA auto-verification failed');
                  throw Exception(
                    '2FA verification failed: ${verifyResult['message']}',
                  );
                }
              } catch (e) {
                //debugPrint('❌ Biometric login: 2FA verify error: $e');
                throw Exception('2FA verification error: $e');
              }
            } else {
              throw Exception('Missing 2FA code or username in login response');
            }
          } else {
            // Regular login without 2FA
            //debugPrint('✅ Biometric login: Completing login directly (no 2FA required)');
            //debugPrint('🔍 DEBUG: User data received: ${loginResult['user']}');

            await _completeLogin(loginResult);
          }
        } else {
          //debugPrint('❌ Biometric login failed: Server returned success=false');
          //debugPrint('🔍 DEBUG: Full response: $loginResult');
          // Clear stored credentials and stay logged out
          await _clearStoredCredentials();
          if (mounted) {
            TopNotification.error(
              context,
              AppLocalizations.of(context)!.biometricLoginFailedManual,
            );
          }
        }
      } catch (e) {
        //debugPrint(' Biometric login error: $e');
        // Clear stored credentials and stay logged out
        await _clearStoredCredentials();
        if (mounted) {
          TopNotification.error(
            context,
            AppLocalizations.of(
              context,
            )!.biometricLoginFailedWithError(e.toString()),
          );
        }
      }
    } else {
      //debugPrint(' Missing stored credentials for biometric login');
    }
  }

  Future<void> _performAutoLogin() async {
    final storedUsername = await DeviceStorage.getString('stored_username');
    final storedPassword = await DeviceStorage.getString('stored_password');

    if (storedUsername != null && storedPassword != null) {
      //debugPrint('🔄 Performing auto-login for: $storedUsername');

      // Set the controllers with stored values for auto-login
      _usernameController.text = storedUsername;
      _passwordController.text = storedPassword;

      try {
        // Try real login via API
        final loginResult = await ApiService.login(
          storedUsername,
          storedPassword,
        );

        if (loginResult['success']) {
          // Check if 2FA is required - look for requiresTwoFactor
          var userHas2FA = loginResult['requiresTwoFactor'] == true;
          var user2FACode = loginResult['twoFactorCode'];

          // Also check in user data if available
          if (loginResult['user'] != null) {
            userHas2FA =
                userHas2FA ||
                loginResult['user']['has_2fa_enabled'] == true ||
                loginResult['user']['has_2fa_enabled'] == 1;
            user2FACode = user2FACode ?? loginResult['user']['twofa'];
          }

          //debugPrint('🔍 Auto-login: userHas2FA=$userHas2FA, user2FACode=$user2FACode');

          if (userHas2FA && user2FACode != null) {
            //debugPrint('🔐 Auto-login: 2FA required, showing 2FA verification');

            // Always require 2FA verification for security - never auto-complete
            setState(() {
              _user2FACode = user2FACode;
              _has2FAEnabled = true;
              _tempLoginResult = loginResult;
            });

            // Show 2FA dialog for manual entry - force user interaction
            _show2FALoginDialog(loginResult);
            return; // Stop here and wait for user input
          } else if (!userHas2FA) {
            // Direct login success without 2FA
            // Auto-login completed successfully for non-2FA users
            //debugPrint('✅ Auto-login: Direct login successful for non-2FA user');

            // Use _completeLogin to properly set all user data
            await _completeLogin(loginResult);

            // Load user data and payment methods separately
            await _loadRealData();
          } else {
            //debugPrint(' Auto-login: 2FA required but no 2FA code available');
            await _clearStoredCredentials();
          }
        } else {
          //debugPrint(' Auto-login failed: Invalid credentials');
          // Clear stored credentials and stay logged out
          await _clearStoredCredentials();
          if (mounted) {
            TopNotification.error(
              context,
              AppLocalizations.of(context)!.autoLoginFailed,
            );
          }
        }
      } catch (e) {
        //debugPrint(' Auto-login error: $e');
        // Clear stored credentials and stay logged out
        await _clearStoredCredentials();
        if (mounted) {
          TopNotification.error(
            context,
            AppLocalizations.of(
              context,
            )!.autoLoginFailedWithError(e.toString()),
          );
        }
      }
    } else {
      //debugPrint(' Missing stored credentials for auto-login');
      // Just stay logged out, no action needed since we removed the auth screen
    }
  }

  Future<void> _authenticateWithBiometric() async {
    try {
      final isAuthenticated = await _localAuth.authenticate(
        localizedReason: AppLocalizations.of(
          context,
        )!.authenticateToAccessYourCultiooAccount,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );

      if (isAuthenticated) {
        //debugPrint(' Biometric authentication successful');
        await _performAutoLogin();
      } else {
        //debugPrint(' Biometric authentication failed');
        setState(() {
          // Authentication state management simplified
        });
      }
    } catch (e) {
      //debugPrint(' Biometric authentication error: $e');
      setState(() {
        // Authentication state management simplified
      });
    }
  }

  Future<void> _authenticate2FA(String enteredCode) async {
    // Prevent multiple calls
    if (_isLoading) return;

    //debugPrint('🔍 DEBUG: _authenticate2FA called with tempLoginResult: ${_tempLoginResult != null ? "present" : "null"}');

    // Store tempLoginResult locally to prevent race conditions
    final localLoginResult = _tempLoginResult;

    setState(() {
      _isLoading = true;
    });

    try {
      // Get username from login result
      String? username = localLoginResult?['username'];
      username ??= localLoginResult?['user']?['username']?.toString();
      if (username == null) {
        throw Exception('Username not found in login result');
      }

      //debugPrint('🔍 Verifying 2FA code via backend for user: $username');

      String cleanEnteredCode = enteredCode.replaceAll('-', '');

      // Call backend /verify-2fa API to get complete user data
      final verifyResult = await ApiService.verify2FA(
        username,
        cleanEnteredCode,
      );

      if (verifyResult['success']) {
        //debugPrint(' 2FA authentication successful via backend');

        // Wait for UI feedback
        await Future.delayed(const Duration(milliseconds: 800));

        final isSocialLogin =
          _isSocialAuthProvider(localLoginResult?['authProvider']?.toString());
        final verifyResultMap = Map<String, dynamic>.from(verifyResult);
        if (isSocialLogin) {
          verifyResultMap['authProvider'] = localLoginResult?['authProvider'];
          if (localLoginResult?['twoFactorCode'] != null) {
            verifyResultMap['twoFactorCode'] =
                localLoginResult?['twoFactorCode'];
          }
          if (verifyResultMap['user'] is Map<String, dynamic>) {
            (verifyResultMap['user'] as Map<String, dynamic>)['has_2fa_enabled'] =
                true;
          }
        }

        // 2FA passed — complete login directly
        final userEmail =
            (verifyResultMap['user']?['email'] ?? '').toString();
        final userName =
            (verifyResultMap['user']?['username'] ?? username).toString();
        setState(() {
          _tempLoginResult = verifyResultMap;
          _isLoading = false;
        });

        await _completeLogin(verifyResultMap);
      } else {
        throw Exception(
          verifyResult['message'] ??
              AppLocalizations.of(context)!.invalid2FACode,
        );
      }
    } catch (e) {
      //debugPrint(' 2FA verification failed: $e');

      // Set incorrect state and show red effect
      setState(() {
        _isLoading = false;
      });

      // Reset after showing red effect
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted) {
          setState(() {
            // Reset UI state
          });
        }
      });

      // Shake animation for incorrect PIN
      if (mounted) {
        HapticFeedback.heavyImpact();
        _showBottomMessage(
          'Authentication failed: ${e.toString().replaceAll('Exception: ', '')}',
          isError: true,
        );
      }
    }
  }

  Future<void> _toggleBiometric() async {
    //debugPrint('🔍 Toggling biometric: available=$_biometricAvailable, enabled=$_biometricEnabled');

    if (!_biometricAvailable) {
      //debugPrint(' Biometric not available on this device');
      TopNotification.error(
        context,
        AppLocalizations.of(
          context,
        )!.biometricAuthenticationIsNotAvailableOnThis,
      );
      return;
    }

    // Show test dialog if enabling
    if (!_biometricEnabled) {
      //debugPrint('🔒 Attempting to enable biometric authentication...');
      await _showBiometricTestModal();
    } else {
      // If disabling, just toggle off
      //debugPrint('🔓 Disabling biometric authentication...');
      await _disableBiometric();
    }
  }

  Future<void> _showBiometricTestModal() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    await TradeRepublicBottomSheet.show(
      context: context,
      useRootNavigator: true,
      isDismissible: false,
      maxHeight: MediaQuery.of(context).size.height * 0.6,
      showDragHandle: true,
      child: Column(
        children: [
          // Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                children: [
                  // Header
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          AppLocalizations.of(context)!.enableBiometricLogin,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF1C1C1E),
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                      TradeRepublicButton(
                        icon: Icon(CupertinoIcons.xmark, size: 18),
                        isSecondary: true,
                        width: 44,
                        height: 44,
                        padding: EdgeInsets.zero,
                        borderRadius: BorderRadius.circular(25),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  Text(
                    'Let\'s test your biometric authentication to make sure it works correctly.',
                    style: TextStyle(
                      fontSize: 16,
                      color: isDark
                          ? Colors.white.withOpacity(0.7)
                          : Colors.black.withOpacity(0.6),
                      height: 1.4,
                    ),
                  ),

                  const SizedBox(height: 40),

                  // Biometric icon
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                      borderRadius: BorderRadius.circular(60),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withOpacity(0.1)
                            : Colors.black.withOpacity(0.05),
                        width: 1,
                      ),
                    ),
                    child: Icon(
                      CupertinoIcons.lock_fill,
                      size: 60,
                      color: isDark
                          ? Colors.white.withOpacity(0.8)
                          : Colors.black.withOpacity(0.7),
                    ),
                  ),

                  const SizedBox(height: 32),

                  Text(
                    AppLocalizations.of(context)!.touchSensorTest,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: isDark
                          ? Colors.white.withOpacity(0.8)
                          : Colors.black.withOpacity(0.8),
                      height: 1.4,
                    ),
                  ),

                  const Spacer(),

                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: TradeRepublicButton(
                          onPressed: () => Navigator.of(context).pop(),
                          label: AppLocalizations.of(context)!.cancel,
                          isSecondary: true,
                          height: 56,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TradeRepublicButton(
                          onPressed: () async {
                            Navigator.of(context).pop();
                            await _testBiometricAuthentication();
                          },
                          label: AppLocalizations.of(context)!.testNow,
                          height: 56,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _testBiometricAuthentication() async {
    try {
      //debugPrint('🔍 Testing biometric authentication...');

      // First check if biometrics are still available
      final isAvailable = await _localAuth.canCheckBiometrics;
      final availableBiometrics = await _localAuth.getAvailableBiometrics();

      if (!isAvailable || availableBiometrics.isEmpty) {
        //debugPrint(' Biometrics not available during test');
        TopNotification.error(
          context,
          AppLocalizations.of(
            context,
          )!.biometricAuthenticationIsNotAvailableOnThis,
        );
        return;
      }

      //debugPrint('🔍 Available biometrics: $availableBiometrics');

      final isAuthenticated = await _localAuth.authenticate(
        localizedReason: AppLocalizations.of(
          context,
        )!.testBiometricAuthenticationForCultioo,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );

      if (isAuthenticated) {
        //debugPrint(' Biometric test successful');
        // Test successful - enable biometric
        await _enableBiometric();
      } else {
        //debugPrint(' Biometric test failed or cancelled');
        TopNotification.error(
          context,
          AppLocalizations.of(context)!.biometricTestCancelledOrFailed,
        );
      }
    } catch (e) {
      //debugPrint(' Error testing biometric: $e');

      String errorMessage = AppLocalizations.of(
        context,
      )!.anErrorOccurredDuringBiometricTest;
      if (e.toString().contains('no_fragment_activity')) {
        errorMessage = AppLocalizations.of(
          context,
        )!.biometricAuthenticationRequiresUpdatedAppConf;
      } else if (e.toString().contains('not_available')) {
        errorMessage = AppLocalizations.of(
          context,
        )!.biometricAuthenticationIsNotAvailableOnThis;
      } else if (e.toString().contains('not_enrolled')) {
        errorMessage = AppLocalizations.of(context)!.noBiometricEnrolled;
      }

      TopNotification.error(context, errorMessage);
    }
  }

  Future<void> _enableBiometric() async {
    try {
      //debugPrint('🔒 Enabling biometric authentication...');
      final prefs = await SharedPreferences.getInstance();

      // Save biometric setting locally
      await DeviceStorage.setBool('biometric_enabled', true);

      // If we have login credentials, save them for auto-login
      final storedUsername = await DeviceStorage.getString('stored_username');
      if (storedUsername != null) {
        //debugPrint('🔒 Biometric enabled for existing user: $storedUsername');
      } else if (_isLoggedIn) {
        // Save current login for future auto-login
        await DeviceStorage.setString(
          'stored_username',
          _userEmail.isNotEmpty ? _userEmail : _userName,
        );
        await DeviceStorage.setBool('auto_login_enabled', true);
        //debugPrint('🔒 Saved current login for biometric auto-login');
      }

      // Update database if user is logged in
      if (_isLoggedIn && storedUsername != null) {
        try {
          await ApiService.updateUserSettings({'biometric_enabled': true});
          //debugPrint(' Updated biometric setting in database');
        } catch (e) {
          //debugPrint('⚠️ Could not update database, saved locally only: $e');
        }
      }

      setState(() {
        _biometricEnabled = true;
      });

      TopNotification.success(
        context,
        AppLocalizations.of(context)!.biometricAuthenticationEnabled,
      );

      //debugPrint(' Biometric authentication enabled');
    } catch (e) {
      //debugPrint(' Error enabling biometric: $e');
      TopNotification.error(
        context,
        AppLocalizations.of(context)!.errorEnablingBiometric,
      );
    }
  }

  Future<void> _disableBiometric() async {
    try {
      //debugPrint('🔓 Disabling biometric authentication...');
      final prefs = await SharedPreferences.getInstance();
      await DeviceStorage.setBool('biometric_enabled', false);

      // Update database if user is logged in
      final storedUsername = await DeviceStorage.getString('stored_username');
      if (_isLoggedIn && storedUsername != null) {
        try {
          await ApiService.updateUserSettings({'biometric_enabled': false});
          //debugPrint(' Updated biometric setting in database');
        } catch (e) {
          //debugPrint('⚠️ Could not update database, saved locally only: $e');
        }
      }

      setState(() {
        _biometricEnabled = false;
      });

      TopNotification.success(
        context,
        AppLocalizations.of(context)!.biometricAuthenticationDisabled,
      );

      //debugPrint(' Biometric authentication disabled');
    } catch (e) {
      //debugPrint(' Error disabling biometric: $e');
      TopNotification.error(
        context,
        AppLocalizations.of(context)!.errorDisablingBiometric,
      );
    }
  }

  // Removed _showModernInfo method to prevent lag

  // Removed _show2FASettings method to prevent lag

  Future<void> _disable2FA() async {
    //debugPrint('🚫 Starting 2FA disable process...');

    try {
      setState(() {
        _isLoading = true;
      });

      final prefs = await SharedPreferences.getInstance();

      // Call backend API to disable 2FA
      final response = await ApiService.disable2FA();

      if (response['success']) {
        //debugPrint(' 2FA successfully disabled via backend');

        // Update local SharedPreferences
        await prefs.setBool('has_2fa_enabled', false);
        await prefs.remove('user_2fa_code');
        await prefs.remove('two_factor_code');

        // Update local state
        setState(() {
          _has2FAEnabled = false;
          _user2FACode = null;
          _isLoading = false;
        });

        // Close any modal if open
        Navigator.of(context).pop();

        // Show success notification
        TopNotification.success(
          context,
          AppLocalizations.of(context)!.twoFADisabled,
        );
      } else {
        throw Exception(
          response['message'] ??
              AppLocalizations.of(context)!.errorDisabling2FA,
        );
      }
    } catch (e) {
      //debugPrint(' Failed to disable 2FA: $e');

      setState(() {
        _isLoading = false;
      });

      // Show error message with the _showInfo method
      _showInfo(
        '${AppLocalizations.of(context)!.errorDisabling2FA}: ${e.toString().replaceAll('Exception: ', '')}',
      );
    }
  }

  // Email Verification Modal
  void _showEmailVerification(String email) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final verificationCodeController = TextEditingController();
    bool isVerifying = false;
    bool isResending = false;

    TradeRepublicBottomSheet.show(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      maxHeight: 500,
      child: StatefulBuilder(
        builder: (context, setModalState) => Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Row(
                children: [
                  Icon(
                    CupertinoIcons.envelope_fill,
                    color: isDark ? Colors.white : Colors.black,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context)!.verifyEmail,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : Colors.black,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Content
            Expanded(
              child: ListView(
                children: [
                  // Information text
                  Text(
                    AppLocalizations.of(context)!.verificationSentTo,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: isDark
                          ? Colors.white.withOpacity(0.6)
                          : Colors.black.withOpacity(0.6),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    email,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Verification code input
                  TradeRepublicTextField.code(
                    controller: verificationCodeController,
                    hintText: '_ _ _ _ _ _ _ _',
                    maxLength: 8,

                    onChanged: (value) async {
                      // Automatische Verifikation wenn 8 Ziffern eingegeben wurden
                      if (value.length == 8 && !isVerifying) {
                        setModalState(() {
                          isVerifying = true;
                        });

                        try {
                          final result = await ApiService.verifyEmail(
                            email: email,
                            code: value.trim(),
                          );

                          if (result['success']) {
                            if (context.mounted) {
                              Navigator.of(context).pop();
                              TopNotification.success(
                                context,
                                AppLocalizations.of(
                                  context,
                                )!.accountCreatedCanSignIn,
                              );
                            }
                          } else {
                            throw Exception(
                              result['message'] ??
                                  AppLocalizations.of(
                                    context,
                                  )!.verificationFailed,
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            setModalState(() {
                              isVerifying = false;
                            });
                            TopNotification.error(
                              context,
                              e.toString().replaceAll('Exception: ', ''),
                            );
                          }
                        }
                      }
                    },
                  ),

                  const SizedBox(height: 16),

                  // Resend code button
                  TradeRepublicButton(
                    label: AppLocalizations.of(context)!.resendCode,
                    isSecondary: true,
                    isLoading: isResending,
                    width: double.infinity,
                    onPressed: (isResending || isVerifying)
                        ? null
                        : () async {
                            setModalState(() => isResending = true);
                            try {
                              final result =
                                  await ApiService.resendVerificationCode(
                                    email,
                                  );
                              if (context.mounted) {
                                if (result['success'] == true) {
                                  TopNotification.success(
                                    context,
                                    AppLocalizations.of(
                                      context,
                                    )!.verificationCodeResent,
                                  );
                                } else {
                                  TopNotification.error(
                                    context,
                                    result['message'] ??
                                        AppLocalizations.of(
                                          context,
                                        )!.verificationFailed,
                                  );
                                }
                              }
                            } catch (e) {
                              if (context.mounted) {
                                TopNotification.error(
                                  context,
                                  e.toString().replaceAll('Exception: ', ''),
                                );
                              }
                            } finally {
                              if (context.mounted) {
                                setModalState(() => isResending = false);
                              }
                            }
                          },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Verify Button
            TradeRepublicButton(
              label: AppLocalizations.of(context)!.verifyEmail,
              isLoading: isVerifying,
              width: double.infinity,
              onPressed: isVerifying
                  ? null
                  : () async {
                      if (verificationCodeController.text.trim().length != 8) {
                        TopNotification.error(
                          context,
                          AppLocalizations.of(context)!.enterEightDigitCode,
                        );
                        return;
                      }

                      setModalState(() {
                        isVerifying = true;
                      });

                      try {
                        final result = await ApiService.verifyEmail(
                          email: email,
                          code: verificationCodeController.text.trim(),
                        );

                        if (result['success']) {
                          Navigator.of(context).pop();
                          TopNotification.success(
                            context,
                            AppLocalizations.of(
                              context,
                            )!.accountCreatedCanSignIn,
                          );
                        } else {
                          throw Exception(
                            result['message'] ??
                                AppLocalizations.of(
                                  context,
                                )!.verificationFailed,
                          );
                        }
                      } catch (e) {
                        TopNotification.error(
                          context,
                          e.toString().replaceAll('Exception: ', ''),
                        );
                      } finally {
                        setModalState(() {
                          isVerifying = false;
                        });
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }

  // Login Email OTP Verification Modal
  // Shown after credentials are verified; completes login on correct OTP.
  void _showLoginEmailVerificationModal(String email, String username) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final codeController = TextEditingController();
    bool isVerifying = false;
    bool isResending = false;

    TradeRepublicBottomSheet.show(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      maxHeight: 520,
      child: StatefulBuilder(
        builder: (ctx, setModalState) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Row(
                children: [
                  Icon(
                    CupertinoIcons.lock_shield_fill,
                    color: isDark ? Colors.white : Colors.black,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context)!.verifyEmail,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : Colors.black,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                children: [
                  Text(
                    AppLocalizations.of(context)?.verificationSentTo ??
                        'A login code was sent to',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      color: (isDark ? Colors.white : Colors.black).withOpacity(
                        0.6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    email,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                  const SizedBox(height: 28),
                  TradeRepublicTextField.code(
                    controller: codeController,
                    hintText: '_ _ _ _ _ _ _ _',
                    maxLength: 8,
                    onChanged: (value) async {
                      if (value.length == 8 && !isVerifying) {
                        setModalState(() => isVerifying = true);
                        try {
                          final result = await ApiService.verifyLoginEmailCode(
                            username,
                            value.trim(),
                          );
                          if (ctx.mounted) Navigator.of(ctx).pop();
                          final storedResult = _tempLoginResult ?? result;
                          // Use verified result (has fresh tokens)
                          final mergedResult = Map<String, dynamic>.from(
                            storedResult,
                          );
                          mergedResult['accessToken'] = result['accessToken'];
                          mergedResult['refreshToken'] = result['refreshToken'];
                          await _completeLogin(mergedResult);
                        } catch (e) {
                          if (ctx.mounted) {
                            setModalState(() => isVerifying = false);
                            TopNotification.error(
                              context,
                              e.toString().replaceAll('Exception: ', ''),
                            );
                          }
                        }
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  TradeRepublicButton(
                    label: AppLocalizations.of(context)!.resendCode,
                    isSecondary: true,
                    isLoading: isResending,
                    width: double.infinity,
                    onPressed: (isResending || isVerifying)
                        ? null
                        : () async {
                            setModalState(() => isResending = true);
                            try {
                              await ApiService.sendLoginEmailCode(username);
                              if (ctx.mounted) {
                                TopNotification.success(
                                  context,
                                  AppLocalizations.of(
                                    context,
                                  )!.verificationCodeResent,
                                );
                              }
                            } catch (e) {
                              if (ctx.mounted) {
                                TopNotification.error(
                                  context,
                                  e.toString().replaceAll('Exception: ', ''),
                                );
                              }
                            } finally {
                              if (ctx.mounted) {
                                setModalState(() => isResending = false);
                              }
                            }
                          },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TradeRepublicButton(
              label: AppLocalizations.of(context)!.verifyEmail,
              isLoading: isVerifying,
              width: double.infinity,
              onPressed: isVerifying
                  ? null
                  : () async {
                      if (codeController.text.trim().length != 8) {
                        TopNotification.error(
                          context,
                          AppLocalizations.of(context)!.enterEightDigitCode,
                        );
                        return;
                      }
                      setModalState(() => isVerifying = true);
                      try {
                        final result = await ApiService.verifyLoginEmailCode(
                          username,
                          codeController.text.trim(),
                        );
                        if (ctx.mounted) Navigator.of(ctx).pop();
                        final storedResult = _tempLoginResult ?? result;
                        final mergedResult = Map<String, dynamic>.from(
                          storedResult,
                        );
                        mergedResult['accessToken'] = result['accessToken'];
                        mergedResult['refreshToken'] = result['refreshToken'];
                        await _completeLogin(mergedResult);
                      } catch (e) {
                        if (ctx.mounted) {
                          TopNotification.error(
                            context,
                            e.toString().replaceAll('Exception: ', ''),
                          );
                        }
                      } finally {
                        setModalState(() => isVerifying = false);
                      }
                    },
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      // If user dismisses without completing, clear loading state
      if (mounted) setState(() => _isLoading = false);
    });
  }

  // Modern Apple-style Registration
  void _showRegister() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;

    // Controllers for registration form
    final nameController = TextEditingController();
    final familyController = TextEditingController();
    final emailController = TextEditingController();
    final phoneController = TextEditingController();
    final streetController = TextEditingController();
    final houseNumberController = TextEditingController();
    final postalCodeController = TextEditingController();
    final cityController = TextEditingController();
    final companyNameController = TextEditingController();
    final companyWebsiteController = TextEditingController();
    final companyDescriptionController = TextEditingController();
    final taxIdController = TextEditingController();
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    DateTime? selectedBirthDate;
    String selectedCountryCode = '+1'; // Default to USA
    String selectedCountry = l10n.countryUS; // Default country
    String selectedCountryIso = 'US';
    String selectedBusinessSize = '1-10';
    bool isRegisterPasswordVisible = false;
    bool isConfirmPasswordVisible = false;
    bool isRegistering = false;
    int registerStep = 0;
    final registerPageController = PageController();
    Timer? usernameCheckDebounce;
    bool isCheckingUsername = false;
    bool? isUsernameAvailable;
    String? lastCheckedUsername;
    String? selectedProfileImage; // base64 data URL from image_picker

    final countries = <Map<String, String>>[
      {'iso': 'US', 'dial': '+1', 'name': l10n.countryUS, 'flag': '🇺🇸'},
      {'iso': 'DE', 'dial': '+49', 'name': l10n.countryDE, 'flag': '🇩🇪'},
      {'iso': 'AT', 'dial': '+43', 'name': l10n.countryAT, 'flag': '🇦🇹'},
      {'iso': 'CH', 'dial': '+41', 'name': l10n.countryCH, 'flag': '🇨🇭'},
      {'iso': 'GB', 'dial': '+44', 'name': l10n.countryGB, 'flag': '🇬🇧'},
      {'iso': 'FR', 'dial': '+33', 'name': l10n.countryFR, 'flag': '🇫🇷'},
      {'iso': 'IT', 'dial': '+39', 'name': l10n.countryIT, 'flag': '🇮🇹'},
      {'iso': 'ES', 'dial': '+34', 'name': l10n.countryES, 'flag': '🇪🇸'},
      {'iso': 'NL', 'dial': '+31', 'name': l10n.countryNL, 'flag': '🇳🇱'},
      {'iso': 'PL', 'dial': '+48', 'name': l10n.countryPL, 'flag': '🇵🇱'},
      {'iso': 'CA', 'dial': '+1', 'name': l10n.countryCA, 'flag': '🇨🇦'},
      {'iso': 'MX', 'dial': '+52', 'name': l10n.countryMX, 'flag': '🇲🇽'},
      {'iso': 'PT', 'dial': '+351', 'name': l10n.countryPT, 'flag': '🇵🇹'},
    ];

    String digitsOnly(String input) {
      return input.replaceAll(RegExp(r'[^0-9]'), '');
    }

    Map<String, String> selectedCountryMeta() {
      return countries.firstWhere(
        (c) => c['iso'] == selectedCountryIso,
        orElse: () => countries.first,
      );
    }

    int phoneMaxDigitsForCountry(String iso) {
      switch (iso) {
        case 'US':
        case 'CA':
          return 10;
        case 'CH':
        case 'FR':
        case 'ES':
        case 'NL':
        case 'PL':
          return 9;
        case 'DE':
        case 'AT':
        case 'GB':
          return 13;
        default:
          return 14;
      }
    }

    String groupPhoneDigits(String digits, List<int> groups) {
      final parts = <String>[];
      var cursor = 0;
      for (final size in groups) {
        if (cursor >= digits.length) break;
        final end = (cursor + size).clamp(0, digits.length);
        parts.add(digits.substring(cursor, end));
        cursor = end;
      }
      if (cursor < digits.length) {
        parts.add(digits.substring(cursor));
      }
      return parts.join(' ');
    }

    String formatPhoneForCountry(String raw, String iso) {
      final maxDigits = phoneMaxDigitsForCountry(iso);
      final normalized = digitsOnly(raw);
      final digits = normalized.length > maxDigits
          ? normalized.substring(0, maxDigits)
          : normalized;

      if (digits.isEmpty) return '';

      switch (iso) {
        case 'US':
        case 'CA':
          if (digits.length <= 3) return digits;
          if (digits.length <= 6) {
            return '${digits.substring(0, 3)} ${digits.substring(3)}';
          }
          return '${digits.substring(0, 3)} ${digits.substring(3, 6)} ${digits.substring(6)}';
        case 'CH':
          return groupPhoneDigits(digits, [3, 3, 2, 2]);
        case 'FR':
        case 'ES':
        case 'NL':
        case 'PL':
          return groupPhoneDigits(digits, [3, 3, 3]);
        default:
          return groupPhoneDigits(digits, [3, 3, 3, 3, 2]);
      }
    }

    void normalizePhoneControllerForCountry(String iso) {
      final formatted = formatPhoneForCountry(phoneController.text, iso);
      if (formatted == phoneController.text) return;
      phoneController.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }

    String taxLabelForCountry(String iso) {
      switch (iso) {
        case 'US':
          return l10n.registrationTaxLabelUs;
        case 'DE':
          return l10n.registrationTaxLabelDe;
        case 'AT':
          return l10n.registrationTaxLabelAt;
        case 'CH':
          return l10n.registrationTaxLabelCh;
        default:
          return l10n.registrationTaxLabelDefault;
      }
    }

    String taxHintForCountry(String iso) {
      switch (iso) {
        case 'US':
          return l10n.registrationTaxHintUs;
        case 'DE':
          return l10n.registrationTaxHintDe;
        case 'AT':
          return l10n.registrationTaxHintAt;
        case 'CH':
          return l10n.registrationTaxHintCh;
        default:
          return l10n.registrationTaxHintDefault;
      }
    }

    String phoneHintForCountry(String iso) {
      return l10n.registrationPhoneHintWithPrefix(selectedCountryCode);
    }

    bool isValidPhoneForCountry(String raw, String iso) {
      final digits = digitsOnly(raw);
      if (digits.isEmpty) return true;

      switch (iso) {
        case 'US':
        case 'CA':
          return digits.length == 10;
        case 'DE':
          return digits.length >= 10 && digits.length <= 13;
        case 'AT':
          return digits.length >= 10 && digits.length <= 13;
        case 'CH':
          return digits.length == 9;
        case 'GB':
          return digits.length == 10;
        case 'FR':
        case 'ES':
        case 'NL':
        case 'PL':
          return digits.length == 9;
        default:
          return digits.length >= 7 && digits.length <= 14;
      }
    }

    bool isValidTaxIdForCountry(String raw, String iso) {
      final value = raw.trim().toUpperCase();
      if (value.isEmpty) return false;

      switch (iso) {
        case 'US':
          // Accept XX-XXXXXXX or XXXXXXXXX (9 digits)
          return RegExp(r'^\d{2}-?\d{7}$').hasMatch(value) ||
              RegExp(r'^\d{9}$').hasMatch(value);
        case 'DE':
          // USt-IdNr: DE123456789 or Steuernummer various formats
          return RegExp(r'^DE\d{9}$').hasMatch(value) ||
              RegExp(
                r'^\d{2,5}[/\-\s]?\d{3}[/\-\s]?\d{3,5}$',
              ).hasMatch(value) ||
              RegExp(r'^\d{8,13}$').hasMatch(value);
        case 'AT':
          return RegExp(r'^ATU\d{8}$').hasMatch(value) ||
              RegExp(r'^\d{8,10}$').hasMatch(value);
        case 'CH':
          return RegExp(r'^CHE[-\s]?\d{3}\.?\d{3}\.?\d{3}$').hasMatch(value) ||
              RegExp(r'^CHE[-\s]?\d{9}$').hasMatch(value) ||
              RegExp(r'^\d{9}$').hasMatch(value);
        default:
          // Accept any 3–40 char alphanumeric/common-separator string
          return RegExp(r'^[A-Z0-9\-\s/.]{3,40}$').hasMatch(value);
      }
    }

    String normalizedUsername(String value) {
      return value.trim().toLowerCase();
    }

    bool canCheckUsername(String username) {
      return username.length >= 2 &&
          RegExp(r'^[a-z0-9_.]+$').hasMatch(username);
    }

    Future<String?> ensureUsernameAvailable(StateSetter setModalState) async {
      final username = normalizedUsername(usernameController.text);
      if (!canCheckUsername(username)) return null;

      if (lastCheckedUsername == username && isUsernameAvailable == true) {
        return null;
      }

      setModalState(() {
        isCheckingUsername = true;
      });

      try {
        final result = await ApiService.checkUsernameAvailability(username);
        final available = result['available'] == true;
        final currentUsername = normalizedUsername(usernameController.text);
        if (currentUsername != username) {
          return null;
        }

        setModalState(() {
          isCheckingUsername = false;
          lastCheckedUsername = username;
          isUsernameAvailable = available;
        });

        if (!available) {
          return l10n.usernameAlreadyTaken;
        }

        return null;
      } catch (_) {
        setModalState(() {
          isCheckingUsername = false;
          lastCheckedUsername = null;
          isUsernameAvailable = null;
        });
        return l10n.usernameCheckFailed;
      }
    }

    void scheduleUsernameCheck(StateSetter setModalState, String rawValue) {
      final normalized = normalizedUsername(rawValue);

      usernameCheckDebounce?.cancel();

      if (!canCheckUsername(normalized)) {
        setModalState(() {
          isCheckingUsername = false;
          isUsernameAvailable = null;
          lastCheckedUsername = null;
        });
        return;
      }

      setModalState(() {
        isCheckingUsername = true;
        isUsernameAvailable = null;
      });

      usernameCheckDebounce = Timer(
        const Duration(milliseconds: 450),
        () async {
          try {
            final result = await ApiService.checkUsernameAvailability(
              normalized,
            );
            final currentUsername = normalizedUsername(usernameController.text);
            if (currentUsername != normalized) return;

            setModalState(() {
              isCheckingUsername = false;
              lastCheckedUsername = normalized;
              isUsernameAvailable = result['available'] == true;
            });
          } catch (_) {
            final currentUsername = normalizedUsername(usernameController.text);
            if (currentUsername != normalized) return;

            setModalState(() {
              isCheckingUsername = false;
              lastCheckedUsername = null;
              isUsernameAvailable = null;
            });
          }
        },
      );
    }

    String? validateCurrentStep() {
      if (registerStep == 0) {
        if (nameController.text.trim().isEmpty ||
            familyController.text.trim().isEmpty ||
            emailController.text.trim().isEmpty) {
          return l10n.fillAllFields;
        }

        final email = emailController.text.trim();
        final emailIsValid = RegExp(
          r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
        ).hasMatch(email);
        if (!emailIsValid) {
          return l10n.invalidEmailAddress;
        }

        if (phoneController.text.trim().isEmpty) {
          return l10n.registrationPhoneRequired;
        }

        if (!isValidPhoneForCountry(phoneController.text, selectedCountryIso)) {
          return l10n.registrationInvalidPhoneForCountry(selectedCountry);
        }
      }

      if (registerStep == 1) {
        // Address is optional – only validate when at least one field is filled
        final anyAddressFilled =
            streetController.text.trim().isNotEmpty ||
            houseNumberController.text.trim().isNotEmpty ||
            postalCodeController.text.trim().isNotEmpty ||
            cityController.text.trim().isNotEmpty;
        if (anyAddressFilled) {
          if (streetController.text.trim().isEmpty ||
              houseNumberController.text.trim().isEmpty ||
              postalCodeController.text.trim().isEmpty ||
              cityController.text.trim().isEmpty) {
            return l10n.completeAddressFields;
          }
        }
      }

      if (registerStep == 2) {
        // Business info is optional – only validate when something is entered
        final taxIdRaw = taxIdController.text.trim();
        if (taxIdRaw.isNotEmpty) {
          if (!isValidTaxIdForCountry(taxIdRaw, selectedCountryIso)) {
            return l10n.registrationInvalidTaxId(
              taxLabelForCountry(selectedCountryIso),
            );
          }
        }

        final websiteRaw = companyWebsiteController.text.trim();
        if (websiteRaw.isNotEmpty) {
          final websiteUrl =
              websiteRaw.startsWith('http://') ||
                  websiteRaw.startsWith('https://')
              ? websiteRaw
              : 'https://$websiteRaw';
          final uri = Uri.tryParse(websiteUrl);
          final websiteIsValid = uri != null && uri.host.isNotEmpty;
          if (!websiteIsValid) {
            return l10n.registrationInvalidWebsite;
          }
        }
      }

      if (registerStep == 3) {
        final username = usernameController.text.trim();
        if (username.isEmpty ||
            passwordController.text.trim().isEmpty ||
            confirmPasswordController.text.trim().isEmpty) {
          return l10n.fillAllFields;
        }

        if (username.contains(RegExp(r'[A-Z]'))) {
          return l10n.usernameLowercaseOnly;
        }

        if (!RegExp(r'^[a-z0-9_.]+$').hasMatch(username)) {
          return l10n.usernameCanOnlyContainLowercaseLettersNumber;
        }

        if (isCheckingUsername) {
          return l10n.pleaseWaitUsernameCheck;
        }

        if (lastCheckedUsername == normalizedUsername(username) &&
            isUsernameAvailable == false) {
          return l10n.usernameAlreadyTaken;
        }

        if (passwordController.text != confirmPasswordController.text) {
          return l10n.passwordsDoNotMatch;
        }
      }

      return null;
    }

    Future<void> submitRegistration(StateSetter setModalState) async {
      final error = validateCurrentStep();
      if (error != null) {
        TopNotification.error(context, error);
        return;
      }

      final usernameError = await ensureUsernameAvailable(setModalState);
      if (usernameError != null) {
        TopNotification.error(context, usernameError);
        return;
      }

      setModalState(() => isRegistering = true);

      try {
        final phoneDigits = digitsOnly(phoneController.text.trim());
        final fullPhone = phoneDigits.isNotEmpty
            ? '$selectedCountryCode$phoneDigits'
            : null;

        final fullAddress =
            '$selectedCountry, ${cityController.text.trim()}, ${streetController.text.trim()} ${houseNumberController.text.trim()}, ${postalCodeController.text.trim()}';

        final formattedBirthdate = selectedBirthDate != null
            ? '${selectedBirthDate!.year}-${selectedBirthDate!.month.toString().padLeft(2, '0')}-${selectedBirthDate!.day.toString().padLeft(2, '0')}'
            : null;

        final websiteRaw = companyWebsiteController.text.trim();
        final websiteUrl = websiteRaw.isEmpty
            ? null
            : (websiteRaw.startsWith('http://') ||
                      websiteRaw.startsWith('https://')
                  ? websiteRaw
                  : 'https://$websiteRaw');
        final companyName = companyNameController.text.trim();

        final registerResult = await ApiService.register(
          name: nameController.text.trim(),
          family: familyController.text.trim(),
          email: emailController.text.trim(),
          password: passwordController.text.trim(),
          phone: fullPhone,
          address: fullAddress,
          username: usernameController.text.trim(),
          birthdate: formattedBirthdate,
          companyName: companyName.isEmpty ? null : companyName,
          companyWebsite: websiteUrl,
          companyDescription: companyDescriptionController.text.trim().isEmpty
              ? null
              : companyDescriptionController.text.trim(),
          businessSize: selectedBusinessSize,
          country: selectedCountry,
          taxId: taxIdController.text.trim(),
          profileImage: selectedProfileImage,
        );

        if (registerResult['success']) {
          Navigator.of(context).pop();
          _showEmailVerification(emailController.text.trim());

          if (registerResult['devCode'] != null) {
            Future.delayed(const Duration(milliseconds: 500), () {
              if (!context.mounted) return;
              TradeRepublicBottomSheet.show(
                context: context,
                showDragHandle: true,
                isDismissible: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '🔐 Dev Mode - Verification Code',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.yourVerificationCode,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark
                            ? const Color(0xFF8E8E93)
                            : const Color(0xFF6C6C6C),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF2C2C2E)
                            : const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(25),
                      ),
                      child: SelectableText(
                        registerResult['devCode'],
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 8,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.emailSendingMayFailInDevModenuseThisCodeF,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? const Color(0xFF8E8E93)
                            : const Color(0xFF6C6C6C),
                      ),
                    ),
                    const SizedBox(height: 20),
                    TradeRepublicButton(
                      label: l10n.gotIt,
                      onPressed: () => Navigator.of(context).pop(),
                      isSecondary: true,
                    ),
                  ],
                ),
              );
            });
          }

          TopNotification.success(context, l10n.verificationCodeSent);
        } else {
          throw Exception(registerResult['message'] ?? l10n.registrationFailed);
        }
      } catch (e) {
        TopNotification.error(
          context,
          l10n.registrationFailedWithMessage(
            e.toString().replaceAll('Exception: ', ''),
          ),
        );
      } finally {
        setModalState(() => isRegistering = false);
      }
    }

    TradeRepublicBottomSheet.show(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      child: StatefulBuilder(
        builder: (context, setModalState) => DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) => LayoutBuilder(
            builder: (context, constraints) => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.createAccount,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : Colors.black,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: List.generate(4, (i) {
                          final active = i <= registerStep;
                          return Expanded(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              margin: EdgeInsets.only(right: i == 3 ? 0 : 6),
                              height: 6,
                              decoration: BoxDecoration(
                                color: active
                                    ? TradeRepublicTheme.accentGreen
                                    : (isDark
                                          ? Colors.white.withOpacity(0.12)
                                          : Colors.black.withOpacity(0.08)),
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.registrationStepOfTotal('${registerStep + 1}', '4'),
                        style: TradeRepublicTheme.bodySmall(context),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: PageView(
                  controller: registerPageController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    SingleChildScrollView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                      child: Column(
                        children: [
                          // ── Profile picture picker ──
                          GestureDetector(
                            onTap: () async {
                              final picker = ImagePicker();
                              final picked = await picker.pickImage(
                                source: ImageSource.gallery,
                                maxWidth: 256,
                                maxHeight: 256,
                                imageQuality: 75,
                              );
                              if (picked != null) {
                                final bytes = await picked.readAsBytes();
                                final isAvif =
                                    bytes.length >= 12 &&
                                    bytes[4] == 0x66 && // f
                                    bytes[5] == 0x74 && // t
                                    bytes[6] == 0x79 && // y
                                    bytes[7] == 0x70 && // p
                                    bytes[8] == 0x61 && // a
                                    bytes[9] == 0x76 && // v
                                    bytes[10] == 0x69 && // i
                                    bytes[11] == 0x66; // f
                                if (isAvif) {
                                  TopNotification.error(
                                    context,
                                    'Please select JPG or PNG (AVIF is not supported).',
                                  );
                                  return;
                                }
                                final encoded = _encodeProfileImageForUpload(
                                  bytes,
                                );
                                if (encoded == null) {
                                  TopNotification.error(
                                    context,
                                    'Image could not be processed. Please use a smaller JPG/PNG.',
                                  );
                                  return;
                                }
                                setModalState(() {
                                  selectedProfileImage = encoded;
                                });
                              }
                            },
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 24),
                              child: Stack(
                                alignment: Alignment.bottomRight,
                                children: [
                                  Container(
                                    width: 88,
                                    height: 88,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isDark
                                          ? Colors.white.withOpacity(0.08)
                                          : Colors.black.withOpacity(0.05),
                                      border: Border.all(
                                        color: isDark
                                            ? Colors.white.withOpacity(0.12)
                                            : Colors.black.withOpacity(0.08),
                                        width: 2,
                                      ),
                                    ),
                                    child: selectedProfileImage != null
                                        ? ClipOval(
                                            child: Image.memory(
                                              base64Decode(
                                                selectedProfileImage!.replaceFirst(
                                                  RegExp(
                                                    r'data:image/[^;]+;base64,',
                                                  ),
                                                  '',
                                                ),
                                              ),
                                              fit: BoxFit.cover,
                                            ),
                                          )
                                        : Icon(
                                            CupertinoIcons.person_fill,
                                            size: 40,
                                            color: isDark
                                                ? Colors.white.withOpacity(0.4)
                                                : Colors.black.withOpacity(
                                                    0.25,
                                                  ),
                                          ),
                                  ),
                                  Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black,
                                    ),
                                    child: Icon(
                                      CupertinoIcons.camera_fill,
                                      size: 14,
                                      color: isDark
                                          ? Colors.black
                                          : Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          _buildModernSectionHeader(
                            l10n.personalInformation,
                            isDark,
                          ),
                          const SizedBox(height: 16),
                          _buildModernRegisterField(
                            l10n.firstName,
                            nameController,
                            isDark,
                            CupertinoIcons.person_fill,
                          ),
                          _buildModernRegisterField(
                            l10n.lastName,
                            familyController,
                            isDark,
                            CupertinoIcons.person_fill,
                          ),
                          TradeRepublicListTile.navigation(
                            title: selectedBirthDate != null
                                ? _formatDatePreview(
                                    selectedBirthDate!,
                                    _dateFormat,
                                  )
                                : l10n.selectBirthDate,
                            subtitle: selectedBirthDate != null
                                ? l10n.birthDate
                                : '(optional)',
                            leading: Icon(
                              CupertinoIcons.calendar,
                              color: isDark
                                  ? Colors.white.withOpacity(0.6)
                                  : Colors.black.withOpacity(0.5),
                              size: 22,
                            ),
                            onTap: () async {
                              DateTime tempDate =
                                  selectedBirthDate ??
                                  DateTime.now().subtract(
                                    const Duration(days: 6570),
                                  );

                              await TradeRepublicBottomSheet.show(
                                context: context,
                                useRootNavigator: true,
                                showDragHandle: true,
                                maxHeight: 350,
                                child: Column(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            l10n.selectBirthDate,
                                            style: TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.w700,
                                              color: isDark
                                                  ? Colors.white
                                                  : Colors.black,
                                            ),
                                          ),
                                          TradeRepublicButton(
                                            onPressed: () {
                                              setModalState(
                                                () => selectedBirthDate =
                                                    tempDate,
                                              );
                                              Navigator.pop(context);
                                            },
                                            label: l10n.done,
                                            isSecondary: true,
                                          ),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      child: CupertinoDatePicker(
                                        mode: CupertinoDatePickerMode.date,
                                        initialDateTime: tempDate,
                                        minimumDate: DateTime(1900),
                                        maximumDate: DateTime.now(),
                                        onDateTimeChanged: (DateTime newDate) {
                                          tempDate = newDate;
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 22),
                          _buildModernSectionHeader(
                            l10n.contactInformation,
                            isDark,
                          ),
                          const SizedBox(height: 16),
                          _buildModernRegisterField(
                            l10n.emailAddress,
                            emailController,
                            isDark,
                            CupertinoIcons.mail,
                          ),
                          Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                GestureDetector(
                                  onTap: () {
                                    TradeRepublicBottomSheet.show(
                                      context: context,
                                      useRootNavigator: true,
                                      showDragHandle: true,
                                      maxHeight:
                                          MediaQuery.of(context).size.height *
                                          0.7,
                                      child: Column(
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                              24,
                                              0,
                                              24,
                                              16,
                                            ),
                                            child: Text(
                                              l10n.countryCode,
                                              style: TextStyle(
                                                fontSize: 24,
                                                fontWeight: FontWeight.w700,
                                                color: isDark
                                                    ? Colors.white
                                                    : Colors.black,
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            child: ListView(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 24,
                                                  ),
                                              children: countries.map((c) {
                                                return _buildCountryCodeOption(
                                                  c['name']!,
                                                  c['dial']!,
                                                  isDark,
                                                  () {
                                                    setModalState(() {
                                                      selectedCountryCode =
                                                          c['dial']!;
                                                      selectedCountry =
                                                          c['name']!;
                                                      selectedCountryIso =
                                                          c['iso']!;
                                                      normalizePhoneControllerForCountry(
                                                        selectedCountryIso,
                                                      );
                                                    });
                                                    Navigator.pop(context);
                                                  },
                                                  flag: c['flag']!,
                                                );
                                              }).toList(),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 28),
                                    child: Container(
                                      width: 124,
                                      height: 52,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? Colors.white.withOpacity(0.08)
                                            : Colors.black.withOpacity(0.04),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            '${selectedCountryMeta()['flag']} $selectedCountryCode',
                                            style: TextStyle(
                                              fontFamily: 'Poppins',
                                              color: isDark
                                                  ? Colors.white
                                                  : Colors.black,
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Icon(
                                            CupertinoIcons.chevron_down,
                                            color: isDark
                                                ? Colors.white.withOpacity(0.6)
                                                : Colors.black.withOpacity(0.5),
                                            size: 18,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TradeRepublicTextField.withLabel(
                                    label: '${l10n.phoneNumber} *',
                                    controller: phoneController,
                                    keyboardType: TextInputType.phone,
                                    hintText: phoneHintForCountry(
                                      selectedCountryIso,
                                    ),
                                    prefixIcon: const Icon(
                                      CupertinoIcons.phone,
                                    ),
                                    onChanged: (value) {
                                      final formatted = formatPhoneForCountry(
                                        value,
                                        selectedCountryIso,
                                      );
                                      if (formatted == value) return;
                                      phoneController.value = TextEditingValue(
                                        text: formatted,
                                        selection: TextSelection.collapsed(
                                          offset: formatted.length,
                                        ),
                                      );
                                    },
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                        RegExp(r'[0-9]'),
                                      ),
                                      LengthLimitingTextInputFormatter(14),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              l10n.optionalFieldsAreMarkedWithOptional,
                              style: TradeRepublicTheme.bodySmall(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SingleChildScrollView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                      child: Column(
                        children: [
                          _buildModernSectionHeader(l10n.address, isDark),
                          const SizedBox(height: 16),
                          TradeRepublicListTile.navigation(
                            title: selectedCountry,
                            leading: const Icon(CupertinoIcons.globe),
                            onTap: () {
                              TradeRepublicBottomSheet.show(
                                context: context,
                                useRootNavigator: true,
                                showDragHandle: true,
                                maxHeight:
                                    MediaQuery.of(context).size.height * 0.7,
                                child: Column(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        24,
                                        0,
                                        24,
                                        16,
                                      ),
                                      child: Text(
                                        l10n.country,
                                        style: TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.w700,
                                          color: isDark
                                              ? Colors.white
                                              : Colors.black,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: ListView(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 24,
                                        ),
                                        children: countries.map((c) {
                                          return _buildCountryCodeOption(
                                            c['name']!,
                                            c['name']!,
                                            isDark,
                                            () {
                                              setModalState(() {
                                                selectedCountry = c['name']!;
                                                selectedCountryIso = c['iso']!;
                                                selectedCountryCode =
                                                    c['dial']!;
                                                normalizePhoneControllerForCountry(
                                                  selectedCountryIso,
                                                );
                                              });
                                              Navigator.pop(context);
                                            },
                                            flag: c['flag']!,
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: _buildModernRegisterField(
                                  l10n.street,
                                  streetController,
                                  isDark,
                                  CupertinoIcons.location_solid,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 1,
                                child: _buildModernRegisterField(
                                  l10n.houseNumber,
                                  houseNumberController,
                                  isDark,
                                  CupertinoIcons.tag,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: _buildModernRegisterField(
                                  l10n.zipCode,
                                  postalCodeController,
                                  isDark,
                                  CupertinoIcons.mail_solid,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 3,
                                child: _buildModernRegisterField(
                                  l10n.city,
                                  cityController,
                                  isDark,
                                  CupertinoIcons.building_2_fill,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    SingleChildScrollView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                      child: Column(
                        children: [
                          _buildModernSectionHeader(
                            l10n.businessInformation,
                            isDark,
                          ),
                          const SizedBox(height: 16),
                          _buildModernRegisterField(
                            l10n.businessName,
                            companyNameController,
                            isDark,
                            CupertinoIcons.building_2_fill,
                            textCapitalization: TextCapitalization.words,
                          ),
                          _buildModernRegisterField(
                            l10n.registrationCompanyWebsiteOptional,
                            companyWebsiteController,
                            isDark,
                            CupertinoIcons.globe,
                            keyboardType: TextInputType.url,
                          ),
                          _buildModernRegisterField(
                            l10n.registrationCompanyDescriptionOptional,
                            companyDescriptionController,
                            isDark,
                            CupertinoIcons.doc_text,
                            maxLines: 3,
                            textCapitalization: TextCapitalization.sentences,
                          ),
                          TradeRepublicListTile.navigation(
                            title:
                                '${l10n.registrationCompanySize}: $selectedBusinessSize',
                            leading: const Icon(
                              CupertinoIcons.person_3_fill,
                              size: 22,
                            ),
                            onTap: () {
                              final sizes = [
                                '1-10',
                                '11-50',
                                '51-200',
                                '201-1000',
                                '1000+',
                              ];
                              TradeRepublicBottomSheet.show(
                                context: context,
                                useRootNavigator: true,
                                showDragHandle: true,
                                maxHeight:
                                    MediaQuery.of(context).size.height * 0.55,
                                child: Column(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        24,
                                        0,
                                        24,
                                        16,
                                      ),
                                      child: Text(
                                        l10n.registrationCompanySize,
                                        style: TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.w700,
                                          color: isDark
                                              ? Colors.white
                                              : Colors.black,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: ListView(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 24,
                                        ),
                                        children: sizes.map((size) {
                                          return TradeRepublicListTile(
                                            title: size,
                                            trailing:
                                                selectedBusinessSize == size
                                                ? const Icon(
                                                    CupertinoIcons
                                                        .checkmark_circle_fill,
                                                    color: Color(0xFF34C759),
                                                  )
                                                : null,
                                            onTap: () {
                                              setModalState(
                                                () =>
                                                    selectedBusinessSize = size,
                                              );
                                              Navigator.pop(context);
                                            },
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          TradeRepublicTextField.withLabel(
                            label:
                                '${taxLabelForCountry(selectedCountryIso)} (optional)',
                            controller: taxIdController,
                            hintText: taxHintForCountry(selectedCountryIso),
                            prefixIcon: const Icon(CupertinoIcons.number),
                            keyboardType: TextInputType.text,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[A-Za-z0-9\-\./ ]'),
                              ),
                              LengthLimitingTextInputFormatter(40),
                            ],
                            onChanged: (value) {
                              // Auto-format US EIN: insert dash after 2 digits
                              if (selectedCountryIso == 'US') {
                                final digits = value.replaceAll(
                                  RegExp(r'[^0-9]'),
                                  '',
                                );
                                if (digits.length >= 3 &&
                                    !value.contains('-')) {
                                  final formatted =
                                      '${digits.substring(0, 2)}-${digits.substring(2)}';
                                  taxIdController.value = TextEditingValue(
                                    text: formatted,
                                    selection: TextSelection.collapsed(
                                      offset: formatted.length,
                                    ),
                                  );
                                }
                              }
                            },
                          ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              selectedCountryIso == 'DE'
                                  ? l10n.registrationTaxDeNote
                                  : l10n.registrationTaxGenericNote,
                              style: TradeRepublicTheme.bodySmall(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SingleChildScrollView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                      child: Column(
                        children: [
                          _buildModernSectionHeader(
                            l10n.loginCredentials,
                            isDark,
                          ),
                          const SizedBox(height: 16),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: TradeRepublicTextField.withLabel(
                              label: l10n.username,
                              controller: usernameController,
                              hintText: l10n.username,
                              prefixIcon: const Icon(CupertinoIcons.at),
                              keyboardType: TextInputType.text,
                              inputFormatters: [
                                FilteringTextInputFormatter.deny(
                                  RegExp(r'[A-Z]'),
                                ),
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'[a-z0-9_.]'),
                                ),
                              ],
                              onChanged: (value) {
                                final lowerValue = value.toLowerCase();
                                if (value != lowerValue) {
                                  usernameController.value = usernameController
                                      .value
                                      .copyWith(
                                        text: lowerValue,
                                        selection: TextSelection.collapsed(
                                          offset: lowerValue.length,
                                        ),
                                      );
                                }
                                scheduleUsernameCheck(
                                  setModalState,
                                  lowerValue,
                                );
                              },
                            ),
                          ),
                          if (isCheckingUsername)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  l10n.checkingUsername,
                                  style: TradeRepublicTheme.bodySmall(context),
                                ),
                              ),
                            ),
                          if (!isCheckingUsername &&
                              lastCheckedUsername ==
                                  normalizedUsername(usernameController.text) &&
                              isUsernameAvailable == true)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  l10n.usernameAvailable,
                                  style: TradeRepublicTheme.bodySmall(
                                    context,
                                  ).copyWith(color: const Color(0xFF34C759)),
                                ),
                              ),
                            ),
                          if (!isCheckingUsername &&
                              lastCheckedUsername ==
                                  normalizedUsername(usernameController.text) &&
                              isUsernameAvailable == false)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  l10n.usernameAlreadyTaken,
                                  style: TradeRepublicTheme.bodySmall(
                                    context,
                                  ).copyWith(color: const Color(0xFFFF3B30)),
                                ),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: TradeRepublicTextField(
                              controller: passwordController,
                              obscureText: !isRegisterPasswordVisible,
                              hintText: l10n.password,
                              prefixIcon: Icon(
                                CupertinoIcons.lock,
                                color: isDark
                                    ? Colors.white.withOpacity(0.6)
                                    : Colors.black.withOpacity(0.5),
                                size: 22,
                              ),
                              suffixIcon: IconButton(
                                onPressed: () {
                                  setModalState(() {
                                    isRegisterPasswordVisible =
                                        !isRegisterPasswordVisible;
                                  });
                                },
                                icon: Icon(
                                  isRegisterPasswordVisible
                                      ? CupertinoIcons.eye
                                      : CupertinoIcons.eye_slash,
                                  color: isDark
                                      ? Colors.white.withOpacity(0.6)
                                      : Colors.black.withOpacity(0.5),
                                  size: 22,
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: TradeRepublicTextField(
                              controller: confirmPasswordController,
                              obscureText: !isConfirmPasswordVisible,
                              hintText: l10n.confirmPassword,
                              prefixIcon: Icon(
                                CupertinoIcons.lock,
                                color: isDark
                                    ? Colors.white.withOpacity(0.6)
                                    : Colors.black.withOpacity(0.5),
                                size: 22,
                              ),
                              suffixIcon: IconButton(
                                onPressed: () {
                                  setModalState(() {
                                    isConfirmPasswordVisible =
                                        !isConfirmPasswordVisible;
                                  });
                                },
                                icon: Icon(
                                  isConfirmPasswordVisible
                                      ? CupertinoIcons.eye
                                      : CupertinoIcons.eye_slash,
                                  color: isDark
                                      ? Colors.white.withOpacity(0.6)
                                      : Colors.black.withOpacity(0.5),
                                  size: 22,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: isDark
                          ? Colors.white.withOpacity(0.05)
                          : Colors.black.withOpacity(0.03),
                      width: 1,
                    ),
                  ),
                ),
                child: Container(
                  width: double.infinity,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(25),
                    boxShadow: [
                      BoxShadow(
                        color: (isDark ? Colors.black : Colors.grey)
                            .withOpacity(0.15),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TradeRepublicButton(
                          label: registerStep == 0
                              ? l10n.cancel
                              : l10n.registrationBack,
                          isSecondary: true,
                          onPressed: isRegistering
                              ? null
                              : () async {
                                  if (registerStep == 0) {
                                    Navigator.maybePop(context);
                                    return;
                                  }
                                  final nextStep = registerStep - 1;
                                  setModalState(() => registerStep = nextStep);
                                  await registerPageController.animateToPage(
                                    nextStep,
                                    duration: const Duration(milliseconds: 220),
                                    curve: Curves.easeOut,
                                  );
                                },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: TradeRepublicButton(
                          onPressed: isRegistering
                              ? null
                              : () async {
                                  final error = validateCurrentStep();
                                  if (error != null) {
                                    TopNotification.error(context, error);
                                    return;
                                  }

                                  if (registerStep < 3) {
                                    final nextStep = registerStep + 1;
                                    setModalState(
                                      () => registerStep = nextStep,
                                    );
                                    await registerPageController.animateToPage(
                                      nextStep,
                                      duration: const Duration(
                                        milliseconds: 220,
                                      ),
                                      curve: Curves.easeOut,
                                    );
                                    return;
                                  }

                                  await submitRegistration(setModalState);
                                },
                          label: registerStep == 3
                              ? (isRegistering
                                    ? l10n.creating
                                    : l10n.createAccount)
                              : l10n.continueButton,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      )
    );
  }

  // Forgot Password Modal
  void _showForgotPassword() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final emailController = TextEditingController();
    bool isLoading = false;

    TradeRepublicBottomSheet.show(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      child: StatefulBuilder(
        builder: (context, setModalState) => DraggableScrollableSheet(
          initialChildSize: 0.55,
          minChildSize: 0.4,
          maxChildSize: 0.75,
          builder: (context, scrollController) => LayoutBuilder(
            builder: (context, constraints) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                  child: Row(
                    children: [
                      Icon(
                        CupertinoIcons.lock_fill,
                        color: isDark ? Colors.white : Colors.black,
                        size: 32,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          AppLocalizations.of(context)!.forgotPassword,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: isDark ? Colors.white : Colors.black,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  AppLocalizations.of(context)!.forgotPasswordSubtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark
                        ? Colors.white.withOpacity(0.7)
                        : Colors.black.withOpacity(0.6),
                    height: 1.4,
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // Form Content
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      // Email Input Field
                      TradeRepublicTextField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        hintText: AppLocalizations.of(context)!.emailAddress,
                        prefixIcon: Icon(CupertinoIcons.mail_solid, size: 22),
                      ),

                      const SizedBox(height: 32),

                      // Send Reset Link Button
                      TradeRepublicButton(
                        label: isLoading
                            ? AppLocalizations.of(context)!.sending
                            : AppLocalizations.of(context)!.sendResetLink,
                        width: double.infinity,
                        onPressed: isLoading
                            ? null
                            : () async {
                                if (emailController.text.trim().isEmpty) {
                                  TopNotification.error(
                                    context,
                                    AppLocalizations.of(
                                      context,
                                    )!.enterEmailAddress,
                                  );
                                  return;
                                }

                                setModalState(() {
                                  isLoading = true;
                                });

                                try {
                                  final result =
                                      await ApiService.requestPasswordReset(
                                        emailController.text.trim(),
                                      );

                                  if (context.mounted) {
                                    if (result['success'] == true) {
                                      Navigator.of(context).pop();
                                      // Show reset code entry modal
                                      _showResetPasswordModal(
                                        emailController.text.trim(),
                                      );
                                    } else {
                                      TopNotification.error(
                                        context,
                                        AppLocalizations.of(
                                          context,
                                        )!.failedToSendResetLink,
                                      );
                                    }
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    TopNotification.error(
                                      context,
                                      AppLocalizations.of(
                                        context,
                                      )!.anErrorOccurredPleaseTryAgain,
                                    );
                                  }
                                } finally {
                                  setModalState(() {
                                    isLoading = false;
                                  });
                                }
                              },
                      ),

                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      )
    );
  }

  // Reset Password Modal (enter code and new password)
  void _showResetPasswordModal(String email) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final codeController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool isLoading = false;
    bool obscureNewPassword = true;
    bool obscureConfirmPassword = true;

    TradeRepublicBottomSheet.show(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      child: StatefulBuilder(
        builder: (context, setModalState) => DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.5,
          maxChildSize: 0.9,
          builder: (context, scrollController) => Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                child: Row(
                  children: [
                    Icon(
                      CupertinoIcons.lock_rotation,
                      color: isDark ? Colors.white : Colors.black,
                      size: 32,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        AppLocalizations.of(context)!.resetPassword,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : Colors.black,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  AppLocalizations.of(context)!.resetPasswordSubtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark
                        ? Colors.white.withOpacity(0.7)
                        : Colors.black.withOpacity(0.6),
                    height: 1.4,
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // Form Content
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      // Code Input Field
                      TradeRepublicTextField.code(
                        controller: codeController,
                        maxLength: 6,
                        hintText: '000000',
                      ),

                      const SizedBox(height: 16),

                      // New Password Field
                      TradeRepublicTextField(
                        controller: newPasswordController,
                        obscureText: obscureNewPassword,
                        hintText: AppLocalizations.of(context)!.newPassword,
                        prefixIcon: Icon(CupertinoIcons.lock_fill, size: 22),
                        suffixIcon: IconButton(
                          onPressed: () {
                            setModalState(() {
                              obscureNewPassword = !obscureNewPassword;
                            });
                          },
                          icon: Icon(
                            obscureNewPassword
                                ? CupertinoIcons.eye_slash
                                : CupertinoIcons.eye,
                            size: 22,
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Confirm Password Field
                      TradeRepublicTextField(
                        controller: confirmPasswordController,
                        obscureText: obscureConfirmPassword,
                        hintText: AppLocalizations.of(
                          context,
                        )!.confirmNewPassword,
                        prefixIcon: Icon(CupertinoIcons.lock_fill, size: 22),
                        suffixIcon: IconButton(
                          onPressed: () {
                            setModalState(() {
                              obscureConfirmPassword = !obscureConfirmPassword;
                            });
                          },
                          icon: Icon(
                            obscureConfirmPassword
                                ? CupertinoIcons.eye_slash
                                : CupertinoIcons.eye,
                            size: 22,
                          ),
                        ),
                      ),

                      const SizedBox(height: 32),

                      // Reset Password Button
                      TradeRepublicButton(
                        label: isLoading
                            ? AppLocalizations.of(context)!.resetting
                            : AppLocalizations.of(context)!.resetPassword,
                        width: double.infinity,
                        onPressed: isLoading
                            ? null
                            : () async {
                                if (codeController.text.trim().length != 6) {
                                  TopNotification.error(
                                    context,
                                    AppLocalizations.of(
                                      context,
                                    )!.enterSixDigitCode,
                                  );
                                  return;
                                }

                                if (newPasswordController.text.trim().length <
                                    6) {
                                  TopNotification.error(
                                    context,
                                    AppLocalizations.of(
                                      context,
                                    )!.passwordMinLength,
                                  );
                                  return;
                                }

                                if (newPasswordController.text !=
                                    confirmPasswordController.text) {
                                  TopNotification.error(
                                    context,
                                    AppLocalizations.of(
                                      context,
                                    )!.passwordsDoNotMatch,
                                  );
                                  return;
                                }

                                setModalState(() {
                                  isLoading = true;
                                });

                                try {
                                  final result = await ApiService.resetPassword(
                                    email: email,
                                    code: codeController.text.trim(),
                                    newPassword: newPasswordController.text,
                                  );

                                  if (context.mounted) {
                                    if (result['success'] == true) {
                                      Navigator.of(context).pop();
                                      TopNotification.success(
                                        context,
                                        AppLocalizations.of(
                                          context,
                                        )!.passwordResetSuccess,
                                      );
                                    } else {
                                      TopNotification.error(
                                        context,
                                        result['message'] ??
                                            AppLocalizations.of(
                                              context,
                                            )!.failedToResetPassword,
                                      );
                                    }
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    TopNotification.error(
                                      context,
                                      AppLocalizations.of(
                                        context,
                                      )!.anErrorOccurredPleaseTryAgain,
                                    );
                                  }
                                } finally {
                                  setModalState(() {
                                    isLoading = false;
                                  });
                                }
                              },
                      ),

                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Helper methods for modern design
  Widget _buildModernSectionHeader(String title, bool isDark) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white : Colors.black,
        ),
      ),
    );
  }

  Widget _buildModernRegisterField(
    String label,
    TextEditingController controller,
    bool isDark,
    IconData icon, {
    bool isUsername = false,
    TextInputType? keyboardType,
    int maxLines = 1,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TradeRepublicTextField(
        controller: controller,
        hintText: label,
        keyboardType: keyboardType,
        maxLines: maxLines,
        textCapitalization: textCapitalization,
        prefixIcon: Icon(icon, size: 22),
        inputFormatters: isUsername
            ? [
                FilteringTextInputFormatter.deny(RegExp(r'[A-Z]')),
                FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9_.]')),
              ]
            : null,
        onChanged: isUsername
            ? (value) {
                final lowerValue = value.toLowerCase();
                if (value != lowerValue) {
                  controller.value = controller.value.copyWith(
                    text: lowerValue,
                    selection: TextSelection.collapsed(offset: lowerValue.length),
                  );
                }
              }
            : null,
      ),
    );
  }

  // Helper method for country code selection
  Widget _buildCountryCodeOption(
    String label,
    String code,
    bool isDark,
    VoidCallback onTap, {
    String flag = '',
  }) {
    return TradeRepublicListTile(
      title: flag.isNotEmpty ? '$flag  $label' : label,
      trailing: Text(
        code,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: isDark ? Colors.grey[400] : Colors.grey[600],
        ),
      ),
      onTap: onTap,
    );
  }

  // Test login for direct login with Arkadiy
  void _testLogin() async {
    //debugPrint('🔄 Test login started...');

    setState(() {
      _isLoading = true;
    });

    try {
      //debugPrint('📡 Trying API login...');

      // Try real login via API
      final loginResult = await ApiService.login('Arkadiy', 'Donezk.2006');

      //debugPrint(' API login response received: ${loginResult.toString()}');

      if (loginResult['success'] && loginResult['user'] != null) {
        // Debug: Print user data to check 2FA fields
        //debugPrint('🔍 Test Login - User data from server: ${loginResult['user']}');

        // Check if user has 2FA enabled from server
        var userHas2FA =
            loginResult['user']['has_2fa_enabled'] == true ||
            loginResult['user']['has_2fa_enabled'] == 1;
        var user2FACode = loginResult['user']['twofa'];

        // If server doesn't provide 2FA data, check stored code first
        if (!userHas2FA ||
            user2FACode == null ||
            user2FACode.toString().isEmpty) {
          final prefs = await SharedPreferences.getInstance();
          String? storedCode = prefs.getString('user_2fa_code');
          bool storedHas2FA = prefs.getBool('has_2fa_enabled') ?? false;

          if (storedCode != null && storedHas2FA) {
            //debugPrint('🔐 Test Login - Using stored 2FA code: $storedCode');
            userHas2FA = true;
            user2FACode = storedCode;
          } else {
            //debugPrint('🔒 Test Login - No 2FA code found - 2FA disabled');
            userHas2FA = false;
            user2FACode = null;
          }
        }

        //debugPrint('🔍 Test Login - Final 2FA Check: userHas2FA=$userHas2FA, user2FACode=$user2FACode');

        if (userHas2FA && user2FACode != null) {
          //debugPrint('🔐 2FA required for test login');
          setState(() {
            _isLoading = false;
            _user2FACode = user2FACode;
            _has2FAEnabled = true;
          });
          _show2FALoginDialog(loginResult);
          return;
        } else {
          //debugPrint('ℹ️ Test Login - No 2FA required: userHas2FA=$userHas2FA, user2FACode=$user2FACode');
        }

        // Complete login if no 2FA required
        await _completeLogin(loginResult);
      } else {
        throw Exception(
          'Login failed: ${loginResult['message'] ?? AppLocalizations.of(context)!.unknownError}',
        );
      }
    } catch (e) {
      //debugPrint(' Test login API error: $e');

      // Fallback: Set data directly without API
      setState(() {
        _isLoggedIn = true;
        _userEmail = 'arkadiytatarynskyy@gmail.com';
        _userName = AppLocalizations.of(context)!.arkadiyTatarynskyy;
        _userUsername = 'arkadiy';
        _isBusiness = true;
        _stripeCustomerId = 'cus_SrVzlS4GjgQUPo';
        _stripeAccountId = 'acct_1RwJQoK2J0qEIPfv';
        _userPhone = '+491794596699';
        _userBirthDate = DateTime(1990, 7, 5);
        _createdAt = DateTime(2025, 8, 25);
        _businessName = AppLocalizations.of(context)!.cultiooGmbh;
        _businessEmail = 'business@cultioo.com';
      });

      //debugPrint('⚠️ Fallback login activated');

      if (mounted) {
        _showBottomMessage('⚠️ Test login (offline mode): Arkadiy logged in');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      //debugPrint('🔄 Test login completed');
    }
  }

  // Mock mode entfernt - nur echte Daten werden verwendet

  void _testApiConnection() async {
    //debugPrint('🧪 Testing API connection...');
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Show loading modal
    TradeRepublicBottomSheet.show(
      context: context,
      isDismissible: false,
      enableDrag: false,
      useRootNavigator: true,
      showDragHandle: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(25, 0, 25, 25),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CultiooLoadingIndicator(),
                const SizedBox(height: 20),

                Text(
                  AppLocalizations.of(context)!.testingApiConnection,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );

    try {
      bool isConnected = await ApiService.testConnection();

      // Close loading dialog
      Navigator.of(context).pop();

      // Show result
      _showBottomMessage(
        isConnected
            ? ' API connection successful!'
            : ' API connection failed. Check the URL.',
        isError: !isConnected,
        isSuccess: isConnected,
      );
    } catch (e) {
      // Close loading dialog
      Navigator.of(context).pop();

      // Show error
      // Show error
      _showBottomMessage(' API-Test fehlgeschlagen: $e', isError: true);
    }
  }

  void _logout() {
    TradeRepublicBottomSheet.show(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      maxHeight: 300,
      child: Builder(
        builder: (context) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon
                // Header
                Row(
                  children: [
                    Icon(
                      CupertinoIcons.square_arrow_right,
                      color: Colors.red,
                      size: 32,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        AppLocalizations.of(context)!.logOut,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: Colors.red,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Content
                Text(
                  AppLocalizations.of(context)!.logOutConfirm,
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // Log Out Button
                TradeRepublicButton(
                  label: AppLocalizations.of(context)!.logOut,
                  onPressed: () async {
                    Navigator.of(context).pop();

                    await _unregisterPushTokenForCurrentUser();

                    // Clear ALL device-specific data
                    await DeviceStorage.clearAll();

                    // Clear non-device-specific data (2FA, etc.)
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.remove('user_2fa_code');
                    await prefs.setBool('has_2fa_enabled', false);

                    // Clear API token
                    await ApiService.clearToken();

                    debugPrint('🗑️ COMPLETE LOGOUT - All device data cleared');

                    setState(() {
                      _isLoggedIn = false;
                      _userEmail = '';
                      _userName = '';
                      _userUsername = '';
                      _accessToken = '';
                      _has2FAEnabled = false;
                      _user2FACode = null;
                      _biometricEnabled = false;
                      _currentUser = null;
                      _profileImageSrc = null;
                      // Reset to home page and tab index
                      _currentPage = 0;
                      _tabIndex = 0;
                    });
                    _pageController.jumpToPage(0);
                    HapticFeedback.lightImpact();
                  },
                  isDestructive: true,
                  width: double.infinity,
                  height: 56,
                ),
                const SizedBox(height: 16),

                // Cancel Button
                TradeRepublicButton(
                  label: AppLocalizations.of(context)!.cancel,
                  onPressed: () => Navigator.of(context).pop(),
                  isSecondary: true,
                  width: double.infinity,
                  height: 56,
                ),
                const SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _clearStoredCredentials() async {
    await _unregisterPushTokenForCurrentUser();

    // Clear ALL device-specific data
    await DeviceStorage.clearAll();

    // Clear non-device-specific data (2FA, etc.)
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_2fa_code');
    await prefs.setBool('has_2fa_enabled', false);

    // Clear ChatOverviewPage data
    await prefs.remove('pinned_conversations');
    await prefs.remove('hidden_conversations');
    await prefs.remove('cached_conversations');
    await prefs.remove('conversations_cache_time');

    // Clear dismissed orders list
    await prefs.remove('dismissed_order_ids');
    final dismissedOrderKeys = prefs
        .getKeys()
        .where((k) => k.startsWith('dismissed_order_ids_'))
        .toList();
    for (final key in dismissedOrderKeys) {
      await prefs.remove(key);
    }
    setState(() => _dismissedOrderIds.clear());

    // Clear API token
    await ApiService.clearToken();

    debugPrint('🗑️ COMPLETE LOGOUT - All device data cleared');
  }

  void _showPaymentMethods() {
    setState(() {
      _isModalOpen = true;
      _isTransitioningToAnotherModal = false;
    });
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      useRootNavigator: true,
      maxHeight: MediaQuery.of(context).size.height * 0.8,
      child: PaymentMethodsModal(
        accessToken: _accessToken,
        onShowAddPaymentMethod: _showAddPaymentMethodSheet,
      ),
    ).whenComplete(() {
      if (_isTransitioningToAnotherModal) return;
      if (!mounted) return;
      setState(() => _isModalOpen = false);
    });
  }

  void _showAddPaymentMethodSheet() {
    setState(() {
      _isModalOpen = true;
      _isTransitioningToAnotherModal = true;
    });
    final isDark = Theme.of(context).brightness == Brightness.dark;

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      useRootNavigator: true,
      maxHeight: MediaQuery.of(context).size.height * 0.75,
      child: AddPaymentMethodSheet(
        isDark: isDark,
        onAdded: () {
          // Reload payment methods after adding
        },
      ),
    ).whenComplete(() {
      if (!mounted) return;
      setState(() {
        _isModalOpen = false;
        _isTransitioningToAnotherModal = false;
      });
    });
  }

  void _showGroups() {
    setState(() => _isModalOpen = true);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      useRootNavigator: true,
      maxHeight: MediaQuery.of(context).size.height * 0.85,
      child: GroupsModal(isDark: isDark, currentUsername: _userName),
    ).whenComplete(() {
      if (!mounted) return;
      setState(() => _isModalOpen = false);
    });
  }

  void _showTransactionHistory() {
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      useRootNavigator: true,
      child: SizedBox(
        height:
            MediaQuery.of(context).size.height *
            0.75, // Limited to 75% of screen height
        child: TransactionHistoryModal(numberFormat: _resolveNumberFormat()),
      ),
    );
  }

  void _showProfileEdit() {
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      useRootNavigator: true,
      maxHeight: MediaQuery.of(context).size.height * 0.8,
      child: ProfileEditModal(
        accessToken: _accessToken,
        userData: _currentUser ?? {},
      ),
    ).then((result) {
      // Update user data immediately if profile was updated successfully
      //debugPrint('🔍 Edit Modal returned: $result');
      if (result != null && result is Map<String, dynamic>) {
        //debugPrint('🔍 Updating _currentUser with: $result');
        setState(() {
          if (_currentUser != null) {
            _currentUser!['name'] = result['name'];
            _currentUser!['email'] = result['email'];
            _currentUser!['phone'] = result['phone'];
            if (result['birthdate'] != null) {
              _currentUser!['birthdate'] = result['birthdate'];
            }

            // Also update _userName and _userEmail for immediate UI display
            _userName = result['name'] ?? _userName;
            _userUsername = result['username'] ?? _userUsername;
            _userEmail = result['email'] ?? _userEmail;
            //debugPrint('🔍 New _userName: $_userName, _userEmail: $_userEmail');
          }
        });

        // Reload complete user profile (including profile picture)
        _loadRealData();
      }
    });
  }

  void _showChangePasswordModal() {
    //debugPrint('🔍 Debug: _showChangePasswordModal called');
    //debugPrint('🔍 Debug: _accessToken = "$_accessToken"');
    //debugPrint('🔍 Debug: _accessToken.isEmpty = ${_accessToken.isEmpty}');

    if (_accessToken.isNotEmpty) {
      //debugPrint('🔍 Debug: Opening ChangePasswordModal...');
      TradeRepublicBottomSheet.show(
        context: context,
        showDragHandle: true,
        useRootNavigator: true,
        maxHeight: MediaQuery.of(context).size.height * 0.75,
        child: ChangePasswordModal(accessToken: _accessToken),
      );
    } else {
      //debugPrint('🔍 Debug: No access token, showing login message');
      _showInfo(AppLocalizations.of(context)!.pleaseLoginFirst);
    }
  }

  void _showDeleteAccountModal() {
    if (_accessToken.isEmpty) {
      _showInfo(AppLocalizations.of(context)!.pleaseLoginFirst);
      return;
    }

    final passwordController = TextEditingController();
    bool isLoading = false;

    TradeRepublicBottomSheet.show(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      maxHeight: MediaQuery.of(context).size.height * 0.7,
      child: StatefulBuilder(
        builder: (BuildContext context, StateSetter setModalState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final textCol = isDark ? Colors.white : Colors.black;
          return Column(
            children: [
              // Header
              Row(
                children: [
                  Icon(
                    CupertinoIcons.exclamationmark_triangle,
                    size: 28,
                    color: isDark ? Colors.red.shade300 : Colors.red,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context)!.deleteAccount,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: textCol,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                ],
              ),

              // Scrollable Content
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      const SizedBox(height: 20),

                      // Warning Message - larger text
                      Text(
                        AppLocalizations.of(context)!.deleteAccountWarning,
                        style: TextStyle(
                          fontSize: 17,
                          color: textCol.withOpacity(0.7),
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),

                      // Password Input - modern design
                      TradeRepublicTextField(
                        controller: passwordController,
                        obscureText: true,
                        enabled: !isLoading,
                        hintText: AppLocalizations.of(
                          context,
                        )!.enterPasswordToConfirm,
                        prefixIcon: Icon(CupertinoIcons.lock_fill, size: 20),
                      ),
                      const SizedBox(height: 24),

                      // Delete Button
                      TradeRepublicButton(
                        label: isLoading
                            ? AppLocalizations.of(context)!.deleting
                            : AppLocalizations.of(context)!.deleteMyAccount,
                        onPressed: isLoading
                            ? null
                            : () async {
                                if (passwordController.text.isEmpty) {
                                  _showInfo(
                                    AppLocalizations.of(
                                      context,
                                    )!.enterYourPassword,
                                  );
                                  return;
                                }

                                setModalState(() {
                                  isLoading = true;
                                });

                                try {
                                  final result = await ApiService.deleteAccount(
                                    password: passwordController.text,
                                  );

                                  if (result['success'] == true) {
                                    if (context.mounted) {
                                      Navigator.of(context).pop();
                                    }

                                    await _clearStoredCredentials();

                                    setState(() {
                                      _isLoggedIn = false;
                                      _userName = '';
                                      _userUsername = '';
                                      _userEmail = '';
                                    });

                                    _showInfo(
                                      AppLocalizations.of(
                                        context,
                                      )!.accountDeletedSuccess,
                                    );

                                    _pageController.jumpToPage(0);
                                  } else {
                                    _showInfo(
                                      result['message'] ??
                                          AppLocalizations.of(
                                            context,
                                          )!.failedToDeleteAccount,
                                    );
                                  }
                                } catch (e) {
                                  _showInfo('Error: ${e.toString()}');
                                } finally {
                                  if (mounted) {
                                    setModalState(() {
                                      isLoading = false;
                                    });
                                  }
                                }
                              },
                        isDestructive: true,
                        width: double.infinity,
                        height: 56,
                      ),
                      const SizedBox(height: 12),

                      // Cancel Button
                      TradeRepublicButton(
                        label: AppLocalizations.of(context)!.cancel,
                        onPressed: isLoading
                            ? null
                            : () {
                                Navigator.of(context).pop();
                              },
                        isSecondary: true,
                        width: double.infinity,
                        height: 56,
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Returns the display label for a desktop tab based on the page index.
  String _getDesktopTabLabel(int pageIndex) {
    final loc = AppLocalizations.of(context)!;
    if (!_isLoggedIn) {
      return pageIndex == 0 ? loc.home : loc.profile;
    }
    if (pageIndex == 1) return loc.orders;
    if (pageIndex == 2) return loc.messages;
    if (pageIndex == 3) return loc.favorites;
    if (pageIndex == 4) return loc.account;
    return loc.home;
  }

  /// Returns the icon for a desktop tab based on the page index.
  IconData _getDesktopTabIcon(int pageIndex) {
    if (!_isLoggedIn) {
      return pageIndex == 0
          ? CupertinoIcons.house_fill
          : CupertinoIcons.person_fill;
    }
    if (pageIndex == 1) return CupertinoIcons.doc_text_fill;
    if (pageIndex == 2) return CupertinoIcons.chat_bubble_fill;
    if (pageIndex == 3) return CupertinoIcons.heart_fill;
    if (pageIndex == 4) return CupertinoIcons.person_fill;
    return CupertinoIcons.house_fill;
  }

  Widget _buildMacOSSidebar(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.transparent : const Color(0xFFFFFFFF),
      ),
      child: SafeArea(
        right: false,
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 32, 8, 10),
              child: Center(
                child: Image.asset(
                  isDark
                      ? 'logo/cultioo_3_logo_white.png'
                      : 'logo/cultioo_3_logo_dark.png',
                  height: 36,
                  fit: BoxFit.fitHeight,
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(6, 16, 6, 12),
                children: [
                  if (_isLoggedIn) ...[
                    _buildSidebarItem(
                      0,
                      isDark,
                      CupertinoIcons.home,
                      CupertinoIcons.house_fill,
                      AppLocalizations.of(context)!.home,
                    ),
                    _buildSidebarItem(
                      1,
                      isDark,
                      CupertinoIcons.doc_text,
                      CupertinoIcons.doc_text_fill,
                      AppLocalizations.of(context)!.orders,
                    ),
                    _buildSidebarItem(
                      2,
                      isDark,
                      CupertinoIcons.chat_bubble,
                      CupertinoIcons.chat_bubble_fill,
                      AppLocalizations.of(context)!.messages,
                    ),
                    _buildSidebarItem(
                      3,
                      isDark,
                      CupertinoIcons.heart,
                      CupertinoIcons.heart_fill,
                      AppLocalizations.of(context)!.favorites,
                    ),
                    _buildSidebarItem(
                      4,
                      isDark,
                      CupertinoIcons.person,
                      CupertinoIcons.person_fill,
                      AppLocalizations.of(context)!.account,
                    ),
                  ] else ...[
                    _buildSidebarItem(
                      0,
                      isDark,
                      CupertinoIcons.home,
                      CupertinoIcons.house_fill,
                      AppLocalizations.of(context)!.home,
                    ),
                    _buildSidebarItem(
                      1,
                      isDark,
                      CupertinoIcons.person,
                      CupertinoIcons.person_fill,
                      AppLocalizations.of(context)!.profile,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarItem(
    int index,
    bool isDark,
    IconData inactiveIcon,
    IconData activeIcon,
    String label,
  ) {
    final isSelected = _tabIndex == index;
    final selBg = TradeRepublicTheme.selectionContainerBackground(context);
    final selFg = TradeRepublicTheme.selectionContainerForeground(context);
    final muted = isDark
        ? Colors.white.withOpacity(0.72)
        : Colors.black.withOpacity(0.62);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Tooltip(
        message: label,
        waitDuration: const Duration(milliseconds: 400),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              final maxPage = _isLoggedIn ? 4 : 1;
              final targetPage = index.clamp(0, maxPage);
              setState(() {
                _tabIndex = targetPage;
                _currentPage = targetPage;
                if (_activeDesktopTab >= 0 &&
                    _activeDesktopTab < _desktopTabPages.length) {
                  _desktopTabPages[_activeDesktopTab] = targetPage;
                }
              });
              _pageController.jumpToPage(targetPage);
            },
            borderRadius: BorderRadius.circular(10),
            hoverColor: isDark
                ? Colors.white.withOpacity(0.05)
                : Colors.black.withOpacity(0.05),
            splashColor: isDark
                ? Colors.white.withOpacity(0.10)
                : Colors.black.withOpacity(0.08),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? selBg : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Icon(
                  isSelected ? activeIcon : inactiveIcon,
                  size: 22,
                  color: isSelected ? selFg : muted,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Build page with fade animation
  Widget _buildPageWithAnimation(Widget page, int pageIndex) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(pageIndex),
      duration: const Duration(milliseconds: 400),
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - value)),
            child: child,
          ),
        );
      },
      child: page,
    );
  }

  Widget _buildDesktopTopNavigation(bool isDark) {
    final maxPage = _isLoggedIn ? 4 : 1;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        CultiooDesktopLayout.topBarHorizontal,
        CultiooDesktopLayout.topBarVertical,
        CultiooDesktopLayout.topBarHorizontal,
        CultiooDesktopLayout.topBarVertical,
      ),
      decoration: const BoxDecoration(),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(_desktopTabPages.length, (i) {
                  final isSelected = _activeDesktopTab == i;
                  final isInSplit =
                      _isDesktopSplitView &&
                      (i == _desktopSplitLeftTab || i == _desktopSplitRightTab);
                  final pageIdx = _desktopTabPages[i].clamp(0, maxPage);
                  final label = _getDesktopTabLabel(pageIdx);
                  final tabIcon = _getDesktopTabIcon(pageIdx);

                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: DragTarget<int>(
                      onWillAcceptWithDetails: (details) => details.data != i,
                      onAcceptWithDetails: (details) {
                        _startDesktopSplit(details.data, i);
                      },
                      builder: (context, candidateData, rejectedData) {
                        return LongPressDraggable<int>(
                          data: i,
                          feedback: Material(
                            color: Colors.transparent,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: (isDark ? Colors.white : Colors.black)
                                    .withOpacity(0.16),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                label,
                                style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          childWhenDragging: Opacity(
                            opacity: 0.45,
                            child: _buildDesktopTabChip(
                              isDark: isDark,
                              label: label,
                              isSelected: isSelected,
                              isInSplit: isInSplit,
                              highlightDrop: false,
                              pageIcon: tabIcon,
                              onTap: () {
                                final maxPage = _isLoggedIn ? 4 : 1;
                                final page = _desktopTabPages[i].clamp(
                                  0,
                                  maxPage,
                                );
                                setState(() {
                                  _activeDesktopTab = i;
                                  _currentPage = page;
                                  _tabIndex = page;
                                });
                                _pageController.jumpToPage(page);
                              },
                              onShowActions: () {
                                final maxPage = _isLoggedIn ? 4 : 1;
                                final page = _desktopTabPages[i].clamp(
                                  0,
                                  maxPage,
                                );
                                setState(() {
                                  _activeDesktopTab = i;
                                  _currentPage = page;
                                  _tabIndex = page;
                                });
                                _pageController.jumpToPage(page);
                                _showDesktopTabActions(i, isDark);
                              },
                              onClose: _desktopTabPages.length > 1
                                  ? () => _closeDesktopTab(i)
                                  : null,
                            ),
                          ),
                          child: _buildDesktopTabChip(
                            isDark: isDark,
                            label: label,
                            isSelected: isSelected,
                            isInSplit: isInSplit,
                            highlightDrop: candidateData.isNotEmpty,
                            pageIcon: tabIcon,
                            onTap: () {
                              final maxPage = _isLoggedIn ? 4 : 1;
                              final page = _desktopTabPages[i].clamp(
                                0,
                                maxPage,
                              );
                              setState(() {
                                _activeDesktopTab = i;
                                _currentPage = page;
                                _tabIndex = page;
                              });
                              _pageController.jumpToPage(page);
                            },
                            onShowActions: () {
                              final maxPage = _isLoggedIn ? 4 : 1;
                              final page = _desktopTabPages[i].clamp(
                                0,
                                maxPage,
                              );
                              setState(() {
                                _activeDesktopTab = i;
                                _currentPage = page;
                                _tabIndex = page;
                              });
                              _pageController.jumpToPage(page);
                              _showDesktopTabActions(i, isDark);
                            },
                            onClose: _desktopTabPages.length > 1
                                ? () => _closeDesktopTab(i)
                                : null,
                          ),
                        );
                      },
                    ),
                  );
                }),
              ),
            ),
          ),
          if (_isDesktopSplitView)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: (isDark ? Colors.white : Colors.black).withOpacity(
                    0.10,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Split',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
              ),
            ),
          Tooltip(
            message: AppLocalizations.of(context)!.refresh,
            child: TradeRepublicButton.icon(
              icon: Icon(
                CupertinoIcons.refresh,
                size: 17,
                color: isDark ? Colors.white : Colors.black,
              ),
              size: 36,
              isSecondary: true,
              onPressed: () async {
                await _refreshCurrentDesktopPage();
              },
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: AppLocalizations.of(context)!.add,
            child: TradeRepublicButton.icon(
              icon: Icon(
                CupertinoIcons.add,
                size: 17,
                color: isDark ? Colors.white : Colors.black,
              ),
              size: 36,
              isSecondary: true,
              onPressed: () {
                final currentTabPage = _desktopTabPages.isNotEmpty
                    ? _desktopTabPages[_activeDesktopTab].clamp(0, maxPage)
                    : _currentPage.clamp(0, maxPage);
                setState(() {
                  _desktopTabPages.add(currentTabPage);
                  _activeDesktopTab = _desktopTabPages.length - 1;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _refreshCurrentDesktopPage() async {
    final maxPage = _isLoggedIn ? 4 : 1;
    final page = _currentPage.clamp(0, maxPage);

    switch (page) {
      case 0:
        await _refreshHomePage();
        break;
      case 1:
        setState(() {
          _ordersFuture = _loadOrdersWithSync();
        });
        await _ordersFuture;
        break;
      case 3:
        if (_isLoggedIn) {
          await _loadFavoritesFromServer();
          await _loadFollowedUsersFromServer();
        } else {
          await _loadFavoritesFromPrefs();
        }
        break;
      case 4:
        if (_isLoggedIn) {
          await _loadRealData();
        }
        break;
      case 2:
      default:
        setState(() {});
        break;
    }
  }

  Widget _buildDesktopTabChip({
    required bool isDark,
    required String label,
    required bool isSelected,
    required bool isInSplit,
    required bool highlightDrop,
    required VoidCallback onTap,
    required VoidCallback onShowActions,
    VoidCallback? onClose,
    IconData? pageIcon,
  }) {
    final unselectedColor = isDark ? Colors.white70 : Colors.black54;
    final borderRadius = BorderRadius.circular(10);
    final ink = isDark ? Colors.white : Colors.black;
    final selBg = TradeRepublicTheme.selectionContainerBackground(context);
    final selFg = TradeRepublicTheme.selectionContainerForeground(context);

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        onDoubleTap: onShowActions,
        onSecondaryTap: onShowActions,
        borderRadius: borderRadius,
        hoverColor: ink.withValues(alpha: 0.07),
        splashColor: ink.withValues(alpha: 0.12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: highlightDrop
                ? ink.withValues(alpha: 0.2)
                : isSelected
                    ? selBg
                    : ink.withValues(alpha: 0.04),
            borderRadius: borderRadius,
          ),
          child: Row(
            children: [
              Icon(
                isInSplit
                    ? CupertinoIcons.rectangle_split_3x1_fill
                    : (pageIcon ?? CupertinoIcons.house_fill),
                size: 15,
                color: isSelected ? selFg : unselectedColor,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? selFg : unselectedColor,
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

  Widget _buildDesktopPageByIndex(int pageIndex, bool isDark) {
    if (_isLoggedIn) {
      switch (pageIndex.clamp(0, 4)) {
        case 0:
          return _buildHomePage(isDark);
        case 1:
          return _buildOrdersPage(isDark);
        case 2:
          return _buildMessagesPage(isDark);
        case 3:
          return _buildFavouritesPage(isDark);
        case 4:
        default:
          return _buildAccountPage(isDark);
      }
    }

    return pageIndex <= 0 ? _buildHomePage(isDark) : _buildAccountPage(isDark);
  }

  void _startDesktopSplit(int sourceTab, int targetTab) {
    if (sourceTab == targetTab) {
      final partner = _firstOtherDesktopTabIndex(targetTab);
      if (partner == -1) return;
      sourceTab = partner;
    }
    setState(() {
      _isDesktopSplitView = true;
      _desktopSplitLeftTab = targetTab;
      _desktopSplitRightTab = sourceTab;
      _activeDesktopTab = sourceTab;
      _desktopSplitRatio = 0.5;
    });
  }

  int _firstOtherDesktopTabIndex(int tabIndex) {
    for (var i = 0; i < _desktopTabPages.length; i++) {
      if (i != tabIndex) return i;
    }
    return -1;
  }

  void _closeDesktopTab(int tabIndex) {
    if (_desktopTabPages.length <= 1) return;

    setState(() {
      _desktopTabPages.removeAt(tabIndex);

      if (_activeDesktopTab >= _desktopTabPages.length) {
        _activeDesktopTab = _desktopTabPages.length - 1;
      }

      if (_isDesktopSplitView) {
        if (_desktopSplitLeftTab == tabIndex ||
            _desktopSplitRightTab == tabIndex) {
          _isDesktopSplitView = false;
        } else {
          if (_desktopSplitLeftTab > tabIndex) _desktopSplitLeftTab -= 1;
          if (_desktopSplitRightTab > tabIndex) _desktopSplitRightTab -= 1;
        }
      }

      final maxPage = _isLoggedIn ? 4 : 1;
      final nextPage = _desktopTabPages[_activeDesktopTab].clamp(0, maxPage);
      _currentPage = nextPage;
      _tabIndex = nextPage;
    });

    _pageController.jumpToPage(_currentPage);
  }

  void _showDesktopTabActions(int tabIndex, bool isDark) {
    final maxPage = _isLoggedIn ? 4 : 1;
    final page = _desktopTabPages[tabIndex].clamp(0, maxPage);

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      maxHeight: 340,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TradeRepublicListTile.navigation(
              title: AppLocalizations.of(context)!.openTab,
              leading: const Icon(
                CupertinoIcons.arrow_right_circle_fill,
                size: 18,
              ),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _activeDesktopTab = tabIndex;
                  _currentPage = page;
                  _tabIndex = page;
                });
                _pageController.jumpToPage(page);
              },
            ),
            TradeRepublicListTile.navigation(
              title: AppLocalizations.of(context)!.splitLeft,
              leading: const Icon(CupertinoIcons.rectangle_split_3x1, size: 18),
              onTap: () {
                Navigator.pop(context);
                final partner = _firstOtherDesktopTabIndex(tabIndex);
                if (partner == -1) {
                  TopNotification.info(
                    context,
                    'Create at least 2 tabs for split screen',
                  );
                  return;
                }
                setState(() {
                  _isDesktopSplitView = true;
                  _desktopSplitLeftTab = tabIndex;
                  _desktopSplitRightTab = partner;
                  _desktopSplitRatio = 0.5;
                });
              },
            ),
            TradeRepublicListTile.navigation(
              title: AppLocalizations.of(context)!.splitRight,
              leading: const Icon(
                CupertinoIcons.rectangle_split_3x1_fill,
                size: 18,
              ),
              onTap: () {
                Navigator.pop(context);
                final partner = _firstOtherDesktopTabIndex(tabIndex);
                if (partner == -1) {
                  TopNotification.info(
                    context,
                    'Create at least 2 tabs for split screen',
                  );
                  return;
                }
                setState(() {
                  _isDesktopSplitView = true;
                  _desktopSplitLeftTab = partner;
                  _desktopSplitRightTab = tabIndex;
                  _desktopSplitRatio = 0.5;
                });
              },
            ),
            if (_isDesktopSplitView)
              TradeRepublicListTile.navigation(
                title: AppLocalizations.of(context)!.exitSplitScreen,
                leading: const Icon(CupertinoIcons.rectangle, size: 18),
                onTap: () {
                  Navigator.pop(context);
                  setState(() => _isDesktopSplitView = false);
                },
              ),
            if (_desktopTabPages.length > 1)
              TradeRepublicListTile.destructive(
                title: AppLocalizations.of(context)!.closeTab,
                leading: const Icon(CupertinoIcons.xmark_circle_fill, size: 18),
                onTap: () {
                  Navigator.pop(context);
                  _closeDesktopTab(tabIndex);
                },
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopSplitView(bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const dividerWidth = 12.0;
        final availableWidth = constraints.maxWidth - dividerWidth;
        final leftWidth = availableWidth * _desktopSplitRatio;
        final rightWidth = availableWidth - leftWidth;

        return Row(
          children: [
            SizedBox(
              width: leftWidth,
              child: _buildDesktopPageByIndex(
                _desktopTabPages[_desktopSplitLeftTab],
                isDark,
              ),
            ),
            MouseRegion(
              cursor: SystemMouseCursors.resizeLeftRight,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: (details) {
                  final nextRatio =
                      (_desktopSplitRatio +
                              (details.delta.dx / constraints.maxWidth))
                          .clamp(0.25, 0.75);
                  setState(() {
                    _desktopSplitRatio = nextRatio;
                  });
                },
                child: Container(
                  width: dividerWidth,
                  color: Colors.transparent,
                  child: Center(
                    child: Container(
                      width: 4,
                      height: 72,
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withOpacity(0.16)
                            : Colors.black.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: rightWidth,
              child: _buildDesktopPageByIndex(
                _desktopTabPages[_desktopSplitRightTab],
                isDark,
              ),
            ),
          ],
        );
      },
    );
  }

  /// Centered desktop workspace: one flat surface (tabs + PageView / split).
  Widget _buildDesktopMainWorkspace(bool isDark) {
    final canvas =
        isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
    final r = CultiooDesktopLayout.mainSurfaceRadius;

    return LayoutBuilder(
      builder: (context, constraints) {
        final span = min(
          CultiooDesktopLayout.mainColumnMaxWidth,
          constraints.maxWidth,
        );
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: span,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: canvas,
                borderRadius: BorderRadius.circular(r),
                border: CultiooDesktopLayout.workspaceFrameBorder(context),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(r),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildDesktopTopNavigation(isDark),
                    Expanded(
                      child:
                          _isDesktopSplitView &&
                              _desktopSplitLeftTab <
                                  _desktopTabPages.length &&
                              _desktopSplitRightTab <
                                  _desktopTabPages.length &&
                              _desktopSplitLeftTab != _desktopSplitRightTab
                          ? _buildDesktopSplitView(isDark)
                          : PageView(
                              controller: _pageController,
                              physics: const NeverScrollableScrollPhysics(),
                              onPageChanged: (pageIndex) {
                                setState(() {
                                  _currentPage = pageIndex;
                                  if (_activeDesktopTab >= 0 &&
                                      _activeDesktopTab <
                                          _desktopTabPages.length) {
                                    _desktopTabPages[_activeDesktopTab] =
                                        pageIndex;
                                  }
                                  if (_isLoggedIn && pageIndex < 5) {
                                    _tabIndex = pageIndex;
                                  } else if (!_isLoggedIn && pageIndex < 3) {
                                    _tabIndex = pageIndex;
                                  }
                                });
                              },
                              children: _isLoggedIn
                                  ? [
                                      _buildHomePage(isDark),
                                      _buildOrdersPage(isDark),
                                      _buildMessagesPage(isDark),
                                      _buildFavouritesPage(isDark),
                                      _buildAccountPage(isDark),
                                    ]
                                  : [
                                      _buildHomePage(isDark),
                                      _buildAccountPage(isDark),
                                    ],
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
  }

  /// Desktop max content width for professional layout
  static const double _desktopMaxContentWidth =
      CultiooDesktopLayout.splitMaxContentWidth;

  /// Whether the current platform is a desktop with a wide screen
  bool get _isWideScreen {
    final width = MediaQuery.of(context).size.width;
    return (defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux) &&
        width > 900;
  }

  /// Calculates responsive grid column count based on available width
  int _responsiveGridColumns(double availableWidth) {
    if (availableWidth > 1200) return 5;
    if (availableWidth > 900) return 4;
    if (availableWidth > 600) return 3;
    return 2;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Use desktop layout on computer (macOS, Windows, Linux)
    if (defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux) {
      return Scaffold(
        backgroundColor: isDark
            ? const Color(0xFF000000)
            : const Color(0xFFFFFFFF),
        body: MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: CultiooDesktopLayout.desktopUiTextScaler(context),
          ),
          child: Stack(
            children: [
              Row(
                children: [
                _showSplashScreen
                    ? AnimatedContainer(
                        duration: const Duration(milliseconds: 600),
                        curve: Curves.easeInOutCubic,
                        width: _sidebarWidth,
                        child: _sidebarWidth == 0
                            ? Container()
                            : _buildMacOSSidebar(isDark),
                      )
                    : Expanded(
                        // Outer [Row] passes unbounded max width to non-flex children; this
                        // [Expanded] gives the inner [Row] a finite width so its [Expanded]
                        // main workspace is valid (see RenderFlex unbounded + flex assert).
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 260),
                              curve: Curves.easeOutCubic,
                              width: _desktopSidebarOuterWidth,
                              child: _buildMacOSSidebar(isDark),
                            ),
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.fromLTRB(
                                  CultiooDesktopLayout.windowHorizontalGutter,
                                  MediaQuery.viewPaddingOf(context).top + 4,
                                  6,
                                  max(10.0, MediaQuery.paddingOf(context).bottom),
                                ),
                                child: _buildDesktopMainWorkspace(isDark),
                              ),
                            ),
                          ],
                        ),
                      ),
                if (!_showSplashScreen) ...[
                  Padding(
                    padding: EdgeInsets.only(
                      right: MediaQuery.paddingOf(context).right,
                    ),
                    child: CultiooDesktopSheetNavigator.buildPanelHost(
                      width: _desktopRightPanelWidth,
                      isDark: isDark,
                    ),
                  ),
                ],
              ],
              ),
              if (_showSplashScreen)
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 600),
                  opacity: _splashOpacity,
                  child: Container(
                    color: isDark
                        ? const Color(0xFF000000)
                        : const Color(0xFFFFFFFF),
                    child: Center(
                      child: AnimatedScale(
                        duration: const Duration(milliseconds: 600),
                        scale: _logoScale,
                        curve: Curves.easeInOutCubic,
                        child: Image.asset(
                          isDark
                              ? 'logo/cultioo_word_transparent_darkmode.png'
                              : 'logo/cultioo_word_transparent_whitemode.png',
                          height: 140,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    // Always show the main app - authentication happens via modals
    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF000000)
          : const Color(0xFFFFFFFF),
      extendBody: true,
      body: Stack(
        children: [
          // Main content
          PageView(
            controller: _pageController,
            onPageChanged: (pageIndex) {
              if (_currentPage != pageIndex) {
                setState(() {
                  _currentPage = pageIndex;
                  _tabIndex = pageIndex;
                });
              }
            },
            children: _isLoggedIn
                ? [
                    _buildPageWithAnimation(_buildHomePage(isDark), 0),
                    _buildPageWithAnimation(_buildOrdersPage(isDark), 1),
                    _buildPageWithAnimation(_buildMessagesPage(isDark), 2),
                    _buildPageWithAnimation(_buildFavouritesPage(isDark), 3),
                    _buildPageWithAnimation(_buildAccountPage(isDark), 4),
                  ]
                : [
                    _buildPageWithAnimation(_buildHomePage(isDark), 0),
                    _buildPageWithAnimation(_buildAccountPage(isDark), 1),
                  ],
          ),
          if (_isDockEnabled && !_hideTabBar && !_isModalOpen)
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.of(context).padding.bottom + 2,
              child: Center(
                child: PageIndicator(
                  currentPage: _currentPage,
                  pageCount: _isLoggedIn ? 5 : 2,
                  pageController: _pageController,
                  onTap: (i) {
                    if (_tabIndex == i) return;
                    HapticFeedback.mediumImpact();
                    setState(() {
                      _tabIndex = i;
                      _currentPage = i;
                    });
                    _pageController.jumpToPage(i);
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Loading screen for auto-login
  // Removed _buildLoadingScreen method to prevent lag

  // Modern Login Screen
  // Removed _buildLoginScreen method to prevent lag

  Widget _buildSystemPage(bool isDark) {
    return SingleChildScrollView(
      padding: CultiooDesktopLayout.pageContentPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Text(
            'System',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF1C1C1E),
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 24),

          // Appearance Section
          _buildGlassSection(
            isDark: isDark,
            title: AppLocalizations.of(context)!.appearance,
            children: [
              _buildSettingsItem(
                isDark: isDark,
                icon: CupertinoIcons.paintbrush,
                title: AppLocalizations.of(context)!.theme,
                subtitle: _getThemeDisplayName(),
                onTap: () => _showThemeSelector(isDark),
              ),
              _buildSettingsItem(
                isDark: isDark,
                icon: CupertinoIcons.textformat,
                title: AppLocalizations.of(context)!.textSize,
                subtitle: _getTextSizeDisplayName(),
                onTap: () => _showTextSizeSelector(isDark),
              ),
              _buildSettingsItem(
                isDark: isDark,
                icon: CupertinoIcons.globe,
                title: AppLocalizations.of(context)!.language,
                subtitle: _getLanguageDisplayName(),
                onTap: () => _showLanguageSelector(isDark),
              ),
              _buildSettingsItem(
                isDark: isDark,
                icon: CupertinoIcons.number,
                title: AppLocalizations.of(context)!.numberFormat,
                subtitle: _getNumberFormatDisplayName(),
                onTap: () => _showNumberFormatSelector(isDark),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Interface Section
          _buildGlassSection(
            isDark: isDark,
            title: AppLocalizations.of(context)!.interface_,
            children: [_buildDockToggleItem(isDark)],
          ),
          const SizedBox(height: 20),

          // Support Section
          _buildGlassSection(
            isDark: isDark,
            title: AppLocalizations.of(context)!.support,
            children: [
              _buildSettingsItem(
                isDark: isDark,
                icon: CupertinoIcons.question_circle,
                title: AppLocalizations.of(context)!.helpCenter,
                subtitle: AppLocalizations.of(context)!.getHelp,
                onTap: () => _showInfo(
                  AppLocalizations.of(context)!.helpCenterComingSoon,
                ),
              ),
              _buildSettingsItem(
                isDark: isDark,
                icon: CupertinoIcons.chat_bubble_text,
                title: AppLocalizations.of(context)!.sendFeedback,
                subtitle: AppLocalizations.of(context)!.shareYourThoughts,
                onTap: () => _showInfo(
                  AppLocalizations.of(context)!.feedbackFormComingSoon,
                ),
              ),
              _buildSettingsItem(
                isDark: isDark,
                icon: CupertinoIcons.info_circle,
                title: AppLocalizations.of(context)!.about,
                subtitle: AppLocalizations.of(context)!.versionInfo,
                onTap: () =>
                    _showInfo(AppLocalizations.of(context)!.versionInfo),
              ),
            ],
          ),

          // Bottom spacing to allow content to flow behind dock
          const SizedBox(height: 120),
        ],
      ),
    );
  }

  Widget _buildHomePage(bool isDark) {
    return CustomScrollView(
      controller: _scrollController,
      cacheExtent: 120,
      physics: CultiooDesktopLayout.adaptiveScrollPhysics(context),
      slivers: [
        if (!CultiooDesktopLayout.isDesktopPlatform)
          CultiooSliverRefreshControl(
            onRefresh: () async {
              await _refreshHomePage();
            },
          ),

        // Lightweight header (no runtime animation)
        SliverToBoxAdapter(
          child: Padding(
            padding: CultiooDesktopLayout.pageContentPadding(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: CultiooDesktopLayout.isDesktopPlatform ? 8 : 20),
                Row(
                  children: [
                    Icon(
                      CupertinoIcons.bag_fill,
                      color: isDark ? Colors.white : Colors.black,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        '${AppLocalizations.of(context)!.welcomeBack}${_userUsername.isNotEmpty ? ', @$_userUsername' : ''}!',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : Colors.black,
                          letterSpacing: -0.5,
                          height: 1.2,
                        ),
                        softWrap: true,
                        maxLines: 2,
                        overflow: TextOverflow.fade,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  AppLocalizations.of(context)!.discoverFreshProducts,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark
                        ? Colors.white.withOpacity(0.7)
                        : Colors.black.withOpacity(0.6),
                    letterSpacing: 0.2,
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),

        SliverAppBar(
          floating: true,
          pinned: true,
          snap: false,
          backgroundColor: CultiooDesktopLayout.isDesktopPlatform
              ? CultiooDesktopLayout.contentCanvasColor(isDark)
              : (isDark ? const Color(0xFF000000) : Colors.white),
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          scrolledUnderElevation: 0,
          elevation: 0,
          automaticallyImplyLeading: false,
          toolbarHeight: 72,
          titleSpacing: 0,
          title: Container(
            color: CultiooDesktopLayout.isDesktopPlatform
                ? CultiooDesktopLayout.contentCanvasColor(isDark)
                : (isDark ? const Color(0xFF000000) : Colors.white),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                height: 62,
                child: Row(
                  children: [
                    Expanded(child: _buildSearchBar(isDark)),
                    const SizedBox(width: 12),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      width: (_isSearchExpanded == true)
                          ? 0.0
                          : (_isLoggedIn ? 170.0 : 74.0),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 180),
                        opacity: (_isSearchExpanded == true) ? 0.0 : 1.0,
                        child: ClipRect(
                          child: OverflowBox(
                            maxWidth: 200,
                            alignment: Alignment.centerRight,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildCategoriesButton(isDark),
                                if (_isLoggedIn) ...[
                                  const SizedBox(width: 8),
                                  _buildHeaderCartButton(isDark),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Filters row (no animation, better scroll perf)
        SliverToBoxAdapter(
          child: Container(
            height: 46,
            margin: EdgeInsets.only(
              left: CultiooDesktopLayout.mainHorizontalPadding,
              right: CultiooDesktopLayout.mainHorizontalPadding,
              top: CultiooDesktopLayout.isDesktopPlatform ? 14 : 20,
              bottom: CultiooDesktopLayout.isDesktopPlatform ? 14 : 20,
            ),
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                TradeRepublicButton(
                  label: _searchRadius >= 9999
                      ? AppLocalizations.of(context)!.allLocations
                      : _resolveDistanceUnit() == 'miles'
                      ? '${(_searchRadius * 0.621371).toInt()} mi'
                      : '${_searchRadius.toInt()} km',
                  icon: const Icon(CupertinoIcons.location, size: 16),
                  isSecondary: true,
                  height: 44,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    _showRadiusSettings(isDark);
                  },
                ),
                const SizedBox(width: 12),
                _buildSortChip(
                  AppLocalizations.of(context)!.sortAZ,
                  'name_asc',
                  isDark,
                ),
                const SizedBox(width: 12),
                _buildSortChip(
                  AppLocalizations.of(context)!.sortZA,
                  'name_desc',
                  isDark,
                ),
                const SizedBox(width: 12),
                _buildSortChip(
                  AppLocalizations.of(context)!.unit,
                  'unit',
                  isDark,
                ),
                const SizedBox(width: 12),
                _buildSortChip(
                  AppLocalizations.of(context)!.lowPrice,
                  'price_asc',
                  isDark,
                ),
                const SizedBox(width: 12),
                _buildSortChip(
                  AppLocalizations.of(context)!.highPrice,
                  'price_desc',
                  isDark,
                ),
                const SizedBox(width: 12),
                _buildIncotermsButton(isDark),
              ],
            ),
          ),
        ),

        if (_isLoadingProducts)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(60, 60, 60, 140),
              child: Column(
                children: [
                  CultiooLoadingIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    AppLocalizations.of(context)!.loadingProducts,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          )
        else if (_filteredProducts.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(40, 60, 40, 140),
              child: Column(
                children: [
                  Icon(
                    CupertinoIcons.bag,
                    size: 54,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    AppLocalizations.of(context)!.noProductsFound,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    AppLocalizations.of(context)!.tryDifferentSearch,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(20, 30, 20, _isWideScreen ? 40 : 0),
            sliver: SliverLayoutBuilder(
              builder: (context, constraints) {
                final cols = _responsiveGridColumns(
                  constraints.crossAxisExtent,
                );
                final aspectRatio = cols >= 5
                    ? 0.84
                    : cols >= 4
                    ? 0.78
                    : cols >= 3
                    ? 0.72
                    : 0.86;
                final displayCount = _visibleProductCount.clamp(
                  0,
                  _filteredProducts.length,
                );

                return SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    childAspectRatio: aspectRatio,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      return RepaintBoundary(
                        child: _buildProductCard(
                          _filteredProducts[index],
                          isDark,
                        ),
                      );
                    },
                    childCount: displayCount,
                    addAutomaticKeepAlives: false,
                    addRepaintBoundaries: true,
                    addSemanticIndexes: false,
                  ),
                );
              },
            ),
          ),

        if (_filteredProducts.length > _visibleProductCount)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 140),
              child: TradeRepublicButton(
                label:
                    'Show more (${_filteredProducts.length - _visibleProductCount} remaining)',
                isSecondary: true,
                width: double.infinity,
                onPressed: () {
                  HapticFeedback.lightImpact();
                  setState(() {
                    _visibleProductCount += 10;
                  });
                },
              ),
            ),
          )
        else
          const SliverToBoxAdapter(child: SizedBox(height: 140)),
      ],
    );
  }

  Widget _buildSearchBar(bool isDark) {
    return SizedBox(
      height: 62.0,
      child: TradeRepublicTextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        hintText: AppLocalizations.of(context)!.searchProducts,
        prefixIcon: Icon(
          CupertinoIcons.search,
          size: 20,
          color: (isDark ? Colors.white : Colors.black).withOpacity(0.4),
        ),
        textInputAction: TextInputAction.search,
        textAlignVertical: TextAlignVertical.center,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        suffixIcon: _searchQuery.isNotEmpty
            ? GestureDetector(
                onTap: _clearSearch,
                child: Icon(
                  CupertinoIcons.clear_circled_solid,
                  size: 18,
                  color: (isDark ? Colors.white : Colors.black).withOpacity(
                    0.35,
                  ),
                ),
              )
            : null,
      ),
    );
  }

  Widget _buildSortButton(bool isDark) {
    return TradeRepublicButton(
      icon: Icon(
        CupertinoIcons.arrow_up_arrow_down,
        color: isDark
            ? Colors.white.withOpacity(0.8)
            : Colors.black.withOpacity(0.7),
        size: 22,
      ),
      isSecondary: true,
      onPressed: null, // Disabled - using horizontal sort chips instead
      width: 70,
      height: 70,
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(20),
    );
  }

  Widget _buildFilterButton(bool isDark) {
    return TradeRepublicButton(
      icon: Icon(
        CupertinoIcons.slider_horizontal_3,
        color: isDark
            ? Colors.white.withOpacity(0.8)
            : Colors.black.withOpacity(0.7),
        size: 22,
      ),
      isSecondary: true,
      onPressed: null, // Disabled - using horizontal sort chips instead
      width: 70,
      height: 70,
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(20),
    );
  }

  Widget _buildCategoriesButton(bool isDark) {
    final hasFilter = _selectedCategories.isNotEmpty;
    final btnSize = 62.0;
    return SizedBox(
      width: btnSize,
      height: btnSize,
      child: Stack(
        children: [
          TradeRepublicButton(
            icon: Icon(
              hasFilter
                  ? CupertinoIcons.square_grid_2x2_fill
                  : CupertinoIcons.square_grid_2x2,
            ),
            onPressed: () => _showCategoryModal(isDark),
            width: btnSize,
            height: btnSize,
            padding: EdgeInsets.zero,
            borderRadius: BorderRadius.circular(20),
          ),
          if (hasFilter)
            Positioned(
              right: 6,
              top: 6,
              child: Container(
                padding: const EdgeInsets.all(3),
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                decoration: BoxDecoration(
                  color: const Color(0xFF34C759),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDark ? Colors.black : Colors.white,
                    width: 1.5,
                  ),
                ),
                child: Text(
                  '${_selectedCategories.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    height: 1,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildIncotermsButton(bool isDark) {
    final hasFilter = _selectedIncoterms.isNotEmpty;
    final label = hasFilter
        ? 'Incoterm${_selectedIncoterms.length > 1 ? 's' : ''} (${_selectedIncoterms.length})'
        : 'Incoterms';
    return TradeRepublicButton(
      label: label,
      isSecondary: !hasFilter,
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      onPressed: () {
        HapticFeedback.lightImpact();
        _showIncotermsModal(isDark);
      },
    );
  }

  Widget _buildHeaderCartButton(bool isDark) {
    // Nur anzeigen wenn eingeloggt
    if (!_isLoggedIn) {
      return const SizedBox.shrink();
    }

    final btnSize = 62.0;
    return SizedBox(
      height: btnSize,
      width: btnSize,
      child: Stack(
        children: [
          TradeRepublicButton(
            icon: const Icon(CupertinoIcons.cart),
            onPressed: () => _showCartModal(isDark),
            width: btnSize,
            height: btnSize,
            padding: EdgeInsets.zero,
            borderRadius: BorderRadius.circular(20),
          ),
          if (_cartItemCount > 0)
            Positioned(
              right: 6,
              top: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white : Colors.black,
                  borderRadius: BorderRadius.circular(10),
                ),
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                child: Text(
                  _cartItemCount > 99 ? '99+' : _cartItemCount.toString(),
                  style: TextStyle(
                    color: isDark ? Colors.black : Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSortChip(String title, String value, bool isDark) {
    final isSelected = _sortOption == value;

    return TradeRepublicButton(
      label: title,
      isSecondary: !isSelected,
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      onPressed: () {
        HapticFeedback.lightImpact();
        setState(() {
          _sortOption = value;
        });
        _applySorting();
      },
    );
  }

  void _applySorting() {
    List<Map<String, dynamic>> sortedProducts = List.from(_filteredProducts);

    switch (_sortOption) {
      case 'price_asc':
        sortedProducts.sort(
          (a, b) => _getProductPrice(a).compareTo(_getProductPrice(b)),
        );
        break;
      case 'price_desc':
        sortedProducts.sort(
          (a, b) => _getProductPrice(b).compareTo(_getProductPrice(a)),
        );
        break;
      case 'name_asc':
        sortedProducts.sort(
          (a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''),
        );
        break;
      case 'name_desc':
        sortedProducts.sort(
          (a, b) => (b['name'] ?? '').compareTo(a['name'] ?? ''),
        );
        break;
      case 'unit':
        sortedProducts.sort((a, b) {
          final aVariants = a['variants'] as List<dynamic>?;
          final bVariants = b['variants'] as List<dynamic>?;
          final aUnit = (aVariants != null && aVariants.isNotEmpty)
              ? (aVariants[0]['unit'] ?? '')
              : '';
          final bUnit = (bVariants != null && bVariants.isNotEmpty)
              ? (bVariants[0]['unit'] ?? '')
              : '';
          return aUnit.toString().compareTo(bUnit.toString());
        });
        break;
    }

    setState(() {
      _filteredProducts = sortedProducts;
    });
  }

  void _showRadiusSettings(bool isDark) {
    setState(() => _isModalOpen = true);
    TradeRepublicBottomSheet.show(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      child: StatefulBuilder(
        builder: (context, setModalState) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Large radius value display
              Text(
                _searchRadius >= 9999
                    ? '∞'
                    : _resolveDistanceUnit() == 'miles'
                    ? '${(_searchRadius * 0.621371).toInt()}'
                    : '${_searchRadius.toInt()}',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 64,
                  fontWeight: FontWeight.w200,
                  color: isDark ? Colors.white : Colors.black,
                  letterSpacing: -2,
                ),
              ),
              Text(
                _searchRadius >= 9999
                    ? 'Everywhere'
                    : _resolveDistanceUnit() == 'miles'
                    ? 'miles'
                    : 'kilometers',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: isDark ? Colors.white38 : Colors.black38,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 40),

              // Minimal slider
              TradeRepublicValueSlider(
                value: _searchRadius >= 9999 ? 1610.0 : _searchRadius,
                min: 5.0,
                max: 1610.0,
                onChanged: (value) {
                  setModalState(() => _searchRadius = value);
                  setState(() => _searchRadius = value);
                  _filterProducts();
                },
              ),
              const SizedBox(height: 24),

              // Quick options as minimal text buttons
              Wrap(
                spacing: 16,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _buildMinimalRadiusOption(5, isDark, setModalState),
                  _buildMinimalRadiusOption(25, isDark, setModalState),
                  _buildMinimalRadiusOption(50, isDark, setModalState),
                  _buildMinimalRadiusOption(100, isDark, setModalState),
                  TradeRepublicButton(
                    label: AppLocalizations.of(context)!.all,
                    isSecondary: _searchRadius < 9999,
                    tint: _searchRadius >= 9999
                        ? (isDark ? Colors.white : Colors.black)
                        : null,
                    onPressed: () {
                      setModalState(() => _searchRadius = 9999);
                      setState(() => _searchRadius = 9999);
                      _filterProducts();
                      HapticFeedback.selectionClick();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    ).whenComplete(() {
      if (!mounted) return;
      setState(() => _isModalOpen = false);
    });
  }

  Widget _buildMinimalRadiusOption(
    int radius,
    bool isDark,
    StateSetter setModalState,
  ) {
    final isSelected = _searchRadius.toInt() == radius;
    final displayValue = _resolveDistanceUnit() == 'miles'
        ? '${(radius * 0.621371).toInt()}mi'
        : '${radius}km';
    return TradeRepublicButton(
      label: displayValue,
      isSecondary: !isSelected,
      onPressed: () {
        setModalState(() => _searchRadius = radius.toDouble());
        setState(() => _searchRadius = radius.toDouble());
        _filterProducts();
        HapticFeedback.selectionClick();
      },
    );
  }

  void _showIncotermsModal(bool isDark) {
    setState(() => _isModalOpen = true);
    final incoterms = _getAvailableIncoterms();
    TradeRepublicBottomSheet.show(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      child: StatefulBuilder(
        builder: (context, setModalState) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Incoterms',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Filter products by delivery terms',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white54 : Colors.black45,
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (incoterms.isEmpty)
                      Text(
                        'No incoterms available in current results',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                      )
                    else
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: incoterms.map((inc) {
                          final isSelected = _selectedIncoterms.contains(inc);
                          return GestureDetector(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              Future.microtask(() {
                                setState(() {
                                  if (isSelected) {
                                    _selectedIncoterms.remove(inc);
                                  } else {
                                    _selectedIncoterms.add(inc);
                                  }
                                });
                                setModalState(() {});
                                _filterProducts();
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? TradeRepublicTheme
                                        .selectionContainerBackground(context)
                                    : (isDark
                                          ? Colors.white.withOpacity(0.07)
                                          : Colors.black.withOpacity(0.05)),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                inc,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 14,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: isSelected
                                      ? TradeRepublicTheme
                                          .selectionContainerForeground(context)
                                      : (isDark ? Colors.white : Colors.black),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    if (_selectedIncoterms.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      TradeRepublicButton(
                        label: AppLocalizations.of(context)!.clearFilter,
                        isSecondary: true,
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          setState(() => _selectedIncoterms.clear());
                          setModalState(() {});
                          _filterProducts();
                        },
                      ),
                    ],
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ).whenComplete(() {
      if (!mounted) return;
      setState(() => _isModalOpen = false);
    });
  }

  String _getCategoryLocalizedName(String englishName) {
    if (englishName == AppLocalizations.of(context)!.allCategories) {
      return englishName;
    }
    final lang = _resolveLanguage();
    if (lang == 'en') return englishName;
    const Map<String, Map<String, String>> t = {
      'Fruits & Vegetables': {
        'de': 'Obst & Gemüse',
        'es': 'Frutas y Verduras',
        'fr': 'Fruits & Légumes',
        'ru': 'Фрукты и Овощи',
        'it': 'Frutta e Verdura',
        'pt': 'Frutas e Legumes',
        'pl': 'Owoce i Warzywa',
        'nl': 'Fruit & Groenten',
        'sv': 'Frukt & Grönsaker',
        'nb': 'Frukt & Grønnsaker',
        'da': 'Frugt & Grøntsager',
        'fi': 'Hedelmät & Vihannekset',
        'ro': 'Fructe & Legume',
        'el': 'Φρούτα & Λαχανικά',
        'bg': 'Плодове & Зеленчуци',
        'hr': 'Voće & Povrće',
        'sk': 'Ovocie & Zelenina',
        'cs': 'Ovoce & Zelenina',
        'hu': 'Gyümölcsök & Zöldségek',
        'lv': 'Augļi & Dārzeņi',
      },
      'Dairy & Eggs': {
        'de': 'Milch & Eier',
        'es': 'Lácteos y Huevos',
        'fr': 'Laitages & Œufs',
        'ru': 'Молочное и Яйца',
        'it': 'Latticini e Uova',
        'pt': 'Laticínios e Ovos',
        'pl': 'Nabiał i Jajka',
        'nl': 'Zuivel & Eieren',
        'sv': 'Mejeriprodukter & Ägg',
        'nb': 'Meieriprodukter & Egg',
        'da': 'Mejeriprodukter & Æg',
        'fi': 'Maitotuotteet & Munat',
        'ro': 'Lactate & Ouă',
        'el': 'Γαλακτοκομικά & Αυγά',
        'bg': 'Млечни продукти & Яйца',
        'hr': 'Mliječni Proizvodi & Jaja',
        'sk': 'Mliečne Výrobky & Vajcia',
        'cs': 'Mléčné Výrobky & Vejce',
        'hu': 'Tejtermékek & Tojás',
        'lv': 'Piena Produkti & Olas',
      },
      'Meat & Sausages': {
        'de': 'Fleisch & Wurst',
        'es': 'Carne y Embutidos',
        'fr': 'Viande & Charcuterie',
        'ru': 'Мясо и Колбасы',
        'it': 'Carne e Salumi',
        'pt': 'Carne e Enchidos',
        'pl': 'Mięso i Wędliny',
        'nl': 'Vlees & Worst',
        'sv': 'Kött & Chark',
        'nb': 'Kjøtt & Pølser',
        'da': 'Kød & Pølser',
        'fi': 'Liha & Makkara',
        'ro': 'Carne & Mezeluri',
        'el': 'Κρέας & Αλλαντικά',
        'bg': 'Месо & Колбаси',
        'hr': 'Meso & Kobasice',
        'sk': 'Mäso & Udeniny',
        'cs': 'Maso & Uzeniny',
        'hu': 'Hús & Felvágottak',
        'lv': 'Gaļa & Desas',
      },
      'Bakery Products': {
        'de': 'Backwaren',
        'es': 'Panadería',
        'fr': 'Boulangerie',
        'ru': 'Хлебобулочные',
        'it': 'Prodotti da Forno',
        'pt': 'Padaria',
        'pl': 'Pieczywo',
        'nl': 'Bakkerij',
        'sv': 'Bageriprodukter',
        'nb': 'Bakervarer',
        'da': 'Bagværk',
        'fi': 'Leipomotuotteet',
        'ro': 'Produse de Panificație',
        'el': 'Αρτοποιήματα',
        'bg': 'Хлебни изделия',
        'hr': 'Pekarski Proizvodi',
        'sk': 'Pekárenské Výrobky',
        'cs': 'Pekárenské Výrobky',
        'hu': 'Pékáruk',
        'lv': 'Maizes Izstrādājumi',
      },
      'Jams & Spreads': {
        'de': 'Marmeladen & Aufstriche',
        'es': 'Mermeladas y Untables',
        'fr': 'Confitures & Tartinades',
        'ru': 'Варенье и Пасты',
        'it': 'Marmellate e Creme',
        'pt': 'Compotas e Pastas',
        'pl': 'Dżemy i Pasty',
        'nl': 'Jam & Smeersel',
        'sv': 'Sylt & Pålägg',
        'nb': 'Syltetøy & Pålegg',
        'da': 'Syltetøj & Pålæg',
        'fi': 'Hillot & Levitteet',
        'ro': 'Gemuri & Creme',
        'el': 'Μαρμελάδες & Αλοιφές',
        'bg': 'Конфитюри & Намазки',
        'hr': 'Džemovi & Namazi',
        'sk': 'Džemy & Nátierky',
        'cs': 'Džemy & Pomazánky',
        'hu': 'Lekvárok & Krémek',
        'lv': 'Ievārījumi & Uzklājumi',
      },
      'Honey': {
        'de': 'Honig',
        'es': 'Miel',
        'fr': 'Miel',
        'ru': 'Мёд',
        'it': 'Miele',
        'pt': 'Mel',
        'pl': 'Miód',
        'nl': 'Honing',
        'sv': 'Honung',
        'nb': 'Honning',
        'da': 'Honning',
        'fi': 'Hunaja',
        'ro': 'Miere',
        'el': 'Μέλι',
        'bg': 'Мед',
        'hr': 'Med',
        'sk': 'Med',
        'cs': 'Med',
        'hu': 'Méz',
        'lv': 'Medus',
      },
      'Cereal Products': {
        'de': 'Getreideprodukte',
        'es': 'Productos de Cereales',
        'fr': 'Produits Céréaliers',
        'ru': 'Зерновые',
        'it': 'Prodotti Cerealicoli',
        'pt': 'Produtos de Cereais',
        'pl': 'Produkty Zbożowe',
        'nl': 'Graanproducten',
        'sv': 'Spannmålsprodukter',
        'nb': 'Kornprodukter',
        'da': 'Kornprodukter',
        'fi': 'Viljatuotteet',
        'ro': 'Produse Cerealiere',
        'el': 'Δημητριακά',
        'bg': 'Зърнени продукти',
        'hr': 'Žitarice',
        'sk': 'Obilné Výrobky',
        'cs': 'Obilné Výrobky',
        'hu': 'Gabonatermékek',
        'lv': 'Graudu Produkti',
      },
      'Beverages': {
        'de': 'Getränke',
        'es': 'Bebidas',
        'fr': 'Boissons',
        'ru': 'Напитки',
        'it': 'Bevande',
        'pt': 'Bebidas',
        'pl': 'Napoje',
        'nl': 'Dranken',
        'sv': 'Drycker',
        'nb': 'Drikke',
        'da': 'Drikkevarer',
        'fi': 'Juomat',
        'ro': 'Băuturi',
        'el': 'Ποτά',
        'bg': 'Напитки',
        'hr': 'Pića',
        'sk': 'Nápoje',
        'cs': 'Nápoje',
        'hu': 'Italok',
        'lv': 'Dzērieni',
      },
      'Spices & Oils': {
        'de': 'Gewürze & Öle',
        'es': 'Especias y Aceites',
        'fr': 'Épices & Huiles',
        'ru': 'Специи и Масла',
        'it': 'Spezie e Oli',
        'pt': 'Especiarias e Óleos',
        'pl': 'Przyprawy i Oleje',
        'nl': 'Kruiden & Oliën',
        'sv': 'Kryddor & Oljor',
        'nb': 'Krydder & Oljer',
        'da': 'Krydderier & Olier',
        'fi': 'Mausteet & Öljyt',
        'ro': 'Condimente & Uleiuri',
        'el': 'Μπαχαρικά & Λάδια',
        'bg': 'Подправки & Масла',
        'hr': 'Začini & Ulja',
        'sk': 'Koreniny & Oleje',
        'cs': 'Koření & Oleje',
        'hu': 'Fűszerek & Olajok',
        'lv': 'Garšvielas & Eļļas',
      },
      'Fish & Seafood': {
        'de': 'Fisch & Meeresfrüchte',
        'es': 'Pescado y Mariscos',
        'fr': 'Poisson & Fruits de Mer',
        'ru': 'Рыба и Морепродукты',
        'it': 'Pesce e Frutti di Mare',
        'pt': 'Peixe e Frutos do Mar',
        'pl': 'Ryby i Owoce Morza',
        'nl': 'Vis & Zeevruchten',
        'sv': 'Fisk & Skaldjur',
        'nb': 'Fisk & Sjømat',
        'da': 'Fisk & Skaldyr',
        'fi': 'Kala & Äyriäiset',
        'ro': 'Pește & Fructe de Mare',
        'el': 'Ψάρια & Θαλασσινά',
        'bg': 'Риба & Морски дарове',
        'hr': 'Riba & Plodovi Mora',
        'sk': 'Ryby & Morské Plody',
        'cs': 'Ryby & Mořské Plody',
        'hu': 'Hal & Tenger Gyümölcsei',
        'lv': 'Zivis & Jūras Veltes',
      },
      'Cheese': {
        'de': 'Käse',
        'es': 'Queso',
        'fr': 'Fromage',
        'ru': 'Сыр',
        'it': 'Formaggio',
        'pt': 'Queijo',
        'pl': 'Ser',
        'nl': 'Kaas',
        'sv': 'Ost',
        'nb': 'Ost',
        'da': 'Ost',
        'fi': 'Juusto',
        'ro': 'Brânză',
        'el': 'Τυρί',
        'bg': 'Сирене',
        'hr': 'Sir',
        'sk': 'Syr',
        'cs': 'Sýr',
        'hu': 'Sajt',
        'lv': 'Siers',
      },
      'Snacks & Sweets': {
        'de': 'Snacks & Süßigkeiten',
        'es': 'Snacks y Dulces',
        'fr': 'Snacks & Sucreries',
        'ru': 'Снеки и Сладости',
        'it': 'Snack e Dolci',
        'pt': 'Snacks e Doces',
        'pl': 'Przekąski i Słodycze',
        'nl': 'Snacks & Snoep',
        'sv': 'Snacks & Godis',
        'nb': 'Snacks & Søtsaker',
        'da': 'Snacks & Slik',
        'fi': 'Naposteltavat & Makeiset',
        'ro': 'Snacksuri & Dulciuri',
        'el': 'Σνακ & Γλυκά',
        'bg': 'Снакс & Сладости',
        'hr': 'Grickalice & Slatkiši',
        'sk': 'Snacky & Sladkosti',
        'cs': 'Snacky & Sladkosti',
        'hu': 'Snackek & Édességek',
        'lv': 'Uzkodas & Saldumi',
      },
      'Ice Cream': {
        'de': 'Eis',
        'es': 'Helado',
        'fr': 'Glace',
        'ru': 'Мороженое',
        'it': 'Gelato',
        'pt': 'Gelado',
        'pl': 'Lody',
        'nl': 'IJs',
        'sv': 'Glass',
        'nb': 'Is',
        'da': 'Is',
        'fi': 'Jäätelö',
        'ro': 'Înghețată',
        'el': 'Παγωτό',
        'bg': 'Сладолед',
        'hr': 'Sladoled',
        'sk': 'Zmrzlina',
        'cs': 'Zmrzlina',
        'hu': 'Fagylalt',
        'lv': 'Saldējums',
      },
      'Bakery Products (frozen)': {
        'de': 'Backwaren (gefroren)',
        'es': 'Panadería (congelada)',
        'fr': 'Boulangerie (surgelée)',
        'ru': 'Выпечка (заморозка)',
        'it': 'Panetteria (surgelata)',
        'pt': 'Padaria (congelada)',
        'pl': 'Pieczywo (mrożone)',
        'nl': 'Bakkerij (bevroren)',
        'sv': 'Bageri (fryst)',
        'nb': 'Bakeri (frosset)',
        'da': 'Bageri (frosset)',
        'fi': 'Leipomo (pakastettu)',
        'ro': 'Panificație (congelată)',
        'el': 'Αρτοποιεία (κατεψ.)',
        'bg': 'Хлебни (замразени)',
        'hr': 'Pekara (zamrznuta)',
        'sk': 'Pekáreň (mrazená)',
        'cs': 'Pekárna (mražená)',
        'hu': 'Pékség (fagyasztott)',
        'lv': 'Maiznīca (saldēta)',
      },
      'Soups & Ready Meals': {
        'de': 'Suppen & Fertiggerichte',
        'es': 'Sopas y Platos Preparados',
        'fr': 'Soupes & Plats Cuisinés',
        'ru': 'Супы и Готовые блюда',
        'it': 'Zuppe e Piatti Pronti',
        'pt': 'Sopas e Refeições',
        'pl': 'Zupy i Dania Gotowe',
        'nl': 'Soepen & Kant-en-klaar',
        'sv': 'Soppor & Färdigrätter',
        'nb': 'Supper & Ferdigretter',
        'da': 'Supper & Færdigretter',
        'fi': 'Keitot & Valmisruoat',
        'ro': 'Supe & Mâncăruri Gata',
        'el': 'Σούπες & Έτοιμα Γεύματα',
        'bg': 'Супи & Готови ястия',
        'hr': 'Juhe & Gotova Jela',
        'sk': 'Polievky & Hotové Jedlá',
        'cs': 'Polévky & Hotová Jídla',
        'hu': 'Levesek & Készételek',
        'lv': 'Zupas & Gatavās Ēdienreizes',
      },
      'Salads & Delicacies': {
        'de': 'Salate & Delikatessen',
        'es': 'Ensaladas y Delicias',
        'fr': 'Salades & Délices',
        'ru': 'Салаты и Деликатесы',
        'it': 'Insalate e Prelibatezze',
        'pt': 'Saladas e Delícias',
        'pl': 'Sałatki i Delikatesy',
        'nl': 'Salades & Delicatessen',
        'sv': 'Sallader & Delikatesser',
        'nb': 'Salater & Delikatesser',
        'da': 'Salater & Delikatesser',
        'fi': 'Salaatit & Herkut',
        'ro': 'Salate & Delicatese',
        'el': 'Σαλάτες & Λιχουδιές',
        'bg': 'Салати & Деликатеси',
        'hr': 'Salate & Delikatese',
        'sk': 'Šaláty & Delikatesy',
        'cs': 'Saláty & Delikatesy',
        'hu': 'Saláták & Csemegék',
        'lv': 'Salāti & Delikateses',
      },
      'Plants & Herbs': {
        'de': 'Pflanzen & Kräuter',
        'es': 'Plantas y Hierbas',
        'fr': 'Plantes & Herbes',
        'ru': 'Растения и Травы',
        'it': 'Piante e Erbe',
        'pt': 'Plantas e Ervas',
        'pl': 'Rośliny i Zioła',
        'nl': 'Planten & Kruiden',
        'sv': 'Växter & Örter',
        'nb': 'Planter & Urter',
        'da': 'Planter & Urter',
        'fi': 'Kasvit & Yrtit',
        'ro': 'Plante & Ierburi',
        'el': 'Φυτά & Βότανα',
        'bg': 'Растения & Билки',
        'hr': 'Biljke & Začinsko Bilje',
        'sk': 'Rastliny & Bylinky',
        'cs': 'Rostliny & Bylinky',
        'hu': 'Növények & Gyógynövények',
        'lv': 'Augi & Garšaugi',
      },
      'Non-Food': {
        'de': 'Non-Food',
        'es': 'No Alimentario',
        'fr': 'Non Alimentaire',
        'ru': 'Непродовольственное',
        'it': 'Non Alimentare',
        'pt': 'Não Alimentar',
        'pl': 'Non-Food',
        'nl': 'Non-Food',
        'sv': 'Non-Food',
        'nb': 'Non-Food',
        'da': 'Non-Food',
        'fi': 'Non-Food',
        'ro': 'Non-Alimentar',
        'el': 'Μη Τρόφιμα',
        'bg': 'Нехранителни стоки',
        'hr': 'Non-Food',
        'sk': 'Non-Food',
        'cs': 'Non-Food',
        'hu': 'Non-Food',
        'lv': 'Non-Food',
      },
      'Canned & Preserved': {
        'de': 'Konserven & Eingelegtes',
        'es': 'Conservas y Encurtidos',
        'fr': 'Conserves & Marinades',
        'ru': 'Консервы и Маринады',
        'it': 'Conserve e Sottaceti',
        'pt': 'Conservas e Marinados',
        'pl': 'Konserwy i Przetwory',
        'nl': 'Conserven & Ingemaaktes',
        'sv': 'Konserver & Inläggningar',
        'nb': 'Hermetikk & Marinader',
        'da': 'Konserves & Marinader',
        'fi': 'Säilykkeet & Marinoidut',
        'ro': 'Conserve & Murături',
        'el': 'Κονσέρβες & Τουρσί',
        'bg': 'Консерви & Маринати',
        'hr': 'Konzerve & Kiseli Krastavci',
        'sk': 'Konzervy & Nakladané',
        'cs': 'Konzervy & Nakládané',
        'hu': 'Konzervek & Savanyítottak',
        'lv': 'Konservi & Marinēti',
      },
      'Pasta & Noodles': {
        'de': 'Pasta & Nudeln',
        'es': 'Pasta y Fideos',
        'fr': 'Pâtes & Nouilles',
        'ru': 'Паста и Лапша',
        'it': 'Pasta e Noodles',
        'pt': 'Massa e Noodles',
        'pl': 'Makaron i Noodles',
        'nl': 'Pasta & Noedels',
        'sv': 'Pasta & Nudlar',
        'nb': 'Pasta & Nudler',
        'da': 'Pasta & Nudler',
        'fi': 'Pasta & Nuudelit',
        'ro': 'Paste & Tăiței',
        'el': 'Ζυμαρικά & Νούντλς',
        'bg': 'Паста & Нудли',
        'hr': 'Tjestenina & Rezanci',
        'sk': 'Cestoviny & Rezance',
        'cs': 'Těstoviny & Nudle',
        'hu': 'Tészta & Nudlik',
        'lv': 'Makaroni & Nūdeles',
      },
      'Sauces & Dips': {
        'de': 'Saucen & Dips',
        'es': 'Salsas y Dips',
        'fr': 'Sauces & Dips',
        'ru': 'Соусы и Дипы',
        'it': 'Salse e Dip',
        'pt': 'Molhos e Dips',
        'pl': 'Sosy i Dipy',
        'nl': 'Sauzen & Dips',
        'sv': 'Såser & Dips',
        'nb': 'Sauser & Dips',
        'da': 'Saucer & Dips',
        'fi': 'Kastikkeet & Dipit',
        'ro': 'Sosuri & Dips',
        'el': 'Σάλτσες & Dips',
        'bg': 'Сосове & Дипове',
        'hr': 'Umaci & Dips',
        'sk': 'Omáčky & Dipy',
        'cs': 'Omáčky & Dipy',
        'hu': 'Szószok & Dippek',
        'lv': 'Mērces & Dipi',
      },
      'Vegan & Vegetarian': {
        'de': 'Vegan & Vegetarisch',
        'es': 'Vegano y Vegetariano',
        'fr': 'Vegan & Végétarien',
        'ru': 'Веган и Вегетарианское',
        'it': 'Vegano e Vegetariano',
        'pt': 'Vegano e Vegetariano',
        'pl': 'Wegańskie i Wegetariańskie',
        'nl': 'Veganistisch & Vegetarisch',
        'sv': 'Veganskt & Vegetariskt',
        'nb': 'Vegansk & Vegetarisk',
        'da': 'Vegansk & Vegetarisk',
        'fi': 'Vegaani & Kasvissyöjä',
        'ro': 'Vegan & Vegetarian',
        'el': 'Vegan & Χορτοφάγο',
        'bg': 'Вегански & Вегетариански',
        'hr': 'Veganski & Vegetarijanski',
        'sk': 'Vegánske & Vegetariánske',
        'cs': 'Veganské & Vegetariánské',
        'hu': 'Vegán & Vegetáriánus',
        'lv': 'Vegānisks & Veģetārisks',
      },
      'Organic Products': {
        'de': 'Bio-Produkte',
        'es': 'Productos Orgánicos',
        'fr': 'Produits Bio',
        'ru': 'Органические продукты',
        'it': 'Prodotti Biologici',
        'pt': 'Produtos Biológicos',
        'pl': 'Produkty Ekologiczne',
        'nl': 'Biologische Producten',
        'sv': 'Ekologiska Produkter',
        'nb': 'Økologiske Produkter',
        'da': 'Økologiske Produkter',
        'fi': 'Luomutuotteet',
        'ro': 'Produse Ecologice',
        'el': 'Βιολογικά Προϊόντα',
        'bg': 'Биологични продукти',
        'hr': 'Ekološki Proizvodi',
        'sk': 'Ekologické Výrobky',
        'cs': 'Ekologické Výrobky',
        'hu': 'Bio Termékek',
        'lv': 'Bioloģiski Produkti',
      },
      'Regional Specialties': {
        'de': 'Regionale Spezialitäten',
        'es': 'Especialidades Regionales',
        'fr': 'Spécialités Régionales',
        'ru': 'Региональные специалитеты',
        'it': 'Specialità Regionali',
        'pt': 'Especialidades Regionais',
        'pl': 'Regionalne Specjały',
        'nl': 'Regionale Specialiteiten',
        'sv': 'Regionala Specialiteter',
        'nb': 'Regionale Spesialiteter',
        'da': 'Regionale Specialiteter',
        'fi': 'Alueelliset Erikoisuudet',
        'ro': 'Specialități Regionale',
        'el': 'Τοπικές Ειδικότητες',
        'bg': 'Регионални специалитети',
        'hr': 'Regionalne Specialitete',
        'sk': 'Regionálne Špeciality',
        'cs': 'Regionální Speciality',
        'hu': 'Regionális Specialitások',
        'lv': 'Reģionālās Specialitātes',
      },
      'Gift Items': {
        'de': 'Geschenkartikel',
        'es': 'Artículos de Regalo',
        'fr': 'Articles Cadeaux',
        'ru': 'Подарочные товары',
        'it': 'Articoli Regalo',
        'pt': 'Artigos de Presente',
        'pl': 'Artykuły Prezentowe',
        'nl': 'Cadeauartikelen',
        'sv': 'Presentartiklar',
        'nb': 'Gaveartikler',
        'da': 'Gaveartikler',
        'fi': 'Lahjatuotteet',
        'ro': 'Articole Cadou',
        'el': 'Δώρα',
        'bg': 'Подаръчни артикули',
        'hr': 'Pokloni',
        'sk': 'Darčekové Predmety',
        'cs': 'Dárkové Zboží',
        'hu': 'Ajándéktárgyak',
        'lv': 'Dāvanu Preces',
      },
    };
    return t[englishName]?[lang] ?? englishName;
  }

  String _getCategoryEmoji(String category) {
    const emojis = <String, String>{
      'Fruits & Vegetables': '🥦',
      'Dairy & Eggs': '🥛',
      'Meat & Sausages': '🥩',
      'Bakery Products': '🍞',
      'Jams & Spreads': '🫐',
      'Honey': '🍯',
      'Cereal Products': '🌾',
      'Beverages': '🥤',
      'Spices & Oils': '🫙',
      'Fish & Seafood': '🐟',
      'Cheese': '🧀',
      'Snacks & Sweets': '🍫',
      'Ice Cream': '🍦',
      'Bakery Products (frozen)': '🥐',
      'Soups & Ready Meals': '🍲',
      'Salads & Delicacies': '🥗',
      'Plants & Herbs': '🌿',
      'Non-Food': '📦',
      'Canned & Preserved': '🥫',
      'Pasta & Noodles': '🍝',
      'Sauces & Dips': '🥣',
      'Vegan & Vegetarian': '🌱',
      'Organic Products': '♻️',
      'Regional Specialties': '🗺️',
      'Gift Items': '🎁',
    };
    return emojis[category] ?? '🛍️';
  }

  void _showCategoryModal(bool isDark) {
    setState(() => _isModalOpen = true);
    TradeRepublicBottomSheet.show(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      maxHeight: MediaQuery.of(context).size.height * 0.88,
      child: Builder(
        builder: (context) {
          String categorySearchQuery = '';
          return StatefulBuilder(
            builder: (context, setModalState) {
              final allCatLabel = AppLocalizations.of(context)!.allCategories;
              // Build list: allCategories entry + fallback (english keys for matching)
              final List<String> allCategories =
                  [allCatLabel] + _fallbackCategories;
              List<String> filteredCategories = allCategories.where((c) {
                final displayName = _getCategoryLocalizedName(c);
                return displayName.toLowerCase().contains(
                  categorySearchQuery.toLowerCase(),
                );
              }).toList();

              return GestureDetector(
                onTap: () => FocusScope.of(context).unfocus(),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Active filter chips row
                      if (_selectedCategories.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      ..._selectedCategories.map(
                                        (cat) => Padding(
                                          padding: const EdgeInsets.only(
                                            right: 6,
                                          ),
                                          child: GestureDetector(
                                            onTap: () {
                                              HapticFeedback.lightImpact();
                                              Future.microtask(() {
                                                setState(
                                                  () => _selectedCategories
                                                      .remove(cat),
                                                );
                                                setModalState(() {});
                                                _filterProducts();
                                              });
                                            },
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: const Color(
                                                  0xFF34C759,
                                                ).withOpacity(0.12),
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    _getCategoryEmoji(cat),
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    _getCategoryLocalizedName(
                                                      cat,
                                                    ),
                                                    style: const TextStyle(
                                                      fontFamily: 'Poppins',
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: Color(0xFF34C759),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  const Icon(
                                                    CupertinoIcons.xmark,
                                                    size: 10,
                                                    color: Color(0xFF34C759),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  Future.microtask(() {
                                    setState(() => _selectedCategories.clear());
                                    setModalState(() {});
                                    _filterProducts();
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.white.withOpacity(0.08)
                                        : Colors.black.withOpacity(0.06),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        CupertinoIcons.xmark,
                                        size: 10,
                                        color: isDark
                                            ? Colors.white70
                                            : Colors.black54,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        AppLocalizations.of(context)!.clearAll,
                                        style: TextStyle(
                                          fontFamily: 'Poppins',
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                          color: isDark
                                              ? Colors.white70
                                              : Colors.black54,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Search field
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: TradeRepublicTextField.search(
                          onChanged: (value) {
                            setModalState(() => categorySearchQuery = value);
                          },
                          hintText: AppLocalizations.of(
                            context,
                          )!.searchCategories,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Emoji grid
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: GridView.builder(
                            physics: const BouncingScrollPhysics(),
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  mainAxisExtent: 88,
                                  crossAxisSpacing: 10,
                                  mainAxisSpacing: 10,
                                ),
                            itemCount: filteredCategories.length,
                            itemBuilder: (context, index) {
                              final category = filteredCategories[index];
                              final isAllCategory = category == allCatLabel;
                              final isSelected = isAllCategory
                                  ? _selectedCategories.isEmpty
                                  : _selectedCategories.contains(category);
                              final emoji = isAllCategory
                                  ? '✨'
                                  : _getCategoryEmoji(category);
                              final displayName = _getCategoryLocalizedName(
                                category,
                              );

                              return GestureDetector(
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  Future.microtask(() {
                                    setState(() {
                                      if (isAllCategory) {
                                        _selectedCategories.clear();
                                      } else if (_selectedCategories.contains(
                                        category,
                                      )) {
                                        _selectedCategories.remove(category);
                                      } else {
                                        _selectedCategories.add(category);
                                      }
                                    });
                                    setModalState(() {});
                                    _filterProducts();
                                  });
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  curve: Curves.easeOutCubic,
                                  decoration: isSelected
                                      ? BoxDecoration(
                                          color: TradeRepublicTheme
                                              .selectionContainerBackground(
                                            context,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            18,
                                          ),
                                        )
                                      : BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                            colors: isDark
                                                ? [
                                                    Colors.white.withOpacity(
                                                      0.09,
                                                    ),
                                                    Colors.white.withOpacity(
                                                      0.04,
                                                    ),
                                                  ]
                                                : CultiooDesktopLayout
                                                      .isDesktopPlatform
                                                    ? [
                                                        Colors.white,
                                                        Colors.white,
                                                      ]
                                                    : [
                                                        Colors.white,
                                                        Colors.grey.shade50,
                                                      ],
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            18,
                                          ),
                                        ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        emoji,
                                        style: const TextStyle(fontSize: 26),
                                      ),
                                      const SizedBox(height: 5),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                        ),
                                        child: Text(
                                          displayName,
                                          style: TextStyle(
                                            fontFamily: 'Poppins',
                                            fontSize: 10.5,
                                            fontWeight: isSelected
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                            color: isSelected
                                                ? TradeRepublicTheme
                                                    .selectionContainerForeground(
                                                    context,
                                                  )
                                                : (isDark
                                                      ? Colors.white
                                                            .withOpacity(0.85)
                                                      : Colors.black
                                                            .withOpacity(0.75)),
                                            height: 1.3,
                                          ),
                                          textAlign: TextAlign.center,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    ).whenComplete(() {
      if (!mounted) return;
      setState(() => _isModalOpen = false);
    });
  }

  // Products helper methods - Optimized for performance
  Future<void> _loadProducts({bool force = false}) async {
    debugPrint('🔍 DEBUG: _loadProducts called, isLoading: $_isLoadingProducts');
    debugPrint(
      '🔍 DEBUG: _fallbackCategories.length = ${_fallbackCategories.length}',
    );
    debugPrint('🔍 DEBUG: Current _categories.length = ${_categories.length}');

    if (_isLoadingProducts) return; // Prevent multiple simultaneous loads

    // Rate limiting check
    final now = DateTime.now();
    if (!force && _lastProductsLoad != null) {
      final timeSinceLastLoad = now.difference(_lastProductsLoad!);
      if (timeSinceLastLoad < _apiCooldown) {
        debugPrint(
          '⏳ Products rate limited: Last load was ${timeSinceLastLoad.inSeconds}s ago, cooldown is ${_apiCooldown.inSeconds}s',
        );
        return;
      }
    }

    _lastProductsLoad = now;

    // FORCE SET fallback categories IMMEDIATELY - never change this
    final allAvailableCategories = _fallbackCategories
        .map(
          (category) => {
            'name': category,
            'slug': category
                .toLowerCase()
                .replaceAll(' ', '-')
                .replaceAll('&', 'and'),
          },
        )
        .toList();

    setState(() {
      _isLoadingProducts = true;
      _categories = allAvailableCategories; // ALWAYS use fallback categories
    });

    debugPrint(
      '🔍 DEBUG: FORCED fallback categories: ${_categories.length} categories',
    );
    debugPrint(
      '🔍 DEBUG: Categories: ${_categories.take(5).map((c) => c['name']).join(', ')}...',
    );

    try {
      debugPrint('🔍 DEBUG: Calling ApiService.getProducts()');
      // Load products but IGNORE categories from API
      final productsResponse = await ApiService.getProducts();
      final responseStr = productsResponse.toString();
      debugPrint(
        '🔍 DEBUG: Products response received: ${responseStr.length > 100 ? responseStr.substring(0, 100) : responseStr}...',
      );

      if (mounted) {
        setState(() {
          _products = List<Map<String, dynamic>>.from(
            productsResponse['products'] ?? [],
          );
          _preprocessProducts(_products);
          _filteredProducts = _products;
          _isLoadingProducts = false;
          // DO NOT CHANGE _categories here - keep fallback categories!
        });

        // Update product count for current user after loading products
        if (_isLoggedIn && _currentUser != null) {
          await _calculateUserProductCount();
        }

        debugPrint(
          '🔍 DEBUG: State updated with ${_products.length} products and ${_categories.length} categories',
        );
        debugPrint(
          '🔍 DEBUG: Final categories: ${_categories.map((c) => c['name']).take(5).join(', ')}...',
        );
      }

      debugPrint(
        '✅ Loaded ${_products.length} products and ${_categories.length} categories',
      );
    } catch (error) {
      debugPrint('❌ Error loading products: $error');

      // Handle rate limiting (429 errors)
      if (error.toString().contains('Status 429') ||
          error.toString().contains('429')) {
        debugPrint('❌ Products API call failed due to rate limiting (429)');
        if (!force && mounted && _productsLoadTimer?.isActive != true) {
          _productsLoadTimer = Timer(const Duration(minutes: 2), () {
            if (mounted) {
              debugPrint('🔄 Retrying products load after rate limit cooldown');
              _loadProducts();
            }
          });
        }
        setState(() {
          _isLoadingProducts = false;
          // Keep fallback categories even on rate limit
        });
        return;
      }

      if (mounted) {
        setState(() {
          _isLoadingProducts = false;
          // Keep fallback categories even on error
        });
      }

      // Show error message but keep fallback categories
      if (mounted) {
        _showBottomMessage(
          AppLocalizations.of(
            context,
          )!.couldNotLoadProductsFromServerCategoriesAva,
        );
      }
    }
  }

  Future<void> _refreshHomePage() async {
    _productsLoadTimer?.cancel();
    _lastProductsLoad = null;

    await _loadProducts(force: true);

    if (_isLoggedIn) {
      try {
        await _loadCartCount();
      } catch (_) {}

      try {
        await _loadFavoritesFromServer();
      } catch (_) {}
    }
  }

  void _onSearchChanged(String value) {
    setState(() {
      _searchQuery = value;
      // Automatically expand when text is entered
      if (value.isNotEmpty && !_isSearchExpanded) {
        _isSearchExpanded = true;
      }
      // Automatically shrink when text is deleted
      else if (value.isEmpty && _isSearchExpanded) {
        _isSearchExpanded = false;
      }
    });
    _filterProducts();
  }

  // Favorites methods
  Future<void> _toggleFavorite(int productId) async {
    // Check if user is logged in
    if (!_isLoggedIn) {
      _showBottomMessage(
        AppLocalizations.of(context)!.pleaseLoginToFollow,
        isError: true,
      );
      return;
    }

    final bool isCurrentlyFavorite = _favoriteProductIds.contains(productId);

    // Optimistische UI-Aktualisierung
    setState(() {
      if (isCurrentlyFavorite) {
        _favoriteProductIds.remove(productId);
      } else {
        _favoriteProductIds.add(productId);
      }
    });

    try {
      if (ApiService.isLoggedIn) {
        // Server-API verwenden
        if (isCurrentlyFavorite) {
          await ApiService.removeFromFavorites(productId);
        } else {
          await ApiService.addToFavorites(productId);
        }
      }

      // Lokale Kopie aktualisieren
      await _saveFavoritesToPrefs();

      // Show success message in English
      _showBottomMessage(
        isCurrentlyFavorite
            ? AppLocalizations.of(context)!.removedFromFavorites
            : AppLocalizations.of(context)!.addedToFavorites,
      );
    } catch (e) {
      // On error: Revert UI change
      setState(() {
        if (isCurrentlyFavorite) {
          _favoriteProductIds.add(productId);
        } else {
          _favoriteProductIds.remove(productId);
        }
      });

      _showBottomMessage(AppLocalizations.of(context)!.errorUpdatingFavorites);
    }
  }

  // Callback for Product Details Modal - synchronizes the favorites states
  void _onFavoriteToggleFromModal(int productId) {
    // Update the local favorites state
    setState(() {
      if (_favoriteProductIds.contains(productId)) {
        _favoriteProductIds.remove(productId);
      } else {
        _favoriteProductIds.add(productId);
      }
    });

    // Save changes locally
    _saveFavoritesToPrefs();

    // Update the product list to synchronize the favorites icons
    _filterProducts();
  }

  Future<void> _saveFavoritesToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final favoriteStrings = _favoriteProductIds
        .map((id) => id.toString())
        .toList();
    await prefs.setStringList('favorite_products', favoriteStrings);
  }

  Future<void> _loadFavoritesFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final favoriteStrings = prefs.getStringList('favorite_products') ?? [];
      setState(() {
        _favoriteProductIds = favoriteStrings
            .map((str) => int.parse(str))
            .toList();
      });

      // Debug info
      debugPrint(
        '📱 Loaded ${_favoriteProductIds.length} favorites from preferences: $_favoriteProductIds',
      );
    } catch (e) {
      debugPrint('⚠️ Failed to load favorites from SharedPreferences: $e');
      // Keep existing data
    }
  }

  // Dismissed cancelled orders persistence
  Future<void> _saveDismissedOrderIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ids = _dismissedOrderIds.map((id) => id.toString()).toList();
      final storageKey = _dismissedOrderStorageKey();
      if (storageKey == null) return;
      await prefs.setStringList(storageKey, ids);
    } catch (e) {
      debugPrint('⚠️ Failed to save dismissed order IDs: $e');
    }
  }

  String? _dismissedOrderStorageKey([String? explicitUsername]) {
    final fallbackUsername = _userUsername.trim().isNotEmpty
        ? _userUsername
        : (_currentUser?['username']?.toString() ?? '');
    final username = (explicitUsername ?? fallbackUsername)
        .trim()
        .toLowerCase();
    if (username.isEmpty) return null;
    return 'dismissed_order_ids_$username';
  }

  Future<void> _loadDismissedOrderIds({String? username}) async {
    try {
      final storageKey = _dismissedOrderStorageKey(username);
      if (storageKey == null) {
        setState(() {
          _dismissedOrderIds.clear();
        });
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final ids = prefs.getStringList(storageKey) ?? [];
      setState(() {
        _dismissedOrderIds.clear();
        _dismissedOrderIds.addAll(ids);
      });
      debugPrint(
        '📱 Loaded ${ids.length} dismissed order IDs for user key: $storageKey',
      );
    } catch (e) {
      debugPrint('⚠️ Failed to load dismissed order IDs: $e');
    }
  }

  // Following users methods
  Future<void> _loadFollowedUsersFromServer() async {
    // Rate limiting check
    final now = DateTime.now();
    if (_lastFollowedUsersLoad != null) {
      final timeSinceLastLoad = now.difference(_lastFollowedUsersLoad!);
      if (timeSinceLastLoad < _apiCooldown) {
        debugPrint(
          '⏳ Rate limited: Last load was ${timeSinceLastLoad.inSeconds}s ago, cooldown is ${_apiCooldown.inSeconds}s',
        );
        return;
      }
    }

    // Cancel any pending timer
    _followedUsersLoadTimer?.cancel();
    _productsLoadTimer?.cancel();

    // Don't reload if already loading
    if (_isLoadingFollowedUsers) {
      debugPrint('⏳ Already loading followed users, skipping duplicate request');
      return;
    }

    _lastFollowedUsersLoad = now;
    setState(() {
      _isLoadingFollowedUsers = true;
    });

    try {
      // Only load from server if user is logged in
      if (ApiService.isLoggedIn) {
        // Get current user info for self-follow filtering
        final currentUsername =
            await DeviceStorage.getString('stored_username') ?? '';

        debugPrint('🔍 Loading followed users from server...');
        debugPrint('DEBUG: Current user logged in: ${ApiService.isLoggedIn}');
        debugPrint('DEBUG: Current username: $currentUsername');
        try {
          final result = await ApiService.getFollowedUsers();
          debugPrint('📡 API Response received: $result');
          debugPrint('DEBUG: API response type: ${result.runtimeType}');
          if (result['success'] == true && result['users'] != null) {
            final users = List<Map<String, dynamic>>.from(result['users']);
            debugPrint('✅ API returned ${users.length} followed users');
            debugPrint('DEBUG: Raw users data: $users');

            // Filter out self-follows (safety measure)
            final filteredUsers = users.where((user) {
              final username = user['username']?.toString() ?? '';
              final isNotSelfFollow = username != currentUsername;
              if (!isNotSelfFollow) {
                debugPrint(
                  '🚫 Filtered out self-follow: $username (current user: $currentUsername)',
                );
              }
              return isNotSelfFollow;
            }).toList();

            setState(() {
              _followedUsers = filteredUsers;
            });
            await _saveFollowedUsersToPrefs();
            debugPrint(
              '✅ Loaded ${filteredUsers.length} followed users from server (filtered from ${users.length})',
            );
          } else if (result['success'] == false && result['message'] != null) {
            debugPrint(
              'ℹ️ ${result['message']} - keeping local followed users data',
            );
            // Don't clear local data when server has issues
          } else {
            debugPrint(
              '⚠️ Server returned empty followed users data - keeping local data intact',
            );
            // Don't clear local data when server returns empty data
          }
        } catch (e) {
          debugPrint('❌ API call failed: $e');

          // Handle rate limiting specifically
          if (e.toString().contains('429') ||
              e.toString().contains('Too many requests')) {
            debugPrint('🚫 Rate limited by server, will retry later');
            // Schedule retry with exponential backoff
            _followedUsersLoadTimer = Timer(const Duration(minutes: 2), () {
              if (mounted && ApiService.isLoggedIn) {
                _loadFollowedUsersFromServer();
              }
            });
            return;
          }

          if (e.toString().contains('404') ||
              e.toString().contains('Not Found')) {
            debugPrint(
              'ℹ️ Following API not yet implemented on server - keeping local data',
            );
            // Don't clear local data when API is not implemented
          } else if (e.toString().contains('Status 404')) {
            debugPrint(
              'ℹ️ Following API endpoint not found - keeping local data intact',
            );
            setState(() {
              _followedUsers = [];
            });
            await _saveFollowedUsersToPrefs();
          } else {
            // For other errors, fall back to local data
            await _loadFollowedUsersFromPrefs();
          }
        }
      } else {
        debugPrint('ℹ️ User not logged in - loading local followed users only');
        await _loadFollowedUsersFromPrefs();
      }
    } catch (e) {
      debugPrint('❌ Error loading followed users: $e');

      // Handle rate limiting at the outer level too
      if (e.toString().contains('429') ||
          e.toString().contains('Too many requests')) {
        debugPrint('🚫 Global rate limit hit, scheduling retry');
        _followedUsersLoadTimer = Timer(const Duration(minutes: 2), () {
          if (mounted && ApiService.isLoggedIn) {
            _loadFollowedUsersFromServer();
          }
        });
      } else {
        // Fallback: Load from SharedPreferences
        await _loadFollowedUsersFromPrefs();
      }
    } finally {
      // Always reset loading state
      if (mounted) {
        setState(() {
          _isLoadingFollowedUsers = false;
        });
      }
    }
  }

  Future<void> _saveFollowedUsersToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final followedUsersJson = _followedUsers
        .map((user) => jsonEncode(user))
        .toList();
    await prefs.setStringList('followed_users', followedUsersJson);
  }

  Future<void> _loadFollowedUsersFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final followedUsersJson = prefs.getStringList('followed_users') ?? [];
      setState(() {
        _followedUsers = followedUsersJson
            .map((jsonStr) => jsonDecode(jsonStr) as Map<String, dynamic>)
            .toList();
      });
    } catch (e) {
      debugPrint('⚠️ Failed to load followed users from SharedPreferences: $e');
      // Keep existing data
    }
  }

  // Calculate product count for the current user
  Future<void> _calculateUserProductCount() async {
    try {
      if (_currentUser != null && _userName.isNotEmpty) {
        // Get all products
        final productsResponse = await ApiService.getProducts();
        if (productsResponse['success'] &&
            productsResponse['products'] != null) {
          final products = productsResponse['products'] as List;

          // Count products by current user
          final userProducts = products
              .where(
                (product) =>
                    product['username'] == _userName ||
                    product['username'] == _userEmail.split('@')[0] ||
                    product['seller_id'] == _currentUser?['id']?.toString(),
              )
              .toList();

          // Update the current user with product count
          setState(() {
            if (_currentUser != null) {
              _currentUser!['product_count'] = userProducts.length;
            }
          });
        }
      }
    } catch (e) {
      // Handle error silently, product count will remain 0
    }
  }

  // Seller notification methods
  Future<void> _toggleSellerNotifications(String sellerId) async {
    final currentSetting = _sellerNotificationSettings[sellerId] ?? false;

    setState(() {
      _sellerNotificationSettings[sellerId] = !currentSetting;
    });

    try {
      // Save to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'seller_notifications_$sellerId',
        (!currentSetting).toString(),
      );

      // TODO: Send to backend API to save notification preference
      // await ApiService.updateSellerNotificationSetting(sellerId, !currentSetting);

      final sellerName =
          _followedUsers.firstWhere(
            (user) =>
                (user['seller_id'] ??
                    user['username'] ??
                    user['id']?.toString()) ==
                sellerId,
            orElse: () => {'name': 'Seller'},
          )['name'] ??
          AppLocalizations.of(context)!.seller;

      _showBottomMessage(
        !currentSetting
            ? AppLocalizations.of(context)!.notifiedWhenSellerAdds(sellerName)
            : AppLocalizations.of(
                context,
              )!.notificationsDisabledFor(sellerName),
        isSuccess: true,
      );
    } catch (e) {
      //debugPrint('Error toggling seller notifications: $e');
      // Revert state change on error
      setState(() {
        _sellerNotificationSettings[sellerId] = currentSetting;
      });
      _showBottomMessage(
        AppLocalizations.of(context)!.failedToUpdateNotificationSettings,
        isError: true,
      );
    }
  }

  Future<void> _loadSellerNotificationSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where(
      (key) => key.startsWith('seller_notifications_'),
    );

    for (final key in keys) {
      final sellerId = key.replaceFirst('seller_notifications_', '');
      final isEnabled = prefs.getString(key) == 'true';
      _sellerNotificationSettings[sellerId] = isEnabled;
    }
  }

  void _showSellerProfile(String sellerId, String sellerName) {
    debugPrint(
      '🔍 DEBUG: _showSellerProfile called with sellerId: "$sellerId", sellerName: "$sellerName"',
    );
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      useRootNavigator: true,
      maxHeight: MediaQuery.of(context).size.height * 0.9,
      child: SellerProfileModal(
        sellerId: sellerId,
        sellerName: sellerName,
        onFollowChanged: () {
          // Reload followed users immediately when follow status changes
          // Use Future.microtask to ensure it runs after the current frame
          Future.microtask(() async {
            await _loadFollowedUsersFromPrefs(); // Load from cache first for immediate UI update
            Future.delayed(const Duration(milliseconds: 200), () {
              _loadFollowedUsersFromServer(); // Then update from server
            });
          });
        },
      ),
    ).then((_) {
      // Reload followed users when modal is closed to reflect any changes
      if (_isLoggedIn) {
        _loadFollowedUsersFromPrefs();
        _loadFollowedUsersFromServer();
      }
    });
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _isSearchExpanded = false; // Collapse search when clearing
    });
    _searchAnimationController.reverse();
    _filterProducts();
  }

  Future<void> _loadCartCount() async {
    try {
      final response = await ApiService.getCartSummary();
      if (response['success'] == true) {
        final cartCount = response['totalItems'] ?? 0;
        setState(() {
          _cartItemCount = cartCount;
        });
        // Cache cart count for offline use
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('cached_cart_count', cartCount);
      }
    } catch (e) {
      //debugPrint('Error loading cart count: $e');

      // Try to load cached cart count
      try {
        final prefs = await SharedPreferences.getInstance();
        final cachedCount = prefs.getInt('cached_cart_count') ?? 0;
        setState(() {
          _cartItemCount = cachedCount;
        });
        //debugPrint('Using cached cart count: $cachedCount');
      } catch (cacheError) {
        //debugPrint('Error loading cached cart count: $cacheError');
      }

      // If we get a rate limiting error, try again later
      if (e.toString().contains('429') ||
          e.toString().contains('Too many requests')) {
        //debugPrint('Rate limited, will retry cart count later...');
        Timer(const Duration(seconds: 2), () {
          _loadCartCount();
        });
      }
    }
  }

  // Callback method that can be passed to child widgets
  void _onCartChanged() {
    // Cancel any existing timer
    _cartLoadTimer?.cancel();

    // Set a new timer to debounce cart loading
    _cartLoadTimer = Timer(const Duration(milliseconds: 300), () {
      _loadCartCount();
    });
  }

  // Calculate distance between two points using Haversine formula
  double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadiusKm = 6371.0;

    double dLat = _degreesToRadians(lat2 - lat1);
    double dLon = _degreesToRadians(lon2 - lon1);

    double a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) *
            cos(_degreesToRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusKm * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * pi / 180;
  }

  void _filterProducts() {
    setState(() {
      _visibleProductCount = 20; // Reset pagination on every filter change
      _filteredProducts = _products.where((product) {
        final matchesSearch =
            _searchQuery.isEmpty ||
            product['name'].toString().toLowerCase().contains(
              _searchQuery.toLowerCase(),
            ) ||
            product['description'].toString().toLowerCase().contains(
              _searchQuery.toLowerCase(),
            );

        // Check category match - supports multi-select via _selectedCategories Set
        bool matchesCategory = _selectedCategories.isEmpty;

        if (!matchesCategory) {
          // Check product category
          if (_selectedCategories.contains(product['category'])) {
            matchesCategory = true;
          }

          // Check variant mainCategory
          if (!matchesCategory && product['variants'] != null) {
            for (final variant in product['variants']) {
              if (_selectedCategories.contains(variant['mainCategory'])) {
                matchesCategory = true;
                break;
              }
            }
          }
        }

        // Distance filtering
        bool matchesRadius = true;
        if (_searchRadius < 9999 &&
            _userLatitude != null &&
            _userLongitude != null) {
          // Check if product has coordinates
          final productLat = product['lat'] ?? product['latitude'];
          final productLng = product['lng'] ?? product['longitude'];

          if (productLat != null && productLng != null) {
            double lat, lng;

            // Handle both string and number types
            if (productLat is String) {
              lat = double.tryParse(productLat) ?? 0.0;
            } else {
              lat = (productLat as num).toDouble();
            }

            if (productLng is String) {
              lng = double.tryParse(productLng) ?? 0.0;
            } else {
              lng = (productLng as num).toDouble();
            }

            if (lat != 0.0 && lng != 0.0) {
              final distance = _calculateDistance(
                _userLatitude!,
                _userLongitude!,
                lat,
                lng,
              );
              matchesRadius = distance <= _searchRadius;
            }
          }
          // If no coordinates, exclude from results when radius is set
          else {
            matchesRadius = false;
          }
        }

        // Incoterm filtering
        bool matchesIncoterm = _selectedIncoterms.isEmpty;
        if (!matchesIncoterm) {
          final incoterm = (product['incoterm'] ?? '')
              .toString()
              .trim()
              .toUpperCase();
          if (incoterm.isNotEmpty && _selectedIncoterms.contains(incoterm)) {
            matchesIncoterm = true;
          }
        }

        return matchesSearch &&
            matchesCategory &&
            matchesRadius &&
            matchesIncoterm;
      }).toList();
    });
  }

  List<String> _getAvailableIncoterms() {
    final incoterms = <String>{};
    for (final product in _products) {
      final inc = (product['incoterm'] ?? '').toString().trim();
      if (inc.isNotEmpty) incoterms.add(inc.toUpperCase());
    }
    return incoterms.toList()..sort();
  }

  /// Pre-computes all expensive variant-loop fields once per product.
  /// Results are stored in the product map under `_c_` prefix keys so
  /// _buildProductCard reads them cheaply with zero iteration at build time.
  void _preprocessProducts(List<Map<String, dynamic>> products) {
    for (final product in products) {
      if (product.containsKey('_c_processed')) continue;

      final variants = product['variants'];
      String? imageUrl = product['image_url']?.toString();
      String unit = '';
      String sellerName = '';
      bool isOrganic = false;
      double? minPrice;
      double? maxPrice;
      int totalStock = 0;
      bool alwaysAvailable = false;
      int minOrder = 0;
      String category = '';

      if (variants is List && variants.isNotEmpty) {
        final imgs = variants[0]['images'];
        if ((imageUrl == null || imageUrl.isEmpty) &&
            imgs is List &&
            imgs.isNotEmpty) {
          imageUrl = imgs[0]?.toString();
        }
        unit = variants[0]['unit']?.toString() ?? '';
        sellerName =
            product['seller_name']?.toString() ??
            product['sellerName']?.toString() ??
            product['seller']?.toString() ??
            product['username']?.toString() ??
            '';
        category =
            variants[0]['mainCategory']?.toString() ??
            product['category']?.toString() ??
            '';
        alwaysAvailable = variants.any(
          (v) => v['alwaysAvailable'] == 1 || v['alwaysAvailable'] == true,
        );
        minOrder = ((variants[0]['minOrder'] ?? 0) as num).toInt();

        for (final v in variants) {
          final p = _parsePrice(v['price']);
          if (p > 0) {
            if (minPrice == null || p < minPrice) minPrice = p;
            if (maxPrice == null || p > maxPrice) maxPrice = p;
          }
          isOrganic = isOrganic || v['organic'] == true || v['organic'] == 1;
          totalStock += ((v['stock'] ?? 0) as num).toInt();
        }
      }

      final hasPriceRange =
          minPrice != null && maxPrice != null && maxPrice != minPrice;
      final priceStr = minPrice != null
          ? (hasPriceRange
                ? '\$${minPrice.toStringAsFixed(2)}–\$${maxPrice.toStringAsFixed(2)}'
                : '\$${minPrice.toStringAsFixed(2)}')
          : _getProductDisplayPrice(product);

      product['_c_processed'] = true;
      product['_c_imageUrl'] = imageUrl ?? '';
      product['_c_unit'] = unit;
      product['_c_sellerName'] = sellerName;
      product['_c_isOrganic'] = isOrganic;
      product['_c_priceStr'] = priceStr;
      product['_c_totalStock'] = totalStock;
      product['_c_alwaysAvailable'] = alwaysAvailable;
      product['_c_minOrder'] = minOrder;
      product['_c_category'] = category;
    }
  }

  Widget _buildCategoryChip(String category, bool isSelected, bool isDark) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 300),
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        return Transform.scale(
          scale: 0.95 + (0.05 * value),
          child: Container(
            margin: const EdgeInsets.only(right: 6), // Reduziert von 12 auf 6
            height: 32, // Reduziert von 45 auf 32
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 4,
              ), // Reduziert Padding
              decoration: BoxDecoration(
                gradient: isSelected
                    ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF007AFF), Color(0xFF5856D6)],
                      )
                    : LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: isDark
                            ? [
                                Colors.white.withOpacity(0.08),
                                Colors.white.withOpacity(0.03),
                              ]
                            : [
                                Colors.white.withOpacity(0.9),
                                Colors.white.withOpacity(0.6),
                              ],
                      ),
                borderRadius: BorderRadius.circular(
                  20,
                ), // Reduziert von 25 auf 20
                boxShadow: [
                  if (isSelected) ...[
                    BoxShadow(
                      color: const Color(0xFF007AFF).withOpacity(0.3),
                      blurRadius: 0, // No blur
                      offset: const Offset(
                        0,
                        2,
                      ), // Reduced for sharper shadow
                      spreadRadius: 0,
                    ),
                    BoxShadow(
                      color: const Color(0xFF007AFF).withOpacity(0.1),
                      blurRadius: 0, // No blur
                      offset: const Offset(
                        0,
                        4,
                      ), // Reduced for sharper shadow
                      spreadRadius: 0,
                    ),
                  ] else ...[
                    BoxShadow(
                      color: isDark
                          ? Colors.black.withOpacity(0.4)
                          : Colors.black.withOpacity(0.06),
                      blurRadius: 0, // No blur
                      offset: const Offset(
                        0,
                        1,
                      ), // Reduced for sharper shadow
                      spreadRadius: 0,
                    ),
                    BoxShadow(
                      color: isDark
                          ? Colors.white.withOpacity(0.05)
                          : Colors.white.withOpacity(0.8),
                      blurRadius: 0, // No blur
                      offset: const Offset(0, -1), // Bleibt gleich
                      spreadRadius: 0,
                    ),
                  ],
                ],
              ),
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() {
                    if (category == 'All') {
                      _selectedCategories.clear();
                    } else if (isSelected) {
                      _selectedCategories.remove(category);
                    } else {
                      _selectedCategories.add(category);
                    }
                  });
                  _filterProducts();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: 1,
                  ), // Reduziert Padding
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isSelected) ...[
                        Container(
                          width: 16, // Reduziert von 20
                          height: 16, // Reduziert von 20
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(
                              20,
                            ), // Angepasst
                          ),
                          child: const Icon(
                            CupertinoIcons.check_mark,
                            size: 10, // Reduziert von 12
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 6), // Reduziert von 8
                      ],
                      Flexible(
                        child: Text(
                          category,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: isSelected
                                ? Colors.white
                                : (isDark
                                      ? Colors.white.withOpacity(0.8)
                                      : Colors.black.withOpacity(0.7)),
                            fontSize: 13, // Reduced font size
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildProductCard(Map<String, dynamic> product, bool isDark) {
    // ─── Read pre-computed fields (set once by _preprocessProducts)
    final bool isWide = _isWideScreen;
    final bool deferHeavyImageWork =
        Scrollable.recommendDeferredLoadingForContext(context);
    final String imageUrl =
        product['_c_imageUrl'] ?? product['image_url']?.toString() ?? '';
    final String unit = product['_c_unit'] ?? '';
    final String sellerName =
        product['_c_sellerName'] ?? product['seller']?.toString() ?? '';
    final String priceStr =
        product['_c_priceStr'] ?? _getProductDisplayPrice(product);

    final isFav = _favoriteProductIds.contains(product['id']);
    final bool isOrganic = product['_c_isOrganic'] == true;

    String localizedCategory = '';
    String city = '';
    String incotermClean = '';
    String? stockLabel;
    int minOrder = 0;
    num views = 0;

    if (isWide) {
      final int totalStock = (product['_c_totalStock'] ?? 0) as int;
      final bool alwaysAvailable = product['_c_alwaysAvailable'] == true;
      final String category =
          product['_c_category'] ?? product['category']?.toString() ?? '';
      views = (product['views'] ?? product['view_count'] ?? 0) as num;
      city = product['locationCity']?.toString() ?? '';
      final incoterm = product['incoterm']?.toString() ?? '';
      localizedCategory = category.isNotEmpty
          ? _getCategoryLocalizedName(category)
          : '';
      stockLabel = alwaysAvailable
          ? '∞'
          : totalStock > 0
          ? '$totalStock'
          : null;
      incotermClean = (incoterm.isNotEmpty && incoterm != 'null')
          ? incoterm.toUpperCase()
          : '';
      minOrder = (product['_c_minOrder'] ?? 0) as int;
    }

    Widget buildCoverMedia(Widget child) {
      return ClipRect(
        child: SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            alignment: Alignment.center,
            clipBehavior: Clip.hardEdge,
            child: child,
          ),
        ),
      );
    }

    // ─── Image widget (full-bleed Trade Republic style)
    Widget imageWidget;
    if (deferHeavyImageWork) {
      imageWidget = _buildCardPlaceholder(isDark);
    } else if (imageUrl.startsWith('data:image')) {
      final bytes = _decodeDataImageCached(imageUrl);
      if (bytes != null) {
        imageWidget = buildCoverMedia(
          Image.memory(
            bytes,
            cacheWidth: isWide ? 240 : 140,
            cacheHeight: isWide ? 240 : 140,
            filterQuality: FilterQuality.none,
            gaplessPlayback: false,
            errorBuilder: (_, _, _) => _buildCardPlaceholder(isDark),
          ),
        );
      } else {
        imageWidget = _buildCardPlaceholder(isDark);
      }
    } else if (imageUrl.isNotEmpty) {
      imageWidget = CachedNetworkImage(
        imageUrl: imageUrl,
        memCacheWidth: isWide ? 220 : 150,
        memCacheHeight: isWide ? 220 : 150,
        maxWidthDiskCache: 420,
        maxHeightDiskCache: 420,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        imageBuilder: (_, provider) => buildCoverMedia(
          Image(image: provider, filterQuality: FilterQuality.low),
        ),
        placeholder: (_, _) => _buildCardPlaceholder(isDark),
        errorWidget: (_, _, _) => _buildCardPlaceholder(isDark),
      );
    } else {
      imageWidget = _buildCardPlaceholder(isDark);
    }

    final Widget productMedia = DecoratedBox(
      decoration: BoxDecoration(
        color: CultiooDesktopLayout.isDesktopPlatform
            ? (isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF))
            : (isDark ? const Color(0xFF181818) : const Color(0xFFF4F4F4)),
      ),
      child: imageWidget,
    );

    if (!isWide) {
      return GestureDetector(
        onTap: () => _showProductDetails(product),
        behavior: HitTestBehavior.opaque,
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF111111) : const Color(0xFFFFFFFF),
            borderRadius: TradeRepublicTheme.borderRadiusXL,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    productMedia,
                    // Favorite button overlay
                    if (_isLoggedIn)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            _toggleFavorite(product['id']);
                          },
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isFav
                                  ? CupertinoIcons.heart_fill
                                  : CupertinoIcons.heart,
                              size: 13,
                              color: isFav
                                  ? TradeRepublicTheme.destructiveRed
                                  : Colors.black54,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product['name'] ?? '',
                      style: TradeRepublicTheme.titleSmall(
                        context,
                      ).copyWith(fontSize: 14),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Flexible(
                          child: Text(
                            priceStr,
                            style: TradeRepublicTheme.titleSmall(
                              context,
                            ).copyWith(fontSize: 14.5),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (unit.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          Text(
                            '/$unit',
                            style: TradeRepublicTheme.bodySmall(
                              context,
                            ).copyWith(fontSize: 10),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sellerName.isNotEmpty ? '@$sellerName' : '',
                      style: TradeRepublicTheme.bodySmall(
                        context,
                      ).copyWith(fontSize: 10),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return TradeRepublicCard(
      padding: EdgeInsets.zero,
      borderRadius: TradeRepublicTheme.borderRadiusXL,
      boxShadow: const [],
      backgroundColor: isDark
          ? const Color(0xFF111111)
          : const Color(0xFFFFFFFF),
      onTap: () => _showProductDetails(product),
      child: ClipRRect(
        borderRadius: TradeRepublicTheme.borderRadiusXL,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Image + overlays (50% of card)
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  productMedia,
                  // Bottom fade
                  const Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0x38000000)],
                          stops: [0.5, 1.0],
                        ),
                      ),
                    ),
                  ),
                  // Organic badge
                  if (isOrganic)
                    Positioned(
                      bottom: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: TradeRepublicTheme.accentGreen.withValues(
                            alpha: 0.88,
                          ),
                          borderRadius: TradeRepublicTheme.borderRadiusMedium,
                        ),
                        child: const Text(
                          'Organic',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  // Fav button
                  if (_isLoggedIn)
                    Positioned(
                      top: 7,
                      right: 7,
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          _toggleFavorite(product['id']);
                        },
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isFav
                                ? CupertinoIcons.heart_fill
                                : CupertinoIcons.heart,
                            size: 14,
                            color: isFav
                                ? TradeRepublicTheme.destructiveRed
                                : Colors.black54,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // ─── Info section
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    // Name
                    Text(
                      product['name'] ?? '',
                      style: TradeRepublicTheme.titleSmall(context).copyWith(
                        fontSize: _isWideScreen ? 14 : 14.5,
                        height: 1.2,
                      ),
                      maxLines: _isWideScreen ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // Price + unit
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Flexible(
                          child: Text(
                            priceStr,
                            style: TradeRepublicTheme.titleSmall(context)
                                .copyWith(
                                  fontSize: _isWideScreen ? 15 : 14.5,
                                  letterSpacing: -0.3,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (unit.isNotEmpty) ...[
                          const SizedBox(width: 3),
                          Text(
                            '/$unit',
                            style: TradeRepublicTheme.bodySmall(
                              context,
                            ).copyWith(fontSize: 10),
                          ),
                        ],
                      ],
                    ),
                    // Desktop-only extra rows
                    if (_isWideScreen) ...[
                      const SizedBox(height: 4),
                      // Category + city row
                      Row(
                        children: [
                          if (localizedCategory.isNotEmpty) ...[
                            Icon(
                              CupertinoIcons.tag,
                              size: 10,
                              color: TradeRepublicTheme.hintColor(
                                context,
                                opacity: 0.45,
                              ),
                            ),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                localizedCategory,
                                style: TradeRepublicTheme.bodySmall(
                                  context,
                                ).copyWith(fontSize: 11),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ] else if (city.isNotEmpty) ...[
                            Icon(
                              CupertinoIcons.location,
                              size: 10,
                              color: TradeRepublicTheme.hintColor(
                                context,
                                opacity: 0.45,
                              ),
                            ),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                city,
                                style: TradeRepublicTheme.bodySmall(
                                  context,
                                ).copyWith(fontSize: 11),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ] else
                            const Spacer(),
                          if (city.isNotEmpty &&
                              localizedCategory.isNotEmpty) ...[
                            const SizedBox(width: 5),
                            Icon(
                              CupertinoIcons.location,
                              size: 10,
                              color: TradeRepublicTheme.hintColor(
                                context,
                                opacity: 0.35,
                              ),
                            ),
                            const SizedBox(width: 2),
                            Text(
                              city,
                              style: TradeRepublicTheme.bodySmall(
                                context,
                              ).copyWith(fontSize: 10.5),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                      if (incotermClean.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              CupertinoIcons.arrowshape_turn_up_right,
                              size: 10,
                              color: TradeRepublicTheme.hintColor(
                                context,
                                opacity: 0.45,
                              ),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              'Incoterm: $incotermClean',
                              style: TradeRepublicTheme.bodySmall(
                                context,
                              ).copyWith(fontSize: 11),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 4),
                      // Stock + min order + views
                      Row(
                        children: [
                          if (stockLabel != null) ...[
                            Icon(
                              CupertinoIcons.cube_box,
                              size: 10,
                              color:
                                  stockLabel == '∞' ||
                                      (int.tryParse(stockLabel) ?? 0) > 5
                                  ? TradeRepublicTheme.accentGreen
                                  : TradeRepublicTheme.destructiveRed,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              stockLabel == '∞'
                                  ? 'In stock'
                                  : '$stockLabel left',
                              style: TradeRepublicTheme.bodySmall(context)
                                  .copyWith(
                                    fontSize: 11,
                                    color:
                                        stockLabel == '∞' ||
                                            (int.tryParse(stockLabel) ?? 0) > 5
                                        ? TradeRepublicTheme.accentGreen
                                        : TradeRepublicTheme.destructiveRed,
                                  ),
                            ),
                          ],
                          if (minOrder > 1) ...[
                            if (stockLabel != null) const SizedBox(width: 6),
                            Icon(
                              CupertinoIcons.cart,
                              size: 10,
                              color: TradeRepublicTheme.hintColor(
                                context,
                                opacity: 0.4,
                              ),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              'Min $minOrder',
                              style: TradeRepublicTheme.bodySmall(
                                context,
                              ).copyWith(fontSize: 11),
                            ),
                          ],
                          const Spacer(),
                          if (views > 0) ...[
                            Icon(
                              CupertinoIcons.eye,
                              size: 10,
                              color: TradeRepublicTheme.hintColor(
                                context,
                                opacity: 0.3,
                              ),
                            ),
                            const SizedBox(width: 2),
                            Text(
                              '$views',
                              style: TradeRepublicTheme.bodySmall(
                                context,
                              ).copyWith(fontSize: 10.5),
                            ),
                          ],
                        ],
                      ),
                    ],
                    const Spacer(),
                    // Seller
                    Text(
                      sellerName.isNotEmpty ? '@$sellerName' : '',
                      style: TradeRepublicTheme.bodySmall(
                        context,
                      ).copyWith(fontSize: 10),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardPlaceholder(bool isDark) {
    return SizedBox.expand(
      child: ColoredBox(
        color: TradeRepublicTheme.hintColor(context, opacity: 0.05),
        child: Center(
          child: Icon(
            CupertinoIcons.leaf_arrow_circlepath,
            size: 28,
            color: TradeRepublicTheme.hintColor(context, opacity: 0.15),
          ),
        ),
      ),
    );
  }

  void _showProductDetails(Map<String, dynamic> product) async {
    // First increment view count
    final productId = product['id'];
    if (productId != null) {
      await _incrementProductViews(productId);
      // Reload product list to show updated views
      _loadProducts();
    }

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      useRootNavigator: true,
      maxHeight: MediaQuery.of(context).size.height * 0.95,
      child: ProductDetailsModal(
        product: product,
        showBottomMessage: _showBottomMessage,
        onCartChanged: _onCartChanged,
        onFavoriteToggle: _onFavoriteToggleFromModal,
        favoriteProductIds:
            _favoriteProductIds, // Pass current favorites list
        isMainAppLoggedIn:
            _isLoggedIn, // Pass main app login status for synchronization
        numberFormat: _resolveNumberFormat(), // Pass number format preference
        currency: _resolveCurrency(), // Pass currency preference
        exchangeRate: _exchangeRate, // Pass exchange rate
      ),
    );
  }

  // Helper method to get stock from variants
  int _getProductStock(Map<String, dynamic> product) {
    // Check if product is always available first
    final alwaysAvailable = product['alwaysAvailable'];
    if (alwaysAvailable == 1 || alwaysAvailable == true) {
      return 999; // Return high stock count for always available products
    }

    final variants = product['variants'];
    if (variants is List && variants.isNotEmpty) {
      final firstVariant = variants[0];
      final variantAlwaysAvailable = firstVariant['alwaysAvailable'];
      if (variantAlwaysAvailable == 1 || variantAlwaysAvailable == true) {
        return 999; // Return high stock count for always available variants
      }
      final stock = firstVariant['stock'];
      if (stock != null) {
        return int.tryParse(stock.toString()) ?? 0;
      }
    }
    return 0;
  }

  // Helper method to build stock badge
  Widget _buildStockBadge(Map<String, dynamic> product, bool isDark) {
    final alwaysAvailable = product['alwaysAvailable'];
    final isAlwaysAvailable = alwaysAvailable == 1 || alwaysAvailable == true;

    // Check variant level alwaysAvailable as well
    bool variantAlwaysAvailable = false;
    final variants = product['variants'];
    if (variants is List && variants.isNotEmpty) {
      final firstVariant = variants[0];
      final variantAlways = firstVariant['alwaysAvailable'];
      variantAlwaysAvailable = variantAlways == 1 || variantAlways == true;
    }

    final stock = _getProductStock(product);
    final isInStock = stock > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isInStock
            ? (isDark ? Colors.green[800] : Colors.green[100])
            : (isDark ? Colors.red[800] : Colors.red[100]),
        borderRadius: BorderRadius.circular(25),
      ),
      child: Text(
        (isAlwaysAvailable || variantAlwaysAvailable)
            ? 'Always'
            : (isInStock ? '$stock' : 'Out'),
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: isInStock
              ? (isDark ? Colors.green[300] : Colors.green[800])
              : (isDark ? Colors.red[300] : Colors.red[800]),
        ),
      ),
    );
  }

  // Helper functions for correct price display
  double _getProductPrice(Map<String, dynamic> product) {
    // First check variants
    final variants = product['variants'];
    if (variants is List && variants.isNotEmpty) {
      final firstVariant = variants[0];
      final price = firstVariant['price'];
      if (price != null) {
        return double.tryParse(price.toString()) ?? 0.0;
      }
    }

    // Fallback to shipping_cost (like Apple)
    final shippingCost = product['shipping_cost'];
    if (shippingCost != null) {
      return double.tryParse(shippingCost.toString()) ?? 0.0;
    }

    // Last fallback to product price
    final productPrice = product['price'];
    if (productPrice != null) {
      return double.tryParse(productPrice.toString()) ?? 0.0;
    }

    return 0.0;
  }

  String _getProductDisplayPrice(Map<String, dynamic> product) {
    final price = _getProductPrice(product);
    return _formatCurrency(price);
  }

  // Helper method to safely parse price values that could be String or num
  double _parsePrice(dynamic price) {
    if (price == null) return 0.0;
    if (price is String) {
      return double.tryParse(price) ?? 0.0;
    } else if (price is num) {
      return price.toDouble();
    }
    return 0.0;
  }

  // Helper method to format numbers with thousand separators (e.g., 1,234.56 or 1.234,56)
  String _formatCurrency(double amount) {
    setNumberFormatStyleIndex(_resolveNumberFormat() == 'de' ? 1 : 0);
    final cur = _resolveCurrency();
    final formatted = formatNumberUS(amount);
    switch (cur) {
      case 'eur': return '€$formatted';
      case 'gbp': return '£$formatted';
      case 'cad': return 'CA\$$formatted';
      case 'mxn': return 'MX\$$formatted';
      case 'rub': return '₽$formatted';
      case 'pln': return '$formatted zł';
      case 'czk': return '$formatted Kč';
      case 'huf': return '$formatted Ft';
      case 'sek': return '${formatted}kr';
      case 'dkk': return '${formatted}kr';
      case 'nok': return '${formatted}kr';
      case 'chf': return 'Fr.$formatted';
      case 'bgn': return '$formatted лв';
      case 'ron': return '$formatted lei';
      case 'usd':
      default:    return '\$$formatted';
    }
  }

  // View count API call
  Future<void> _incrementProductViews(int productId) async {
    try {
      await ApiService.incrementProductView(productId);
    } catch (e) {
      //debugPrint('❌ Error incrementing view count: $e');
    }
  }

  void _showCartModal(bool isDark) {
    // Check if user is logged in
    if (!_isLoggedIn) {
      _showBottomMessage(
        AppLocalizations.of(context)!.pleaseLoginToViewCart,
        isError: true,
      );
      return;
    }

    Future.microtask(() => setState(() => _isModalOpen = true));
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      useRootNavigator: false,
      sheetTitle: 'Cart',
      maxHeight: MediaQuery.of(context).size.height * 0.9,
      child: RepaintBoundary(
        child: CartModal(
          showBottomMessage: _showBottomMessage,
          onCartChanged: _onCartChanged,
          onProceedToCheckout: _showCheckoutModal,
          currency: _resolveCurrency(),
          exchangeRate: _exchangeRate,
          numberFormat: _resolveNumberFormat(),
        ),
      ),
    ).whenComplete(() {
      Future.microtask(() => setState(() => _isModalOpen = false));
      _loadCartCount();
    });
  }

  void _showCheckoutModal(
    bool isDark,
    List<Map<String, dynamic>> cartItems,
    double totalPrice,
  ) {
    //debugPrint('🛒 _showCheckoutModal called with:');
    //debugPrint('   - isDark: $isDark');
    //debugPrint('   - cartItems: ${cartItems.length} items');
    //debugPrint('   - totalPrice: {currencySymbol}$totalPrice');

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      useRootNavigator: false,
      sheetTitle: 'Checkout',
      maxHeight: MediaQuery.of(context).size.height * 0.9,
      child: RepaintBoundary(
        child: CheckoutModal(
          cartItems: cartItems,
          totalPrice: totalPrice,
          accessToken: _accessToken,
          currentUser: _currentUser,
          numberFormat: _resolveNumberFormat(), // Pass number format
          onOrderComplete: () {
            // Callback when order is completed successfully
            _loadCartCount(); // Reload cart count
            _showBottomMessage(
              AppLocalizations.of(context)!.orderPlacedSuccess,
              isSuccess: true,
            );
          },
        ),
      ),
    );
  }

  // OLD _buildCheckoutModal REMOVED - NOW USING SEPARATE CheckoutModal CLASS

  Future<void> _processPayment(
    Map<String, dynamic> paymentIntent,
    String paymentMethodId,
  ) async {
    // Here you would integrate with Stripe SDK to confirm the payment
    // For now, we'll simulate a successful payment
    await Future.delayed(const Duration(seconds: 2));

    // In a real implementation, you would:
    // 1. Use Stripe SDK to confirm payment with the payment intent
    // 2. Handle 3D Secure authentication if required
    // 3. Update the order status in your backend
    // 4. Clear the cart

    //debugPrint('Payment processed successfully with payment intent: ${paymentIntent['id']}');
    //debugPrint('Payment method: $paymentMethodId');
  }

  Widget _buildDetailRow(String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartItem(Map<String, dynamic> item, int index, bool isDark) {
    final price =
        double.tryParse(
          item['variant_price']?.toString() ??
              item['price']?.toString() ??
              '0.0',
        ) ??
        0.0;
    final quantity = item['quantity'] ?? 1;
    final totalItemPrice = price * quantity;

    final flatCart = CultiooDesktopLayout.isDesktopPlatform;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: flatCart
            ? Colors.transparent
            : (isDark ? Colors.grey[850] : Colors.grey[50]),
        borderRadius: BorderRadius.circular(25),
      ),
      child: Row(
        children: [
          // Product Image
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(25),
              color: flatCart
                  ? (isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.06))
                  : (isDark ? Colors.grey[800] : Colors.grey[100]),
            ),
            child: item['image_url'] != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(25),
                    child: item['image_url'].startsWith('data:image')
                        ? Image.memory(
                            base64Decode(item['image_url'].split(',')[1]),
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Icon(
                                CupertinoIcons.photo,
                                color: isDark ? Colors.white38 : Colors.black38,
                              );
                            },
                          )
                        : Image.network(
                            item['image_url'],
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Icon(
                                CupertinoIcons.photo,
                                color: isDark ? Colors.white38 : Colors.black38,
                              );
                            },
                          ),
                  )
                : Icon(
                    CupertinoIcons.bag,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
          ),

          const SizedBox(width: 16),

          // Product Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['name'] ?? AppLocalizations.of(context)!.unknownProduct,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                if (item['variant_title'] != null)
                  Text(
                    item['variant_title'],
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatCurrency(totalItemPrice),
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.green[300] : Colors.green[700],
                      ),
                    ),
                    Row(
                      children: [
                        // Decrease quantity
                        TradeRepublicButton(
                          icon: Icon(
                            quantity > 1
                                ? CupertinoIcons.minus
                                : CupertinoIcons.delete,
                            size: 18,
                            color: quantity > 1
                                ? (isDark ? Colors.white : Colors.black)
                                : Colors.red[400],
                          ),
                          onPressed: () {
                            if (mounted) {
                              setState(() {
                                if (quantity > 1) {
                                  _cartItems[index]['quantity'] = quantity - 1;
                                } else {
                                  _cartItems.removeAt(index);
                                }
                              });
                            }
                          },
                        ),

                        const SizedBox(width: 16),

                        Text(
                          quantity.toString(),
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),

                        const SizedBox(width: 16),

                        // Increase quantity
                        TradeRepublicButton(
                          icon: const Icon(
                            CupertinoIcons.add,
                            size: 18,
                            color: Colors.white,
                          ),
                          tint: isDark
                              ? Colors.orange[700]
                              : Colors.orange[600],
                          onPressed: () {
                            if (mounted) {
                              setState(() {
                                _cartItems[index]['quantity'] = quantity + 1;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(dynamic dateValue) {
    if (dateValue == null) return AppLocalizations.of(context)!.noDate;

    try {
      DateTime date;
      if (dateValue is String) {
        date = DateTime.parse(dateValue);
      } else if (dateValue is DateTime) {
        date = dateValue;
      } else {
        return AppLocalizations.of(context)!.invalidDate;
      }

      // Use local time
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays == 0) {
        return 'Today ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      } else if (difference.inDays == 1) {
        return 'Yesterday ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      } else if (difference.inDays < 7) {
        return '${difference.inDays} days ago';
      } else if (difference.inDays < 30) {
        return '${(difference.inDays / 7).floor()} weeks ago';
      } else if (difference.inDays < 365) {
        return '${(difference.inDays / 30).floor()} months ago';
      } else {
        // Use the user's preferred date format for older dates
        final day = date.day.toString().padLeft(2, '0');
        final month = date.month.toString().padLeft(2, '0');
        final year = date.year.toString();
        final time =
            '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

        String dateStr;
        switch (_resolveDateFormat()) {
          case 'MM/dd/yyyy':
            dateStr = '$month/$day/$year';
            break;
          case 'yyyy-MM-dd':
            dateStr = '$year-$month-$day';
            break;
          case 'dd-MM-yyyy':
            dateStr = '$day-$month-$year';
            break;
          case 'dd/MM/yyyy':
            dateStr = '$day/$month/$year';
            break;
          case 'dd.MM.yyyy':
          default:
            dateStr = '$day.$month.$year';
            break;
        }

        return '$dateStr $time';
      }
    } catch (e) {
      return AppLocalizations.of(context)!.invalidDateFormat;
    }
  }

  Widget _buildOrdersPage(bool isDark) {
    // Check if user is logged in before trying to fetch orders
    if (!_isLoggedIn) {
      return SingleChildScrollView(
        padding: CultiooDesktopLayout.pageContentPadding(context),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: _isWideScreen
                  ? _desktopMaxContentWidth
                  : double.infinity,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                // Header
                Row(
                  children: [
                    Icon(
                      CupertinoIcons.doc_text_fill,
                      color: isDark ? Colors.white : Colors.black,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        AppLocalizations.of(context)!.myOrders,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          color: isDark ? Colors.white : Colors.black,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 40),
                Center(
                  child: Column(
                    children: [
                      Icon(
                        CupertinoIcons.arrow_right_square,
                        size: 80,
                        color: (isDark ? Colors.white : Colors.black)
                            .withOpacity(0.3),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        AppLocalizations.of(context)!.pleaseSignIn,
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black54,
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        AppLocalizations.of(context)!.signInToViewOrders,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          color: isDark ? Colors.white54 : Colors.black45,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    _ordersFuture ??= _loadOrdersWithSync();
    return FutureBuilder<Map<String, dynamic>>(
      future: _ordersFuture,
      builder: (context, snapshot) {
        return CustomScrollView(
          physics: CultiooDesktopLayout.adaptiveScrollPhysics(context),
          slivers: [
            if (!CultiooDesktopLayout.isDesktopPlatform)
              CultiooSliverRefreshControl(
                onRefresh: () async {
                  setState(() {
                    _ordersFuture = _loadOrdersWithSync();
                  });
                  await _ordersFuture;
                },
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: CultiooDesktopLayout.pageContentPadding(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 20),

                    // Header
                    TweenAnimationBuilder<double>(
                      duration: const Duration(milliseconds: 400),
                      tween: Tween(begin: 0.0, end: 1.0),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, child) {
                        return Transform.translate(
                          offset: Offset(-30 * (1 - value), 0),
                          child: Opacity(opacity: value, child: child),
                        );
                      },
                      child: Row(
                        children: [
                          Icon(
                            CupertinoIcons.doc_text_fill,
                            color: isDark ? Colors.white : Colors.black,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              AppLocalizations.of(context)!.myOrders,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                                color: isDark ? Colors.white : Colors.black,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Statistics
                    if (snapshot.hasData &&
                        snapshot.data!['success'] == true) ...[
                      _buildOrdersStatisticsSection(
                        isDark,
                        snapshot.data!['orders'] as List<dynamic>,
                      ),
                      const SizedBox(height: 24),
                      _buildOrdersControls(isDark),
                      const SizedBox(height: 24),
                    ],

                    // Content
                    if (snapshot.connectionState == ConnectionState.waiting)
                      _buildOrdersLoading(isDark)
                    else if (snapshot.hasError)
                      _buildOrdersError(isDark, snapshot.error.toString())
                    else if (snapshot.hasData) ...[
                      if (snapshot.data!['success'] == true) ...[
                        Builder(
                          builder: (context) {
                            final allOrders =
                                snapshot.data!['orders'] as List<dynamic>;
                            final visibleOrders = _filterAndSortOrders(allOrders);
                            return _buildOrdersList(
                              isDark,
                              visibleOrders,
                              allOrders,
                            );
                          },
                        ),
                      ]
                      else
                        _buildOrdersError(
                          isDark,
                          snapshot.data!['message'] ??
                              AppLocalizations.of(context)!.unknownError,
                        ),
                    ] else
                      _buildOrdersEmpty(isDark),

                    const SizedBox(height: 120),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildOrdersLoading(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CultiooLoadingIndicator(),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.of(context)!.loadingYourOrders,
            style: TextStyle(
              fontFamily: 'Poppins',
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrdersError(bool isDark, String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            CupertinoIcons.exclamationmark_circle,
            size: 64,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.of(context)!.errorLoadingOrders,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            error,
            style: TextStyle(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          TradeRepublicButton(
            label: AppLocalizations.of(context)!.retry,
            onPressed: () => setState(() {}),
          ),
        ],
      ),
    );
  }

  Widget _buildOrdersEmpty(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            CupertinoIcons.doc_text,
            size: 64,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.of(context)!.noOrdersYet,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.of(context)!.ordersWillAppearHere,
            style: TextStyle(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildOrdersList(
    bool isDark,
    List<dynamic> orders,
    List<dynamic> allOrders,
  ) {
    // Filter out locally dismissed orders
    final visibleOrders = orders.where((o) {
      final id = o['id'];
      if (!_dismissedOrderIds.contains(id)) return true;
      final status = (o['status'] ?? '').toString().toLowerCase();
      final isClosed = [
        'completed',
        'delivered',
        'cancelled',
        'canceled',
        'refunded',
        'succeeded',
        'closed',
      ].contains(status);
      return !isClosed;
    }).toList();

    if (visibleOrders.isEmpty) {
      return _buildOrdersEmpty(isDark);
    }

    return Column(
      children: visibleOrders.asMap().entries.map((entry) {
        final index = entry.key;
        final order = entry.value;
        final status = (order['status'] ?? '').toString().toLowerCase();
        final isClosed = [
          'completed',
          'delivered',
          'cancelled',
          'canceled',
          'refunded',
          'succeeded',
          'closed',
        ].contains(status);

        // Staggered animation
        final isFromTop = index % 2 == 0;
        final card = TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: Duration(milliseconds: 400 + (index * 100)),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) {
            return Transform.translate(
              offset: Offset(
                0,
                isFromTop ? -30 * (1 - value) : 30 * (1 - value),
              ),
              child: Opacity(opacity: value, child: child),
            );
          },
          child: _buildOrderCard(isDark, order, allOrders),
        );

        if (!isClosed) return card;

        return _SwipeToHideOrder(
          key: ValueKey('swipe_${order['id']}'),
          isDark: isDark,
          onDismissed: () {
            setState(() => _dismissedOrderIds.add(order['id']));
            _saveDismissedOrderIds();
          },
          child: card,
        );
      }).toList(),
    );
  }

  List<Map<String, dynamic>> _extractSplitOrderFamilyEntries(
    Map<String, dynamic> order,
    List<dynamic> sourceOrders,
  ) {
    int? toOrderInt(dynamic value) {
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '');
    }

    final rawOrderId = order['id'];
    final orderId = toOrderInt(rawOrderId);
    if (orderId == null) return const <Map<String, dynamic>>[];

    final rawParent = order['parent_order_id'];
    final parentId = toOrderInt(rawParent);
    final familyRoot = parentId ?? orderId;

    final byId = <int, Map<String, dynamic>>{};
    byId[orderId] = order;
    for (final entry in sourceOrders) {
      if (entry is! Map<String, dynamic>) continue;
      final rawEntryId = entry['id'];
      final entryId = toOrderInt(rawEntryId);
      if (entryId == null) continue;
      final rawEntryParent = entry['parent_order_id'];
      final entryParent = toOrderInt(rawEntryParent);
      if (entryId == familyRoot || entryParent == familyRoot) {
        byId[entryId] = entry;
      }
    }
    final entries = byId.entries.toList()
      ..sort((a, b) {
        final ap = toOrderInt(a.value['split_order_part']) ?? 999;
        final bp = toOrderInt(b.value['split_order_part']) ?? 999;
        if (ap != bp) return ap.compareTo(bp);
        return a.key.compareTo(b.key);
      });
    return entries
        .map((e) => {
              'id': e.key,
              'status': (e.value['status'] ?? 'pending').toString(),
              'amount': e.value['total_amount'] ?? e.value['amount'],
              'parent_order_id': e.value['parent_order_id'],
              'split_order_part': e.value['split_order_part'],
              'split_order': e.value['split_order'],
            })
        .toList();
  }

  String _displaySplitOrderNumber(Map<String, dynamic> order) {
    int? toOrderInt(dynamic value) {
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '');
    }

    final id = toOrderInt(order['id']);
    if (id == null) return '—';
    final parentId = toOrderInt(order['parent_order_id']);
    final base = parentId ?? id;
    final part = toOrderInt(order['split_order_part']);
    final rawSplit = order['split_order'];
    final isSplit = rawSplit == true ||
        rawSplit == 1 ||
        rawSplit.toString() == '1' ||
        parentId != null ||
        (part != null && part > 0);
    if (isSplit && part != null && part > 0) {
      return '$base.$part';
    }
    return '$base';
  }

  String _formatOrderHeadline(
    Map<String, dynamic> order,
    List<dynamic> sourceOrders,
  ) {
    return 'Order #${_displaySplitOrderNumber(order)}';
  }

  Widget _buildOrderCard(
    bool isDark,
    Map<String, dynamic> order,
    List<dynamic> sourceOrders,
  ) {
    final status = order['status'] ?? 'pending';
    final orderDate = DateTime.tryParse(order['order_date']?.toString() ?? '');

    // Parse totalAmount safely - could be String or number from database
    double totalAmount = 0.0;
    final totalAmountRaw = order['total_amount'];
    if (totalAmountRaw is String) {
      totalAmount = double.tryParse(totalAmountRaw) ?? 0.0;
    } else if (totalAmountRaw is num) {
      totalAmount = totalAmountRaw.toDouble();
    }

    final items = order['items'] as List<dynamic>? ?? [];
    final paymentStatus = order['payment_status'] ?? 'pending';
    final isPaid = paymentStatus == 'paid' || paymentStatus == 'completed';

    Color statusColor;
    IconData statusIcon;
    String displayStatus;

    switch (status.toLowerCase()) {
      case 'completed':
      case 'delivered':
        statusColor = Colors.green;
        statusIcon = CupertinoIcons.checkmark_circle;
        displayStatus = 'DELIVERED';
        break;
      case 'succeeded':
        statusColor = Colors.green;
        statusIcon = CupertinoIcons.creditcard_fill;
        displayStatus = AppLocalizations.of(context)!.statusPaymentSuccessful;
        break;
      case 'confirmed':
        if (isPaid) {
          statusColor = Colors.green;
          statusIcon = CupertinoIcons.checkmark_seal_fill;
          displayStatus = 'CONFIRMED';
        } else {
          statusColor = Colors.orange;
          statusIcon = CupertinoIcons.clock;
          displayStatus = AppLocalizations.of(context)!.statusAwaitingPayment;
        }
        break;
      case 'accepted':
        statusColor = Colors.blue;
        statusIcon = CupertinoIcons.hand_thumbsup_fill;
        displayStatus = 'ACCEPTED';
        break;
      case 'ready_for_pickup':
        statusColor = Colors.teal;
        statusIcon = CupertinoIcons.cube_box;
        displayStatus = AppLocalizations.of(context)!.statusReadyForPickup;
        break;
      case 'in_transit':
      case 'shipped':
        statusColor = Colors.blue;
        statusIcon = CupertinoIcons.cube_box;
        displayStatus = 'SHIPPED';
        break;
      case 'pending':
        statusColor = Colors.orange;
        statusIcon = CupertinoIcons.time;
        displayStatus = 'PROCESSING';
        break;
      case 'awaiting':
      case 'approval_requested':
        statusColor = Colors.orange;
        statusIcon = CupertinoIcons.clock;
        displayStatus = AppLocalizations.of(context)!.statusAwaitingApproval;
        break;
      case 'payment_failed':
        statusColor = Colors.red;
        statusIcon = CupertinoIcons.exclamationmark_circle;
        displayStatus = AppLocalizations.of(context)!.statusPaymentFailed;
        break;
      case 'cancelled':
      case 'canceled':
        statusColor = Colors.red;
        statusIcon = CupertinoIcons.xmark_circle;
        displayStatus = 'CANCELLED';
        break;
      case 'refunded':
        statusColor = Colors.purple;
        statusIcon = CupertinoIcons.arrow_counterclockwise;
        displayStatus = 'REFUNDED';
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = CupertinoIcons.question_circle;
        displayStatus = status.toUpperCase().replaceAll('_', ' ');
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? Colors.black : Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Order Header
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatOrderHeadline(order, sourceOrders),
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (orderDate != null)
                      Text(
                        _formatOrderDate(orderDate),
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, size: 16, color: statusColor),
                    const SizedBox(width: 6),
                    Text(
                      displayStatus,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Order Items
          if (items.isNotEmpty) ...[
            Text(
              AppLocalizations.of(context)!.itemsCount(items.length),
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            ...items
                .take(3)
                .map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Text(
                          '• ',
                          style: TextStyle(
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                        Expanded(
                          child: Text(
                            '${item['name'] ?? AppLocalizations.of(context)!.unknownProduct} (${item['quantity'] ?? 1}x)',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 14,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                          ),
                        ),
                        Text(
                          _formatCurrency(_parsePrice(item['price'])),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            if (items.length > 3)
              Text(
                '+${items.length - 3} more items',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
            const SizedBox(height: 16),
          ],

          // Order Total and Actions
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.total,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                    Text(
                      _formatCurrency(totalAmount),
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
              TradeRepublicButton(
                label: AppLocalizations.of(context)!.viewDetails,
                onPressed: () => _showOrderDetails(order, sourceOrders),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatOrderDate(DateTime date) {
    // Use local time
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'Today, ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return 'Yesterday, ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      final dateStr = _formatDatePreview(date, _dateFormat);
      return '$dateStr ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }
  }

  void _showOrderDetails(Map<String, dynamic> order, List<dynamic> sourceOrders) {
    final linkedSplitOrders = _extractSplitOrderFamilyEntries(order, sourceOrders);
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      useRootNavigator: true,
      maxHeight: MediaQuery.of(context).size.height * 0.92,
      child: OrderDetailsModal(
        order: order,
        linkedSplitOrders: linkedSplitOrders,
        numberFormat: _resolveNumberFormat(), // Pass number format
        onOrderUpdated: () {
          // Refresh orders when an order is updated
          setState(() {
            _ordersFuture = null; // Reset so FutureBuilder re-fetches
          });
        },
      ),
    );
  }

  // Orders Statistics Section
  Widget _buildOrdersStatisticsSection(bool isDark, List<dynamic> orders) {
    final stats = _calculateMonthlyStats(orders);
    final totalSpent = stats['totalSpent'] as double;
    final totalOrders = stats['totalOrders'] as int;

    final chartData = _filterAndSortOrders(orders)
        .where((o) {
          final status = o['status']?.toString().toLowerCase() ?? '';
          return status != 'closed' && status != 'cancelled';
        })
        .map((o) => _parsePrice(o['total_amount']))
        .where((v) => v > 0)
        .toList()
        .cast<double>();

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.05)
            : Colors.white.withOpacity(0.8),
        borderRadius: BorderRadius.circular(25),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                CupertinoIcons.chart_bar,
                color: isDark ? Colors.white : Colors.black,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                _selectedOrderMonth == 'all'
                    ? AppLocalizations.of(context)!.totalStatistics
                    : AppLocalizations.of(context)!.monthlyStatistics,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.totalSpent,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatCurrency(totalSpent),
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF4CAF50),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.ordersCount,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$totalOrders',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (chartData.isNotEmpty) ...[
            const SizedBox(height: 20),
            SizedBox(
              height: 100,
              child: TradeRepublicBarChart(
                data: chartData,
                isLight: !isDark,
                valueFormatter: _formatCurrency,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Orders Controls (Month Selector and Sort)
  Widget _buildOrdersControls(bool isDark) {
    return Row(
      children: [
        // Month Selector
        Expanded(
          child: TradeRepublicButton(
            label: _getMonthDisplayName(),
            onPressed: () => _showMonthSelector(isDark),
          ),
        ),
        const SizedBox(width: 12),
        // Sort Button
        TradeRepublicButton.icon(
          icon: const Icon(CupertinoIcons.ellipsis_vertical),
          onPressed: () => _showOrdersSortSelector(isDark),
          size: 50,
        ),
        const SizedBox(width: 12),
        // Sync Button
        TradeRepublicButton.icon(
          icon: const Icon(CupertinoIcons.arrow_2_circlepath),
          onPressed: () => _manualSyncOrderStatuses(isDark),
          size: 50,
        ),
      ],
    );
  }

  // Calculate monthly statistics
  Map<String, dynamic> _calculateMonthlyStats(List<dynamic> orders) {
    double totalSpent = 0.0;
    int totalOrders = 0;

    final filteredOrders = _filterOrdersByMonth(orders);

    for (final order in filteredOrders) {
      final status = order['status']?.toString().toLowerCase() ?? '';
      if (status == 'closed' || status == 'cancelled') continue;
      totalOrders++;
      final amount = _parsePrice(order['total_amount']);
      totalSpent += amount;
    }

    return {'totalSpent': totalSpent, 'totalOrders': totalOrders};
  }

  // Filter and sort orders
  List<dynamic> _filterAndSortOrders(List<dynamic> orders) {
    int? toOrderInt(dynamic value) {
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '');
    }

    final monthFiltered = _filterOrdersByMonth(orders);
    var filteredOrders = monthFiltered;

    // Apply awaiting filter if enabled (and keep split families together)
    if (_showAwaitingOnly) {
      final base = monthFiltered.where((order) {
        final status = order['status']?.toString().toLowerCase() ?? '';
        return status == 'awaiting' ||
            status == 'confirmed' ||
            status == 'pending';
      }).toList();

      final familyRoots = <int>{};
      for (final o in base) {
        if (o is! Map<String, dynamic>) continue;
        final id = toOrderInt(o['id']);
        if (id == null) continue;
        final parentId = toOrderInt(o['parent_order_id']);
        familyRoots.add(parentId ?? id);
      }

      if (familyRoots.isNotEmpty) {
        filteredOrders = monthFiltered.where((order) {
          if (order is! Map<String, dynamic>) return false;
          final id = toOrderInt(order['id']);
          if (id == null) return false;
          final parentId = toOrderInt(order['parent_order_id']);
          return familyRoots.contains(parentId ?? id);
        }).toList();
      } else {
        filteredOrders = base;
      }
    }

    return _sortOrdersByOption(filteredOrders);
  }

  // Filter orders by selected month
  List<dynamic> _filterOrdersByMonth(List<dynamic> orders) {
    if (_selectedOrderMonth == 'all') {
      return orders;
    }

    return orders.where((order) {
      final orderDate = DateTime.tryParse(
        order['order_date']?.toString() ?? '',
      );
      if (orderDate == null) return false;

      final orderMonthKey =
          '${orderDate.year}-${orderDate.month.toString().padLeft(2, '0')}';
      return orderMonthKey == _selectedOrderMonth;
    }).toList();
  }

  // Load orders with automatic Stripe status sync
  Future<Map<String, dynamic>> _loadOrdersWithSync() async {
    try {
      // First, sync order statuses with Stripe in the background
      // Don't wait for this to complete to avoid delaying the UI
      ApiService.syncOrderStatusesWithStripe().catchError((error) {
        debugPrint('⚠️ Background sync failed: $error');
        return <String, dynamic>{}; // Return empty map on error
      });

      // Load orders normally
      return await ApiService.getUserOrders();
    } catch (error) {
      // If sync fails, still try to load orders
      return await ApiService.getUserOrders();
    }
  }

  // Sort orders by selected option
  List<dynamic> _sortOrdersByOption(List<dynamic> orders) {
    final sortedOrders = List<dynamic>.from(orders);

    switch (_ordersSortOption) {
      case 'date_desc':
        sortedOrders.sort((a, b) {
          final dateA =
              DateTime.tryParse(a['order_date']?.toString() ?? '') ??
              DateTime.now();
          final dateB =
              DateTime.tryParse(b['order_date']?.toString() ?? '') ??
              DateTime.now();
          return dateB.compareTo(dateA);
        });
        break;
      case 'date_asc':
        sortedOrders.sort((a, b) {
          final dateA =
              DateTime.tryParse(a['order_date']?.toString() ?? '') ??
              DateTime.now();
          final dateB =
              DateTime.tryParse(b['order_date']?.toString() ?? '') ??
              DateTime.now();
          return dateA.compareTo(dateB);
        });
        break;
      case 'price_desc':
        sortedOrders.sort((a, b) {
          final priceA = _parsePrice(a['total_amount']);
          final priceB = _parsePrice(b['total_amount']);
          return priceB.compareTo(priceA);
        });
        break;
      case 'price_asc':
        sortedOrders.sort((a, b) {
          final priceA = _parsePrice(a['total_amount']);
          final priceB = _parsePrice(b['total_amount']);
          return priceA.compareTo(priceB);
        });
        break;
      case 'status':
        sortedOrders.sort((a, b) {
          final statusA = a['status']?.toString() ?? '';
          final statusB = b['status']?.toString() ?? '';
          return statusA.compareTo(statusB);
        });
        break;
    }

    return sortedOrders;
  }

  // Manual sync of order statuses with Stripe
  Future<void> _manualSyncOrderStatuses(bool isDark) async {
    // Show loading modal
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      isDismissible: false,
      enableDrag: false,
      useRootNavigator: false,
      sheetTitle: AppLocalizations.of(context)!.syncingWithStripe,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CultiooLoadingIndicator(),
          const SizedBox(height: 20),
          Text(
            AppLocalizations.of(context)!.syncingWithStripe,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.of(context)!.checkingPaymentStatuses,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );

    try {
      // Call the sync API
      final result = await ApiService.syncOrderStatusesWithStripe();

      // Close loading modal
      TradeRepublicBottomSheet.hide(context);

      // Show result modal
      TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      useRootNavigator: false,
      sheetTitle: AppLocalizations.of(context)!.syncComplete,
      maxHeight: 500,
      child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                result['updated'] > 0
                    ? CupertinoIcons.checkmark_circle
                    : CupertinoIcons.info_circle,
                color: result['updated'] > 0 ? Colors.green : Colors.blue,
                size: 48,
              ),
              const SizedBox(height: 16),

              Text(
                AppLocalizations.of(context)!.syncComplete,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 8),

              Text(
                result['message'] ??
                    AppLocalizations.of(context)!.synchronizationCompleted,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withOpacity(0.05)
                      : Colors.black.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          AppLocalizations.of(context)!.ordersUpdated,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                        Text(
                          '${result['updated']}',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: result['updated'] > 0
                                ? Colors.green
                                : (isDark ? Colors.white : Colors.black),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          AppLocalizations.of(context)!.totalChecked,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                        Text(
                          '${result['total']}',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              TradeRepublicButton(
                label: AppLocalizations.of(context)!.ok,
                width: double.infinity,
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                onPressed: () {
                  Navigator.of(context).pop();
                  // Trigger refresh of orders
                  if (mounted) {
                    setState(() {});
                  }
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      );
    } catch (error) {
      // Close loading modal
      TradeRepublicBottomSheet.hide(context);

      // Show error modal
      TradeRepublicBottomSheet.show(
        context: context,
        showDragHandle: true,
        useRootNavigator: false,
        sheetTitle: AppLocalizations.of(context)!.syncFailed,
        maxHeight: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                CupertinoIcons.exclamationmark_circle,
                color: Colors.red,
                size: 48,
              ),
              const SizedBox(height: 16),

              Text(
                AppLocalizations.of(context)!.syncFailed,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 8),

              Text(
                error.toString().replaceAll('Exception: ', ''),
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),

              TradeRepublicButton(
                label: AppLocalizations.of(context)!.ok,
                width: double.infinity,
                isDestructive: true,
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      );
    }
  }

  // Get display name for selected month
  String _getMonthDisplayName() {
    if (_selectedOrderMonth == 'all') {
      return AppLocalizations.of(context)!.allMonths;
    }

    final parts = _selectedOrderMonth.split('-');
    if (parts.length != 2) return AppLocalizations.of(context)!.allMonths;

    final year = parts[0];
    final month = int.tryParse(parts[1]) ?? 1;

    const monthNames = [
      '',
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return '${monthNames[month]} $year';
  }

  // Show month selector modal
  void _showMonthSelector(bool isDark) {
    // Generate dynamic month list for current and previous months
    final now = DateTime.now();
    final monthOptions = <Widget>[];

    // Add "All Months" option first
    monthOptions.add(
      _buildMonthOption(AppLocalizations.of(context)!.allMonths, 'all', isDark),
    );

    // Generate last 12 months including current month
    for (int i = 0; i < 12; i++) {
      final monthDate = DateTime(now.year, now.month - i);
      final monthValue =
          '${monthDate.year}-${monthDate.month.toString().padLeft(2, '0')}';
      final monthNames = [
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December',
      ];
      final monthName = monthNames[monthDate.month - 1];
      final monthTitle = '$monthName ${monthDate.year}';

      monthOptions.add(_buildMonthOption(monthTitle, monthValue, isDark));
    }

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      useRootNavigator: true,
      maxHeight: 450,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.calendar,
                  color: isDark ? Colors.white : Colors.black,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context)!.selectMonth,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : Colors.black,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Add scrollable container for month options
          SizedBox(
            height: 300, // Fixed height for scrollable area
            child: SingleChildScrollView(child: Column(children: monthOptions)),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // Show sort selector modal
  void _showOrdersSortSelector(bool isDark) {
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      useRootNavigator: true,
      maxHeight: 500,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Row(
                children: [
                  Icon(
                    CupertinoIcons.arrow_up_arrow_down,
                    color: isDark ? Colors.white : Colors.black,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context)!.sortOrders,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : Colors.black,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildOrdersSortOption(
              AppLocalizations.of(context)!.newestFirst,
              'date_desc',
              CupertinoIcons.clock,
              isDark,
            ),
            _buildOrdersSortOption(
              AppLocalizations.of(context)!.highestPrice,
              'price_desc',
              CupertinoIcons.graph_square,
              isDark,
            ),
            _buildOrdersSortOption(
              AppLocalizations.of(context)!.byStatus,
              'status',
              CupertinoIcons.flag,
              isDark,
            ),

            // Separator
            const SizedBox(height: 12),
            Divider(
              color: isDark
                  ? Colors.white.withOpacity(0.1)
                  : Colors.black.withOpacity(0.1),
              thickness: 1,
            ),
            const SizedBox(height: 12),

            // Filter option for awaiting orders
            _buildAwaitingFilterOption(isDark),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // Build month option
  Widget _buildMonthOption(String title, String value, bool isDark) {
    final isSelected = _selectedOrderMonth == value;
    return TradeRepublicListTile(
      title: title,
      trailing: isSelected
          ? const Icon(
              CupertinoIcons.checkmark_circle_fill,
              color: Color(0xFF4CAF50),
              size: 20,
            )
          : null,
      onTap: () {
        setState(() => _selectedOrderMonth = value);
        Navigator.of(context).pop();
      },
    );
  }

  // Build sort option
  Widget _buildOrdersSortOption(
    String title,
    String value,
    IconData icon,
    bool isDark,
  ) {
    final isSelected = _ordersSortOption == value;
    return TradeRepublicListTile(
      title: title,
      leading: Icon(icon, size: 20),
      trailing: isSelected
          ? const Icon(
              CupertinoIcons.checkmark_circle_fill,
              color: Color(0xFF4CAF50),
              size: 20,
            )
          : null,
      onTap: () {
        setState(() => _ordersSortOption = value);
        Navigator.of(context).pop();
      },
    );
  }

  // Build awaiting filter option
  Widget _buildAwaitingFilterOption(bool isDark) {
    return TradeRepublicListTile(
      title: AppLocalizations.of(context)!.showAwaitingOnly,
      leading: Icon(
        CupertinoIcons.hourglass,
        color: _showAwaitingOnly ? Colors.orange : null,
        size: 20,
      ),
      titleColor: _showAwaitingOnly ? Colors.orange : null,
      trailing: _showAwaitingOnly
          ? const Icon(
              CupertinoIcons.checkmark_circle_fill,
              color: Colors.orange,
              size: 20,
            )
          : null,
      onTap: () {
        setState(() => _showAwaitingOnly = !_showAwaitingOnly);
        Navigator.of(context).pop();
      },
    );
  }

  Widget _buildMessagesPageBACKUP(
    bool isDark,
    Map<String, dynamic> conversation,
  ) {
    final otherUserName =
        conversation['other_user_name'] ??
        AppLocalizations.of(context)!.unknownUser;
    final otherUserUsername = conversation['other_user_username'] ?? 'unknown';
    final lastMessage = conversation['last_message'] ?? '';
    final lastMessageTime = conversation['last_message_time'];
    final hasUnread = conversation['has_unread'] == true;

    String timeString = '';
    if (lastMessageTime != null) {
      try {
        final dateTime = DateTime.parse(lastMessageTime);
        final now = DateTime.now();
        final difference = now.difference(dateTime);

        if (difference.inDays == 0) {
          timeString =
              '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
        } else if (difference.inDays == 1) {
          timeString = AppLocalizations.of(context)!.yesterday;
        } else if (difference.inDays < 7) {
          timeString = '${difference.inDays}d ago';
        } else {
          timeString = '${dateTime.day}/${dateTime.month}';
        }
      } catch (e) {
        timeString = '';
      }
    }

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 400),
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 20 * (1 - value)),
          child: Opacity(
            opacity: value.clamp(0.0, 1.0),
            child: Container(
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                borderRadius: BorderRadius.circular(25),
                border: Border.all(
                  color: hasUnread
                      ? const Color(0xFF007AFF).withOpacity(0.3)
                      : isDark
                      ? Colors.white.withOpacity(0.05)
                      : Colors.black.withOpacity(0.05),
                  width: hasUnread ? 1.0 : 0.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: hasUnread
                        ? const Color(0xFF007AFF).withOpacity(0.1)
                        : isDark
                        ? Colors.black.withOpacity(0.4)
                        : Colors.black.withOpacity(0.08),
                    blurRadius: hasUnread ? 15 : 10,
                    offset: Offset(0, hasUnread ? 6 : 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(25),
                  onTap: () {
                    HapticFeedback.lightImpact();
                    // Chat functionality disabled
                    _showBottomMessage(
                      AppLocalizations.of(
                        context,
                      )!.chatFunctionIsCurrentlyNotAvailable,
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        // Avatar with Hero Animation
                        Hero(
                          tag: 'avatar_$otherUserUsername',
                          child: Stack(
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(25),
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF007AFF),
                                      Color(0xFF5856D6),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    otherUserName.isNotEmpty
                                        ? otherUserName[0].toUpperCase()
                                        : 'U',
                                    style: const TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                              if (hasUnread)
                                Positioned(
                                  top: -2,
                                  right: -2,
                                  child: Container(
                                    width: 20,
                                    height: 20,
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFF34C759),
                                          Color(0xFF30D158),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(25),
                                      border: Border.all(
                                        color: isDark
                                            ? const Color(0xFF1C1C1E)
                                            : Colors.white,
                                        width: 3,
                                      ),
                                    ),
                                    child: const Center(
                                      child: Icon(
                                        CupertinoIcons.circle_fill,
                                        size: 8,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),

                        // Content
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      otherUserName,
                                      style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: hasUnread
                                            ? FontWeight.w700
                                            : FontWeight.w600,
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (timeString.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: hasUnread
                                            ? const Color(
                                                0xFF007AFF,
                                              ).withOpacity(0.1)
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(25),
                                      ),
                                      child: Text(
                                        timeString,
                                        style: TextStyle(
                                          fontFamily: 'Poppins',
                                          fontSize: 12,
                                          color: hasUnread
                                              ? const Color(0xFF007AFF)
                                              : (isDark
                                                    ? Colors.grey[400]
                                                    : Colors.grey[600]),
                                          fontWeight: hasUnread
                                              ? FontWeight.w600
                                              : FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '@$otherUserUsername',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isDark
                                      ? Colors.grey[400]
                                      : Colors.grey[600],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (lastMessage.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  lastMessage,
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 15,
                                    color: hasUnread
                                        ? (isDark
                                              ? Colors.white
                                              : Colors.black87)
                                        : (isDark
                                              ? Colors.grey[300]
                                              : Colors.grey[700]),
                                    fontWeight: hasUnread
                                        ? FontWeight.w500
                                        : FontWeight.normal,
                                    height: 1.3,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),

                        // Arrow with animation
                        TweenAnimationBuilder<double>(
                          duration: const Duration(milliseconds: 200),
                          tween: Tween(begin: 0.0, end: 1.0),
                          builder: (context, arrowValue, child) {
                            return Transform.scale(
                              scale: 0.8 + (0.2 * arrowValue),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: (isDark ? Colors.white : Colors.black)
                                      .withOpacity(0.05),
                                  borderRadius: BorderRadius.circular(25),
                                ),
                                child: Icon(
                                  CupertinoIcons.chevron_right,
                                  color: isDark
                                      ? Colors.grey[500]
                                      : Colors.grey[600],
                                  size: 16,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMessagesPage(bool isDark) {
    debugPrint('🔍 _buildMessagesPage called');
    debugPrint('🔍 _isBusiness = $_isBusiness');
    debugPrint('🔍 _isLoggedIn = $_isLoggedIn');
    debugPrint('🔍 _currentUser isBusiness = ${_currentUser?['isBusiness']}');

    // Check if user is logged in before accessing messages
    if (!_isLoggedIn) {
      return SingleChildScrollView(
        padding: CultiooDesktopLayout.pageContentPadding(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            // Header
            Row(
              children: [
                Icon(
                  CupertinoIcons.chat_bubble_fill,
                  color: isDark ? Colors.white : Colors.black,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context)!.messages,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: isDark ? Colors.white : Colors.black,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40),
            Center(
              child: Column(
                children: [
                  Icon(
                    CupertinoIcons.arrow_right_square,
                    size: 80,
                    color: (isDark ? Colors.white : Colors.black).withOpacity(
                      0.3,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    AppLocalizations.of(context)!.pleaseSignIn,
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black54,
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppLocalizations.of(
                      context,
                    )!.toViewYourMessagesYouNeedToSignInFirst,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: isDark ? Colors.white54 : Colors.black45,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return ChatOverviewPage(isDark: isDark);
  }

  void _showUserSearchModal(bool isDark) {
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      useRootNavigator: true,
      maxHeight: MediaQuery.of(context).size.height * 0.8,
      child: FindUsersModal(isDark: isDark),
    );
  }

  Widget _buildFeatureItem(
    bool isDark,
    IconData icon,
    String title,
    String description,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.black : Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withOpacity(0.3)
                : Colors.grey.withOpacity(0.15),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF007AFF).withOpacity(0.1),
              borderRadius: BorderRadius.circular(25),
            ),
            child: Icon(icon, color: const Color(0xFF007AFF), size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountPage(bool isDark) {
    return CustomScrollView(
      physics: CultiooDesktopLayout.adaptiveScrollPhysics(context),
      slivers: [
        if (!CultiooDesktopLayout.isDesktopPlatform)
          CultiooSliverRefreshControl(
            onRefresh: () async {
              await _loadUserData();
            },
          ),
        SliverToBoxAdapter(
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            padding: CultiooDesktopLayout.pageContentPadding(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),

                // Modern Header with animation
                TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 400),
                  tween: Tween(begin: 0.0, end: 1.0),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) {
                    return Transform.translate(
                      offset: Offset(-30 * (1 - value), 0),
                      child: Opacity(opacity: value, child: child),
                    );
                  },
                  child: Row(
                    children: [
                      Icon(
                        CupertinoIcons.person_fill,
                        color: isDark ? Colors.white : Colors.black,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          AppLocalizations.of(context)!.myAccount,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : Colors.black,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                      if (_isLoggedIn)
                        // Logout button
                        TradeRepublicButton(
                          icon: Icon(
                            CupertinoIcons.power,
                            size: 22,
                            color: isDark
                                ? const Color(0xFF8E8E93)
                                : const Color(0xFF6C6C6C),
                          ),
                          isSecondary: true,
                          onPressed: _logout,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Profile Card with animation
                if (_isLoggedIn) ...[
                  TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 500),
                    tween: Tween(begin: 0.0, end: 1.0),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, child) {
                      return Transform.translate(
                        offset: Offset(0, -30 * (1 - value)),
                        child: Opacity(opacity: value, child: child),
                      );
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.transparent
                            : Colors.black.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(
                          CultiooDesktopLayout.cardCornerRadius(),
                        ),
                        // Minimalist card: no border.
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(25),
                        child: Row(
                          children: [
                            // Tappable profile avatar
                            GestureDetector(
                              onTap: () async {
                                final picker = ImagePicker();
                                final picked = await picker.pickImage(
                                  source: ImageSource.gallery,
                                  maxWidth: 256,
                                  maxHeight: 256,
                                  imageQuality: 75,
                                );
                                if (picked == null) return;
                                final bytes = await picked.readAsBytes();
                                final isAvif =
                                    bytes.length >= 12 &&
                                    bytes[4] == 0x66 &&
                                    bytes[5] == 0x74 &&
                                    bytes[6] == 0x79 &&
                                    bytes[7] == 0x70 &&
                                    bytes[8] == 0x61 &&
                                    bytes[9] == 0x76 &&
                                    bytes[10] == 0x69 &&
                                    bytes[11] == 0x66;
                                if (isAvif) {
                                  if (mounted) {
                                    TopNotification.error(
                                      context,
                                      'Please select JPG or PNG (AVIF is not supported).',
                                    );
                                  }
                                  return;
                                }
                                final b64 = _encodeProfileImageForUpload(bytes);
                                if (b64 == null) {
                                  if (mounted) {
                                    TopNotification.error(
                                      context,
                                      'Image could not be processed. Please use a smaller JPG/PNG.',
                                    );
                                  }
                                  return;
                                }
                                try {
                                  await ApiService.updateUserProfile(
                                    profileImage: b64,
                                  );
                                  setState(() {
                                    if (_currentUser != null) {
                                      _currentUser!['profilePic'] = b64;
                                      _currentUser!['profile_image'] = b64;
                                    }
                                    _profileImageSrc = b64;
                                  });
                                  if (mounted) {
                                    TopNotification.success(
                                      context,
                                      'Profile photo updated',
                                    );
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    TopNotification.error(
                                      context,
                                      'Failed to update photo: ${e.toString().replaceAll('Exception: ', '')}',
                                    );
                                  }
                                }
                              },
                              child: Stack(
                                alignment: Alignment.bottomRight,
                                children: [
                                  Builder(
                                    builder: (context) {
                                      final pic =
                                          _profileImageSrc ??
                                          _resolveCurrentUserProfileImage();
                                      final hasPhoto =
                                          pic != null && pic.isNotEmpty;
                                      return Container(
                                        width: 72,
                                        height: 72,
                                        decoration: BoxDecoration(
                                          color: isDark
                                              ? Colors.transparent
                                              : Colors.black.withOpacity(0.05),
                                          borderRadius: BorderRadius.circular(
                                            25,
                                          ),
                                          border: null,
                                        ),
                                        child: hasPhoto
                                            ? ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(23),
                                                child: _buildProfileImage(pic),
                                              )
                                            : Center(
                                                child: Text(
                                                  _userName.isNotEmpty
                                                      ? _userName[0]
                                                            .toUpperCase()
                                                      : 'U',
                                                  style: TextStyle(
                                                    fontFamily: 'Poppins',
                                                    fontSize: 28,
                                                    fontWeight: FontWeight.w700,
                                                    color: isDark
                                                        ? Colors.white
                                                        : Colors.black,
                                                  ),
                                                ),
                                              ),
                                      );
                                    },
                                  ),
                                  Container(
                                    width: 22,
                                    height: 22,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black,
                                      border: Border.all(
                                        color: isDark
                                            ? Colors.black.withOpacity(0.3)
                                            : Colors.white.withOpacity(0.5),
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Icon(
                                      CupertinoIcons.camera_fill,
                                      size: 11,
                                      color: isDark
                                          ? Colors.black
                                          : Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 20),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _getAccountDisplayLabel(),
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 22,
                                      fontWeight: FontWeight.w700,
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _userEmail,
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 16,
                                      color: isDark
                                          ? const Color(0xFF8E8E93)
                                          : const Color(0xFF6C6C6C),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Quick Actions Row
                  const SizedBox(height: 24),
                  if (!_isModalOpen)
                    TweenAnimationBuilder<double>(
                      duration: const Duration(milliseconds: 600),
                      tween: Tween(begin: 0.0, end: 1.0),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, child) {
                        return Transform.translate(
                          offset: Offset(0, 30 * (1 - value)),
                          child: Opacity(opacity: value, child: child),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 32,
                          horizontal: 16,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            // Edit Profile
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TradeRepublicButton(
                                  icon: const Icon(
                                    CupertinoIcons.person_fill,
                                    size: 24,
                                  ),
                                  onPressed: () {
                                    HapticFeedback.lightImpact();
                                    _showProfileEdit();
                                  },
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  AppLocalizations.of(context)!.editProfile,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                ),
                              ],
                            ),
                            // Groups
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TradeRepublicButton(
                                  icon: const Icon(
                                    CupertinoIcons.person_3_fill,
                                    size: 24,
                                  ),
                                  onPressed: () {
                                    HapticFeedback.lightImpact();
                                    _showGroups();
                                  },
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  AppLocalizations.of(context)!.groups,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                ),
                              ],
                            ),
                            // Payment
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TradeRepublicButton(
                                  icon: const Icon(
                                    CupertinoIcons.creditcard_fill,
                                    size: 24,
                                  ),
                                  onPressed: () {
                                    HapticFeedback.lightImpact();
                                    _showPaymentMethods();
                                  },
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  AppLocalizations.of(context)!.payment,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                ),
                              ],
                            ),
                            // History
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TradeRepublicButton(
                                  icon: const Icon(
                                    CupertinoIcons.doc_text_fill,
                                    size: 24,
                                  ),
                                  onPressed: () {
                                    HapticFeedback.lightImpact();
                                    _showTransactionHistory();
                                  },
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  AppLocalizations.of(context)!.history,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Addresses Section with animation
                  const SizedBox(height: 32),
                  TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 700),
                    tween: Tween(begin: 0.0, end: 1.0),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, child) {
                      return Transform.translate(
                        offset: Offset(30 * (1 - value), 0),
                        child: Opacity(opacity: value, child: child),
                      );
                    },
                    child: _buildGlassSection(
                      isDark: isDark,
                      title: AppLocalizations.of(context)!.myAddresses,
                      children: [
                        _buildListItem(
                          isDark: isDark,
                          icon: CupertinoIcons.house,
                          title: AppLocalizations.of(context)!.manageAddresses,
                          subtitle: AppLocalizations.of(
                            context,
                          )!.deliveryAndBilling,
                          trailing: CupertinoIcons.chevron_right,
                          onTap: () {
                            TradeRepublicBottomSheet.show(
                              context: context,
                              showDragHandle: true,
                              useRootNavigator: true,
                              maxHeight:
                                  MediaQuery.of(context).size.height * 0.8,
                              child: AddressesModal(accessToken: _accessToken),
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),
                  TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 900),
                    tween: Tween(begin: 0.0, end: 1.0),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, child) {
                      return Transform.translate(
                        offset: Offset(0, 30 * (1 - value)),
                        child: Opacity(opacity: value, child: child),
                      );
                    },
                    child: _buildGlassSection(
                      isDark: isDark,
                      title: AppLocalizations.of(context)!.accountInformation,
                      children: [
                        _buildInfoItem(
                          isDark: isDark,
                          icon: CupertinoIcons.person_fill,
                          title: AppLocalizations.of(context)!.name,
                          value: _userName.isNotEmpty
                              ? _userName
                              : AppLocalizations.of(context)!.notSet,
                        ),
                        Divider(
                          height: 1,
                          indent: 66,
                          endIndent: 16,
                          color: isDark
                              ? Colors.white.withOpacity(0.1)
                              : Colors.black.withOpacity(0.05),
                        ),
                        _buildInfoItem(
                          isDark: isDark,
                          icon: CupertinoIcons.at,
                          title: AppLocalizations.of(context)!.username,
                          value: _userUsername.isNotEmpty
                              ? '@$_userUsername'
                              : AppLocalizations.of(context)!.notSet,
                        ),
                        Divider(
                          height: 1,
                          indent: 66,
                          endIndent: 16,
                          color: isDark
                              ? Colors.white.withOpacity(0.1)
                              : Colors.black.withOpacity(0.05),
                        ),
                        _buildInfoItem(
                          isDark: isDark,
                          icon: CupertinoIcons.mail_solid,
                          title: AppLocalizations.of(context)!.email,
                          value: _userEmail.isNotEmpty
                              ? _userEmail
                              : AppLocalizations.of(context)!.notSet,
                        ),
                        Divider(
                          height: 1,
                          indent: 66,
                          endIndent: 16,
                          color: isDark
                              ? Colors.white.withOpacity(0.1)
                              : Colors.black.withOpacity(0.05),
                        ),
                        _buildInfoItem(
                          isDark: isDark,
                          icon: CupertinoIcons.phone_fill,
                          title: AppLocalizations.of(context)!.phone,
                          value: _userPhone?.isNotEmpty == true
                              ? _userPhone!
                              : AppLocalizations.of(context)!.notSet,
                        ),
                        Divider(
                          height: 1,
                          indent: 66,
                          endIndent: 16,
                          color: isDark
                              ? Colors.white.withOpacity(0.1)
                              : Colors.black.withOpacity(0.05),
                        ),
                        _buildInfoItem(
                          isDark: isDark,
                          icon: CupertinoIcons.calendar,
                          title: AppLocalizations.of(context)!.birthDate,
                          value: _userBirthDate != null
                              ? _formatDate(_userBirthDate)
                              : AppLocalizations.of(context)!.notSet,
                        ),
                        Divider(
                          height: 1,
                          indent: 66,
                          endIndent: 16,
                          color: isDark
                              ? Colors.white.withOpacity(0.1)
                              : Colors.black.withOpacity(0.05),
                        ),
                        if (_lastLogin != null) ...[
                          Divider(
                            height: 1,
                            indent: 66,
                            endIndent: 16,
                            color: isDark
                                ? Colors.white.withOpacity(0.1)
                                : Colors.black.withOpacity(0.05),
                          ),
                          _buildInfoItem(
                            isDark: isDark,
                            icon: CupertinoIcons.time_solid,
                            title: AppLocalizations.of(context)!.lastLogin,
                            value: _formatLastLoginDate(_lastLogin!),
                          ),
                        ],
                        if (_createdAt != null) ...[
                          Divider(
                            height: 1,
                            indent: 66,
                            endIndent: 16,
                            color: isDark
                                ? Colors.white.withOpacity(0.1)
                                : Colors.black.withOpacity(0.05),
                          ),
                          _buildInfoItem(
                            isDark: isDark,
                            icon: CupertinoIcons.calendar_badge_plus,
                            title: AppLocalizations.of(context)!.accountCreated,
                            value: _formatDate(_createdAt),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Finance Section with animation
                  TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 1000),
                    tween: Tween(begin: 0.0, end: 1.0),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, child) {
                      return Transform.translate(
                        offset: Offset(-30 * (1 - value), 0),
                        child: Opacity(opacity: value, child: child),
                      );
                    },
                    child: _buildGlassSection(
                      isDark: isDark,
                      title: AppLocalizations.of(context)!.finance,
                      children: [
                        _buildListItem(
                          isDark: isDark,
                          icon: CupertinoIcons.creditcard_fill,
                          title: AppLocalizations.of(context)!.paymentMethods,
                          subtitle:
                              '${_paymentMethods.length} method${_paymentMethods.length != 1 ? 's' : ''} available',
                          trailing: CupertinoIcons.chevron_right,
                          onTap: _showPaymentMethods,
                        ),
                        Divider(
                          height: 1,
                          indent: 66,
                          endIndent: 16,
                          color: isDark
                              ? Colors.white.withOpacity(0.1)
                              : Colors.black.withOpacity(0.05),
                        ),
                        _buildListItem(
                          isDark: isDark,
                          icon: CupertinoIcons.bag,
                          title: AppLocalizations.of(context)!.orderHistory,
                          subtitle: AppLocalizations.of(
                            context,
                          )!.viewYourOrders,
                          trailing: CupertinoIcons.chevron_right,
                          onTap: _showTransactionHistory,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Privacy & Security Section with animation
                  TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 1100),
                    tween: Tween(begin: 0.0, end: 1.0),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, child) {
                      return Transform.translate(
                        offset: Offset(30 * (1 - value), 0),
                        child: Opacity(opacity: value, child: child),
                      );
                    },
                    child: _buildGlassSection(
                      isDark: isDark,
                      title: AppLocalizations.of(context)!.privacySecurity,
                      children: [
                        _buildListItem(
                          isDark: isDark,
                          icon: CupertinoIcons.shield,
                          title: AppLocalizations.of(context)!.twoFactorAuth,
                          subtitle: _has2FAEnabled
                              ? 'Code: ${_user2FACode ?? AppLocalizations.of(context)!.noCode}'
                              : AppLocalizations.of(context)!.disabled,
                          trailing: CupertinoIcons.chevron_right,
                          onTap: () {
                            HapticFeedback.lightImpact();
                            _show2FACode();
                          },
                        ),
                        Divider(
                          height: 1,
                          indent: 66,
                          endIndent: 16,
                          color: isDark
                              ? Colors.white.withOpacity(0.1)
                              : Colors.black.withOpacity(0.05),
                        ),
                        _buildBiometricListItem(isDark),
                        Divider(
                          height: 1,
                          indent: 66,
                          endIndent: 16,
                          color: isDark
                              ? Colors.white.withOpacity(0.1)
                              : Colors.black.withOpacity(0.05),
                        ),
                        _buildListItem(
                          isDark: isDark,
                          icon: CupertinoIcons.lock,
                          title: AppLocalizations.of(context)!.changePassword,
                          subtitle: AppLocalizations.of(
                            context,
                          )!.updateYourPassword,
                          trailing: CupertinoIcons.chevron_right,
                          onTap: () {
                            //debugPrint('🔍 Debug: Change Password button tapped!');
                            _showChangePasswordModal();
                          },
                        ),
                        Divider(
                          height: 1,
                          indent: 66,
                          endIndent: 16,
                          color: isDark
                              ? Colors.white.withOpacity(0.1)
                              : Colors.black.withOpacity(0.05),
                        ),
                        _buildListItem(
                          isDark: isDark,
                          icon: CupertinoIcons.delete,
                          title: AppLocalizations.of(context)!.deleteAccount,
                          subtitle: AppLocalizations.of(
                            context,
                          )!.permanentlyDelete,
                          trailing: CupertinoIcons.chevron_right,
                          onTap: () {
                            HapticFeedback.lightImpact();
                            _showDeleteAccountModal();
                          },
                          textColor: Colors.red,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Settings Section
                  _buildGlassSection(
                    isDark: isDark,
                    title: AppLocalizations.of(context)!.settings,
                    children: [
                      _buildListItem(
                        isDark: isDark,
                        icon: CupertinoIcons.person_fill,
                        title: AppLocalizations.of(context)!.editProfile,
                        subtitle: AppLocalizations.of(
                          context,
                        )!.changeNameEmailPhone,
                        trailing: CupertinoIcons.chevron_right,
                        onTap: _showProfileEdit,
                      ),
                      Divider(
                        height: 1,
                        indent: Platform.isIOS ? 60 : 80,
                        endIndent: 16,
                        color: isDark
                            ? Colors.white.withOpacity(0.1)
                            : Colors.black.withOpacity(0.05),
                      ),
                      _buildListItem(
                        isDark: isDark,
                        icon: CupertinoIcons.settings,
                        title: AppLocalizations.of(context)!.settings,
                        subtitle: AppLocalizations.of(
                          context,
                        )!.themeLangCurrency,
                        trailing: CupertinoIcons.chevron_right,
                        onTap: () {
                          HapticFeedback.lightImpact();
                          TradeRepublicBottomSheet.show(
                            context: context,
                            showDragHandle: true,
                            useRootNavigator: true,
                            maxHeight: MediaQuery.of(context).size.height * 0.9,
                            child: _buildSettingsModal(),
                          );
                        },
                      ),
                    ],
                  ),
                  // Connected Accounts Section
                  if (_isGoogleConnected ||
                      (Platform.isIOS && _isAppleConnected)) ...[
                    const SizedBox(height: 32),
                    _buildGlassSection(
                      isDark: isDark,
                      title: AppLocalizations.of(context)!.connectedAccounts,
                      children: [
                        if (_isGoogleConnected)
                          TradeRepublicListTile.navigation(
                            title: AppLocalizations.of(context)!.googleAccount,
                            subtitle: AppLocalizations.of(context)!.online,
                            leading: const Icon(CupertinoIcons.link, size: 20),
                            onTap: () {
                              HapticFeedback.lightImpact();
                              _signInWithGoogle();
                            },
                          ),
                        if (Platform.isIOS && _isAppleConnected)
                          TradeRepublicListTile.navigation(
                            title: AppLocalizations.of(context)!.appleAccount,
                            subtitle: AppLocalizations.of(context)!.online,
                            leading: const Icon(Icons.apple, size: 20),
                            onTap: () {
                              HapticFeedback.lightImpact();
                              _signInWithApple();
                            },
                          ),
                      ],
                    ),
                  ],

                  // Bottom spacing to allow content to flow behind dock
                  const SizedBox(height: 40),
                ] else ...[
                  // Modern Apple-style Login Screen
                  Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: _isWideScreen ? 520 : double.infinity,
                      ),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 32,
                        ),
                        child: Column(
                          children: [
                            // Modern App Icon/Logo
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white.withOpacity(0.1)
                                    : Colors.black.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(25),
                              ),
                              child: Center(
                                child: Icon(
                                  CupertinoIcons.sparkles,
                                  size: 40,
                                  color: isDark ? Colors.white : Colors.black,
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Modern Typography
                            Text(
                              AppLocalizations.of(context)!.welcomeToCultioo,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                                color: isDark ? Colors.white : Colors.black,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              AppLocalizations.of(context)!.signInSubtitle,
                              style: TextStyle(
                                fontSize: 16,
                                color: isDark
                                    ? const Color(0xFF8E8E93)
                                    : const Color(0xFF6C6C6C),
                              ),
                            ),
                            const SizedBox(height: 32),

                            // Modern Email Field
                            TradeRepublicTextField(
                              controller: _usernameController,
                              hintText: AppLocalizations.of(
                                context,
                              )!.usernameOrEmail,
                              keyboardType: TextInputType.emailAddress,
                            ),
                            const SizedBox(height: 16),

                            // Modern Password Field
                            TradeRepublicTextField(
                              controller: _passwordController,
                              obscureText: !_isPasswordVisible,
                              hintText: AppLocalizations.of(context)!.password,
                              prefixIcon: Icon(
                                CupertinoIcons.lock_fill,
                                size: 20,
                              ),
                              suffixIcon: IconButton(
                                onPressed: () {
                                  setState(() {
                                    _isPasswordVisible = !_isPasswordVisible;
                                  });
                                },
                                icon: Icon(
                                  _isPasswordVisible
                                      ? CupertinoIcons.eye
                                      : CupertinoIcons.eye_slash,
                                  size: 20,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),

                            // Forgot Password Button
                            Align(
                              alignment: Alignment.centerRight,
                              child: TradeRepublicButton(
                                label: AppLocalizations.of(
                                  context,
                                )!.forgotPassword,
                                onPressed: _showForgotPassword,
                                isSecondary: true,
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Sign In Button
                            TradeRepublicButton(
                              label: _isLoading
                                  ? AppLocalizations.of(context)!.signingIn
                                  : AppLocalizations.of(context)!.signIn,
                              onPressed: _isLoading ? null : _login,
                              isLoading: _isLoading,
                              width: double.infinity,
                            ),
                            const SizedBox(height: 16),

                            // Create Account Button
                            TradeRepublicButton(
                              label: AppLocalizations.of(
                                context,
                              )!.createAccount,
                              onPressed: _isLoading ? null : _showRegister,
                              isSecondary: true,
                              width: double.infinity,
                            ),

                            const SizedBox(height: 32),

                            // Divider
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    height: 1,
                                    color: isDark
                                        ? Colors.white.withOpacity(0.1)
                                        : Colors.black.withOpacity(0.1),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  child: Text(
                                    AppLocalizations.of(context)!.or,
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 14,
                                      color: isDark
                                          ? const Color(0xFF8E8E93)
                                          : const Color(0xFF6C6C6C),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Container(
                                    height: 1,
                                    color: isDark
                                        ? Colors.white.withOpacity(0.1)
                                        : Colors.black.withOpacity(0.1),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 32),

                            // Google Sign In Button
                            TradeRepublicButton(
                              label: AppLocalizations.of(
                                context,
                              )!.continueWithGoogle,
                              icon: Image.asset(
                                'logo/google.png',
                                width: 20,
                                height: 20,
                              ),
                              isSecondary: true,
                              width: double.infinity,
                              onPressed: _isLoading
                                  ? null
                                  : () {
                                      HapticFeedback.lightImpact();
                                      _signInWithGoogle();
                                    },
                            ),

                            if (Platform.isIOS) ...[
                              const SizedBox(height: 12),
                              TradeRepublicButton(
                                label: AppLocalizations.of(context)!.continueWithApple,
                                icon: const Icon(Icons.apple, size: 20),
                                isSecondary: true,
                                width: double.infinity,
                                onPressed: _isLoading
                                    ? null
                                    : () {
                                        HapticFeedback.lightImpact();
                                        _signInWithApple();
                                      },
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],

                // Bottom spacing to allow content to flow behind dock
                const SizedBox(height: 180),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Simple settings modal used by account page when tapping "Settings"
  Widget _buildSettingsModal() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        // Fixed Header
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
          child: Text(
            AppLocalizations.of(context)!.settings,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
        ),
        // Scrollable Content
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Reuse existing settings item builders for consistency
                  _buildSettingsItem(
                    isDark: isDark,
                    icon: CupertinoIcons.paintbrush,
                    title: AppLocalizations.of(context)!.theme,
                    subtitle: _getThemeDisplayName(),
                    onTap: () async {
                      await _closeSettingsSheetSafely(context);
                      if (!mounted) return;
                      _showThemeSelector(isDark);
                    },
                  ),
                  _buildSettingsItem(
                    isDark: isDark,
                    icon: CupertinoIcons.textformat_size,
                    title: AppLocalizations.of(context)!.textSize,
                    subtitle: _getTextSizeDisplayName(),
                    onTap: () async {
                      await _closeSettingsSheetSafely(context);
                      if (!mounted) return;
                      _showTextSizeSelector(isDark);
                    },
                  ),
                  _buildSettingsItem(
                    isDark: isDark,
                    icon: CupertinoIcons.globe,
                    title: AppLocalizations.of(context)!.language,
                    subtitle: _getLanguageDisplayName(),
                    onTap: () async {
                      await _closeSettingsSheetSafely(context);
                      if (!mounted) return;
                      _showLanguageSelector(isDark);
                    },
                  ),
                  _buildSettingsItem(
                    isDark: isDark,
                    icon: CupertinoIcons.number,
                    title: AppLocalizations.of(context)!.numberFormat,
                    subtitle: _getNumberFormatDisplayName(),
                    onTap: () async {
                      await _closeSettingsSheetSafely(context);
                      if (!mounted) return;
                      _showNumberFormatSelector(isDark);
                    },
                  ),
                  _buildSettingsItem(
                    isDark: isDark,
                    icon: CupertinoIcons.money_dollar_circle,
                    title: AppLocalizations.of(context)!.currency,
                    subtitle: _getCurrencyDisplayName(),
                    onTap: () async {
                      await _closeSettingsSheetSafely(context);
                      if (!mounted) return;
                      _showCurrencySelector(isDark);
                    },
                  ),
                  _buildSettingsItem(
                    isDark: isDark,
                    icon: CupertinoIcons.location,
                    title: AppLocalizations.of(context)!.distanceUnit,
                    subtitle: _getDistanceUnitDisplayName(),
                    onTap: () async {
                      await _closeSettingsSheetSafely(context);
                      if (!mounted) return;
                      _showDistanceUnitSelector(isDark);
                    },
                  ),
                  _buildSettingsItem(
                    isDark: isDark,
                    icon: CupertinoIcons.chart_bar,
                    title: AppLocalizations.of(context)!.weightUnit,
                    subtitle: _getWeightUnitDisplayName(),
                    onTap: () async {
                      await _closeSettingsSheetSafely(context);
                      if (!mounted) return;
                      _showWeightUnitSelector(isDark);
                    },
                  ),
                  _buildSettingsItem(
                    isDark: isDark,
                    icon: CupertinoIcons.calendar,
                    title: AppLocalizations.of(context)!.dateFormat,
                    subtitle: _getDateFormatDisplayName(),
                    onTap: () async {
                      await _closeSettingsSheetSafely(context);
                      if (!mounted) return;
                      _showDateFormatSelector(isDark);
                    },
                  ),

                  const SizedBox(height: 24),

                  // Legal & Help Section
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      AppLocalizations.of(context)!.legalHelp,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  _buildSettingsItem(
                    isDark: isDark,
                    icon: CupertinoIcons.doc_text,
                    title: AppLocalizations.of(context)!.termsAndConditions,
                    subtitle: AppLocalizations.of(context)!.viewTermsOfService,
                    onTap: () async {
                      await _closeSettingsSheetSafely(context);
                      if (!mounted) return;
                      _openLegalPage('cultioo_terms');
                    },
                  ),
                  _buildSettingsItem(
                    isDark: isDark,
                    icon: CupertinoIcons.shield,
                    title: AppLocalizations.of(context)!.privacyPolicy,
                    subtitle: AppLocalizations.of(context)!.howWeHandleData,
                    onTap: () async {
                      await _closeSettingsSheetSafely(context);
                      if (!mounted) return;
                      _openLegalPage('cultioo_privacy');
                    },
                  ),
                  _buildSettingsItem(
                    isDark: isDark,
                    icon: CupertinoIcons.question_circle,
                    title: AppLocalizations.of(context)!.generalHelp,
                    subtitle: AppLocalizations.of(context)!.faqAndSupport,
                    onTap: () async {
                      await _closeSettingsSheetSafely(context);
                      if (!mounted) return;
                      launchUrl(
                        Uri.parse('https://cultioo.com/us/us_help'),
                        mode: LaunchMode.externalApplication,
                      );
                    },
                  ),

                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Helper methods for the new favorites page1
  Widget _buildFavouritesPage(bool isDark) {
    return CustomScrollView(
      physics: CultiooDesktopLayout.adaptiveScrollPhysics(context),
      slivers: [
        if (!CultiooDesktopLayout.isDesktopPlatform)
          CultiooSliverRefreshControl(
            onRefresh: () async {
              await _loadFavoritesFromServer();
            },
          ),
        SliverToBoxAdapter(
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            padding: CultiooDesktopLayout.pageContentPadding(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),

                // Modern Header with animation
                TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 400),
                  tween: Tween(begin: 0.0, end: 1.0),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) {
                    return Transform.translate(
                      offset: Offset(-30 * (1 - value), 0),
                      child: Opacity(opacity: value, child: child),
                    );
                  },
                  child: Row(
                    children: [
                      Icon(
                        CupertinoIcons.heart_fill,
                        color: isDark ? Colors.white : Colors.black,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          AppLocalizations.of(context)!.favorites,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : Colors.black,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Quick Stats Cards with animation
                TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 500),
                  tween: Tween(begin: 0.0, end: 1.0),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) {
                    return Transform.translate(
                      offset: Offset(0, -30 * (1 - value)),
                      child: Opacity(opacity: value, child: child),
                    );
                  },
                      child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.05)
                                : Colors.black.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(
                              CultiooDesktopLayout.cardCornerRadius(),
                            ),
                            // Minimalist card: no border.
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    CupertinoIcons.bag,
                                    color: const Color(0xFFE74C3C),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${_favoriteProductIds.length}',
                                          style: TextStyle(
                                            fontFamily: 'Poppins',
                                            fontSize: 22,
                                            fontWeight: FontWeight.w700,
                                            color: isDark
                                                ? Colors.white
                                                : Colors.black,
                                          ),
                                        ),
                                        Text(
                                          'Products',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: isDark
                                                ? const Color(0xFF8E8E93)
                                                : const Color(0xFF6C6C6C),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.05)
                                : Colors.black.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(
                              CultiooDesktopLayout.cardCornerRadius(),
                            ),
                            // Minimalist card: no border.
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    CupertinoIcons.person_2,
                                    color: const Color(0xFFE74C3C),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${_followedUsers.length}',
                                          style: TextStyle(
                                            fontFamily: 'Poppins',
                                            fontSize: 22,
                                            fontWeight: FontWeight.w700,
                                            color: isDark
                                                ? Colors.white
                                                : Colors.black,
                                          ),
                                        ),
                                        Text(
                                          AppLocalizations.of(context)!.following,
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: isDark
                                                ? const Color(0xFF8E8E93)
                                                : const Color(0xFF6C6C6C),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // CNSegmentedControl for iOS, custom for other platforms
                TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 500),
                  tween: Tween(begin: 0.0, end: 1.0),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) {
                    return Transform.translate(
                      offset: Offset(0, 20 * (1 - value)),
                      child: Opacity(opacity: value, child: child),
                    );
                  },
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: CultiooDesktopLayout.isDesktopPlatform
                            ? 24
                            : (defaultTargetPlatform == TargetPlatform.macOS
                                ? 200
                                : 40),
                      ),
                      child: TradeRepublicSliderExpanded(
                        labels: [
                          AppLocalizations.of(context)!.products,
                          AppLocalizations.of(context)!.following,
                        ],
                        selectedIndex: _selectedFavoriteTab,
                        onChanged: (index) {
                          HapticFeedback.selectionClick();
                          setState(() {
                            _selectedFavoriteTab = index;
                          });
                          _favoritesPageController.animateToPage(
                            index,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                          if (index == 1) {
                            _loadFollowedUsersFromPrefs();
                            _loadFollowedUsersFromServer();
                          }
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Content based on selected tab
                if (_selectedFavoriteTab == 0) ...[
                  // Products Tab Content in Account style
                  TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeInOutQuart,
                    tween: Tween<double>(begin: 0.0, end: 1.0),
                    builder: (context, value, child) {
                      return Transform.translate(
                        offset: Offset(20 * (1 - value), 0),
                        child: Opacity(opacity: value, child: child),
                      );
                    },
                    child: Column(
                      children: [
                        if (_favoriteProductIds.isNotEmpty) ...[
                          // Products Section Header
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 8,
                            ),
                            child: Text(
                              AppLocalizations.of(context)!.favoriteProducts,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: isDark ? Colors.white : Colors.black,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Products List in Cards
                          ..._favoriteProductIds.map((productId) {
                            final product = _products.firstWhere(
                              (p) => p['id'] == productId,
                              orElse: () => {},
                            );
                            if (product.isEmpty) return const SizedBox.shrink();

                            return Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white.withOpacity(0.05)
                                    : Colors.black.withOpacity(0.02),
                                borderRadius: BorderRadius.circular(25),
                              ),
                              child: _buildFavoriteProductListItem(
                                product,
                                isDark,
                              ),
                            );
                          }),
                        ] else ...[
                          // Empty State for Products
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 40,
                              vertical: 40,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withOpacity(0.05)
                                  : Colors.black.withOpacity(0.02),
                              borderRadius: BorderRadius.circular(25),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFFE74C3C,
                                    ).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(25),
                                  ),
                                  child: Icon(
                                    CupertinoIcons.heart,
                                    size: 32,
                                    color: const Color(0xFFE74C3C),
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  AppLocalizations.of(
                                    context,
                                  )!.noFavoriteProductsYet,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  child: Text(
                                    AppLocalizations.of(
                                      context,
                                    )!.tapTheHeartIconOnProductsToAddThemToYour,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: isDark
                                          ? const Color(0xFF8E8E93)
                                          : const Color(0xFF6C6C6C),
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ] else ...[
                  // Following Tab Content
                  TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeInOutQuart,
                    tween: Tween<double>(begin: 0.0, end: 1.0),
                    builder: (context, value, child) {
                      return Transform.translate(
                        offset: Offset(20 * (1 - value), 0),
                        child: Opacity(opacity: value, child: child),
                      );
                    },
                    child: Column(
                      children: [
                        if (_followedUsers.isNotEmpty) ...[
                          // Following Section Header
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 8,
                            ),
                            child: Text(
                              AppLocalizations.of(context)!.following,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: isDark ? Colors.white : Colors.black,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Following Users List
                          ..._followedUsers.map((user) {
                            return Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white.withOpacity(0.05)
                                    : Colors.black.withOpacity(0.02),
                                borderRadius: BorderRadius.circular(25),
                              ),
                              child: Row(
                                children: [
                                  // User Avatar
                                  Container(
                                    width: 50,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: const Color(
                                        0xFFE74C3C,
                                      ).withOpacity(0.1),
                                    ),
                                    child: Center(
                                      child: Text(
                                        user['username']
                                                ?.toString()
                                                .substring(0, 1)
                                                .toUpperCase() ??
                                            '?',
                                        style: const TextStyle(
                                          color: Color(0xFFE74C3C),
                                          fontSize: 20,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),

                                  // User Info
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          user['username']?.toString() ??
                                              'Unknown',
                                          style: TextStyle(
                                            fontFamily: 'Poppins',
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: isDark
                                                ? Colors.white
                                                : Colors.black,
                                          ),
                                        ),
                                        if (user['bio'] != null &&
                                            user['bio'].toString().isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 4,
                                            ),
                                            child: Text(
                                              user['bio'].toString(),
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: isDark
                                                    ? const Color(0xFF8E8E93)
                                                    : const Color(0xFF6C6C6C),
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),

                                  const SizedBox(width: 16),

                                  // Unfollow Button
                                  TradeRepublicButton(
                                    label: AppLocalizations.of(context)!.following,
                                    isDestructive: true,
                                    height: 36,
                                    onPressed: () async {
                                      try {
                                        final targetUsername = user['username']
                                            ?.toString();
                                        if (targetUsername == null) return;

                                        final result =
                                            await ApiService.unfollowUser(
                                              targetUsername,
                                            );
                                        if (result['success'] == true) {
                                          setState(() {
                                            _followedUsers.removeWhere(
                                              (u) =>
                                                  u['username'] ==
                                                  targetUsername,
                                            );
                                          });
                                          await _saveFollowedUsersToPrefs();

                                          final prefs =
                                              await SharedPreferences.getInstance();
                                          await prefs.remove(
                                            'following_$targetUsername',
                                          );

                                          _showBottomMessage(
                                            'Unfollowed ${user['name'] ?? user['username']}',
                                            isSuccess: true,
                                          );
                                        } else {
                                          _showBottomMessage(
                                            AppLocalizations.of(
                                              context,
                                            )!.failedToUnfollowUser,
                                            isError: true,
                                          );
                                        }
                                      } catch (e) {
                                        debugPrint('Error unfollowing user: $e');
                                        setState(() {
                                          final targetUsername =
                                              user['username']?.toString();
                                          _followedUsers.removeWhere(
                                            (u) =>
                                                u['username'] == targetUsername,
                                          );
                                        });
                                        await _saveFollowedUsersToPrefs();
                                        _showBottomMessage(
                                          'Unfollowed ${user['name'] ?? user['username']}',
                                          isSuccess: true,
                                        );
                                      }
                                    },
                                  ),
                                ],
                              ),
                            );
                          }),
                        ] else ...[
                          // Empty State for Following
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 40,
                              vertical: 40,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withOpacity(0.05)
                                  : Colors.black.withOpacity(0.02),
                              borderRadius: BorderRadius.circular(25),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFFE74C3C,
                                    ).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(25),
                                  ),
                                  child: const Icon(
                                    CupertinoIcons.person_2_fill,
                                    size: 32,
                                    color: Color(0xFFE74C3C),
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  AppLocalizations.of(
                                    context,
                                  )!.notFollowingAnyoneYet,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  child: Text(
                                    AppLocalizations.of(
                                      context,
                                    )!.startFollowingUsersToSeeTheirProfilesHere,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: isDark
                                          ? const Color(0xFF8E8E93)
                                          : const Color(0xFF6C6C6C),
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],

                // Bottom spacing to allow content to flow behind dock
                const SizedBox(height: 120),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Helper methods for the new favorites page
  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.03)
            : Colors.white.withOpacity(0.6),
        borderRadius: BorderRadius.circular(25),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(25),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isDark
                  ? Colors.white.withOpacity(0.6)
                  : Colors.black.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }

  // Helper method for minimal radius preset buttons
  Widget _buildMinimalPresetButton(
    int radius,
    String label,
    bool isDark,
    StateSetter setModalState,
  ) {
    final isSelected = _searchRadius.toInt() == radius;

    return GestureDetector(
      onTap: () {
        setModalState(() {
          _searchRadius = radius.toDouble();
        });
        setState(() {
          _searchRadius = radius.toDouble();
        });
        _filterProducts(); // Re-filter products when radius changes
        HapticFeedback.selectionClick();
      },
      child: Platform.isIOS
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.blue.withOpacity(0.1)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(25),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected
                      ? Colors.blue
                      : (isDark ? Colors.white : Colors.black).withOpacity(0.8),
                ),
              ),
            )
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.blue.withOpacity(0.1)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(25),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected
                      ? Colors.blue
                      : (isDark ? Colors.white : Colors.black).withOpacity(0.8),
                ),
              ),
            ),
    );
  }

  // Helper method for radius preset buttons
  Widget _buildRadiusPresetButton(
    int radius,
    String label,
    bool isDark,
    StateSetter setModalState,
  ) {
    final isSelected = _searchRadius.toInt() == radius;

    return GestureDetector(
      onTap: () {
        setModalState(() {
          _searchRadius = radius.toDouble();
        });
        setState(() {
          _searchRadius = radius.toDouble();
        });
        HapticFeedback.selectionClick();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.blue.withOpacity(0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(25),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${radius}km',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                color: isSelected
                    ? Colors.blue
                    : (isDark ? Colors.white : Colors.black).withOpacity(0.8),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: isSelected
                    ? Colors.blue.withOpacity(0.8)
                    : (isDark ? Colors.white : Colors.black).withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFavoriteProductsCarousel(bool isDark) {
    final favoriteProducts = _products.where((product) {
      final productId = product['id'];
      return _favoriteProductIds.contains(productId);
    }).toList();

    if (favoriteProducts.isEmpty) {
      return const SizedBox.shrink();
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: favoriteProducts.length,
      itemBuilder: (context, index) {
        final product = favoriteProducts[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          child: _buildFavoriteProductListItem(product, isDark),
        );
      },
    );
  }

  Widget _buildFavoriteProductListItem(
    Map<String, dynamic> product,
    bool isDark,
  ) {
    return GestureDetector(
      onTap: () => _showProductDetails(product),
      child: Row(
        children: [
          // Product Image
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withOpacity(0.05)
                  : Colors.black.withOpacity(0.02),
              borderRadius: BorderRadius.circular(25),
            ),
            child: product['image_url'] != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(25),
                    child:
                        (product['image_url']?.toString() ?? '').startsWith(
                          'data:image',
                        )
                        ? Image.memory(
                            base64Decode(
                              (product['image_url']?.toString() ?? '').split(
                                ',',
                              )[1],
                            ),
                            fit: BoxFit.cover,
                            width: 60,
                            height: 60,
                            errorBuilder: (context, error, stackTrace) {
                              return Icon(
                                CupertinoIcons.bag,
                                color: isDark
                                    ? const Color(0xFF8E8E93)
                                    : const Color(0xFF6C6C6C),
                                size: 24,
                              );
                            },
                          )
                        : Image.network(
                            product['image_url']?.toString() ?? '',
                            fit: BoxFit.cover,
                            width: 60,
                            height: 60,
                            errorBuilder: (context, error, stackTrace) {
                              return Icon(
                                CupertinoIcons.bag,
                                color: isDark
                                    ? const Color(0xFF8E8E93)
                                    : const Color(0xFF6C6C6C),
                                size: 24,
                              );
                            },
                          ),
                  )
                : Icon(
                    CupertinoIcons.bag,
                    color: isDark
                        ? const Color(0xFF8E8E93)
                        : const Color(0xFF6C6C6C),
                    size: 24,
                  ),
          ),
          const SizedBox(width: 16),

          // Product Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product['name'] ??
                      AppLocalizations.of(context)!.unknownProduct,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  _getSellerName(product),
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark
                        ? const Color(0xFF8E8E93)
                        : const Color(0xFF6C6C6C),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  _getProductDisplayPrice(product),
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFE74C3C),
                  ),
                ),
              ],
            ),
          ),

          // Favorite Button - Account style
          Container(
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withOpacity(0.05)
                  : Colors.black.withOpacity(0.02),
              borderRadius: BorderRadius.circular(25),
              border: Border.all(
                color: isDark
                    ? Colors.white.withOpacity(0.1)
                    : Colors.black.withOpacity(0.05),
                width: 0.5,
              ),
            ),
            child: TradeRepublicButton(
              icon: const Icon(
                CupertinoIcons.heart_fill,
                color: Colors.red,
                size: 18,
              ),
              isSecondary: true,
              width: 44,
              height: 44,
              padding: EdgeInsets.zero,
              borderRadius: BorderRadius.circular(25),
              onPressed: () => _toggleFavorite(product['id']),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernProductCard(Map<String, dynamic> product, bool isDark) {
    return GestureDetector(
      onTap: () => _showProductDetails(product),
      child: Container(
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withOpacity(0.05)
              : Colors.white.withOpacity(0.9),
          borderRadius: BorderRadius.circular(25),
          border: Border.all(
            color: isDark
                ? Colors.white.withOpacity(0.1)
                : Colors.black.withOpacity(0.05),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withOpacity(0.3)
                  : Colors.black.withOpacity(0.08),
              blurRadius: 20,
              offset: const Offset(0, 10),
              spreadRadius: -5,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product image
            Container(
              height: 140,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withOpacity(0.05)
                    : Colors.grey[100],
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(25),
                  topRight: Radius.circular(25),
                ),
              ),
              child: Stack(
                children: [
                  if (product['images'] != null && product['images'].isNotEmpty)
                    ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(25),
                        topRight: Radius.circular(25),
                      ),
                      child: Image.network(
                        product['images'][0],
                        height: 140,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            height: 140,
                            color: isDark
                                ? Colors.white.withOpacity(0.05)
                                : Colors.grey[100],
                            child: Icon(
                              CupertinoIcons.photo,
                              size: 40,
                              color: isDark
                                  ? Colors.white.withOpacity(0.3)
                                  : Colors.grey[400],
                            ),
                          );
                        },
                      ),
                    )
                  else
                    SizedBox(
                      height: 140,
                      child: Icon(
                        CupertinoIcons.photo,
                        size: 40,
                        color: isDark
                            ? Colors.white.withOpacity(0.3)
                            : Colors.grey[400],
                      ),
                    ),

                  // Favorite button
                  Positioned(
                    top: 12,
                    right: 12,
                    child: TradeRepublicButton(
                      icon: Icon(
                        CupertinoIcons.heart_fill,
                        size: 16,
                        color: const Color(0xFFFF6B6B),
                      ),
                      isSecondary: true,
                      width: 40,
                      height: 40,
                      padding: EdgeInsets.zero,
                      borderRadius: BorderRadius.circular(25),
                      onPressed: () => _toggleFavorite(product['id']),
                    ),
                  ),
                ],
              ),
            ),

            // Product details
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product['name'] ??
                          AppLocalizations.of(context)!.unknownProduct,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _getSellerName(product),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isDark
                            ? Colors.white.withOpacity(0.6)
                            : Colors.black.withOpacity(0.5),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Spacer(),
                    Text(
                      _getProductDisplayPrice(product),
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFFE74C3C),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernFollowedUserCard(Map<String, dynamic> user, bool isDark) {
    return GestureDetector(
      onTap: () => _showSellerProfile(
        user['id'].toString(),
        user['name'] ?? AppLocalizations.of(context)!.unknownSeller,
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withOpacity(0.05)
              : Colors.white.withOpacity(0.9),
          borderRadius: BorderRadius.circular(25),
          border: Border.all(
            color: isDark
                ? Colors.white.withOpacity(0.1)
                : Colors.black.withOpacity(0.05),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withOpacity(0.3)
                  : Colors.black.withOpacity(0.08),
              blurRadius: 20,
              offset: const Offset(0, 10),
              spreadRadius: -5,
            ),
          ],
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [const Color(0xFFE74C3C), const Color(0xFFC0392B)],
                ),
                borderRadius: BorderRadius.circular(25),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFE74C3C).withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  (user['name'] ?? 'U')[0].toUpperCase(),
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),

            // User info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user['name'] ?? AppLocalizations.of(context)!.unknownSeller,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (user['business_name'] != null)
                    Text(
                      user['business_name'],
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isDark
                            ? Colors.white.withOpacity(0.6)
                            : Colors.black.withOpacity(0.5),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        CupertinoIcons.location,
                        size: 16,
                        color: isDark
                            ? Colors.white.withOpacity(0.5)
                            : Colors.black.withOpacity(0.4),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        user['address'] ??
                            AppLocalizations.of(context)!.locationUnknown,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: isDark
                              ? Colors.white.withOpacity(0.5)
                              : Colors.black.withOpacity(0.4),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Notification toggle
            GestureDetector(
              onTap: () => _toggleSellerNotifications(user['id'].toString()),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color:
                      _sellerNotificationSettings[user['id'].toString()] == true
                      ? const Color(0xFFE74C3C).withOpacity(0.1)
                      : isDark
                      ? Colors.white.withOpacity(0.05)
                      : Colors.black.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(
                    color:
                        _sellerNotificationSettings[user['id'].toString()] ==
                            true
                        ? const Color(0xFFE74C3C)
                        : isDark
                        ? Colors.white.withOpacity(0.1)
                        : Colors.black.withOpacity(0.1),
                    width: 1,
                  ),
                ),
                child: Icon(
                  _sellerNotificationSettings[user['id'].toString()] == true
                      ? CupertinoIcons.bell_fill
                      : CupertinoIcons.bell_slash,
                  size: 20,
                  color:
                      _sellerNotificationSettings[user['id'].toString()] == true
                      ? const Color(0xFFE74C3C)
                      : isDark
                      ? Colors.white.withOpacity(0.6)
                      : Colors.black.withOpacity(0.4),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernEmptyState(bool isDark) {
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.03)
            : Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.08)
              : Colors.black.withOpacity(0.05),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFE74C3C).withOpacity(0.1),
                  const Color(0xFFC0392B).withOpacity(0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(25),
            ),
            child: Icon(
              CupertinoIcons.heart,
              size: 48,
              color: isDark
                  ? Colors.white.withOpacity(0.4)
                  : Colors.black.withOpacity(0.3),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            AppLocalizations.of(context)!.noFavoritesYet,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            AppLocalizations.of(
              context,
            )!.discoverAmazingProductsAndFollowInterestingS,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: isDark
                  ? Colors.white.withOpacity(0.6)
                  : Colors.black.withOpacity(0.5),
            ),
          ),
          const SizedBox(height: 120),
        ],
      ),
    );
  }

  Widget _buildFavoritesLoading(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CultiooLoadingIndicator(),
          const SizedBox(height: 16),
          Text(
            'Loading...',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 16,
              color: isDark
                  ? Colors.white.withOpacity(0.7)
                  : Colors.black.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFavoritesEmpty(bool isDark, String type) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            type == 'products' ? CupertinoIcons.heart : CupertinoIcons.person_2,
            size: 64,
            color: isDark
                ? Colors.white.withOpacity(0.3)
                : Colors.black.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            type == 'products'
                ? AppLocalizations.of(context)!.noFavoriteProductsYet
                : AppLocalizations.of(context)!.notFollowingAnyoneYet,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? Colors.white.withOpacity(0.7)
                  : Colors.black.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            type == 'products'
                ? AppLocalizations.of(
                    context,
                  )!.tapTheHeartIconOnProductsToAddThemToYour
                : AppLocalizations.of(
                    context,
                  )!.followSellersAndUsersToSeeThemHere,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: isDark
                  ? Colors.white.withOpacity(0.5)
                  : Colors.black.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFavoriteProductCard(Map<String, dynamic> product, bool isDark) {
    final displayPrice = _getProductDisplayPrice(product);

    Widget buildSquareCover(Widget child) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(25),
        child: ClipRect(
          child: SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.cover,
              alignment: Alignment.center,
              clipBehavior: Clip.hardEdge,
              child: child,
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(25), // Changed to 25px
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.1)
              : Colors.black.withOpacity(0.05),
        ),
      ),
      child: InkWell(
        onTap: () => _showProductDetails(product),
        borderRadius: BorderRadius.circular(25), // Changed to 25px
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Product Image
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(25), // Changed to 25px
                  color: isDark
                      ? Colors.white.withOpacity(0.05)
                      : Colors.grey[100],
                ),
                child: product['image_url'] != null
                    ? ((product['image_url']?.toString() ?? '').startsWith(
                            'data:image',
                          )
                          ? buildSquareCover(
                              Image.memory(
                                base64Decode(
                                  (product['image_url']?.toString() ?? '')
                                      .split(',')[1],
                                ),
                                errorBuilder: (context, error, stackTrace) {
                                  return Icon(
                                    CupertinoIcons.bag,
                                    color: isDark
                                        ? Colors.white.withOpacity(0.3)
                                        : Colors.grey[400],
                                    size: 32,
                                  );
                                },
                              ),
                            )
                          : buildSquareCover(
                              Image.network(
                                product['image_url']?.toString() ?? '',
                                errorBuilder: (context, error, stackTrace) {
                                  return Icon(
                                    CupertinoIcons.bag,
                                    color: isDark
                                        ? Colors.white.withOpacity(0.3)
                                        : Colors.grey[400],
                                    size: 32,
                                  );
                                },
                              ),
                            ))
                    : Icon(
                        CupertinoIcons.bag,
                        color: isDark
                            ? Colors.white.withOpacity(0.3)
                            : Colors.grey[400],
                        size: 32,
                      ),
              ),

              const SizedBox(width: 16),

              // Product Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product['name'] ?? 'Product',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    if (_getSellerName(product) !=
                        AppLocalizations.of(context)!.unknownSeller)
                      Text(
                        'by ${_getSellerName(product)}',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14,
                          color: isDark
                              ? Colors.white.withOpacity(0.6)
                              : Colors.black.withOpacity(0.6),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      displayPrice,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                  ],
                ),
              ),

              // Favorite Button
              TradeRepublicButton(
                icon: const Icon(
                  CupertinoIcons.heart_fill,
                  color: Colors.red,
                  size: 18,
                ),
                isSecondary: true,
                width: 44,
                height: 44,
                padding: EdgeInsets.zero,
                borderRadius: BorderRadius.circular(25),
                onPressed: () => _toggleFavorite(product['id']),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFollowedUserCard(Map<String, dynamic> user, bool isDark) {
    final isSeller = user['is_seller'] == 1 || user['is_seller'] == true;

    return GestureDetector(
      onTap: () {
        if (isSeller) {
          _showSellerProfile(
            user['id'].toString(),
            user['name'] ?? user['username'] ?? 'Seller',
          );
        }
      },
      child: Row(
        children: [
          // User Avatar - Account style
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withOpacity(0.05)
                  : Colors.black.withOpacity(0.02),
              borderRadius: BorderRadius.circular(25),
              border: Border.all(
                color: isDark
                    ? Colors.white.withOpacity(0.1)
                    : Colors.black.withOpacity(0.05),
                width: 0.5,
              ),
            ),
            child: user['avatar_url'] != null || user['avatar'] != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(25),
                    child: Image.network(
                      user['avatar_url'] ?? user['avatar'] ?? '',
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Center(
                          child: Text(
                            (user['name'] ?? user['username'] ?? 'U')[0]
                                .toUpperCase(),
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              color: isDark ? Colors.white : Colors.black,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        );
                      },
                    ),
                  )
                : Center(
                    child: Text(
                      (user['name'] ?? user['username'] ?? 'U')[0]
                          .toUpperCase(),
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        color: isDark ? Colors.white : Colors.black,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
          ),

          const SizedBox(width: 16),

          // User Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user['name'] ?? user['username'] ?? 'User',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                if (user['username'] != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '@${user['username']}',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      color: isDark
                          ? const Color(0xFF8E8E93)
                          : const Color(0xFF6C6C6C),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (isSeller) ...[
                      Icon(
                        CupertinoIcons.bag,
                        size: 16,
                        color: const Color(0xFF45B7D1),
                      ),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      isSeller ? AppLocalizations.of(context)!.seller : 'User',
                      style: TextStyle(
                        fontSize: 14,
                        color: isSeller
                            ? const Color(0xFF45B7D1)
                            : (isDark
                                  ? const Color(0xFF8E8E93)
                                  : const Color(0xFF6C6C6C)),
                      ),
                    ),
                    if (user['isVerified'] == true) ...[
                      const SizedBox(width: 6),
                      Icon(
                        CupertinoIcons.checkmark_seal_fill,
                        size: 16,
                        color: const Color(0xFF45B7D1),
                      ),
                    ],
                  ],
                ),
                if (user['bio'] != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    user['bio'],
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      color: isDark
                          ? const Color(0xFF8E8E93)
                          : const Color(0xFF6C6C6C),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (user['followersCount'] != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${user['followersCount']} followers',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: isDark
                          ? const Color(0xFF8E8E93)
                          : const Color(0xFF6C6C6C),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Notification Toggle & Unfollow Button - Account style
          Row(
            children: [
              if (isSeller) ...[
                // Notification Toggle - Modern Switch
                TradeRepublicSwitch(
                  value:
                      _sellerNotificationSettings[user['id'].toString()] ??
                      false,
                  onChanged: (value) {
                    _toggleSellerNotifications(user['id'].toString());
                  },
                ),
                const SizedBox(width: 8),
              ],

              // Unfollow Button
              Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withOpacity(0.05)
                      : Colors.black.withOpacity(0.02),
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withOpacity(0.1)
                        : Colors.black.withOpacity(0.05),
                    width: 0.5,
                  ),
                ),
                child: TradeRepublicButton(
                  icon: const Icon(
                    CupertinoIcons.person_badge_minus,
                    color: Colors.red,
                    size: 18,
                  ),
                  isSecondary: true,
                  width: 44,
                  height: 44,
                  padding: EdgeInsets.zero,
                  borderRadius: BorderRadius.circular(25),
                  onPressed: () async {
                    try {
                      // Safety check: prevent unfollowing yourself
                      final currentUsername =
                          await DeviceStorage.getString('stored_username') ??
                          '';
                      final targetUsername =
                          user['username'] ?? user['id'].toString();

                      if (currentUsername == targetUsername) {
                        _showBottomMessage(
                          AppLocalizations.of(context)!.cannotUnfollowYourself,
                          isError: true,
                        );
                        return;
                      }

                      // Call API to unfollow user
                      final result = await ApiService.unfollowUser(
                        targetUsername,
                      );
                      if (result['success'] == true) {
                        setState(() {
                          _followedUsers.removeWhere(
                            (u) =>
                                u['id'] == user['id'] ||
                                u['username'] == user['username'],
                          );
                        });
                        await _saveFollowedUsersToPrefs();

                        // Also remove the individual follow flag for seller profiles
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.remove('following_$targetUsername');

                        _showBottomMessage(
                          'Unfollowed ${user['name'] ?? user['username']}',
                          isSuccess: true,
                        );
                      } else {
                        _showBottomMessage(
                          AppLocalizations.of(context)!.failedToUnfollowUser,
                          isError: true,
                        );
                      }
                    } catch (e) {
                      debugPrint('Error unfollowing user: $e');
                      // Fallback: remove from local list
                      setState(() {
                        _followedUsers.removeWhere(
                          (u) =>
                              u['id'] == user['id'] ||
                              u['username'] == user['username'],
                        );
                      });
                      await _saveFollowedUsersToPrefs();
                      _showBottomMessage(
                        'Unfollowed ${user['name'] ?? user['username']}',
                        isSuccess: true,
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Account page methods
  // Removed duplicate method

  // Quick Action Card for the top row
  Widget _buildUserProfileCard(Map<String, dynamic> user, bool isDark) {
    final isSeller = user['is_seller'] == 1 || user['is_seller'] == true;
    final sellerId =
        user['seller_id'] ?? user['username'] ?? user['id']?.toString();
    final hasNotifications = _sellerNotificationSettings[sellerId] ?? false;

    return Container(
      padding: const EdgeInsets.all(20), // Same padding as Account cards
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.05)
            : Colors.black.withOpacity(0.02), // Same as Account page
        borderRadius: BorderRadius.circular(25), // Same border radius
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.1)
              : Colors.black.withOpacity(0.05), // Same border
          width: 1,
        ),
      ),
      child: GestureDetector(
        onTap: () {
          if (isSeller && sellerId != null) {
            // Open seller profile modal
            _showSellerProfile(
              sellerId,
              user['name'] ?? user['username'] ?? 'Seller',
            );
          } else {
            // Open user profile or start conversation for regular users
            //debugPrint('Open user profile for: ${user['name']}');
          }
        },
        child: Row(
          children: [
            // User Avatar with seller indicator
            Stack(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDark
                        ? Colors.white.withOpacity(0.1)
                        : Colors.black.withOpacity(0.08),
                  ),
                  child: user['avatar_url'] != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(25),
                          child: Image.network(
                            user['avatar_url'],
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Center(
                                child: Text(
                                  (user['name'] ?? 'U')[0].toUpperCase(),
                                  style: const TextStyle(
                                    fontFamily: 'Poppins',
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              );
                            },
                          ),
                        )
                      : Center(
                          child: Text(
                            (user['name'] ?? 'U')[0].toUpperCase(),
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                ),
                // Seller badge
                if (isSeller)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark
                              ? (Colors.grey[900] ?? Colors.black)
                              : Colors.white,
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        CupertinoIcons.bag,
                        color: Colors.white,
                        size: 10,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 16),
            // User Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          user['name'] ??
                              AppLocalizations.of(context)!.unknownUser,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                      ),
                      if (isSeller)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(25),
                          ),
                          child: Text(
                            AppLocalizations.of(context)!.seller,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.green,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '@${user['username'] ?? 'unknown'}',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      color: isDark
                          ? Colors.white.withOpacity(0.6)
                          : Colors.black.withOpacity(0.6),
                    ),
                  ),
                  if (user['bio'] != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      user['bio'],
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? Colors.white.withOpacity(0.5)
                            : Colors.black.withOpacity(0.5),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  // Product count for sellers
                  if (isSeller) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${user['product_count'] ?? 0} products',
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: Color(0xFF10B981),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Actions Row
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Notification toggle for sellers
                if (isSeller && sellerId != null) ...[
                  GestureDetector(
                    onTap: () => _toggleSellerNotifications(sellerId),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: hasNotifications
                            ? (isDark
                                  ? Colors.white.withOpacity(0.15)
                                  : Colors.black.withOpacity(0.08))
                            : (isDark
                                  ? Colors.white.withOpacity(0.05)
                                  : Colors.black.withOpacity(0.02)),
                        borderRadius: BorderRadius.circular(25),
                      ),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: Icon(
                          hasNotifications
                              ? CupertinoIcons.bell_fill
                              : CupertinoIcons.bell_slash,
                          key: ValueKey(hasNotifications),
                          color: isDark
                              ? Colors.white.withOpacity(0.9)
                              : Colors.black.withOpacity(0.8),
                          size: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                // Following Status - Keep RED for favorites consistency
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(
                      0xFFFF6B6B,
                    ).withOpacity(0.1), // Red like favorites
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: Text(
                    AppLocalizations.of(context)!.following,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFFF6B6B), // Red text like favorites
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Quick Action Card for the top row
  Widget _buildQuickActionCard({
    required bool isDark,
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    // Modern glassmorphic design for macOS
    if (Platform.isMacOS) {
      return GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          width: 140,
          height: 140,
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withOpacity(0.04)
                : Colors.black.withOpacity(0.03),
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withOpacity(0.08)
                      : Colors.black.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  icon,
                  size: 28,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black,
                  letterSpacing: -0.2,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      );
    }

    // Use CNButton.icon on iOS for native look
    if (Platform.isIOS) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TradeRepublicButton(
            icon: Icon(icon),
            onPressed: () {
              HapticFeedback.lightImpact();
              onTap();
            },
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black,
            ),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TradeRepublicButton(
          icon: Icon(icon),
          onPressed: () {
            HapticFeedback.lightImpact();
            onTap();
          },
        ),
        const SizedBox(height: 8),
        Text(
          title,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black,
          ),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          maxLines: 2,
        ),
      ],
    );
  }

  // Modern Section Builder
  // Modern List Item
  Widget _buildListItem({
    required bool isDark,
    required IconData icon,
    required String title,
    required String subtitle,
    required IconData trailing,
    required VoidCallback onTap,
    Color? textColor,
    Color? iconColor,
  }) {
    if (textColor != null) {
      return TradeRepublicListTile.destructive(
        title: title,
        subtitle: subtitle,
        leading: Icon(icon, size: 20),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
      );
    }
    return TradeRepublicListTile.navigation(
      title: title,
      subtitle: subtitle,
      leading: Icon(
        icon,
        size: 20,
        color: iconColor ?? (isDark ? Colors.white : Colors.black),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
    );
  }

  Widget _buildInfoItem({
    required bool isDark,
    required IconData icon,
    required String title,
    required String value,
  }) {
    return TradeRepublicListTile(
      title: value,
      subtitle: title,
      leading: Icon(
        icon,
        size: 20,
        color: isDark ? Colors.white : Colors.black,
      ),
    );
  }

  Widget _buildBiometricListItem(bool isDark) {
    return TradeRepublicListTile.toggle(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      title: AppLocalizations.of(context)!.biometricAuthentication,
      subtitle: _biometricEnabled
          ? AppLocalizations.of(context)!.enabled
          : (_biometricAvailable
                ? AppLocalizations.of(context)!.available
                : AppLocalizations.of(context)!.notAvailable),
      leading: const Icon(CupertinoIcons.lock_fill, size: 20),
      value: _biometricEnabled && _biometricAvailable,
      onChanged: (value) {
        if (_biometricAvailable) {
          _toggleBiometricSetting(value);
        }
      },
    );
  }

  Future<void> _toggleBiometricSetting(bool enable) async {
    if (!_biometricAvailable) {
      _showBottomMessage(
        AppLocalizations.of(
          context,
        )!.biometricAuthenticationIsNotAvailableOnThis,
        isError: true,
      );
      return;
    }

    if (enable) {
      // Test biometric authentication before enabling
      try {
        final isAuthenticated = await _localAuth.authenticate(
          localizedReason: AppLocalizations.of(
            context,
          )!.verifyYourIdentityToEnableBiometricAuthentic,
          options: const AuthenticationOptions(
            biometricOnly: true,
            stickyAuth: true,
          ),
        );

        if (isAuthenticated) {
          setState(() {
            _biometricEnabled = true;
          });

          // Persist local device setting
          await DeviceStorage.setBool('biometric_enabled', true);

          // Persist to backend so value survives next login/profile reload
          if (_isLoggedIn) {
            try {
              await ApiService.updateUserSettings({'biometric_enabled': true});
            } catch (e) {
              debugPrint('⚠️ Could not persist biometric_enabled=true to backend: $e');
            }
          }

          _showBottomMessage(
            AppLocalizations.of(context)!.biometricAuthenticationEnabled,
            isSuccess: true,
          );
        }
      } catch (e) {
        //debugPrint('Biometric authentication error: $e');
        _showBottomMessage(
          AppLocalizations.of(context)!.failedToVerifyBiometricAuthentication,
          isError: true,
        );
      }
    } else {
      // Disable biometric
      setState(() {
        _biometricEnabled = false;
      });

      // Persist local device setting
      await DeviceStorage.setBool('biometric_enabled', false);

      // Persist to backend so value survives next login/profile reload
      if (_isLoggedIn) {
        try {
          await ApiService.updateUserSettings({'biometric_enabled': false});
        } catch (e) {
          debugPrint('⚠️ Could not persist biometric_enabled=false to backend: $e');
        }
      }

      _showBottomMessage(
        AppLocalizations.of(context)!.biometricAuthenticationDisabled,
      );
    }
  }

  Future<void> _show2FACode() async {
    await _refresh2FAStateFromServer();

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      useRootNavigator: true,
      maxHeight: MediaQuery.of(context).size.height * 0.82,
      child: _build2FAManagementModal(),
    );
  }

  Widget _build2FAManagementModal() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? Colors.white : Colors.black;
    final surface = isDark
        ? Colors.white.withOpacity(0.06)
        : Colors.black.withOpacity(0.04);
    bool codeVisible = false;

    return StatefulBuilder(
      builder: (context, setModal) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ──
            Row(
              children: [
                Icon(CupertinoIcons.lock_shield_fill, size: 22, color: fg),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context)!.twoFactorAuth,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: fg,
                      letterSpacing: -0.4,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // ── Status pill ──
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Icon(
                    _has2FAEnabled
                        ? CupertinoIcons.checkmark_shield_fill
                        : CupertinoIcons.shield,
                    size: 20,
                    color: fg,
                  ),
                  const SizedBox(width: 14),
                  Text(
                    _has2FAEnabled ? '2FA aktiviert' : '2FA deaktiviert',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: fg,
                    ),
                  ),
                ],
              ),
            ),

            // ── Code display (only when enabled) ──
            if (_has2FAEnabled && _user2FACode != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dein 2FA Code',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: fg.withOpacity(0.45),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(
                        _user2FACode!.length.clamp(0, 8),
                        (i) {
                          final ch = _user2FACode![i];
                          return Container(
                            width: 36,
                            height: 46,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: fg.withOpacity(0.15),
                                width: 1.5,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            alignment: Alignment.center,
                            child: codeVisible
                                ? Text(
                                    ch,
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                      color: fg,
                                    ),
                                  )
                                : Container(
                                    width: 9,
                                    height: 9,
                                    decoration: BoxDecoration(
                                      color: fg.withOpacity(0.4),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 14),
                    GestureDetector(
                      onTap: () =>
                          setModal(() => codeVisible = !codeVisible),
                      behavior: HitTestBehavior.opaque,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            codeVisible
                                ? CupertinoIcons.eye_slash
                                : CupertinoIcons.eye,
                            size: 15,
                            color: fg.withOpacity(0.45),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            codeVisible ? 'Ausblenden' : 'Code anzeigen',
                            style: TextStyle(
                              fontSize: 13,
                              color: fg.withOpacity(0.45),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 24),

            // ── Action buttons ──
            if (!_has2FAEnabled) ...[
              TradeRepublicButton(
                label: AppLocalizations.of(context)!.setup2FA,
                onPressed: () => _showSetup2FAModal(),
                width: double.infinity,
              ),
            ] else ...[
              TradeRepublicButton(
                label: AppLocalizations.of(context)!.generateNewCode,
                onPressed: () => _showSetup2FAModal(isUpdate: true),
                width: double.infinity,
              ),
              const SizedBox(height: 12),
              TradeRepublicButton(
                label: AppLocalizations.of(context)!.disable2FA,
                onPressed: () {
                  Navigator.of(context).pop();
                  _showDisable2FAConfirmation();
                },
                isDestructive: true,
                width: double.infinity,
              ),
            ],
            SizedBox(
              height: MediaQuery.of(context).viewInsets.bottom + 8,
            ),
          ],
        );
      },
    );
  }

  void _showSetup2FAModal({bool isUpdate = false}) {
    Navigator.of(context).pop();
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      useRootNavigator: true,
      maxHeight: MediaQuery.of(context).size.height * 0.78,
      child: _build2FASetupModal(isUpdate: isUpdate),
    );
  }

  Widget _build2FASetupModal({bool isUpdate = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? Colors.white : Colors.black;
    final surface = isDark
        ? Colors.white.withOpacity(0.06)
        : Colors.black.withOpacity(0.04);
    final codeController = TextEditingController();

    return StatefulBuilder(
      builder: (context, setModal) {
        void generateRandom() {
          final rand =
              List.generate(8, (_) => Random().nextInt(10).toString()).join();
          setModal(() => codeController.text = rand);
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ──
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  isUpdate
                      ? CupertinoIcons.arrow_2_circlepath
                      : CupertinoIcons.lock_shield,
                  size: 22,
                  color: fg,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isUpdate
                            ? AppLocalizations.of(context)!.generateNew2faCode
                            : AppLocalizations.of(context)!.setup2FA,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: fg,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '8-stelliger numerischer Code',
                        style: TextStyle(
                          fontSize: 14,
                          color: fg.withOpacity(0.45),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 28),

            // ── Code input ──
            TradeRepublicTextField.code(
              controller: codeController,
              onChanged: (_) => setModal(() {}),
              maxLength: 8,
              hintText: AppLocalizations.of(context)!.enterEightDigitCode,
            ),

            const SizedBox(height: 10),

            // ── Generate random button ──
            GestureDetector(
              onTap: generateRandom,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      CupertinoIcons.arrow_2_circlepath,
                      size: 14,
                      color: fg.withOpacity(0.4),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      'Generate Random Code',
                      style: TextStyle(
                        fontSize: 13,
                        color: fg.withOpacity(0.4),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 18),

            // ── Info box ──
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        CupertinoIcons.info_circle,
                        size: 15,
                        color: fg.withOpacity(0.4),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Wichtige Hinweise',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: fg.withOpacity(0.4),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '• Genau 8 Ziffern (0–9)\n• Diesen Code gut merken – du brauchst ihn bei jedem Login',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.6,
                      color: fg.withOpacity(0.35),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Save button ──
            TradeRepublicButton(
              label: _isLoading
                  ? AppLocalizations.of(context)!.saving
                  : (isUpdate
                      ? AppLocalizations.of(context)!.updateCode
                      : AppLocalizations.of(context)!.saveCode),
              isLoading: _isLoading,
              width: double.infinity,
              onPressed: _isLoading
                  ? null
                  : () async {
                      if (codeController.text.length != 8) {
                        _showInfo(
                          AppLocalizations.of(context)!.enterEightDigitCode,
                        );
                        return;
                      }
                      await _save2FACodeToDatabase(
                        codeController.text,
                        isUpdate: isUpdate,
                      );
                      if (mounted) Navigator.of(context).pop();
                    },
            ),

            const SizedBox(height: 12),

            // ── Cancel button ──
            TradeRepublicButton(
              label: AppLocalizations.of(context)!.cancel,
              isSecondary: true,
              width: double.infinity,
              onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
            ),
            SizedBox(
              height: MediaQuery.of(context).viewInsets.bottom + 8,
            ),
          ],
        );
      },
    );
  }

  Future<void> _save2FACodeToDatabase(
    String code, {
    bool isUpdate = false,
  }) async {
    try {
      setState(() {
        _isLoading = true;
      });

      //debugPrint('🔐 ${isUpdate ? 'Updating' : 'Saving'} 2FA code to database');

      // Call API to save/update 2FA code in database
      final result = await ApiService.save2FACode(
        '',
        code,
      ); // Username not needed, backend gets it from JWT

      if (result['success'] == true) {
        //debugPrint('✅ 2FA code ${isUpdate ? 'updated' : 'saved'} successfully in database');

        // Update local state
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_2fa_code', code);
        await prefs.setBool('has_2fa_enabled', true);

        setState(() {
          _user2FACode = code;
          _has2FAEnabled = true;
          _isLoading = false;
        });

        // Show success message
        if (mounted) {
          _showBottomMessage(
            isUpdate
                ? AppLocalizations.of(context)!.tfaCodeUpdatedSuccess
                : AppLocalizations.of(context)!.tfaCodeSavedSuccess,
            isSuccess: true,
          );
        }
      } else {
        String errorMessage =
            result['message'] ??
            AppLocalizations.of(context)!.errorSaving2FACode;
        throw Exception(errorMessage);
      }
    } catch (e) {
      //debugPrint(' Error saving 2FA code to database: $e');

      setState(() {
        _isLoading = false;
      });

      // Show error message
      if (mounted) {
        _showBottomMessage(
          'Failed to save 2FA code to database: ${e.toString()}',
          isError: true,
        );
      }
    }
  }

  void _showDisable2FAConfirmation() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? Colors.white : Colors.black;
    final surface = isDark
        ? Colors.white.withOpacity(0.06)
        : Colors.black.withOpacity(0.04);

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      useRootNavigator: true,
      child: Builder(
        builder: (context) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Header ──
              Row(
                children: [
                  Icon(CupertinoIcons.shield, size: 22, color: fg),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context)!.disable2FA,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: fg,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // ── Warning box ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  AppLocalizations.of(
                    context,
                  )!.areYouSureYouWantToDisableTwofactorAuthent1,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    color: fg.withOpacity(0.65),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

              const SizedBox(height: 24),

              // ── Buttons ──
              Row(
                children: [
                  Expanded(
                    child: TradeRepublicButton(
                      label: AppLocalizations.of(context)!.cancel,
                      isSecondary: true,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TradeRepublicButton(
                      label: AppLocalizations.of(context)!.disable2FA,
                      isDestructive: true,
                      onPressed: () {
                        Navigator.of(context).pop();
                        _disable2FA();
                      },
                    ),
                  ),
                ],
              ),
              SizedBox(
                height: MediaQuery.of(context).viewInsets.bottom + 8,
              ),
            ],
          );
        },
      ),
    );
  }

  // Removed _generateNew2FACode method to prevent lag

  void _showInfo(String message) {
    _showBottomMessage(message);
  }

  Future<void> _openLegalPage(String anchor) async {
    final uri = Uri.parse('https://cultioo.com/us/us_legal_app#$anchor');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    if (mounted) {
      TopNotification.error(context, 'Could not open legal page');
    }
  }

  // Glass effect section builder
  Widget _buildGlassSection({
    required bool isDark,
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            title,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF1C1C1E),
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: isDark
                ? Colors.transparent
                : Colors.black.withOpacity(0.02),
            borderRadius: BorderRadius.circular(25),
            border: null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Column(children: children),
        ),
      ],
    );
  }

  // Settings item builder with Apple-like design
  Widget _buildSettingsItem({
    required bool isDark,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return TradeRepublicListTile.navigation(
      title: title,
      subtitle: subtitle,
      leading: Icon(
        icon,
        size: 20,
        color: isDark ? Colors.white : Colors.black,
      ),
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
    );
  }

  Widget _buildDockToggleItem(bool isDark) {
    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withOpacity(0.1)
                    : Colors.black.withOpacity(0.05),
                borderRadius: BorderRadius.circular(25),
              ),
              child: Icon(
                CupertinoIcons.square_grid_2x2,
                color: isDark ? Colors.white : Colors.black,
                size: 20,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context)!.motionDock,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _isDockEnabled
                        ? AppLocalizations.of(context)!.enabled
                        : 'Disabled',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark
                          ? const Color(0xFF8E8E93)
                          : const Color(0xFF8E8E93),
                    ),
                  ),
                ],
              ),
            ),
            TradeRepublicSwitch(
              value: _isDockEnabled,
              onChanged: (value) => _toggleDockSetting(),
            ),
          ],
        ),
      ),
    );
  } // Appearance Settings Helper Methods

  String _getThemeDisplayName() {
    switch (_themeMode) {
      case 'light':
        return AppLocalizations.of(context)!.themeLight;
      case 'dark':
        return AppLocalizations.of(context)!.themeDark;
      case 'system':
      default:
        return AppLocalizations.of(context)!.themeSystem;
    }
  }

  // Resolve 'system' setting to actual value based on device locale
  String _resolveLanguage() {
    if (_language != 'system') return _language;
    final locale = PlatformDispatcher.instance.locale;
    final supported = ['en', 'de', 'es', 'fr', 'ru', 'it', 'pt'];
    return supported.contains(locale.languageCode) ? locale.languageCode : 'en';
  }

  String _resolveNumberFormat() {
    if (_numberFormat != 'system') return _numberFormat;
    final locale = PlatformDispatcher.instance.locale;
    // German-style number format for DE, AT, CH, etc.
    final deLocales = ['de', 'fr', 'es', 'it', 'pt', 'ru'];
    return deLocales.contains(locale.languageCode) ? 'de' : 'en';
  }

  String _resolveCurrency() {
    if (_currency != 'system') return _currency;
    final locale = PlatformDispatcher.instance.locale;
    final country = locale.countryCode?.toUpperCase() ?? '';
    switch (country) {
      // Eurozone
      case 'DE': case 'AT': case 'FR': case 'ES': case 'IT': case 'PT':
      case 'NL': case 'BE': case 'FI': case 'IE': case 'GR': case 'LU':
      case 'SK': case 'SI': case 'EE': case 'LV': case 'LT': case 'CY':
      case 'MT': case 'HR':
        return 'eur';
      case 'GB': return 'gbp';
      case 'PL': return 'pln';
      case 'CZ': return 'czk';
      case 'HU': return 'huf';
      case 'SE': return 'sek';
      case 'DK': return 'dkk';
      case 'NO': return 'nok';
      case 'CH': case 'LI': return 'chf';
      case 'BG': return 'bgn';
      case 'RO': return 'ron';
      case 'CA': return 'cad';
      case 'MX': return 'mxn';
      case 'RU': return 'rub';
      default:   return 'usd';
    }
  }

  String _resolveDistanceUnit() {
    if (_distanceUnit != 'system') return _distanceUnit;
    final locale = PlatformDispatcher.instance.locale;
    final country = locale.countryCode?.toUpperCase() ?? '';
    // US, UK, Myanmar, Liberia use miles
    return (country == 'US' ||
            country == 'GB' ||
            country == 'MM' ||
            country == 'LR')
        ? 'miles'
        : 'km';
  }

  String _resolveWeightUnit() {
    if (_weightUnit != 'system') return _weightUnit;
    final locale = PlatformDispatcher.instance.locale;
    final country = locale.countryCode?.toUpperCase() ?? '';
    return (country == 'US' ||
            country == 'GB' ||
            country == 'MM' ||
            country == 'LR')
        ? 'lbs'
        : 'kg';
  }

  String _resolveDateFormat() {
    if (_dateFormat != 'system') return _dateFormat;
    final locale = PlatformDispatcher.instance.locale;
    final country = locale.countryCode?.toUpperCase() ?? '';
    switch (country) {
      case 'US':
        return 'MM/dd/yyyy';
      case 'GB':
        return 'dd-MM-yyyy';
      case 'DE':
      case 'AT':
      case 'CH':
        return 'dd.MM.yyyy';
      default:
        return 'dd/MM/yyyy';
    }
  }

  String _getTextSizeDisplayName() {
    switch (_textSize) {
      case 'small':
        return AppLocalizations.of(context)!.textSizeSmall;
      case 'large':
        return AppLocalizations.of(context)!.textSizeLarge;
      case 'medium':
        return AppLocalizations.of(context)!.textSizeMedium;
      case 'system':
      default:
        return AppLocalizations.of(context)!.system;
    }
  }

  String _getLanguageDisplayName() {
    switch (_language) {
      case 'de':
        return AppLocalizations.of(context)!.languageDe;
      case 'en':
        return AppLocalizations.of(context)!.languageEn;
      case 'es':
        return AppLocalizations.of(context)!.languageEs;
      case 'fr':
        return AppLocalizations.of(context)!.languageFr;
      case 'ru':
        return AppLocalizations.of(context)!.languageRu;
      case 'it':
        return AppLocalizations.of(context)!.languageIt;
      case 'pt':
        return AppLocalizations.of(context)!.languagePt;
      case 'system':
      default:
        return AppLocalizations.of(context)!.system;
    }
  }

  String _getNumberFormatDisplayName() {
    switch (_numberFormat) {
      case 'de':
        return AppLocalizations.of(context)!.numberFormatDe;
      case 'en':
        return AppLocalizations.of(context)!.numberFormatEn;
      case 'system':
      default:
        return AppLocalizations.of(context)!.system;
    }
  }

  String _getCurrencyDisplayName() {
    switch (_currency) {
      case 'eur':
        return AppLocalizations.of(context)!.currencyEur;
      case 'usd':
        return AppLocalizations.of(context)!.currencyUsd;
      case 'rub':
        return AppLocalizations.of(context)!.currencyRub;
      case 'mxn':
        return AppLocalizations.of(context)!.currencyMxn;
      case 'cad':
        return AppLocalizations.of(context)!.currencyCad;
      case 'gbp':
        return AppLocalizations.of(context)!.currencyGbp;
      case 'chf':
        return AppLocalizations.of(context)!.currencyChf;
      case 'pln':
        return AppLocalizations.of(context)!.currencyPln;
      case 'czk':
        return AppLocalizations.of(context)!.currencyCzk;
      case 'huf':
        return AppLocalizations.of(context)!.currencyHuf;
      case 'sek':
        return AppLocalizations.of(context)!.currencySek;
      case 'dkk':
        return AppLocalizations.of(context)!.currencyDkk;
      case 'nok':
        return AppLocalizations.of(context)!.currencyNok;
      case 'bgn':
        return AppLocalizations.of(context)!.currencyBgn;
      case 'ron':
        return AppLocalizations.of(context)!.currencyRon;
      case 'system':
      default:
        return AppLocalizations.of(context)!.system;
    }
  }

  String _getDistanceUnitDisplayName() {
    switch (_distanceUnit) {
      case 'miles':
        return AppLocalizations.of(context)!.miles;
      case 'km':
        return AppLocalizations.of(context)!.kilometers;
      case 'system':
      default:
        return AppLocalizations.of(context)!.system;
    }
  }

  String _getWeightUnitDisplayName() {
    switch (_weightUnit) {
      case 'lbs':
        return AppLocalizations.of(context)!.poundsLbs;
      case 'kg':
        return AppLocalizations.of(context)!.kilogramsKg;
      case 'system':
      default:
        return AppLocalizations.of(context)!.system;
    }
  }

  String _getDateFormatDisplayName() {
    final now = DateTime.now();
    switch (_dateFormat) {
      case 'MM/dd/yyyy':
        return 'US Format (MM/dd/yyyy) - ${_formatDatePreview(now, 'MM/dd/yyyy')}';
      case 'yyyy-MM-dd':
        return 'ISO Format (yyyy-MM-dd) - ${_formatDatePreview(now, 'yyyy-MM-dd')}';
      case 'dd-MM-yyyy':
        return AppLocalizations.of(
          context,
        )!.ukFormatDatePreview(_formatDatePreview(now, 'dd-MM-yyyy'));
      case 'dd/MM/yyyy':
        return AppLocalizations.of(
          context,
        )!.europeanFormatDatePreview(_formatDatePreview(now, 'dd/MM/yyyy'));
      case 'dd.MM.yyyy':
        return 'German (dd.MM.yyyy) - ${_formatDatePreview(now, 'dd.MM.yyyy')}';
      case 'system':
      default:
        return AppLocalizations.of(context)!.system;
    }
  }

  Future<void> _updateAppearanceSetting(String key, String value) async {
    try {
      await SettingsService.updateAllSettings(
        theme: key == 'theme' ? value : null,
        textSize: key == 'textSize' ? value : null,
        language: key == 'language' ? value : null,
        numberFormat: key == 'numberFormat' ? value : null,
        currency: key == 'currency' ? value : null,
      );

      setState(() {
        switch (key) {
          case 'theme':
            _themeMode = value;
            break;
          case 'textSize':
            _textSize = value;
            // Update app text scale factor
            _MyAppState.updateTextScale();
            break;
          case 'language':
            _language = value;
            _localizedStrings = SettingsService.getLocalizedStrings(
              _resolveLanguage(),
            );
            // Update app locale
            _MyAppState.updateLocale(value);
            break;
          case 'numberFormat':
            _numberFormat = value;
            break;
          case 'currency':
            _currency = value;
            if (_resolveCurrency() == 'eur') {
              _loadExchangeRate();
            } else {
              _exchangeRate = 1.0; // Reset to 1.0 for USD
            }
            break;
        }
      });

      // Update app theme if theme changed
      if (key == 'theme') {
        // We need to reload the app to apply theme changes
        _reloadAppTheme();
      }

      TopNotification.success(
        context,
        AppLocalizations.of(context)!.settingsUpdated,
      );
    } catch (e) {
      //debugPrint(' Error updating appearance setting: $e');
      TopNotification.error(
        context,
        AppLocalizations.of(context)!.failedToUpdateSettings,
      );
    }
  }

  Future<void> _toggleDockSetting() async {
    try {
      final newDockState = !_isDockEnabled;

      // Update local settings
      final settings = await SettingsService.loadLocalSettings();
      settings['dockEnabled'] = newDockState;
      await SettingsService.saveLocalSettings(settings);

      setState(() {
        _isDockEnabled = newDockState;
      });

      // Provide haptic feedback
      HapticFeedback.lightImpact();

      TopNotification.success(
        context,
        newDockState
            ? AppLocalizations.of(context)!.motionDockEnabled
            : AppLocalizations.of(context)!.motionDockDisabled,
      );

      //debugPrint('🎛️ Dock setting updated: $_isDockEnabled');
    } catch (e) {
      //debugPrint(' Error updating dock setting: $e');
      TopNotification.error(
        context,
        AppLocalizations.of(context)!.failedToUpdateDockSetting,
      );
    }
  }

  void _reloadAppTheme() {
    // Trigger app theme reload using the static callback
    _MyAppState.updateTheme();
  }

  void _showThemeSelector(bool isDark) {
    _showSettingsModal(
      isDark: isDark,
      title: AppLocalizations.of(context)!.theme,
      options: [
        SettingsOption(
          'light',
          AppLocalizations.of(context)!.themeLight,
          CupertinoIcons.sun_max,
        ),
        SettingsOption(
          'dark',
          AppLocalizations.of(context)!.themeDark,
          CupertinoIcons.moon,
        ),
        SettingsOption(
          'system',
          AppLocalizations.of(context)!.themeSystem,
          CupertinoIcons.gear,
        ),
      ],
      currentValue: _themeMode,
      onChanged: (value) => _updateAppearanceSetting('theme', value),
    );
  }

  void _showTextSizeSelector(bool isDark) {
    final l10n = AppLocalizations.of(context)!;
    _showSettingsModal(
      isDark: isDark,
      title: l10n.textSize,
      options: [
        SettingsOption(
          'system',
          l10n.system,
          CupertinoIcons.device_phone_portrait,
        ),
        SettingsOption(
          'small',
          l10n.textSizeSmall,
          CupertinoIcons.textformat_size,
        ),
        SettingsOption(
          'medium',
          l10n.textSizeMedium,
          CupertinoIcons.textformat,
        ),
        SettingsOption(
          'large',
          l10n.textSizeLarge,
          CupertinoIcons.textformat_size,
        ),
      ],
      currentValue: _textSize,
      onChanged: (value) => _updateAppearanceSetting('textSize', value),
    );
  }

  void _showLanguageSelector(bool isDark) {
    final l10n = AppLocalizations.of(context)!;
    _showSettingsModal(
      isDark: isDark,
      title: l10n.language,
      options: [
        SettingsOption(
          'system',
          l10n.system,
          CupertinoIcons.device_phone_portrait,
        ),
        SettingsOption('en', l10n.languageEn, CupertinoIcons.globe),
        SettingsOption('de', l10n.languageDe, CupertinoIcons.globe),
        SettingsOption('es', l10n.languageEs, CupertinoIcons.globe),
        SettingsOption('fr', l10n.languageFr, CupertinoIcons.globe),
        SettingsOption('ru', l10n.languageRu, CupertinoIcons.globe),
        SettingsOption('it', l10n.languageIt, CupertinoIcons.globe),
        SettingsOption('pt', l10n.languagePt, CupertinoIcons.globe),
      ],
      currentValue: _language,
      onChanged: (value) => _updateAppearanceSetting('language', value),
    );
  }

  void _showNumberFormatSelector(bool isDark) {
    _showSettingsModal(
      isDark: isDark,
      title: AppLocalizations.of(context)!.numberFormat,
      options: [
        SettingsOption(
          'system',
          AppLocalizations.of(context)!.system,
          CupertinoIcons.device_phone_portrait,
        ),
        SettingsOption(
          'en',
          AppLocalizations.of(context)!.numberFormatEn,
          CupertinoIcons.number,
        ),
        SettingsOption(
          'de',
          AppLocalizations.of(context)!.numberFormatDe,
          CupertinoIcons.number,
        ),
      ],
      currentValue: _numberFormat,
      onChanged: (value) => _updateAppearanceSetting('numberFormat', value),
    );
  }

  void _showCurrencySelector(bool isDark) {
    final l10n = AppLocalizations.of(context)!;
    _showSettingsModal(
      isDark: isDark,
      title: l10n.currency,
      options: [
        SettingsOption(
          'system',
          l10n.system,
          CupertinoIcons.device_phone_portrait,
        ),
        SettingsOption(
          'usd',
          l10n.currencyUsd,
          CupertinoIcons.money_dollar_circle,
        ),
        SettingsOption(
          'eur',
          l10n.currencyEur,
          CupertinoIcons.money_euro_circle,
        ),
        SettingsOption(
          'rub',
          l10n.currencyRub,
          CupertinoIcons.money_dollar_circle,
        ),
        SettingsOption(
          'mxn',
          l10n.currencyMxn,
          CupertinoIcons.money_dollar_circle,
        ),
        SettingsOption(
          'cad',
          l10n.currencyCad,
          CupertinoIcons.money_dollar_circle,
        ),
        SettingsOption(
          'gbp',
          l10n.currencyGbp,
          CupertinoIcons.money_dollar_circle,
        ),
        SettingsOption(
          'pln',
          l10n.currencyPln,
          CupertinoIcons.money_dollar_circle,
        ),
        SettingsOption(
          'czk',
          l10n.currencyCzk,
          CupertinoIcons.money_dollar_circle,
        ),
        SettingsOption(
          'huf',
          l10n.currencyHuf,
          CupertinoIcons.money_dollar_circle,
        ),
        SettingsOption(
          'sek',
          l10n.currencySek,
          CupertinoIcons.money_dollar_circle,
        ),
        SettingsOption(
          'dkk',
          l10n.currencyDkk,
          CupertinoIcons.money_dollar_circle,
        ),
        SettingsOption(
          'nok',
          l10n.currencyNok,
          CupertinoIcons.money_dollar_circle,
        ),
        SettingsOption(
          'chf',
          l10n.currencyChf,
          CupertinoIcons.money_dollar_circle,
        ),
        SettingsOption(
          'bgn',
          l10n.currencyBgn,
          CupertinoIcons.money_dollar_circle,
        ),
        SettingsOption(
          'ron',
          l10n.currencyRon,
          CupertinoIcons.money_dollar_circle,
        ),
      ],
      currentValue: _currency,
      onChanged: (value) => _updateAppearanceSetting('currency', value),
    );
  }

  void _showDistanceUnitSelector(bool isDark) {
    _showSettingsModal(
      isDark: isDark,
      title: AppLocalizations.of(context)!.distanceUnit,
      options: [
        SettingsOption(
          'system',
          AppLocalizations.of(context)!.system,
          CupertinoIcons.device_phone_portrait,
        ),
        SettingsOption(
          'km',
          AppLocalizations.of(context)!.kilometers,
          CupertinoIcons.location,
        ),
        SettingsOption(
          'miles',
          AppLocalizations.of(context)!.miles,
          CupertinoIcons.location_solid,
        ),
      ],
      currentValue: _distanceUnit,
      onChanged: (value) {
        setState(() {
          _distanceUnit = value;
        });
        _saveDistanceUnit(value);
      },
    );
  }

  void _showWeightUnitSelector(bool isDark) {
    _showSettingsModal(
      isDark: isDark,
      title: AppLocalizations.of(context)!.weightUnit,
      options: [
        SettingsOption(
          'system',
          AppLocalizations.of(context)!.system,
          CupertinoIcons.device_phone_portrait,
        ),
        SettingsOption(
          'kg',
          AppLocalizations.of(context)!.kilogram,
          CupertinoIcons.chart_bar,
        ),
        SettingsOption(
          'lbs',
          AppLocalizations.of(context)!.pound,
          CupertinoIcons.chart_bar_fill,
        ),
      ],
      currentValue: _weightUnit,
      onChanged: (value) {
        setState(() {
          _weightUnit = value;
        });
        _saveWeightUnit(value);
      },
    );
  }

  void _showDateFormatSelector(bool isDark) {
    final now = DateTime.now();
    _showSettingsModal(
      isDark: isDark,
      title: AppLocalizations.of(context)!.dateFormat,
      options: [
        SettingsOption(
          'system',
          AppLocalizations.of(context)!.system,
          CupertinoIcons.device_phone_portrait,
        ),
        SettingsOption(
          'dd.MM.yyyy',
          'German (dd.MM.yyyy) - ${_formatDatePreview(now, 'dd.MM.yyyy')}',
          CupertinoIcons.calendar,
        ),
        SettingsOption(
          'MM/dd/yyyy',
          'US Format (MM/dd/yyyy) - ${_formatDatePreview(now, 'MM/dd/yyyy')}',
          CupertinoIcons.calendar,
        ),
        SettingsOption(
          'yyyy-MM-dd',
          'ISO Format (yyyy-MM-dd) - ${_formatDatePreview(now, 'yyyy-MM-dd')}',
          CupertinoIcons.calendar,
        ),
        SettingsOption(
          'dd-MM-yyyy',
          AppLocalizations.of(
            context,
          )!.ukFormatDatePreview(_formatDatePreview(now, 'dd-MM-yyyy')),
          CupertinoIcons.calendar,
        ),
        SettingsOption(
          'dd/MM/yyyy',
          AppLocalizations.of(
            context,
          )!.europeanFormatDatePreview(_formatDatePreview(now, 'dd/MM/yyyy')),
          CupertinoIcons.calendar,
        ),
      ],
      currentValue: _dateFormat,
      onChanged: (value) {
        setState(() {
          _dateFormat = value;
        });
        _saveDateFormat(value);
      },
    );
  }

  Future<void> _saveDistanceUnit(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('distance_unit', value);
  }

  Future<void> _saveWeightUnit(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('weight_unit', value);
  }

  Future<void> _saveDateFormat(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('date_format', value);
  }

  // Helper method for date format preview in settings
  String _formatDatePreview(DateTime date, String format) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();

    switch (format) {
      case 'MM/dd/yyyy':
        return '$month/$day/$year';
      case 'yyyy-MM-dd':
        return '$year-$month-$day';
      case 'dd-MM-yyyy':
        return '$day-$month-$year';
      case 'dd/MM/yyyy':
        return '$day/$month/$year';
      case 'dd.MM.yyyy':
      default:
        return '$day.$month.$year';
    }
  }

  void _showSettingsModal({
    required bool isDark,
    required String title,
    required List<SettingsOption> options,
    required String currentValue,
    required Function(String) onChanged,
  }) {
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      useRootNavigator: true,
      maxHeight: 450,
      child: Builder(
        builder: (context) {
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Title
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 24),

                // Options
                ...options.map(
                  (option) => _buildSettingsOptionTile(
                    isDark: isDark,
                    option: option,
                    isSelected: option.value == currentValue,
                    onTap: () {
                      Navigator.of(context).maybePop();
                      onChanged(option.value);
                    },
                  ),
                ),

                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _closeSettingsSheetSafely(BuildContext ctx) async {
    await Navigator.of(ctx).maybePop();
  }

  Widget _buildSettingsOptionTile({
    required bool isDark,
    required SettingsOption option,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final selectionBg =
        TradeRepublicTheme.selectionContainerBackground(context);
    final selectionFg =
        TradeRepublicTheme.selectionContainerForeground(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 3),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            color: isSelected ? selectionBg : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: TradeRepublicListTile(
            title: option.label,
            titleColor: isSelected ? selectionFg : null,
            leading: Icon(
              option.icon,
              size: 20,
              color: isSelected ? selectionFg : null,
            ),
            trailing: isSelected
                ? Icon(
                    CupertinoIcons.checkmark_alt,
                    color: selectionFg,
                    size: 20,
                  )
                : null,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            onTap: onTap,
          ),
        ),
      ),
    );
  }

  String _formatLastLoginDate(DateTime lastLogin) {
    // Use local time
    final now = DateTime.now();
    final difference = now.difference(lastLogin);

    //debugPrint('🔍 Last Login Debug:');
    //debugPrint('   Now: $now');
    //debugPrint('   LastLogin: $lastLogin');
    //debugPrint('   Difference: ${difference.inMinutes} minutes, ${difference.inHours} hours');

    // Format time and date strings
    final timeString =
        '${lastLogin.hour.toString().padLeft(2, '0')}:${lastLogin.minute.toString().padLeft(2, '0')}';
    final dateString =
        '${lastLogin.day.toString().padLeft(2, '0')}.${lastLogin.month.toString().padLeft(2, '0')}.${lastLogin.year}';

    // Always show exact time for recent logins
    if (difference.inMinutes < 5) {
      return '$timeString (${difference.inMinutes} min ago)';
    } else if (difference.inMinutes < 60) {
      return '$timeString (${difference.inMinutes} min ago)';
    } else if (difference.inHours < 24) {
      return '$timeString (${difference.inHours}h ago)';
    } else if (difference.inDays == 1) {
      return AppLocalizations.of(context)!.yesterdayAtTimeMain(timeString);
    } else if (difference.inDays < 7) {
      final dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      final dayName = dayNames[lastLogin.weekday - 1];
      return '$dayName at $timeString';
    } else {
      return '$dateString $timeString';
    }
  }

  // Helper method to get seller name with fallbacks
  String _getSellerName(Map<String, dynamic> product) {
    // Debug: Print the entire product object to see what data we have
    if (kDebugMode) {
      debugPrint('🔍 Full product debug:');
      debugPrint('   - Keys: ${product.keys.toList()}');
      debugPrint('   - username: ${product['username']}');
      debugPrint('   - seller_name: ${product['seller_name']}');
      debugPrint('   - seller: ${product['seller']}');
      debugPrint('   - user: ${product['user']}');
    }

    // Try different possible keys for seller name, including more variations
    final sellerName =
        product['seller_name'] ??
        product['sellerName'] ??
        product['username'] ??
        product['seller']?['name'] ??
        product['seller']?['businessName'] ??
        product['seller']?['firstName'] ??
        product['user']?['name'] ??
        product['user']?['businessName'] ??
        product['user']?['firstName'] ??
        product['user_name'] ??
        product['userName'] ??
        product['createdBy'] ??
        product['created_by'] ??
        product['owner'] ??
        product['seller_username'] ??
        AppLocalizations.of(context)!.unknownSeller;

    if (kDebugMode) {
      debugPrint('   - Final seller name: $sellerName');
    }

    return sellerName;
  }

  String? _encodeProfileImageForUpload(Uint8List originalBytes) {
    try {
      final decoded = img.decodeImage(originalBytes);
      if (decoded == null) return null;

      final longestSide = max(decoded.width, decoded.height);
      final target = longestSide > 128 ? 128 : longestSide;

      final resized = img.copyResize(
        decoded,
        width: decoded.width >= decoded.height ? target : null,
        height: decoded.height > decoded.width ? target : null,
        interpolation: img.Interpolation.average,
      );

      final jpg = img.encodeJpg(resized, quality: 50);
      final dataUrl = 'data:image/jpeg;base64,${base64Encode(jpg)}';
      if (dataUrl.length > 60000) return null;
      return dataUrl;
    } catch (_) {
      return null;
    }
  }

  String? _normalizeProfileImageSource(dynamic raw) {
    if (raw == null) return null;

    if (raw is String) {
      final src = raw.trim();
      if (src.isEmpty || src == 'null') return null;

      if (src.startsWith('data:image') ||
          src.startsWith('http://') ||
          src.startsWith('https://') ||
          src.startsWith('/')) {
        return src;
      }

      // JSON payload as string, e.g. {"type":"Buffer","data":[...]}
      if (src.contains('"type"') &&
          src.contains('Buffer') &&
          src.contains('"data"')) {
        try {
          final parsed = jsonDecode(src);
          final fromJson = _normalizeProfileImageSource(parsed);
          if (fromJson != null) return fromJson;
        } catch (_) {
          // ignore and continue with other heuristics
        }
      }

      // Raw base64 without data URL prefix
      final looksLikeBase64 = RegExp(r'^[A-Za-z0-9+/=\s]+$').hasMatch(src);
      if (looksLikeBase64 && src.length > 100) {
        return 'data:image/jpeg;base64,${src.replaceAll(RegExp(r'\s+'), '')}';
      }

      return src;
    }

    // Buffer-like JSON map from backend serialization
    if (raw is Map) {
      final type = raw['type']?.toString();
      final data = raw['data'];
      if (type == 'Buffer' && data is List) {
        try {
          final bytes = List<int>.from(data);
          return 'data:image/jpeg;base64,${base64Encode(bytes)}';
        } catch (_) {
          return null;
        }
      }

      // Nested value fallbacks
      for (final key in [
        'profilePic',
        'profile_image',
        'profileImage',
        'avatar',
      ]) {
        final nested = _normalizeProfileImageSource(raw[key]);
        if (nested != null && nested.isNotEmpty) return nested;
      }
    }

    return null;
  }

  String? _resolveCurrentUserProfileImage() {
    final user = _currentUser;
    if (user == null) return null;

    for (final key in [
      'profileImage',
      'profilePic',
      'profile_image',
      'avatar',
    ]) {
      final normalized = _normalizeProfileImageSource(user[key]);
      if (normalized != null && normalized.isNotEmpty) return normalized;
    }
    return null;
  }

  String _getAccountDisplayLabel() {
    final username = _userUsername.trim().isNotEmpty
        ? _userUsername.trim()
        : (_currentUser?['username']?.toString().trim() ?? '');
    final business = (_businessName ?? '').trim();

    if (username.isNotEmpty) {
      return business.isNotEmpty ? '@$username · $business' : '@$username';
    }

    if (_userName.trim().isNotEmpty) return _userName.trim();
    if (_userEmail.trim().isNotEmpty) return _userEmail.trim();
    return AppLocalizations.of(context)!.unknownUser;
  }

  /// Renders a profile image from a base64 data URL or a regular URL.
  Widget _buildProfileImage(String src) {
    try {
      if (src.startsWith('data:image')) {
        final comma = src.indexOf(',');
        if (comma != -1) {
          final bytes = base64Decode(src.substring(comma + 1));
          return Image.memory(
            bytes,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
          );
        }
      }

      // Raw base64 without data URL prefix
      final trimmed = src.trim();
      final looksLikeBase64 = RegExp(r'^[A-Za-z0-9+/=\s]+$').hasMatch(trimmed);
      if (looksLikeBase64 && trimmed.length > 100) {
        final bytes = base64Decode(trimmed.replaceAll(RegExp(r'\s+'), ''));
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        );
      }

      // Normalize URL (relative DB paths -> current backend host)
      final backendBase = ApiService.baseUrl.replaceFirst('/api', '');
      final normalized = trimmed;
      final url =
          normalized.startsWith('http://') || normalized.startsWith('https://')
          ? normalized
          : normalized.startsWith('/')
          ? '$backendBase$normalized'
          : normalized.startsWith('uploads/')
          ? '$backendBase/$normalized'
          : '$backendBase/uploads/$normalized';
      return Image.network(
        url,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, _, _) => Center(
          child: Icon(
            CupertinoIcons.person_fill,
            size: 32,
            color: Colors.black26,
          ),
        ),
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }
}

/// Trade Republic-style swipe-to-hide wrapper for closed order cards.
/// Slides left to reveal a minimal dark delete zone, then collapses with
/// a height animation for a smooth removal feel.
class _SwipeToHideOrder extends StatefulWidget {
  final bool isDark;
  final VoidCallback onDismissed;
  final Widget child;

  const _SwipeToHideOrder({
    required super.key,
    required this.isDark,
    required this.onDismissed,
    required this.child,
  });

  @override
  State<_SwipeToHideOrder> createState() => _SwipeToHideOrderState();
}

class _SwipeToHideOrderState extends State<_SwipeToHideOrder>
    with SingleTickerProviderStateMixin {
  late AnimationController _collapseController;
  late Animation<double> _heightFactor;
  late Animation<double> _opacityAnim;

  @override
  void initState() {
    super.initState();
    _collapseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _heightFactor = CurvedAnimation(
      parent: _collapseController,
      curve: Curves.easeInCubic,
    );
    _opacityAnim = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _collapseController, curve: Curves.easeIn),
    );
  }

  @override
  void dispose() {
    _collapseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizeTransition(
      sizeFactor: Tween<double>(begin: 1.0, end: 0.0).animate(_heightFactor),
      axisAlignment: -1,
      child: FadeTransition(
        opacity: _opacityAnim,
        child: TradeRepublicSwipeAction(
          margin: const EdgeInsets.only(bottom: 16),
          borderRadius: 25,
          foregroundColor: widget.isDark ? Colors.black : Colors.white,
          trailing: TradeRepublicSwipeSpec(
            icon: CupertinoIcons.xmark_circle_fill,
            label: 'Hide',
            onActivate: () {
              _collapseController.forward().then((_) {
                if (mounted) widget.onDismissed();
              });
            },
            backgroundColor: const Color(0xFFC80000),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class SettingsOption {
  final String value;
  final String label;
  final IconData icon;

  SettingsOption(this.value, this.label, this.icon);
}

class _ModernNumberButtonWidget extends StatefulWidget {
  final String text;
  final bool isDark;
  final bool isBackspace;
  final VoidCallback onPressed;

  const _ModernNumberButtonWidget({
    required this.text,
    required this.isDark,
    required this.isBackspace,
    required this.onPressed,
  });

  @override
  State<_ModernNumberButtonWidget> createState() =>
      _ModernNumberButtonWidgetState();
}

class _ModernNumberButtonWidgetState extends State<_ModernNumberButtonWidget> {
  bool isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        // Haptic feedback and visual feedback on press
        HapticFeedback.lightImpact();
        setState(() {
          isPressed = true;
        });
      },
      onTapUp: (_) {
        setState(() {
          isPressed = false;
        });
      },
      onTapCancel: () {
        setState(() {
          isPressed = false;
        });
      },
      onTap: widget.onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        transform: Matrix4.identity()..scale(isPressed ? 0.95 : 1.0),
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: widget.isDark
                ? [
                    Colors.white.withOpacity(isPressed ? 0.20 : 0.12),
                    Colors.white.withOpacity(isPressed ? 0.12 : 0.06),
                  ]
                : [
                    Colors.black.withOpacity(isPressed ? 0.12 : 0.06),
                    Colors.black.withOpacity(isPressed ? 0.08 : 0.03),
                  ],
          ),
          borderRadius: BorderRadius.circular(25),
          border: Border.all(
            color: widget.isDark
                ? Colors.white.withOpacity(isPressed ? 0.25 : 0.15)
                : Colors.black.withOpacity(isPressed ? 0.15 : 0.08),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: widget.isDark
                  ? Colors.black.withOpacity(0.3)
                  : Colors.black.withOpacity(0.1),
              blurRadius: isPressed ? 15 : 20,
              offset: Offset(0, isPressed ? 4 : 8),
              spreadRadius: 0,
            ),
          ],
        ),
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: widget.isBackspace ? 24 : 32,
              fontWeight: FontWeight.w600,
              color: widget.isDark
                  ? (isPressed ? Colors.white.withOpacity(0.9) : Colors.white)
                  : (isPressed ? Colors.black.withOpacity(0.9) : Colors.black),
            ),
            child: Text(widget.text),
          ),
        ),
      ),
    );
  }
}

class SecurityVerificationModal extends StatefulWidget {
  final String? expectedCode;
  final bool isAutoLogin;
  final Function(String) onSubmit;
  final VoidCallback onCancel;

  const SecurityVerificationModal({
    super.key,
    this.expectedCode,
    required this.isAutoLogin,
    required this.onSubmit,
    required this.onCancel,
  });

  @override
  State<SecurityVerificationModal> createState() =>
      _SecurityVerificationModalState();
}

class _SecurityVerificationModalState extends State<SecurityVerificationModal> {
  final TextEditingController _codeController = TextEditingController();
  bool _isLoading = false;
  String _enteredCode = '';

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _tryBiometricAuth() async {
    try {
      setState(() {
        _isLoading = true;
      });

      // Get the main app state to check biometric availability
      final mainAppState = context.findAncestorStateOfType<_MyHomePageState>();
      if (mainAppState == null ||
          !mainAppState.biometricAvailable ||
          !mainAppState.biometricEnabled) {
        throw Exception(
          AppLocalizations.of(
            context,
          )!.biometricAuthenticationNotAvailableOrNotEnab,
        );
      }

      final bool didAuthenticate = await mainAppState.localAuth.authenticate(
        localizedReason: AppLocalizations.of(
          context,
        )!.pleaseAuthenticateToVerifyYourIdentity,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );

      if (didAuthenticate) {
        // Use the expected code if biometric auth succeeds
        if (widget.expectedCode != null && widget.expectedCode!.isNotEmpty) {
          widget.onSubmit(widget.expectedCode!);
        } else {
          // Fallback to stored 2FA code
          final prefs = await SharedPreferences.getInstance();
          final stored2FACode = prefs.getString('user_2fa_code');
          if (stored2FACode != null && stored2FACode.isNotEmpty) {
            widget.onSubmit(stored2FACode);
          } else {
            throw Exception('No valid 2FA code available');
          }
        }
      }
    } catch (e) {
      //debugPrint('❌ Biometric authentication failed: $e');
      if (mounted) {
        TopNotification.error(
          context,
          AppLocalizations.of(
            context,
          )!.biometricLoginFailedWithError(e.toString()),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _submitCode() {
    if (_enteredCode.length == 8) {
      widget.onSubmit(_enteredCode);
    }
  }

  // Remove unused functions after number pad removal

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mainAppState = context.findAncestorStateOfType<_MyHomePageState>();
    final biometricAvailable = mainAppState?.biometricAvailable ?? false;
    final biometricEnabled = mainAppState?.biometricEnabled ?? false;
    final showBiometric = biometricAvailable && biometricEnabled;

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width > 800
                ? 480.0
                : double.infinity,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? Colors.black : Colors.white,

              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(25),
                topRight: Radius.circular(25),
              ),
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 32),

                  // Title
                  Text(
                    AppLocalizations.of(context)!.securityVerification,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppLocalizations.of(
                      context,
                    )!.enterYour8digitVerificationCode,
                    style: TextStyle(
                      fontSize: 16,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    AppLocalizations.of(
                      context,
                    )!.codeWillAutosubmitWhenComplete,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: isDark
                          ? Colors.white.withOpacity(0.6)
                          : Colors.grey[500],
                    ),
                    textAlign: TextAlign.center,
                  ),

                  if (showBiometric) ...[
                    const SizedBox(height: 20),
                    // Biometric authentication button
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: TradeRepublicButton(
                        label: _isLoading
                            ? 'Authenticating...'
                            : AppLocalizations.of(
                                context,
                              )!.useBiometricAuthentication,
                        onPressed: _isLoading ? null : _tryBiometricAuth,
                        icon: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CultiooLoadingIndicator(),
                              )
                            : const Icon(CupertinoIcons.lock_fill),
                        isLoading: _isLoading,
                        width: double.infinity,
                      ),
                    ),

                    // Divider with "OR" text
                    Row(
                      children: [
                        Expanded(
                          child: Divider(
                            color: isDark
                                ? Colors.white24
                                : Colors.grey[300],
                            thickness: 1,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                          ),
                          child: Text(
                            'OR',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? Colors.white54
                                  : Colors.grey[600],
                            ),
                          ),
                        ),
                        Expanded(
                          child: Divider(
                            color: isDark
                                ? Colors.white24
                                : Colors.grey[300],
                            thickness: 1,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],

                  const SizedBox(height: 20),

                  // Code display - 8 digits, responsive sizing
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(8, (index) {
                      final hasDigit = index < _enteredCode.length;
                      return Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          height: 48,
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withOpacity(0.1)
                                : Colors.grey[100],
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: hasDigit
                                  ? const Color(0xFF6366F1)
                                  : (isDark
                                        ? Colors.white24
                                        : Colors.grey[300]!),
                              width: 1.5,
                            ),
                          ),
                          child: Center(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 150),
                              transitionBuilder: (child, animation) =>
                                  FadeTransition(
                                      opacity: animation, child: child),
                              child: Text(
                                hasDigit ? _enteredCode[index] : '•',
                                key: ValueKey('$index${hasDigit ? _enteredCode[index] : "empty"}'),
                                style: TextStyle(
                                  fontSize: hasDigit ? 22 : 18,
                                  fontWeight: FontWeight.w700,
                                  color: hasDigit
                                      ? (isDark
                                          ? Colors.white
                                          : const Color(0xFF1E293B))
                                      : (isDark
                                          ? Colors.white24
                                          : Colors.grey[400]),
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),

                  const SizedBox(height: 28),

                  // Simple text input instead of number pad
                  TradeRepublicTextField.code(
                    controller: _codeController,
                    onChanged: (value) {
                      setState(() {
                        _enteredCode = value;
                      });
                      if (value.length == 8) {
                        _submitCode();
                      }
                    },
                    maxLength: 8,
                  ),

                  const SizedBox(height: 28),

                  // Verify button
                  TradeRepublicButton(
                    label: AppLocalizations.of(context)!.verifyCode,
                    onPressed: _enteredCode.length >= 8
                        ? _submitCode
                        : null,
                    width: double.infinity,
                  ),

                  const SizedBox(height: 12),

                  // Cancel button
                  TradeRepublicButton(
                    label: AppLocalizations.of(context)!.cancel,
                    onPressed: widget.onCancel,
                    isSecondary: true,
                  ),

                  const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
  }
}
