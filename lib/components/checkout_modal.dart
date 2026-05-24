import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:convert';
import 'package:flutter_stripe/flutter_stripe.dart';
import '../utils/number_formatters.dart';
import '../services/api_service.dart';
import '../services/trade_republic_widgets.dart';
import '../services/app_localizations.dart';
import '../services/cultioo_spinner.dart';
import 'credit_card_widget.dart';

class CheckoutModal extends StatefulWidget {
  final List<Map<String, dynamic>> cartItems;
  final double totalPrice;
  final String accessToken;
  final Map<String, dynamic>? currentUser;
  final VoidCallback onOrderComplete;
  final String? numberFormat; // Number format preference

  const CheckoutModal({
    super.key,
    required this.cartItems,
    required this.totalPrice,
    required this.accessToken,
    this.currentUser,
    required this.onOrderComplete,
    this.numberFormat,
  });

  @override
  State<CheckoutModal> createState() => _CheckoutModalState();
}

class _CheckoutModalState extends State<CheckoutModal> {
  bool _isLoading = false;
  String _selectedPaymentMethod =
      'saved_card'; // 'saved_card', 'card', 'apple_pay', 'google_pay'

  // Payment form controllers
  final TextEditingController _cardNumberController = TextEditingController();
  final TextEditingController _expiryController = TextEditingController();
  final TextEditingController _cvvController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();

  // Address management - per item
  List<Map<String, dynamic>> _userAddresses = [];
  final Map<int, Map<String, dynamic>?> _selectedAddressPerItem =
      {}; // itemIndex -> address
  bool _isLoadingAddresses = false;

  // Shipping type - per item
  final Map<int, String> _selectedShippingTypePerItem =
      {}; // itemIndex -> 'delvioo' or 'standard'

  // Cleaning certificate requirement - per item
  final Map<int, bool> _requiresCleaningPerItem =
      {}; // itemIndex -> true/false (only if product offers it)

  // Stripe saved cards management
  List<Map<String, dynamic>> _savedCards = [];
  Map<String, dynamic>? _selectedSavedCard;
  Map<String, dynamic>? _selectedSepaMethod;
  Map<String, dynamic>? _selectedAchMethod;
  Map<String, dynamic>? _selectedWireMethod;
  bool _isLoadingSavedCards = false;

  // Product details cache for shipping costs
  final Map<String, Map<String, dynamic>> _productDetails = {};
  bool _isLoadingProducts = false;

  // Business information for payment terms
  final TextEditingController _businessNameController = TextEditingController();
  final TextEditingController _businessTaxIdController =
      TextEditingController();
  final TextEditingController _businessStreetController =
      TextEditingController();
  final TextEditingController _businessHouseNumberController =
      TextEditingController();
  final TextEditingController _businessPostalCodeController =
      TextEditingController();
  final TextEditingController _businessCityController = TextEditingController();
  final TextEditingController _businessCountryController =
      TextEditingController();
  final TextEditingController _businessPhoneController =
      TextEditingController();
  final TextEditingController _businessEmailController =
      TextEditingController();
  final TextEditingController _businessDunsController =
      TextEditingController(); // D-U-N-S® number (optional, improves Gemini AI score)
  Map<String, dynamic>? _businessInfo;
  bool _isLoadingBusinessInfo = false;

  // Created order IDs for success page (used in card payment sheet)
  List<String> _createdOrderIds = [];
  double _totalPaidAmount = 0.0;

  // Payment terms limits (US market)
  static const double _weeklyPaymentLimit = 75000.0; // $75,000/week
  static const double _overLimitFeePercent = 1.0; // 1% fee over limit
  double _currentWeekUsage = 0.0;
  bool _isLoadingWeeklyUsage = false;

  // Removed single shipping type selection - now using per-item selection
  // final Set<String> _selectedShippingTypes = {'delvioo'}; // delvioo is always selected

  double _parseCartQuantity(dynamic quantityRaw) {
    if (quantityRaw is num) {
      return quantityRaw.toDouble();
    }

    if (quantityRaw is String) {
      return double.tryParse(quantityRaw.trim().replaceAll(',', '.')) ?? 1.0;
    }

    return 1.0;
  }

  // Shipping cost calculation - sums up all selected shipping costs per item
  double get _shippingCost {
    double totalShippingCost = 0.0;

    for (int i = 0; i < widget.cartItems.length; i++) {
      final item = widget.cartItems[i];
      final productId = item['productId'];
      final quantityRaw = item['quantity'] ?? 1;
      final quantity = _parseCartQuantity(quantityRaw);
      final product = _productDetails[productId?.toString() ?? ''];
      final selectedShippingType = _selectedShippingTypePerItem[i] ?? 'delvioo';

      if (product != null) {
        final shippingCostsRaw = product['shippingCosts'];
        if (shippingCostsRaw != null) {
          try {
            String shippingCostsStr = shippingCostsRaw.toString();
            if (shippingCostsStr.startsWith('{')) {
              Map<String, dynamic> costs = json.decode(shippingCostsStr);
              // Use the selected shipping type for this item
              if (costs.containsKey(selectedShippingType)) {
                final cost = costs[selectedShippingType];
                double costValue = (cost is int)
                    ? cost.toDouble()
                    : double.tryParse(cost.toString()) ?? 0.0;
                totalShippingCost += costValue * quantity;
              }
            }
          } catch (e) {
            print('Error parsing shipping costs: $e');
          }
        }
      }
    }

    return totalShippingCost;
  }

  // Swipe to pay state
  double _swipePosition = 0.0;
  bool _isPaymentTriggered = false;

  // Group membership
  Map<String, dynamic>? _userGroup;

  // Checkout steps
  int _currentStep = 0; // 0 = product info, 1 = payment method
  final PageController _pageController = PageController();

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadUserAddresses();
    _loadSavedCards();
    _loadProductPaymentDefault();
    _loadProductDetails();
    _initializeItemSelections();
    _loadWeeklyUsage(); // Load current week's payment terms usage
    _loadUserGroup(); // Load group membership for display in checkout
  }

  Future<void> _loadProductPaymentDefault() async {
    if (!mounted) return;

    try {
      final defaults = await ApiService.getPaymentDefaults();
      final defaultProduct = defaults['default_payment_product']?.toString();

      if (defaultProduct == null || defaultProduct.isEmpty) return;

      // Explicit wallet default
      if (defaultProduct == 'wallet') {
        if (!mounted) return;
        setState(() {
          _selectedPaymentMethod = 'wallet';
          _selectedSavedCard = null;
          _selectedSepaMethod = null;
          _selectedAchMethod = null;
          _selectedWireMethod = null;
        });
        return;
      }

      // Legacy type defaults
      const legacyTypes = {
        'card',
        'saved_card',
        'sepa',
        'ach',
        'wire',
        'payment_30_days',
        'payment_60_days',
      };
      if (legacyTypes.contains(defaultProduct)) {
        if (!mounted) return;
        setState(() => _selectedPaymentMethod = defaultProduct);
      }

      // New-style defaults are method IDs from user_payment_methods table
      final methods = await ApiService.getUserPaymentMethods();
      final selected = methods
          .where((m) => m['id']?.toString() == defaultProduct)
          .cast<Map<String, dynamic>>()
          .toList();

      if (selected.isEmpty || !mounted) return;

      final method = selected.first;
      final type = method['type']?.toString();

      setState(() {
        if (type == 'card') {
          _selectedPaymentMethod = 'saved_card';
          _selectedSavedCard = method;
          _selectedSepaMethod = null;
          _selectedAchMethod = null;
          _selectedWireMethod = null;
        } else if (type == 'sepa') {
          _selectedPaymentMethod = 'sepa';
          _selectedSepaMethod = method;
          _selectedSavedCard = null;
          _selectedAchMethod = null;
          _selectedWireMethod = null;
        } else if (type == 'ach') {
          _selectedPaymentMethod = 'ach';
          _selectedAchMethod = method;
          _selectedSavedCard = null;
          _selectedSepaMethod = null;
          _selectedWireMethod = null;
        } else if (type == 'wire') {
          _selectedPaymentMethod = 'wire';
          _selectedWireMethod = method;
          _selectedSavedCard = null;
          _selectedSepaMethod = null;
          _selectedAchMethod = null;
        }
      });
    } catch (e) {
      print('⚠️ Error loading product payment default: $e');
    }
  }

  void _initializeItemSelections() {
    // Initialize address, shipping type, and cleaning requirement for each cart item
    for (int i = 0; i < widget.cartItems.length; i++) {
      _selectedShippingTypePerItem[i] = 'delvioo'; // Default to delvioo
      _selectedAddressPerItem[i] = null; // Will be set when addresses load
      _requiresCleaningPerItem[i] = false; // Default to no cleaning required
    }
  }

  Future<void> _loadUserGroup() async {
    if (!mounted) return;
    try {
      final result = await ApiService.getGroups();
      if (result['success'] == true && mounted) {
        final groups = List<Map<String, dynamic>>.from(
          result['groups'] ?? [],
        );
        setState(() => _userGroup = groups.isNotEmpty ? groups.first : null);
      }
    } catch (e) {
      print('❌ Error loading user group for checkout: $e');
    }
  }

  Future<void> _loadWeeklyUsage() async {
    if (!mounted) return;

    setState(() => _isLoadingWeeklyUsage = true);

    try {
      print('📊 Loading weekly payment terms usage...');
      final response = await ApiService.getMonthlyPaymentTermsUsage(
        widget.accessToken,
      );

      if (response['success'] == true) {
        setState(() {
          _currentWeekUsage = (response['total_usage'] ?? 0.0).toDouble();
        });
        print(
          '✅ Current week usage: \$${_currentWeekUsage.toStringAsFixed(2)}',
        );
      }
    } catch (e) {
      print('❌ Error loading weekly usage: $e');
      // Set to 0 if there's an error
      setState(() => _currentWeekUsage = 0.0);
    } finally {
      if (mounted) {
        setState(() => _isLoadingWeeklyUsage = false);
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _cardNumberController.dispose();
    _expiryController.dispose();
    _cvvController.dispose();
    _nameController.dispose();
    _businessNameController.dispose();
    _businessTaxIdController.dispose();
    _businessStreetController.dispose();
    _businessHouseNumberController.dispose();
    _businessPostalCodeController.dispose();
    _businessCityController.dispose();
    _businessCountryController.dispose();
    _businessPhoneController.dispose();
    _businessEmailController.dispose();
    _businessDunsController.dispose();
    super.dispose();
  }

  void _loadUserData() {
    if (widget.currentUser != null) {
      _nameController.text =
          widget.currentUser!['name']?.toString().trim() ?? '';
    }
  }

  Future<void> _removePurchasedItemsFromCart() async {
    final processedKeys = <String>{};

    for (final item in widget.cartItems) {
      final rawProductId = item['productId'] ?? item['id'];
      final productId = rawProductId is int
          ? rawProductId
          : int.tryParse(rawProductId?.toString().replaceAll(RegExp(r'[^0-9]'), '') ?? '');

      if (productId == null) continue;

      final rawVariant = item['variantIdx'];
      final variantIdx = rawVariant is int
          ? rawVariant
          : int.tryParse(rawVariant?.toString() ?? '') ?? 0;

      final itemKey = '$productId:$variantIdx';
      if (!processedKeys.add(itemKey)) continue;

      try {
        await ApiService.removeFromCart(productId, variantIdx: variantIdx);
      } catch (e) {
        print('⚠️ Failed to remove cart item $itemKey after checkout: $e');
      }
    }
  }

  Future<void> _loadProductDetails() async {
    setState(() => _isLoadingProducts = true);

    try {
      print('📦 Loading product details for checkout...');
      for (var item in widget.cartItems) {
        final rawId = item['productId'];
        // productId may arrive as int, String, or BigInt-string like "2n" → always parse to int
        final productId = rawId is int
            ? rawId
            : int.tryParse(rawId.toString().replaceAll(RegExp(r'[^0-9]'), ''));
        if (productId != null && !_productDetails.containsKey(productId.toString())) {
          try {
            final productResponse = await ApiService.getProduct(productId);
            if (productResponse['success'] == true) {
              _productDetails[productId.toString()] = productResponse['product'];
              print('✅ Loaded product $productId with shipping data');
            }
          } catch (e) {
            print('❌ Error loading product $productId: $e');
          }
        }
      }
    } catch (e) {
      print('❌ Error loading product details: $e');
    } finally {
      setState(() => _isLoadingProducts = false);
    }
  }

  // Format currency according to number format preference
  String _formatCurrency(double amount) {
    setNumberFormatStyleIndex(widget.numberFormat == 'de' ? 1 : 0);
    return formatCurrencyUsd(amount);
  }

  /// Converts a full country name (as stored in the controller) to a 2-letter
  /// ISO country code expected by the backend. Falls back to 'US'.
  static String _countryNameToCode(String name) {
    const map = {
      'United States': 'US', 'Germany': 'DE', 'United Kingdom': 'GB',
      'France': 'FR', 'Spain': 'ES', 'Italy': 'IT', 'Netherlands': 'NL',
      'Belgium': 'BE', 'Austria': 'AT', 'Switzerland': 'CH', 'Poland': 'PL',
      'Sweden': 'SE', 'Norway': 'NO', 'Denmark': 'DK', 'Finland': 'FI',
      'Canada': 'CA', 'Australia': 'AU', 'New Zealand': 'NZ',
      'Japan': 'JP', 'Singapore': 'SG',
    };
    return map[name] ?? (name.length == 2 ? name.toUpperCase() : 'US');
  }

  Future<void> _loadUserAddresses() async {
    setState(() => _isLoadingAddresses = true);

    try {
      print('🏠 Loading user addresses...');
      final addresses = await ApiService.getUserAddresses();
      print('📍 Received ${addresses.length} addresses: $addresses');

      setState(() {
        _userAddresses = addresses;
        if (addresses.isNotEmpty) {
          // Find the default address (isSelected: 1) first
          final defaultAddress = addresses.firstWhere(
            (addr) => addr['isSelected'] == 1,
            orElse: () => addresses.first,
          );

          // Set default address for all items
          for (int i = 0; i < widget.cartItems.length; i++) {
            _selectedAddressPerItem[i] = defaultAddress;
          }
          print(
            '✅ Set default address for ${widget.cartItems.length} items: ${defaultAddress['address']}',
          );
        }
      });
    } catch (e, stackTrace) {
      print('❌ Error loading addresses: $e');
      print('Stack trace: $stackTrace');
      setState(() => _userAddresses = []);
    } finally {
      setState(() => _isLoadingAddresses = false);
    }
  }

  // Format address display in correct order: Street, City, ZIP, Country
  String _formatAddressDisplay(Map<String, dynamic> address) {
    final fullAddress = address['address']?.toString() ?? '';
    final country = address['country']?.toString() ?? '';

    // If address is already formatted (contains comma), parse and reorder
    if (fullAddress.contains(',')) {
      final parts = fullAddress.split(',').map((e) => e.trim()).toList();

      // Check if first part is country name (like "Germany")
      if (parts.isNotEmpty &&
          parts[0].length > 2 &&
          country.isNotEmpty &&
          parts[0].toLowerCase().contains(
            country.toLowerCase().substring(0, 3),
          )) {
        // Remove country from beginning and add to end
        final withoutCountry = parts.sublist(1);
        return '${withoutCountry.join(', ')}, $country';
      }
    }

    // If no parsing needed, return as is (with country at end if available)
    if (country.isNotEmpty &&
        !fullAddress.toLowerCase().contains(country.toLowerCase())) {
      return '$fullAddress, $country';
    }

    return fullAddress.isNotEmpty
        ? fullAddress
        : AppLocalizations.of(context)!.noAddressProvided;
  }

  Future<void> _loadSavedCards() async {
    setState(() => _isLoadingSavedCards = true);

    try {
      print('💳 Loading saved Stripe cards...');
      final savedCards = await ApiService.getSavedCards(widget.accessToken);
      print('✅ Loaded ${savedCards.length} saved cards: $savedCards');

      setState(() {
        _savedCards = savedCards;
        if (savedCards.isNotEmpty && _selectedSavedCard == null) {
          // Select default card or first card
          _selectedSavedCard = savedCards.firstWhere(
            (card) => card['is_default'] == true,
            orElse: () => savedCards.first,
          );
          // Only keep saved_card as method if we actually have one
          if (_selectedPaymentMethod == 'saved_card') {
            _selectedPaymentMethod = 'saved_card';
          }
        } else if (savedCards.isEmpty && _selectedPaymentMethod == 'saved_card') {
          // No saved cards – fall back to entering a new card
          _selectedPaymentMethod = 'card';
        }
      });
    } catch (e) {
      print('❌ Error loading saved cards: $e');
      setState(() {
        _savedCards = [];
        if (_selectedPaymentMethod == 'saved_card') {
          _selectedPaymentMethod = 'card';
        }
      });
    } finally {
      setState(() => _isLoadingSavedCards = false);
    }
  }

  // Show saved payment methods selection sheet
  void _showSavedPaymentMethodsSheet() async {
    try {
      // Load all saved payment methods
      final methods = await ApiService.getUserPaymentMethods();

      if (!mounted) return;

      if (methods.isEmpty) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)!.noSavedPaymentMethods,
        );
        return;
      }

      TradeRepublicBottomSheet.show(
        context: context,
        showDragHandle: true,
        maxHeight: MediaQuery.of(context).size.height * 0.75,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TradeRepublicSectionHeader(
                title: AppLocalizations.of(context)!.savedPaymentMethods1,
                subtitle: AppLocalizations.of(context)!.chooseHowYouWantToPay,
                leading: const Icon(CupertinoIcons.creditcard_fill, size: 20),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  itemCount: methods.length,
                  itemBuilder: (sheetContext, index) {
                    final method = methods[index];
                    return _buildSavedMethodOption(method, sheetContext);
                  },
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)!.errorLoadingPaymentMethods,
        );
      }
    }
  }

  // Build saved payment method option
  Widget _buildSavedMethodOption(Map<String, dynamic> method, BuildContext sheetContext) {
    final type = method['type'] ?? '';

    IconData icon;
    String title;
    String subtitle;
    Color iconColor;

    switch (type) {
      case 'card':
        icon = CupertinoIcons.creditcard_fill;
        // /payment-methods returns nested card object; /saved-cards returns flat fields
        final cardData = method['card'] as Map<String, dynamic>?;
        final brand = (cardData?['brand'] ?? method['brand'] ?? method['card_brand'] ?? 'card').toString().toUpperCase();
        final last4 = (cardData?['last4'] ?? method['last4'] ?? method['card_last4'] ?? '****').toString();
        final expMonth = (cardData?['exp_month'] ?? method['exp_month'] ?? method['card_exp_month'] ?? '--').toString();
        final expYear = (cardData?['exp_year'] ?? method['exp_year'] ?? method['card_exp_year'] ?? '--').toString();
        title = '$brand \u2022\u2022\u2022\u2022 $last4';
        subtitle = 'Expires $expMonth/$expYear';
        iconColor = Colors.blue.shade400;
        break;
      case 'sepa':
        icon = CupertinoIcons.building_2_fill;
        title = AppLocalizations.of(
          context,
        )!.sepaEndingIn(method['iban_last4'].toString());
        subtitle = method['account_holder_name'] ?? '';
        iconColor = Colors.purple.shade400;
        break;
      case 'ach':
        icon = CupertinoIcons.creditcard_fill;
        title = AppLocalizations.of(
          context,
        )!.achEndingIn(method['account_number_last4'].toString());
        subtitle = method['account_holder_name'] ?? '';
        iconColor = Colors.teal.shade400;
        break;
      case 'wire':
        icon = CupertinoIcons.arrow_right_arrow_left;
        title = AppLocalizations.of(
          context,
        )!.wireEndingIn(method['account_number_last4'].toString());
        subtitle = method['account_holder_name'] ?? '';
        iconColor = Colors.red.shade400;
        break;
      default:
        icon = CupertinoIcons.creditcard;
        title = AppLocalizations.of(context)!.paymentMethod;
        subtitle = '';
        iconColor = Colors.grey.shade400;
    }

    return TradeRepublicListTile.navigation(
      title: title,
      subtitle: subtitle.isNotEmpty ? subtitle : null,
      leading: Icon(icon, color: iconColor, size: 20),
      onTap: () {
        Navigator.pop(sheetContext);
        // Handle selection based on type
        setState(() {
          if (type == 'sepa') {
            _selectedPaymentMethod = 'sepa';
            _selectedSepaMethod = method;
            _selectedSavedCard = null;
            _selectedAchMethod = null;
            _selectedWireMethod = null;
          } else if (type == 'ach') {
            _selectedPaymentMethod = 'ach';
            _selectedAchMethod = method;
            _selectedSavedCard = null;
            _selectedSepaMethod = null;
            _selectedWireMethod = null;
          } else if (type == 'wire') {
            _selectedPaymentMethod = 'wire';
            _selectedWireMethod = method;
            _selectedSavedCard = null;
            _selectedSepaMethod = null;
            _selectedAchMethod = null;
          } else if (type == 'card') {
            _selectedPaymentMethod = 'saved_card';
            _selectedSavedCard = method;
            _selectedSepaMethod = null;
            _selectedAchMethod = null;
            _selectedWireMethod = null;
          }
        });
        TopNotification.success(
          context,
          AppLocalizations.of(context)!.paymentMethodSelected(title),
        );
      },
    );
  }

  /// Check if user is in a group that requires purchase approval
  /// Returns true if approval is required and request was sent
  Future<bool> _checkGroupApprovalRequired() async {
    try {
      // Get user's groups
      final groupsResult = await ApiService.getGroups();
      if (groupsResult['success'] != true) return false;

      final groups = groupsResult['groups'] as List? ?? [];

      // Find groups where user requires approval
      for (final group in groups) {
        if (group['i_require_approval'] == 1 ||
            group['i_require_approval'] == true) {
          // User needs approval in this group
          final totalWithShipping = widget.totalPrice + _shippingCost;

          // Show approval request dialog
          final sendRequest = await _showApprovalRequiredDialog(
            group,
            totalWithShipping,
          );

          if (sendRequest == true) {
            // Create full orders with status "approval_requested"
            // This saves all details (name, price, quantity, address) in the orders table
            try {
              final createdOrderIds = <String>[];

              // Create an order for each cart item
              for (int i = 0; i < widget.cartItems.length; i++) {
                final item = widget.cartItems[i];
                final address = _selectedAddressPerItem[i];
                final shippingType =
                    _selectedShippingTypePerItem[i] ?? 'delvioo';

                if (address == null) {
                  throw Exception(
                    'Please select delivery address for all items',
                  );
                }

                // Calculate item details
                final productId = item['productId'];
                final quantityRaw = item['quantity'] ?? 1;
                final quantity = _parseCartQuantity(quantityRaw);
                final product = _productDetails[productId?.toString() ?? ''];

                // Get item price
                double itemPrice = 0.0;
                final priceRaw = item['price'];
                if (priceRaw is String) {
                  itemPrice = double.tryParse(priceRaw) ?? 0.0;
                } else if (priceRaw is num) {
                  itemPrice = priceRaw.toDouble();
                }

                // Get product details
                final productName =
                    item['name'] ?? product?['name'] ?? AppLocalizations.of(context)!.unknownProduct;
                final productUnit = item['unit'] ?? product?['unit'] ?? 'kg';
                final sellerUsername =
                    item['seller_username'] ??
                    item['seller'] ??
                    product?['username'];

                // Calculate shipping cost for this item
                double itemShippingCost = 0.0;
                if (product != null) {
                  if (shippingType == 'delvioo') {
                    itemShippingCost = product['delvioo_shipping_cost'] is num
                        ? (product['delvioo_shipping_cost'] as num).toDouble()
                        : double.tryParse(
                                product['delvioo_shipping_cost']?.toString() ??
                                    '0',
                              ) ??
                              0.0;
                  } else if (shippingType == 'standard') {
                    itemShippingCost = product['standard_shipping_cost'] is num
                        ? (product['standard_shipping_cost'] as num).toDouble()
                        : double.tryParse(
                                product['standard_shipping_cost']?.toString() ??
                                    '0',
                              ) ??
                              0.0;
                  }
                }

                // Calculate totals
                final itemSubtotal = itemPrice * quantity;
                final itemTotal = itemSubtotal + itemShippingCost;

                // Prepare order data - will be stored in orders table
                final orderData = {
                  'items': [
                    {
                      'id': productId,
                      'name': productName,
                      'quantity': quantity, // Store as decimal (e.g., 455.55)
                      'price': itemPrice,
                      'unit': productUnit,
                      'seller_username': sellerUsername,
                      'variantIdx': item['variantIdx'] ?? 0,
                    },
                  ],
                  'shippingAddress': address,
                  'totalAmount': itemTotal,
                  'productSubtotal': itemSubtotal,
                  'shippingCost': itemShippingCost,
                  'shippingType': shippingType,
                  'commission': 0.0,
                  'sellerAmount': itemSubtotal,
                  'status':
                      'approval_requested', // Special status for pending approval
                  'paymentIntentId':
                      null, // No payment yet - waiting for approval
                  'payment_method_type':
                      'approval_request', // Special type to bypass payment intent ID requirement
                  'delvioo': shippingType == 'delvioo' ? 1 : 0,
                  'groupId': group['id'], // Link to group for approval tracking
                };

                // Create order in database
                print('📦 Creating approval order for item $i: $productName');
                final orderResponse = await ApiService.createOrder(
                  orderData,
                  widget.accessToken,
                );

                if (orderResponse['success'] == true) {
                  final orderId =
                      orderResponse['order']?['id']?.toString() ??
                      orderResponse['orderId']?.toString() ??
                      '';
                  if (orderId.isNotEmpty) {
                    createdOrderIds.add(orderId);
                    print('✅ Order created: #$orderId');
                  }
                }
              }

              // Now send approval request with the created order IDs
              final items = widget.cartItems
                  .map(
                    (item) => {
                      'product_id': item['productId'],
                      'product_name':
                          item['name'] ?? item['productName'] ?? 'Unknown',
                      'quantity': item['quantity'] ?? 1,
                      'price': item['price'],
                      'seller_username':
                          item['seller_username'] ?? item['seller'],
                    },
                  )
                  .toList();

              Map<String, dynamic>? shippingAddress;
              if (_selectedAddressPerItem.isNotEmpty) {
                shippingAddress = _selectedAddressPerItem.values.first;
              }

              final result = await ApiService.requestPurchaseApproval(
                group['id'],
                cartItems: items,
                totalAmount: totalWithShipping,
                shippingCost: _shippingCost,
                shippingAddress: shippingAddress,
              );

              if (result['success'] == true) {
                if (mounted) {
                  await _removePurchasedItemsFromCart();
                  TopNotification.success(
                    context,
                    AppLocalizations.of(context)!.approvalRequestSent,
                  );
                  widget.onOrderComplete(); // Refresh orders list
                  Navigator.pop(context); // Close checkout modal
                }
                return true;
              } else {
                if (mounted) {
                  TopNotification.error(
                    context,
                    result['message'] ?? AppLocalizations.of(context)!.errorSendingRequest,
                  );
                }
              }
            } catch (e) {
              print('❌ Error creating approval orders: $e');
              if (mounted) {
                TopNotification.error(
                  context,
                  AppLocalizations.of(context)!.errorSavingOrder(e.toString()),
                );
              }
            }
          } else {
            // User cancelled the approval dialog - abort the order
            if (mounted) {
              Navigator.pop(context); // Close checkout modal
            }
            return true; // Return true to indicate approval was required and order should be cancelled
          }
          return true;
        }
      }

      return false; // No approval required
    } catch (e) {
      print('❌ Error checking group approval: $e');
      return false;
    }
  }

  Future<bool?> _showApprovalRequiredDialog(
    Map<String, dynamic> group,
    double totalAmount,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return TradeRepublicBottomSheet.show<bool>(
      context: context,
      showDragHandle: true,
      isDismissible: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icon with gradient background
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF9500), Color(0xFFFF6B00)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(25),
            ),
            child: const Icon(
              CupertinoIcons.checkmark_seal_fill,
              color: Colors.white,
              size: 32,
            ),
          ),

          const SizedBox(height: 24),

          // Title
          Text(
            AppLocalizations.of(context)!.approvalRequired,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : const Color(0xFF1a1a1a),
              letterSpacing: -0.5,
            ),
          ),

          const SizedBox(height: 12),

          // Description
          Text(
            'As a member of "${group['name']}", you need approval from the group owner for this purchase.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: (isDark ? Colors.white : Colors.black).withOpacity(0.6),
              height: 1.5,
            ),
          ),

          const SizedBox(height: 28),

          // Order details card with modern glassmorphism
          Container(
            padding: const EdgeInsets.all(25),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [
                        Colors.white.withOpacity(0.05),
                        Colors.white.withOpacity(0.02),
                      ]
                    : [const Color(0xFFF5F6FA), Colors.white],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(25),

              border: Border.all(
                color: isDark
                    ? Colors.white.withOpacity(0.08)
                    : Colors.black.withOpacity(0.04),
                width: 1,
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(25),
                          ),
                          child: const Icon(
                            CupertinoIcons.bag,
                            color: Colors.blue,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppLocalizations.of(context)!.orderValue,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: (isDark ? Colors.white : Colors.black)
                                    .withOpacity(0.5),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '\$${totalAmount.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF1a1a1a),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(25),
                      ),
                      child: Text(
                        '${widget.cartItems.length} ${widget.cartItems.length == 1 ? "item" : "items"}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.blue,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Modern action buttons
          Row(
            children: [
              Expanded(
                child: TradeRepublicButton(
                  label: AppLocalizations.of(context)!.cancel,
                  onPressed: () => Navigator.pop(context, false),
                  isSecondary: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: TradeRepublicButton(
                  label: AppLocalizations.of(context)!.sendRequest,
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(CupertinoIcons.paperplane_fill),
                  backgroundColor: const Color(0xFFFF9500),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _processPayment() async {
    // Check if user needs group approval before purchase
    final approvalRequired = await _checkGroupApprovalRequired();
    if (approvalRequired) {
      return; // Approval request was sent, don't proceed with payment
    }

    // Check if all items have addresses selected
    for (int i = 0; i < widget.cartItems.length; i++) {
      if (_selectedAddressPerItem[i] == null) {
        if (mounted) {
          TopNotification.error(
            context,
            AppLocalizations.of(context)!.selectDeliveryAddress,
          );
        }
        return;
      }
    }

    if (_selectedPaymentMethod == 'card' &&
        (_cardNumberController.text.isEmpty ||
            _expiryController.text.isEmpty ||
            _cvvController.text.isEmpty ||
            _nameController.text.isEmpty)) {
      TopNotification.error(
        context,
        AppLocalizations.of(context)!.fillAllPaymentFields,
      );
      return;
    }

    if (_selectedPaymentMethod == 'saved_card' && _selectedSavedCard == null) {
      if (_savedCards.isEmpty) {
        // No saved cards at all – silently treat as new card entry
        _selectedPaymentMethod = 'card';
      } else {
        TopNotification.error(
          context,
          AppLocalizations.of(context)!.pleaseSelectASavedCard,
        );
        return;
      }
    }

    if (_selectedPaymentMethod == 'sepa' && _selectedSepaMethod == null) {
      TopNotification.error(
        context,
        AppLocalizations.of(context)!.pleaseSelectASepaPaymentMethod,
      );
      return;
    }

    if (_selectedPaymentMethod == 'ach' && _selectedAchMethod == null) {
      TopNotification.error(
        context,
        AppLocalizations.of(context)!.pleaseSelectAnAchPaymentMethod,
      );
      return;
    }

    if (_selectedPaymentMethod == 'wire' && _selectedWireMethod == null) {
      TopNotification.error(
        context,
        AppLocalizations.of(context)!.pleaseSelectAWireTransferMethod,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. Calculate total amount for Stripe payment
      final totalWithShipping = widget.totalPrice + _shippingCost;
      final commissionRate = 0.0; // Commission handled later

      print('💰 Payment calculation:');
      print('  - Total amount: \$${totalWithShipping.toStringAsFixed(2)}');

      // 2. Handle Monioo Wallet payment
      if (_selectedPaymentMethod == 'wallet') {
        await _processMoniooWalletPayment(totalWithShipping, commissionRate);
        return;
      }

      // 2. Handle Google Pay / Apple Pay through Stripe Payment Sheet
      if (_selectedPaymentMethod == 'google_pay' ||
          _selectedPaymentMethod == 'apple_pay') {
        await _processWalletPayment(totalWithShipping, commissionRate);
        return;
      }

      // 3. Prepare payment data for card payments
      final paymentData = _selectedPaymentMethod == 'card'
          ? {
              'type': 'new_card',
              'card_number': _cardNumberController.text,
              'expiry_date': _expiryController.text,
              'cvv': _cvvController.text,
              'cardholder_name': _nameController.text,
            }
          : _selectedPaymentMethod == 'saved_card'
          ? {
              'type': 'saved_card',
              'saved_card_id': _selectedSavedCard!['id'],
              'last4': _selectedSavedCard!['last4'],
              'brand': _selectedSavedCard!['brand'],
            }
          : _selectedPaymentMethod == 'sepa'
          ? {
              'type': 'sepa',
              'payment_method_id': _selectedSepaMethod!['id'],
              'iban_last4': _selectedSepaMethod!['iban_last4'],
              'account_holder_name':
                  _selectedSepaMethod!['account_holder_name'],
            }
          : _selectedPaymentMethod == 'ach'
          ? {
              'type': 'ach',
              'payment_method_id': _selectedAchMethod!['id'],
              'account_number_last4':
                  _selectedAchMethod!['account_number_last4'],
              'account_holder_name': _selectedAchMethod!['account_holder_name'],
            }
          : _selectedPaymentMethod == 'wire'
          ? {
              'type': 'wire',
              'payment_method_id': _selectedWireMethod!['id'],
              'account_number_last4':
                  _selectedWireMethod!['account_number_last4'],
              'account_holder_name':
                  _selectedWireMethod!['account_holder_name'],
            }
          : _selectedPaymentMethod == 'stripe'
          ? {'type': 'stripe'}
          : null;

      // 4. Continue with standard payment flow
      await _completePayment(totalWithShipping, commissionRate, paymentData);
    } catch (e) {
      print('❌ Payment error: $e');
      if (mounted) {
        TopNotification.error(context, 'Payment failed: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _swipePosition = 0.0;
          _isPaymentTriggered = false;
        });
      }
    }
  }

  Future<void> _processMoniooWalletPayment(
    double totalAmount,
    double commissionRate,
  ) async {
    final walletResult = await ApiService.payFromWallet(
      amount: totalAmount,
      description: 'Cultioo checkout payment',
      referenceType: 'order_checkout',
    );

    if (walletResult['success'] != true) {
      throw Exception(
        walletResult['message'] ?? walletResult['error'] ?? 'Wallet payment failed',
      );
    }

    final paymentRef =
        'wallet_${DateTime.now().millisecondsSinceEpoch.toString()}';
    await _completeOrderCreation(totalAmount, commissionRate, paymentRef);
  }

  // Process card payment from bottom sheet (without auto-closing modal)
  Future<void> _processCardPaymentInSheet() async {
    // Check if user needs group approval before purchase
    final approvalRequired = await _checkGroupApprovalRequired();
    if (approvalRequired) {
      // The approval dialog already handled everything (sent request or closed modal)
      // Just return without throwing an exception
      return;
    }

    // Check if all items have addresses selected
    for (int i = 0; i < widget.cartItems.length; i++) {
      if (_selectedAddressPerItem[i] == null) {
        throw Exception('Please select a delivery address for all items');
      }
    }

    // Validate card fields
    if (_cardNumberController.text.isEmpty ||
        _expiryController.text.isEmpty ||
        _cvvController.text.isEmpty ||
        _nameController.text.isEmpty) {
      throw Exception('Please fill in all payment fields');
    }

    setState(() => _isLoading = true);

    try {
      // 1. Calculate total amount for Stripe payment
      final totalWithShipping = widget.totalPrice + _shippingCost;
      final commissionRate = 0.0; // Commission handled later

      print('💰 Card Payment calculation:');
      print('  - Total amount: \$${totalWithShipping.toStringAsFixed(2)}');

      // 2. Prepare payment data for card payment
      final paymentData = {
        'type': 'new_card',
        'card_number': _cardNumberController.text,
        'expiry_date': _expiryController.text,
        'cvv': _cvvController.text,
        'cardholder_name': _nameController.text,
      };

      // 3. Create Stripe Payment Intent
      final paymentResponse = await ApiService.createStripePayment({
        'amount': totalWithShipping,
        'currency': 'eur',
        'payment_method': 'card',
        'payment_data': paymentData,
        'customer_email': widget.currentUser?['email'] ?? 'unknown@example.com',
        'description': 'Cultioo Order - ${widget.cartItems.length} items',
        'metadata': {
          'order_items_count': widget.cartItems.length.toString(),
          'shipping_cost': _shippingCost.toString(),
          'commission_rate': commissionRate.toString(),
        },
      }, widget.accessToken);

      print(
        '✅ Stripe Payment Intent created: ${paymentResponse['payment_intent_id']}',
      );

      // 4. Create orders without closing the modal
      await _createOrdersWithoutClosing(
        totalWithShipping,
        commissionRate,
        paymentResponse['payment_intent_id'],
      );

      print('✅ All orders created successfully!');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _swipePosition = 0.0;
          _isPaymentTriggered = false;
        });
      }
    }
  }

  // Create orders without auto-closing modal (for card payment sheet)
  Future<void> _createOrdersWithoutClosing(
    double totalAmount,
    double commissionRate,
    String paymentIntentId,
  ) async {
    List<String> createdOrderIds = [];

    // Generate a split group ID if there are multiple items (order will be split)
    final isSplitOrder = widget.cartItems.length > 1;
    String? firstOrderId; // Track first order ID for parent_order_id

    for (int i = 0; i < widget.cartItems.length; i++) {
      final item = widget.cartItems[i];
      final address = _selectedAddressPerItem[i];
      final shippingType = _selectedShippingTypePerItem[i] ?? 'delvioo';

      if (address == null) {
        throw Exception('Missing address for item ${i + 1}');
      }

      // Calculate costs for this specific item
      final productId = item['productId'];
      final quantityRaw = item['quantity'] ?? 1;
        final quantity = _parseCartQuantity(quantityRaw);
      final product = _productDetails[productId?.toString() ?? ''];

      // Get item price (considering variant)
      double itemPrice = 0.0;
      final priceRaw = item['price'];
      itemPrice = (priceRaw is String)
          ? double.tryParse(priceRaw) ?? 0.0
          : (priceRaw is int)
          ? priceRaw.toDouble()
          : (priceRaw as double? ?? 0.0);

      final variantIdx = item['variantIdx'];
      if (product != null && variantIdx != null) {
        final variants = product['variants'] as List<dynamic>?;
        if (variants != null && variantIdx < variants.length) {
          final variant = variants[variantIdx];
          final variantPriceRaw = variant['price'];
          itemPrice = (variantPriceRaw is String)
              ? double.tryParse(variantPriceRaw) ?? 0.0
              : (variantPriceRaw is int)
              ? variantPriceRaw.toDouble()
              : (variantPriceRaw as double? ?? 0.0);
        }
      }

      final productSubtotal = itemPrice * quantity;

      // Calculate shipping cost for this item
      double itemShippingCost = 0.0;
      if (product != null) {
        final shippingCostsRaw = product['shippingCosts'];
        if (shippingCostsRaw != null) {
          try {
            String shippingCostsStr = shippingCostsRaw.toString();
            if (shippingCostsStr.startsWith('{')) {
              Map<String, dynamic> costs = json.decode(shippingCostsStr);
              if (costs.containsKey(shippingType)) {
                final cost = costs[shippingType];
                itemShippingCost = (cost is int)
                    ? cost.toDouble()
                    : double.tryParse(cost.toString()) ?? 0.0;
                itemShippingCost *= quantity;
              }
            }
          } catch (e) {
            print('Error parsing shipping costs for item $i: $e');
          }
        }
      }

      final itemTotal = productSubtotal + itemShippingCost;
      final platformCommission = (itemTotal * commissionRate) / 100;
      final sellerAmount = itemTotal - platformCommission;

      // Create order data for this single item
      final orderData = {
        'paymentIntentId': paymentIntentId,
        'totalAmount': itemTotal,
        'items': [
          {
            'id': productId ?? item['id'],
            'productId': productId,
            'name': item['name'],
            'price': itemPrice,
            'quantity': quantity,
            'seller': item['seller'] ?? 'Unknown Seller',
            'category': item['category'] ?? 'General',
            'variantIdx': variantIdx,
          },
        ],
        'shippingAddress': address,
        'paymentMethodId': null,
        'status': 'confirmed',
        'payment_status': 'paid', // Mark as paid for card payments
        'shipping_cost': itemShippingCost,
        'subtotal': productSubtotal,
        'commission_rate': commissionRate,
        'platform_commission': platformCommission,
        'seller_amount': sellerAmount,
        'payment_method_type': 'card',
        'shipping_type': shippingType,
        'requires_cleaning_certificate': _requiresCleaningPerItem[i] == true
            ? 1
            : 0,
        'cleaning_certificate_fee':
            (_requiresCleaningPerItem[i] == true && product != null)
            ? (product['cleaning_certificate_fee'] ?? 0.0)
            : 0.0,
        if (_businessInfo != null) 'business_info': _businessInfo,
        if (isSplitOrder) 'split_order': 1,
        if (isSplitOrder) 'split_order_part': i + 1,
        if (isSplitOrder && firstOrderId != null) 'parent_order_id': int.tryParse(firstOrderId),
      };

      print('📦 Creating order ${i + 1}/${widget.cartItems.length}...');
      final orderResponse = await ApiService.createOrder(
        orderData,
        widget.accessToken,
      );

      final orderId = orderResponse['orderId'];
      if (i == 0) firstOrderId = orderId; // remember first order ID
      createdOrderIds.add(orderId);
      print('✅ Order $orderId created for item: ${item['name']}');

      // Send push notification for order success
      await ApiService.sendOrderNotification(
        accessToken: widget.accessToken,
        productName: item['name'] ?? 'Product',
        totalAmount: itemTotal,
        orderId: orderId,
      );
    }

    // Store order IDs for the success page
    _createdOrderIds = createdOrderIds;
    _totalPaidAmount = totalAmount;
  }

  // Process Google Pay / Apple Pay via Stripe Payment Sheet
  Future<void> _processWalletPayment(
    double totalAmount,
    double commissionRate,
  ) async {
    try {
      print(
        '💳 Processing ${_selectedPaymentMethod == 'google_pay' ? 'Google' : 'Apple'} Pay...',
      );

      // Create Payment Intent
      final paymentResponse = await ApiService.createStripePayment({
        'amount': totalAmount,
        'currency': 'usd',
        'payment_method': _selectedPaymentMethod,
        'payment_data': {'type': _selectedPaymentMethod},
        'customer_email': widget.currentUser?['email'] ?? 'unknown@example.com',
        'description': 'Cultioo Order - ${widget.cartItems.length} items',
        'metadata': {
          'order_items_count': widget.cartItems.length.toString(),
          'shipping_cost': _shippingCost.toString(),
          'commission_rate': commissionRate.toString(),
        },
      }, widget.accessToken);

      print(
        '✅ Payment Intent created: ${paymentResponse['payment_intent_id']}',
      );

      final clientSecret = paymentResponse['client_secret'];

      if (clientSecret == null) {
        throw Exception('Client secret not received from server');
      }

      // Initialize Stripe Payment Sheet with wallet support
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'Cultioo',
          googlePay: _selectedPaymentMethod == 'google_pay'
              ? PaymentSheetGooglePay(
                  merchantCountryCode: 'US',
                  currencyCode: 'USD',
                  testEnv: true, // Set to false in production
                )
              : null,
          applePay: _selectedPaymentMethod == 'apple_pay'
              ? PaymentSheetApplePay(merchantCountryCode: 'US')
              : null,
        ),
      );

      // Present Payment Sheet
      await Stripe.instance.presentPaymentSheet();

      print(
        '✅ ${_selectedPaymentMethod == 'google_pay' ? 'Google' : 'Apple'} Pay payment successful!',
      );

      // Complete order creation after successful payment
      await _completeOrderCreation(
        totalAmount,
        commissionRate,
        paymentResponse['payment_intent_id'],
      );
    } on StripeException catch (e) {
      print('❌ Stripe error: ${e.error.localizedMessage}');
      if (mounted) {
        TopNotification.error(
          context,
          AppLocalizations.of(
            context,
          )!.paymentCancelledOrFailed(e.error.localizedMessage ?? ''),
        );
      }
      rethrow;
    } catch (e) {
      print('❌ Wallet payment error: $e');
      rethrow;
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _swipePosition = 0.0;
          _isPaymentTriggered = false;
        });
      }
    }
  }

  // Complete standard payment (card, saved_card, stripe)
  Future<void> _completePayment(
    double totalAmount,
    double commissionRate,
    Map<String, dynamic>? paymentData,
  ) async {
    // Create Stripe Payment Intent for total amount
    final paymentResponse = await ApiService.createStripePayment({
      'amount': totalAmount,
      'currency': 'usd',
      'payment_method': _selectedPaymentMethod,
      'payment_data': paymentData,
      'customer_email': widget.currentUser?['email'] ?? 'unknown@example.com',
      'description': 'Cultioo Order - ${widget.cartItems.length} items',
      'metadata': {
        'order_items_count': widget.cartItems.length.toString(),
        'shipping_cost': _shippingCost.toString(),
        'commission_rate': commissionRate.toString(),
      },
    }, widget.accessToken);

    print(
      '✅ Stripe Payment Intent created: ${paymentResponse['payment_intent_id']}',
    );

    // Complete order creation
    await _completeOrderCreation(
      totalAmount,
      commissionRate,
      paymentResponse['payment_intent_id'],
    );
  }

  // Create SEPA order with "waiting" status
  Future<void> _createSepaOrder(
    String virtualIban,
    String accountHolder,
    String customerIban,
  ) async {
    setState(() => _isLoading = true);

    try {
      final totalWithShipping = widget.totalPrice + _shippingCost;
      final commissionRate = 0.0; // Commission handled later

      print('💰 SEPA Order creation:');
      print('  - Total amount: \$${totalWithShipping.toStringAsFixed(2)}');
      print('  - Virtual IBAN: $virtualIban');
      print('  - Account holder: $accountHolder');

      final transferDueAt = DateTime.now().add(const Duration(hours: 48));
      List<String> createdOrderIds = [];

      for (int i = 0; i < widget.cartItems.length; i++) {
        final item = widget.cartItems[i];
        final address = _selectedAddressPerItem[i];
        final shippingType = _selectedShippingTypePerItem[i] ?? 'delvioo';

        if (address == null) {
          throw Exception('Missing address for item ${i + 1}');
        }

        // Calculate costs for this specific item
        final productId = item['productId'];
        final quantityRaw = item['quantity'] ?? 1;
        print('🔢 Quantity conversion:');
        print('  - quantityRaw: $quantityRaw (${quantityRaw.runtimeType})');
        final quantity = _parseCartQuantity(quantityRaw);
        print('  - quantity after conversion: $quantity');
        final product = _productDetails[productId?.toString() ?? ''];

        // Get item price (considering variant)
        double itemPrice = 0.0;
        final priceRaw = item['price'];
        itemPrice = (priceRaw is String)
            ? double.tryParse(priceRaw) ?? 0.0
            : (priceRaw is int)
            ? priceRaw.toDouble()
            : (priceRaw as double? ?? 0.0);

        final variantIdx = item['variantIdx'];
        if (product != null && variantIdx != null) {
          final variants = product['variants'] as List<dynamic>?;
          if (variants != null && variantIdx < variants.length) {
            final variant = variants[variantIdx];
            final variantPriceRaw = variant['price'];
            itemPrice = (variantPriceRaw is String)
                ? double.tryParse(variantPriceRaw) ?? 0.0
                : (variantPriceRaw is int)
                ? variantPriceRaw.toDouble()
                : (variantPriceRaw as double? ?? 0.0);
          }
        }

        final productSubtotal = itemPrice * quantity;

        // Calculate shipping cost for this item
        double itemShippingCost = 0.0;
        if (product != null) {
          final shippingCostsRaw = product['shippingCosts'];
          if (shippingCostsRaw != null) {
            try {
              String shippingCostsStr = shippingCostsRaw.toString();
              if (shippingCostsStr.startsWith('{')) {
                Map<String, dynamic> costs = json.decode(shippingCostsStr);
                if (costs.containsKey(shippingType)) {
                  final cost = costs[shippingType];
                  itemShippingCost = (cost is int)
                      ? cost.toDouble()
                      : double.tryParse(cost.toString()) ?? 0.0;
                  itemShippingCost *= quantity;
                }
              }
            } catch (e) {
              print('Error parsing shipping costs for item $i: $e');
            }
          }
        }

        final itemTotal = productSubtotal + itemShippingCost;
        final platformCommission = (itemTotal * commissionRate) / 100;
        final sellerAmount = itemTotal - platformCommission;

        // Create order data for this single item with "waiting" status
        final orderData = {
          'totalAmount': itemTotal,
          'items': [
            {
              'id': productId ?? item['id'],
              'productId': productId,
              'name': item['name'],
              'price': itemPrice,
              'quantity': quantity,
              'seller': item['seller'] ?? 'Unknown Seller',
              'category': item['category'] ?? 'General',
              'variantIdx': variantIdx,
            },
          ],
          'shippingAddress': address,
          'status': 'waiting', // Waiting for bank transfer
          'payment_method_type': 'sepa',
          'shipping_cost': itemShippingCost,
          'subtotal': productSubtotal,
          'commission_rate': commissionRate,
          'platform_commission': platformCommission,
          'seller_amount': sellerAmount,
          'shipping_type': shippingType,
          // ACH/SEPA transfers must remain unpaid until incoming transfer is confirmed.
          // We persist a hard 48h transfer deadline for web/app UX.
          'payment_due_date': transferDueAt.toIso8601String(),
          'sepa_details': {
            'virtual_iban': virtualIban,
            'account_holder': accountHolder,
            'customer_iban': customerIban,
            'transfer_due_date': transferDueAt.toIso8601String(),
          },
        };

        print('📦 Creating SEPA order ${i + 1}/${widget.cartItems.length}...');
        final orderResponse = await ApiService.createOrder(
          orderData,
          widget.accessToken,
        );

        final orderId = orderResponse['orderId'];
        createdOrderIds.add(orderId);
        print('✅ SEPA Order $orderId created with status "waiting"');
        print('  - Product subtotal: \$${productSubtotal.toStringAsFixed(2)}');
        print('  - Shipping cost: \$${itemShippingCost.toStringAsFixed(2)}');
        print(
          '  - Platform commission: \$${platformCommission.toStringAsFixed(2)}',
        );
        print('  - Seller amount: \$${sellerAmount.toStringAsFixed(2)}');

        // Don't send notifications for SEPA orders - they are 'waiting' status until payment is received
        // await ApiService.sendOrderNotification(...);
      }

      print('✅ All ${createdOrderIds.length} SEPA orders created!');

      if (mounted) {
        // Show success dialog
        _showSepaOrderSuccessDialog(
          createdOrderIds,
          totalWithShipping,
          virtualIban,
        );

        await _removePurchasedItemsFromCart();

        // Close checkout modal and trigger completion callback
        Navigator.of(context).pop();
        widget.onOrderComplete();

        TopNotification.success(
          context,
          '${createdOrderIds.length} orders created! Please transfer \$${totalWithShipping.toStringAsFixed(2)} within 48 hours. Status changes to paid only after transfer confirmation.',
        );
      }
    } catch (e) {
      print('❌ SEPA order creation error: $e');
      if (mounted) {
        TopNotification.error(
          context,
          'Error creating SEPA order: ${e.toString()}',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Create ACH order with "waiting" status
  Future<void> _createAchOrder(
    String virtualAccountNumber,
    String virtualRoutingNumber,
    String accountHolder,
    String customerAccountNumber,
    String customerRoutingNumber,
  ) async {
    setState(() => _isLoading = true);

    try {
      final totalWithShipping = widget.totalPrice + _shippingCost;
      final commissionRate = 0.0; // Commission handled later

      print('💰 ACH Order creation:');
      print('  - Total amount: \$${totalWithShipping.toStringAsFixed(2)}');
      print('  - Virtual Account: $virtualAccountNumber');
      print('  - Virtual Routing: $virtualRoutingNumber');
      print('  - Account holder: $accountHolder');

      final transferDueAt = DateTime.now().add(const Duration(hours: 48));
      List<String> createdOrderIds = [];

      for (int i = 0; i < widget.cartItems.length; i++) {
        final item = widget.cartItems[i];
        final address = _selectedAddressPerItem[i];
        final shippingType = _selectedShippingTypePerItem[i] ?? 'delvioo';

        if (address == null) {
          throw Exception('Missing address for item ${i + 1}');
        }

        // Calculate costs for this specific item
        final productId = item['productId'];
        final quantityRaw = item['quantity'] ?? 1;
        print('🔢 Quantity conversion:');
        print('  - quantityRaw: $quantityRaw (${quantityRaw.runtimeType})');
        final quantity = _parseCartQuantity(quantityRaw);
        print('  - quantity after conversion: $quantity');
        final product = _productDetails[productId?.toString() ?? ''];

        // Get item price (considering variant)
        double itemPrice = 0.0;
        final priceRaw = item['price'];
        itemPrice = (priceRaw is String)
            ? double.tryParse(priceRaw) ?? 0.0
            : (priceRaw is int)
            ? priceRaw.toDouble()
            : (priceRaw as double? ?? 0.0);

        final variantIdx = item['variantIdx'];
        if (product != null && variantIdx != null) {
          final variants = product['variants'] as List<dynamic>?;
          if (variants != null && variantIdx < variants.length) {
            final variant = variants[variantIdx];
            final variantPriceRaw = variant['price'];
            itemPrice = (variantPriceRaw is String)
                ? double.tryParse(variantPriceRaw) ?? 0.0
                : (variantPriceRaw is int)
                ? variantPriceRaw.toDouble()
                : (variantPriceRaw as double? ?? 0.0);
          }
        }

        final productSubtotal = itemPrice * quantity;

        // Calculate shipping cost for this item
        double itemShippingCost = 0.0;
        if (product != null) {
          final shippingCostsRaw = product['shippingCosts'];
          if (shippingCostsRaw != null) {
            try {
              String shippingCostsStr = shippingCostsRaw.toString();
              if (shippingCostsStr.startsWith('{')) {
                Map<String, dynamic> costs = json.decode(shippingCostsStr);
                if (costs.containsKey(shippingType)) {
                  final cost = costs[shippingType];
                  itemShippingCost = (cost is int)
                      ? cost.toDouble()
                      : double.tryParse(cost.toString()) ?? 0.0;
                  itemShippingCost *= quantity;
                }
              }
            } catch (e) {
              print('Error parsing shipping costs for item $i: $e');
            }
          }
        }

        final itemTotal = productSubtotal + itemShippingCost;
        final platformCommission = (itemTotal * commissionRate) / 100;
        final sellerAmount = itemTotal - platformCommission;

        // Create order data for this single item with "waiting" status
        final orderData = {
          'totalAmount': itemTotal,
          'items': [
            {
              'id': productId ?? item['id'],
              'productId': productId,
              'name': item['name'],
              'price': itemPrice,
              'quantity': quantity,
              'seller': item['seller'] ?? 'Unknown Seller',
              'category': item['category'] ?? 'General',
              'variantIdx': variantIdx,
            },
          ],
          'shippingAddress': address,
          'status': 'waiting', // Waiting for ACH transfer
          'payment_method_type': 'ach',
          'shipping_cost': itemShippingCost,
          'subtotal': productSubtotal,
          'commission_rate': commissionRate,
          'platform_commission': platformCommission,
          'seller_amount': sellerAmount,
          'shipping_type': shippingType,
          // ACH/SEPA transfers must remain unpaid until incoming transfer is confirmed.
          // We persist a hard 48h transfer deadline for web/app UX.
          'payment_due_date': transferDueAt.toIso8601String(),
          'ach_details': {
            'virtual_account_number': virtualAccountNumber,
            'virtual_routing_number': virtualRoutingNumber,
            'account_holder': accountHolder,
            'customer_account_number': customerAccountNumber,
            'customer_routing_number': customerRoutingNumber,
            'transfer_due_date': transferDueAt.toIso8601String(),
          },
        };

        print('📦 Creating ACH order ${i + 1}/${widget.cartItems.length}...');
        final orderResponse = await ApiService.createOrder(
          orderData,
          widget.accessToken,
        );

        final orderId = orderResponse['orderId'];
        createdOrderIds.add(orderId);
        print('✅ ACH Order $orderId created with status "waiting"');
        print('  - Product subtotal: \$${productSubtotal.toStringAsFixed(2)}');
        print('  - Shipping cost: \$${itemShippingCost.toStringAsFixed(2)}');
        print(
          '  - Platform commission: \$${platformCommission.toStringAsFixed(2)}',
        );
        print('  - Seller amount: \$${sellerAmount.toStringAsFixed(2)}');

        // Don't send notifications for ACH orders - they are 'waiting' status until payment is received
        // await ApiService.sendOrderNotification(...);
      }

      print('✅ All ${createdOrderIds.length} ACH orders created!');

      if (mounted) {
        // Show success dialog
        _showAchOrderSuccessDialog(
          createdOrderIds,
          totalWithShipping,
          virtualAccountNumber,
          virtualRoutingNumber,
        );

        await _removePurchasedItemsFromCart();

        // Close checkout modal and trigger completion callback
        Navigator.of(context).pop();
        widget.onOrderComplete();

        TopNotification.success(
          context,
          '${createdOrderIds.length} orders created! Please transfer \$${totalWithShipping.toStringAsFixed(2)} via ACH within 48 hours. Status changes to paid only after transfer confirmation.',
        );
      }
    } catch (e) {
      print('❌ ACH order creation error: $e');
      if (mounted) {
        TopNotification.error(
          context,
          'Error creating ACH order: ${e.toString()}',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Create Wire Transfer order with status "waiting"
  Future<void> _createWireOrder(
    String virtualRoutingNumber,
    String virtualAccountNumber,
    String accountHolder,
    String customerRoutingNumber,
    String customerAccountNumber,
  ) async {
    setState(() => _isLoading = true);

    try {
      final totalWithShipping = widget.totalPrice + _shippingCost;
      final commissionRate = 0.0; // Commission handled later

      print('💰 Wire Transfer order creation:');
      print('  - Total amount: \$${totalWithShipping.toStringAsFixed(2)}');
      print('  - Virtual Routing: $virtualRoutingNumber');
      print('  - Virtual Account: $virtualAccountNumber');
      print('  - Account holder: $accountHolder');

      List<String> createdOrderIds = [];

      for (int i = 0; i < widget.cartItems.length; i++) {
        final item = widget.cartItems[i];
        final address = _selectedAddressPerItem[i];
        final shippingType = _selectedShippingTypePerItem[i] ?? 'delvioo';

        if (address == null) {
          throw Exception('Missing address for item ${i + 1}');
        }

        // Calculate costs for this specific item
        final productId = item['productId'];
        final quantityRaw = item['quantity'] ?? 1;
        final quantity = _parseCartQuantity(quantityRaw);
        final product = _productDetails[productId?.toString() ?? ''];

        // Get item price
        double itemPrice = 0.0;
        final priceRaw = item['price'];
        itemPrice = (priceRaw is String)
            ? double.tryParse(priceRaw) ?? 0.0
            : (priceRaw is int)
            ? priceRaw.toDouble()
            : (priceRaw as double? ?? 0.0);

        final variantIdx = item['variantIdx'];
        if (product != null && variantIdx != null) {
          final variants = product['variants'] as List<dynamic>?;
          if (variants != null && variantIdx < variants.length) {
            final variant = variants[variantIdx];
            final variantPriceRaw = variant['price'];
            itemPrice = (variantPriceRaw is String)
                ? double.tryParse(variantPriceRaw) ?? 0.0
                : (variantPriceRaw is int)
                ? variantPriceRaw.toDouble()
                : (variantPriceRaw as double? ?? 0.0);
          }
        }

        final productSubtotal = itemPrice * quantity;

        // Calculate shipping cost
        double itemShippingCost = 0.0;
        if (product != null) {
          final shippingCostsRaw = product['shippingCosts'];
          if (shippingCostsRaw != null) {
            try {
              String shippingCostsStr = shippingCostsRaw.toString();
              if (shippingCostsStr.startsWith('{')) {
                Map<String, dynamic> costs = json.decode(shippingCostsStr);
                if (costs.containsKey(shippingType)) {
                  final cost = costs[shippingType];
                  itemShippingCost = (cost is int)
                      ? cost.toDouble()
                      : double.tryParse(cost.toString()) ?? 0.0;
                  itemShippingCost *= quantity;
                }
              }
            } catch (e) {
              print('Error parsing shipping costs for item $i: $e');
            }
          }
        }

        final itemTotal = productSubtotal + itemShippingCost;
        final platformCommission = (itemTotal * commissionRate) / 100;
        final sellerAmount = itemTotal - platformCommission;

        // Create order data
        final orderData = {
          'totalAmount': itemTotal,
          'items': [
            {
              'id': productId ?? item['id'],
              'productId': productId,
              'name': item['name'],
              'price': itemPrice,
              'quantity': quantity,
              'seller': item['seller'] ?? 'Unknown Seller',
              'category': item['category'] ?? 'General',
              'variantIdx': variantIdx,
            },
          ],
          'shippingAddress': address,
          'status': 'waiting', // Waiting for Wire transfer
          'payment_method_type': 'wire',
          'shipping_cost': itemShippingCost,
          'subtotal': productSubtotal,
          'commission_rate': commissionRate,
          'platform_commission': platformCommission,
          'seller_amount': sellerAmount,
          'shipping_type': shippingType,
          'wire_details': {
            'virtual_routing_number': virtualRoutingNumber,
            'virtual_account_number': virtualAccountNumber,
            'account_holder': accountHolder,
            'customer_routing_number': customerRoutingNumber,
            'customer_account_number': customerAccountNumber,
          },
        };

        print('📦 Creating Wire order ${i + 1}/${widget.cartItems.length}...');
        final orderResponse = await ApiService.createOrder(
          orderData,
          widget.accessToken,
        );

        final orderId = orderResponse['orderId'];
        createdOrderIds.add(orderId);
        print('✅ Wire Order $orderId created with status "waiting"');

        // Don't send notifications for Wire orders - they are 'waiting' status until payment is received
        // await ApiService.sendOrderNotification(...);
      }

      print('✅ All ${createdOrderIds.length} Wire orders created!');

      if (mounted) {
        // Show success dialog
        _showWireOrderSuccessDialog(
          createdOrderIds,
          totalWithShipping,
          virtualRoutingNumber,
          virtualAccountNumber,
        );

        await _removePurchasedItemsFromCart();

        // Close checkout modal and trigger completion callback
        Navigator.of(context).pop();
        widget.onOrderComplete();

        TopNotification.success(
          context,
          '${createdOrderIds.length} orders created! Please transfer \$${totalWithShipping.toStringAsFixed(2)} via wire to complete payment.',
        );
      }
    } catch (e) {
      print('❌ Wire order creation error: $e');
      if (mounted) {
        TopNotification.error(
          context,
          'Error creating Wire order: ${e.toString()}',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Create Payment Terms order (Net 30 or Net 60) with virtual Stripe account
  Future<void> _createPaymentTermsOrder(
    String paymentType,
    Map<String, dynamic> accountData,
    {
    bool markAsPaid = false,
  }
  ) async {
    if (mounted) setState(() => _isLoading = true);

    // Extract account details — differs for ACH (US) vs SEPA (EU)
    final accountType    = accountData['type']           as String? ?? 'ach';
    final accountHolder  = accountData['account_holder'] as String? ?? '';
    // ACH fields
    final virtualAccountNumber = accountData['account_number'] as String? ?? '';
    final virtualRoutingNumber = accountData['routing_number'] as String? ?? '';
    // SEPA fields
    final virtualIban = accountData['iban'] as String? ?? '';
    final virtualBic  = accountData['bic']  as String? ?? '';

    try {
      final totalWithShipping = widget.totalPrice + _shippingCost;
      final commissionRate = 0.0; // Commission handled later

      // Calculate over-limit fee if applicable
      final remainingLimit = _weeklyPaymentLimit - _currentWeekUsage;
      final isOverLimit = totalWithShipping > remainingLimit;
      final overLimitAmount = isOverLimit
          ? totalWithShipping - remainingLimit
          : 0.0;
      final overLimitFee = overLimitAmount * (_overLimitFeePercent / 100);
      final totalWithFees = totalWithShipping + overLimitFee;

      final paymentTermDays = paymentType == 'payment_30_days' ? 30 : 60;

      print('💼 Payment Terms order creation (Net $paymentTermDays):');
      print('  - Total amount: \$${totalWithShipping.toStringAsFixed(2)}');
      print(
        '  - Current week usage: \$${_currentWeekUsage.toStringAsFixed(2)}',
      );
      print('  - Weekly limit: \$${_weeklyPaymentLimit.toStringAsFixed(2)}');
      print('  - Remaining limit: \$${remainingLimit.toStringAsFixed(2)}');
      if (accountType == 'sepa') {
        print('  - SEPA IBAN: $virtualIban');
        print('  - SEPA BIC:  $virtualBic');
      } else {
        print('  - ACH Account: $virtualAccountNumber');
        print('  - ACH Routing: $virtualRoutingNumber');
      }
      if (isOverLimit) {
        print('  - ⚠️ Over limit by: \$${overLimitAmount.toStringAsFixed(2)}');
        print(
          '  - Over-limit fee: \$${overLimitFee.toStringAsFixed(2)} ($_overLimitFeePercent%)',
        );
        print('  - Total with fees: \$${totalWithFees.toStringAsFixed(2)}');
      }

      List<String> createdOrderIds = [];

      for (int i = 0; i < widget.cartItems.length; i++) {
        final item = widget.cartItems[i];
        final address = _selectedAddressPerItem[i];
        final shippingType = _selectedShippingTypePerItem[i] ?? 'delvioo';

        if (address == null) {
          throw Exception('Missing address for item ${i + 1}');
        }

        // Calculate costs for this specific item
        final productId = item['productId'];
        final quantityRaw = item['quantity'] ?? 1;
        final quantity = _parseCartQuantity(quantityRaw);
        final product = _productDetails[productId?.toString() ?? ''];

        // Get item price (considering variant)
        double itemPrice = 0.0;
        final priceRaw = item['price'];
        itemPrice = (priceRaw is String)
            ? double.tryParse(priceRaw) ?? 0.0
            : (priceRaw is int)
            ? priceRaw.toDouble()
            : (priceRaw as double? ?? 0.0);

        final variantIdx = item['variantIdx'];
        if (product != null && variantIdx != null) {
          final variants = product['variants'] as List<dynamic>?;
          if (variants != null && variantIdx < variants.length) {
            final variant = variants[variantIdx];
            final variantPriceRaw = variant['price'];
            itemPrice = (variantPriceRaw is String)
                ? double.tryParse(variantPriceRaw) ?? 0.0
                : (variantPriceRaw is int)
                ? variantPriceRaw.toDouble()
                : (variantPriceRaw as double? ?? 0.0);
          }
        }

        final productSubtotal = itemPrice * quantity;

        // Calculate shipping cost for this item
        double itemShippingCost = 0.0;
        if (product != null) {
          final shippingCostsRaw = product['shippingCosts'];
          if (shippingCostsRaw != null) {
            try {
              String shippingCostsStr = shippingCostsRaw.toString();
              if (shippingCostsStr.startsWith('{')) {
                Map<String, dynamic> costs = json.decode(shippingCostsStr);
                if (costs.containsKey(shippingType)) {
                  final cost = costs[shippingType];
                  itemShippingCost = (cost is int)
                      ? cost.toDouble()
                      : double.tryParse(cost.toString()) ?? 0.0;
                  itemShippingCost *= quantity;
                }
              }
            } catch (e) {
              print('Error parsing shipping costs for item $i: $e');
            }
          }
        }

        final itemTotal = productSubtotal + itemShippingCost;

        // Calculate proportional over-limit fee for this item
        final itemProportion = itemTotal / totalWithShipping;
        final itemOverLimitFee = overLimitFee * itemProportion;
        final itemTotalWithFee = itemTotal + itemOverLimitFee;

        final platformCommission = (itemTotalWithFee * commissionRate) / 100;
        final sellerAmount = itemTotalWithFee - platformCommission;

        // Calculate due date and reminder dates
        final now = DateTime.now();
        final dueDate = now.add(Duration(days: paymentTermDays));
        final reminderDate = now.add(Duration(days: 25)); // Day 25 reminder
        final firstLateFeeDate = dueDate.add(Duration(days: 0)); // Day 30: +5%
        final secondLateFeeDate = dueDate.add(
          Duration(days: 2),
        ); // Day 32: +15%
        final legalActionDate = dueDate.add(Duration(days: 4)); // Day 34: Legal

        final orderStatus = markAsPaid ? 'confirmed' : 'pending';

        // Create order data for this single item
        final orderData = {
          'totalAmount': itemTotalWithFee,
          'items': [
            {
              'id': productId ?? item['id'],
              'productId': productId,
              'name': item['name'],
              'price': itemPrice,
              'quantity': quantity,
              'seller': item['seller'] ?? 'Unknown Seller',
              'category': item['category'] ?? 'General',
              'variantIdx': variantIdx,
            },
          ],
          'shippingAddress': address,
          'status': orderStatus,
          'payment_method_type': paymentType,
          'shipping_cost': itemShippingCost,
          'subtotal': productSubtotal,
          'commission_rate': commissionRate,
          'platform_commission': platformCommission,
          'seller_amount': sellerAmount,
          'shipping_type': shippingType,
          'payment_terms_details': {
            'term_days': paymentTermDays,
            'due_date': dueDate.toIso8601String(),
            'reminder_date': reminderDate.toIso8601String(), // Day 25
            'first_late_fee_date': firstLateFeeDate.toIso8601String(),
            'second_late_fee_date': secondLateFeeDate.toIso8601String(),
            'legal_action_date': legalActionDate.toIso8601String(),
            'business_info': _businessInfo,
            'over_limit_fee': itemOverLimitFee,
            'is_over_limit': isOverLimit,
            'payment_system': accountType,
            'account_holder': accountHolder,
            // ACH (US) fields
            if (accountType != 'sepa') ...{
              'virtual_account_number': virtualAccountNumber,
              'virtual_routing_number': virtualRoutingNumber,
            },
            // SEPA (EU) fields
            if (accountType == 'sepa') ...{
              'virtual_iban': virtualIban,
              'virtual_bic': virtualBic,
            },
            'late_fee_schedule': {
              'first_reminder': {
                'day': paymentTermDays,
                'fee_percent': 5,
                'action': 'First Reminder',
              },
              'account_suspended': {
                'day': paymentTermDays + 2,
                'fee_percent': 15,
                'action': 'Account Suspended',
              },
              'legal_action': {
                'day': paymentTermDays + 4,
                'fee_percent': 0,
                'action': 'Legal Action - Lawsuit',
              },
            },
          },
        };

        print(
          '📦 Creating Net $paymentTermDays order ${i + 1}/${widget.cartItems.length}...',
        );
        final orderResponse = await ApiService.createOrder(
          orderData,
          widget.accessToken,
        );

        final orderId = orderResponse['orderId'];
        createdOrderIds.add(orderId);
        print(
          '✅ Net $paymentTermDays Order $orderId created with status "$orderStatus"',
        );
        print('  - Product subtotal: \$${productSubtotal.toStringAsFixed(2)}');
        print('  - Shipping cost: \$${itemShippingCost.toStringAsFixed(2)}');
        if (itemOverLimitFee > 0) {
          print('  - Over-limit fee: \$${itemOverLimitFee.toStringAsFixed(2)}');
        }
        print(
          '  - Platform commission: \$${platformCommission.toStringAsFixed(2)}',
        );
        print('  - Seller amount: \$${sellerAmount.toStringAsFixed(2)}');
        print('  - Due date: ${dueDate.toString().split(' ')[0]}');
        print(
          '  - Reminder email: ${reminderDate.toString().split(' ')[0]} (Day 25)',
        );

        // Schedule reminder email for Day 25 via Mailgun
        await ApiService.schedulePaymentReminder(
          accessToken: widget.accessToken,
          orderId: orderId,
          customerEmail: widget.currentUser?['email'] ?? '',
          businessName: _businessInfo?['business_name'] ?? '',
          totalAmount: itemTotalWithFee,
          dueDate: dueDate,
          reminderDate: reminderDate,
        );

        // Don't send notifications for Payment Terms orders - they are 'waiting' status until payment is received
        // await ApiService.sendOrderNotification(...);
      }

      print(
        '✅ All ${createdOrderIds.length} Net $paymentTermDays orders created!',
      );

      if (mounted) {
        // Update weekly usage locally immediately so the limit shows correctly
        setState(() {
          _currentWeekUsage += totalWithFees;
        });

        await _removePurchasedItemsFromCart();

        // Show success dialog and WAIT for user to close it
        await _showPaymentTermsSuccessDialog(
          createdOrderIds,
          totalWithFees,
          paymentTermDays,
          dueDate: DateTime.now().add(Duration(days: paymentTermDays)),
          overLimitFee: overLimitFee,
          markAsPaid: markAsPaid,
        );

        if (!mounted) return;

        // Close checkout modal and trigger completion callback
        Navigator.of(context).pop();
        widget.onOrderComplete();

        TopNotification.success(
          context,
          markAsPaid
              ? '${createdOrderIds.length} orders created and marked as paid.'
              : '${createdOrderIds.length} orders created! Invoice due in $paymentTermDays days.',
        );
      }
    } catch (e) {
      print('❌ Payment Terms order creation error: $e');
      if (mounted) {
        TopNotification.error(
          context,
          'Error creating Payment Terms order: ${e.toString()}',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Complete order creation after successful payment
  Future<void> _completeOrderCreation(
    double totalAmount,
    double commissionRate,
    String paymentIntentId,
  ) async {
    List<String> createdOrderIds = [];

    for (int i = 0; i < widget.cartItems.length; i++) {
      final item = widget.cartItems[i];
      final address = _selectedAddressPerItem[i];
      final shippingType = _selectedShippingTypePerItem[i] ?? 'delvioo';

      if (address == null) {
        throw Exception('Missing address for item ${i + 1}');
      }

      // Calculate costs for this specific item
      final productId = item['productId'];
      final quantityRaw = item['quantity'] ?? 1;
      print('🔢 Quantity conversion (_processPayment):');
      print('  - quantityRaw: $quantityRaw (${quantityRaw.runtimeType})');
        final quantity = _parseCartQuantity(quantityRaw);
      print('  - quantity after conversion: $quantity');
      final product = _productDetails[productId?.toString() ?? ''];

      // Get item price (considering variant)
      double itemPrice = 0.0;
      final priceRaw = item['price'];
      itemPrice = (priceRaw is String)
          ? double.tryParse(priceRaw) ?? 0.0
          : (priceRaw is int)
          ? priceRaw.toDouble()
          : (priceRaw as double? ?? 0.0);

      final variantIdx = item['variantIdx'];
      if (product != null && variantIdx != null) {
        final variants = product['variants'] as List<dynamic>?;
        if (variants != null && variantIdx < variants.length) {
          final variant = variants[variantIdx];
          final variantPriceRaw = variant['price'];
          itemPrice = (variantPriceRaw is String)
              ? double.tryParse(variantPriceRaw) ?? 0.0
              : (variantPriceRaw is int)
              ? variantPriceRaw.toDouble()
              : (variantPriceRaw as double? ?? 0.0);
        }
      }

      final productSubtotal = itemPrice * quantity;

      // Calculate shipping cost for this item
      double itemShippingCost = 0.0;
      if (product != null) {
        final shippingCostsRaw = product['shippingCosts'];
        if (shippingCostsRaw != null) {
          try {
            String shippingCostsStr = shippingCostsRaw.toString();
            if (shippingCostsStr.startsWith('{')) {
              Map<String, dynamic> costs = json.decode(shippingCostsStr);
              if (costs.containsKey(shippingType)) {
                final cost = costs[shippingType];
                itemShippingCost = (cost is int)
                    ? cost.toDouble()
                    : double.tryParse(cost.toString()) ?? 0.0;
                itemShippingCost *= quantity;
              }
            }
          } catch (e) {
            print('Error parsing shipping costs for item $i: $e');
          }
        }
      }

      final itemTotal = productSubtotal + itemShippingCost;
      final platformCommission = (itemTotal * commissionRate) / 100;
      final sellerAmount = itemTotal - platformCommission;

      // Create order data for this single item
      final orderData = {
        'paymentIntentId': paymentIntentId,
        'totalAmount': itemTotal,
        'items': [
          {
            'id': productId ?? item['id'],
            'productId': productId,
            'name': item['name'],
            'price': itemPrice,
            'quantity': quantity,
            'seller': item['seller'] ?? 'Unknown Seller',
            'category': item['category'] ?? 'General',
            'variantIdx': variantIdx,
          },
        ],
        'shippingAddress': address,
        'paymentMethodId': _selectedPaymentMethod == 'saved_card'
            ? _selectedSavedCard!['id']
            : null,
        'status': _selectedPaymentMethod == 'sepa' ? 'waiting' : 'confirmed',
        'payment_status': _selectedPaymentMethod == 'sepa' ? 'pending' : 'paid',
        'shipping_cost': itemShippingCost,
        'subtotal': productSubtotal,
        'commission_rate': commissionRate,
        'platform_commission': platformCommission,
        'seller_amount': sellerAmount,
        'payment_method_type': _selectedPaymentMethod,
        'shipping_type': shippingType,
        // Cleaning certificate requirement
        'requires_cleaning_certificate': _requiresCleaningPerItem[i] == true
            ? 1
            : 0,
        'cleaning_certificate_fee':
            (_requiresCleaningPerItem[i] == true && product != null)
            ? (product['cleaning_certificate_fee'] ?? 0.0)
            : 0.0,
        // Add business info for payment terms
        if (_businessInfo != null) 'business_info': _businessInfo,
      };

      print('📦 Creating order ${i + 1}/${widget.cartItems.length}...');
      final orderResponse = await ApiService.createOrder(
        orderData,
        widget.accessToken,
      );

      final orderId = orderResponse['orderId'];
      createdOrderIds.add(orderId);
      print('✅ Order $orderId created for item: ${item['name']}');
      print('  - Product subtotal: \$${productSubtotal.toStringAsFixed(2)}');
      print('  - Shipping cost: \$${itemShippingCost.toStringAsFixed(2)}');
      print(
        '  - Platform commission: \$${platformCommission.toStringAsFixed(2)}',
      );
      print('  - Seller amount: \$${sellerAmount.toStringAsFixed(2)}');

      // Send push notification for order success
      await ApiService.sendOrderNotification(
        accessToken: widget.accessToken,
        productName: item['name'] ?? 'Product',
        totalAmount: itemTotal,
        orderId: orderId,
      );
    }

    print('✅ All ${createdOrderIds.length} orders created successfully!');

    if (mounted) {
      // Show success dialog and wait until user taps Done.
      await _showMultiOrderSuccessDialog(createdOrderIds, totalAmount);

      await _removePurchasedItemsFromCart();

      // Close checkout modal and trigger completion callback
      Navigator.of(context).pop();
      widget.onOrderComplete();

      TopNotification.success(
        context,
        '${createdOrderIds.length} orders placed successfully! Total: ${_formatCurrency(totalAmount)}',
      );
    }
  }

  Future<void> _showMultiOrderSuccessDialog(
    List<String> orderIds,
    double totalAmount,
  ) async {
    if (!mounted) return;

    await TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: Builder(
        builder: (context) {
          final isDark = Theme.of(context).brightness == Brightness.dark;

          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Success icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    CupertinoIcons.checkmark_circle_fill,
                    color: Colors.green,
                    size: 50,
                  ),
                ),

                const SizedBox(height: 24),

                Text(
                  AppLocalizations.of(context)!.ordersPlacedSuccessfully,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 16),

                Text(
                  '${orderIds.length} separate orders have been created',
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 24),

                // Order IDs
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withOpacity(0.05)
                        : Colors.black.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context)!.orderIds1,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...orderIds.map(
                        (id) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            '• $id',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? Colors.white70 : Colors.black54,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Total amount
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.totalPaid,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    Text(
                      _formatCurrency(totalAmount),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Close button
                TradeRepublicButton(
                  label: AppLocalizations.of(context)!.done,
                  onPressed: () => Navigator.of(context).pop(),
                  width: double.infinity,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // Show SEPA order success dialog with payment instructions
  void _showSepaOrderSuccessDialog(
    List<String> orderIds,
    double totalAmount,
    String virtualIban,
  ) {
    if (!mounted) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    TradeRepublicBottomSheet.show(
      context: context,
      isDismissible: false,
      showDragHandle: true,
      maxHeight: MediaQuery.of(context).size.height * 0.95,
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  // Success icon
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      CupertinoIcons.clock_fill,
                      size: 40,
                      color: Colors.amber,
                    ),
                  ),

                  const SizedBox(height: 24),

                  Text(
                    AppLocalizations.of(context)!.ordersCreated,
                    style: TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black,
                      letterSpacing: -1,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 8),

                  Text(
                    AppLocalizations.of(context)!.waitingForSepaPayment,
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.amber,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 24),

                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Payment instructions
                          Container(
                            padding: const EdgeInsets.all(28),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(25),

                              border: Border.all(
                                color: Colors.blue.withOpacity(0.2),
                                width: 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      CupertinoIcons.info,
                                      color: Colors.blue,
                                      size: 28,
                                    ),
                                    const SizedBox(width: 16),
                                    Text(
                                      AppLocalizations.of(
                                        context,
                                      )!.paymentInstructions,
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  AppLocalizations.of(
                                    context,
                                  )!.pleaseTransferTheExactAmountToTheIbanBelow,
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: isDark
                                        ? Colors.white70
                                        : Colors.black87,
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 20),

                          // Virtual IBAN Card
                          Container(
                            padding: const EdgeInsets.all(28),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Colors.blue, Colors.blue.shade700],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(25),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  AppLocalizations.of(
                                    context,
                                  )!.transferToThisIban,
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        virtualIban,
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                          letterSpacing: 1.5,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: () {
                                        Clipboard.setData(
                                          ClipboardData(text: virtualIban),
                                        );
                                        TopNotification.info(
                                          context,
                                          AppLocalizations.of(
                                            context,
                                          )!.ibanCopied,
                                        );
                                      },
                                      icon: Icon(
                                        CupertinoIcons.doc_on_doc,
                                        color: Colors.white,
                                        size: 24,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                Divider(color: Colors.white24),
                                const SizedBox(height: 20),
                                Text(
                                  AppLocalizations.of(
                                    context,
                                  )!.amountToTransfer1,
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _formatCurrency(totalAmount),
                                  style: TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 20),

                          // Order IDs
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withOpacity(0.05)
                                  : Colors.black.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(25),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  AppLocalizations.of(
                                    context,
                                  )!.orderIdsCount(orderIds.length),
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                ...orderIds.map(
                                  (id) => Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Text(
                                      '• $id',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: isDark
                                            ? Colors.white70
                                            : Colors.black54,
                                        fontFamily: 'monospace',
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
                  ),

                  const SizedBox(height: 20),

                  // Close button
                  TradeRepublicButton(
                    label: AppLocalizations.of(context)!.done,
                    onPressed: () => Navigator.of(context).pop(),
                    width: double.infinity,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Show ACH order success dialog with payment instructions
  void _showAchOrderSuccessDialog(
    List<String> orderIds,
    double totalAmount,
    String virtualAccountNumber,
    String virtualRoutingNumber,
  ) {
    if (!mounted) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    TradeRepublicBottomSheet.show(
      context: context,
      isDismissible: false,
      showDragHandle: true,
      maxHeight: MediaQuery.of(context).size.height * 0.95,
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  // Success icon
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      CupertinoIcons.clock_fill,
                      size: 40,
                      color: Colors.amber,
                    ),
                  ),

                  const SizedBox(height: 24),

                  Text(
                    AppLocalizations.of(context)!.ordersCreated,
                    style: TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black,
                      letterSpacing: -1,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 8),

                  Text(
                    AppLocalizations.of(context)!.waitingForAchPayment,
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.amber,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 24),

                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Payment instructions
                          Container(
                            padding: const EdgeInsets.all(28),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(25),
                              border: Border.all(
                                color: Colors.green.withOpacity(0.2),
                                width: 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      CupertinoIcons.info,
                                      color: Colors.green,
                                      size: 28,
                                    ),
                                    const SizedBox(width: 16),
                                    Text(
                                      AppLocalizations.of(
                                        context,
                                      )!.achPaymentInstructions,
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  AppLocalizations.of(
                                    context,
                                  )!.pleaseTransferTheExactAmountViaAchToTheAc,
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: isDark
                                        ? Colors.white70
                                        : Colors.black87,
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 20),

                          // Virtual ACH Account Card
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.green.shade700,
                                  Colors.green.shade500,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(25),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  AppLocalizations.of(context)!.routingNumber,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      virtualRoutingNumber,
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                        letterSpacing: 2,
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: () {
                                        Clipboard.setData(
                                          ClipboardData(
                                            text: virtualRoutingNumber,
                                          ),
                                        );
                                        TopNotification.info(
                                          context,
                                          AppLocalizations.of(
                                            context,
                                          )!.routingNumberCopied1,
                                        );
                                      },
                                      icon: Icon(
                                        CupertinoIcons.doc_on_doc,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                Divider(color: Colors.white24),
                                const SizedBox(height: 20),
                                Text(
                                  AppLocalizations.of(context)!.accountNumber,
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        virtualAccountNumber,
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                          letterSpacing: 2,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: () {
                                        Clipboard.setData(
                                          ClipboardData(
                                            text: virtualAccountNumber,
                                          ),
                                        );
                                        TopNotification.info(
                                          context,
                                          AppLocalizations.of(
                                            context,
                                          )!.accountNumberCopied1,
                                        );
                                      },
                                      icon: Icon(
                                        CupertinoIcons.doc_on_doc,
                                        color: Colors.white,
                                        size: 24,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                Divider(color: Colors.white24),
                                const SizedBox(height: 20),
                                Text(
                                  AppLocalizations.of(
                                    context,
                                  )!.amountToTransfer1,
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _formatCurrency(totalAmount),
                                  style: TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 20),

                          // Order IDs
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withOpacity(0.05)
                                  : Colors.black.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(25),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  AppLocalizations.of(
                                    context,
                                  )!.orderIdsCount(orderIds.length),
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                ...orderIds.map(
                                  (id) => Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Text(
                                      '• $id',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: isDark
                                            ? Colors.white70
                                            : Colors.black54,
                                        fontFamily: 'monospace',
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
                  ),

                  const SizedBox(height: 20),

                  // Close button
                  TradeRepublicButton(
                    label: AppLocalizations.of(context)!.done,
                    onPressed: () => Navigator.of(context).pop(),
                    width: double.infinity,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Show Wire Transfer Order Success Dialog
  void _showWireOrderSuccessDialog(
    List<String> orderIds,
    double totalAmount,
    String virtualRoutingNumber,
    String virtualAccountNumber,
  ) {
    if (!mounted) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      isDismissible: false,
      maxHeight: MediaQuery.of(context).size.height * 0.95,
      child: Builder(
        builder: (context) {
          return Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    children: [
                      // Success icon
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          CupertinoIcons.clock_fill,
                          size: 40,
                          color: Colors.amber,
                        ),
                      ),

                      const SizedBox(height: 24),

                      Text(
                        AppLocalizations.of(context)!.ordersCreated,
                        style: TextStyle(
                          fontSize: 42,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black,
                          letterSpacing: -1,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: 8),

                      Text(
                        AppLocalizations.of(context)!.waitingForWireTransfer,
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.amber,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: 24),

                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Payment instructions
                              Container(
                                padding: const EdgeInsets.all(28),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.white.withOpacity(0.04)
                                      : Colors.black.withOpacity(0.02),
                                  borderRadius: BorderRadius.circular(25),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      AppLocalizations.of(
                                        context,
                                      )!.wireTransferInstructions,
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      AppLocalizations.of(
                                        context,
                                      )!.pleaseSendAWireTransferForTheExactAmountT,
                                      style: TextStyle(
                                        fontSize: 18,
                                        color: isDark
                                            ? Colors.white70
                                            : Colors.black87,
                                        height: 1.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 20),

                              // Virtual Wire Account Card
                              Container(
                                padding: const EdgeInsets.all(28),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.deepPurple.shade700,
                                      Colors.deepPurple.shade500,
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(25),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      AppLocalizations.of(
                                        context,
                                      )!.routingNumber,
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.white70,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          virtualRoutingNumber,
                                          style: TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                            letterSpacing: 2,
                                          ),
                                        ),
                                        IconButton(
                                          onPressed: () {
                                            Clipboard.setData(
                                              ClipboardData(
                                                text: virtualRoutingNumber,
                                              ),
                                            );
                                            TopNotification.info(
                                              context,
                                              AppLocalizations.of(
                                                context,
                                              )!.routingNumberCopied1,
                                            );
                                          },
                                          icon: Icon(
                                            CupertinoIcons.doc_on_doc,
                                            color: Colors.white,
                                            size: 24,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 20),
                                    Divider(color: Colors.white24),
                                    const SizedBox(height: 20),
                                    Text(
                                      AppLocalizations.of(
                                        context,
                                      )!.accountNumber,
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.white70,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            virtualAccountNumber,
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                              letterSpacing: 1.5,
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          onPressed: () {
                                            Clipboard.setData(
                                              ClipboardData(
                                                text: virtualAccountNumber,
                                              ),
                                            );
                                            TopNotification.info(
                                              context,
                                              AppLocalizations.of(
                                                context,
                                              )!.accountNumberCopied1,
                                            );
                                          },
                                          icon: Icon(
                                            CupertinoIcons.doc_on_doc,
                                            color: Colors.white,
                                            size: 24,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 20),
                                    Divider(color: Colors.white24),
                                    const SizedBox(height: 20),
                                    Text(
                                      AppLocalizations.of(
                                        context,
                                      )!.amountToTransfer1,
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.white70,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _formatCurrency(totalAmount),
                                      style: TextStyle(
                                        fontSize: 32,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 20),

                              // Order IDs
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.white.withOpacity(0.04)
                                      : Colors.black.withOpacity(0.02),
                                  borderRadius: BorderRadius.circular(25),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      AppLocalizations.of(
                                        context,
                                      )!.orderIdsCount(orderIds.length),
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    ...orderIds.map(
                                      (id) => Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 6,
                                        ),
                                        child: Text(
                                          '• $id',
                                          style: TextStyle(
                                            fontSize: 16,
                                            color: isDark
                                                ? Colors.white70
                                                : Colors.black54,
                                            fontFamily: 'monospace',
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
                      ),

                      const SizedBox(height: 20),

                      // Close button
                      TradeRepublicButton(
                        label: AppLocalizations.of(context)!.done,
                        onPressed: () => Navigator.of(context).pop(),
                        width: double.infinity,
                      ),
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

  Future<void> _showPaymentTermsSuccessDialog(
    List<String> orderIds,
    double totalAmount,
    int termDays, {
    required DateTime dueDate,
    double overLimitFee = 0.0,
    bool markAsPaid = false,
  }) async {
    if (!mounted) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasOverLimitFee = overLimitFee > 0;

    await TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      isDismissible: false,
      maxHeight: MediaQuery.of(context).size.height * 0.9,
      child: Builder(
        builder: (context) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              children: [
                // Success icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    CupertinoIcons.calendar,
                    size: 40,
                    color: Colors.orange,
                  ),
                ),

                const SizedBox(height: 24),

                Text(
                  AppLocalizations.of(context)!.ordersCreated,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 8),

                Text(
                  AppLocalizations.of(context)!.netPaymentTerms(termDays),
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.orange,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 8),

                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: markAsPaid
                        ? Colors.green.withOpacity(0.15)
                        : Colors.orange.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        markAsPaid
                            ? CupertinoIcons.checkmark_seal_fill
                            : CupertinoIcons.time,
                        size: 14,
                        color: markAsPaid ? Colors.green : Colors.orange,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        markAsPaid
                            ? 'Order Confirmed & Paid'
                            : 'Order Pending — awaiting verification',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: markAsPaid ? Colors.green : Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Payment instructions
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(25),

                            border: Border.all(
                              color: Colors.orange.withOpacity(0.2),
                              width: 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    CupertinoIcons.info,
                                    color: Colors.orange,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    AppLocalizations.of(context)!.paymentTerms,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                AppLocalizations.of(
                                  context,
                                )!.invoiceDueWithinDays(termDays),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isDark
                                      ? Colors.white70
                                      : Colors.black87,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Invoice Details Card
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.orange.shade700,
                                Colors.orange.shade500,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(25),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                AppLocalizations.of(context)!.invoiceTotal,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _formatCurrency(totalAmount),
                                style: TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: -1,
                                ),
                              ),

                              if (hasOverLimitFee) ...[
                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(25),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        CupertinoIcons
                                            .exclamationmark_triangle_fill,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        AppLocalizations.of(
                                          context,
                                        )!.includesOverLimitFee(
                                          _formatCurrency(overLimitFee),
                                        ),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.white,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],

                              const SizedBox(height: 20),
                              Divider(color: Colors.white.withOpacity(0.3)),
                              const SizedBox(height: 20),

                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        AppLocalizations.of(context)!.dueDate,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.white70,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${dueDate.day}.${dueDate.month}.${dueDate.year}',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        AppLocalizations.of(context)!.orders,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.white70,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        orderIds.length.toString(),
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Order Items Summary
                        Text(
                          AppLocalizations.of(context)!.orderSummary,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                        const SizedBox(height: 12),

                        ...widget.cartItems.asMap().entries.map((entry) {
                          final i = entry.key;
                          final item = entry.value;
                          final itemName = item['name'] ?? 'Product';
                          final quantityRaw = item['quantity'] ?? 1;
                            final quantity = _parseCartQuantity(quantityRaw);
                          final priceRaw = item['price'];
                          final itemPrice = (priceRaw is String)
                              ? double.tryParse(priceRaw) ?? 0.0
                              : (priceRaw is int)
                                  ? priceRaw.toDouble()
                                  : (priceRaw as double? ?? 0.0);

                          final productId = item['productId'];
                          final product = _productDetails[productId?.toString() ?? ''];
                          double minOrder = 1.0;
                          if (product != null) {
                            minOrder = (product['minOrder'] ?? 1).toDouble();
                          }
                          final actualQty = minOrder * quantity;
                          final subtotal = itemPrice * actualQty;
                          final shippingType = _selectedShippingTypePerItem[i] ?? 'delvioo';

                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withOpacity(0.06)
                                  : Colors.black.withOpacity(0.04),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              children: [
                                // Item icon
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${i + 1}',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.orange,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // Item details
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        itemName,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: isDark ? Colors.white : Colors.black,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        '${actualQty.toStringAsFixed(actualQty == actualQty.roundToDouble() ? 0 : 2)} × ${_formatCurrency(itemPrice)}  •  $shippingType',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isDark ? Colors.white54 : Colors.black45,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Item subtotal
                                Text(
                                  _formatCurrency(subtotal),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),

                        // Shipping + Total breakdown
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withOpacity(0.04)
                                : Colors.black.withOpacity(0.02),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    AppLocalizations.of(context)!.shippingCost,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: isDark ? Colors.white54 : Colors.black45,
                                    ),
                                  ),
                                  Text(
                                    _formatCurrency(_shippingCost),
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: isDark ? Colors.white54 : Colors.black45,
                                    ),
                                  ),
                                ],
                              ),
                              if (hasOverLimitFee) ...[
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Over-Limit Fee',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.orange,
                                      ),
                                    ),
                                    Text(
                                      _formatCurrency(overLimitFee),
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.orange,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 8),
                              Divider(
                                height: 1,
                                color: isDark ? Colors.white12 : Colors.black12,
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    AppLocalizations.of(context)!.total,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: isDark ? Colors.white : Colors.black,
                                    ),
                                  ),
                                  Text(
                                    _formatCurrency(totalAmount),
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: isDark ? Colors.white : Colors.black,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Remaining weekly limit info
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                CupertinoIcons.chart_bar_alt_fill,
                                color: Colors.blue,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Weekly Net Limit',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDark ? Colors.white54 : Colors.black45,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${_formatCurrency(_weeklyPaymentLimit - _currentWeekUsage)} remaining',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: isDark ? Colors.white : Colors.black,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Progress indicator
                              SizedBox(
                                width: 40,
                                height: 40,
                                child: CircularProgressIndicator(
                                  value: (_currentWeekUsage / _weeklyPaymentLimit).clamp(0.0, 1.0),
                                  strokeWidth: 4,
                                  backgroundColor: isDark
                                      ? Colors.white.withOpacity(0.1)
                                      : Colors.black.withOpacity(0.06),
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    _currentWeekUsage >= _weeklyPaymentLimit
                                        ? Colors.red
                                        : Colors.blue,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Order IDs
                        if (orderIds.length > 1) ...[
                          Text(
                            AppLocalizations.of(context)!.orderIds,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white70 : Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...orderIds.map(
                            (id) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                '• $id',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDark
                                      ? Colors.white60
                                      : Colors.black45,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Close button
                TradeRepublicButton(
                  label: AppLocalizations.of(context)!.done,
                  onPressed: () => Navigator.of(context).pop(),
                  width: double.infinity,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showOrderSuccessDialog(
    String orderId,
    double totalAmount,
    double commission,
    double sellerAmount,
  ) {
    if (!mounted) return;

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: _buildSuccessBottomSheet(
        orderId,
        totalAmount,
        commission,
        sellerAmount,
      ),
    );
  }

  Widget _buildSuccessBottomSheet(
    String orderId,
    double totalAmount,
    double commission,
    double sellerAmount,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                  child: Column(
                    children: [
                      // Success Animation Container
                      // Success Animation Container
                      TradeRepublicCard(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            // Success Icon
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                color: const Color(0xFF4CAF50),
                                borderRadius: BorderRadius.circular(25),
                              ),
                              child: const Icon(
                                CupertinoIcons.checkmark,
                                color: Colors.white,
                                size: 48,
                              ),
                            ),

                            const SizedBox(height: 24),

                            Text(
                              '🎉 Payment Successful',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black,
                              ),
                              textAlign: TextAlign.center,
                            ),

                            const SizedBox(height: 8),

                            Text(
                              AppLocalizations.of(
                                context,
                              )!.yourOrderHasBeenPlacedSuccessfully,
                              style: TextStyle(
                                fontSize: 16,
                                color: isDark ? Colors.white70 : Colors.black54,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Order Details
                      TradeRepublicCard(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TradeRepublicSectionHeader(
                              title: AppLocalizations.of(context)!.orderDetails,
                            ),
                            const SizedBox(height: 8),

                            _buildDetailRow(
                              AppLocalizations.of(context)!.orderId,
                              orderId,
                              isDark,
                            ),
                            const SizedBox(height: 12),
                            _buildDetailRow(
                              AppLocalizations.of(context)!.totalPaid,
                              _formatCurrency(totalAmount),
                              isDark,
                            ),
                            const SizedBox(height: 12),
                            _buildDetailRow(
                              AppLocalizations.of(context)!.platformFee65,
                              _formatCurrency(commission),
                              isDark,
                            ),
                            const SizedBox(height: 12),
                            _buildDetailRow(
                              AppLocalizations.of(context)!.sellerReceives,
                              _formatCurrency(sellerAmount),
                              isDark,
                            ),

                            const SizedBox(height: 20),

                            TradeRepublicCard(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Icon(
                                    CupertinoIcons.info,
                                    color: isDark ? Colors.blue.shade300 : Colors.blue.shade700,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      AppLocalizations.of(
                                        context,
                                      )!.moneyWillBeTransferredToSellersWithin2448H,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: isDark ? Colors.blue.shade300 : Colors.blue.shade700,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Close Button (Fixed at bottom)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: TradeRepublicButton(
                  label: AppLocalizations.of(context)!.continueShopping,
                  tint: const Color(0xFF4CAF50),
                  onPressed: () => Navigator.of(context).pop(),
                  width: double.infinity,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value, bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 15,
            color: isDark ? Colors.white70 : Colors.black54,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            color: isDark ? Colors.white : Colors.black,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentMethodSelector() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isIOS = Platform.isIOS;

    return TradeRepublicCard(
      padding: const EdgeInsets.all(20),
      child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TradeRepublicSectionHeader(
                title: AppLocalizations.of(context)!.paymentMethod,
                subtitle: AppLocalizations.of(context)!.chooseHowYouWantToPay,
                leading: Icon(
                  CupertinoIcons.creditcard,
                  color: TradeRepublicTheme.textColor(context),
                  size: 22,
                ),
              ),
              const SizedBox(height: 20),

              // Saved Payment Methods Button
              TradeRepublicListTile.navigation(
                title: AppLocalizations.of(context)!.useSavedPaymentMethod,
                subtitle: AppLocalizations.of(context)!.cardSepaAchWireTransfer,
                leading: Icon(CupertinoIcons.creditcard_fill, size: 20, color: Colors.blue.shade400),
                onTap: () => _showSavedPaymentMethodsSheet(),
              ),
              const SizedBox(height: 20),

              // Selected Payment Method Display - Modern Card Design
              if (_selectedSavedCard != null ||
                  _selectedSepaMethod != null ||
                  _selectedAchMethod != null ||
                  _selectedWireMethod != null) ...[
                _buildSelectedPaymentCard(isDark),
                const SizedBox(height: 20),
              ],

              // Cards Section
              if (_savedCards.isNotEmpty) ...[
                TradeRepublicSectionHeader(
                  title: AppLocalizations.of(context)!.savedCards,
                ),
                const SizedBox(height: 8),
                _buildPaymentOption(
                  'saved_card',
                  AppLocalizations.of(context)!.useSavedCard,
                  CupertinoIcons.creditcard,
                ),
                const SizedBox(height: 16),
              ],

              TradeRepublicSectionHeader(
                title: AppLocalizations.of(context)!.instantPayment,
              ),
              const SizedBox(height: 8),

              _buildPaymentOption(
                'wallet',
                AppLocalizations.of(context)!.walletPayment1,
                CupertinoIcons.money_dollar_circle_fill,
                subtitle: AppLocalizations.of(context)!.walletBalance,
              ),
              const SizedBox(height: 8),

              _buildPaymentOption(
                'card',
                AppLocalizations.of(context)!.creditOrDebitCard,
                CupertinoIcons.creditcard,
                subtitle: AppLocalizations.of(context)!.visaMastercardAmex,
              ),
              const SizedBox(height: 8),

              if (isIOS) ...[
                _buildPaymentOption(
                  'apple_pay',
                  AppLocalizations.of(context)!.applePay,
                  CupertinoIcons.device_phone_portrait,
                  subtitle: AppLocalizations.of(context)!.fastSecure,
                ),
                const SizedBox(height: 8),
              ],

              if (!isIOS) ...[
                _buildPaymentOption(
                  'google_pay',
                  AppLocalizations.of(context)!.googlePay,
                  CupertinoIcons.creditcard,
                  subtitle: AppLocalizations.of(context)!.fastSecure,
                ),
                const SizedBox(height: 8),
              ],

              const SizedBox(height: 16),

              // Bank Transfer Section
              TradeRepublicSectionHeader(
                title: AppLocalizations.of(context)!.bankTransfer,
              ),
              const SizedBox(height: 8),

              _buildPaymentOption(
                'sepa',
                AppLocalizations.of(context)!.sepaDirectDebit,
                CupertinoIcons.building_2_fill,
                subtitle: AppLocalizations.of(context)!.bankAccount13Days,
              ),
              const SizedBox(height: 8),

              _buildPaymentOption(
                'ach',
                AppLocalizations.of(context)!.achDirectDebit,
                CupertinoIcons.building_2_fill,
                subtitle: AppLocalizations.of(context)!.businessDaysLowerFees,
              ),
              const SizedBox(height: 8),

              _buildPaymentOption(
                'wire',
                AppLocalizations.of(context)!.wireTransfer,
                CupertinoIcons.arrow_right_arrow_left,
                subtitle: AppLocalizations.of(context)!.sameOrNextBusinessDay,
              ),

              const SizedBox(height: 16),

              // Payment Terms Section
              TradeRepublicSectionHeader(
                title: AppLocalizations.of(context)!.paymentTermsB2b,
              ),
              const SizedBox(height: 8),

              _buildPaymentOption(
                'payment_30_days',
                AppLocalizations.of(context)!.net30,
                CupertinoIcons.calendar,
                subtitle: AppLocalizations.of(
                  context,
                )!.payWithin30DaysBusinessOnly,
              ),
              const SizedBox(height: 8),

              _buildPaymentOption(
                'payment_60_days',
                AppLocalizations.of(context)!.net60,
                CupertinoIcons.calendar,
                subtitle: AppLocalizations.of(
                  context,
                )!.payWithin60DaysBusinessOnly,
              ),
            ],
          ),
    );
  }

  Widget _buildPaymentOption(
    String value,
    String title,
    IconData icon, {
    String? subtitle,
  }) {
    final isSelected = _selectedPaymentMethod == value;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Check if this requires business info
    final requiresBusinessInfo =
        value == 'payment_30_days' || value == 'payment_60_days';

    // Check if this requires SEPA payment
    final requiresSepaInfo = value == 'sepa';

    // Check if this requires ACH payment
    final requiresAchInfo = value == 'ach';

    // Check if this requires Wire payment
    final requiresWireInfo = value == 'wire';

    // Get icon color based on payment method
    Color getIconColor() {
      if (isSelected) {
        return TradeRepublicTheme.selectionContainerForeground(context);
      }

      // Special colors for different payment methods
      switch (value) {
        case 'wallet':
          return Colors.green.shade700;
        case 'apple_pay':
          return Colors.black;
        case 'google_pay':
          return Colors.blue;
        case 'stripe':
          return const Color(0xFF635BFF); // Stripe purple
        case 'ach':
          return Colors.green.shade700;
        case 'wire':
          return Colors.deepPurple.shade700;
        case 'payment_30_days':
        case 'payment_60_days':
          return Colors.orange.shade700;
        default:
          return isDark ? Colors.white60 : Colors.black45;
      }
    }

    // Check if this requires card entry
    final requiresCardInfo = value == 'card';

    return TradeRepublicListTile(
      title: title,
      subtitle: subtitle,
      backgroundColor: isSelected
          ? TradeRepublicTheme.selectionContainerBackground(context)
          : null,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      leading: Icon(icon, color: getIconColor(), size: 22),
      trailing: isSelected
          ? Icon(
              CupertinoIcons.checkmark_circle_fill,
              color: TradeRepublicTheme.selectionContainerForeground(context),
              size: 20,
            )
          : null,
      onTap: () {
        if (requiresBusinessInfo) {
          _showBusinessInfoSheet(value);
        } else if (requiresSepaInfo) {
          _showSepaPaymentSheet();
        } else if (requiresAchInfo) {
          _showAchPaymentSheet();
        } else if (requiresWireInfo) {
          _showWirePaymentSheet();
        } else if (requiresCardInfo) {
          setState(() => _selectedPaymentMethod = value);
          _showCreditCardSheet();
        } else {
          setState(() => _selectedPaymentMethod = value);
        }
      },
    );
  }

  Widget _buildAddressSelector() {

    if (_isLoadingAddresses) {
      return TradeRepublicCard(
        padding: const EdgeInsets.all(20),
        child: const Center(child: CultiooLoadingIndicator()),
      );
    }

    if (_userAddresses.isEmpty) {
      return TradeRepublicCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(
              CupertinoIcons.location_slash,
              size: 48,
              color: TradeRepublicTheme.hintColor(context),
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context)!.noAddressesFound,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: TradeRepublicTheme.textColor(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context)!.addAnAddressInSettings,
              style: TextStyle(
                fontSize: 14,
                color: TradeRepublicTheme.hintColor(context),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return TradeRepublicCard(
      child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: TradeRepublicSectionHeader(
                  title: AppLocalizations.of(context)!.selectDeliveryAddress1,
                ),
              ),

              const Divider(height: 1),

              // Scrollable address list
              SizedBox(
                height: 200,
                child: ListView.builder(
                  itemCount: _userAddresses.length,
                  itemBuilder: (context, index) {
                    return _buildAddressOption(_userAddresses[index]);
                  },
                ),
              ),
            ],
          ),
    );
  }

  Widget _buildAddressOption(Map<String, dynamic> address) {
    // This method is no longer used - kept for compatibility
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: () {}, // No-op
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(25),
        ),
        child: Row(
          children: [
            Icon(
              CupertinoIcons.location_solid,
              color: isDark ? Colors.white70 : Colors.black54,
              size: 24,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    address['username'] != null
                        ? '${address['username']}\'s Address'
                        : AppLocalizations.of(context)!.address,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _formatAddressDisplay(address),
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (address['isSelected'] == 1) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(25),
                      ),
                      child: Text(
                        'Default',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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

  Widget _buildSavedCardsSelector() {
    if (_selectedPaymentMethod != 'saved_card' || _savedCards.isEmpty) {
      return const SizedBox.shrink();
    }

    return TradeRepublicCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TradeRepublicSectionHeader(
            title: AppLocalizations.of(context)!.selectSavedCard,
          ),
          const SizedBox(height: 8),
          ..._savedCards.map((card) => _buildSavedCardOption(card)),
        ],
      ),
    );
  }

  Widget _buildSavedCardOption(Map<String, dynamic> card) {
    final isSelected = _selectedSavedCard?['id'] == card['id'];
    final cardData = card['card'] as Map<String, dynamic>?;
    final brand = (cardData?['brand'] ?? card['brand'] ?? card['card_brand'] ?? 'unknown').toString();
    final last4 = (cardData?['last4'] ?? card['last4'] ?? card['card_last4'] ?? '****').toString();
    final expMonthRaw = (cardData?['exp_month'] ?? card['exp_month'] ?? card['card_exp_month'] ?? '1').toString();
    final expYearRaw = (cardData?['exp_year'] ?? card['exp_year'] ?? card['card_exp_year'] ?? '').toString();
    final isDefault = card['is_default'] == true || card['isDefault'] == true;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => setState(() => _selectedSavedCard = card),
        child: Stack(
          children: [
            CreditCardWidget(
              brand: brand,
              last4: last4,
              expMonth: expMonthRaw,
              expYear: expYearRaw,
              isDefault: isDefault,
            ),
            // Selected overlay
            if (isSelected)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.6),
                      width: 2,
                    ),
                  ),
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          CupertinoIcons.checkmark,
                          color: Colors.white,
                          size: 13,
                        ),
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

  Widget _buildCreditCardForm() {
    if (_selectedPaymentMethod != 'card') {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Get card info from controllers
    final cardNumber = _cardNumberController.text.replaceAll(' ', '');
    final hasCardNumber = cardNumber.length >= 4;
    final cardBrand = _detectCardBrand(cardNumber);
    final displayNumber = hasCardNumber
        ? '**** **** **** ${cardNumber.substring(cardNumber.length - 4)}'
        : '**** **** **** ****';
    final cardName = _nameController.text.isEmpty
        ? AppLocalizations.of(context)!.cardholderName
        : _nameController.text.toUpperCase();
    final expiry = _expiryController.text.isEmpty
        ? 'MM/YY'
        : _expiryController.text;

    return Container(
      margin: const EdgeInsets.only(top: 16),
      child: TweenAnimationBuilder<double>(
        duration: const Duration(milliseconds: 600),
        tween: Tween(begin: 0.0, end: 1.0),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) {
          return Transform(
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateX(0.1 * (1 - value))
              ..translate(0.0, 20 * (1 - value), 0.0),
            alignment: Alignment.center,
            child: Opacity(opacity: value, child: child),
          );
        },
        child: Container(
          height: 200,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(25),

            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _getCardGradient(cardBrand, isDark),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(25),

            child: Stack(
              children: [
                // Holographic effect
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white.withOpacity(0.1),
                          Colors.transparent,
                          Colors.white.withOpacity(0.05),
                        ],
                      ),
                    ),
                  ),
                ),
                // Card content
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Card brand logo
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Icon(
                            _getCardIcon(cardBrand),
                            color: Colors.white,
                            size: 40,
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(25),
                            ),
                            child: Text(
                              cardBrand.toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      // Card number
                      Text(
                        displayNumber,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 2,
                          fontFamily: 'Courier',
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Cardholder and expiry
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'CARDHOLDER',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.7),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  cardName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                AppLocalizations.of(context)!.validThru,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                expiry,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1,
                                ),
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
          ),
        ),
      ),
    );
  }

  // Detect card brand from number
  String _detectCardBrand(String number) {
    if (number.isEmpty) return 'card';
    if (number.startsWith('4')) return 'visa';
    if (number.startsWith(RegExp(r'^5[1-5]'))) return 'mastercard';
    if (number.startsWith(RegExp(r'^3[47]'))) return 'amex';
    if (number.startsWith('6')) return 'discover';
    return 'card';
  }

  // Get card gradient colors
  List<Color> _getCardGradient(String brand, bool isDark) {
    switch (brand) {
      case 'visa':
        return [
          const Color(0xFF1A1F71),
          const Color(0xFF0D47A1),
          const Color(0xFF1565C0),
        ];
      case 'mastercard':
        return [
          const Color(0xFFEB001B),
          const Color(0xFFF79E1B),
          const Color(0xFFFF9100),
        ];
      case 'amex':
        return [
          const Color(0xFF006FCF),
          const Color(0xFF0288D1),
          const Color(0xFF00A3E0),
        ];
      case 'discover':
        return [
          const Color(0xFFFF6000),
          const Color(0xFFFF7B00),
          const Color(0xFFFF9000),
        ];
      default:
        return isDark
            ? [
                const Color(0xFF2C3E50),
                const Color(0xFF34495E),
                const Color(0xFF4A5568),
              ]
            : [
                const Color(0xFF667EEA),
                const Color(0xFF764BA2),
                const Color(0xFF8B5CF6),
              ];
    }
  }

  // Get card icon
  IconData _getCardIcon(String brand) {
    switch (brand) {
      case 'visa':
      case 'mastercard':
      case 'amex':
      case 'discover':
        return CupertinoIcons.creditcard;
      default:
        return CupertinoIcons.creditcard;
    }
  }

  // Build Selected Payment Card - Ultra Modern with Gradients
  Widget _buildSelectedPaymentCard(bool isDark) {
    String type;
    String title;
    String subtitle;

    if (_selectedSavedCard != null) {
      // Show visual card widget for saved card
      final cardData = _selectedSavedCard!['card'] as Map<String, dynamic>?;
      final brand = (cardData?['brand'] ?? _selectedSavedCard!['brand'] ?? _selectedSavedCard!['card_brand'] ?? 'unknown').toString();
      final last4 = (cardData?['last4'] ?? _selectedSavedCard!['last4'] ?? _selectedSavedCard!['card_last4'] ?? '****').toString();
      final expMonthRaw = (cardData?['exp_month'] ?? _selectedSavedCard!['exp_month'] ?? _selectedSavedCard!['card_exp_month'] ?? '1').toString();
      final expYearRaw = (cardData?['exp_year'] ?? _selectedSavedCard!['exp_year'] ?? _selectedSavedCard!['card_exp_year'] ?? '').toString();
      final isDefault = _selectedSavedCard!['is_default'] == true || _selectedSavedCard!['isDefault'] == true;

      return TradeRepublicCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CreditCardWidget(
              brand: brand,
              last4: last4,
              expMonth: expMonthRaw,
              expYear: expYearRaw,
              isDefault: isDefault,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TradeRepublicButton(
                    label: AppLocalizations.of(context)!.useSavedCard,
                    isSecondary: true,
                    height: 40,
                    onPressed: _showSavedPaymentMethodsSheet,
                  ),
                ),
                const SizedBox(width: 8),
                TradeRepublicButton(
                  icon: const Icon(CupertinoIcons.xmark, size: 14),
                  isSecondary: true,
                  height: 40,
                  width: 40,
                  padding: EdgeInsets.zero,
                  onPressed: () {
                    setState(() {
                      _selectedSavedCard = null;
                      _selectedSepaMethod = null;
                      _selectedAchMethod = null;
                      _selectedWireMethod = null;
                      _selectedPaymentMethod = 'card';
                    });
                  },
                ),
              ],
            ),
          ],
        ),
      );
    } else if (_selectedSepaMethod != null) {
      final last4 = (_selectedSepaMethod!['iban_last4'] ?? '????').toString();
      final holder = (_selectedSepaMethod!['account_holder_name'] ?? '').toString();
      return _buildBankAccountCardTile(
        BankAccountWidget(type: 'sepa', maskedNumber: last4, accountHolderName: holder),
      );
    } else if (_selectedAchMethod != null) {
      final last4 = (_selectedAchMethod!['account_number_last4'] ?? '????').toString();
      final holder = (_selectedAchMethod!['account_holder_name'] ?? '').toString();
      final routing = _selectedAchMethod!['routing_number']?.toString();
      return _buildBankAccountCardTile(
        BankAccountWidget(type: 'ach', maskedNumber: last4, accountHolderName: holder, routingOrSwift: routing),
      );
    } else if (_selectedWireMethod != null) {
      final last4 = (_selectedWireMethod!['account_number_last4'] ?? '????').toString();
      final holder = (_selectedWireMethod!['account_holder_name'] ?? '').toString();
      final swift = _selectedWireMethod!['swift_bic']?.toString() ?? _selectedWireMethod!['routing_number']?.toString();
      return _buildBankAccountCardTile(
        BankAccountWidget(type: 'wire', maskedNumber: last4, accountHolderName: holder, routingOrSwift: swift),
      );
    } else {
      return const SizedBox.shrink();
    }
  }

  Widget _buildBankAccountCardTile(Widget cardWidget) {
    return Column(
      children: [
        cardWidget,
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TradeRepublicButton(
                label: AppLocalizations.of(context)!.useSavedCard,
                isSecondary: true,
                height: 40,
                onPressed: _showSavedPaymentMethodsSheet,
              ),
            ),
            const SizedBox(width: 8),
            TradeRepublicButton(
              icon: const Icon(CupertinoIcons.xmark, size: 14),
              isSecondary: true,
              height: 40,
              width: 40,
              padding: EdgeInsets.zero,
              onPressed: () {
                setState(() {
                  _selectedSavedCard = null;
                  _selectedSepaMethod = null;
                  _selectedAchMethod = null;
                  _selectedWireMethod = null;
                  _selectedPaymentMethod = 'card';
                });
              },
            ),
          ],
        ),
      ],
    );
  }

  // Get payment icon based on type
  IconData _getPaymentIcon(String type) {
    switch (type) {
      case 'sepa':
        return CupertinoIcons.building_2_fill;
      case 'ach':
        return CupertinoIcons.creditcard;
      case 'wire':
        return CupertinoIcons.building_2_fill;
      default:
        return CupertinoIcons.creditcard;
    }
  }

  // Modern Credit Card Bottom Sheet
  void _showCreditCardSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 0 = form, 1 = processing, 2 = success, 3 = error
    int currentPage = 0;
    String? paymentError;

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      maxHeight: MediaQuery.of(context).size.height * 0.95,
      child: StatefulBuilder(
        builder: (context, setSheetState) {
          // Validating Page
          if (currentPage == 1) {
            return Column(
              children: [
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Spinning animation
                        SizedBox(
                          width: 80,
                          height: 80,
                          child: CultiooLoadingIndicator(),
                        ),
                        const SizedBox(height: 40),
                        Text(
                          AppLocalizations.of(context)!.processingPayment,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          AppLocalizations.of(
                            context,
                          )!.pleaseWaitWhileWeProcessYourPayment,
                          style: TextStyle(
                            fontSize: 16,
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }

          // Success Page
          if (currentPage == 2) {
            return Column(
              children: [
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Success checkmark animation
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            CupertinoIcons.checkmark_circle_fill,
                            size: 80,
                            color: Colors.green,
                          ),
                        ),
                        const SizedBox(height: 40),
                        Text(
                          AppLocalizations.of(context)!.paymentSuccessful1,
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '${_createdOrderIds.length} order${_createdOrderIds.length > 1 ? 's' : ''} placed successfully!\nTotal: ${_formatCurrency(_totalPaidAmount)}',
                          style: TextStyle(
                            fontSize: 16,
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        // Show masked card number
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withOpacity(0.05)
                                : Colors.black.withOpacity(0.03),
                            borderRadius: BorderRadius.circular(25),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                CupertinoIcons.creditcard,
                                color: isDark ? Colors.white70 : Colors.black54,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                '•••• •••• •••• ${_cardNumberController.text.replaceAll(' ', '').length >= 4 ? _cardNumberController.text.replaceAll(' ', '').substring(_cardNumberController.text.replaceAll(' ', '').length - 4) : '****'}',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white : Colors.black,
                                  letterSpacing: 2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Done button (payment already processed)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: TradeRepublicButton(
                    label: AppLocalizations.of(context)!.done,
                    onPressed: () async {
                      HapticFeedback.lightImpact();
                      await _removePurchasedItemsFromCart();
                      // Close bottom sheet
                      Navigator.pop(context);
                      // Close checkout modal
                      Navigator.of(context).pop();
                      // Trigger completion callback
                      widget.onOrderComplete();
                      // Show notification
                      TopNotification.success(
                        context,
                        '${_createdOrderIds.length} order${_createdOrderIds.length > 1 ? 's' : ''} placed successfully!',
                      );
                    },
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    width: double.infinity,
                  ),
                ),
              ],
            );
          }

          // Error Page (currentPage == 3)
          if (currentPage == 3) {
            return Column(
              children: [
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Error icon
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            CupertinoIcons.exclamationmark_circle,
                            size: 60,
                            color: Colors.red,
                          ),
                        ),
                        const SizedBox(height: 32),
                        Text(
                          AppLocalizations.of(context)!.paymentFailed,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 40),
                          child: Text(
                            paymentError ??
                                AppLocalizations.of(
                                  context,
                                )!.anErrorOccurredWhileProcessingYourPayment,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              color: isDark ? Colors.white70 : Colors.black54,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Try Again button
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: TradeRepublicButton(
                    label: AppLocalizations.of(context)!.tryAgain,
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      setSheetState(() {
                        currentPage = 0; // Back to form
                        paymentError = null;
                      });
                    },
                    isDestructive: true,
                    width: double.infinity,
                  ),
                ),
              ],
            );
          }

          // Form Page (currentPage == 0)
          return Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      Row(
                        children: [
                          Icon(CupertinoIcons.creditcard_fill, color: isDark ? Colors.white : Colors.black, size: 28),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              AppLocalizations.of(context)!.creditDebitCard,
                              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: isDark ? Colors.white : Colors.black, letterSpacing: -0.5),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        AppLocalizations.of(context)!.instantPaymentProcessing,
                        style: TextStyle(fontSize: 15, color: isDark ? Colors.white60 : Colors.black54),
                      ),

                      const SizedBox(height: 24),

                      // Content
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Cardholder Name
                              Text(
                                AppLocalizations.of(context)!.cardholderName1,
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : Colors.black,
                                ),
                              ),
                              const SizedBox(height: 12),
                              TradeRepublicTextField(
                                controller: _nameController,
                                hintText: AppLocalizations.of(context)!.johnDoe,
                                onChanged: (_) => setSheetState(() {}),
                              ),

                              const SizedBox(height: 32),

                              // Card Number
                              Text(
                                AppLocalizations.of(context)!.cardNumber,
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : Colors.black,
                                ),
                              ),
                              const SizedBox(height: 12),
                              TradeRepublicTextField(
                                controller: _cardNumberController,
                                hintText: '1234 5678 9012 3456',
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(16),
                                  _CardNumberFormatter(),
                                ],
                                onChanged: (_) => setSheetState(() {}),
                              ),

                              const SizedBox(height: 32),

                              // Expiry Date and CVV Row
                              Row(
                                children: [
                                  // Expiry Date
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          AppLocalizations.of(
                                            context,
                                          )!.expiryDate,
                                          style: TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                            color: isDark
                                                ? Colors.white
                                                : Colors.black,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        TradeRepublicTextField(
                                          controller: _expiryController,
                                          hintText: 'MM/YY',
                                          keyboardType: TextInputType.number,
                                          inputFormatters: [
                                            LengthLimitingTextInputFormatter(5),
                                            _ExpiryDateFormatter(),
                                          ],
                                          onChanged: (_) =>
                                              setSheetState(() {}),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  // CVV
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'CVV',
                                          style: TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                            color: isDark
                                                ? Colors.white
                                                : Colors.black,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        TradeRepublicTextField(
                                          controller: _cvvController,
                                          hintText: '•••',
                                          keyboardType: TextInputType.number,
                                          obscureText: true,
                                          inputFormatters: [
                                            FilteringTextInputFormatter
                                                .digitsOnly,
                                            LengthLimitingTextInputFormatter(4),
                                          ],
                                          onChanged: (_) =>
                                              setSheetState(() {}),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 40),

                              // Info
                              Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.white.withOpacity(0.04)
                                      : Colors.black.withOpacity(0.02),
                                  borderRadius: BorderRadius.circular(25),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          CupertinoIcons.shield_lefthalf_fill,
                                          color: Colors.green,
                                          size: 24,
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          AppLocalizations.of(
                                            context,
                                          )!.securePayment,
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: isDark
                                                ? Colors.white
                                                : Colors.black,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      AppLocalizations.of(
                                        context,
                                      )!.yourDataIsSslEncryptedAndSecure,
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: isDark
                                            ? Colors.white70
                                            : Colors.black54,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Pay Now Button
                      TradeRepublicButton(
                        label: AppLocalizations.of(context)!.payNow,
                        onPressed: () async {
                          print('💳 Pay Now button pressed');
                          print('  Name: ${_nameController.text}');
                          print('  Card: ${_cardNumberController.text}');
                          print('  Expiry: ${_expiryController.text}');
                          print('  CVV: ${_cvvController.text}');

                          // Validate
                          if (_nameController.text.isEmpty ||
                              _cardNumberController.text.isEmpty ||
                              _expiryController.text.isEmpty ||
                              _cvvController.text.isEmpty) {
                            print('❌ Validation failed - empty fields');
                            HapticFeedback.heavyImpact();
                            TopNotification.error(
                              context,
                              AppLocalizations.of(
                                context,
                              )!.pleaseFillInAllFields,
                            );
                            return;
                          }
                          print('✅ Validation passed');
                          HapticFeedback.lightImpact();

                          // Go to processing page (show spinner)
                          print('🔄 Going to processing page');
                          setSheetState(() {
                            currentPage = 1;
                            paymentError = null;
                          });

                          // Process the actual payment
                          try {
                            print('💰 Starting payment processing...');
                            setState(() {
                              _selectedPaymentMethod = 'card';
                            });

                            // Process card payment flow. It handles success UI + checkout close.
                            await _processCardPaymentInSheet();
                            return;
                          } catch (e) {
                            // Payment failed
                            print('❌ Payment failed: $e');
                            setSheetState(() {
                              currentPage = 3; // Error page
                              paymentError = e.toString();
                            });
                          }
                        },
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        width: double.infinity,
                      ),

                      const SizedBox(height: 16),
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

  // Modern TextField Helper
  Widget _buildModernTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required bool isDark,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    bool obscureText = false,
    Function(String)? onChanged,
  }) {
    return TradeRepublicTextField(
      controller: controller,
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, size: 20),
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      obscureText: obscureText,
      onChanged: onChanged,
    );
  }

  Widget _buildOrderSummary() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final totalWithShipping = widget.totalPrice + _shippingCost;

    return TradeRepublicCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TradeRepublicSectionHeader(
            title: AppLocalizations.of(context)!.orderSummary,
          ),
          const SizedBox(height: 8),

              ...widget.cartItems.asMap().entries.map((entry) {
                final item = entry.value;
                final productId = item['productId'];
                final quantityRaw = item['quantity'] ?? 1;
                final quantity = _parseCartQuantity(quantityRaw);
                final product = _productDetails[productId?.toString() ?? ''];

                double itemPrice = 0.0;

                if (product != null) {
                  final variantIdx = item['variantIdx'];
                  if (variantIdx != null) {
                    final variants = product['variants'] as List<dynamic>?;
                    if (variants != null && variantIdx < variants.length) {
                      final variant = variants[variantIdx];
                      final priceRaw = variant['price'];
                      itemPrice = (priceRaw is String)
                          ? double.tryParse(priceRaw) ?? 0.0
                          : (priceRaw is int)
                          ? priceRaw.toDouble()
                          : (priceRaw as double? ?? 0.0);
                    }
                  }
                }

                if (itemPrice == 0.0) {
                  final priceRaw = item['price'];
                  itemPrice = (priceRaw is String)
                      ? double.tryParse(priceRaw) ?? 0.0
                      : (priceRaw is int)
                      ? priceRaw.toDouble()
                      : (priceRaw as double? ?? 0.0);
                }

                final actualQuantity = quantity;
                final itemTotal = itemPrice * actualQuantity;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          '${actualQuantity.toStringAsFixed(2)}x ${item['name']}',
                          style: TextStyle(
                            color: isDark ? Colors.white70 : Colors.black54,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      Text(
                        _formatCurrency(itemTotal),
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white : Colors.black,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                );
              }),

              const SizedBox(height: 16),

              // Subtotal
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    AppLocalizations.of(context)!.subtotal,
                    style: TextStyle(
                      fontSize: 15,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                  Text(
                    _formatCurrency(widget.totalPrice),
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white : Colors.black,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),

              // Shipping row (only shown when there is a shipping cost)
              if (_shippingCost > 0) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.shippingMethod,
                      style: TextStyle(
                        fontSize: 15,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                    Text(
                      _formatCurrency(_shippingCost),
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white : Colors.black,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ],

              Divider(height: 32, color: isDark ? Colors.white12 : Colors.black12),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    AppLocalizations.of(context)!.total,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                  Text(
                    _formatCurrency(totalWithShipping),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                ],
              ),
            ],
          ),
    );
  }

  Widget _buildShippingTypeSelector() {
    return TradeRepublicCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TradeRepublicSectionHeader(
            title: AppLocalizations.of(context)!.shippingMethod,
          ),
          const SizedBox(height: 8),
          _buildShippingTypeOption(
            'standard',
            AppLocalizations.of(context)!.standardShipping,
            CupertinoIcons.cube_box,
            '3-5 business days',
          ),
          const SizedBox(height: 8),
          _buildShippingTypeOption(
            'delvioo',
            AppLocalizations.of(context)!.delviooExpress,
            CupertinoIcons.bolt,
            AppLocalizations.of(context)!.sameDayDelivery,
          ),
        ],
      ),
    );
  }

  void _showDelviooInfo() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      maxHeight: MediaQuery.of(context).size.height * 0.75,
      child: Builder(
        builder: (sheetContext) => Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                child: Column(
                  children: [
                    // Icon
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: (isDark ? Colors.blue[300] : Colors.blue[700])!
                            .withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        CupertinoIcons.bolt_fill,
                        size: 48,
                        color: isDark ? Colors.blue[300] : Colors.blue[700],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Title
                    Text(
                      AppLocalizations.of(context)!.delviooExpress,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Description
                    TradeRepublicCard(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        AppLocalizations.of(
                          context,
                        )!.delviooEnsuresThatOnlyRegisteredAndOfficiall,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          color: TradeRepublicTheme.hintColor(context),
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Close Button (Fixed at bottom)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: TradeRepublicButton(
                label: AppLocalizations.of(context)!.gotIt,
                onPressed: () => Navigator.pop(sheetContext),
                width: double.infinity,
                height: 56,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShippingTypeOption(
    String value,
    String title,
    IconData icon,
    String description,
  ) {
    // This method is no longer used in the new per-item checkout design
    // Kept as stub for compatibility
    return Container();
  }

  // Build checkout section for a single cart item
  Widget _buildItemCheckoutSection(int itemIndex) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final item = widget.cartItems[itemIndex];
    final rawId = item['productId'];
    // Always parse productId to int (handles String, int, BigInt-string like "2n")
    final productId = rawId is int
        ? rawId
        : int.tryParse(rawId.toString().replaceAll(RegExp(r'[^0-9]'), ''));
    final quantityRaw = item['quantity'] ?? 1;
    // Quantity is already the correct value (multiplier * 100), e.g., 623 = 6.23x minOrder
    final quantity = (quantityRaw is int)
        ? quantityRaw.toDouble()
        : (quantityRaw is String)
        ? (double.tryParse(quantityRaw) ?? 1.0)
        : ((quantityRaw ?? 1.0) as num).toDouble();
    final product = _productDetails[productId?.toString() ?? ''];

    // Debug: Print cart item details
    print('🛒 Cart item $itemIndex:');
    print('  - productId: $productId');
    print('  - quantity raw: $quantityRaw');
    print('  - quantity: $quantity');
    print('  - item price from cart: ${item['price']}');
    print('  - item data: $item');

    // Get variant info if available
    final variantIdx = item['variantIdx'];
    String itemName = item['name'] ?? 'Product';
    double itemPrice = 0.0;
    double minOrder = 1.0; // Default minimum order

    // Try to get price from product details first (most accurate)
    if (product != null) {
      if (variantIdx != null) {
        final variants = product['variants'] as List<dynamic>?;
        if (variants != null && variantIdx < variants.length) {
          final variant = variants[variantIdx];
          itemName = '${product['name']} - ${variant['title']}';

          // Parse price ensuring double type
          final priceRaw = variant['price'];
          itemPrice = (priceRaw is String)
              ? double.tryParse(priceRaw) ?? 0.0
              : (priceRaw is int)
              ? priceRaw.toDouble()
              : (priceRaw as double? ?? 0.0);

          // Get minOrder from variant, ensuring double type
          final minOrderRaw = variant['minOrder'];
          minOrder = (minOrderRaw is String)
              ? double.tryParse(minOrderRaw) ?? 1.0
              : (minOrderRaw is int)
              ? minOrderRaw.toDouble()
              : (minOrderRaw as double? ?? 1.0);
        }
      } else {
        // No variant, use base product price
        final priceRaw = product['price'];
        itemPrice = (priceRaw is String)
            ? double.tryParse(priceRaw) ?? 0.0
            : (priceRaw is int)
            ? priceRaw.toDouble()
            : (priceRaw as double? ?? 0.0);
      }
    }

    // Fallback to cart item price if product details not available
    if (itemPrice == 0.0) {
      final priceRaw = item['price'];
      itemPrice = (priceRaw is String)
          ? double.tryParse(priceRaw) ?? 0.0
          : (priceRaw is int)
          ? priceRaw.toDouble()
          : (priceRaw as double? ?? 0.0);
    }

    final actualQuantity = quantity;
    final itemSubtotal = itemPrice * actualQuantity;

    print('  - minOrder: $minOrder');
    print('  - actualQuantity: $actualQuantity');

    // Calculate shipping cost for this item
    double itemShippingCost = 0.0;
    if (product != null) {
      final selectedShippingType =
          _selectedShippingTypePerItem[itemIndex] ?? 'delvioo';
      final shippingCostsRaw = product['shippingCosts'];
      if (shippingCostsRaw != null) {
        try {
          String shippingCostsStr = shippingCostsRaw.toString();
          if (shippingCostsStr.startsWith('{')) {
            Map<String, dynamic> costs = json.decode(shippingCostsStr);
            if (costs.containsKey(selectedShippingType)) {
              final cost = costs[selectedShippingType];
              itemShippingCost = (cost is int)
                  ? cost.toDouble()
                  : double.tryParse(cost.toString()) ?? 0.0;
              // Use actualQuantity (already converted from cents format)
              itemShippingCost *= actualQuantity;
            }
          }
        } catch (e) {
          print('Error parsing shipping costs: $e');
        }
      }
    }

    return TradeRepublicCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Item info
          Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          itemName,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppLocalizations.of(
                                context,
                              )!.pricePerUnit(_formatCurrency(itemPrice)),
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? Colors.white60 : Colors.black45,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Quantity: ${actualQuantity.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? Colors.white60 : Colors.black45,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _formatCurrency(itemSubtotal),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                      Text(
                        AppLocalizations.of(context)!.subtotal,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white54 : Colors.black45,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 16),
              Divider(color: isDark ? Colors.white24 : Colors.black26),
              const SizedBox(height: 16),

              // Address selector for this item
              TradeRepublicSectionHeader(
                title: AppLocalizations.of(context)!.deliveryAddress,
              ),
              const SizedBox(height: 8),
              _buildItemAddressSelector(itemIndex),

              const SizedBox(height: 16),

              // Shipping type selector for this item
              TradeRepublicSectionHeader(
                title: AppLocalizations.of(context)!.shippingMethod,
              ),
              const SizedBox(height: 8),
              _buildItemShippingSelector(itemIndex, product),

              // Cleaning Certificate Option (only if product offers it)
              if (product != null &&
                  (product['offers_cleaning_certificate'] == true ||
                      product['offers_cleaning_certificate'] == 1)) ...[
                const SizedBox(height: 16),
                _buildCleaningCertificateSelector(itemIndex, product),
              ],

              // Show shipping cost
              if (itemShippingCost > 0) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.shippingCost,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                    Text(
                      _formatCurrency(itemShippingCost),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 12),
              Divider(color: isDark ? Colors.white24 : Colors.black26),
              const SizedBox(height: 12),

              // Total for this item
              TradeRepublicCard.elevated(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.itemTotal,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: TradeRepublicTheme.textColor(context),
                      ),
                    ),
                    Text(
                      _formatCurrency(itemSubtotal),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: TradeRepublicTheme.textColor(context),
                      ),
                    ),
                  ],
                ),
              ),

              // Shipping cost information
              if (itemShippingCost > 0) ...[
                const SizedBox(height: 12),
                Text(
                  AppLocalizations.of(
                    context,
                  )!.shippingWillBeCalculatedAndAddedAtFinalChe,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : Colors.black45,
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
    );
  }

  // Build address selector for a specific item
  Widget _buildItemAddressSelector(int itemIndex) {
    final selectedAddress = _selectedAddressPerItem[itemIndex];

    if (_isLoadingAddresses) {
      return Center(child: CultiooLoadingIndicator());
    }

    if (_userAddresses.isEmpty) {
      return TradeRepublicCard(
        padding: const EdgeInsets.all(12),
        child: Text(
          AppLocalizations.of(context)!.noAddressesAvailablePleaseAddOne,
          style: TextStyle(
            color: TradeRepublicTheme.hintColor(context),
            fontSize: 14,
          ),
        ),
      );
    }

    // Button to open address selection bottom sheet
    return TradeRepublicListTile.navigation(
      title: selectedAddress != null
          ? _formatAddressDisplay(selectedAddress)
          : AppLocalizations.of(context)!.selectDeliveryAddress1,
      subtitle: selectedAddress?['country'],
      leading: const Icon(CupertinoIcons.location_solid, size: 20),
      onTap: () => _showAddressSelectionSheet(itemIndex),
    );
  }

  // Show address selection bottom sheet (Uber style)
  void _showAddressSelectionSheet(int itemIndex) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedAddress = _selectedAddressPerItem[itemIndex];

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      maxHeight: MediaQuery.of(context).size.height * 0.7,
      child: Column(
        children: [
          // Header with close button
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Row(
              children: [
                Text(
                  AppLocalizations.of(context)!.selectAddress,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),

          Divider(height: 1, color: isDark ? Colors.white12 : Colors.black12),

          // Address list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _userAddresses.length,
              itemBuilder: (context, index) {
                final address = _userAddresses[index];
                final isSelected = selectedAddress?['id'] == address['id'];

                return TradeRepublicListTile(
                  title: _formatAddressDisplay(address),
                  subtitle: address['country'] ?? '',
                  backgroundColor: isSelected
                      ? TradeRepublicTheme.selectionContainerBackground(context)
                      : null,
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  leading: Icon(
                    CupertinoIcons.location_solid,
                    size: 20,
                    color: isSelected
                        ? TradeRepublicTheme.selectionContainerForeground(context)
                        : TradeRepublicTheme.iconColor(context, opacity: 0.45),
                  ),
                  trailing: isSelected
                      ? Icon(
                          CupertinoIcons.checkmark_circle_fill,
                          color: TradeRepublicTheme.selectionContainerForeground(
                            context,
                          ),
                          size: 20,
                        )
                      : null,
                  onTap: () {
                    setState(() {
                      _selectedAddressPerItem[itemIndex] = address;
                    });
                    Navigator.of(context).pop();
                    HapticFeedback.lightImpact();
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // Show SEPA Payment Bottom Sheet
  void _showSepaPaymentSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final TextEditingController nameController = TextEditingController();
    bool isValidating = false;
    bool isValidated = false;
    String? virtualIban;

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      maxHeight: MediaQuery.of(context).size.height * 0.95,
      child: StatefulBuilder(
        builder: (context, setModalState) {
          return Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 0),
                child: Row(
                  children: [
                    Icon(CupertinoIcons.arrow_right_arrow_left, color: isDark ? Colors.white : Colors.black, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        AppLocalizations.of(context)!.sepaDirectDebit,
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: isDark ? Colors.white : Colors.black, letterSpacing: -0.5),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  AppLocalizations.of(context)!.businessDaysProcessing,
                  style: TextStyle(fontSize: 15, color: isDark ? Colors.white60 : Colors.black54),
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: isValidated
                      ? _buildValidatedSepaView(
                          isDark,
                          virtualIban ?? '',
                          nameController.text,
                          '',
                        )
                      : SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Processing time card
                              TradeRepublicCard(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    TradeRepublicSectionHeader(
                                      title: AppLocalizations.of(context)!.processingTime,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      AppLocalizations.of(context)!.sepaDirectDebitTransfersAreProcessedWithin1,
                                      style: TextStyle(
                                        fontSize: 15,
                                        color: TradeRepublicTheme.hintColor(context),
                                        height: 1.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 24),

                              // Account Holder Name
                              TradeRepublicSectionHeader(
                                title: AppLocalizations.of(context)!.accountHolderName,
                              ),
                              const SizedBox(height: 8),
                              TradeRepublicTextField(
                                controller: nameController,
                                hintText: AppLocalizations.of(context)!.johnDoe,
                              ),

                              const SizedBox(height: 32),
                            ],
                          ),
                        ),
                ),
              ),

              // Button
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                child: !isValidated
                    ? TradeRepublicButton(
                        label: AppLocalizations.of(context)!.validateAccount,
                        onPressed: isValidating
                            ? null
                            : () async {
                                setModalState(() {
                                  isValidating = true;
                                });

                                try {
                                  // Get country from first selected address
                                  final firstAddress = _selectedAddressPerItem[0];
                                  final country = firstAddress?['country']?.toString() ?? 'DE';
                                  final fallbackName = [
                                    widget.currentUser?['firstname']?.toString() ?? '',
                                    widget.currentUser?['lastname']?.toString() ?? '',
                                  ].where((e) => e.trim().isNotEmpty).join(' ').trim();
                                  final holderName = nameController.text.trim().isNotEmpty
                                      ? nameController.text.trim()
                                      : (fallbackName.isNotEmpty
                                          ? fallbackName
                                          : widget.currentUser?['username']?.toString() ?? 'Cultioo Customer');
                                  final email = widget.currentUser?['email']?.toString() ??
                                      '${holderName.toLowerCase().replaceAll(' ', '.')}@cultioo.local';

                                  // Call real Stripe API to generate virtual SEPA account
                                  final accountData = await ApiService.generateVirtualAccount(
                                    widget.accessToken,
                                    'sepa',
                                    holderName,
                                    email,
                                    country,
                                  );

                                  virtualIban = accountData['iban']?.toString()
                                      ?? accountData['account']?['iban']?.toString()
                                      ?? accountData['virtual_iban']?.toString();

                                  if (virtualIban == null || virtualIban!.isEmpty) {
                                    throw Exception('No IBAN returned from server');
                                  }

                                  setModalState(() {
                                    isValidating = false;
                                    isValidated = true;
                                    if (nameController.text.trim().isEmpty) {
                                      nameController.text = holderName;
                                    }
                                  });
                                } catch (e) {
                                  print('❌ SEPA virtual account error: $e');
                                  setModalState(() => isValidating = false);
                                  if (context.mounted) {
                                    TopNotification.error(
                                      context,
                                      'Could not generate virtual IBAN: ${e.toString()}',
                                    );
                                  }
                                }
                              },
                        isLoading: isValidating,
                        width: double.infinity,
                      )
                    : TradeRepublicButton(
                        label: AppLocalizations.of(
                          context,
                        )!.confirmSepaTransfer,
                        onPressed: () {
                          Navigator.of(context).pop();
                          _createSepaOrder(
                            virtualIban!,
                            nameController.text.trim().isNotEmpty
                                ? nameController.text.trim()
                                : (widget.currentUser?['username']?.toString() ?? 'Cultioo Customer'),
                            '',
                          );
                        },
                        width: double.infinity,
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  // Show ACH Payment Bottom Sheet
  void _showAchPaymentSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final TextEditingController nameController = TextEditingController();
    bool isValidating = false;
    bool isValidated = false;
    String? virtualAccountNumber;
    String? virtualRoutingNumber;

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      maxHeight: MediaQuery.of(context).size.height * 0.95,
      child: StatefulBuilder(
        builder: (context, setModalState) {
          return Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      Row(
                        children: [
                          Icon(CupertinoIcons.building_2_fill, color: isDark ? Colors.white : Colors.black, size: 28),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              AppLocalizations.of(context)!.achDirectDebit,
                              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: isDark ? Colors.white : Colors.black, letterSpacing: -0.5),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        AppLocalizations.of(context)!.businessDaysProcessing,
                        style: TextStyle(fontSize: 15, color: isDark ? Colors.white60 : Colors.black54),
                      ),

                      const SizedBox(height: 24),

                      // Content
                      Expanded(
                        child: isValidated
                            ? _buildValidatedAchView(
                                isDark,
                                virtualAccountNumber!,
                                virtualRoutingNumber!,
                                nameController.text,
                                '',
                                '',
                              )
                            : SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Account Holder Name
                                    TradeRepublicSectionHeader(
                                      title: AppLocalizations.of(context)!.accountHolder,
                                    ),
                                    const SizedBox(height: 8),
                                    TradeRepublicTextField(
                                      controller: nameController,
                                      hintText: AppLocalizations.of(context)!.johnDoe,
                                    ),

                                    const SizedBox(height: 24),

                                    // Info
                                    TradeRepublicCard(
                                      padding: const EdgeInsets.all(20),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          TradeRepublicSectionHeader(
                                            title: AppLocalizations.of(context)!.processingTime,
                                            subtitle: AppLocalizations.of(context)!.businessDaysProcessing,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                      ),

                      const SizedBox(height: 24),

                      // Footer Button
                      isValidated
                          ? TradeRepublicButton(
                              label: AppLocalizations.of(
                                context,
                              )!.confirmTransfer,
                              onPressed: () {
                                Navigator.of(context).pop();
                                _createAchOrder(
                                  virtualAccountNumber!,
                                  virtualRoutingNumber!,
                                  nameController.text.trim().isNotEmpty
                                      ? nameController.text.trim()
                                      : (widget.currentUser?['username']?.toString() ?? 'Cultioo Customer'),
                                  '',
                                  '',
                                );
                              },
                              width: double.infinity,
                            )
                          : TradeRepublicButton(
                              label: AppLocalizations.of(
                                context,
                              )!.validateAccount,
                              onPressed: isValidating
                                  ? null
                                  : () {
                                      setModalState(() {
                                        isValidating = true;
                                      });

                                      final fallbackName = [
                                        widget.currentUser?['firstname']?.toString() ?? '',
                                        widget.currentUser?['lastname']?.toString() ?? '',
                                      ].where((e) => e.trim().isNotEmpty).join(' ').trim();
                                      final holderName = nameController.text.trim().isNotEmpty
                                          ? nameController.text.trim()
                                          : (fallbackName.isNotEmpty
                                              ? fallbackName
                                              : widget.currentUser?['username']?.toString() ?? 'Cultioo Customer');

                                      // Call real Stripe API to generate virtual ACH account
                                      ApiService.generateVirtualAccount(
                                        widget.accessToken,
                                        'ach',
                                        holderName,
                                        widget.currentUser?['email']?.toString() ?? '${holderName.toLowerCase().replaceAll(' ', '.')}@cultioo.local',
                                        'US',
                                      ).then((accountData) {
                                        virtualRoutingNumber = accountData['routing_number']?.toString()
                                            ?? accountData['account']?['routing_number']?.toString()
                                            ?? accountData['virtual_routing_number']?.toString();
                                        virtualAccountNumber = accountData['account_number']?.toString()
                                            ?? accountData['account']?['account_number']?.toString()
                                            ?? accountData['virtual_account_number']?.toString();

                                        if (virtualRoutingNumber == null || virtualAccountNumber == null ||
                                            virtualRoutingNumber!.isEmpty || virtualAccountNumber!.isEmpty) {
                                          throw Exception('No account details returned from server');
                                        }

                                        setModalState(() {
                                          isValidating = false;
                                          isValidated = true;
                                          if (nameController.text.trim().isEmpty) {
                                            nameController.text = holderName;
                                          }
                                        });
                                      }).catchError((e) {
                                        print('❌ ACH virtual account error: $e');
                                        setModalState(() => isValidating = false);
                                        if (context.mounted) {
                                          TopNotification.error(
                                            context,
                                            'Could not generate virtual account: ${e.toString()}',
                                          );
                                        }
                                      });
                                    },
                              isLoading: isValidating,
                              width: double.infinity,
                            ),

                      const SizedBox(height: 16),
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

  // Show Wire Transfer Payment Bottom Sheet
  void _showWirePaymentSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final TextEditingController nameController = TextEditingController();
    bool isValidating = false;
    bool isValidated = false;
    String? virtualAccountNumber;
    String? virtualRoutingNumber;

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      maxHeight: MediaQuery.of(context).size.height * 0.95,
      child: StatefulBuilder(
        builder: (context, setModalState) {
          return Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 0),
                child: Row(
                  children: [
                    Icon(CupertinoIcons.paperplane_fill, color: isDark ? Colors.white : Colors.black, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        AppLocalizations.of(context)!.wireTransfer,
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: isDark ? Colors.white : Colors.black, letterSpacing: -0.5),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  AppLocalizations.of(context)!.sameOrNextBusinessDay,
                  style: TextStyle(fontSize: 15, color: isDark ? Colors.white60 : Colors.black54),
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: isValidated
                      ? _buildValidatedWireView(
                          isDark,
                          virtualRoutingNumber!,
                          virtualAccountNumber!,
                          nameController.text,
                          '',
                          '',
                        )
                      : SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Processing time card
                              TradeRepublicCard(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    TradeRepublicSectionHeader(
                                      title: AppLocalizations.of(context)!.processingTime,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      AppLocalizations.of(context)!.wireTransfersAreProcessedTheSameOrNextBusi,
                                      style: TextStyle(
                                        fontSize: 15,
                                        color: TradeRepublicTheme.hintColor(context),
                                        height: 1.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 24),

                              // Account Holder Name
                              TradeRepublicSectionHeader(
                                title: AppLocalizations.of(context)!.accountHolderName,
                              ),
                              const SizedBox(height: 8),
                              TradeRepublicTextField(
                                controller: nameController,
                                hintText: AppLocalizations.of(context)!.johnDoe,
                              ),

                              const SizedBox(height: 32),
                            ],
                          ),
                        ),
                ),
              ),

              // Footer Button
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                child: isValidated
                    ? TradeRepublicButton(
                        label: AppLocalizations.of(
                          context,
                        )!.confirmWireTransfer,
                        onPressed: () {
                          Navigator.of(context).pop();
                          _createWireOrder(
                            virtualRoutingNumber!,
                            virtualAccountNumber!,
                            nameController.text.trim().isNotEmpty
                                ? nameController.text.trim()
                                : (widget.currentUser?['username']?.toString() ??
                                    'Cultioo Customer'),
                            '',
                            '',
                          );
                        },
                        width: double.infinity,
                      )
                    : TradeRepublicButton(
                        label: AppLocalizations.of(context)!.validateAccount,
                        onPressed: isValidating
                            ? null
                            : () async {
                                setModalState(() {
                                  isValidating = true;
                                });

                                try {
                                  final fallbackName = [
                                    widget.currentUser?['firstname']?.toString() ??
                                        '',
                                    widget.currentUser?['lastname']?.toString() ?? '',
                                  ].where((e) => e.trim().isNotEmpty).join(' ').trim();
                                  final holderName = nameController.text.trim().isNotEmpty
                                      ? nameController.text.trim()
                                      : (fallbackName.isNotEmpty
                                          ? fallbackName
                                          : widget.currentUser?['username']
                                                  ?.toString() ??
                                              'Cultioo Customer');
                                  final firstAddress = _selectedAddressPerItem[0];
                                  final country = firstAddress?['country']?.toString() ??
                                      'US';
                                  final email = widget.currentUser?['email']?.toString() ??
                                      '${holderName.toLowerCase().replaceAll(' ', '.')}@cultioo.local';

                                  // Wire uses the same virtual bank rails as ACH in backend.
                                  final accountData = await ApiService.generateVirtualAccount(
                                    widget.accessToken,
                                    'ach',
                                    holderName,
                                    email,
                                    country,
                                  );
                                  virtualRoutingNumber = accountData['routing_number']
                                          ?.toString() ??
                                      accountData['account']?['routing_number']
                                          ?.toString() ??
                                      accountData['virtual_routing_number']
                                          ?.toString();
                                  virtualAccountNumber = accountData['account_number']
                                          ?.toString() ??
                                      accountData['account']?['account_number']
                                          ?.toString() ??
                                      accountData['virtual_account_number']
                                          ?.toString();
                                  if (virtualRoutingNumber == null ||
                                      virtualAccountNumber == null ||
                                      virtualRoutingNumber!.isEmpty ||
                                      virtualAccountNumber!.isEmpty) {
                                    throw Exception(
                                      'No virtual wire account details returned',
                                    );
                                  }
                                  setModalState(() {
                                    isValidating = false;
                                    isValidated = true;
                                    if (nameController.text.trim().isEmpty) {
                                      nameController.text = holderName;
                                    }
                                  });
                                } catch (e) {
                                  print('❌ Wire virtual account error: $e');
                                  setModalState(() => isValidating = false);
                                  if (context.mounted) {
                                    TopNotification.error(
                                      context,
                                      'Could not generate virtual wire account: ${e.toString()}',
                                    );
                                  }
                                }
                              },
                        isLoading: isValidating,
                        width: double.infinity,
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  // Build validated Wire view
  Widget _buildValidatedWireView(
    bool isDark,
    String virtualRoutingNumber,
    String virtualAccountNumber,
    String accountHolder,
    String customerRoutingNumber,
    String customerAccountNumber,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          // Success Animation
          TweenAnimationBuilder(
            tween: Tween<double>(begin: 0, end: 1),
            duration: const Duration(milliseconds: 600),
            builder: (context, double value, child) {
              return Transform.scale(
                scale: value,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    CupertinoIcons.checkmark_circle_fill,
                    color: Colors.green,
                    size: 50,
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 24),

          Text(
            AppLocalizations.of(context)!.accountVerified,
            style: TextStyle(
              fontSize: 42,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black,
              letterSpacing: -1,
            ),
          ),

          const SizedBox(height: 16),

          Text(
            AppLocalizations.of(context)!.sendWireTransferToCompletePayment,
            style: TextStyle(
              fontSize: 18,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),

          const SizedBox(height: 32),

          // Virtual Wire Account Display
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.deepPurple.shade700,
                  Colors.deepPurple.shade500,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(25),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context)!.routingNumber,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      virtualRoutingNumber,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 2,
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(text: virtualRoutingNumber),
                        );
                        TopNotification.info(
                          context,
                          AppLocalizations.of(context)!.routingNumberCopied1,
                        );
                      },
                      icon: Icon(
                        CupertinoIcons.doc_on_doc,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Divider(color: Colors.white24),
                const SizedBox(height: 24),
                Text(
                  AppLocalizations.of(context)!.accountNumber,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        virtualAccountNumber,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(text: virtualAccountNumber),
                        );
                        TopNotification.info(
                          context,
                          AppLocalizations.of(context)!.accountNumberCopied1,
                        );
                      },
                      icon: Icon(
                        CupertinoIcons.doc_on_doc,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Divider(color: Colors.white24),
                const SizedBox(height: 24),
                Text(
                  AppLocalizations.of(context)!.amountToTransfer,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _formatCurrency(widget.totalPrice + _shippingCost),
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Payment Details
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withOpacity(0.04)
                  : Colors.black.withOpacity(0.02),
              borderRadius: BorderRadius.circular(25),
            ),
            child: Column(
              children: [
                _buildDetailRow(
                  AppLocalizations.of(context)!.yourName,
                  accountHolder,
                  isDark,
                ),
                const SizedBox(height: 16),
                Divider(
                  height: 1,
                  color: isDark ? Colors.white12 : Colors.black12,
                ),
                const SizedBox(height: 16),
                _buildDetailRow(
                  AppLocalizations.of(context)!.yourRoutingNumber,
                  customerRoutingNumber,
                  isDark,
                ),
                const SizedBox(height: 16),
                Divider(
                  height: 1,
                  color: isDark ? Colors.white12 : Colors.black12,
                ),
                const SizedBox(height: 16),
                _buildDetailRow(
                  AppLocalizations.of(context)!.yourAccountNumber,
                  customerAccountNumber,
                  isDark,
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Instructions
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withOpacity(0.04)
                  : Colors.black.withOpacity(0.02),
              borderRadius: BorderRadius.circular(25),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Important',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  AppLocalizations.of(
                    context,
                  )!.sendTheExactAmountViaWireTransferToTheAcc,
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark ? Colors.white70 : Colors.black87,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Build validated SEPA view with virtual IBAN
  Widget _buildValidatedSepaView(
    bool isDark,
    String virtualIban,
    String accountHolder,
    String customerIban,
  ) {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Success icon
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              CupertinoIcons.checkmark_circle_fill,
              color: Colors.blue,
              size: 40,
            ),
          ),

          const SizedBox(height: 24),

          Text(
            AppLocalizations.of(context)!.accountVerified,
            style: TextStyle(
              fontSize: 42,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black,
              letterSpacing: -1,
            ),
          ),

          const SizedBox(height: 16),

          Text(
            AppLocalizations.of(context)!.transferFundsToCompletePayment,
            style: TextStyle(
              fontSize: 18,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),

          const SizedBox(height: 32),

          // Virtual IBAN Card
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade700, Colors.blue.shade500],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(25),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'IBAN',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        virtualIban,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: virtualIban));
                        TopNotification.info(
                          context,
                          AppLocalizations.of(context)!.ibanCopied1,
                        );
                      },
                      icon: Icon(
                        CupertinoIcons.doc_on_doc,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Divider(color: Colors.white24),
                const SizedBox(height: 24),
                Text(
                  AppLocalizations.of(context)!.amountToTransfer,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _formatCurrency(widget.totalPrice + _shippingCost),
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Payment Details
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withOpacity(0.04)
                  : Colors.black.withOpacity(0.02),
              borderRadius: BorderRadius.circular(25),
            ),
            child: Column(
              children: [
                _buildDetailRow(
                  AppLocalizations.of(context)!.yourName,
                  accountHolder,
                  isDark,
                ),
                const SizedBox(height: 16),
                Divider(
                  height: 1,
                  color: isDark ? Colors.white12 : Colors.black12,
                ),
                const SizedBox(height: 16),
                _buildDetailRow(
                  AppLocalizations.of(context)!.yourIban,
                  customerIban,
                  isDark,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Build validated ACH view with virtual account details
  Widget _buildValidatedAchView(
    bool isDark,
    String virtualAccountNumber,
    String virtualRoutingNumber,
    String accountHolder,
    String customerAccountNumber,
    String customerRoutingNumber,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          // Success Animation
          TweenAnimationBuilder(
            tween: Tween<double>(begin: 0, end: 1),
            duration: const Duration(milliseconds: 600),
            builder: (context, double value, child) {
              return Transform.scale(
                scale: value,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    CupertinoIcons.checkmark_circle_fill,
                    color: Colors.green,
                    size: 50,
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 24),

          Text(
            AppLocalizations.of(context)!.accountVerified,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            AppLocalizations.of(
              context,
            )!.transferFundsViaAchToCompleteYourPayment,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          ),

          const SizedBox(height: 32),

          // Virtual ACH Account Display
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.green.shade700, Colors.green.shade500],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(25),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      CupertinoIcons.building_2_fill,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      AppLocalizations.of(context)!.virtualAchAccount,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  AppLocalizations.of(context)!.routingNumber,
                  style: TextStyle(fontSize: 12, color: Colors.white60),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      virtualRoutingNumber,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 2,
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        TopNotification.info(
                          context,
                          AppLocalizations.of(context)!.routingNumberCopied,
                        );
                      },
                      icon: Icon(
                        CupertinoIcons.doc_on_doc,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  AppLocalizations.of(context)!.accountNumber,
                  style: TextStyle(fontSize: 12, color: Colors.white60),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      virtualAccountNumber,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 2,
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        TopNotification.info(
                          context,
                          AppLocalizations.of(context)!.accountNumberCopied,
                        );
                      },
                      icon: Icon(
                        CupertinoIcons.doc_on_doc,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  AppLocalizations.of(context)!.cultiooPaymentsLlc,
                  style: TextStyle(fontSize: 14, color: Colors.white70),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Payment Details
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withOpacity(0.05)
                  : Colors.black.withOpacity(0.03),
              borderRadius: BorderRadius.circular(25),
            ),
            child: Column(
              children: [
                _buildDetailRow(
                  AppLocalizations.of(context)!.yourName,
                  accountHolder,
                  isDark,
                ),
                const SizedBox(height: 16),
                Divider(
                  height: 1,
                  color: isDark ? Colors.white12 : Colors.black12,
                ),
                const SizedBox(height: 16),
                _buildDetailRow(
                  AppLocalizations.of(context)!.yourAccount,
                  (() {
                    final digits = customerAccountNumber.replaceAll(RegExp(r'\s+'), '');
                    if (digits.length >= 4) {
                      return '****${digits.substring(digits.length - 4)}';
                    }
                    return AppLocalizations.of(context)!.notAvailable;
                  })(),
                  isDark,
                ),
                const SizedBox(height: 16),
                Divider(
                  height: 1,
                  color: isDark ? Colors.white12 : Colors.black12,
                ),
                const SizedBox(height: 16),
                _buildDetailRow(
                  'Amount',
                  _formatCurrency(widget.totalPrice + _shippingCost),
                  isDark,
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Instructions
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.1),
              borderRadius: BorderRadius.circular(25),

              border: Border.all(
                color: Colors.amber.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  CupertinoIcons.lightbulb,
                  color: Colors.amber.shade700,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    AppLocalizations.of(
                      context,
                    )!.transferTheExactAmountViaAchToTheVirtualA,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white70 : Colors.black87,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Build validated Wire view with virtual SWIFT and IBAN
  // Show business information bottom sheet for payment terms
  void _showBusinessInfoSheet(String paymentType) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Determine payment method details
    String title;
    String description;
    int? days;

    switch (paymentType) {
      case 'payment_30_days':
        title = AppLocalizations.of(context)!.net30;
        description = AppLocalizations.of(
          context,
        )!.payWithin30DaysFromInvoiceDate;
        days = 30;
        break;
      case 'payment_60_days':
        title = AppLocalizations.of(context)!.net60;
        description = AppLocalizations.of(
          context,
        )!.payWithin60DaysFromInvoiceDate;
        days = 60;
        break;
      case 'ach':
        title = AppLocalizations.of(context)!.achTransfer;
        description = AppLocalizations.of(context)!.businessDaysProcessing;
        break;
      default:
        title = AppLocalizations.of(context)!.businessPayment;
        description = AppLocalizations.of(context)!.businessPaymentDetailsRequired;
    }

    // Calculate if over limit and fee (for payment terms only)
    final totalWithShipping = widget.totalPrice + _shippingCost;
    final remainingLimit = _weeklyPaymentLimit - _currentWeekUsage;
    final isOverLimit = totalWithShipping > remainingLimit;
    final overLimitAmount = isOverLimit
        ? totalWithShipping - remainingLimit
        : 0.0;
    final overLimitFee = overLimitAmount * (_overLimitFeePercent / 100);

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      maxHeight: MediaQuery.of(context).size.height * 0.95,
      child: Builder(
        builder: (sheetContext) => _NetPaymentSheetContent(
          isDark: isDark,
          title: title,
          description: description,
          days: days,
          totalWithShipping: totalWithShipping,
          remainingLimit: remainingLimit,
          isOverLimit: isOverLimit,
          overLimitFee: overLimitFee,
          paymentType: paymentType,
          businessNameController: _businessNameController,
          businessTaxIdController: _businessTaxIdController,
          businessEmailController: _businessEmailController,
          businessPhoneController: _businessPhoneController,
          businessStreetController: _businessStreetController,
          businessHouseNumberController: _businessHouseNumberController,
          businessPostalCodeController: _businessPostalCodeController,
          businessCityController: _businessCityController,
          businessCountryController: _businessCountryController,
          businessDunsController: _businessDunsController,
          isLoadingBusinessInfo: _isLoadingBusinessInfo,
          formatCurrency: _formatCurrency,
          weeklyPaymentLimit: _weeklyPaymentLimit,
          currentWeekUsage: _currentWeekUsage,
          overLimitFeePercent: _overLimitFeePercent,
          validateBusinessInfo: _validateBusinessInfo,
          submitBusinessInfo: _submitBusinessInfo,
          buildBusinessTextField: _buildBusinessTextField,
          buildInfoRow: _buildInfoRow,
          onClose: () => Navigator.pop(sheetContext),
        ),
      ),
    );
  }

  Widget _buildBusinessTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required bool isDark,
    int maxLines = 1,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        const SizedBox(height: 12),
        TradeRepublicTextField(
          controller: controller,
          hintText: hint,
          prefixIcon: Icon(icon, size: 24),
          maxLines: maxLines,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 15,
            color: isDark ? Colors.white60 : Colors.black54,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            color: isDark ? Colors.white : Colors.black,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  bool _validateBusinessInfo() {
    if (_businessNameController.text.isEmpty) {
      TopNotification.error(
        context,
        AppLocalizations.of(context)!.pleaseEnterYourBusinessName,
      );
      return false;
    }
    if (_businessTaxIdController.text.isEmpty) {
      TopNotification.error(
        context,
        AppLocalizations.of(context)!.pleaseEnterYourTaxIdEin,
      );
      return false;
    }
    if (_businessStreetController.text.isEmpty) {
      TopNotification.error(
        context,
        AppLocalizations.of(context)!.pleaseEnterYourStreetName,
      );
      return false;
    }
    if (_businessHouseNumberController.text.isEmpty) {
      TopNotification.error(
        context,
        AppLocalizations.of(context)!.pleaseEnterYourHouseNumber,
      );
      return false;
    }
    if (_businessPostalCodeController.text.isEmpty) {
      TopNotification.error(
        context,
        AppLocalizations.of(context)!.pleaseEnterYourPostalCode,
      );
      return false;
    }
    if (_businessCityController.text.isEmpty) {
      TopNotification.error(
        context,
        AppLocalizations.of(context)!.pleaseEnterYourCity,
      );
      return false;
    }
    if (_businessCountryController.text.isEmpty) {
      TopNotification.error(
        context,
        AppLocalizations.of(context)!.pleaseEnterYourCountry,
      );
      return false;
    }
    // Check phone is not empty and has actual digits beyond country code
    final phoneDigits = _businessPhoneController.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (_businessPhoneController.text.isEmpty || phoneDigits.length < 7) {
      TopNotification.error(
        context,
        AppLocalizations.of(context)!.pleaseEnterYourBusinessPhone,
      );
      return false;
    }
    if (_businessEmailController.text.isEmpty) {
      TopNotification.error(
        context,
        AppLocalizations.of(context)!.pleaseEnterYourBusinessEmail,
      );
      return false;
    }
    final dunsDigits = _businessDunsController.text.replaceAll(RegExp(r'[^0-9]'), '');
    // DUNS is optional — only reject if something was entered but the length is wrong
    if (dunsDigits.isNotEmpty && dunsDigits.length != 9) {
      TopNotification.error(
        context,
        AppLocalizations.of(context)!.pleaseEnterValidDuns,
      );
      return false;
    }
    return true;
  }

  Future<void> _submitBusinessInfo(
    BuildContext sheetContext,
    String paymentType, {
    String? settlementType,
  }) async {
    setState(() => _isLoadingBusinessInfo = true);

    try {
      // ── Step 1: Check existing DB eligibility ──────────────────────────
      // (Realtime registry check is now done inline in the review page UI)
      final eligibilityResponse = await ApiService.checkBusinessEligibility(
        widget.accessToken,
        _businessTaxIdController.text,
        businessPhone: _businessPhoneController.text,
      );

      print('🏢 Business eligibility response: $eligibilityResponse');

      if (eligibilityResponse['status'] == 'approved') {
        // Already approved — place order immediately
        final businessData = eligibilityResponse['business'];
        _businessInfo = {
          'business_name': businessData['business_name'],
          'tax_id': businessData['tax_id'],
          'email': _businessEmailController.text,
          'phone': _businessPhoneController.text,
          'street': _businessStreetController.text,
          'house_number': _businessHouseNumberController.text,
          'postal_code': _businessPostalCodeController.text,
          'city': _businessCityController.text,
          'country': _businessCountryController.text,
          'duns_number': _businessDunsController.text.trim(),
          'verification_status': 'approved',
        };
        if (mounted) {
          Navigator.pop(sheetContext);
          await _processPaymentTermsPayment(
            paymentType,
            markAsPaid: true,
            settlementType: settlementType,
          );
        }
      } else {
        // ── Step 2: Full verification + DB write ──────────────────────────
        print('📝 Submitting full verification (status: ${eligibilityResponse['status']})...');

        final verificationResponse = await ApiService.submitBusinessVerification(
          accessToken:   widget.accessToken,
          businessName:  _businessNameController.text,
          taxId:         _businessTaxIdController.text,
          street:        _businessStreetController.text,
          houseNumber:   _businessHouseNumberController.text,
          postalCode:    _businessPostalCodeController.text,
          city:          _businessCityController.text,
          country:       _countryNameToCode(
                           _businessCountryController.text.isNotEmpty
                             ? _businessCountryController.text
                             : 'United States',
                         ),
          businessPhone: _businessPhoneController.text,
          businessEmail: _businessEmailController.text,
          dunsNumber:    _businessDunsController.text.trim(),
        );

        if (verificationResponse['success'] == true) {
          final status = (verificationResponse['status'] ?? '').toString();

          _businessInfo = {
            'business_name': _businessNameController.text,
            'tax_id': _businessTaxIdController.text,
            'email': _businessEmailController.text,
            'phone': _businessPhoneController.text,
            'street': _businessStreetController.text,
            'house_number': _businessHouseNumberController.text,
            'postal_code': _businessPostalCodeController.text,
            'city': _businessCityController.text,
            'country': _businessCountryController.text,
            'duns_number': _businessDunsController.text.trim(),
            'verification_status': status,
          };

          if (status == 'rejected') {
            if (mounted) {
              final emailSent = verificationResponse['email_sent'] == true;
              await _closeBusinessInfoSheetThenShow(sheetContext, () {
                _showVerificationRejectedDialog(
                  verificationResponse['message']?.toString() ??
                      'Business verification rejected.',
                  emailSent: emailSent,
                );
              });
            }
            return;
          }

          if (mounted) {
            Navigator.pop(sheetContext);
            await _processPaymentTermsPayment(
              paymentType,
              markAsPaid: status == 'approved',
              settlementType: settlementType,
            );
          }
        } else {
          if (mounted) {
            TopNotification.error(
              context,
              verificationResponse['message'] ??
                  AppLocalizations.of(context)!.failedToSubmitVerification,
            );
          }
        }
      }
    } catch (e) {
      print('❌ Error in business info submission: $e');
      if (mounted) {
        TopNotification.error(context, 'Error: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingBusinessInfo = false);
      }
    }
  }

  Future<void> _closeBusinessInfoSheetThenShow(BuildContext sheetContext, VoidCallback showDialog) async {
    if (!mounted) return;

    Navigator.of(sheetContext).pop();

    // Wait for the sheet close animation to finish before opening the next one.
    await Future<void>.delayed(const Duration(milliseconds: 240));

    if (!mounted) return;
    showDialog();
  }

  void _showVerificationRejectedDialog(
    String message, {
    required bool emailSent,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      isDismissible: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(CupertinoIcons.xmark_circle_fill, color: Colors.red, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Business Rejected',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(
              fontSize: 15,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            emailSent
                ? 'Check your email for details and next steps.'
                : 'Rejection email could not be sent. Please check mail configuration.',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: emailSent
                  ? (isDark ? Colors.white60 : Colors.black54)
                  : Colors.orange,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: TradeRepublicButton(
              label: AppLocalizations.of(context)!.ok,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }

  // Process payment terms payment after verification
  Future<void> _processPaymentTermsPayment(
    String paymentType, {
    bool markAsPaid = false,
    String? settlementType,
  }) async {
    try {
      print('💳 Processing payment terms payment for: $paymentType');

      final isNetTerms =
          paymentType == 'payment_30_days' || paymentType == 'payment_60_days';
      if (isNetTerms && settlementType == null) {
        throw Exception('Please choose ACH or SEPA before creating Net terms order.');
      }

        // Use explicit user choice for Net terms (fallback kept for safety)
        final selectedSettlement = (settlementType ?? '').toLowerCase();
        final fallbackCountry =
          (widget.currentUser?['country'] as String? ?? 'US').toUpperCase().trim();
        final autoSettlementType = _isSepaCountry(fallbackCountry) ? 'sepa' : 'ach';
        final effectiveSettlementType =
          (selectedSettlement == 'ach' || selectedSettlement == 'sepa')
          ? selectedSettlement
          : autoSettlementType;
        final userCountry = effectiveSettlementType == 'sepa' ? 'DE' : 'US';
        final virtualAccountPaymentType = effectiveSettlementType;
        print('🌍 Net settlement type: ${effectiveSettlementType.toUpperCase()}');

      // Generate virtual account based on country
      final virtualAccountResponse = await ApiService.generateVirtualAccount(
        widget.accessToken,
        virtualAccountPaymentType,
        _businessInfo!['business_name'],
        _businessInfo!['email'],
        userCountry,
      );

      if (virtualAccountResponse['success'] == true) {
        print('✅ Virtual account generated (type: ${virtualAccountResponse['type']})');

        // Create payment terms order with full account data
        await _createPaymentTermsOrder(
          paymentType,
          virtualAccountResponse,
          markAsPaid: markAsPaid,
        );
      } else {
        throw Exception('Failed to generate virtual account');
      }
    } catch (e) {
      print('❌ Error processing payment terms: $e');
      if (mounted) {
        TopNotification.error(context, 'Error: ${e.toString()}');
      }
    }
  }

  /// Returns true if the country is in the SEPA zone (EU + EEA + CH + GB + micro-states)
  bool _isSepaCountry(String countryCode) {
    const sepaCountries = {
      'DE','AT','FR','IT','ES','NL','BE','PT','FI','IE','GR',
      'SK','SI','EE','LV','LT','LU','MT','CY','HR','BG','RO',
      'CZ','HU','PL','DK','SE','NO','IS','LI','CH','GB','AD',
      'MC','SM','GI','VA',
    };
    return sepaCountries.contains(countryCode.toUpperCase());
  }

  // Build shipping selector for a specific item
  Widget _buildItemShippingSelector(
    int itemIndex,
    Map<String, dynamic>? product,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Get Incoterm from product
    final incoterm = product?['incoterm']?.toString().toUpperCase() ?? 'EXW';

    // Incoterm descriptions
    final incotermDescriptions = {
      'EXW': AppLocalizations.of(
        context,
      )!.exWorksSellerMakesGoodsAvailableAtTheirPre,
      'FCA': AppLocalizations.of(
        context,
      )!.freeCarrierSellerDeliversToCarrierAtNamedP,
      'CPT': AppLocalizations.of(
        context,
      )!.carriagePaidToSellerPaysFreightToDestinatio,
      'CIP': AppLocalizations.of(
        context,
      )!.carriageAndInsurancePaidSellerPaysFreightAn,
      'DAP': AppLocalizations.of(
        context,
      )!.deliveredAtPlaceSellerDeliversToNamedDestin,
      'DPU': AppLocalizations.of(
        context,
      )!.deliveredAtPlaceUnloadedSellerDeliversAndUn,
      'DDP': AppLocalizations.of(
        context,
      )!.deliveredDutyPaidSellerPaysAllCostsToDesti,
      'FAS': AppLocalizations.of(
        context,
      )!.freeAlongsideShipSellerDeliversAlongsideVess,
      'FOB': AppLocalizations.of(
        context,
      )!.freeOnBoardSellerDeliversGoodsOnBoardVesse,
      'CFR': AppLocalizations.of(
        context,
      )!.costAndFreightSellerPaysFreightToDestinatio,
      'CIF': AppLocalizations.of(
        context,
      )!.costInsuranceAndFreightSellerPaysFreightAnd,
    };

    final incotermDescription =
        incotermDescriptions[incoterm] ??
        AppLocalizations.of(context)!.standardDeliveryTerms;

    return TradeRepublicCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                CupertinoIcons.cube_box,
                color: isDark ? Colors.white70 : Colors.black54,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                AppLocalizations.of(context)!.shippingTerms,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? Colors.white : Colors.black,
              borderRadius: BorderRadius.circular(25),
            ),
            child: Text(
              incoterm,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.black : Colors.white,
                letterSpacing: 1.2,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            incotermDescription,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white60 : Colors.black54,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  // Cleaning Certificate Selector - shows only if seller offers cleaning certificate
  Widget _buildCleaningCertificateSelector(
    int itemIndex,
    Map<String, dynamic>? product,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Check if product offers cleaning certificate
    final offersCleaningCertificate =
        product?['offers_cleaning_certificate'] == 1 ||
        product?['offers_cleaning_certificate'] == true;

    if (!offersCleaningCertificate) {
      return const SizedBox.shrink(); // Don't show if not offered
    }

    final cleaningFee = (product?['cleaning_certificate_fee'] ?? 0).toDouble();
    final cleaningDescription =
        product?['cleaning_certificate_description'] as String? ??
        AppLocalizations.of(
          context,
        )!.driverMustCleanAndSanitizeTheTransportVehic;

    final requiresCleaning = _requiresCleaningPerItem[itemIndex] ?? false;

    return TradeRepublicCard(
      margin: const EdgeInsets.only(top: 16),
      border: requiresCleaning
          ? Border.all(color: Colors.green.withOpacity(0.5), width: 1)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: requiresCleaning
                      ? Colors.green.withOpacity(0.1)
                      : (isDark
                            ? Colors.white.withOpacity(0.1)
                            : Colors.black.withOpacity(0.05)),
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Icon(
                  CupertinoIcons.sparkles,
                  color: requiresCleaning
                      ? Colors.green
                      : (isDark ? Colors.white70 : Colors.black54),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.cleaningCertificate,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppLocalizations.of(
                        context,
                      )!.requireVehicleCleaningBeforeTransport,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              // Toggle Switch
              TradeRepublicSwitch(
                value: requiresCleaning,
                onChanged: (value) {
                  setState(() {
                    _requiresCleaningPerItem[itemIndex] = value;
                  });
                },
              ),
            ],
          ),

          // Show additional info when enabled
          if (requiresCleaning) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(25),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        CupertinoIcons.checkmark_seal,
                        color: Colors.green,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        AppLocalizations.of(context)!.cleaningRequired,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    cleaningDescription,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white70 : Colors.black87,
                      height: 1.4,
                    ),
                  ),
                  if (cleaningFee > 0) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          CupertinoIcons.money_euro,
                          color: isDark ? Colors.white60 : Colors.black54,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Additional fee: {currencySymbol}${cleaningFee.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],

          // Info text when disabled
          if (!requiresCleaning) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  CupertinoIcons.info,
                  color: isDark ? Colors.white38 : Colors.black38,
                  size: 14,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    cleaningFee > 0
                        ? 'Optional cleaning certificate (+\$${cleaningFee.toStringAsFixed(2)})'
                        : AppLocalizations.of(
                            context,
                          )!.optionalCleaningCertificateAvailable,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              Icon(
                CupertinoIcons.bag_fill,
                color: isDark ? Colors.white : Colors.black,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  AppLocalizations.of(context)!.checkout,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : Colors.black,
                    letterSpacing: -0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Step Indicator
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              Flexible(
                flex: 0,
                child: _buildStepIndicator(
                  0,
                  AppLocalizations.of(context)!.productInfo,
                  isDark,
                ),
              ),
              Expanded(
                child: Container(
                  height: 2,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: _currentStep >= 1
                        ? (isDark ? Colors.white : Colors.black)
                        : (isDark ? Colors.white : Colors.black).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(25),
                  ),
                ),
              ),
              Flexible(
                flex: 0,
                child: _buildStepIndicator(
                  1,
                  AppLocalizations.of(context)!.payment,
                  isDark,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        Expanded(
          child: PageView(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(),
            onPageChanged: (page) {
              setState(() => _currentStep = page);
            },
            children: [
              // Step 1: Product Info
              _buildStep1ProductInfo(isDark),

              // Step 2: Payment Method
              _buildStep2PaymentMethod(isDark),
            ],
          ),
        ),

        // Navigation Buttons
        Container(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          decoration: BoxDecoration(
            
            border: Border(
              top: BorderSide(
                color: (isDark ? Colors.white : Colors.black).withOpacity(0.1),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              if (_currentStep > 0) ...[
                Expanded(
                  child: TradeRepublicButton(
                    label: AppLocalizations.of(context)!.back,
                    isSecondary: true,
                    onPressed: () {
                      _pageController.previousPage(
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeInOutCubic,
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: TradeRepublicButton(
                  label: _currentStep == 0
                      ? AppLocalizations.of(context)!.continueToPayment
                      : AppLocalizations.of(context)!.completeOrder,
                  tint: isDark ? Colors.white : Colors.black,
                  isLoading: _isLoading,
                  onPressed: _isLoading
                      ? null
                      : () async {
                          if (_currentStep == 0) {
                            bool allAddressesSelected = true;
                            for (int i = 0; i < widget.cartItems.length; i++) {
                              if (_selectedAddressPerItem[i] == null) {
                                allAddressesSelected = false;
                                break;
                              }
                            }

                            if (!allAddressesSelected) {
                              TopNotification.error(
                                context,
                                AppLocalizations.of(
                                  context,
                                )!.pleaseSelectDeliveryAddressForAllItems,
                              );
                              return;
                            }

                            final approvalRequired =
                                await _checkGroupApprovalRequired();

                            if (approvalRequired) {
                              return;
                            }

                            _pageController.nextPage(
                              duration: const Duration(milliseconds: 400),
                              curve: Curves.easeInOutCubic,
                            );
                          } else {
                            _processPayment();
                          }
                        },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Build Step Indicator
  Widget _buildStepIndicator(int step, String label, bool isDark) {
    final isActive = _currentStep == step;
    final isCompleted = _currentStep > step;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: isCompleted
                ? Colors.green.shade500
                : isActive
                ? (isDark ? Colors.white : Colors.black)
                : (isDark ? Colors.white : Colors.black).withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(
              color: isCompleted
                  ? Colors.green.shade500
                  : isActive
                  ? (isDark ? Colors.white : Colors.black)
                  : (isDark ? Colors.white : Colors.black).withOpacity(0.2),
              width: 2,
            ),
          ),
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) {
                return ScaleTransition(scale: animation, child: child);
              },
              child: isCompleted
                  ? const Icon(
                      CupertinoIcons.checkmark,
                      color: Colors.white,
                      size: 18,
                      key: ValueKey('check'),
                    )
                  : Text(
                      '${step + 1}',
                      key: ValueKey('number_$step'),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isActive
                            ? (isDark ? Colors.black : Colors.white)
                            : (isDark ? Colors.white : Colors.black)
                                  .withOpacity(0.5),
                      ),
                    ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
              color: isActive
                  ? (isDark ? Colors.white : Colors.black)
                  : (isDark ? Colors.white : Colors.black).withOpacity(0.5),
            ),
            child: Text(label, overflow: TextOverflow.ellipsis, maxLines: 1),
          ),
        ),
      ],
    );
  }

  // Step 1: Product Info (Addresses, Shipping, etc.)
  Widget _buildStep1ProductInfo(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Order Summary Header
          TradeRepublicSectionHeader(
            title: AppLocalizations.of(context)!.orderSummary,
          ),
          const SizedBox(height: 8),

          // Per-item configuration sections
          ...List.generate(widget.cartItems.length, (index) {
            return Column(
              children: [
                _buildItemCheckoutSection(index),
                if (index < widget.cartItems.length - 1)
                  const SizedBox(height: 24),
              ],
            );
          }),

          const SizedBox(height: 24),

          // Order Summary
          _buildOrderSummary(),

          // Group card (shown if user is member of a group)
          if (_userGroup != null) ...[            const SizedBox(height: 24),
            _buildGroupCard(isDark),
          ],

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // Group membership card
  Widget _buildGroupCard(bool isDark) {
    if (_userGroup == null) return const SizedBox.shrink();
    final group = _userGroup!;
    final groupName = group['name']?.toString() ?? '';
    final myRole = group['my_role']?.toString() ?? 'member';
    final memberCount = group['member_count'] ?? 0;
    final requiresApproval =
        group['i_require_approval'] == 1 ||
        group['i_require_approval'] == true;
    final initial =
        groupName.isNotEmpty ? groupName.substring(0, 1).toUpperCase() : 'G';

    const groupColors = [
      Color(0xFF007AFF),
      Color(0xFF34C759),
      Color(0xFFFF9500),
      Color(0xFF5856D6),
      Color(0xFFFF2D55),
      Color(0xFF00C7BE),
    ];
    final accentColor =
        groupColors[initial.codeUnitAt(0) % groupColors.length];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TradeRepublicSectionHeader(title: AppLocalizations.of(context)!.groups),
        const SizedBox(height: 8),
        TradeRepublicCard(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(
                    initial,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: accentColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      groupName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$memberCount ${AppLocalizations.of(context)!.member} · ${myRole == 'admin' ? AppLocalizations.of(context)!.admin : AppLocalizations.of(context)!.member}',
                      style: TextStyle(
                        fontSize: 13,
                        color: (isDark ? Colors.white : Colors.black)
                            .withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ),
              if (requiresApproval)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        CupertinoIcons.clock,
                        size: 12,
                        color: Colors.orange,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        AppLocalizations.of(context)!.approvalRequired,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.orange,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // Step 2: Payment Method
  Widget _buildStep2PaymentMethod(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Payment method
          TradeRepublicSectionHeader(
            title: AppLocalizations.of(context)!.paymentMethod,
          ),
          const SizedBox(height: 8),
          _buildPaymentMethodSelector(),
          const SizedBox(height: 24),

          // Saved cards selector
          _buildSavedCardsSelector(),
          const SizedBox(height: 24),

          // Credit card form
          _buildCreditCardForm(),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// Separate StatefulWidget for Net Payment Sheet with page navigation
class _NetPaymentSheetContent extends StatefulWidget {
  final bool isDark;
  final String title;
  final String description;
  final int? days;
  final double totalWithShipping;
  final double remainingLimit;
  final bool isOverLimit;
  final double overLimitFee;
  final String paymentType;
  final TextEditingController businessNameController;
  final TextEditingController businessTaxIdController;
  final TextEditingController businessEmailController;
  final TextEditingController businessPhoneController;
  final TextEditingController businessStreetController;
  final TextEditingController businessHouseNumberController;
  final TextEditingController businessPostalCodeController;
  final TextEditingController businessCityController;
  final TextEditingController businessCountryController;
  final TextEditingController businessDunsController;
  final bool isLoadingBusinessInfo;
  final String Function(double) formatCurrency;
  final double weeklyPaymentLimit;
  final double currentWeekUsage;
  final double overLimitFeePercent;
  final bool Function() validateBusinessInfo;
  final Future<void> Function(BuildContext, String, {String? settlementType}) submitBusinessInfo;
  final Widget Function({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required bool isDark,
    int maxLines,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  })
  buildBusinessTextField;
  final Widget Function(String, String, bool) buildInfoRow;
  final VoidCallback onClose;

  const _NetPaymentSheetContent({
    required this.isDark,
    required this.title,
    required this.description,
    required this.days,
    required this.totalWithShipping,
    required this.remainingLimit,
    required this.isOverLimit,
    required this.overLimitFee,
    required this.paymentType,
    required this.businessNameController,
    required this.businessTaxIdController,
    required this.businessEmailController,
    required this.businessPhoneController,
    required this.businessStreetController,
    required this.businessHouseNumberController,
    required this.businessPostalCodeController,
    required this.businessCityController,
    required this.businessCountryController,
    required this.businessDunsController,
    required this.isLoadingBusinessInfo,
    required this.formatCurrency,
    required this.weeklyPaymentLimit,
    required this.currentWeekUsage,
    required this.overLimitFeePercent,
    required this.validateBusinessInfo,
    required this.submitBusinessInfo,
    required this.buildBusinessTextField,
    required this.buildInfoRow,
    required this.onClose,
  });

  @override
  State<_NetPaymentSheetContent> createState() =>
      _NetPaymentSheetContentState();
}

// ── Inline business verification state ─────────────────────────────────────
enum _BizVerifyUIState { idle, loading, autoApproved, needsConfirm, confirmed }

class _NetPaymentSheetContentState extends State<_NetPaymentSheetContent> {
  int _currentPage = 0; // 0 = overview, 1 = business form, 2 = review & confirm
  final PageController _pageController = PageController();

  // Inline verification state for the review page
  _BizVerifyUIState _verifyUIState = _BizVerifyUIState.idle;
  Map<String, dynamic>? _verifyResult;
  String? _selectedSettlementType; // ach | sepa (required for Net30/60)

  bool get _needsSettlementChoice =>
      widget.paymentType == 'payment_30_days' ||
      widget.paymentType == 'payment_60_days';

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToPage(int page) {
    setState(() => _currentPage = page);
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOut,
    );
  }

  void _showCountrySelector(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final countries = [
      {'code': 'US', 'name': 'United States', 'flag': '🇺🇸', 'phone': '+1'},
      {'code': 'DE', 'name': 'Germany', 'flag': '🇩🇪', 'phone': '+49'},
      {'code': 'GB', 'name': 'United Kingdom', 'flag': '🇬🇧', 'phone': '+44'},
      {'code': 'FR', 'name': 'France', 'flag': '🇫🇷', 'phone': '+33'},
      {'code': 'ES', 'name': 'Spain', 'flag': '🇪🇸', 'phone': '+34'},
      {'code': 'IT', 'name': 'Italy', 'flag': '🇮🇹', 'phone': '+39'},
      {'code': 'NL', 'name': 'Netherlands', 'flag': '🇳🇱', 'phone': '+31'},
      {'code': 'BE', 'name': 'Belgium', 'flag': '🇧🇪', 'phone': '+32'},
      {'code': 'AT', 'name': 'Austria', 'flag': '🇦🇹', 'phone': '+43'},
      {'code': 'CH', 'name': 'Switzerland', 'flag': '🇨🇭', 'phone': '+41'},
      {'code': 'PL', 'name': 'Poland', 'flag': '🇵🇱', 'phone': '+48'},
      {'code': 'SE', 'name': 'Sweden', 'flag': '🇸🇪', 'phone': '+46'},
      {'code': 'NO', 'name': 'Norway', 'flag': '🇳🇴', 'phone': '+47'},
      {'code': 'DK', 'name': 'Denmark', 'flag': '🇩🇰', 'phone': '+45'},
      {'code': 'FI', 'name': 'Finland', 'flag': '🇫🇮', 'phone': '+358'},
      {'code': 'CA', 'name': 'Canada', 'flag': '🇨🇦', 'phone': '+1'},
      {'code': 'AU', 'name': 'Australia', 'flag': '🇦🇺', 'phone': '+61'},
      {'code': 'NZ', 'name': 'New Zealand', 'flag': '🇳🇿', 'phone': '+64'},
      {'code': 'JP', 'name': 'Japan', 'flag': '🇯🇵', 'phone': '+81'},
      {'code': 'SG', 'name': 'Singapore', 'flag': '🇸🇬', 'phone': '+65'},
    ];

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      maxHeight: MediaQuery.of(context).size.height * 0.7,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Text(
              AppLocalizations.of(context)!.selectCountry,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ),
          Divider(height: 1, color: isDark ? Colors.white12 : Colors.black12),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: countries.length,
              itemBuilder: (context, index) {
                final country = countries[index];
                final isSelected = widget.businessCountryController.text == country['name'];
                return TradeRepublicListTile(
                  title: '${country['flag']} ${country['name']}',
                  backgroundColor: isSelected
                      ? TradeRepublicTheme.selectionContainerBackground(context)
                      : null,
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  trailing: isSelected
                      ? Icon(
                          CupertinoIcons.checkmark_circle_fill,
                          color: TradeRepublicTheme.selectionContainerForeground(
                            context,
                          ),
                          size: 20,
                        )
                      : null,
                  onTap: () {
                    setState(() {
                      widget.businessCountryController.text = country['name'] as String;
                      // Pre-fill phone with country code only if phone is empty or just a country code
                      final phoneCode = country['phone'] as String;
                      final currentPhone = widget.businessPhoneController.text.replaceAll(RegExp(r'[^0-9+]'), '');
                      // Only overwrite if empty or very short (just a country code, <=4 chars like +1, +49, +358)
                      if (currentPhone.isEmpty || currentPhone.length <= 4) {
                        widget.businessPhoneController.text = phoneCode;
                      }
                      // Clear tax ID when country changes (different formats)
                      widget.businessTaxIdController.clear();
                    });
                    Navigator.of(context).pop();
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _getCountryCode(String countryName) {
    final countryMap = {
      'United States': 'US',
      'Germany': 'DE',
      'United Kingdom': 'GB',
      'France': 'FR',
      'Spain': 'ES',
      'Italy': 'IT',
      'Netherlands': 'NL',
      'Belgium': 'BE',
      'Austria': 'AT',
      'Switzerland': 'CH',
      'Poland': 'PL',
      'Sweden': 'SE',
      'Norway': 'NO',
      'Denmark': 'DK',
      'Finland': 'FI',
      'Canada': 'CA',
      'Australia': 'AU',
      'New Zealand': 'NZ',
      'Japan': 'JP',
      'Singapore': 'SG',
    };
    return countryMap[countryName] ?? 'US';
  }

  String _getTaxIdHint(String countryName) {
    final hintMap = {
      'United States': 'XX-XXXXXXX',
      'Canada': 'XX-XXXXXXX',
      'Germany': 'XXX/XXXX/XXXX',
      'United Kingdom': 'XXXXX XXXXX',
      'France': 'XXX XXX XXX',
      'Netherlands': 'XXXXXXXXXXBXX',
      'Switzerland': 'CHE-XXX.XXX.XXX',
    };
    return hintMap[countryName] ?? 'Tax ID';
  }

  // ── Business verification helpers ────────────────────────────────────────
  Future<void> _runVerification() async {
    if (!mounted) return;
    if (_needsSettlementChoice && _selectedSettlementType == null) {
      TopNotification.error(
        context,
        'Please choose ACH or SEPA for Net invoice settlement.',
      );
      return;
    }
    setState(() {
      _verifyUIState = _BizVerifyUIState.loading;
      _verifyResult = null;
    });

    final result = await ApiService.verifyBusinessRealtime(
      businessName: widget.businessNameController.text,
      taxId:        widget.businessTaxIdController.text,
      postalCode:   widget.businessPostalCodeController.text,
      city:         widget.businessCityController.text,
      country:      _getCountryCode(
                      widget.businessCountryController.text.isNotEmpty
                        ? widget.businessCountryController.text
                        : 'United States',
                    ),
      dunsNumber:   widget.businessDunsController.text,
    );

    if (!mounted) return;

    final confidence = result['confidence'] as String? ?? 'unavailable';
    final isSmallPrivate = result['checks']?['smallPrivateFallback'] == true;
    final isAutoApprove = confidence == 'high' ||
        confidence == 'unavailable' ||
        (confidence == 'low' && isSmallPrivate);

    setState(() {
      _verifyResult = result;
      _verifyUIState = isAutoApprove
          ? _BizVerifyUIState.autoApproved
          : _BizVerifyUIState.needsConfirm;
    });

    if (isAutoApprove && widget.validateBusinessInfo()) {
      await widget.submitBusinessInfo(
        context,
        widget.paymentType,
        settlementType: _selectedSettlementType,
      );
    }
  }

  Widget _buildVerifyResultCard() {
    final result = _verifyResult!;
    final confidence = result['confidence'] as String? ?? 'unavailable';
    final foundName = result['foundName'] as String? ?? '';
    final jurisdiction = result['jurisdiction'] as String? ?? '';
    final isSmallPrivate = result['checks']?['smallPrivateFallback'] == true;
    final isDark = widget.isDark;
    final textColor = isDark ? Colors.white : Colors.black;

    Color borderColor;
    Color bgColor;
    String icon;
    String title;
    String detail;
    bool showButtons = false;
    String proceedLabel = 'Proceed';

    if (confidence == 'high') {
      borderColor = const Color(0xFF28a745);
      bgColor = isDark ? const Color(0xFF0D2B14) : const Color(0xFFF0FFF4);
      icon = '✅';
      title = 'Business verified';
      detail = foundName.isNotEmpty
          ? 'Found as "$foundName"${jurisdiction.isNotEmpty ? " · ${jurisdiction.toUpperCase()}" : ""}'
          : 'Your business was confirmed in the registry.';
    } else if (confidence == 'medium') {
      borderColor = const Color(0xFF17a2b8);
      bgColor = isDark ? const Color(0xFF0A2030) : const Color(0xFFF0FAFF);
      icon = '🔎';
      title = 'Close match found — please confirm';
      detail = foundName.isNotEmpty
          ? 'Closest registry match:\n"$foundName"\n\nIs this your company?'
          : 'A close match was found. Please confirm before proceeding.';
      showButtons = true;
      proceedLabel = 'Yes, place order';
    } else if (confidence == 'low' && isSmallPrivate) {
      borderColor = const Color(0xFFfd7e14);
      bgColor = isDark ? const Color(0xFF2A1800) : const Color(0xFFFFF8F0);
      icon = '📋';
      title = 'Small private business';
      detail = 'Your EIN and ZIP code are valid. Small private businesses are often not in public databases — your order will be reviewed within 1 business day.';
    } else if (confidence == 'low') {
      borderColor = const Color(0xFFfd7e14);
      bgColor = isDark ? const Color(0xFF2A1800) : const Color(0xFFFFF8F0);
      icon = '⚠️';
      title = 'Name doesn\'t match closely';
      detail = foundName.isNotEmpty
          ? 'Closest registry match:\n"$foundName"\n\nCheck your company name and Tax ID. You may still proceed with manual review.'
          : 'Low-confidence match. Your order will require manual review before credit terms are granted.';
      showButtons = true;
      proceedLabel = 'Proceed (manual review)';
    } else if (confidence == 'not_found') {
      final einOk = result['einValid'] == true;
      final zipOk = result['zipValid'] == true;
      final issues = [
        if (!einOk) 'EIN format invalid',
        if (!zipOk) 'ZIP code not found',
      ].join(' · ');
      borderColor = const Color(0xFFdc3545);
      bgColor = isDark ? const Color(0xFF2A0A0A) : const Color(0xFFFFF5F5);
      icon = '❌';
      title = 'Could not validate business';
      detail = issues.isNotEmpty
          ? '$issues\n\nPlease double-check your details. You may still proceed — credit terms will require manual review.'
          : 'Business not found in US/EU registries. You may proceed — your application will require manual review.';
      showButtons = true;
      proceedLabel = 'Proceed (manual review)';
    } else {
      // unavailable
      borderColor = const Color(0xFFaaaaaa);
      bgColor = isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF8F9FA);
      icon = '⚠️';
      title = 'Verification service unavailable';
      detail = 'Could not reach verification databases. Your order will be processed but may require manual review.';
    }

    final bool isSubmitting = _verifyUIState == _BizVerifyUIState.confirmed;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(icon, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      detail,
                      style: TextStyle(
                        fontSize: 13,
                        color: textColor.withOpacity(0.72),
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (showButtons) ...[  
            const SizedBox(height: 14),
            if (isSubmitting)
              const Center(child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: CupertinoActivityIndicator(),
              ))
            else
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _verifyUIState = _BizVerifyUIState.idle;
                          _verifyResult = null;
                        });
                        _goToPage(1);
                      },
                      child: Container(
                        height: 44,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withOpacity(0.08)
                              : Colors.black.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'Edit details',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: textColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        if (_needsSettlementChoice && _selectedSettlementType == null) {
                          TopNotification.error(
                            context,
                            'Please choose ACH or SEPA for Net invoice settlement.',
                          );
                          return;
                        }
                        setState(() => _verifyUIState = _BizVerifyUIState.confirmed);
                        if (widget.validateBusinessInfo()) {
                          await widget.submitBusinessInfo(
                            context,
                            widget.paymentType,
                            settlementType: _selectedSettlementType,
                          );
                        }
                      },
                      child: Container(
                        height: 44,
                        decoration: BoxDecoration(
                          color: borderColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          proceedLabel,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }

  // ── Step indicator ──────────────────────────────────────────────────────────
  Widget _buildStepIndicator() {
    const steps = 3;
    final textColor = widget.isDark ? Colors.white : Colors.black;
    final inactiveColor = widget.isDark ? Colors.white24 : Colors.black12;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      child: Row(
        children: List.generate(steps, (i) {
          final isActive = i == _currentPage;
          final isDone = i < _currentPage;
          return Expanded(
            child: Row(
              children: [
                // Circle
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: isActive || isDone ? textColor : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isActive || isDone ? textColor : inactiveColor,
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: isDone
                        ? Icon(CupertinoIcons.checkmark, size: 13,
                            color: widget.isDark ? Colors.black : Colors.white)
                        : Text(
                            '${i + 1}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isActive
                                  ? (widget.isDark ? Colors.black : Colors.white)
                                  : inactiveColor,
                            ),
                          ),
                  ),
                ),
                // Connector line (not after last step)
                if (i < steps - 1)
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      height: 1.5,
                      color: i < _currentPage ? textColor : inactiveColor,
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepIndicator(),
        Expanded(
          child: PageView(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _buildOverviewPage(),
              _buildBusinessFormPage(),
              _buildReviewPage(),
            ],
          ),
        ),
      ],
    );
  }

  // ── PAGE 0: Overview ────────────────────────────────────────────────────────
  Widget _buildOverviewPage() {
    final textColor = widget.isDark ? Colors.white : Colors.black;
    final subtleColor = widget.isDark ? Colors.white54 : Colors.black45;
    final days = widget.days ?? 30;

    // Due date
    final dueDate = DateTime.now().add(Duration(days: days));
    final dueDateStr =
        '${dueDate.day}.${dueDate.month.toString().padLeft(2, '0')}.${dueDate.year}';

    // Credit usage progress
    final usageRatio = (widget.weeklyPaymentLimit > 0)
        ? (widget.currentWeekUsage / widget.weeklyPaymentLimit).clamp(0.0, 1.0)
        : 0.0;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Hero ──────────────────────────────────────────────────
                Text(
                  widget.title,
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    color: textColor,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.description,
                  style: TextStyle(fontSize: 15, color: subtleColor),
                ),
                const SizedBox(height: 28),

                // ── Order summary card ─────────────────────────────────
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                  decoration: BoxDecoration(
                    color: widget.isDark
                        ? Colors.white.withOpacity(0.07)
                        : Colors.black.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    children: [
                      _overviewRow(
                        AppLocalizations.of(context)!.orderTotal,
                        widget.formatCurrency(widget.totalWithShipping),
                        textColor,
                        subtleColor,
                        valueBold: true,
                      ),
                      const SizedBox(height: 14),
                      _overviewRow(
                        AppLocalizations.of(context)!.paymentDue,
                        dueDateStr,
                        textColor,
                        subtleColor,
                        valueBold: true,
                        valueColor: textColor,
                      ),
                      if (widget.isOverLimit) ...[
                        const SizedBox(height: 14),
                        _overviewRow(
                          'Over-limit fee (${widget.overLimitFeePercent.toStringAsFixed(0)}%)',
                          '+${widget.formatCurrency(widget.overLimitFee)}',
                          textColor,
                          subtleColor,
                          valueColor: Colors.orange,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ── Credit usage bar ──────────────────────────────────
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          AppLocalizations.of(context)!.creditLimit,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: subtleColor,
                          ),
                        ),
                        Text(
                          '${widget.formatCurrency(widget.remainingLimit)} ${AppLocalizations.of(context)!.available}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: textColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: usageRatio,
                        minHeight: 6,
                        backgroundColor: widget.isDark
                            ? Colors.white12
                            : Colors.black12,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          usageRatio > 0.8
                              ? Colors.orange
                              : (widget.isDark ? Colors.white : Colors.black),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${widget.formatCurrency(widget.currentWeekUsage)} of ${widget.formatCurrency(widget.weeklyPaymentLimit)} used this week',
                      style: TextStyle(fontSize: 12, color: subtleColor),
                    ),
                  ],
                ),
                const SizedBox(height: 28),

                // ── How it works ─────────────────────────────────────
                Text(
                  'How it works',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 14),
                _howItWorksStep(
                  icon: CupertinoIcons.cart_fill,
                  title: AppLocalizations.of(context)!.orderToday,
                  subtitle: 'Place your order and receive your goods immediately.',
                  textColor: textColor,
                  subtleColor: subtleColor,
                ),
                const SizedBox(height: 12),
                _howItWorksStep(
                  icon: CupertinoIcons.doc_text_fill,
                  title: AppLocalizations.of(context)!.invoiceIssued,
                  subtitle: 'You\'ll receive an invoice with payment due in $days days.',
                  textColor: textColor,
                  subtleColor: subtleColor,
                ),
                const SizedBox(height: 12),
                _howItWorksStep(
                  icon: CupertinoIcons.checkmark_seal_fill,
                  title: AppLocalizations.of(context)!.payBy(dueDateStr),
                  subtitle: 'Transfer payment via bank transfer or ACH within the period.',
                  textColor: textColor,
                  subtleColor: subtleColor,
                ),
                const SizedBox(height: 28),

                // ── Late payment – compact ────────────────────────────
                Text(
                  AppLocalizations.of(context)!.latePaymentConsequences,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 12),
                _lateFeeRow('Day $days', AppLocalizations.of(context)!.paymentReminder, '+5%', Colors.orange, subtleColor, textColor),
                _dividerThin(),
                _lateFeeRow('Day ${days + 2}', AppLocalizations.of(context)!.accountSuspended, '+15%', Colors.red, subtleColor, textColor),
                _dividerThin(),
                _lateFeeRow('Day ${days + 4}', AppLocalizations.of(context)!.legalAction, AppLocalizations.of(context)!.lawsuitFiled, Colors.red.shade700, subtleColor, textColor),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),

        // ── Bottom CTA ────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            children: [
              Text(
                AppLocalizations.of(context)!.byContinuingYouAgreeToTheseTerms,
                style: TextStyle(fontSize: 12, color: subtleColor),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              TradeRepublicButton(
                label: AppLocalizations.of(context)!.continueButton,
                onPressed: () => _goToPage(1),
                width: double.infinity,
                height: 56,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _overviewRow(
    String label,
    String value,
    Color textColor,
    Color subtleColor, {
    bool valueBold = false,
    Color? valueColor,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(fontSize: 14, color: subtleColor, fontWeight: FontWeight.w500)),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            color: valueColor ?? textColor,
            fontWeight: valueBold ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _howItWorksStep({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color textColor,
    required Color subtleColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: widget.isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.06),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 18, color: textColor),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: textColor)),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(fontSize: 13, color: subtleColor, height: 1.4)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _lateFeeRow(String day, String label, String penalty, Color penaltyColor, Color subtleColor, Color textColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 58,
            child: Text(day, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: penaltyColor)),
          ),
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 14, color: textColor)),
          ),
          Text(
            penalty,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: penaltyColor),
          ),
        ],
      ),
    );
  }

  Widget _dividerThin() {
    return Divider(
      height: 1,
      color: widget.isDark ? Colors.white10 : Colors.black12,
    );
  }

  // ── PAGE 2: Review & Confirm ─────────────────────────────────────────────────
  Widget _buildReviewPage() {
    final textColor = widget.isDark ? Colors.white : Colors.black;
    final subtleColor = widget.isDark ? Colors.white54 : Colors.black45;
    final days = widget.days ?? 30;
    final dueDate = DateTime.now().add(Duration(days: days));
    final dueDateStr =
        '${dueDate.day}.${dueDate.month.toString().padLeft(2, '0')}.${dueDate.year}';

    Widget reviewRow(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(fontSize: 14, color: subtleColor, fontWeight: FontWeight.w500)),
          Flexible(
            child: Text(
              value,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor),
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );

    Widget reviewDivider() =>
        Divider(height: 1, color: widget.isDark ? Colors.white10 : Colors.black12);

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Review & Confirm',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: textColor,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Please review your order and business details before confirming.',
                  style: TextStyle(fontSize: 14, color: subtleColor),
                ),
                const SizedBox(height: 24),

                // ── Order details block ────────────────────────────
                _reviewSectionTitle('Order', textColor),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: widget.isDark
                        ? Colors.white.withOpacity(0.06)
                        : Colors.black.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    children: [
                      reviewRow(AppLocalizations.of(context)!.orderTotal,
                          widget.formatCurrency(widget.totalWithShipping)),
                      reviewDivider(),
                      reviewRow('Payment terms', widget.title),
                      if (_needsSettlementChoice) ...[
                        reviewDivider(),
                        reviewRow(
                          'Settlement rail',
                          (_selectedSettlementType ?? 'Not selected').toUpperCase(),
                        ),
                      ],
                      reviewDivider(),
                      reviewRow('Due date', dueDateStr),
                      if (widget.isOverLimit) ...[
                        reviewDivider(),
                        reviewRow(
                            'Over-limit fee',
                            '+${widget.formatCurrency(widget.overLimitFee)}'),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ── Business details block ─────────────────────────
                _reviewSectionTitle(AppLocalizations.of(context)!.businessInformation, textColor),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: widget.isDark
                        ? Colors.white.withOpacity(0.06)
                        : Colors.black.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    children: [
                      if (widget.businessNameController.text.isNotEmpty) ...[
                        reviewRow(AppLocalizations.of(context)!.businessName,
                            widget.businessNameController.text),
                        reviewDivider(),
                      ],
                      if (widget.businessTaxIdController.text.isNotEmpty) ...[
                        reviewRow(AppLocalizations.of(context)!.taxIdEin,
                            widget.businessTaxIdController.text),
                        reviewDivider(),
                      ],
                      if (widget.businessEmailController.text.isNotEmpty) ...[
                        reviewRow(AppLocalizations.of(context)!.businessEmail,
                            widget.businessEmailController.text),
                        reviewDivider(),
                      ],
                      if (widget.businessPhoneController.text.isNotEmpty) ...[
                        reviewRow(AppLocalizations.of(context)!.businessPhone,
                            widget.businessPhoneController.text),
                        reviewDivider(),
                      ],
                      reviewRow(
                        AppLocalizations.of(context)!.sectionAddress,
                        [
                          widget.businessStreetController.text,
                          widget.businessHouseNumberController.text,
                          widget.businessPostalCodeController.text,
                          widget.businessCityController.text,
                          widget.businessCountryController.text,
                        ].where((s) => s.isNotEmpty).join(', '),
                      ),
                      if (widget.businessDunsController.text.isNotEmpty) ...[
                        reviewDivider(),
                        reviewRow('D-U-N-S®', widget.businessDunsController.text),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                if (_needsSettlementChoice) ...[
                  _reviewSectionTitle('Settlement account', textColor),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: widget.isDark
                          ? Colors.white.withOpacity(0.06)
                          : Colors.black.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TradeRepublicButton(
                            label: AppLocalizations.of(context)!.achTab,
                            onPressed: () {
                              setState(() => _selectedSettlementType = 'ach');
                            },
                            isSecondary: _selectedSettlementType != 'ach',
                            height: 44,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TradeRepublicButton(
                            label: AppLocalizations.of(context)!.sepaTab,
                            onPressed: () {
                              setState(() => _selectedSettlementType = 'sepa');
                            },
                            isSecondary: _selectedSettlementType != 'sepa',
                            height: 44,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // ── Verification notice ────────────────────────────
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: widget.isDark
                        ? Colors.white.withOpacity(0.05)
                        : Colors.black.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(CupertinoIcons.shield_lefthalf_fill,
                          size: 16, color: subtleColor),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Your business details will be verified before your order is confirmed. You\'ll receive a confirmation email once approved.',
                          style: TextStyle(
                              fontSize: 12, color: subtleColor, height: 1.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Verification card + action buttons ────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            children: [
              // Loading indicator while verifying
              if (_verifyUIState == _BizVerifyUIState.loading)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: widget.isDark
                        ? Colors.white.withOpacity(0.06)
                        : Colors.black.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      const CupertinoActivityIndicator(),
                      const SizedBox(width: 12),
                      Text(
                        'Checking business registries…',
                        style: TextStyle(
                          fontSize: 14,
                          color: widget.isDark ? Colors.white70 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              // Result card (shown after verification)
              if (_verifyResult != null) _buildVerifyResultCard(),
              // Main CTA button — shown only when idle, autoApproved or confirmed
              if (_verifyUIState == _BizVerifyUIState.idle)
                TradeRepublicButton(
                  label: AppLocalizations.of(context)!.verifyAndPlaceOrder,
                  onPressed: _runVerification,
                  width: double.infinity,
                  height: 56,
                )
              else if (_verifyUIState == _BizVerifyUIState.autoApproved ||
                       _verifyUIState == _BizVerifyUIState.confirmed)
                TradeRepublicButton(
                  label: AppLocalizations.of(context)!.placingOrder,
                  onPressed: null,
                  isLoading: true,
                  width: double.infinity,
                  height: 56,
                ),
              // Edit link — only when idle or needsConfirm
              if (_verifyUIState == _BizVerifyUIState.idle ||
                  _verifyUIState == _BizVerifyUIState.needsConfirm) ...[  
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () => _goToPage(1),
                  child: Text(
                    'Edit business information',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: subtleColor,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _reviewSectionTitle(String title, Color textColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: textColor.withOpacity(0.4),
        ),
      ),
    );
  }

  // ── PAGE 1: Business Form ────────────────────────────────────────────────────
  Widget _buildBusinessFormPage() {
    final textColor = widget.isDark ? Colors.white : Colors.black;
    final subtleColor = widget.isDark ? Colors.white54 : Colors.black45;

    // Section header row
    Widget sectionLabel(String title, IconData icon) => Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Row(
        children: [
          Icon(icon, size: 13, color: subtleColor),
          const SizedBox(width: 6),
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: subtleColor,
            ),
          ),
        ],
      ),
    );

    // Card wrapper for a group of fields
    Widget sectionCard(List<Widget> children) => Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      decoration: BoxDecoration(
        color: widget.isDark
            ? Colors.white.withOpacity(0.06)
            : Colors.black.withOpacity(0.04),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );

    Widget fieldPad(Widget child) =>
        Padding(padding: const EdgeInsets.only(bottom: 12), child: child);

    return Column(
      children: [
        // ── Header ──────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 16, 0),
          child: Row(
            children: [
              IconButton(
                onPressed: () => _goToPage(0),
                icon: Icon(CupertinoIcons.arrow_left, color: textColor),
              ),
              Expanded(
                child: Text(
                  AppLocalizations.of(context)!.businessInformation,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── Scrollable form content ──────────────────────────────
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // ── 1. Company ─────────────────────────────────
                sectionLabel(AppLocalizations.of(context)!.sectionCompany, CupertinoIcons.building_2_fill),
                sectionCard([
                  fieldPad(widget.buildBusinessTextField(
                    controller: widget.businessNameController,
                    label: AppLocalizations.of(context)!.businessName,
                    hint: AppLocalizations.of(context)!.enterYourRegisteredBusinessName,
                    icon: CupertinoIcons.building_2_fill,
                    isDark: widget.isDark,
                  )),
                  widget.buildBusinessTextField(
                    controller: widget.businessTaxIdController,
                    label: AppLocalizations.of(context)!.taxIdEin,
                    hint: _getTaxIdHint(widget.businessCountryController.text),
                    icon: CupertinoIcons.number,
                    isDark: widget.isDark,
                    keyboardType: TextInputType.text,
                    inputFormatters: [
                      _TaxIdFormatter(
                        _getCountryCode(widget.businessCountryController.text),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ]),

                // ── 2. Contact ─────────────────────────────────
                sectionLabel(AppLocalizations.of(context)!.sectionContact, CupertinoIcons.person),
                sectionCard([
                  fieldPad(widget.buildBusinessTextField(
                    controller: widget.businessEmailController,
                    label: AppLocalizations.of(context)!.businessEmail,
                    hint: 'accounting@business.com',
                    icon: CupertinoIcons.mail,
                    isDark: widget.isDark,
                    keyboardType: TextInputType.emailAddress,
                  )),
                  widget.buildBusinessTextField(
                    controller: widget.businessPhoneController,
                    label: AppLocalizations.of(context)!.businessPhone,
                    hint: '+1 (555) 123-4567',
                    icon: CupertinoIcons.phone,
                    isDark: widget.isDark,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [_PhoneNumberFormatter()],
                  ),
                  const SizedBox(height: 12),
                ]),

                // ── 3. Address ─────────────────────────────────
                sectionLabel(AppLocalizations.of(context)!.sectionAddress, CupertinoIcons.location),
                sectionCard([
                  // Street + House Number in a row
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: widget.buildBusinessTextField(
                            controller: widget.businessStreetController,
                            label: AppLocalizations.of(context)!.street,
                            hint: AppLocalizations.of(context)!.enterStreetName,
                            icon: CupertinoIcons.location_solid,
                            isDark: widget.isDark,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 1,
                          child: widget.buildBusinessTextField(
                            controller: widget.businessHouseNumberController,
                            label: AppLocalizations.of(context)!.houseNumber1,
                            hint: AppLocalizations.of(context)!.enterHouseNumber,
                            icon: CupertinoIcons.house,
                            isDark: widget.isDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Postal Code + City in a row
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 2,
                          child: widget.buildBusinessTextField(
                            controller: widget.businessPostalCodeController,
                            label: AppLocalizations.of(context)!.postalCode,
                            hint: AppLocalizations.of(context)!.enterPostalCode,
                            icon: CupertinoIcons.mail_solid,
                            isDark: widget.isDark,
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 3,
                          child: widget.buildBusinessTextField(
                            controller: widget.businessCityController,
                            label: AppLocalizations.of(context)!.city,
                            hint: AppLocalizations.of(context)!.enterCity,
                            icon: CupertinoIcons.building_2_fill,
                            isDark: widget.isDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Country selector
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context)!.country,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: widget.isDark ? Colors.white70 : Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TradeRepublicListTile.navigation(
                        title: widget.businessCountryController.text.isEmpty
                            ? AppLocalizations.of(context)!.selectCountry
                            : widget.businessCountryController.text,
                        leading: Icon(
                          CupertinoIcons.globe,
                          size: 20,
                          color: widget.isDark ? Colors.white70 : Colors.black54,
                        ),
                        onTap: () => _showCountrySelector(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ]),

                // ── 4. D-U-N-S® Verification (required) ────────
                sectionLabel(AppLocalizations.of(context)!.sectionVerification, CupertinoIcons.shield_lefthalf_fill),
                Container(
                  margin: const EdgeInsets.only(bottom: 20),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: widget.isDark
                        ? Colors.white.withOpacity(0.06)
                        : Colors.black.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: widget.isDark ? Colors.white12 : Colors.black12,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              color: widget.isDark ? Colors.white : Colors.black,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              CupertinoIcons.shield_lefthalf_fill,
                              color: widget.isDark ? Colors.black : Colors.white,
                              size: 16,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  AppLocalizations.of(context)!.dunsLabel,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: textColor,
                                  ),
                                ),
                                Text(
                                  AppLocalizations.of(context)!.dunsSubtitle,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: subtleColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      widget.buildBusinessTextField(
                        controller: widget.businessDunsController,
                        label: AppLocalizations.of(context)!.dunsFieldLabel,
                        hint: '123456789',
                        icon: CupertinoIcons.number_square,
                        isDark: widget.isDark,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(9),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        AppLocalizations.of(context)!.dunsDescription,
                        style: TextStyle(
                          fontSize: 11,
                          color: subtleColor,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Terms & Conditions ──────────────────────────
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: widget.isDark
                        ? Colors.white.withOpacity(0.04)
                        : Colors.black.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context)!.termsConditions,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${AppLocalizations.of(context)!.termsInfoVerified}\n'
                        '${AppLocalizations.of(context)!.termsInfoDue(widget.days ?? 30)}\n'
                        '${AppLocalizations.of(context)!.termsInfoLate}\n'
                        '${AppLocalizations.of(context)!.termsInfoSubject}',
                        style: TextStyle(
                          fontSize: 12,
                          color: widget.isDark ? Colors.white60 : Colors.black54,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),

              ],
            ),
          ),
        ),

        // ── Submit button ────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.all(24),
          child: TradeRepublicButton(
            label: AppLocalizations.of(context)!.continueButton,
            onPressed: () {
              if (widget.validateBusinessInfo()) {
                _goToPage(2);
              }
            },
            width: double.infinity,
            height: 56,
          ),
        ),
      ],
    );
  }
}

class _CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var text = newValue.text;

    if (newValue.selection.isCollapsed) {
      final buffer = StringBuffer();
      for (int i = 0; i < text.length; i++) {
        buffer.write(text[i]);
        final nonZeroIndex = i + 1;
        if (nonZeroIndex % 4 == 0 && nonZeroIndex != text.length) {
          buffer.write(' ');
        }
      }

      final string = buffer.toString();
      return newValue.copyWith(
        text: string,
        selection: TextSelection.collapsed(offset: string.length),
      );
    }

    return newValue;
  }
}

class _ExpiryDateFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var text = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');

    if (text.length >= 2) {
      text = '${text.substring(0, 2)}/${text.substring(2)}';
    }

    return newValue.copyWith(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

// Phone number formatter with country code and brackets
class _PhoneNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.replaceAll(RegExp(r'[^0-9+]'), '');
    
    if (text.isEmpty) {
      return newValue.copyWith(text: '', selection: const TextSelection.collapsed(offset: 0));
    }

    final buffer = StringBuffer();
    
    // Handle country code (starts with +)
    if (text.startsWith('+')) {
      if (text.length == 1) {
        return newValue.copyWith(text: '+', selection: const TextSelection.collapsed(offset: 1));
      }
      
      final digits = text.substring(1);
      buffer.write('+');
      
      // US/Canada format: +1 (555) 123-4567
      if (digits.startsWith('1') && digits.length > 1) {
        buffer.write('1 ');
        final remaining = digits.substring(1);
        
        if (remaining.isNotEmpty) {
          buffer.write('(');
          buffer.write(remaining.substring(0, remaining.length > 3 ? 3 : remaining.length));
          
          if (remaining.length > 3) {
            buffer.write(') ');
            buffer.write(remaining.substring(3, remaining.length > 6 ? 6 : remaining.length));
            
            if (remaining.length > 6) {
              buffer.write('-');
              buffer.write(remaining.substring(6, remaining.length > 10 ? 10 : remaining.length));
            }
          }
        }
      }
      // European format: +49 (30) 1234-5678
      else {
        // Country code (2-3 digits)
        final countryCodeLength = digits.length > 2 ? (digits.startsWith('49') || digits.startsWith('44') ? 2 : 3) : digits.length;
        buffer.write(digits.substring(0, countryCodeLength));
        
        if (digits.length > countryCodeLength) {
          buffer.write(' ');
          final remaining = digits.substring(countryCodeLength);
          
          // Area code in brackets
          buffer.write('(');
          final areaCodeLength = remaining.length > 3 ? 3 : remaining.length;
          buffer.write(remaining.substring(0, areaCodeLength));
          
          if (remaining.length > 3) {
            buffer.write(') ');
            final localPart = remaining.substring(3);
            
            // Split local number with dash
            final firstPart = localPart.substring(0, localPart.length > 4 ? 4 : localPart.length);
            buffer.write(firstPart);
            
            if (localPart.length > 4) {
              buffer.write('-');
              buffer.write(localPart.substring(4, localPart.length > 8 ? 8 : localPart.length));
            }
          }
        }
      }
    } else {
      // No country code - format as US number
      if (text.length <= 3) {
        buffer.write('(');
        buffer.write(text);
      } else if (text.length <= 6) {
        buffer.write('(');
        buffer.write(text.substring(0, 3));
        buffer.write(') ');
        buffer.write(text.substring(3));
      } else {
        buffer.write('(');
        buffer.write(text.substring(0, 3));
        buffer.write(') ');
        buffer.write(text.substring(3, 6));
        buffer.write('-');
        buffer.write(text.substring(6, text.length > 10 ? 10 : text.length));
      }
    }

    final formatted = buffer.toString();
    return newValue.copyWith(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

// Tax ID formatter based on country
class _TaxIdFormatter extends TextInputFormatter {
      final String countryCode;
  
      _TaxIdFormatter(this.countryCode);

      @override
      TextEditingValue formatEditUpdate(
        TextEditingValue oldValue,
        TextEditingValue newValue,
      ) {
        final text = newValue.text.replaceAll(RegExp(r'[^0-9A-Z]'), '').toUpperCase();
    
        if (text.isEmpty) {
          return newValue.copyWith(text: '', selection: const TextSelection.collapsed(offset: 0));
        }

        String formatted;
    
        switch (countryCode) {
          case 'US':
          case 'CA':
            // US EIN: XX-XXXXXXX (9 digits with dash after 2nd)
            if (text.length <= 2) {
              formatted = text;
            } else {
              formatted = '${text.substring(0, 2)}-${text.substring(2, text.length > 9 ? 9 : text.length)}';
            }
            break;
        
          case 'DE':
            // German Tax ID: XXX/XXXX/XXXX (11 digits with slashes)
            if (text.length <= 3) {
              formatted = text;
            } else if (text.length <= 7) {
              formatted = '${text.substring(0, 3)}/${text.substring(3)}';
            } else {
              formatted = '${text.substring(0, 3)}/${text.substring(3, 7)}/${text.substring(7, text.length > 11 ? 11 : text.length)}';
            }
            break;
        
          case 'GB':
            // UK UTR: XXXXX XXXXX (10 digits with space)
            if (text.length <= 5) {
              formatted = text;
            } else {
              formatted = '${text.substring(0, 5)} ${text.substring(5, text.length > 10 ? 10 : text.length)}';
            }
            break;
        
          case 'FR':
            // French SIREN: XXX XXX XXX (9 digits with spaces)
            if (text.length <= 3) {
              formatted = text;
            } else if (text.length <= 6) {
              formatted = '${text.substring(0, 3)} ${text.substring(3)}';
            } else {
              formatted = '${text.substring(0, 3)} ${text.substring(3, 6)} ${text.substring(6, text.length > 9 ? 9 : text.length)}';
            }
            break;
        
          case 'NL':
            // Dutch BTW: XXXXXXXXXXBXX (14 chars with B)
            if (text.length <= 9) {
              formatted = text;
            } else if (text.length == 10) {
              formatted = '${text.substring(0, 9)}B';
            } else {
              formatted = '${text.substring(0, 9)}B${text.substring(10, text.length > 12 ? 12 : text.length)}';
            }
            break;
        
          case 'CH':
            // Swiss UID: CHE-XXX.XXX.XXX
            final digits = text.replaceAll('CHE', '');
            if (digits.isEmpty) {
              formatted = 'CHE-';
            } else if (digits.length <= 3) {
              formatted = 'CHE-$digits';
            } else if (digits.length <= 6) {
              formatted = 'CHE-${digits.substring(0, 3)}.${digits.substring(3)}';
            } else {
              formatted = 'CHE-${digits.substring(0, 3)}.${digits.substring(3, 6)}.${digits.substring(6, digits.length > 9 ? 9 : digits.length)}';
            }
            break;
        
          default:
            // Generic: just limit to 15 chars
            formatted = text.substring(0, text.length > 15 ? 15 : text.length);
        }

        return newValue.copyWith(
          text: formatted,
          selection: TextSelection.collapsed(offset: formatted.length),
        );
      }
}

// Custom Painter for EMV Chip Pattern
class ChipPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withOpacity(0.1)
      ..style = PaintingStyle.fill;

    // Draw chip contact grid pattern
    final cellWidth = size.width / 4;
    final cellHeight = size.height / 3;

    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 3; j++) {
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            i * cellWidth + cellWidth * 0.1,
            j * cellHeight + cellHeight * 0.1,
            cellWidth * 0.8,
            cellHeight * 0.8,
          ),
          const Radius.circular(25),
        );
        canvas.drawRRect(rect, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Simple card pattern painter for subtle background texture
class CardPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    // Draw subtle diagonal lines
    const spacing = 30.0;
    for (double i = 0; i < size.width + size.height; i += spacing) {
      canvas.drawLine(
        Offset(i, 0),
        Offset(i - size.height, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Animated Swipe Card for Payment Method (like Messages)
class _AnimatedSwipePaymentCard extends StatefulWidget {
  final VoidCallback onDelete;
  final Widget child;

  const _AnimatedSwipePaymentCard({
    required this.onDelete,
    required this.child,
  });

  @override
  State<_AnimatedSwipePaymentCard> createState() =>
      _AnimatedSwipePaymentCardState();
}

class _AnimatedSwipePaymentCardState extends State<_AnimatedSwipePaymentCard>
    with TickerProviderStateMixin {
  double _dragExtent = 0;
  double _startExtent = 0;

  // Animation controllers
  late AnimationController _deleteAnimController;
  late AnimationController _bounceController;
  late AnimationController _scaleController;

  // Haptic feedback tracking
  bool _hasTriggeredSelectionHaptic = false;
  bool _hasTriggeredLightHaptic = false;
  bool _hasTriggeredMediumHaptic = false;

  @override
  void initState() {
    super.initState();
    _deleteAnimController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _bounceController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _deleteAnimController.dispose();
    _bounceController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  void _handleDragStart(DragStartDetails details) {
    _bounceController.stop();
    _bounceController.reset();
    _dragExtent = 0;
    _startExtent = 0;
    _scaleController.animateTo(0.97, curve: Curves.easeOut);
    _hasTriggeredSelectionHaptic = false;
    _hasTriggeredLightHaptic = false;
    _hasTriggeredMediumHaptic = false;
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragExtent += details.primaryDelta ?? 0;
      // Only allow swiping left
      _dragExtent = _dragExtent.clamp(-120.0, 0.0);
    });

    final absDrag = _dragExtent.abs();
    if (absDrag > 20 && !_hasTriggeredSelectionHaptic) {
      HapticFeedback.selectionClick();
      _hasTriggeredSelectionHaptic = true;
    }
    if (absDrag > 60 && !_hasTriggeredLightHaptic) {
      HapticFeedback.lightImpact();
      _hasTriggeredLightHaptic = true;
    }
    if (absDrag > 100 && !_hasTriggeredMediumHaptic) {
      HapticFeedback.mediumImpact();
      _hasTriggeredMediumHaptic = true;
    }

    _deleteAnimController.value = (-_dragExtent / 100).clamp(0.0, 1.0);
  }

  void _handleDragEnd(DragEndDetails details) {
    _scaleController.animateTo(1.0, curve: Curves.easeOutCubic);

    final velocity = details.velocity.pixelsPerSecond.dx;
    final threshold = 80.0;

    if (_dragExtent < -threshold || velocity < -500) {
      HapticFeedback.heavyImpact();
      widget.onDelete();
    }

    _startExtent = _dragExtent;
    _bounceController.reset();
    _bounceController.forward();

    _deleteAnimController.animateTo(0, curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final animatedDragExtent =
        _bounceController.isAnimating || _bounceController.isCompleted
        ? _startExtent *
              (1 - Curves.easeOutCubic.transform(_bounceController.value))
        : _dragExtent;

    Color backgroundColor = animatedDragExtent < -20
        ? Colors.red.withOpacity((-animatedDragExtent / 100).clamp(0.0, 0.8))
        : Colors.transparent;

    return GestureDetector(
      onHorizontalDragStart: _handleDragStart,
      onHorizontalDragUpdate: _handleDragUpdate,
      onHorizontalDragEnd: _handleDragEnd,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Background with delete icon
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(25),
              ),
              child: Row(
                children: [
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.only(right: 24),
                    child: AnimatedBuilder(
                      animation: _deleteAnimController,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: 0.5 + (_deleteAnimController.value * 0.5),
                          child: Opacity(
                            opacity: _deleteAnimController.value,
                            child: const Icon(
                              CupertinoIcons.delete,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Foreground card
          AnimatedBuilder(
            animation: Listenable.merge([_scaleController, _bounceController]),
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(animatedDragExtent, 0),
                child: Transform.scale(
                  scale: _scaleController.value,
                  child: widget.child,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
