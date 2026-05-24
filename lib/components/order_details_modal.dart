import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import '../services/api_service.dart';
import '../services/cultioo_desktop_layout.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../utils/number_formatters.dart';
import '../utils/wagon_catalog.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' hide Path;
import '../services/trade_republic_widgets.dart';
import '../services/app_localizations.dart';
import '../services/cultioo_spinner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'credit_card_widget.dart';

class OrderDetailsModal extends StatefulWidget {
  final Map<String, dynamic> order;
  final List<Map<String, dynamic>>? linkedSplitOrders;
  final Function? onOrderUpdated; // Callback to refresh order list
  final String? numberFormat; // Number format preference

  const OrderDetailsModal({
    super.key,
    required this.order,
    this.linkedSplitOrders,
    this.onOrderUpdated,
    this.numberFormat,
  });

  @override
  State<OrderDetailsModal> createState() => _OrderDetailsModalState();
}

class _GradientPickupTrianglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(0, size.height)
      ..lineTo(size.width, size.height)
      ..close();

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final paint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFFFD84D), Color(0xFFFFB300)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(rect);

    final shadowPaint = Paint()
      ..color = const Color(0xFFFFCC00).withOpacity(0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);

    canvas.drawPath(path.shift(const Offset(0, 1.2)), shadowPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Renders a placeholder for one frame, then the real [FlutterMap]. Avoids
/// pointer/hit-testing the map before its render subtree has a size (common
/// when the map opens inside animated bottom sheets on desktop).
class _LayoutSafeMapSlot extends StatefulWidget {
  const _LayoutSafeMapSlot({
    required this.placeholderColor,
    required this.builder,
  });

  final Color placeholderColor;
  final WidgetBuilder builder;

  @override
  State<_LayoutSafeMapSlot> createState() => _LayoutSafeMapSlotState();
}

class _LayoutSafeMapSlotState extends State<_LayoutSafeMapSlot> {
  bool _showMap = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _showMap = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_showMap) {
      return ColoredBox(
        color: widget.placeholderColor,
        child: const SizedBox.expand(),
      );
    }
    return widget.builder(context);
  }
}

class _OrderDetailsModalState extends State<OrderDetailsModal> {
  /// Delvioo-account bottom sheet: list tiles inside grouped cards
  static const EdgeInsets _kSheetTilePadding =
      EdgeInsets.symmetric(horizontal: 18, vertical: 14);
  static const EdgeInsets _kSheetTilePaddingCompact =
      EdgeInsets.symmetric(horizontal: 18, vertical: 12);
  static const EdgeInsets _kSheetTilePaddingDense =
      EdgeInsets.symmetric(horizontal: 18, vertical: 10);

  bool _isMarkingReceived = false;
  bool _isClosingOrder = false;
  bool _isDownloadingInvoice = false;
  late Map<String, dynamic> _currentOrder;
  bool _splitFamilyExpanded = false;
  List<Map<String, dynamic>> _splitFamilyOrders = [];
  bool _isLoadingSplitFamily = false;
  int? _selectedSplitOrderId;
  bool _hasReviewed = false;
  bool _isLoadingReviewStatus = true;


  // Shipping payment state
  bool _buyerPaysShipping = false;
  double _shippingCostDue = 0;
  String? _shippingIncoterm;
  Map<String, dynamic>? _acceptedBidForShipping;
  // 'pending' = buyer must pay, 'paid' = paid, 'seller_pays' = seller responsible, 'deferred' = net30/60, null = unknown
  String? _shippingPaymentStatus;
  String? _shippingPaymentType; // 'card','ach_net30','ach_net60','sepa_net30','sepa_net60'
  String? _shippingPaymentDueDate; // ISO date string e.g. '2026-04-12'

  // Buyer waiting charges state
  double _buyerWaitingCharges = 0;
  int _buyerWaitingSeconds = 0;
  int _waitingFreeMinutes = 15;
  double? _waitingRatePerHour;
  bool _waitingChargesPaid = false;
  bool _isPayingWaitingCharges = false;

  // Auction state
  Map<String, dynamic>? _auction;
  List<Map<String, dynamic>> _bids = [];
  bool _isLoadingAuction =
      true; // Start with loading=true to show loading UI initially
  bool _isStartingAuction = false;
  bool _isDisablingDelvioo = false; // For "arrange own shipping" action
  int _selectedAuctionDuration = 60; // minutes
  Timer? _auctionTimer; // Timer for countdown updates
  bool _useCustomDuration = false; // For manual time input
  final TextEditingController _customDurationController =
      TextEditingController();

  // Driver selection mode: 'auction' or 'findDriver'
  String _driverSelectionMode = 'auction';
  // Find Driver state
  List<Map<String, dynamic>> _availableDrivers = [];
  bool _isLoadingAvailableDrivers = false;
  Map<String, dynamic>? _selectedMapDriver;
  bool _isSelectingDriver = false;
  bool _driverPendingConfirmation = false; // true right after direct driver selection
  String _driverSortBy = 'wagon'; // wagon | status | distance | rating | price
  bool _hideOccupiedDrivers = true; // hide busy drivers by default
  String? _requiredWagonType;
  /// Road distance (OSRM) pickup → delivery for this order; shared by all drivers.
  double? _roadPickupToDeliveryKm;
  /// OSRM driver → pickup (km), same as map preview; keyed by driver user id.
  final Map<int, double> _driverToPickupRoadKmById = {};

  // Auction smart settings
  bool _maxBidEnabled = false; // Ceiling price for bids
  double? _maxBidPrice;
  bool _autoAcceptEnabled = false; // Auto-end when bid hits threshold
  double? _autoAcceptThreshold;
  bool _cullyAiEnabled = false; // AI auto-picks best driver
  bool _minBidsEnabled = false; // Minimum bids before auto-accept or end
  int? _minBids;
  final TextEditingController _maxBidPriceController = TextEditingController();
  final TextEditingController _autoAcceptController = TextEditingController();
  final TextEditingController _minBidsController = TextEditingController();

  // Business info controllers for Net 30/60 payment terms
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
  bool _isLoadingBusinessInfo = false;

  // Payment terms limits
  static const double _monthlyPaymentLimit = 75000.0; // $75,000/month
  static const double _overLimitFeePercent = 1.0; // 1% fee over limit
  final double _currentMonthUsage = 0.0;

  @override
  void initState() {
    super.initState();
    _currentOrder = Map<String, dynamic>.from(widget.order);

    print('🚀🚀🚀 OrderDetailsModal opened for Order #${_currentOrder['id']}');
    print('🚀 Order status: ${_currentOrder['status']}');
    print('🚀 Order delvioo: ${_currentOrder['delvioo']}');

    // Check if this is a delivery order that might have an auction
    final delvioo = _currentOrder['delvioo'];
    final isDeliveryOrder = delvioo != null &&
        delvioo != 0 &&
        delvioo != '0' &&
        delvioo != false &&
        delvioo != '';

    // Only set loading=true if this is a delivery order
    _isLoadingAuction = isDeliveryOrder;

    // Seed shipping state from the order data already available
    final rawShippingStatus = _currentOrder['shipping_payment_status']?.toString();
    if (rawShippingStatus != null && rawShippingStatus.isNotEmpty) {
      _shippingPaymentStatus = rawShippingStatus;
      _buyerPaysShipping = rawShippingStatus == 'pending' || rawShippingStatus == 'paid';
    }
    final rawShippingCost = _currentOrder['shipping_cost'];
    if (rawShippingCost != null) {
      final cost = rawShippingCost is num
          ? rawShippingCost.toDouble()
          : double.tryParse(rawShippingCost.toString()) ?? 0.0;
      if (cost > 0) _shippingCostDue = cost;
    }
    // Seed buyer waiting charges from order data
    final rawBuyerCharges = _currentOrder['buyer_waiting_charges'];
    if (rawBuyerCharges != null) {
      final c = rawBuyerCharges is num ? rawBuyerCharges.toDouble() : double.tryParse(rawBuyerCharges.toString()) ?? 0.0;
      if (c > 0) _buyerWaitingCharges = c;
    }
    final rawBuyerSec = _currentOrder['buyer_waiting_seconds'];
    if (rawBuyerSec != null) {
      _buyerWaitingSeconds = rawBuyerSec is num ? rawBuyerSec.toInt() : int.tryParse(rawBuyerSec.toString()) ?? 0;
    }
    _waitingFreeMinutes = ((_currentOrder['waiting_free_minutes'] ?? 15) as num).toInt();
    final rawRate = _currentOrder['waiting_rate_per_hour'];
    if (rawRate != null) _waitingRatePerHour = rawRate is num ? rawRate.toDouble() : double.tryParse(rawRate.toString());
    _waitingChargesPaid = _currentOrder['waiting_charges_paid'] == 1 || _currentOrder['waiting_charges_paid'] == true;

    _checkReviewStatus();
    _refreshOrderData(); // Refresh order data from server first
  }

  int? _toOrderInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  int? _baseOrderIdFor(Map<String, dynamic> order) {
    final parent = _toOrderInt(order['parent_order_id']);
    final id = _toOrderInt(order['id']);
    return parent ?? id;
  }

  String _displayOrderNumberFor(Map<String, dynamic> order) {
    final base = _baseOrderIdFor(order);
    if (base == null) return '';
    final part = _toOrderInt(order['split_order_part']);
    final rawSplit = order['split_order'];
    final isSplit = rawSplit == true ||
        rawSplit == 1 ||
        rawSplit.toString() == '1' ||
        (order['parent_order_id'] != null) ||
        (part != null && part > 0);
    if (isSplit && part != null && part > 0) {
      return '$base.$part';
    }
    return '$base';
  }

  String _displayNumberForOrderId(int id) {
    for (final o in _splitFamilyOrders) {
      final oid = _toOrderInt(o['id']);
      if (oid == id) return _displayOrderNumberFor(o);
    }
    return id.toString();
  }

  List<Map<String, dynamic>> _resolveLinkedSplitOrders() {
    final byId = <int, Map<String, dynamic>>{};

    void addEntry(dynamic idRaw, dynamic statusRaw) {
      final id = _toOrderInt(idRaw);
      if (id == null) return;
      byId[id] = {
        'id': id,
        'status': (statusRaw ?? byId[id]?['status'] ?? 'pending').toString(),
      };
    }

    // 1) Linked split orders from widget caller (preferred).
    for (final raw in (widget.linkedSplitOrders ?? [])) {
      if (raw is Map<String, dynamic>) {
        addEntry(raw['id'] ?? raw['order_id'], raw['status']);
      }
    }

    // 2) Optional split family payload coming from backend/app response.
    final dynamic familyRaw = _currentOrder['linked_split_orders'] ??
        _currentOrder['split_orders'] ??
        _currentOrder['split_family'];
    if (familyRaw is List) {
      for (final raw in familyRaw) {
        if (raw is Map) {
          addEntry(raw['id'] ?? raw['order_id'], raw['status']);
        } else {
          addEntry(raw, 'pending');
        }
      }
    }

    // 3) Always include current + parent fallback.
    addEntry(_currentOrder['id'], _currentOrder['status']);
    addEntry(_currentOrder['parent_order_id'], 'pending');

    final entries = byId.values.toList()
      ..sort((a, b) => (_toOrderInt(a['id']) ?? 0).compareTo(_toOrderInt(b['id']) ?? 0));
    return entries;
  }

  String _splitHeaderLabel() {
    final ids = _resolveLinkedSplitOrders()
        .map((e) => _toOrderInt(e['id']))
        .whereType<int>()
        .toList();
    if (ids.length >= 2) {
      return ids.map(_displayNumberForOrderId).join(' & ');
    }
    final current = _displayOrderNumberFor(_currentOrder);
    return current.isEmpty ? AppLocalizations.of(context)!.orders : current;
  }

  Future<void> _loadSplitFamilyIfNeeded() async {
    final linked = _resolveLinkedSplitOrders();
    final ids = linked.map((e) => _toOrderInt(e['id'])).whereType<int>().toList();
    if (ids.length < 2) {
      if (mounted && _splitFamilyOrders.isNotEmpty) {
        setState(() => _splitFamilyOrders = []);
      }
      return;
    }

    if (mounted) setState(() => _isLoadingSplitFamily = true);
    final fetched = <Map<String, dynamic>>[];
    for (final id in ids) {
      try {
        final resp = await ApiService.getOrder(id);
        if (resp['success'] == true && resp['order'] != null) {
          fetched.add(Map<String, dynamic>.from(resp['order']));
        } else {
          fetched.add({'id': id, 'status': (linked.firstWhere((e) => _toOrderInt(e['id']) == id, orElse: () => {'status': 'pending'})['status'] ?? 'pending')});
        }
      } catch (_) {
        fetched.add({'id': id, 'status': (linked.firstWhere((e) => _toOrderInt(e['id']) == id, orElse: () => {'status': 'pending'})['status'] ?? 'pending')});
      }
    }

    fetched.sort((a, b) {
      final ap = _toOrderInt(a['split_order_part']) ?? 999;
      final bp = _toOrderInt(b['split_order_part']) ?? 999;
      if (ap != bp) return ap.compareTo(bp);
      return (_toOrderInt(a['id']) ?? 0).compareTo(_toOrderInt(b['id']) ?? 0);
    });

    final currentId = _toOrderInt(_currentOrder['id']);
    final desiredSelected = _selectedSplitOrderId ?? currentId;
    final hasSelected = desiredSelected != null && fetched.any((o) => _toOrderInt(o['id']) == desiredSelected);
    if (mounted) {
      setState(() {
        _splitFamilyOrders = fetched;
        _selectedSplitOrderId = hasSelected ? desiredSelected : currentId;
        _isLoadingSplitFamily = false;
      });
    }
  }



  Future<void> _switchToSplitOrder(int orderId) async {
    final currentId = _toOrderInt(_currentOrder['id']);
    if (currentId == orderId) return;
    if (mounted) setState(() => _selectedSplitOrderId = orderId);
    try {
      final resp = await ApiService.getOrder(orderId);
      if (!mounted) return;
      if (resp['success'] == true && resp['order'] != null) {
        setState(() {
          _currentOrder = Map<String, dynamic>.from(resp['order']);
          _auction = null;
          _bids = [];
          _isLoadingAuction = false;
        });
        _checkReviewStatus();
        _loadAuctionIfNeeded();
        _loadSplitFamilyIfNeeded();
      }
    } catch (e) {
      if (!mounted) return;
      TopNotification.error(
        context,
        'Failed to load order',
        title: e.toString(),
      );
    }
  }

  // Refresh order data from server to get latest status
  Future<void> _refreshOrderData() async {
    try {
      final orderId = _currentOrder['id'];
      print('🔄 Refreshing order data for Order #$orderId');
      final response = await ApiService.getOrder(orderId);

      if (response['success'] == true && response['order'] != null) {
        final order = response['order'];
        // Never roll back a locally-confirmed 'completed' status with stale
        // server data – keep whichever status is "further along".
        const statusRank = {
          'pending': 0, 'awaiting': 0, 'waiting': 0,
          'confirmed': 1, 'succeeded': 1, 'approval_approved': 1,
          'accepted': 2, 'ready_for_pickup': 3, 'ready': 3,
          'picked_up': 4, 'shipped': 4,
          'buyer_check_in': 5,
          'delivered': 6, 'completed': 6,
        };
        final serverStatus = (order['status'] ?? '').toString().toLowerCase();
        final localStatus = (_currentOrder['status'] ?? '').toString().toLowerCase();
        final serverRank = statusRank[serverStatus] ?? 0;
        final localRank  = statusRank[localStatus]  ?? 0;
        final mergedStatus = serverRank >= localRank ? serverStatus : localStatus;

        setState(() {
          _currentOrder = Map<String, dynamic>.from(order);
          if (mergedStatus.isNotEmpty) _currentOrder['status'] = mergedStatus;

          // Load incoterm from order response
          final incoterm = order['incoterm']?.toString() ?? '';
          final buyerPays = order['buyer_pays_shipping'] == true;
          if (incoterm.isNotEmpty) {
            _shippingIncoterm = incoterm;
            _buyerPaysShipping = buyerPays;
            print(
              '📦 Incoterm loaded from order: $_shippingIncoterm, buyer_pays: $_buyerPaysShipping',
            );
          }

          // Update shipping payment status from fresh server data
          final freshShippingStatus = order['shipping_payment_status']?.toString();
          if (freshShippingStatus != null && freshShippingStatus.isNotEmpty) {
            _shippingPaymentStatus = freshShippingStatus;
            print('📦 shipping_payment_status from refresh: $freshShippingStatus');
          }
          final freshShippingCost = order['shipping_cost'];
          if (freshShippingCost != null) {
            final cost = freshShippingCost is num
                ? freshShippingCost.toDouble()
                : double.tryParse(freshShippingCost.toString()) ?? 0.0;
            if (cost > 0) _shippingCostDue = cost;
          }

          // Update buyer waiting charges from fresh data
          final freshBuyerCharges = order['buyer_waiting_charges'];
          if (freshBuyerCharges != null) {
            final c = freshBuyerCharges is num ? freshBuyerCharges.toDouble() : double.tryParse(freshBuyerCharges.toString()) ?? 0.0;
            _buyerWaitingCharges = c;
          }
          final freshBuyerSec = order['buyer_waiting_seconds'];
          if (freshBuyerSec != null) {
            _buyerWaitingSeconds = freshBuyerSec is num ? freshBuyerSec.toInt() : int.tryParse(freshBuyerSec.toString()) ?? 0;
          }
          _waitingFreeMinutes = ((order['waiting_free_minutes'] ?? 15) as num).toInt();
          final freshRate = order['waiting_rate_per_hour'];
          if (freshRate != null) _waitingRatePerHour = freshRate is num ? freshRate.toDouble() : double.tryParse(freshRate.toString());
          _waitingChargesPaid = order['waiting_charges_paid'] == 1 || order['waiting_charges_paid'] == true;
        });
        print('✅ Order refreshed - new status: ${_currentOrder['status']}');
        print('✅ Order refreshed - delvioo: ${_currentOrder['delvioo']}');
        print(
          '✅ Order refreshed - payment_method_type: ${_currentOrder['payment_method_type']}',
        );
        print(
          '✅ Order refreshed - ach_details: ${_currentOrder['ach_details']}',
        );
        print(
          '✅ Order refreshed - sepa_details: ${_currentOrder['sepa_details']}',
        );
        print('✅ Order refreshed - incoterm: ${_currentOrder['incoterm']}');
      }
    } catch (e) {
      print('❌ Error refreshing order: $e');
    }

    // Now load auction with fresh data
    _loadAuctionIfNeeded();
    _loadSplitFamilyIfNeeded();
  }

  @override
  void dispose() {
    _auctionTimer?.cancel();
    _customDurationController.dispose();
    _maxBidPriceController.dispose();
    _autoAcceptController.dispose();
    _minBidsController.dispose();
    _businessNameController.dispose();
    _businessTaxIdController.dispose();
    _businessStreetController.dispose();
    _businessHouseNumberController.dispose();
    _businessPostalCodeController.dispose();
    _businessCityController.dispose();
    _businessCountryController.dispose();
    _businessPhoneController.dispose();
    _businessEmailController.dispose();
    super.dispose();
  }

  // Start the auction countdown timer
  void _startAuctionTimer() {
    print('⏱️ _startAuctionTimer called');
    _auctionTimer?.cancel();
    _auctionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_auction != null && _auction!['status'] == 'active') {
        final endTime = DateTime.tryParse(_auction!['end_time'] ?? '');
        if (endTime != null) {
          final remaining = endTime.difference(DateTime.now());
          if (remaining.isNegative) {
            // Auction has expired, reload to get updated status
            print('⏱️ Auction expired, reloading...');
            _loadAuction();
            timer.cancel();
          } else {
            // Just trigger a rebuild to update the timer display
            if (mounted) setState(() {});
          }
        }
      } else {
        print('⏱️ Timer cancelled - auction null or not active');
        timer.cancel();
      }
    });
    print('⏱️ Timer started successfully');
  }

  // Load auction data if order is in confirmed status or has delvioo delivery
  Future<void> _loadAuctionIfNeeded() async {
    if (!mounted) return;
    final status = _currentOrder['status']?.toLowerCase() ?? '';
    final delvioo = _currentOrder['delvioo'];
    final isDeliveryOrder = delvioo != null &&
        delvioo != 0 &&
        delvioo != '0' &&
        delvioo != false &&
        delvioo != '';

    print('🎯 _loadAuctionIfNeeded called');
    print('  - order status: $status');
    print('  - delvioo: $delvioo (${delvioo.runtimeType})');
    print('  - isDeliveryOrder: $isDeliveryOrder');

    // Load auction for delivery orders in confirmed/accepted/shipped status
    // Also load for pending Net 30/60 orders (deferred payment)
    // Also load for statuses AFTER driver selection (ready_for_pickup, picked_up, delivered, completed)
    final isNetPayment = _currentOrder['payment_method_type'] == 'payment_30_days' ||
        _currentOrder['payment_method_type'] == 'payment_60_days' ||
        _currentOrder['payment_terms_details'] != null;
    if (isDeliveryOrder && (status == 'confirmed' || status == 'succeeded' ||
        status == 'accepted' || status == 'shipped' ||
        status == 'ready_for_pickup' || status == 'ready' ||
        status == 'picked_up' || status == 'delivered' || status == 'completed' ||
        (status == 'pending' && isNetPayment))) {
      print('🎯 Loading auction for order ${_currentOrder['id']}');
      await _loadAuction();
    } else {
      // Not a delivery order or not in correct status - stop loading
      print('🎯 Not loading auction - setting _isLoadingAuction to false');
      if (mounted) {
        setState(() => _isLoadingAuction = false);
      }
    }
  }

  // Load auction details
  Future<void> _loadAuction() async {
    if (!mounted) return;
    print(
      '🎯 _loadAuction called, current _isLoadingAuction: $_isLoadingAuction',
    );

    setState(() => _isLoadingAuction = true);
    print('🎯 _loadAuction started for order ${_currentOrder['id']}');

    try {
      final orderId = _currentOrder['id'];
      final response = await ApiService.getOrderAuction(
        orderId is int ? orderId : int.tryParse(orderId.toString()) ?? 0,
      );
      if (!mounted) return;
      print('🎯 Auction API response: $response');

      if (response['success'] == true) {
        // Load incoterm from response (always available)
        final incoterm = response['incoterm']?.toString() ?? '';
        final buyerPaysShipping = response['buyer_pays_shipping'] == true;

        print(
          '🎯 Incoterm from auction response: $incoterm, buyer_pays: $buyerPaysShipping',
        );

        if (!mounted) return;
        setState(() {
          _auction = response['auction'];
          _bids = List<Map<String, dynamic>>.from(response['bids'] ?? []);
          // Set incoterm directly from auction response
          if (incoterm.isNotEmpty) {
            _shippingIncoterm = incoterm;
            _buyerPaysShipping = buyerPaysShipping;
          }
          // Read shipping payment status from backend
          final rawStatus = response['shipping_payment_status']?.toString();
          if (rawStatus != null && rawStatus.isNotEmpty) {
            _shippingPaymentStatus = rawStatus;
          }
          final rawType = response['shipping_payment_type']?.toString();
          if (rawType != null && rawType.isNotEmpty) {
            _shippingPaymentType = rawType;
          }
          final rawDue = response['shipping_payment_due_date']?.toString();
          if (rawDue != null && rawDue.isNotEmpty) {
            _shippingPaymentDueDate = rawDue;
          }
          // Seed _shippingCostDue from winning bid if not yet set
          if (_shippingCostDue == 0 && _bids.isNotEmpty) {
            final winId = response['auction']?['winning_bid_id'] ?? response['auction']?['accepted_bid_id'];
            if (winId != null) {
              final wb = _bids.firstWhere(
                (b) => b['id'].toString() == winId.toString(),
                orElse: () => {},
              );
              if (wb.isNotEmpty) {
                final amt = wb['bid_amount'];
                final cost = amt is num ? amt.toDouble() : double.tryParse(amt.toString()) ?? 0.0;
                if (cost > 0) _shippingCostDue = cost;
              }
            }
          }
        });
        print('🎯 Auction loaded successfully:');
        print('  - Auction: $_auction');
        print('  - Auction status: ${_auction?['status']}');
        print('  - Auction end_time: ${_auction?['end_time']}');
        print('  - Bids count: ${_bids.length}');
        print('  - Incoterm: $_shippingIncoterm');

        // Check if there's an accepted bid and load shipping info
        final acceptedBidId = _auction?['accepted_bid_id'] ?? _auction?['winning_bid_id'];
        if (acceptedBidId != null) {
          print(
            '🎯 Found accepted bid ID: $acceptedBidId - loading shipping info',
          );
          await _loadShippingInfoForAcceptedBid(orderId, acceptedBidId);
          if (!mounted) return;
        }

        // Start countdown timer if auction is active
        if (_auction?['status'] == 'active') {
          print('🎯 Auction is ACTIVE - starting timer');
          _startAuctionTimer();
        } else {
          print('🎯 Auction status is NOT active: ${_auction?['status']}');
        }
      } else {
        print('🎯 Auction API returned success=false or no auction found');
      }
    } catch (e) {
      print('❌ Error loading auction: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingAuction = false);
      }
    }
  }

  // Load shipping info for an already accepted bid
  Future<void> _loadShippingInfoForAcceptedBid(
    dynamic orderId,
    dynamic bidId,
  ) async {
    try {
      final shippingInfoResponse = await ApiService.getShippingInfo(
        orderId,
        bidId,
      );
      if (!mounted) return;

      if (shippingInfoResponse['success'] == true) {
        final buyerPaysShipping =
            shippingInfoResponse['buyer_pays_shipping'] == true;
        final shippingCost = _parseNumericValue(
          shippingInfoResponse['shipping_cost'],
        );
        final incoterm = shippingInfoResponse['incoterm']?.toString() ?? '';

        print(
          '📦 Loaded shipping info: buyer_pays=$buyerPaysShipping, cost=$shippingCost, incoterm=$incoterm',
        );

        // Find the accepted bid in our bids list
        final acceptedBid = _bids.firstWhere(
          (b) => b['id'].toString() == bidId.toString(),
          orElse: () => {'id': bidId, 'bid_amount': shippingCost},
        );

        if (!mounted) return;
        setState(() {
          _buyerPaysShipping = buyerPaysShipping;
          _shippingCostDue = shippingCost;
          _shippingIncoterm = incoterm;
          _acceptedBidForShipping = acceptedBid;
        });
      }
    } catch (e) {
      print('❌ Error loading shipping info for accepted bid: $e');
    }
  }

  // Start auction
  Future<void> _startAuction() async {
    // Validate custom duration if using custom option
    if (_useCustomDuration) {
      final customDuration = int.tryParse(_customDurationController.text);
      if (customDuration == null ||
          customDuration < 5 ||
          customDuration > 180) {
        TopNotification.error(
          context,
          AppLocalizations.of(
            context,
          )!.pleaseEnterAValidDurationBetween5And180Mi,
        );
        return;
      }
      _selectedAuctionDuration = customDuration;
    }

    setState(() => _isStartingAuction = true);

    try {
      final orderId = _currentOrder['id'];
      final response = await ApiService.startDriverAuction(
        orderId,
        durationMinutes: _selectedAuctionDuration,
        maxBidPrice: _maxBidEnabled ? _maxBidPrice : null,
        autoAcceptThreshold: _autoAcceptEnabled ? _autoAcceptThreshold : null,
        cullyAiEnabled: _cullyAiEnabled,
        minBids: _minBidsEnabled ? _minBids : null,
      );

      if (!mounted) return;

      if (response['success'] == true) {
        setState(() {
          _auction = response['auction'];
        });
        TopNotification.success(
          context,
          AppLocalizations.of(context)!.auctionStartedDriversCanNowSubmitBids,
        );
        // Refresh auction data
        await _loadAuction();
      } else {
        if (mounted) {
          TopNotification.error(
            context,
            response['error'] ?? AppLocalizations.of(context)!.failedToStartAuction,
          );
        }
      }
    } catch (e) {
      print('❌ Error starting auction: $e');
      if (mounted) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)!.errorStartingAuction,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isStartingAuction = false);
      }
    }
  }

  // Accept a bid
  Future<void> _acceptBid(Map<String, dynamic> bid) async {
    try {
      final orderId = _currentOrder['id'];
      final bidId = bid['id'];

      print(
        '🎯 Accepting bid - orderId: $orderId (${orderId.runtimeType}), bidId: $bidId (${bidId.runtimeType})',
      );
      print('🎯 Full bid data: $bid');

      // First, check if buyer needs to pay for shipping (without accepting bid yet)
      // We call a new endpoint to get shipping info without accepting
      final shippingInfoResponse = await ApiService.getShippingInfo(
        orderId,
        bidId,
      );

      if (!mounted) return;

      if (shippingInfoResponse['success'] == true) {
        final buyerPaysShipping =
            shippingInfoResponse['buyer_pays_shipping'] == true;
        final shippingCost = _parseNumericValue(
          shippingInfoResponse['shipping_cost'],
        );
        final incoterm = shippingInfoResponse['incoterm']?.toString() ?? '';

        print(
          '📦 Buyer pays shipping: $buyerPaysShipping, Cost: $shippingCost, Incoterm: $incoterm',
        );

        // Store bid info for later use
        setState(() {
          _acceptedBidForShipping = bid;
          _buyerPaysShipping = buyerPaysShipping;
          _shippingCostDue = shippingCost;
          _shippingIncoterm = incoterm;
        });

        // Helper to continue with the normal shipping/confirmation flow after split
        Future<void> continueAcceptFlow() async {
          if (!mounted) return;
          if (buyerPaysShipping && shippingCost > 0) {
            await _showShippingPaymentModal(
              bid: bid,
              shippingCost: shippingCost,
              incoterm: incoterm,
            );
          } else {
            await _showDriverConfirmationModal(bid: bid, incoterm: incoterm);
          }
        }

        // Check capacity BEFORE showing any other modal
        final suggestedSplit = _calculateSuggestedSplitForBid(bid);
        print('✂️ Bid split suggestion for bid #${bid['id']}: $suggestedSplit');

        if (suggestedSplit != null && mounted) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final dynamic rawAuctionId = _auction?['id'] ?? bid['auction_id'];
          final int? auctionId = rawAuctionId is int
              ? rawAuctionId
              : int.tryParse(rawAuctionId?.toString() ?? '');

          print('✂️ Using auctionId for split: $auctionId (from _auction: ${_auction?['id']}, from bid: ${bid['auction_id']})');

          _showDriverSplitModal(
            driver: {
              'username': bid['driver_username'] ?? 'Driver',
              'name': bid['driver_username'] ?? 'Driver',
            },
            isDark: isDark,
            fittingQty: (suggestedSplit['fittingQty'] as num).toDouble(),
            remainingQty: (suggestedSplit['remainingQty'] as num).toDouble(),
            unit: suggestedSplit['unit'].toString(),
            selectedSectionIndex: (bid['section_index'] as num?)?.toInt(),
            onSplitConfirmed: (fitting, remaining, unit) async {
              // Call the split API to create the overflow order
              if (auctionId != null && auctionId > 0) {
                print('📦 Calling split API for auction $auctionId');
                try {
                  final splitResp = await ApiService.splitAuctionOrder(
                    auctionId: auctionId,
                    sectionIndex: (bid['section_index'] as num?)?.toInt() ?? 0,
                    sectionCapacity: fitting,
                    overflowQuantity: remaining,
                    splitUnit: unit,
                  );
                  print('✅ Split API response: $splitResp');
                  if (splitResp['success'] != true) {
                    if (mounted) {
                      final errorMsg = splitResp['message'] ?? splitResp['error'] ?? 'Split failed. Driver was not confirmed.';
                      TopNotification.error(
                        context,
                        errorMsg.toString(),
                      );
                    }
                    return;
                  }
                } catch (e) {
                  print('⚠️ Split API error: $e');
                  if (mounted) {
                    TopNotification.error(
                      context,
                      'Split request failed. Driver was not confirmed.',
                    );
                  }
                  return;
                }
              } else {
                if (mounted) {
                  TopNotification.error(
                    context,
                    'Missing auction ID ($auctionId). Split could not be created.',
                  );
                }
                return;
              }
              // Then continue with the normal bid acceptance flow
              await continueAcceptFlow();
            },
          );
        } else {
          // No split needed – proceed normally
          await continueAcceptFlow();
        }
      } else {
        // If we can't get shipping info, try to accept bid directly (backward compatibility)
        await _confirmBidAcceptance(bid);
      }
    } catch (e) {
      print('❌ Error in _acceptBid: $e');
      // On error, try to accept bid directly (backward compatibility)
      await _confirmBidAcceptance(bid);
    }
  }

  // Confirm bid acceptance and update order status
  Future<void> _confirmBidAcceptance(Map<String, dynamic> bid) async {
    try {
      final orderId = _currentOrder['id'];
      final bidId = bid['id'];

      print('✅ Confirming bid acceptance for Order #$orderId, Bid #$bidId...');

      final response = await ApiService.acceptDriverBid(orderId, bidId);

      print('📥 Accept bid response: $response');

      if (!mounted) return;

      if (response['success'] == true) {
        // Update order with accepted driver
        final autoCharge = response['auto_charge'] as Map<String, dynamic>?;
        final finalStatus = response['shipping_payment_status']?.toString();

        setState(() {
          _currentOrder['driver_id'] = bid['driver_id'];
          _currentOrder['driver_username'] = bid['driver_username'];
          _currentOrder['status'] = 'accepted';
          // Update shipping payment status from auto-charge result
          if (finalStatus != null && finalStatus.isNotEmpty) {
            _shippingPaymentStatus = finalStatus;
            _buyerPaysShipping = finalStatus == 'pending';
            if (autoCharge != null && autoCharge['amount'] != null) {
              _shippingCostDue = (autoCharge['amount'] as num).toDouble();
            }
            if (finalStatus == 'paid' && autoCharge != null) {
              _shippingPaymentType = autoCharge['method']?.toString();
            }
          }
        });

        final l10n = AppLocalizations.of(context)!;
        if (autoCharge != null && autoCharge['paid'] == true) {
          final amount = (autoCharge['amount'] as num?)?.toStringAsFixed(2) ?? '';
          final method = autoCharge['method']?.toString() ?? '';
          TopNotification.success(
            context,
            '${l10n.driverSelected} · \$$amount ${l10n.shippingPaymentPaid} ($method)',
          );
        } else {
          TopNotification.success(
            context,
            'Driver ${bid['driver_username']} accepted! Order confirmed.',
          );
        }

        // Callback to refresh parent
        widget.onOrderUpdated?.call();

        // Close modal (deferred to avoid navigator lock during gesture transitions)
        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final nav = Navigator.of(context);
            if (nav.canPop()) {
              nav.maybePop();
            }
          });
        }
      } else {
        print(
          '❌ Accept bid failed: ${response['error'] ?? response['message']}',
        );
        TopNotification.error(
          context,
          response['error'] ?? response['message'] ?? AppLocalizations.of(context)!.failedToAcceptBid,
        );
      }
    } catch (e) {
      print('❌ Error confirming bid acceptance: $e');
      if (mounted) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)!.errorAcceptingBid(e.toString()),
        );
      }
    }
  }

  // Show driver confirmation modal when seller pays shipping
  Future<void> _showDriverConfirmationModal({
    required Map<String, dynamic> bid,
    required String incoterm,
  }) async {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final driverUsername = bid['driver_username'] ?? 'Driver';
    final bidAmount = _parseBidAmount(bid['bid_amount']);

    final confirmed = await TradeRepublicBottomSheet.show<bool>(
      context: context,
      showDragHandle: true,
      child: Builder(
        builder: (sheetContext) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
              // Success icon (monochrome TR)
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: TradeRepublicTheme.fillColor(
                    context,
                    opacity: Theme.of(context).brightness == Brightness.dark
                        ? 0.12
                        : 0.08,
                  ),
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Icon(
                  CupertinoIcons.cube_box_fill,
                  color: TradeRepublicTheme.textColor(context)
                      .withValues(alpha: 0.88),
                  size: 40,
                ),
              ),
              const SizedBox(height: 20),

              // Title
              Text(
                l10n.confirmDriverSelection,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : Colors.black,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 12),

              // Incoterm info
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: TradeRepublicTheme.fillColor(context, opacity: 0.08),
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(
                    color: TradeRepublicTheme.textColor(context)
                        .withValues(alpha: 0.12),
                  ),
                ),

                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      CupertinoIcons.hammer_fill,
                      color: TradeRepublicTheme.textColor(context)
                          .withValues(alpha: 0.75),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      AppLocalizations.of(
                        context,
                      )!.incotermLabel(incoterm.toUpperCase()),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: TradeRepublicTheme.textColor(context),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: TradeRepublicTheme.fillColor(
                          context,
                          opacity: 0.12,
                        ),
                        borderRadius: BorderRadius.circular(25),
                      ),

                      child: Text(
                        l10n.sellerPays,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: TradeRepublicTheme.hintColor(
                            context,
                            opacity: 0.85,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Driver info card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark
                      ? TradeRepublicTheme.darkElevated
                      : TradeRepublicTheme.lightSurface,
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(
                    color: TradeRepublicTheme.textColor(context)
                        .withValues(alpha: 0.08),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: TradeRepublicTheme.fillColor(
                          context,
                          opacity: 0.1,
                        ),
                        borderRadius: BorderRadius.circular(25),
                      ),

                      child: Icon(
                        CupertinoIcons.person_fill,
                        color: TradeRepublicTheme.textColor(context)
                            .withValues(alpha: 0.72),
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            driverUsername,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            AppLocalizations.of(
                              context,
                            )!.shippingCostAmount(bidAmount.toString()),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? Colors.white.withOpacity(0.6)
                                  : Colors.black.withOpacity(0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Info text
              Text(
                AppLocalizations.of(
                  context,
                )!.theSellerWillPayForTheShippingCostsAccordi,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark
                      ? Colors.white.withOpacity(0.6)
                      : Colors.black.withOpacity(0.6),
                ),
              ),
              const SizedBox(height: 24),

              // Buttons
              Row(
                children: [
                  // Cancel button
                  Expanded(
                    child: TradeRepublicButton(
                      label: l10n.cancel,
                      isSecondary: true,
                      onPressed: () => Navigator.of(sheetContext).pop(false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Confirm button
                  Expanded(
                    flex: 2,
                    child: TradeRepublicButton(
                      label: l10n.confirmDriver,
                      onPressed: () => Navigator.of(sheetContext).pop(true),
                    ),
                  ),
                ],
              ),
              ],
            ),
          ),
        ),
      ),
    );

    if (!mounted) return;
    if (confirmed == true) {
      await _confirmBidAcceptance(bid);
    }
  }

  // Show shipping payment modal - Full checkout-style UI matching payment methods sheet
  Future<void> _showShippingPaymentModal({
    required Map<String, dynamic> bid,
    required double shippingCost,
    required String incoterm,
  }) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Show loading while fetching payment methods
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      isDismissible: false,
      enableDrag: false,
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CultiooLoadingIndicator()),
      ),
    );

    // Load saved payment methods
    List<Map<String, dynamic>> savedCards = [];
    List<Map<String, dynamic>> sepaAccounts = [];
    List<Map<String, dynamic>> achAccounts = [];
    List<Map<String, dynamic>> wireAccounts = [];

    String selectedPaymentMethod = 'card';
    Map<String, dynamic>? selectedSavedCard;

    try {
      var paymentMethods = await ApiService.getUserPaymentMethods();
      print('💳 Payment methods loaded: ${paymentMethods.length}');
      print('💳 Payment methods data: $paymentMethods');

      if (paymentMethods.isEmpty) {
        await Future.delayed(const Duration(seconds: 2));
        paymentMethods = await ApiService.getUserPaymentMethods();
        print('💳 Payment methods after retry: ${paymentMethods.length}');
      }

      if (paymentMethods.isNotEmpty) {
        savedCards = paymentMethods
            .where((m) => m['type'] == 'card')
            .toList()
            .cast<Map<String, dynamic>>();
        sepaAccounts = paymentMethods
            .where((m) => m['type'] == 'sepa' || m['type'] == 'sepa_debit')
            .toList()
            .cast<Map<String, dynamic>>();
        achAccounts = paymentMethods
            .where((m) => m['type'] == 'ach' || m['type'] == 'us_bank_account')
            .toList()
            .cast<Map<String, dynamic>>();
        wireAccounts = paymentMethods
            .where((m) => m['type'] == 'wire')
            .toList()
            .cast<Map<String, dynamic>>();

        print('💳 Saved cards: ${savedCards.length}');
        print('💳 SEPA accounts: ${sepaAccounts.length}');
        print('💳 ACH accounts: ${achAccounts.length}');
        print('💳 Wire accounts: ${wireAccounts.length}');
      }

      if (savedCards.isNotEmpty) {
        selectedPaymentMethod = 'saved_card';
        selectedSavedCard = savedCards[0];
      }
    } catch (e) {
      print('❌ Error loading payment methods: $e');
    }

    // Close loading dialog
    if (mounted) {
      Navigator.pop(context);
    }

    if (!mounted) return;

    await TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      maxHeight: MediaQuery.of(context).size.height * 0.9,
      child: StatefulBuilder(
        builder: (context, setModalState) {
          return Column(
            children: [
              // Header with icon
              Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.blue.shade700, Colors.blue.shade500],
                        ),
                        borderRadius: BorderRadius.circular(25),
                      ),

                      child: const Icon(
                        CupertinoIcons.cube_box_fill,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLocalizations.of(context)!.payShippingCost,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: isDark ? Colors.white : Colors.black,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            AppLocalizations.of(context)!.selectAPaymentMethod,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: (isDark ? Colors.white : Colors.black)
                                  .withOpacity(0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(
                    left: 24,
                    right: 24,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 40,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Shipping Details Card
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: isDark
                                ? [
                                    Colors.blue.shade700.withOpacity(0.3),
                                    Colors.blue.shade900.withOpacity(0.2),
                                  ]
                                : [Colors.blue.shade50, Colors.blue.shade100],
                          ),
                          borderRadius: BorderRadius.circular(25),
                        ),

                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(25),
                                      ),
                                      child: Icon(
                                        CupertinoIcons.money_dollar_circle_fill,
                                        color: Colors.blue.shade400,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      AppLocalizations.of(context)!.totalAmount,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: isDark
                                            ? Colors.white.withOpacity(0.8)
                                            : Colors.black.withOpacity(0.7),
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  _formatCurrency(shippingCost),
                                  style: TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w800,
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Container(
                              height: 1,
                              color: (isDark ? Colors.white : Colors.black)
                                  .withOpacity(0.1),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      CupertinoIcons.arrow_left_right,
                                      size: 18,
                                      color: isDark
                                          ? Colors.white.withOpacity(0.6)
                                          : Colors.black.withOpacity(0.5),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Incoterm',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: isDark
                                            ? Colors.white.withOpacity(0.6)
                                            : Colors.black.withOpacity(0.5),
                                      ),
                                    ),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: TradeRepublicTheme.fillColor(
                                      context,
                                      opacity: isDark ? 0.12 : 0.07,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: TradeRepublicTheme.textColor(
                                        context,
                                      ).withValues(alpha: 0.1),
                                    ),
                                  ),
                                  child: Text(
                                    incoterm.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: TradeRepublicTheme.textColor(
                                        context,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      CupertinoIcons.person_fill,
                                      size: 18,
                                      color: isDark
                                          ? Colors.white.withOpacity(0.6)
                                          : Colors.black.withOpacity(0.5),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      AppLocalizations.of(context)!.driver,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: isDark
                                            ? Colors.white.withOpacity(0.6)
                                            : Colors.black.withOpacity(0.5),
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  bid['driver_username'] ?? 'N/A',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),

                      // Saved Payment Methods Section
                      if (savedCards.isNotEmpty ||
                          sepaAccounts.isNotEmpty ||
                          achAccounts.isNotEmpty ||
                          wireAccounts.isNotEmpty) ...[
                        Text(
                          AppLocalizations.of(context)!.savedPaymentMethods,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white54 : Colors.black45,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Saved Cards
                        ...savedCards.map((card) {
                          final isSelected =
                              selectedPaymentMethod == 'saved_card' &&
                              selectedSavedCard?['id'] == card['id'];
                          final cardData = card['card'] as Map<String, dynamic>? ?? card;
                          final brand = (cardData['brand'] ?? card['brand'] ?? 'card').toString();
                          final last4 = (cardData['last4'] ?? card['last4'] ?? '????').toString();
                          final expM = (cardData['exp_month'] ?? card['exp_month'] ?? '').toString();
                          final expY = (cardData['exp_year'] ?? card['exp_year'] ?? '').toString();
                          final isDefault = card['is_default'] == true || card['isDefault'] == true;
                          return _buildCardSelectionTile(
                            isSelected: isSelected,
                            onTap: () => setModalState(() {
                              selectedPaymentMethod = 'saved_card';
                              selectedSavedCard = card;
                            }),
                            child: CreditCardWidget(
                              brand: brand, last4: last4,
                              expMonth: expM, expYear: expY,
                              isDefault: isDefault,
                            ),
                          );
                        }),

                        // Saved SEPA
                        ...sepaAccounts.map((sepa) {
                          final isSelected =
                              selectedPaymentMethod == 'saved_sepa' &&
                              selectedSavedCard?['id'] == sepa['id'];
                          final last4 = (sepa['iban_last4'] ?? sepa['last4'] ?? '????').toString();
                          final holder = (sepa['account_holder_name'] ?? '').toString();
                          return _buildCardSelectionTile(
                            isSelected: isSelected,
                            onTap: () => setModalState(() {
                              selectedPaymentMethod = 'saved_sepa';
                              selectedSavedCard = sepa;
                            }),
                            child: BankAccountWidget(
                              type: 'sepa', maskedNumber: last4,
                              accountHolderName: holder, isDefault: sepa['is_default'] == true,
                            ),
                          );
                        }),

                        // Saved ACH
                        ...achAccounts.map((ach) {
                          final isSelected =
                              selectedPaymentMethod == 'saved_ach' &&
                              selectedSavedCard?['id'] == ach['id'];
                          final last4 = (ach['account_number_last4'] ?? ach['last4'] ?? '????').toString();
                          final holder = (ach['account_holder_name'] ?? '').toString();
                          final routing = ach['routing_number']?.toString();
                          return _buildCardSelectionTile(
                            isSelected: isSelected,
                            onTap: () => setModalState(() {
                              selectedPaymentMethod = 'saved_ach';
                              selectedSavedCard = ach;
                            }),
                            child: BankAccountWidget(
                              type: 'ach', maskedNumber: last4,
                              accountHolderName: holder, routingOrSwift: routing,
                              isDefault: ach['is_default'] == true,
                            ),
                          );
                        }),

                        // Saved Wire
                        ...wireAccounts.map((wire) {
                          final isSelected =
                              selectedPaymentMethod == 'saved_wire' &&
                              selectedSavedCard?['id'] == wire['id'];
                          final last4 = (wire['account_number_last4'] ?? wire['last4'] ?? '????').toString();
                          final holder = (wire['account_holder_name'] ?? '').toString();
                          final swift = wire['swift_bic']?.toString() ?? wire['routing_number']?.toString();
                          return _buildCardSelectionTile(
                            isSelected: isSelected,
                            onTap: () => setModalState(() {
                              selectedPaymentMethod = 'saved_wire';
                              selectedSavedCard = wire;
                            }),
                            child: BankAccountWidget(
                              type: 'wire', maskedNumber: last4,
                              accountHolderName: holder, routingOrSwift: swift,
                              isDefault: wire['is_default'] == true,
                            ),
                          );
                        }),

                        const SizedBox(height: 20),
                      ],

                      // Instant Payment Section
                      Text(
                        AppLocalizations.of(context)!.instantPayment,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white54 : Colors.black45,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 12),

                      _buildShippingPaymentOption(
                        isSelected: selectedPaymentMethod == 'card',
                        isDark: isDark,
                        icon: CupertinoIcons.creditcard,
                        title: AppLocalizations.of(context)!.creditOrDebitCard,
                        subtitle: AppLocalizations.of(
                          context,
                        )!.visaMastercardAmex,
                        color: Colors.blue.shade400,
                        onTap: () {
                          setModalState(() {
                            selectedPaymentMethod = 'card';
                            selectedSavedCard = null;
                          });
                        },
                      ),

                      const SizedBox(height: 20),

                      // Bank Transfer Section
                      Text(
                        AppLocalizations.of(context)!.bankTransfer,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white54 : Colors.black45,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 12),

                      _buildShippingPaymentOption(
                        isSelected: selectedPaymentMethod == 'sepa',
                        isDark: isDark,
                        icon: CupertinoIcons.building_2_fill,
                        title: AppLocalizations.of(context)!.sepaDirectDebit,
                        subtitle: AppLocalizations.of(
                          context,
                        )!.bankAccount13Days,
                        color: Colors.purple.shade400,
                        onTap: () {
                          setModalState(() {
                            selectedPaymentMethod = 'sepa';
                            selectedSavedCard = null;
                          });
                        },
                      ),

                      _buildShippingPaymentOption(
                        isSelected: selectedPaymentMethod == 'ach',
                        isDark: isDark,
                        icon: CupertinoIcons.money_dollar_circle_fill,
                        title: AppLocalizations.of(context)!.achDirectDebit,
                        subtitle: AppLocalizations.of(context)!.businessDaysLowerFees,
                        color: Colors.teal.shade400,
                        onTap: () {
                          setModalState(() {
                            selectedPaymentMethod = 'ach';
                            selectedSavedCard = null;
                          });
                        },
                      ),

                      _buildShippingPaymentOption(
                        isSelected: selectedPaymentMethod == 'wire',
                        isDark: isDark,
                        icon: CupertinoIcons.arrow_right_arrow_left,
                        title: AppLocalizations.of(context)!.wireTransfer,
                        subtitle: AppLocalizations.of(
                          context,
                        )!.sameOrNextBusinessDay,
                        color: Colors.deepPurple.shade400,
                        onTap: () {
                          setModalState(() {
                            selectedPaymentMethod = 'wire';
                            selectedSavedCard = null;
                          });
                        },
                      ),

                      const SizedBox(height: 20),

                      // Payment Terms Section
                      Text(
                        AppLocalizations.of(context)!.paymentTermsB2b,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white54 : Colors.black45,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 12),

                      _buildShippingPaymentOption(
                        isSelected: selectedPaymentMethod == 'net_30',
                        isDark: isDark,
                        icon: CupertinoIcons.calendar,
                        title: AppLocalizations.of(context)!.net30,
                        subtitle: AppLocalizations.of(
                          context,
                        )!.payWithin30DaysBusinessOnly,
                        color: Colors.orange.shade400,
                        onTap: () {
                          setModalState(() {
                            selectedPaymentMethod = 'net_30';
                            selectedSavedCard = null;
                          });
                        },
                      ),

                      _buildShippingPaymentOption(
                        isSelected: selectedPaymentMethod == 'net_60',
                        isDark: isDark,
                        icon: CupertinoIcons.calendar_badge_plus,
                        title: AppLocalizations.of(context)!.net60,
                        subtitle: AppLocalizations.of(
                          context,
                        )!.payWithin60DaysBusinessOnly,
                        color: Colors.orange.shade600,
                        onTap: () {
                          setModalState(() {
                            selectedPaymentMethod = 'net_60';
                            selectedSavedCard = null;
                          });
                        },
                      ),

                      const SizedBox(height: 28),

                      // Pay Button
                      TradeRepublicButton(
                        label: selectedPaymentMethod == 'net_30'
                            ? AppLocalizations.of(context)!.acceptNet30Terms
                            : selectedPaymentMethod == 'net_60'
                            ? AppLocalizations.of(context)!.acceptNet60Terms
                            : AppLocalizations.of(
                                context,
                              )!.payAmount(_formatCurrency(shippingCost)),
                        onPressed: () async {
                          if (selectedPaymentMethod == 'saved_card' ||
                              selectedPaymentMethod == 'saved_sepa' ||
                              selectedPaymentMethod == 'saved_ach' ||
                              selectedPaymentMethod == 'saved_wire') {
                            if (selectedSavedCard != null) {
                              Navigator.pop(context);
                              await _processShippingPayment(
                                bid: bid,
                                amount: shippingCost,
                                paymentMethodId: selectedSavedCard!['id'],
                              );
                            }
                          } else if (selectedPaymentMethod == 'card') {
                            Navigator.pop(context);
                            _showCardPaymentSheetForShipping(
                              isDark,
                              bid,
                              shippingCost,
                            );
                          } else if (selectedPaymentMethod == 'sepa') {
                            Navigator.pop(context);
                            _showSepaPaymentSheetForShipping(
                              isDark,
                              bid,
                              shippingCost,
                            );
                          } else if (selectedPaymentMethod == 'ach') {
                            Navigator.pop(context);
                            _showAchPaymentSheetForShipping(
                              isDark,
                              bid,
                              shippingCost,
                            );
                          } else if (selectedPaymentMethod == 'wire') {
                            Navigator.pop(context);
                            _showWirePaymentSheetForShipping(
                              isDark,
                              bid,
                              shippingCost,
                            );
                          } else if (selectedPaymentMethod == 'net_30') {
                            Navigator.pop(context);
                            _showBusinessInfoSheetForShipping(
                              isDark: isDark,
                              bid: bid,
                              shippingCost: shippingCost,
                              paymentType: 'payment_30_days',
                            );
                          } else if (selectedPaymentMethod == 'net_60') {
                            Navigator.pop(context);
                            _showBusinessInfoSheetForShipping(
                              isDark: isDark,
                              bid: bid,
                              shippingCost: shippingCost,
                              paymentType: 'payment_60_days',
                            );
                          }
                        },
                        width: double.infinity,
                      ),
                      const SizedBox(height: 16),

                      // Security info
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            CupertinoIcons.lock,
                            size: 14,
                            color: isDark
                                ? Colors.white.withOpacity(0.4)
                                : Colors.black.withOpacity(0.3),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            AppLocalizations.of(
                              context,
                            )!.paymentsSecuredByStripe,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? Colors.white.withOpacity(0.4)
                                  : Colors.black.withOpacity(0.3),
                            ),
                          ),
                        ],
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

  // Manual order split modal


  // Perform manual order split API call


  // Helper method to build shipping payment option (checkout style)
  Widget _buildCardSelectionTile({
    required bool isSelected,
    required VoidCallback onTap,
    required Widget child,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          children: [
            child,
            if (isSelected)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 2),
                  ),
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(CupertinoIcons.checkmark, color: Colors.black, size: 13),
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

  Widget _buildShippingPaymentOption({
    required bool isSelected,
    required bool isDark,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    final normalizedTitle = _normalizeSheetLabel(title);
    final normalizedSubtitle = _normalizeSheetLabel(subtitle);
    final subtitleToShow = normalizedSubtitle.toLowerCase() ==
            normalizedTitle.toLowerCase()
        ? ''
        : normalizedSubtitle;

    return TradeRepublicListTile(
      title: normalizedTitle,
      subtitle: subtitleToShow,
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      trailing: isSelected
          ? Icon(CupertinoIcons.checkmark_circle_fill, color: color, size: 20)
          : null,
      onTap: onTap,
    );
  }

  // Process shipping payment with Stripe
  Future<void> _processShippingPayment({
    required Map<String, dynamic> bid,
    required double amount,
    String? paymentMethodId,
  }) async {
    try {
      final orderId = _currentOrder['id'];
      final bidId = bid['id'];

      print('💳 Processing shipping payment for order #$orderId, bid #$bidId');
      print('💳 Amount: $amount');
      print('💳 Payment method ID: $paymentMethodId');

      // Show loading
      TradeRepublicBottomSheet.show(
        context: context,
        showDragHandle: true,
        isDismissible: false,
        enableDrag: false,
        child: const Padding(
          padding: EdgeInsets.only(bottom: 40),
          child: Center(child: CultiooLoadingIndicator()),
        ),
      );

      // TODO: Call API to process shipping payment
      // final response = await ApiService.processShippingPayment(
      //   orderId: orderId,
      //   bidId: bidId,
      //   amount: amount,
      //   paymentMethodId: paymentMethodId,
      // );

      // Simulate API call for now
      await Future.delayed(const Duration(seconds: 2));

      if (!mounted) return;

      // Close loading
      Navigator.pop(context);

      // Show success
      TopNotification.success(
        context,
        AppLocalizations.of(context)!.shippingPaymentSuccessfulConfirmingDriver,
      );

      // Now confirm the bid acceptance (which will update status to 'accepted')
      await _confirmBidAcceptance(bid);

      if (!mounted) return;

      // Send invoice email after successful payment
      try {
        print('📧 Sending invoice email for order #$orderId...');
        final invoiceResult = await ApiService.sendInvoiceEmail(orderId);
        if (!mounted) return;
        if (invoiceResult['success'] == true) {
          print('✅ Invoice email sent successfully');
          TopNotification.info(
            context,
            AppLocalizations.of(context)!.invoiceSentToEmail,
          );
        } else {
          print('⚠️ Failed to send invoice: ${invoiceResult['message']}');
          // Don't show error to user - payment was successful, invoice is optional
        }
      } catch (invoiceError) {
        print('❌ Error sending invoice email: $invoiceError');
        // Don't fail the payment process if invoice sending fails
      }
    } catch (e) {
      print('❌ Error processing shipping payment: $e');

      if (!mounted) return;

      // Close loading if still open
      Navigator.pop(context);

      TopNotification.error(
        context,
        AppLocalizations.of(
          context,
        )!.errorProcessingShippingPayment(e.toString()),
      );
    }
  }

  // Show Business Info Sheet for Net 30/60 Shipping Payment
  void _showBusinessInfoSheetForShipping({
    required bool isDark,
    required Map<String, dynamic> bid,
    required double shippingCost,
    required String paymentType,
  }) {
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
      default:
        title = AppLocalizations.of(context)!.businessPayment;
        description = AppLocalizations.of(context)!.businessPaymentDetailsRequired;
    }

    // Calculate if over limit and fee
    final remainingLimit = _monthlyPaymentLimit - _currentMonthUsage;
    final isOverLimit = shippingCost > remainingLimit;
    final overLimitAmount = isOverLimit ? shippingCost - remainingLimit : 0.0;
    final overLimitFee = overLimitAmount * (_overLimitFeePercent / 100);

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      maxHeight: MediaQuery.of(context).size.height * 0.95,
      child: _ShippingNetPaymentSheet(
        isDark: isDark,
        title: title,
        description: description,
        days: days,
        shippingCost: shippingCost,
        remainingLimit: remainingLimit,
        isOverLimit: isOverLimit,
        overLimitFee: overLimitFee,
        paymentType: paymentType,
        bid: bid,
        businessNameController: _businessNameController,
        businessTaxIdController: _businessTaxIdController,
        businessEmailController: _businessEmailController,
        businessPhoneController: _businessPhoneController,
        businessStreetController: _businessStreetController,
        businessHouseNumberController: _businessHouseNumberController,
        businessPostalCodeController: _businessPostalCodeController,
        businessCityController: _businessCityController,
        businessCountryController: _businessCountryController,
        isLoadingBusinessInfo: _isLoadingBusinessInfo,
        formatCurrency: _formatCurrency,
        monthlyPaymentLimit: _monthlyPaymentLimit,
        currentMonthUsage: _currentMonthUsage,
        overLimitFeePercent: _overLimitFeePercent,
        validateBusinessInfo: _validateShippingBusinessInfo,
        submitBusinessInfo: (type) => _submitShippingBusinessInfo(
          paymentType: type,
          bid: bid,
          shippingCost: shippingCost,
        ),
        onClose: () => Navigator.pop(context),
      ),
    );
  }

  // Validate business info for shipping payment terms
  bool _validateShippingBusinessInfo() {
    if (_businessNameController.text.trim().isEmpty) {
      TopNotification.error(
        context,
        AppLocalizations.of(context)!.pleaseEnterYourBusinessName,
      );
      return false;
    }
    if (_businessTaxIdController.text.trim().isEmpty) {
      TopNotification.error(
        context,
        AppLocalizations.of(context)!.pleaseEnterYourTaxIdEin,
      );
      return false;
    }
    if (_businessEmailController.text.trim().isEmpty) {
      TopNotification.error(
        context,
        AppLocalizations.of(context)!.pleaseEnterYourBusinessEmail,
      );
      return false;
    }
    if (_businessPhoneController.text.trim().isEmpty) {
      TopNotification.error(
        context,
        AppLocalizations.of(context)!.pleaseEnterYourBusinessPhone,
      );
      return false;
    }
    if (_businessStreetController.text.trim().isEmpty) {
      TopNotification.error(
        context,
        AppLocalizations.of(context)!.pleaseEnterYourStreetAddress,
      );
      return false;
    }
    if (_businessCityController.text.trim().isEmpty) {
      TopNotification.error(
        context,
        AppLocalizations.of(context)!.pleaseEnterYourCity,
      );
      return false;
    }
    if (_businessPostalCodeController.text.trim().isEmpty) {
      TopNotification.error(
        context,
        AppLocalizations.of(context)!.pleaseEnterYourPostalCode,
      );
      return false;
    }
    if (_businessCountryController.text.trim().isEmpty) {
      TopNotification.error(
        context,
        AppLocalizations.of(context)!.pleaseEnterYourCountry,
      );
      return false;
    }
    return true;
  }

  // Submit business info and process shipping payment terms
  Future<void> _submitShippingBusinessInfo({
    required String paymentType,
    required Map<String, dynamic> bid,
    required double shippingCost,
  }) async {
    setState(() => _isLoadingBusinessInfo = true);

    try {
      final orderId = _currentOrder['id'];
      final bidId = bid['id'];

      print('💼 Submitting business info for shipping payment terms');
      print('💼 Payment type: $paymentType');
      print('💼 Order ID: $orderId, Bid ID: $bidId');
      print('💼 Shipping cost: $shippingCost');

      // Collect business info
      final businessInfo = {
        'business_name': _businessNameController.text.trim(),
        'tax_id': _businessTaxIdController.text.trim(),
        'email': _businessEmailController.text.trim(),
        'phone': _businessPhoneController.text.trim(),
        'street': _businessStreetController.text.trim(),
        'house_number': _businessHouseNumberController.text.trim(),
        'postal_code': _businessPostalCodeController.text.trim(),
        'city': _businessCityController.text.trim(),
        'country': _businessCountryController.text.trim(),
      };

      print('💼 Business info: $businessInfo');

      // TODO: Call API to verify business and process payment terms
      // For now, simulate the process
      await Future.delayed(const Duration(seconds: 2));

      if (!mounted) return;

      // Show success and process the shipping payment
      TopNotification.success(
        context,
        AppLocalizations.of(context)!.businessVerifiedProcessingPaymentTerms,
      );

      // Process the shipping payment with payment terms
      await _processShippingPayment(
        bid: bid,
        amount: shippingCost,
        paymentMethodId: paymentType == 'payment_30_days' ? 'net_30' : 'net_60',
      );
    } catch (e) {
      print('❌ Error submitting business info: $e');
      if (mounted) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)!.errorGeneric(e.toString()),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingBusinessInfo = false);
      }
    }
  }

  // Helper method to build payment method option
  String _normalizeSheetLabel(String text) {
    final words = text
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.length < 2) return text.trim();

    final cleaned = <String>[];
    for (final word in words) {
      if (cleaned.isEmpty || cleaned.last.toLowerCase() != word.toLowerCase()) {
        cleaned.add(word);
      }
    }
    return cleaned.join(' ');
  }

  Widget _buildPaymentMethodOption(
    String value,
    String title,
    IconData icon,
    Color color,
    String selectedPaymentMethod,
    Function(String) onChanged,
    bool isDark,
    bool enabled, {
    String? subtitle,
  }) {
    final isSelected = selectedPaymentMethod == value;
    final normalizedTitle = _normalizeSheetLabel(title);
    final normalizedSubtitle =
        subtitle == null ? null : _normalizeSheetLabel(subtitle);
    final showSubtitle = normalizedSubtitle != null &&
        normalizedSubtitle.trim().isNotEmpty &&
        normalizedSubtitle.toLowerCase() != normalizedTitle.toLowerCase();

    return GestureDetector(
      onTap: enabled ? () => onChanged(value) : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withOpacity(0.1)
              : (isDark
                    ? const Color(0xFF141414)
                    : Colors.black.withOpacity(0.02)),
          borderRadius: BorderRadius.circular(25),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(25),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    normalizedTitle,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                  if (showSubtitle) ...[
                    const SizedBox(height: 2),
                    Text(
                      normalizedSubtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? Colors.white.withOpacity(0.5)
                            : Colors.black.withOpacity(0.4),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (isSelected)
              Icon(
                CupertinoIcons.checkmark_circle_fill,
                color: color,
                size: 24,
              ),
          ],
        ),
      ),
    );
  }

  // Helper method to build saved card option
  Widget _buildSavedCardOption(
    Map<String, dynamic> card,
    Map<String, dynamic>? selectedSavedCard,
    Function(Map<String, dynamic>) onChanged,
    bool isDark,
  ) {
    final isSelected = selectedSavedCard?['id'] == card['id'];
    final color = TradeRepublicTheme.textColor(context);

    return TradeRepublicListTile(
      title: '•••• ${card['last4'] ?? '****'} ${card['brand']?.toString().toUpperCase() ?? 'Card'}',
      leading: Icon(CupertinoIcons.creditcard_fill, color: color, size: 20),
      trailing: isSelected
          ? Icon(CupertinoIcons.checkmark_circle_fill, color: color, size: 20)
          : null,
      onTap: () => onChanged(card),
    );
  }

  // Helper method to build saved SEPA option
  Widget _buildSavedSepaOption(
    Map<String, dynamic> sepa,
    Map<String, dynamic>? selectedSavedCard,
    Function(Map<String, dynamic>) onChanged,
    bool isDark,
  ) {
    final isSelected = selectedSavedCard?['id'] == sepa['id'];
    final color = TradeRepublicTheme.textColor(context);

    return TradeRepublicListTile(
      title: 'SEPA •••• ${sepa['iban']?.toString().length != null && sepa['iban'].toString().length >= 4 ? sepa['iban']!.toString().substring(sepa['iban']!.toString().length - 4) : '****'}',
      leading: Icon(CupertinoIcons.building_2_fill, color: color, size: 20),
      trailing: isSelected
          ? Icon(CupertinoIcons.checkmark_circle_fill, color: color, size: 20)
          : null,
      onTap: () => onChanged(sepa),
    );
  }

  // Helper method to build saved ACH option
  Widget _buildSavedAchOption(
    Map<String, dynamic> ach,
    Map<String, dynamic>? selectedSavedCard,
    Function(Map<String, dynamic>) onChanged,
    bool isDark,
  ) {
    final isSelected = selectedSavedCard?['id'] == ach['id'];
    final color = TradeRepublicTheme.textColor(context);

    return TradeRepublicListTile(
      title: 'ACH •••• ${ach['account_number']?.toString().length != null && ach['account_number'].toString().length >= 4 ? ach['account_number']!.toString().substring(ach['account_number']!.toString().length - 4) : '****'}',
      leading: Icon(CupertinoIcons.money_dollar_circle_fill, color: color, size: 20),
      trailing: isSelected
          ? Icon(CupertinoIcons.checkmark_circle_fill, color: color, size: 20)
          : null,
      onTap: () => onChanged(ach),
    );
  }

  // Helper method to build saved Wire option
  Widget _buildSavedWireOption(
    Map<String, dynamic> wire,
    Map<String, dynamic>? selectedSavedCard,
    Function(Map<String, dynamic>) onChanged,
    bool isDark,
  ) {
    final isSelected = selectedSavedCard?['id'] == wire['id'];
    final color = TradeRepublicTheme.textColor(context);

    return TradeRepublicListTile(
      title: 'Wire •••• ${wire['account_number']?.toString().length != null && wire['account_number'].toString().length >= 4 ? wire['account_number']!.toString().substring(wire['account_number']!.toString().length - 4) : '****'}',
      leading: Icon(CupertinoIcons.arrow_left_right, color: color, size: 20),
      trailing: isSelected
          ? Icon(CupertinoIcons.checkmark_circle_fill, color: color, size: 20)
          : null,
      onTap: () => onChanged(wire),
    );
  }

  // Card Payment Sheet for Shipping
  void _showCardPaymentSheetForShipping(
    bool isDark,
    Map<String, dynamic> bid,
    double shippingCost,
  ) {
    final TextEditingController cardNumberController = TextEditingController();
    final TextEditingController expiryController = TextEditingController();
    final TextEditingController cvvController = TextEditingController();
    final TextEditingController nameController = TextEditingController();

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: Builder(
        builder: (context) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.cardPayment,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    TradeRepublicButton(
                      icon: const Icon(CupertinoIcons.xmark_circle_fill, size: 18),
                      isSecondary: true,
                      width: 44,
                      height: 44,
                      padding: EdgeInsets.zero,
                      borderRadius: BorderRadius.circular(25),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                TradeRepublicTextField(
                  controller: cardNumberController,
                  labelText: AppLocalizations.of(context)!.cardNumber,
                  hintText: '1234 5678 9012 3456',
                  prefixIcon: const Icon(CupertinoIcons.creditcard),
                  keyboardType: TextInputType.number,
                  inputFormatters: [_CardNumberFormatter()],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TradeRepublicTextField(
                        controller: expiryController,
                        labelText: 'Expiry',
                        hintText: 'MM/YY',
                        keyboardType: TextInputType.number,
                        inputFormatters: [_ExpiryDateFormatter()],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TradeRepublicTextField(
                        controller: cvvController,
                        labelText: 'CVV',
                        hintText: '123',
                        keyboardType: TextInputType.number,
                        maxLength: 3,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TradeRepublicTextField(
                  controller: nameController,
                  labelText: AppLocalizations.of(context)!.cardholderName1,
                  hintText: AppLocalizations.of(context)!.johnDoe,
                  prefixIcon: const Icon(CupertinoIcons.person),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 24),
                TradeRepublicButton(
                  label: AppLocalizations.of(
                    context,
                  )!.payAmount(_formatCurrency(shippingCost)),
                  onPressed: () async {
                    Navigator.pop(context);
                    await _processShippingPayment(
                      bid: bid,
                      amount: shippingCost,
                    );
                  },
                  width: double.infinity,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // SEPA Payment Sheet for Shipping
  void _showSepaPaymentSheetForShipping(
    bool isDark,
    Map<String, dynamic> bid,
    double shippingCost,
  ) {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController ibanController = TextEditingController();

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: Builder(
        builder: (context) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.sepaDirectDebit,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    TradeRepublicButton(
                      icon: const Icon(CupertinoIcons.xmark_circle_fill, size: 18),
                      isSecondary: true,
                      width: 44,
                      height: 44,
                      padding: EdgeInsets.zero,
                      borderRadius: BorderRadius.circular(25),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                TradeRepublicTextField(
                  controller: nameController,
                  labelText: AppLocalizations.of(context)!.accountHolderName,
                  prefixIcon: const Icon(CupertinoIcons.person),
                ),
                const SizedBox(height: 16),
                TradeRepublicTextField(
                  controller: ibanController,
                  labelText: AppLocalizations.of(context)!.iban,
                  hintText: 'DE89370400440532013000',
                  prefixIcon: const Icon(CupertinoIcons.building_2_fill),
                  textCapitalization: TextCapitalization.characters,
                ),
                const SizedBox(height: 24),
                TradeRepublicButton(
                  label: AppLocalizations.of(
                    context,
                  )!.payAmount(_formatCurrency(shippingCost)),
                  onPressed: () async {
                    Navigator.pop(context);
                    await _processShippingPayment(
                      bid: bid,
                      amount: shippingCost,
                    );
                  },
                  width: double.infinity,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ACH Payment Sheet for Shipping
  void _showAchPaymentSheetForShipping(
    bool isDark,
    Map<String, dynamic> bid,
    double shippingCost,
  ) {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController routingController = TextEditingController();
    final TextEditingController accountController = TextEditingController();

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: Builder(
        builder: (context) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.achBankTransfer,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    TradeRepublicButton(
                      icon: const Icon(CupertinoIcons.xmark_circle_fill, size: 18),
                      isSecondary: true,
                      width: 44,
                      height: 44,
                      padding: EdgeInsets.zero,
                      borderRadius: BorderRadius.circular(25),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                TradeRepublicTextField(
                  controller: nameController,
                  labelText: AppLocalizations.of(context)!.accountHolderName,
                  prefixIcon: const Icon(CupertinoIcons.person),
                ),
                const SizedBox(height: 16),
                TradeRepublicTextField(
                  controller: routingController,
                  labelText: AppLocalizations.of(context)!.routingNumber,
                  hintText: '110000000',
                  prefixIcon: const Icon(CupertinoIcons.number),
                  keyboardType: TextInputType.number,
                  maxLength: 9,
                ),
                const SizedBox(height: 16),
                TradeRepublicTextField(
                  controller: accountController,
                  labelText: AppLocalizations.of(context)!.accountNumber,
                  prefixIcon: const Icon(CupertinoIcons.building_2_fill),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 24),
                TradeRepublicButton(
                  label: AppLocalizations.of(
                    context,
                  )!.payAmount(_formatCurrency(shippingCost)),
                  onPressed: () async {
                    Navigator.pop(context);
                    await _processShippingPayment(
                      bid: bid,
                      amount: shippingCost,
                    );
                  },
                  width: double.infinity,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Wire Payment Sheet for Shipping
  void _showWirePaymentSheetForShipping(
    bool isDark,
    Map<String, dynamic> bid,
    double shippingCost,
  ) {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController routingController = TextEditingController();
    final TextEditingController accountController = TextEditingController();

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: Builder(
        builder: (context) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.wireTransfer,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    TradeRepublicButton(
                      icon: const Icon(CupertinoIcons.xmark_circle_fill, size: 18),
                      isSecondary: true,
                      width: 44,
                      height: 44,
                      padding: EdgeInsets.zero,
                      borderRadius: BorderRadius.circular(25),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                TradeRepublicTextField(
                  controller: nameController,
                  labelText: AppLocalizations.of(context)!.accountHolderName,
                  prefixIcon: const Icon(CupertinoIcons.person),
                ),
                const SizedBox(height: 16),
                TradeRepublicTextField(
                  controller: routingController,
                  labelText: AppLocalizations.of(context)!.swiftbicCode,
                  hintText: 'DEUTDEFF',
                  prefixIcon: const Icon(CupertinoIcons.barcode),
                  textCapitalization: TextCapitalization.characters,
                ),
                const SizedBox(height: 16),
                TradeRepublicTextField(
                  controller: accountController,
                  labelText: AppLocalizations.of(context)!.accountNumber,
                  prefixIcon: const Icon(CupertinoIcons.building_2_fill),
                ),
                const SizedBox(height: 24),
                TradeRepublicButton(
                  label: AppLocalizations.of(
                    context,
                  )!.payAmount(_formatCurrency(shippingCost)),
                  onPressed: () async {
                    Navigator.pop(context);
                    await _processShippingPayment(
                      bid: bid,
                      amount: shippingCost,
                    );
                  },
                  width: double.infinity,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Close/Delete an order
  Future<void> _closeOrder() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Show confirmation bottom sheet first
    final confirmed = await TradeRepublicBottomSheet.show<bool>(
      context: context,
      showDragHandle: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Warning Icon
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                CupertinoIcons.exclamationmark_triangle_fill,
                color: Colors.red.shade400,
                size: 40,
              ),
            ),
            const SizedBox(height: 20),

            // Title
            Text(
              AppLocalizations.of(context)!.cancelOrder1,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 12),

            // Description
            Text(
              AppLocalizations.of(
                context,
              )!.thisActionCannotBeUndoneTheOrderWillBePer,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
                height: 1.4,
              ),
            ),
            const SizedBox(height: 28),

            // Buttons
            Row(
              children: [
                // Keep Order Button
                Expanded(
                  child: TradeRepublicButton(
                    label: AppLocalizations.of(context)!.keepOrder,
                    isSecondary: true,
                    onPressed: () => Navigator.pop(context, false),
                  ),
                ),
                const SizedBox(width: 12),
                // Cancel Order Button
                Expanded(
                  child: TradeRepublicButton(
                    label: AppLocalizations.of(context)!.cancelOrder,
                    isDestructive: true,
                    onPressed: () => Navigator.pop(context, true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    setState(() => _isClosingOrder = true);

    try {
      final rawId = _currentOrder['id'];
      final orderId = rawId is int
          ? rawId
          : int.tryParse(rawId.toString().replaceAll(RegExp(r'[^0-9]'), ''));
      if (orderId == null) {
        if (mounted) {
          TopNotification.error(
            context,
            'Invalid order ID',
          );
        }
        return;
      }
      final response = await ApiService.closeOrder(orderId);

      if (!mounted) return;

      if (response['success'] == true) {
        TopNotification.success(
          context,
          AppLocalizations.of(context)!.orderClosedSuccess,
        );
        widget.onOrderUpdated?.call();
        Navigator.pop(context);
      } else {
        TopNotification.error(
          context,
          response['error'] ?? AppLocalizations.of(context)!.failedToCloseOrder,
        );
      }
    } catch (e) {
      print('❌ Error closing order: $e');
      if (mounted) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)!.errorClosingOrder,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isClosingOrder = false);
      }
    }
  }

  // Show invoice selection bottom sheet
  void _showInvoiceSelectionSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Text(
            AppLocalizations.of(context)!.downloadInvoice,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.of(context)!.chooseWhichInvoiceToDownload,
            style: TextStyle(
              fontSize: 14,
              color: isDark
                  ? Colors.white.withOpacity(0.6)
                  : Colors.black.withOpacity(0.5),
            ),
          ),
          const SizedBox(height: 24),

          // Product Invoice Option
          TradeRepublicListTile.navigation(
            title: AppLocalizations.of(context)!.productInvoice,
            subtitle: AppLocalizations.of(context)!.invoiceForProductPurchase,
            leading: const Icon(CupertinoIcons.bag, size: 20),
            onTap: () {
              Navigator.pop(context);
              _downloadInvoice('product');
            },
          ),
          const SizedBox(height: 12),

          // Driver Invoice Option
          TradeRepublicListTile.navigation(
            title: AppLocalizations.of(context)!.driverInvoice,
            subtitle: AppLocalizations.of(context)!.invoiceForShippingdeliveryService,
            leading: const Icon(CupertinoIcons.cube_box, size: 20),
            onTap: () {
              Navigator.pop(context);
              _downloadInvoice('driver');
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // Download invoice PDF
  Future<void> _downloadInvoice(String invoiceType) async {
    setState(() => _isDownloadingInvoice = true);

    try {
      final orderId = _currentOrder['id'];
      print('📄 Downloading $invoiceType invoice for order #$orderId');

      final pdfBytes = await ApiService.downloadInvoicePdf(orderId);

      if (!mounted) return;

      // Get the downloads directory
      final directory = await getApplicationDocumentsDirectory();
      final fileName = invoiceType == 'product'
          ? 'Product_Invoice_$orderId.pdf'
          : 'Driver_Invoice_$orderId.pdf';
      final filePath = '${directory.path}/$fileName';

      // Write the PDF file
      final file = File(filePath);
      await file.writeAsBytes(pdfBytes);

      print('✅ Invoice saved to: $filePath');

      // Open the PDF file
      final result = await OpenFilex.open(filePath);

      if (!mounted) return;

      if (result.type == ResultType.done) {
        TopNotification.success(
          context,
          '${invoiceType == 'product' ? 'Product' : 'Driver'} invoice downloaded successfully',
        );
      } else if (result.type == ResultType.noAppToOpen) {
        TopNotification.info(
          context,
          AppLocalizations.of(context)!.invoiceSavedNoAppToOpenPdfFiles,
        );
      } else {
        TopNotification.info(
          context,
          AppLocalizations.of(context)!.invoiceSavedTo(filePath),
        );
      }
    } catch (e) {
      print('❌ Error downloading invoice: $e');
      if (mounted) {
        TopNotification.error(
          context,
          'Error downloading invoice: ${e.toString().replaceAll('Exception: ', '')}',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isDownloadingInvoice = false);
      }
    }
  }

  // Check if user has already reviewed this order
  Future<void> _checkReviewStatus() async {
    if (_currentOrder['status']?.toLowerCase() != 'delivered') {
      setState(() {
        _isLoadingReviewStatus = false;
      });
      return;
    }

    try {
      final response = await ApiService.getReviewStatus(_currentOrder['id']);
      if (mounted) {
        setState(() {
          _hasReviewed = response['hasReviewed'] ?? false;
          _isLoadingReviewStatus = false;
        });
      }
    } catch (e) {
      print('❌ Error checking review status: $e');
      if (mounted) {
        setState(() {
          _isLoadingReviewStatus = false;
        });
      }
    }
  }

  // Helper method to safely parse price values that could be String or num
  double _parsePrice(dynamic price) {
    if (price == null) return 0.0;

    if (price is double) return price;
    if (price is int) return price.toDouble();
    if (price is String) {
      String cleanPrice = price.replaceAll(RegExp(r'[^\d.,]'), '');
      cleanPrice = cleanPrice.replaceAll(',', '.');
      return double.tryParse(cleanPrice) ?? 0.0;
    }
    return 0.0;
  }

  // Helper method to safely format bid amount (handles String, int, double)
  String _parseBidAmount(dynamic amount) {
    if (amount == null) return '0.00';
    if (amount is num) return amount.toStringAsFixed(2);
    if (amount is String) {
      final parsed = double.tryParse(amount);
      return parsed?.toStringAsFixed(2) ?? '0.00';
    }
    return '0.00';
  }

  // Helper method to parse quantity values
  double _parseQuantity(dynamic quantity) {
    if (quantity == null) return 1.0;

    if (quantity is double) return quantity;
    if (quantity is int) return quantity.toDouble();
    if (quantity is String) {
      String cleanQty = quantity.replaceAll(RegExp(r'[^\d.,]'), '');
      cleanQty = cleanQty.replaceAll(',', '.');
      return double.tryParse(cleanQty) ?? 1.0;
    }
    return 1.0;
  }

  // Returns true if the given unit string represents a volume (not weight)
  bool _isVolumeUnit(String unit) {
    const volumes = {'m³', 'm3', 'ft³', 'ft3', 'l', 'liter', 'litre', 'liters', 'litres', 'ml', 'gallon', 'gallons', 'gal', 'cbm', 'cbf'};
    return volumes.contains(unit.toLowerCase().trim());
  }

  // Normalise to base unit: weight → kg, volume → m³
  double _normalizeToBase(double value, String unit) {
    switch (unit.toLowerCase().trim()) {
      case 'kg': return value;
      case 't': case 'ton': case 'tonne': case 'tonnes': return value * 1000;
      case 'lbs': case 'lb': case 'pound': case 'pounds': return value * 0.453592;
      case 'g': case 'gram': case 'grams': return value / 1000;
      case 'oz': return value * 0.0283495;
      case 'm³': case 'm3': case 'cbm': return value;
      case 'ft³': case 'ft3': case 'cbf': return value * 0.0283168;
      case 'l': case 'liter': case 'litre': case 'liters': case 'litres': return value / 1000;
      case 'ml': return value / 1000000;
      case 'gallon': case 'gallons': case 'gal': return value * 0.00378541;
      default: return value;
    }
  }

  // Get total quantity + unit from the current order
  Map<String, dynamic> _getOrderTotalQuantityAndUnit() {
    final directTotal = _currentOrder['total_quantity'];
    final directUnit = _currentOrder['quantity_unit']?.toString();
    if (directTotal != null && directUnit != null && directUnit.isNotEmpty) {
      return {'quantity': _parseQuantity(directTotal), 'unit': directUnit};
    }
    final items = _currentOrder['items'] as List<dynamic>? ?? [];
    if (items.isEmpty) return {'quantity': 0.0, 'unit': 'kg'};
    String? commonUnit;
    double total = 0.0;
    bool allSameUnit = true;
    for (final rawItem in items) {
      final item = rawItem as Map<String, dynamic>;
      final unit = _getItemUnit(item);
      final qty = _parseQuantity(item['quantity'] ?? item['qty'] ?? item['amount']);
      if (commonUnit == null) {
        commonUnit = unit;
      } else if (commonUnit != unit) {
        allSameUnit = false;
      }
      total += qty;
    }
    return {'quantity': total, 'unit': allSameUnit ? (commonUnit ?? 'kg') : 'kg'};
  }

  // Format a quantity value cleanly (no unnecessary decimals)
  String _fmtQty(double value) {
    if (value == value.truncateToDouble()) return value.toStringAsFixed(0);
    if (value < 10) return value.toStringAsFixed(2);
    return value.toStringAsFixed(1);
  }

  // Helper method to get unit for order item with fallback
  String _getItemUnit(Map<String, dynamic> item) {
    // Debug: Print all available fields
    print('🔍 Order Item Unit Debug:');
    print('  Available fields: ${item.keys.toList()}');
    print('  unit: ${item['unit']}');
    print('  unitType: ${item['unitType']}');
    print('  variant_unit: ${item['variant_unit']}');
    print('  product_id: ${item['product_id']}');
    print('  variantId: ${item['variantId']}');

    // Check for unit in the item itself
    if (item['unit'] != null && item['unit'].toString().isNotEmpty) {
      print('  ✅ Using unit: ${item['unit']}');
      return item['unit'].toString();
    }
    if (item['unitType'] != null && item['unitType'].toString().isNotEmpty) {
      print('  ✅ Using unitType: ${item['unitType']}');
      return item['unitType'].toString();
    }
    if (item['variant_unit'] != null &&
        item['variant_unit'].toString().isNotEmpty) {
      print('  ✅ Using variant_unit: ${item['variant_unit']}');
      return item['variant_unit'].toString();
    }
    if (item['product_unit'] != null &&
        item['product_unit'].toString().isNotEmpty) {
      print('  ✅ Using product_unit: ${item['product_unit']}');
      return item['product_unit'].toString();
    }

    print('  ⚠️ No unit found - using default kg');
    return 'kg'; // Final fallback
  }

  // Helper method to format status text for display
  String _formatStatusText(String status) {
    // Special cases for better readability
    if (status.toLowerCase() == 'ready_for_pickup') {
      return AppLocalizations.of(context)!.readyForPickup;
    }
    if (status.toLowerCase() == 'picked_up') {
      return AppLocalizations.of(context)!.pickedUp;
    }

    // Convert status to human-readable format
    return status
        .split('_')
        .map((word) => word[0].toUpperCase() + word.substring(1).toLowerCase())
        .join(' ');
  }

  // Format currency according to number format preference
  String _formatCurrency(dynamic amount) {
    double numericAmount;
    if (amount is double) {
      numericAmount = amount;
    } else if (amount is int) {
      numericAmount = amount.toDouble();
    } else if (amount is String) {
      numericAmount = double.tryParse(amount.replaceAll(',', '.')) ?? 0.0;
    } else {
      numericAmount = 0.0;
    }
    setNumberFormatStyleIndex(widget.numberFormat == 'de' ? 1 : 0);
    return formatCurrencyUsd(numericAmount);
  }

  /// True if the order already has a buyer receipt timestamp (API may use [received_date] or [receivedAt]).
  bool _orderHasMeaningfulReceivedTimestamp() {
    final dynamic v =
        _currentOrder['received_date'] ?? _currentOrder['receivedAt'];
    if (v == null) return false;
    final s = v.toString().trim();
    if (s.isEmpty || s.toLowerCase() == 'null') return false;
    if (RegExp(r'^0000-00-00', caseSensitive: false).hasMatch(s)) {
      return false;
    }
    return DateTime.tryParse(s) != null;
  }

  // Mark order as received
  Future<void> _markAsReceived() async {
    // Block completion if buyer waiting charges are unpaid
    if (_buyerWaitingCharges > 0 && !_waitingChargesPaid) {
      TopNotification.error(
        context,
        '${AppLocalizations.of(context)!.waitingCharges} — ${_formatCurrency(_buyerWaitingCharges)} ${AppLocalizations.of(context)!.mustBePaidFirst}',
      );
      return;
    }

    setState(() {
      _isMarkingReceived = true;
    });

    try {
      final result = await ApiService.markOrderAsReceived(_currentOrder['id']);

      if (result['success'] == true) {
        // Immediately update status locally so the UI reacts right away
        setState(() {
          _currentOrder = Map<String, dynamic>.from(_currentOrder)
            ..['status'] = 'completed'
            ..['received_date'] = DateTime.now().toIso8601String();
        });

        // Show success message
        if (mounted) {
          TopNotification.success(
            context,
            AppLocalizations.of(context)!.orderReceivedSuccess,
          );
        }

        // Call callback to refresh order list
        if (widget.onOrderUpdated != null) {
          widget.onOrderUpdated!();
        }

        // Re-fetch from server in background — delay so the DB write has time
        // to settle, and guard against rolling back the just-confirmed status.
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) _refreshOrderData();
        });

      } else {
        // Backend returned success:false — show the error message
        final errMsg = result['error'] ?? result['message'] ?? 'Could not complete order';
        if (mounted) {
          TopNotification.error(context, errMsg);
        }
      }
    } catch (e) {
      if (mounted) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)!.errorGeneric(e.toString()),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isMarkingReceived = false;
        });
      }
    }
  }

  // Calculate delivery countdown
  String _getDeliveryCountdown() {
    try {
      final orderDate = DateTime.tryParse(
        _currentOrder['order_date']?.toString() ?? '',
      );
      final deliveryDays = 3; // Default delivery time

      if (orderDate != null) {
        // Use local time for delivery calculation
        final deliveryDate = orderDate.add(Duration(days: deliveryDays));
        final now = DateTime.now();
        final difference = deliveryDate.difference(now);

        if (difference.isNegative) {
          return AppLocalizations.of(context)!.deliveryOverdue;
        } else if (difference.inDays > 0) {
          return '${difference.inDays} days remaining';
        } else if (difference.inHours > 0) {
          return '${difference.inHours} hours remaining';
        } else {
          return AppLocalizations.of(context)!.deliveryToday;
        }
      }
    } catch (e) {
      // Handle parsing error
    }
    return AppLocalizations.of(context)!.deliveryTimeUnknown;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final desktop = CultiooDesktopLayout.isDesktopPlatform;

    // Match Delvioo account bottom sheets: strip extra bottom safe padding so the
    // sheet content aligns with TradeRepublicBottomSheet's own padding.
    return TradeRepublicCardFlatScope(
      flat: desktop,
      child: MediaQuery.removePadding(
        context: context,
        removeBottom: true,
        child: ColoredBox(
          color: desktop
              ? (isDark ? Colors.black : Colors.white)
              : TradeRepublicTheme.backgroundColor(context),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.max,
                children: [
                  _buildDelviooSheetHeader(isDark),
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics(),
                      ),
                      padding: const EdgeInsets.only(bottom: 36),
                      child: _buildContent(isDark),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Hero header aligned with Delvioo account bottom sheets (e.g. payment / profile modals).
  Widget _buildDelviooSheetHeader(bool isDark) {
    final statusRaw = (_currentOrder['status'] ?? '').toString();
    final desktop = CultiooDesktopLayout.isDesktopPlatform;
    final tc = TradeRepublicTheme.textColor(context);

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            AppLocalizations.of(context)!.orderDetails,
            textAlign: TextAlign.center,
            style: _sheetCaptionStyle(context).copyWith(
              fontSize: desktop ? 18 : 15,
              fontWeight: FontWeight.w600,
              color: desktop
                  ? tc.withValues(alpha: 0.52)
                  : TradeRepublicTheme.hintColor(context, opacity: 0.45),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _displayOrderNumberFor(_currentOrder),
            textAlign: TextAlign.center,
            style: TradeRepublicTheme.titleLarge(context).copyWith(
              fontSize: desktop ? 44 : 34,
              fontWeight: FontWeight.w700,
              letterSpacing: desktop ? -1.6 : -1.2,
              height: 1.02,
              color: tc,
            ),
          ),
          // Split button - only show if no driver assigned yet
          if ((_currentOrder['status'] == 'pending' || _currentOrder['status'] == 'confirmed') &&
              (_currentOrder['driver_id'] == null ||
               _currentOrder['driver_id'].toString().isEmpty ||
               _currentOrder['driver_id'].toString() == 'null'))
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _showManualSplitFlow(context, isDark),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF9500), Color(0xFFFF6B00)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF9500).withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        CupertinoIcons.arrow_branch,
                        color: Colors.white,
                        size: desktop ? 18 : 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Split Order',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: desktop ? 14 : 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            _formatOrderDate(),
            textAlign: TextAlign.center,
            style: _sheetCaptionStyle(context).copyWith(
              fontSize: desktop ? 18 : 15,
              fontWeight: FontWeight.w400,
              color: desktop
                  ? tc.withValues(alpha: 0.48)
                  : TradeRepublicTheme.hintColor(context, opacity: 0.5),
            ),
          ),
          if (_splitFamilyOrders.length >= 2) ...[
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Builder(builder: (context) {
                final labels = _splitFamilyOrders.map(_displayOrderNumberFor).toList();
                final ids = _splitFamilyOrders
                    .map((o) => _toOrderInt(o['id']))
                    .whereType<int>()
                    .toList();
                final selectedId = _selectedSplitOrderId ?? _toOrderInt(_currentOrder['id']) ?? (ids.isNotEmpty ? ids.first : 0);
                var selectedIndex = ids.indexOf(selectedId);
                if (selectedIndex < 0) selectedIndex = 0;
                return TradeRepublicSlider(
                  labels: labels,
                  selectedIndex: selectedIndex,
                  height: desktop ? 46 : 42,
                  onChanged: (idx) {
                    if (idx >= 0 && idx < ids.length) {
                      _switchToSplitOrder(ids[idx]);
                    }
                  },
                );
              }),
            ),
          ],
          if (statusRaw.isNotEmpty) ...[
            const SizedBox(height: 14),
            _buildOrderStatusChip(isDark, statusRaw),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildOrderStatusChip(bool isDark, String statusRaw) {
    final label = _formatStatusText(statusRaw);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: _sheetSurfaceMuted(context),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Text(
        label,
        style: _sheetSectionLabelStyle(context).copyWith(
          fontSize: 13,
          color: TradeRepublicTheme.textColor(context).withValues(alpha: 0.88),
        ),
      ),
    );
  }

  // ─── Shared typography & chrome (Delvioo account bottom sheets) ───
  TextStyle _sheetSectionLabelStyle(BuildContext context) => TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.15,
        color: TradeRepublicTheme.hintColor(context, opacity: 0.52),
      );

  Widget _sheetSectionLabelWidget(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 10, top: 2),
      child: Text(label, style: _sheetSectionLabelStyle(context)),
    );
  }

  TextStyle _sheetSubSheetTitleStyle(BuildContext context) =>
      TradeRepublicTheme.titleMedium(context).copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.55,
      );

  TextStyle _sheetCaptionStyle(BuildContext context) =>
      TradeRepublicTheme.bodySmall(context);

  Color _sheetSurfaceMuted(BuildContext context) {
    if (CultiooDesktopLayout.isDesktopPlatform) {
      return TradeRepublicTheme.textColor(context).withValues(alpha: 0.08);
    }
    return Theme.of(context).brightness == Brightness.dark
        ? TradeRepublicTheme.darkElevated
        : TradeRepublicTheme.lightSurface;
  }

  Icon _sheetTrailingChevron(BuildContext context) => Icon(
        CupertinoIcons.chevron_right,
        size: 15,
        color: TradeRepublicTheme.iconColor(context, opacity: 0.32),
      );

  Icon _sheetLeadingIcon(
    IconData icon,
    BuildContext context, {
    Color? color,
  }) {
    return Icon(
      icon,
      size: 22,
      color: color ?? TradeRepublicTheme.iconColor(context, opacity: 0.92),
    );
  }

  Widget _buildContent(bool isDark) {
    final status = _currentOrder['status'] ?? 'pending';
    final items = _currentOrder['items'] as List<dynamic>? ?? [];
    final address = _resolveDeliveryAddressMap();

    // Debug logging
    print('🔍 OrderDetailsModal - Full order data: $_currentOrder');
    print('🔍 OrderDetailsModal - Address object: $address');
    print('🔍 OrderDetailsModal - Address type: ${address.runtimeType}');
    print('🔍 OrderDetailsModal - Address keys: ${address.keys.toList()}');

    // If order is rejected, show simple rejection message
    if (status.toLowerCase() == 'rejected' ||
        status.toLowerCase() == 'cancelled') {
      return TradeRepublicCard(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: TradeRepublicTheme.destructiveRed.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                CupertinoIcons.xmark_circle_fill,
                size: 44,
                color: TradeRepublicTheme.destructiveRed.withValues(alpha: 0.95),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              status.toLowerCase() == 'rejected'
                  ? AppLocalizations.of(context)!.orderRejected
                  : AppLocalizations.of(context)!.orderCancelled,
              textAlign: TextAlign.center,
              style: TradeRepublicTheme.titleLarge(context).copyWith(
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              status.toLowerCase() == 'rejected'
                  ? AppLocalizations.of(
                      context,
                    )!.thisOrderHasBeenRejectedAndWillNotBeProce
                  : AppLocalizations.of(context)!.thisOrderHasBeenCancelled,
              textAlign: TextAlign.center,
              style: _sheetCaptionStyle(context).copyWith(
                fontSize: 15,
                height: 1.45,
                color: TradeRepublicTheme.hintColor(context, opacity: 0.55),
              ),
            ),
            const SizedBox(height: 28),
            TradeRepublicButton(
              label: AppLocalizations.of(context)!.close,
              isSecondary: true,
              width: double.infinity,
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      );
    }

    final statusLower = status.toString().toLowerCase();
    final totalAmount = _parsePrice(_currentOrder['total_amount']);
    final paymentReceived = _currentOrder['payment_received'] == true ||
        statusLower == 'completed';
    final isNetPayment =
        _currentOrder['payment_method_type'] == 'payment_30_days' ||
        _currentOrder['payment_method_type'] == 'payment_60_days' ||
        _currentOrder['payment_terms_details'] != null;
    final delvioo = _currentOrder['delvioo'];
    final isDelivery = delvioo != null &&
        delvioo != 0 && delvioo != '0' && delvioo != false;
    final showDriverAuction = isDelivery &&
        (statusLower == 'confirmed' || statusLower == 'succeeded' ||
            statusLower == 'accepted' || statusLower == 'shipped' ||
            (statusLower == 'pending' && isNetPayment));
    final showDriverContact = statusLower == 'picked_up' || statusLower == 'shipped';
    final canDownloadInvoice = const {'accepted', 'ready_for_pickup', 'ready',
        'picked_up', 'shipped', 'delivered', 'completed'}.contains(statusLower.trim());
    final canCancel = const {'pending', 'waiting', 'awaiting', 'confirmed'}.contains(statusLower);
    const terminalBuyerDetail = {
      'completed',
      'delivered',
      'cancelled',
      'canceled',
      'refunded',
      'failed',
      'payment_failed',
    };
    final delviooOff = !isDelivery;
    final isSelfDeliveryConfirmed =
        statusLower == 'confirmed' &&
        delviooOff &&
        !terminalBuyerDetail.contains(statusLower) &&
        !_orderHasMeaningfulReceivedTimestamp();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Progress bar ──
        _buildProgressBar(isDark, status),
        const SizedBox(height: 20),

        // ── BUYER CHECK-IN: driver arrived – QR + confirm ──
        if (statusLower == 'buyer_check_in') ...[
          _buildBuyerCheckInVerificationCard(isDark),
          const SizedBox(height: 12),
          TradeRepublicButton(
            label: AppLocalizations.of(context)!.confirm,
            icon: const Icon(CupertinoIcons.checkmark_circle_fill, color: Colors.white, size: 20),
            tint: TradeRepublicTheme.textColor(context),
            isLoading: _isMarkingReceived,
            onPressed: _isMarkingReceived ? null : _markAsReceived,
            width: double.infinity,
          ),
          const SizedBox(height: 20),
        ],

        // ── APPROVAL: pay now ──
        if (statusLower == 'approval_approved') ...[
          _buildApprovalPaymentSection(isDark),
          const SizedBox(height: 20),
        ],

        // ── WAITING / AWAITING: compact payment reminder ──
        if (statusLower == 'waiting' || statusLower == 'awaiting') ...[
          _buildPaymentDeadlineCountdown(isDark),
          const SizedBox(height: 10),
          TradeRepublicButton(
            label: AppLocalizations.of(context)!.waitingForBankTransfer,
            icon: const Icon(CupertinoIcons.arrow_right_circle_fill, size: 18),
            isSecondary: true,
            onPressed: () => _showPaymentSheet(isDark),
            width: double.infinity,
          ),
          const SizedBox(height: 20),
        ],

        // ── Driver auction (interactive – stays inline) ──
        if (showDriverAuction) ...[
          _buildDriverAuctionSection(isDark),
          const SizedBox(height: 20),
        ],

        // ── Navigation tiles (grouped card — Delvioo account style) ──
        TradeRepublicCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              TradeRepublicListTile(
                padding: _kSheetTilePadding,
                title: AppLocalizations.of(context)!.orderItemsCount(items.length),
                subtitle: _formatCurrency(totalAmount),
                leading: _sheetLeadingIcon(CupertinoIcons.cube_box, context),
                trailing: _sheetTrailingChevron(context),
                onTap: () => _showItemsSheet(isDark, items),
              ),
              const TradeRepublicDivider(margin: EdgeInsets.zero),
              TradeRepublicListTile(
                padding: _kSheetTilePadding,
                title: AppLocalizations.of(context)!.payment,
                subtitle: paymentReceived
                    ? '${AppLocalizations.of(context)!.paid} · ${_formatCurrency(totalAmount)}'
                    : 'Open · ${_formatCurrency(totalAmount)}',
                leading: _sheetLeadingIcon(
                  paymentReceived
                      ? CupertinoIcons.checkmark_circle
                      : CupertinoIcons.creditcard,
                  context,
                  color: paymentReceived ? TradeRepublicTheme.textColor(context) : null,
                ),
                trailing: _sheetTrailingChevron(context),
                onTap: () => _showPaymentSheet(isDark),
              ),
              const TradeRepublicDivider(margin: EdgeInsets.zero),
              TradeRepublicListTile(
                padding: _kSheetTilePadding,
                title: AppLocalizations.of(context)!.deliveryInformation1,
                subtitle: _getDeliveryCountdown(),
                leading: _sheetLeadingIcon(CupertinoIcons.location, context),
                trailing: _sheetTrailingChevron(context),
                onTap: () => _showDeliverySheet(isDark, address),
              ),
              const TradeRepublicDivider(margin: EdgeInsets.zero),
              TradeRepublicListTile(
                padding: _kSheetTilePadding,
                title: AppLocalizations.of(context)!.sectionContact,
                subtitle: showDriverContact
                    ? '${AppLocalizations.of(context)!.contactSeller} & Driver'
                    : AppLocalizations.of(context)!.contactSeller,
                leading: _sheetLeadingIcon(CupertinoIcons.chat_bubble_text, context),
                trailing: _sheetTrailingChevron(context),
                onTap: () => _showContactSheet(isDark),
              ),
            ],
          ),
        ),

        // ── Invoice tile ──
        if (canDownloadInvoice) ...[
          const SizedBox(height: 8),
          TradeRepublicCard(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: TradeRepublicListTile(
              padding: _kSheetTilePadding,
              title: AppLocalizations.of(context)!.downloadInvoice,
              subtitle: 'PDF',
              leading: Icon(CupertinoIcons.doc_text,
                  size: 22, color: TradeRepublicTheme.textColor(context)),
              trailing: _isDownloadingInvoice
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(CupertinoIcons.arrow_down_circle,
                      size: 18, color: isDark ? Colors.white38 : Colors.black26),
              onTap: _isDownloadingInvoice ? null : _showInvoiceSelectionSheet,
            ),
          ),
        ],

        // ── Confirm receipt (self-delivery) ──
        if (isSelfDeliveryConfirmed) ...[
          const SizedBox(height: 16),
          TradeRepublicButton(
            label: AppLocalizations.of(context)!.confirm,
            icon: const Icon(CupertinoIcons.checkmark_circle_fill, color: Colors.white, size: 20),
            tint: TradeRepublicTheme.textColor(context),
            isLoading: _isMarkingReceived,
            onPressed: _isMarkingReceived ? null : _markAsReceived,
            width: double.infinity,
          ),
        ],

        // ── Cancel order ──
        if (canCancel) ...[
          const SizedBox(height: 12),
          TradeRepublicButton(
            label: AppLocalizations.of(context)!.cancelOrder,
            isDestructive: true,
            isLoading: _isClosingOrder,
            onPressed: _isClosingOrder ? null : _closeOrder,
            width: double.infinity,
          ),
        ],

        // ── Buyer waiting charges ──
        if (_buyerWaitingCharges > 0) ...[
          const SizedBox(height: 16),
          _buildBuyerWaitingChargesCard(isDark),
        ],

        const SizedBox(height: 24),
      ],
    );
  }

  String _fmtSecs(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  Widget _buildBuyerWaitingChargesCard(bool isDark) {
    final chargeableSeconds = (_buyerWaitingSeconds - _waitingFreeMinutes * 60).clamp(0, _buyerWaitingSeconds);
    return TradeRepublicCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(CupertinoIcons.timer, color: Colors.orange, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.waitingCharges,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    Text(
                      _fmtSecs(_buyerWaitingSeconds),
                      style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black45),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _waitingChargesPaid ? Colors.green : Colors.orange,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _waitingChargesPaid
                      ? AppLocalizations.of(context)!.paid
                      : _formatCurrency(_buyerWaitingCharges),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ),
            ],
          ),
          if (!_waitingChargesPaid) ...[
            const SizedBox(height: 12),
            // Invoice details
            _waitingInvoiceRow(isDark, AppLocalizations.of(context)!.freeWaiting, '$_waitingFreeMinutes min'),
            _waitingInvoiceRow(isDark, 'Waited (delivery)', _fmtSecs(_buyerWaitingSeconds)),
            _waitingInvoiceRow(isDark, 'Chargeable', _fmtSecs(chargeableSeconds)),
            if (_waitingRatePerHour != null && _waitingRatePerHour! > 0)
              _waitingInvoiceRow(isDark, 'Rate/hr', _formatCurrency(_waitingRatePerHour!)),
            const Divider(height: 20),
            TradeRepublicButton(
              label: '${AppLocalizations.of(context)!.pay} · ${_formatCurrency(_buyerWaitingCharges)}',
              icon: const Icon(CupertinoIcons.arrow_right_circle_fill, size: 18, color: Colors.white),
              isLoading: _isPayingWaitingCharges,
              onPressed: _isPayingWaitingCharges ? null : _payBuyerWaitingCharges,
              width: double.infinity,
            ),
          ],
        ],
      ),
    );
  }

  Widget _waitingInvoiceRow(bool isDark, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: isDark ? Colors.white54 : Colors.black54)),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black)),
        ],
      ),
    );
  }

  Future<void> _payBuyerWaitingCharges() async {
    setState(() => _isPayingWaitingCharges = true);
    try {
      final orderId = _currentOrder['id'];
      final result = await ApiService.payBuyerWaitingCharges(orderId);
      if (!mounted) return;
      if (result['success'] == true) {
        setState(() {
          _waitingChargesPaid = true;
          _isPayingWaitingCharges = false;
        });
        _showSuccessSnackBar('✅ ${AppLocalizations.of(context)!.waitingCharges} ${AppLocalizations.of(context)!.paid} · ${_formatCurrency(_buyerWaitingCharges)}');
      } else {
        setState(() => _isPayingWaitingCharges = false);
        _showErrorDialog(AppLocalizations.of(context)!.error, result['error'] ?? result['message'] ?? 'Payment failed');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isPayingWaitingCharges = false);
        _showErrorDialog(AppLocalizations.of(context)!.error, e.toString());
      }
    }
  }

  Map<String, dynamic> _resolveDeliveryAddressMap() {
    Map<String, dynamic> decodeAddress(dynamic raw) {
      if (raw is Map<String, dynamic>) return Map<String, dynamic>.from(raw);
      if (raw is Map) return raw.map((k, v) => MapEntry(k.toString(), v));
      if (raw is String && raw.trim().isNotEmpty) {
        try {
          final decoded = json.decode(raw);
          if (decoded is Map<String, dynamic>) return Map<String, dynamic>.from(decoded);
          if (decoded is Map) return decoded.map((k, v) => MapEntry(k.toString(), v));
        } catch (_) {}
      }
      return <String, dynamic>{};
    }

    final resolved = <String, dynamic>{};
    final primary = decodeAddress(_currentOrder['address']);
    final delivery = decodeAddress(_currentOrder['delivery_address']);
    final shipping = decodeAddress(_currentOrder['shipping_address']);

    // Order: generic -> shipping -> delivery (most specific wins)
    resolved.addAll(primary);
    resolved.addAll(shipping);
    resolved.addAll(delivery);

    final firstName = (_currentOrder['firstname'] ?? _currentOrder['first_name'] ?? '').toString().trim();
    final lastName = (_currentOrder['lastname'] ?? _currentOrder['last_name'] ?? '').toString().trim();
    final fallbackName = [firstName, lastName].where((x) => x.isNotEmpty).join(' ').trim();

    resolved['name'] = (resolved['name'] ?? resolved['full_name'] ?? fallbackName ?? '').toString().trim();
    if ((resolved['name'] as String).isEmpty && fallbackName.isNotEmpty) {
      resolved['name'] = fallbackName;
    }

    resolved['street'] = (resolved['street'] ??
            resolved['address_line1'] ??
            resolved['line1'] ??
            resolved['address'] ??
            _currentOrder['street'])
        ?.toString()
        .trim();
    resolved['house_number'] =
        (resolved['house_number'] ?? resolved['houseNo'] ?? _currentOrder['house_number'])?.toString().trim();
    resolved['city'] = (resolved['city'] ?? resolved['town'] ?? _currentOrder['city'])?.toString().trim();
    resolved['postal_code'] = (resolved['postal_code'] ??
            resolved['postalCode'] ??
            resolved['zip_code'] ??
            resolved['zipCode'] ??
            resolved['zip'] ??
            _currentOrder['postal_code'] ??
            _currentOrder['zip'])
        ?.toString()
        .trim();
    resolved['country'] = (resolved['country'] ?? _currentOrder['country'])?.toString().trim();

    return resolved;
  }

  // ==========================================
  // SUB-SHEET: Items
  // ==========================================
  void _showItemsSheet(bool isDark, List<dynamic> items) {
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: MediaQuery.removePadding(
        context: context,
        removeBottom: true,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildItemsSection(isDark, items),
              if (_currentOrder['requires_cleaning_certificate'] == 1 ||
                  _currentOrder['requires_cleaning_certificate'] == '1' ||
                  _currentOrder['requires_cleaning_certificate'] == true) ...[
                const SizedBox(height: 16),
                _buildCustomerCleaningCertificateInfo(isDark),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  // SUB-SHEET: Payment
  // ==========================================
  void _showPaymentSheet(bool isDark) {
    final statusLower = (_currentOrder['status'] ?? '').toString().toLowerCase();
    final isWaiting = statusLower == 'waiting' || statusLower == 'awaiting';

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: MediaQuery.removePadding(
        context: context,
        removeBottom: true,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isWaiting) ...[
              // Summary + bank details for waiting orders
              TradeRepublicCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    TradeRepublicListTile(
                      padding: _kSheetTilePadding,
                      title: getPaymentMethodName(),
                      subtitle: AppLocalizations.of(context)!.paymentMethod,
                      leading: Icon(
                        _getPaymentMethodIcon(_getActualPaymentType()),
                        size: 20,
                        color: _getPaymentMethodColor(_getActualPaymentType()),
                      ),
                      trailing: Text(
                        AppLocalizations.of(context)!.awaitingPayment,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.orange.shade700),
                      ),
                    ),
                    const TradeRepublicDivider(margin: EdgeInsets.zero),
                    TradeRepublicListTile(
                      padding: _kSheetTilePadding,
                      title: _formatCurrency(_parsePrice(_currentOrder['total_amount'])),
                      subtitle: AppLocalizations.of(context)!.amount,
                      leading: Icon(
                        _currentOrder['payment_received'] == true
                            ? CupertinoIcons.checkmark_circle_fill
                            : CupertinoIcons.time,
                        color: _currentOrder['payment_received'] == true
                            ? TradeRepublicTheme.textColor(context)
                            : Colors.orange.shade600,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _buildBankTransferDetails(isDark, getPaymentMethodName()),
              const SizedBox(height: 12),
              _buildPaymentDeadlineCountdown(isDark),
            ] else
              _buildPaymentSection(isDark),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  // SUB-SHEET: Delivery & Address
  // ==========================================
  void _showDeliverySheet(bool isDark, Map<String, dynamic> address) {
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: MediaQuery.removePadding(
        context: context,
        removeBottom: true,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            _buildDeliveryInfoSection(isDark),
            const SizedBox(height: 16),
            _buildAddressSection(isDark, address),
            if (_currentOrder['tracking_number'] != null) ...[
              const SizedBox(height: 16),
              _buildTrackingSection(isDark),
            ],
          ],
        ),
      ),
    ),
    );
  }

  // ==========================================
  // SUB-SHEET: Contact
  // ==========================================
  void _showContactSheet(bool isDark) {
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 40),
        child: _buildContactSection(isDark),
      ),
    );
  }

  // ==========================================
  // PROGRESS BAR - Ultra Modern Minimal Design
  // ==========================================

  Widget _buildProgressBar(bool isDark, String status) {
    final steps = _getProgressSteps();
    final currentIndex = _getCurrentStepIndex(status, steps);
    final isCompleted = status.toLowerCase() == 'completed';
    final monoText = TradeRepublicTheme.textColor(context);
    final monoSubtle = TradeRepublicTheme.hintColor(context, opacity: 0.5);
    final monoSurface = _sheetSurfaceMuted(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sheetSectionLabelWidget(
          context,
          AppLocalizations.of(context)!.currentStatus,
        ),
        // Completed banner — shown instead of normal step card
        if (isCompleted)
          TradeRepublicCard(
            child: TradeRepublicListTile(
              padding: _kSheetTilePadding,
              title: AppLocalizations.of(context)!.orderReceivedSuccess,
              subtitle: _currentOrder['received_date'] != null
                  ? _formatDate(_currentOrder['received_date'])
                  : null,
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: monoText,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  CupertinoIcons.checkmark_seal_fill,
                  color: isDark ? Colors.black : Colors.white,
                  size: 22,
                ),
              ),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: monoSurface,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'DONE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: monoText,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          )
        else
          // Current step card
          _buildCurrentStepCard(steps[currentIndex], isDark),
        const SizedBox(height: 16),
        // Progress indicator
        _buildMinimalProgressIndicator(steps, currentIndex, isDark),
        const SizedBox(height: 12),
        // Compact step pills
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: List.generate(steps.length, (i) {
            final isDone = i < currentIndex;
            final isNow = i == currentIndex;
            final step = steps[i];
            final pillColor = isDone || isNow
                ? monoSurface
                : TradeRepublicTheme.fillColor(context, opacity: isDark ? 0.08 : 0.05);
            final labelColor = isDone || isNow ? monoText : monoSubtle;

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: pillColor,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isDone ? CupertinoIcons.checkmark_alt : step.icon,
                    size: 13,
                    color: labelColor,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    step.label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isNow ? FontWeight.w700 : FontWeight.w600,
                      color: labelColor,
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildCurrentStepCard(_ProgressStep step, bool isDark) {
    final monoText = TradeRepublicTheme.textColor(context);
    final monoSurface = _sheetSurfaceMuted(context);

    return TradeRepublicCard(
      child: TradeRepublicListTile(
        padding: _kSheetTilePadding,
        title: step.label,
        subtitle: AppLocalizations.of(context)!.currentStatus,
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: monoText,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(step.icon, color: isDark ? Colors.black : Colors.white, size: 22),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: monoSurface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            'ACTIVE',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: monoText,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMinimalProgressIndicator(
    List<_ProgressStep> steps,
    int currentIndex,
    bool isDark,
  ) {
    final color = isDark ? Colors.white : Colors.black;
    return TradeRepublicCard(
      padding: _kSheetTilePaddingCompact,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Step ${currentIndex + 1} of ${steps.length}',
                style: TradeRepublicTheme.bodySmall(context),
              ),
              Text(
                '${((currentIndex + 1) / steps.length * 100).round()}%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(25),
            child: LayoutBuilder(
              builder: (context, constraints) => Stack(
                children: [
                  Container(
                    width: constraints.maxWidth,
                    height: 5,
                    color: isDark
                        ? const Color(0xFF1C1C1E)
                        : Colors.black.withOpacity(0.06),
                  ),
                  Container(
                    width: constraints.maxWidth *
                        ((currentIndex + 1) / steps.length).clamp(0.0, 1.0),
                    height: 5,
                    color: color,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepItem(
    _ProgressStep step,
    int index,
    int currentIndex,
    bool isDark,
  ) {
    final isCompleted = index < currentIndex;
    final isCurrent = index == currentIndex;
    final isUpcoming = index > currentIndex;
    final iconColor = isUpcoming
        ? (isDark ? Colors.grey[600]! : Colors.grey[400]!)
        : step.color;

    return Column(
      children: [
        if (index > 0) const TradeRepublicDivider(margin: EdgeInsets.zero),
        TradeRepublicListTile(
          padding: _kSheetTilePaddingDense,
          title: step.label,
          titleColor: isUpcoming
              ? (isDark ? Colors.grey[600] : Colors.grey[400])
              : null,
          leading: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isUpcoming
                  ? (isDark ? const Color(0xFF111113) : Colors.black.withOpacity(0.03))
                  : step.color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: isCompleted
                  ? Icon(CupertinoIcons.checkmark_alt, size: 16, color: step.color)
                  : Icon(step.icon, size: 15, color: iconColor),
            ),
          ),
          trailing: isCurrent
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: step.color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'NOW',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: step.color,
                      letterSpacing: 0.5,
                    ),
                  ),
                )
              : isCompleted
                  ? Icon(CupertinoIcons.checkmark_alt, size: 16, color: step.color)
                  : null,
        ),
      ],
    );
  }

  /// Returns the list of steps based on order type (pickup vs delivery)
  List<_ProgressStep> _getProgressSteps() {
    final mono = Theme.of(context).brightness == Brightness.dark
      ? Colors.white
      : Colors.black;
    final delviooValue = _currentOrder['delvioo'];
    final isPickup =
        delviooValue == 0 || delviooValue == '0' || delviooValue == false;

    if (isPickup) {
      return [
        _ProgressStep(
          id: 'confirmed',
          label: AppLocalizations.of(context)!.paid,
          icon: CupertinoIcons.creditcard,
          color: mono,
        ),
        _ProgressStep(
          id: 'delivered',
          label: AppLocalizations.of(context)!.delivered,
          icon: CupertinoIcons.checkmark_seal_fill,
          color: mono,
        ),
      ];
    }

    return [
      _ProgressStep(
        id: 'awaiting',
        label: AppLocalizations.of(context)!.pending,
        icon: CupertinoIcons.hourglass,
        color: mono,
      ),
      _ProgressStep(
        id: 'confirmed',
        label: AppLocalizations.of(context)!.paid,
        icon: CupertinoIcons.creditcard,
        color: mono,
      ),
      _ProgressStep(
        id: 'accepted',
        label: AppLocalizations.of(context)!.processing,
        icon: CupertinoIcons.cube_box,
        color: mono,
      ),
      _ProgressStep(
        id: 'ready_for_pickup',
        label: AppLocalizations.of(context)!.ready,
        icon: CupertinoIcons.checkmark_circle,
        color: mono,
      ),
      _ProgressStep(
        id: 'picked_up',
        label: AppLocalizations.of(context)!.transit,
        icon: CupertinoIcons.cube_box,
        color: mono,
      ),
      _ProgressStep(
        id: 'buyer_check_in',
        label: AppLocalizations.of(context)!.driverArrived,
        icon: CupertinoIcons.location_fill,
        color: mono,
      ),
      _ProgressStep(
        id: 'delivered',
        label: AppLocalizations.of(context)!.delivered,
        icon: CupertinoIcons.home,
        color: mono,
      ),
    ];
  }

  /// Determines the current step index based on order status
  int _getCurrentStepIndex(String status, List<_ProgressStep> steps) {
    final lowerStatus = status.toLowerCase();
    final isPickup = steps.length == 2;

    if (isPickup) {
      if (lowerStatus == 'delivered' || lowerStatus == 'completed' || lowerStatus == 'buyer_check_in') return 1;
      return 0;
    }

    // Delivery order status mapping
    const statusMap = {
      'pending': 0,
      'awaiting': 0,
      'waiting': 0,
      'confirmed': 1,
      'succeeded': 1,
      'approval_approved': 1, // approved order, waiting for payment → treat as confirmed
      'accepted': 2,
      'ready_for_pickup': 3,
      'ready': 3,
      'picked_up': 4,
      'shipped': 4,
      'buyer_check_in': 5,
      'delivered': 6,
      'completed': 6,
    };

    return statusMap[lowerStatus] ?? 0;
  }

  // Helper method to get payment method display name
  String getPaymentMethodName() {
    return _getPaymentMethodName(_getActualPaymentType());
  }

  Widget _buildStatusSection(bool isDark, String status) {
    // Just a simple status badge for now
    return const SizedBox.shrink();
  }

  // ==========================================
  // PAYMENT SECTION FOR APPROVED ORDERS (waiting for payment)
  // ==========================================
  Widget _buildApprovalPaymentSection(bool isDark) {
    final paymentMethodName = _getPaymentMethodName(
      _currentOrder['payment_method_type']?.toString() ?? '',
    );
    final paymentReceived = _currentOrder['payment_received'] == true;
    final accentColor = isDark ? Colors.white : Colors.black;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sheetSectionLabelWidget(
          context,
          AppLocalizations.of(context)!.paymentRequired,
        ),

        // Header card: payment method + status badge
        TradeRepublicCard(
          padding: EdgeInsets.zero,
          child: TradeRepublicListTile(
            padding: _kSheetTilePadding,
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: (isDark ? Colors.white : Colors.black).withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _getPaymentMethodIcon(_currentOrder['payment_method_type']?.toString() ?? ''),
                color: isDark ? Colors.white : Colors.black,
                size: 20,
              ),
            ),
            title: paymentMethodName,
            subtitle: AppLocalizations.of(context)!.paymentMethod,
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    paymentReceived ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.time,
                    color: accentColor,
                    size: 12,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    paymentReceived
                        ? AppLocalizations.of(context)!.paymentReceived
                        : AppLocalizations.of(context)!.awaitingPayment,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: accentColor),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Amount card
        TradeRepublicCard(
          padding: _kSheetTilePadding,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                AppLocalizations.of(context)!.amount,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
              ),
              Text(
                _formatCurrency(_parsePrice(_currentOrder['total_amount'])),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Bank transfer details
        _buildBankTransferDetails(isDark, getPaymentMethodName()),
        const SizedBox(height: 8),

        // Info note
        TradeRepublicCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(CupertinoIcons.info, size: 16, color: isDark ? Colors.grey[500] : Colors.grey[600]),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  AppLocalizations.of(context)!.yourOrderWillBeAutomaticallyConfirmedOncePa,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.grey[500] : Colors.grey[600],
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Payment countdown
        _buildPaymentDeadlineCountdown(isDark),
      ],
    );
  }

  // Show payment methods selection sheet - Full checkout-style UI
  void _showPaymentMethodsSheet(bool isDark) async {
    // Show loading while fetching payment methods
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      isDismissible: false,
      enableDrag: false,
      child: const Padding(
        padding: EdgeInsets.only(bottom: 40),
        child: Center(child: CultiooLoadingIndicator()),
      ),
    );

    // Load saved payment methods first
    List<Map<String, dynamic>> savedCards = [];
    List<Map<String, dynamic>> sepaAccounts = [];
    List<Map<String, dynamic>> achAccounts = [];
    List<Map<String, dynamic>> wireAccounts = [];

    // Selected payment method state - will be set after loading
    String selectedPaymentMethod = 'card';
    Map<String, dynamic>? selectedSavedCard;

    try {
      // Load all payment methods from Stripe - with retry if empty
      var paymentMethods = await ApiService.getUserPaymentMethods();

      print('🔍 First attempt - payment methods: $paymentMethods');

      // If empty, wait 2 seconds and retry (might be rate limited)
      if (paymentMethods.isEmpty) {
        print('⏳ Payment methods empty, retrying in 2 seconds...');
        await Future.delayed(const Duration(seconds: 2));
        paymentMethods = await ApiService.getUserPaymentMethods();
        print('🔄 Retry attempt - payment methods: $paymentMethods');
      }

      if (paymentMethods.isNotEmpty) {
        for (var method in paymentMethods) {
          final type = method['type']?.toString().toLowerCase() ?? '';
          print('🔍 Processing method - type: $type, data: $method');
          if (type == 'card') {
            savedCards.add(method);
            final cardData = method['card'] ?? {};
            print(
              '✅ Added card: ${cardData['brand']} ••••${cardData['last4']}',
            );
          } else if (type == 'sepa_debit' || type == 'sepa') {
            sepaAccounts.add(method);
          } else if (type == 'us_bank_account' || type == 'ach') {
            achAccounts.add(method);
          } else if (type == 'wire_transfer' || type == 'wire') {
            wireAccounts.add(method);
          }
        }
      }

      print(
        '✅ Loaded payment methods: ${savedCards.length} cards, ${sepaAccounts.length} SEPA, ${achAccounts.length} ACH, ${wireAccounts.length} Wire',
      );

      // Set default selection based on available methods
      if (savedCards.isNotEmpty) {
        selectedPaymentMethod = 'saved_card';
        selectedSavedCard = savedCards.first; // Auto-select first card
        final cardData = selectedSavedCard['card'] ?? {};
        print(
          '🎯 Auto-selected first card: ${cardData['brand']} ••••${cardData['last4']}',
        );
      } else {
        selectedPaymentMethod = 'card'; // Default to new card
        print('💳 No saved cards found - defaulting to new card entry');
      }
    } catch (e) {
      print('❌ Error loading payment methods: $e');
    }

    // Close loading dialog
    if (mounted) {
      Navigator.pop(context);
    }

    if (!mounted) return;

    await TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: Builder(
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setModalState) {
              final isIOS = Platform.isIOS;
              final scrollController = ScrollController();

              return Column(
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: Row(
                      children: [
                        TradeRepublicButton(
                          icon: Icon(
                            CupertinoIcons.back,
                            size: 18,
                          ),
                          isSecondary: true,
                          width: 44,
                          height: 44,
                          padding: EdgeInsets.zero,
                          borderRadius: BorderRadius.circular(25),
                          onPressed: () => Navigator.pop(context),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          AppLocalizations.of(context)!.paymentMethod,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Content
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Payment Method Selector
                          ClipRRect(
                            borderRadius: BorderRadius.circular(25),

                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFF0E0E0E)
                                      : Colors.white.withOpacity(0.7),
                                  borderRadius: BorderRadius.circular(25),
                                ),

                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          CupertinoIcons.creditcard,
                                          color: isDark
                                              ? Colors.white
                                              : Colors.black,
                                          size: 24,
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          AppLocalizations.of(
                                            context,
                                          )!.choosePayment,
                                          style: TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                            color: isDark
                                                ? Colors.white
                                                : Colors.black,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 20),

                                    // Saved Payment Methods Button (always visible)
                                    _buildOldPaymentMethodOption(
                                      isDark,
                                      AppLocalizations.of(
                                        context,
                                      )!.useSavedPaymentMethod,
                                      CupertinoIcons.money_dollar_circle_fill,
                                      Colors.blue,
                                      () {
                                        _showSavedPaymentMethodsSheet();
                                      },
                                    ),
                                    const SizedBox(height: 8),

                                    // Instant Payment Section
                                    Text(
                                      AppLocalizations.of(
                                        context,
                                      )!.instantPayment,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: isDark
                                            ? Colors.white54
                                            : Colors.black45,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                    const SizedBox(height: 12),

                                    _buildOldPaymentMethodOption(
                                      isDark,
                                      AppLocalizations.of(
                                        context,
                                      )!.creditOrDebitCard,
                                      CupertinoIcons.creditcard,
                                      Colors.blue,
                                      () {
                                        _showCardPaymentSheet(isDark);
                                      },
                                    ),
                                    const SizedBox(height: 8),

                                    if (isIOS) ...[
                                      _buildOldPaymentMethodOption(
                                        isDark,
                                        AppLocalizations.of(context)!.applePay,
                                        Icons.apple,
                                        Colors.black,
                                        () {
                                          _processPaymentWithMethod(
                                            'apple_pay',
                                            null,
                                          );
                                        },
                                      ),
                                      const SizedBox(height: 8),
                                    ],

                                    if (!isIOS) ...[
                                      _buildOldPaymentMethodOption(
                                        isDark,
                                        AppLocalizations.of(context)!.googlePay,
                                        CupertinoIcons.money_dollar_circle_fill,
                                        Colors.green,
                                        () {
                                          _processPaymentWithMethod(
                                            'google_pay',
                                            null,
                                          );
                                        },
                                      ),
                                      const SizedBox(height: 8),
                                    ],

                                    const SizedBox(height: 16),

                                    // Bank Transfer Section
                                    Text(
                                      AppLocalizations.of(
                                        context,
                                      )!.bankTransfer,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: isDark
                                            ? Colors.white54
                                            : Colors.black45,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                    const SizedBox(height: 12),

                                    _buildOldPaymentMethodOption(
                                      isDark,
                                      AppLocalizations.of(
                                        context,
                                      )!.sepaDirectDebit,
                                      CupertinoIcons.building_2_fill,
                                      Colors.purple,
                                      () {
                                        _showSepaPaymentSheet(isDark);
                                      },
                                    ),
                                    const SizedBox(height: 8),

                                    _buildOldPaymentMethodOption(
                                      isDark,
                                      AppLocalizations.of(
                                        context,
                                      )!.achDirectDebit,
                                      CupertinoIcons.building_2_fill,
                                      Colors.teal,
                                      () {
                                        _showAchPaymentSheet(isDark);
                                      },
                                    ),
                                    const SizedBox(height: 8),

                                    _buildOldPaymentMethodOption(
                                      isDark,
                                      AppLocalizations.of(
                                        context,
                                      )!.wireTransfer,
                                      CupertinoIcons.arrow_right_arrow_left,
                                      Colors.orange,
                                      () {
                                        _showWirePaymentSheet(isDark);
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 24),

                          // Saved Cards Selector
                          if (selectedPaymentMethod == 'saved_card' &&
                              savedCards.isNotEmpty)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(25),

                              child: BackdropFilter(
                                filter: ImageFilter.blur(
                                  sigmaX: 10,
                                  sigmaY: 10,
                                ),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color(0xFF0E0E0E)
                                        : Colors.white.withOpacity(0.7),
                                    borderRadius: BorderRadius.circular(25),
                                  ),
                                  padding: const EdgeInsets.all(20),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        AppLocalizations.of(
                                          context,
                                        )!.selectCard,
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: isDark
                                              ? Colors.white
                                              : Colors.black,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      ...savedCards.map((card) {
                                        final isSelected =
                                            selectedSavedCard?['id'] ==
                                            card['id'];
                                        final last4 = card['last4'] ?? '****';
                                        final brand = card['brand'] ?? 'card';

                                        return TradeRepublicListTile(
                                          title: '${brand.toUpperCase()} •••• $last4',
                                          leading: const Icon(
                                            CupertinoIcons.creditcard,
                                            color: Colors.blue,
                                            size: 20,
                                          ),
                                          trailing: isSelected
                                              ? const Icon(
                                                  CupertinoIcons.checkmark_circle_fill,
                                                  color: Colors.blue,
                                                  size: 20,
                                                )
                                              : null,
                                          onTap: () {
                                            setModalState(() {
                                              selectedSavedCard = card;
                                            });
                                          },
                                        );
                                      }),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                          const SizedBox(height: 100),
                        ],
                      ),
                    ),
                  ),

                  // Pay Now Button
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: SafeArea(
                      child: TradeRepublicButton(
                        label: AppLocalizations.of(context)!.payNow,
                        tint: TradeRepublicTheme.textColor(context),
                        onPressed: () async {
                          // Validate selection
                          if (selectedPaymentMethod == 'saved_card' &&
                              selectedSavedCard == null) {
                            TopNotification.error(
                              context,
                              AppLocalizations.of(context)!.pleaseSelectACard,
                            );
                            return;
                          }

                          Navigator.pop(context);
                          await _processPaymentWithMethod(
                            selectedPaymentMethod,
                            selectedSavedCard?['id'],
                          );
                        },
                        width: double.infinity,
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  // Show saved payment methods selection sheet
  void _showSavedPaymentMethodsSheet() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.blue.shade700, Colors.blue.shade500],
                      ),
                      borderRadius: BorderRadius.circular(25),
                    ),

                    child: const Icon(
                      CupertinoIcons.money_dollar_circle_fill,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLocalizations.of(context)!.savedPaymentMethods1,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: isDark ? Colors.white : Colors.black,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          AppLocalizations.of(context)!.selectAPaymentMethod,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: (isDark ? Colors.white : Colors.black)
                                .withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Payment methods list
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: methods.length,
                itemBuilder: (context, index) {
                  final method = methods[index];
                  return _buildSavedMethodOption(method, isDark);
                },
              ),
            ),
          ],
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
  Widget _buildSavedMethodOption(Map<String, dynamic> method, bool isDark) {
    final type = method['type'] ?? '';

    IconData icon;
    String title;
    String subtitle;
    Color iconColor;

    switch (type) {
      case 'card':
        icon = CupertinoIcons.creditcard;
        final cardData = method['card'] ?? {};
        final brand = (cardData['brand'] ?? 'card').toUpperCase();
        title =
            '$brand \u2022\u2022\u2022\u2022 ${cardData['last4'] ?? 'XXXX'}';
        subtitle =
            'Expires ${cardData['exp_month'] ?? 'XX'}/${cardData['exp_year'] ?? 'XXXX'}';
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
        icon = CupertinoIcons.money_dollar_circle_fill;
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
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: iconColor.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      onTap: () async {
        final methodId = method['id']?.toString();
        await _processPaymentWithMethod(type, methodId);
      },
    );
  }

  Widget _buildOldPaymentMethodOption(
    bool isDark,
    String title,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return TradeRepublicListTile.navigation(
      title: title,
      leading: Icon(icon, size: 20),
      onTap: onTap,
    );
  }

  // Show Card Payment Sheet
  void _showCardPaymentSheet(bool isDark) {
    final TextEditingController cardNumberController = TextEditingController();
    final TextEditingController expiryController = TextEditingController();
    final TextEditingController cvvController = TextEditingController();
    final TextEditingController nameController = TextEditingController();

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      maxHeight: MediaQuery.of(context).size.height * 0.95,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context)!.cardPayment,
                    style: TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black,
                      letterSpacing: -1,
                    ),
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
                  const SizedBox(height: 16),
                  TradeRepublicTextField(
                    controller: cardNumberController,
                    hintText: '1234 5678 9012 3456',
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(16),
                      _CardNumberFormatter(),
                    ],
                    maxLength: 19,
                    counterText: '',
                  ),
                  const SizedBox(height: 24),

                  Row(
                    children: [
                      // Expiry
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Expiry',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black,
                              ),
                            ),
                            const SizedBox(height: 16),
                            TradeRepublicTextField(
                              controller: expiryController,
                              hintText: 'MM/YY',
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(4),
                                _ExpiryDateFormatter(),
                              ],
                              maxLength: 5,
                              counterText: '',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      // CVV
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'CVV',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black,
                              ),
                            ),
                            const SizedBox(height: 16),
                            TradeRepublicTextField(
                              controller: cvvController,
                              hintText: '123',
                              keyboardType: TextInputType.number,
                              obscureText: true,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Cardholder Name
                  Text(
                    AppLocalizations.of(context)!.cardholderName1,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TradeRepublicTextField(
                    controller: nameController,
                    hintText: AppLocalizations.of(context)!.johnDoe,
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),

          // Button
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
            child: TradeRepublicButton(
              label: AppLocalizations.of(context)!.payNow,
              onPressed: () {
                if (cardNumberController.text.isEmpty ||
                    expiryController.text.isEmpty ||
                    cvvController.text.isEmpty ||
                    nameController.text.isEmpty) {
                  TopNotification.error(
                    context,
                    AppLocalizations.of(context)!.pleaseFillInAllFields,
                  );
                  return;
                }
                Navigator.pop(context);
                _processPaymentWithMethod('card', null);
              },
              width: double.infinity,
            ),
          ),
        ],
      ),
    );
  }

  // Show SEPA Payment Sheet
  void _showSepaPaymentSheet(bool isDark) {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController ibanController = TextEditingController();

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      maxHeight: MediaQuery.of(context).size.height * 0.95,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context)!.sepaDirectDebit,
                    style: TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    AppLocalizations.of(context)!.businessDaysProcessing,
                    style: TextStyle(
                      fontSize: 18,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Account Holder Name
                  Text(
                    AppLocalizations.of(context)!.accountHolderName,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TradeRepublicTextField(
                    controller: nameController,
                    hintText: AppLocalizations.of(context)!.johnDoe,
                  ),
                  const SizedBox(height: 24),

                  // IBAN
                  Text(
                    AppLocalizations.of(context)!.iban,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TradeRepublicTextField(
                    controller: ibanController,
                    hintText: AppLocalizations.of(
                      context,
                    )!.de89370400440532013000,
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),

          // Button
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
            child: TradeRepublicButton(
              label: AppLocalizations.of(context)!.confirmSepaTransfer,
              onPressed: () {
                if (nameController.text.isEmpty ||
                    ibanController.text.isEmpty) {
                  TopNotification.error(
                    context,
                    AppLocalizations.of(context)!.pleaseFillInAllFields,
                  );
                  return;
                }
                Navigator.pop(context);
                _processPaymentWithMethod('sepa_debit', null);
              },
              width: double.infinity,
            ),
          ),
        ],
      ),
    );
  }

  // Show ACH Payment Sheet
  void _showAchPaymentSheet(bool isDark) {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController routingController = TextEditingController();
    final TextEditingController accountController = TextEditingController();

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      maxHeight: MediaQuery.of(context).size.height * 0.95,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context)!.achDirectDebit,
                    style: TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    AppLocalizations.of(context)!.businessDaysProcessing,
                    style: TextStyle(
                      fontSize: 18,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Account Holder Name
                  Text(
                    AppLocalizations.of(context)!.accountHolderName,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TradeRepublicTextField(
                    controller: nameController,
                    hintText: AppLocalizations.of(context)!.johnDoe,
                  ),
                  const SizedBox(height: 24),

                  // Routing Number
                  Text(
                    AppLocalizations.of(context)!.routingNumber,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TradeRepublicTextField(
                    controller: routingController,
                    hintText: '110000000',
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 24),

                  // Account Number
                  Text(
                    AppLocalizations.of(context)!.accountNumber,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TradeRepublicTextField(
                    controller: accountController,
                    hintText: '000123456789',
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),

          // Button
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
            child: TradeRepublicButton(
              label: AppLocalizations.of(context)!.confirmAchTransfer,
              onPressed: () {
                if (nameController.text.isEmpty ||
                    routingController.text.isEmpty ||
                    accountController.text.isEmpty) {
                  TopNotification.error(
                    context,
                    AppLocalizations.of(context)!.pleaseFillInAllFields,
                  );
                  return;
                }
                Navigator.pop(context);
                _processPaymentWithMethod('us_bank_account', null);
              },
              width: double.infinity,
            ),
          ),
        ],
      ),
    );
  }

  // Show Wire Payment Sheet
  void _showWirePaymentSheet(bool isDark) {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController routingController = TextEditingController();
    final TextEditingController accountController = TextEditingController();

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      maxHeight: MediaQuery.of(context).size.height * 0.95,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context)!.wireTransfer,
                    style: TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    AppLocalizations.of(context)!.sameOrNextBusinessDay,
                    style: TextStyle(
                      fontSize: 18,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Account Holder Name
                  Text(
                    AppLocalizations.of(context)!.accountHolderName,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TradeRepublicTextField(
                    controller: nameController,
                    hintText: AppLocalizations.of(context)!.johnDoe,
                  ),
                  const SizedBox(height: 24),

                  // Routing Number
                  Text(
                    AppLocalizations.of(context)!.routingNumber,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TradeRepublicTextField(
                    controller: routingController,
                    hintText: '110000000',
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 24),

                  // Account Number
                  Text(
                    AppLocalizations.of(context)!.accountNumber,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TradeRepublicTextField(
                    controller: accountController,
                    hintText: '000123456789',
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),

          // Button
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
            child: TradeRepublicButton(
              label: AppLocalizations.of(context)!.confirmWireTransfer,
              onPressed: () {
                if (nameController.text.isEmpty ||
                    routingController.text.isEmpty ||
                    accountController.text.isEmpty) {
                  TopNotification.error(
                    context,
                    AppLocalizations.of(context)!.pleaseFillInAllFields,
                  );
                  return;
                }
                Navigator.pop(context);
                _processPaymentWithMethod('wire_transfer', null);
              },
              width: double.infinity,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _processPaymentWithMethod(
    String methodType,
    String? methodId,
  ) async {
    // Don't close modals - let user see the process

    try {
      final orderId = _currentOrder['id'];

      print(
        '🔄 Processing payment: type=$methodType, methodId=$methodId, orderId=$orderId',
      );

      // Call the API to pay for approved order
      final response = await ApiService.payApprovedOrder(
        orderId,
        paymentMethodId: methodId ?? '',
        paymentMethodType: methodType,
      );

      print('📥 Payment response: $response');

      if (response['success'] == true) {
        // Close both modals on success
        Navigator.pop(context); // Close saved methods sheet
        Navigator.pop(context); // Close payment methods sheet

        TopNotification.show(
          context,
          message: AppLocalizations.of(
            context,
          )!.paymentSuccessfulOrderConfirmed,
          type: NotificationType.success,
          duration: const Duration(seconds: 3),
        );

        // Refresh order data
        await _refreshOrderData();

        // Notify parent to refresh orders list
        if (widget.onOrderUpdated != null) {
          widget.onOrderUpdated!();
        }
      } else {
        // Get error details from response
        String errorMessage = AppLocalizations.of(context)!.paymentFailed1;
        String? errorDetail =
            response['error']?.toString() ?? response['message']?.toString();

        print('❌ Payment failed: $errorDetail');

        // Parse Stripe errors
        if (errorDetail != null) {
          if (errorDetail.contains(
            AppLocalizations.of(context)!.noSuchPaymentmethod,
          )) {
            errorMessage = AppLocalizations.of(
              context,
            )!.dieseZahlungsmethodeIstNichtMehrGltignbitteF;
          } else if (errorDetail.contains(
            AppLocalizations.of(context)!.noStripeCustomer,
          )) {
            errorMessage = AppLocalizations.of(
              context,
            )!.bitteFgeZuerstEineZahlungsmethodeHinzu;
          } else if (errorDetail.contains('resource_missing')) {
            errorMessage = AppLocalizations.of(
              context,
            )!.zahlungsmethodeNichtGefundennbitteFgeEineNeue;
          } else if (errorDetail.isNotEmpty) {
            errorMessage = errorDetail;
          }
        }

        TopNotification.show(
          context,
          message: errorMessage,
          type: NotificationType.error,
          duration: const Duration(seconds: 6),
        );
      }
    } catch (e) {
      print('💥 Payment error: $e');

      TopNotification.show(
        context,
        message: AppLocalizations.of(
          context,
        )!.fehlerBeimBezahlenBitteVersucheEsErneut,
        type: NotificationType.error,
        duration: const Duration(seconds: 6),
      );
    }
  }

  // ==========================================
  // BANK TRANSFER DETAILS (SEPA/ACH/Wire) - Modern Net-style Card
  // ==========================================
  Widget _buildBankTransferDetails(bool isDark, String paymentMethod) {
    final hasAchDetails = _currentOrder['ach_details'] != null;
    final hasWireDetails = _currentOrder['wire_details'] != null;
    final paymentType =
        _currentOrder['payment_method_type']?.toString().toLowerCase() ?? '';

    // Method-specific styling
    final Color methodColor;
    final IconData methodIcon;
    final String methodTitle;

    if (hasAchDetails || paymentType == 'ach') {
      methodColor = TradeRepublicTheme.textColor(context);
      methodIcon = CupertinoIcons.money_dollar_circle_fill;
      methodTitle = AppLocalizations.of(context)!.achDirectDebit;
    } else if (hasWireDetails || paymentType == 'wire') {
      methodColor = TradeRepublicTheme.textColor(context);
      methodIcon = CupertinoIcons.arrow_right_arrow_left;
      methodTitle = AppLocalizations.of(context)!.wireTransfer;
    } else {
      methodColor = TradeRepublicTheme.textColor(context);
      methodIcon = CupertinoIcons.building_2_fill;
      methodTitle = AppLocalizations.of(context)!.sepaDirectDebit;
    }

    // Build a copyable field row
    Widget buildRow(String label, String value, {bool copyable = true}) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white38 : Colors.black38,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                      fontFamily: 'monospace',
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            if (copyable)
              GestureDetector(
                onTap: () {
                  if (value != AppLocalizations.of(context)!.notAvailable1 &&
                      value != AppLocalizations.of(context)!.ibanNotAvailable) {
                    Clipboard.setData(ClipboardData(text: value));
                    TopNotification.info(context, 'Copied!');
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: methodColor.withOpacity(isDark ? 0.15 : 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.copy_rounded,
                    size: 15,
                    color: methodColor,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    // Build field list for each payment type
    final List<({String label, String value, bool copyable})> fields;

    if (hasAchDetails || paymentType == 'ach') {
      final achDetails = _currentOrder['ach_details'];
      final routingNumber =
          achDetails?['virtual_routing_number'] ??
          achDetails?['routing_number'] ??
          AppLocalizations.of(context)!.notAvailable1;
      final accountNumber =
          achDetails?['virtual_account_number'] ??
          achDetails?['account_number'] ??
          AppLocalizations.of(context)!.notAvailable1;
      final bankName =
          (achDetails?['bank_name'] as String? ?? '').isNotEmpty
              ? achDetails!['bank_name'] as String
              : AppLocalizations.of(context)!.usBankAccount;
      final accountHolder = achDetails?['account_holder']?.toString() ?? '';
      fields = [
        if (accountHolder.isNotEmpty)
          (label: AppLocalizations.of(context)!.accountHolder, value: accountHolder, copyable: false),
        (label: 'Bank', value: bankName, copyable: false),
        (label: AppLocalizations.of(context)!.routingNumber, value: routingNumber, copyable: true),
        (label: AppLocalizations.of(context)!.accountNumber, value: accountNumber, copyable: true),
      ];
    } else if (hasWireDetails || paymentType == 'wire') {
      final wireDetails = _currentOrder['wire_details'];
      final swiftCode =
          wireDetails?['virtual_routing_number'] ??
          wireDetails?['swift_code'] ??
          AppLocalizations.of(context)!.notAvailable1;
      final accountNumber =
          wireDetails?['virtual_account_number'] ??
          wireDetails?['account_number'] ??
          AppLocalizations.of(context)!.notAvailable1;
      final bankName =
          (wireDetails?['bank_name'] as String? ?? '').isNotEmpty
              ? wireDetails!['bank_name'] as String
              : AppLocalizations.of(context)!.internationalWire;
      final bankAddress = wireDetails?['bank_address']?.toString() ?? '';
      fields = [
        (label: 'Bank', value: bankName, copyable: false),
        if (bankAddress.isNotEmpty)
          (label: AppLocalizations.of(context)!.bankAddress, value: bankAddress, copyable: false),
        (label: AppLocalizations.of(context)!.swiftbicCode, value: swiftCode, copyable: true),
        (label: AppLocalizations.of(context)!.accountNumber, value: accountNumber, copyable: true),
      ];
    } else {
      // SEPA
      final virtualIban =
          _currentOrder['sepa_details']?['virtual_iban'] ??
          AppLocalizations.of(context)!.ibanNotAvailable;
      final bic = _currentOrder['sepa_details']?['bic']?.toString() ?? '';
      final accountHolder =
          _currentOrder['sepa_details']?['account_holder']?.toString() ?? '';
      fields = [
        if (accountHolder.isNotEmpty)
          (label: AppLocalizations.of(context)!.accountHolder, value: accountHolder, copyable: false),
        (label: AppLocalizations.of(context)!.iban, value: virtualIban, copyable: true),
        if (bic.isNotEmpty)
          (label: AppLocalizations.of(context)!.bicSwift, value: bic, copyable: true),
      ];
    }

    return ClipRRect(
      borderRadius: TradeRepublicTheme.borderRadiusLarge,
      child: TradeRepublicCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Colored header row
            Container(
              color: methodColor.withOpacity(isDark ? 0.10 : 0.06),
              padding: _kSheetTilePadding,
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: methodColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(methodIcon, color: methodColor, size: 19),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    methodTitle,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: methodColor,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
            ),
            // Field rows with dividers
            for (int i = 0; i < fields.length; i++) ...[
              const TradeRepublicDivider(margin: EdgeInsets.zero),
              buildRow(fields[i].label, fields[i].value, copyable: fields[i].copyable),
            ],
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // PAYMENT DEADLINE COUNTDOWN (2 days)
  // ==========================================
  Widget _buildPaymentDeadlineCountdown(bool isDark) {
    // Get order date
    final orderDateStr =
        _currentOrder['order_date'] ??
        _currentOrder['date'] ??
        _currentOrder['created_at'];
    DateTime? orderDate;

    if (orderDateStr != null) {
      orderDate = DateTime.tryParse(orderDateStr.toString());
    }

    if (orderDate == null) {
      return const SizedBox.shrink();
    }

    // Payment deadline is 2 days (48 hours) from order creation
    final deadline = orderDate.add(const Duration(days: 2));
    final now = DateTime.now();
    final remaining = deadline.difference(now);

    // Check if deadline has passed
    final isExpired = remaining.isNegative;

    // Calculate display values
    final totalHours = remaining.inHours.abs();
    final days = totalHours ~/ 24;
    final hours = totalHours % 24;
    final minutes = remaining.inMinutes.abs() % 60;

    // Determine urgency level
    Color urgencyColor;
    String urgencyText;
    IconData urgencyIcon;

    if (isExpired) {
      urgencyColor = Colors.red;
      urgencyText = AppLocalizations.of(context)!.paymentDeadlineExpired;
      urgencyIcon = Icons.error_outline;
    } else if (remaining.inHours < 6) {
      urgencyColor = Colors.red;
      urgencyText = AppLocalizations.of(context)!.urgentPaymentRequiredSoon;
      urgencyIcon = Icons.warning_amber_rounded;
    } else if (remaining.inHours < 24) {
      urgencyColor = Colors.orange;
      urgencyText = AppLocalizations.of(context)!.lessThan24HoursRemaining;
      urgencyIcon = Icons.schedule;
    } else {
      urgencyColor = Colors.amber.shade700;
      urgencyText = AppLocalizations.of(context)!.timeRemainingToPay;
      urgencyIcon = Icons.timer_outlined;
    }

    return TradeRepublicCard(
      backgroundColor: urgencyColor.withOpacity(0.08),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(urgencyIcon, color: urgencyColor, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  urgencyText,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: urgencyColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Countdown Display
          if (!isExpired) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Days
                if (days > 0) ...[
                  _buildTimeUnit(days.toString(), 'Days', urgencyColor, isDark),
                  const SizedBox(width: 12),
                  Text(
                    ':',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: urgencyColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                // Hours
                _buildTimeUnit(
                  hours.toString().padLeft(2, '0'),
                  'Hours',
                  urgencyColor,
                  isDark,
                ),
                const SizedBox(width: 12),
                Text(
                  ':',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: urgencyColor,
                  ),
                ),
                const SizedBox(width: 12),
                // Minutes
                _buildTimeUnit(
                  minutes.toString().padLeft(2, '0'),
                  'Min',
                  urgencyColor,
                  isDark,
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Warning text
            TradeRepublicCard(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    CupertinoIcons.info,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(
                        context,
                      )!.orderWillBeAutomaticallyCancelledIfPaymentI,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            // Expired state
            TradeRepublicCard(
              backgroundColor: Colors.red.withOpacity(0.10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: TradeRepublicListTile(
                padding: EdgeInsets.zero,
                title: AppLocalizations.of(context)!.orderClosing,
                subtitle: AppLocalizations.of(context)!.paymentDeadlineHasPassedThisOrderWillBeClo,
                titleColor: Colors.red,
                leading: const Icon(CupertinoIcons.xmark_circle_fill, color: Colors.red, size: 28),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Time unit widget for countdown
  Widget _buildTimeUnit(String value, String label, Color color, bool isDark) {
    return Column(
      children: [
        TradeRepublicCard(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          backgroundColor: color.withOpacity(0.12),
          child: Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
              letterSpacing: -0.5,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // ==========================================
  // DRIVER AUCTION SECTION
  // ==========================================
  Widget _buildDriverAuctionSection(bool isDark) {
    print('🏗️ _buildDriverAuctionSection called');
    print('  - _isLoadingAuction: $_isLoadingAuction');
    print('  - _auction: $_auction');

    // Show loading indicator while auction is being loaded
    if (_isLoadingAuction) {
      return TradeRepublicCard(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                const CultiooLoadingIndicator(),
                const SizedBox(height: 16),
                Text(
                  AppLocalizations.of(context)!.loadingAuction,
                  style: _sheetCaptionStyle(context).copyWith(fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // If no auction exists yet, show mode selector + chosen UI
    if (_auction == null) {
      print('🏗️ No auction found - showing driver selection mode: $_driverSelectionMode');

      final selectionContent = Column(
        children: [
          _buildDriverModeSelector(isDark),
          const SizedBox(height: 16),
          if (_driverSelectionMode == 'auction')
            _buildStartAuctionUI(isDark)
          else
            _buildFindDriverUI(isDark),
          const SizedBox(height: 12),
          _buildArrangeOwnShippingCard(isDark),
        ],
      );

      final driverAssigned =
          _currentOrder['driver_id'] != null &&
          _currentOrder['driver_id'].toString().isNotEmpty &&
          _currentOrder['driver_id'].toString() != 'null';
      final auctionSt =
          _currentOrder['auction_status']?.toString().toLowerCase() ?? '';
      final orderStatus =
          _currentOrder['status']?.toString().toLowerCase() ?? '';
      // Match server: direct_assigned on the order row. If the list API omitted
      // auction_status, infer from typical pre-accept statuses so we do not hide the banner.
      final likelyDirectAssignPending = auctionSt.isEmpty &&
          ['pending', 'confirmed', 'awaiting', 'paid'].contains(orderStatus);
      final showAwaitingDriverBanner = _driverPendingConfirmation ||
          (driverAssigned &&
              (auctionSt == 'direct_assigned' || likelyDirectAssignPending));

      // Lock everything until the selected driver responds
      if (showAwaitingDriverBanner) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: _kSheetTilePadding,
              decoration: BoxDecoration(
                color: const Color(0xFFFF9500).withOpacity(isDark ? 0.16 : 0.10),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFFFF9500).withOpacity(0.25),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF9500).withOpacity(0.18),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      CupertinoIcons.clock_fill,
                      color: Color(0xFFFF9500),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Awaiting Driver Response',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Driver request is already active. Auction and Find Driver stay locked until this request is resolved.',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white54 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Entire selection UI greyed-out + non-interactive
            Opacity(
              opacity: 0.35,
              child: IgnorePointer(
                child: selectionContent,
              ),
            ),
          ],
        );
      }

      return selectionContent;
    }

    // Check if auction is expired and no driver was selected
    final endTimeStr = _auction!['end_time']?.toString() ?? '';
    final endTime = DateTime.tryParse(endTimeStr);
    final isExpired = endTime != null && DateTime.now().isAfter(endTime);
    // Use winning_bid_id (real DB column), fallback to accepted_bid_id
    final hasAcceptedBid =
        _auction!['winning_bid_id'] != null ||
        _auction!['accepted_bid_id'] != null;
    // Check driver_id on the order (orders table has driver_id, not driver_username)
    final driverAssigned =
        _currentOrder['driver_id'] != null &&
        _currentOrder['driver_id'].toString().isNotEmpty &&
        _currentOrder['driver_id'].toString() != 'null';

    // If auction expired without a driver being selected, allow reset
    if (_auction!['status'] != 'active' && !hasAcceptedBid && !driverAssigned) {
      print('🏗️ Auction expired without driver - showing Reset UI');
      return _buildAuctionExpiredNoDriverUI(isDark);
    }

    // If auction is active, show timer and bids
    if (_auction!['status'] == 'active') {
      // Also check if time is actually expired even if status says active
      if (isExpired && !hasAcceptedBid && !driverAssigned) {
        print('🏗️ Auction time expired without driver - showing Reset UI');
        return _buildAuctionExpiredNoDriverUI(isDark);
      }
      print('🏗️ Auction is active - showing Active Auction UI');
      return _buildActiveAuctionUI(isDark);
    }

    // If auction completed with driver selected
    print('🏗️ Auction completed - showing Completed UI');
    return _buildAuctionCompletedUI(isDark);
  }

  // Auction Expired Without Driver UI - allows user to restart auction
  Widget _buildAuctionExpiredNoDriverUI(bool isDark) {
    return TradeRepublicCard(
      backgroundColor: Colors.orange.withOpacity(0.06),
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          TradeRepublicListTile(
            padding: _kSheetTilePadding,
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(CupertinoIcons.time, color: Colors.orange, size: 20),
            ),
            title: AppLocalizations.of(context)!.auctionExpired,
            subtitle: AppLocalizations.of(context)!.noDriverWasSelected,
          ),
          const TradeRepublicDivider(margin: EdgeInsets.zero),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(CupertinoIcons.info, size: 14, color: Colors.orange.withOpacity(0.8)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        AppLocalizations.of(context)!.theAuctionEndedWithoutAnyDriverBeingAssigne,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white60 : Colors.black54,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TradeRepublicButton(
                  label: AppLocalizations.of(context)!.startNewAuction,
                  onPressed: _isStartingAuction ? null : _resetAuction,
                  icon: const Icon(CupertinoIcons.refresh),
                  isLoading: _isStartingAuction,
                  tint: Colors.orange,
                  width: double.infinity,
                ),
                const SizedBox(height: 8),
                _buildArrangeOwnShippingCard(isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // "Arrange own shipping" opt-out card shown below driver selection
  Widget _buildArrangeOwnShippingCard(bool isDark) {
    final loc = AppLocalizations.of(context)!;
    return TradeRepublicCard(
      backgroundColor: isDark
          ? Colors.white.withOpacity(0.03)
          : Colors.black.withOpacity(0.02),
      padding: EdgeInsets.zero,
      child: TradeRepublicListTile(
        padding: _kSheetTilePaddingCompact,
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.grey.withOpacity(0.12),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(
            CupertinoIcons.arrow_right_arrow_left,
            color: isDark ? Colors.white54 : Colors.black45,
            size: 18,
          ),
        ),
        title: loc.arrangeOwnShipping,
        subtitle: loc.arrangeOwnShippingSubtitle,
        trailing: TradeRepublicButton(
            label: loc.disable,
            isDestructive: true,
            isLoading: _isDisablingDelvioo,
            height: 36,
            onPressed: _isDisablingDelvioo ? null : _disableDelvioo,
          ),
      ),
    );
  }

  // Disable Delvioo – buyer opts to arrange shipping themselves
  Future<void> _disableDelvioo() async {
    final loc = AppLocalizations.of(context)!;

    // Confirm bottom sheet
    final confirmed = await TradeRepublicBottomSheet.show<bool>(
      context: context,
      showDragHandle: true,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                loc.arrangeOwnShipping,
                style: _sheetSubSheetTitleStyle(context),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                loc.arrangeOwnShippingConfirm,
                style: _sheetCaptionStyle(context).copyWith(fontSize: 15),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TradeRepublicButton(
                      label: loc.cancel,
                      isSecondary: true,
                      onPressed: () => Navigator.pop(context, false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: TradeRepublicButton(
                      label: loc.confirm,
                      isDestructive: true,
                      onPressed: () => Navigator.pop(context, true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true) return;

    if (_currentOrder['is_approval_request'] == true) {
      TopNotification.error(context, loc.arrangeOwnShippingFailed);
      return;
    }

    setState(() => _isDisablingDelvioo = true);
    try {
      final int? orderId =
          _toOrderInt(_currentOrder['id'] ?? _currentOrder['order_id']);
      if (orderId == null || orderId <= 0) {
        TopNotification.error(context, loc.arrangeOwnShippingFailed);
        return;
      }
      final response = await ApiService.setDelviooEnabled(orderId, false);
      if (response['success'] == true) {
        setState(() {
          _currentOrder['delvioo'] = 0;
        });
        TopNotification.success(context, loc.arrangeOwnShippingSuccess);
        widget.onOrderUpdated?.call();
      } else {
        TopNotification.error(context, response['message'] ?? loc.arrangeOwnShippingFailed);
      }
    } catch (e) {
      print('❌ Error disabling Delvioo: $e');
      TopNotification.error(context, loc.arrangeOwnShippingFailed);
    } finally {
      setState(() => _isDisablingDelvioo = false);
    }
  }

  // Reset auction to allow starting a new one
  Future<void> _resetAuction() async {
    setState(() => _isStartingAuction = true);

    try {
      final orderId = _currentOrder['id'];

      // Call API to reset/delete the expired auction
      final response = await ApiService.resetDriverAuction(orderId);

      if (response['success'] == true) {
        setState(() {
          _auction = null;
          _bids = [];
        });
        TopNotification.success(
          context,
          AppLocalizations.of(context)!.auctionResetYouCanStartANewAuction,
        );
      } else {
        TopNotification.error(
          context,
          response['message'] ?? AppLocalizations.of(context)!.failedToResetAuction,
        );
      }
    } catch (e) {
      print('❌ Error resetting auction: $e');
      // Even if API fails, allow local reset
      setState(() {
        _auction = null;
        _bids = [];
      });
      TopNotification.info(
        context,
        AppLocalizations.of(context)!.auctionResetLocallyYouCanStartANewAuction,
      );
    } finally {
      setState(() => _isStartingAuction = false);
    }
  }

  Future<void> _cancelAuction() async {
    setState(() => _isStartingAuction = true);

    try {
      final orderId = _currentOrder['id'];
      print('🔴 Cancel auction: orderId=$orderId, type=${orderId.runtimeType}');
      final response = await ApiService.cancelDriverAuction(orderId);
      print('🔴 Cancel auction response: $response');

      if (!mounted) return;

      if (response['success'] == true) {
        await _loadAuction();
        TopNotification.success(
          context,
          response['message']?.toString() ?? 'Driver request cancelled',
        );
      } else {
        TopNotification.error(
          context,
          response['message']?.toString() ?? 'Failed to cancel driver request',
        );
      }
    } catch (e) {
      print('🔴 Cancel auction error: $e');
      if (!mounted) return;
      TopNotification.error(
        context,
        'Failed to cancel driver request',
        title: e.toString(),
      );
    } finally {
      if (mounted) setState(() => _isStartingAuction = false);
    }
  }

  // Start Auction UI - allows user to set timer duration
  Widget _buildStartAuctionUI(bool isDark) {
    final isLight = TradeRepublicTheme.isLight(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sheetSectionLabelWidget(
          context,
          AppLocalizations.of(context)!.driverAuction,
        ),
        TradeRepublicCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isLight ? Colors.black : Colors.white,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(
                      CupertinoIcons.cube_box,
                      color: isLight ? Colors.white : Colors.black,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLocalizations.of(context)!.driverAuction,
                          style: _sheetSubSheetTitleStyle(context),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          AppLocalizations.of(context)!.getCompetitiveDeliveryOffers,
                          style: _sheetCaptionStyle(context).copyWith(
                            fontSize: 15,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              TradeRepublicCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'How to use auction',
                      style: TradeRepublicTheme.titleSmall(context).copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TradeRepublicListTile(
                      padding: _kSheetTilePaddingCompact,
                      leading: Icon(
                        CupertinoIcons.timer,
                        size: 18,
                        color: TradeRepublicTheme.textColor(context),
                      ),
                      title: AppLocalizations.of(context)!.auctionStepSetDuration,
                      subtitle: AppLocalizations.of(context)!.auctionStepSetDurationSubtitle,
                    ),
                    TradeRepublicListTile(
                      padding: _kSheetTilePaddingCompact,
                      leading: const Icon(
                        CupertinoIcons.slider_horizontal_3,
                        size: 18,
                        color: Color(0xFFFF9500),
                      ),
                      title: AppLocalizations.of(context)!.auctionStepOptionalRules,
                      subtitle: AppLocalizations.of(context)!.auctionStepOptionalRulesSubtitle,
                    ),
                    TradeRepublicListTile(
                      padding: _kSheetTilePaddingCompact,
                      leading: Icon(
                        CupertinoIcons.checkmark_seal_fill,
                        size: 18,
                        color: TradeRepublicTheme.textColor(context),
                      ),
                      title: AppLocalizations.of(context)!.auctionStepStartAndChoose,
                      subtitle: AppLocalizations.of(context)!.auctionStepStartAndChooseSubtitle,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              TradeRepublicCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: TradeRepublicTheme.textColor(context).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            CupertinoIcons.time,
                            color: TradeRepublicTheme.textColor(context),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          AppLocalizations.of(context)!.auctionDuration,
                          style: TradeRepublicTheme.titleSmall(context).copyWith(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        _buildDurationChip(15, isDark),
                        const SizedBox(width: 12),
                        _buildDurationChip(30, isDark),
                        const SizedBox(width: 12),
                        _buildDurationChip(60, isDark),
                        const SizedBox(width: 12),
                        _buildDurationChip(120, isDark),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TradeRepublicButton(
                      label: AppLocalizations.of(context)!.auctionCustomDuration,
                      icon: Icon(
                        _useCustomDuration
                            ? CupertinoIcons.time
                            : CupertinoIcons.pencil,
                        color: Colors.white,
                        size: 16,
                      ),
                      height: 44,
                      tint: _useCustomDuration
                          ? TradeRepublicTheme.textColor(context)
                          : null,
                      isSecondary: !_useCustomDuration,
                      onPressed: () {
                        setState(() {
                          _useCustomDuration = !_useCustomDuration;
                          if (_useCustomDuration) {
                            _customDurationController.text =
                                _selectedAuctionDuration.toString();
                          }
                        });
                      },
                    ),
                  ],
                ),
              ),

              // Custom duration input field
              if (_useCustomDuration) ...[
                const SizedBox(height: 20),
                TradeRepublicCard(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context)!.customDuration,
                        style: TradeRepublicTheme.titleSmall(context).copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TradeRepublicTextField(
                        controller: _customDurationController,
                        keyboardType: TextInputType.number,
                        hintText: AppLocalizations.of(context)!.enterMinutes,
                        onChanged: (value) {
                          final minutes = int.tryParse(value);
                          if (minutes != null &&
                              minutes >= 5 &&
                              minutes <= 180) {
                            setState(() {
                              _selectedAuctionDuration = minutes;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      Text(
                        AppLocalizations.of(context)!.range5180Minutes3HoursMax,
                        style: _sheetCaptionStyle(context).copyWith(fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
          const SizedBox(height: 24),

          // ── Max Bid Price ──
          _buildAuctionSmartCard(
            isDark: isDark,
            icon: CupertinoIcons.money_dollar_circle,
            color: TradeRepublicTheme.textColor(context),
            title: AppLocalizations.of(context)!.auctionMaxBidPrice,
            subtitle: AppLocalizations.of(context)!.auctionMaxBidPriceSubtitle,
            isEnabled: _maxBidEnabled,
            onToggle: (val) => setState(() {
              _maxBidEnabled = val;
              if (!val) {
                _maxBidPrice = null;
                _maxBidPriceController.clear();
              }
            }),
            child: _maxBidEnabled
                ? Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: TradeRepublicTextField(
                      controller: _maxBidPriceController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [_CurrencyRtlFormatter()],
                      hintText: AppLocalizations.of(context)!.auctionMaxBidPlaceholder,
                      onChanged: (val) {
                        _maxBidPrice = double.tryParse(val.replaceAll(',', ''));
                      },
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 12),

          // ── Auto-Accept ──
          _buildAuctionSmartCard(
            isDark: isDark,
            icon: CupertinoIcons.bolt_circle,
            color: const Color(0xFFFF9500),
            title: AppLocalizations.of(context)!.auctionAutoAccept,
            subtitle: AppLocalizations.of(context)!.auctionAutoAcceptSubtitle,
            isEnabled: _autoAcceptEnabled,
            onToggle: (val) => setState(() {
              _autoAcceptEnabled = val;
              if (!val) {
                _autoAcceptThreshold = null;
                _autoAcceptController.clear();
              }
            }),
            child: _autoAcceptEnabled
                ? Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: TradeRepublicTextField(
                      controller: _autoAcceptController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [_CurrencyRtlFormatter()],
                      hintText: AppLocalizations.of(context)!.auctionAutoAcceptPlaceholder,
                      onChanged: (val) {
                        _autoAcceptThreshold = double.tryParse(val.replaceAll(',', ''));
                      },
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 12),

          // ── Min Bids ──
          _buildAuctionSmartCard(
            isDark: isDark,
            icon: CupertinoIcons.person_2,
            color: const Color(0xFFFF3B30),
            title: AppLocalizations.of(context)!.auctionMinBids,
            subtitle: AppLocalizations.of(context)!.auctionMinBidsSubtitle,
            isEnabled: _minBidsEnabled,
            onToggle: (val) => setState(() {
              _minBidsEnabled = val;
              if (!val) {
                _minBids = null;
                _minBidsController.clear();
              }
            }),
            child: _minBidsEnabled
                ? Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: TradeRepublicTextField(
                      controller: _minBidsController,
                      keyboardType: TextInputType.number,
                      hintText: AppLocalizations.of(context)!.auctionMinBidsPlaceholder,
                      onChanged: (val) {
                        _minBids = int.tryParse(val);
                      },
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 12),

          // ── Cully AI ──
          _buildAuctionSmartCard(
            isDark: isDark,
            icon: CupertinoIcons.sparkles,
            color: TradeRepublicTheme.textColor(context),
            title: AppLocalizations.of(context)!.cullyAiSelectBestDriver,
            subtitle: AppLocalizations.of(context)!.cullyAiSubtitle,
            isEnabled: _cullyAiEnabled,
            onToggle: (val) => setState(() => _cullyAiEnabled = val),
          ),
          const SizedBox(height: 24),

          // Clean info section
          TradeRepublicCard(
            child: TradeRepublicListTile(
              padding: _kSheetTilePaddingCompact,
              title: AppLocalizations.of(context)!.howItWorks,
              subtitle: AppLocalizations.of(context)!.driversSubmitBidsChooseTheBestOfferAndSave,
              leading: Icon(
                CupertinoIcons.lightbulb,
                size: 22,
                color: TradeRepublicTheme.textColor(context),
              ),
            ),
          ),
          const SizedBox(height: 32),

          // Clean start button - Trade Republic style
          TradeRepublicButton(
            label: AppLocalizations.of(context)!.startAuction,
            icon: const Icon(
              CupertinoIcons.play_circle_fill,
              color: Colors.white,
              size: 20,
            ),
            tint: TradeRepublicTheme.textColor(context),
            isLoading: _isStartingAuction,
            onPressed: _isStartingAuction ? null : _startAuction,
            width: double.infinity,
          ),
            ],
          ),
        ),
      ],
    );
  }

  // ==========================================
  // DRIVER MODE SELECTOR (Auction vs Find Driver)
  // ==========================================
  Widget _buildDriverModeSelector(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sheetSectionLabelWidget(
          context,
          AppLocalizations.of(context)!.deliveryInformation1,
        ),
        TradeRepublicCard(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          child: TradeRepublicSlider(
            labels: [
              AppLocalizations.of(context)!.driverAuction,
              AppLocalizations.of(context)!.findDriver,
            ],
            selectedIndex: _driverSelectionMode == 'auction' ? 0 : 1,
            onChanged: (index) {
              setState(() =>
                  _driverSelectionMode = index == 0 ? 'auction' : 'findDriver');
              if (index == 1 &&
                  _availableDrivers.isEmpty &&
                  !_isLoadingAvailableDrivers) {
                _loadAvailableDrivers();
              }
            },
          ),
        ),
      ],
    );
  }

  // ==========================================
  // FIND DRIVER ON MAP UI
  // ==========================================
  bool _isDriverOccupied(Map<String, dynamic> driver) {
    final raw = driver['is_occupied'] ??
        driver['is_busy'] ??
        driver['busy'] ??
        driver['occupied'] ??
        driver['availability_status'];

    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    final s = raw?.toString().toLowerCase().trim() ?? '';
    return s == '1' ||
        s == 'true' ||
        s == 'occupied' ||
        s == 'busy' ||
        s == 'assigned' ||
        s == 'unavailable';
  }

  bool _driverMatchesRequiredWagon(Map<String, dynamic> driver) {
    final raw = driver['matches_required_wagon'];
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    final s = raw?.toString().toLowerCase().trim() ?? '';
    if (s == '1' || s == 'true') return true;

    // Fallback for deployments where matches_required_wagon is missing:
    // compare normalized vehicle type to normalized required wagon.
    final required = normalizeWagonTypeId(_requiredWagonType);
    if (required.isEmpty) return true;
    final vehicle = normalizeWagonTypeId(driver['vehicle_type']?.toString());
    if (vehicle.isEmpty) return false;
    return vehicle == required;
  }

  bool _driverPassesRequiredWagonFilter(Map<String, dynamic> driver) {
    final required = _requiredWagonType?.trim() ?? '';
    if (required.isEmpty) return true;
    return _driverMatchesRequiredWagon(driver);
  }

  double _toSortableDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? double.nan;
    return double.nan;
  }

  /// Distance used for sorting (matches list totals when OSRM pickup→delivery is loaded).
  double _driverSortDistanceKm(Map<String, dynamic> driver) {
    final total = _driverDistanceTotalKm(driver);
    if (total != null && total > 0) return total;
    return _toSortableDouble(driver['distance_km'] ?? driver['distance']);
  }

  String _requiredWagonLabel() {
    final raw = _requiredWagonType?.trim();
    if (raw == null || raw.isEmpty) return AppLocalizations.of(context)!.unknown;
    return wagonLabelFromType(raw, AppLocalizations.of(context)!);
  }

  List<Map<String, dynamic>> get _sortedDrivers {
    final source = _availableDrivers
        .where(_driverPassesRequiredWagonFilter)
        .where((d) => _hideOccupiedDrivers ? !_isDriverOccupied(d) : true)
        .toList();
    final list = source;
    list.sort((a, b) {
      final aBusy = _isDriverOccupied(a);
      final bBusy = _isDriverOccupied(b);

      if (_driverSortBy == 'status') {
        if (aBusy != bBusy) return aBusy ? 1 : -1; // green first, red after
        final ad = _driverSortDistanceKm(a);
        final bd = _driverSortDistanceKm(b);
        if (ad.isNaN && !bd.isNaN) return 1;
        if (!ad.isNaN && bd.isNaN) return -1;
        if (!ad.isNaN && !bd.isNaN) return ad.compareTo(bd);
        return 0;
      }

      if (_driverSortBy == 'distance') {
        final ad = _driverSortDistanceKm(a);
        final bd = _driverSortDistanceKm(b);
        if (ad.isNaN && !bd.isNaN) return 1;
        if (!ad.isNaN && bd.isNaN) return -1;
        if (!ad.isNaN && !bd.isNaN) return ad.compareTo(bd);
        return 0;
      }

      if (_driverSortBy == 'rating') {
        final ar = _toSortableDouble(a['rating']);
        final br = _toSortableDouble(b['rating']);
        if (ar.isNaN && !br.isNaN) return 1;
        if (!ar.isNaN && br.isNaN) return -1;
        if (!ar.isNaN && !br.isNaN) return br.compareTo(ar);
        return 0;
      }

      if (_driverSortBy == 'wagon') {
        final aMatch = _driverMatchesRequiredWagon(a);
        final bMatch = _driverMatchesRequiredWagon(b);
        if (aMatch != bMatch) return aMatch ? -1 : 1;
        if (aBusy != bBusy) return aBusy ? 1 : -1;
        final ad = _driverSortDistanceKm(a);
        final bd = _driverSortDistanceKm(b);
        if (ad.isNaN && !bd.isNaN) return 1;
        if (!ad.isNaN && bd.isNaN) return -1;
        if (!ad.isNaN && !bd.isNaN) return ad.compareTo(bd);
        return 0;
      }

      final ap = _toSortableDouble(a['estimated_price'] ?? a['price']);
      final bp = _toSortableDouble(b['estimated_price'] ?? b['price']);
      if (ap.isNaN && !bp.isNaN) return 1;
      if (!ap.isNaN && bp.isNaN) return -1;
      if (!ap.isNaN && !bp.isNaN) return ap.compareTo(bp);
      return 0;
    });
    return list;
  }

  Widget _buildDriverSortControl(bool isDark, {StateSetter? setSheetState}) {
    Widget chip(String key, String label) {
      final selected = _driverSortBy == key;
      return GestureDetector(
        onTap: () {
          setState(() => _driverSortBy = key);
          setSheetState?.call(() {});
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? TradeRepublicTheme.textColor(context)
                : _sheetSurfaceMuted(context),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.1,
              color: selected
                  ? (TradeRepublicTheme.isLight(context)
                      ? Colors.white
                      : Colors.black)
                  : TradeRepublicTheme.hintColor(context, opacity: 0.65),
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          // Free-only toggle
          GestureDetector(
            onTap: () {
              setState(() => _hideOccupiedDrivers = !_hideOccupiedDrivers);
              setSheetState?.call(() {});
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _hideOccupiedDrivers
                    ? TradeRepublicTheme.textColor(context)
                    : _sheetSurfaceMuted(context),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    _hideOccupiedDrivers
                        ? AppLocalizations.of(context)!.free
                        : AppLocalizations.of(context)!.all,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.1,
                      color: _hideOccupiedDrivers
                          ? Colors.white
                          : TradeRepublicTheme.hintColor(context, opacity: 0.65),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          chip('wagon', AppLocalizations.of(context)!.wagonType),
          const SizedBox(width: 8),
          chip('status', '${AppLocalizations.of(context)!.free} / ${AppLocalizations.of(context)!.occupied}'),
          const SizedBox(width: 8),
          chip('distance', AppLocalizations.of(context)!.proximity),
        ],
      ),
    );
  }

  void _onDriverTap(Map<String, dynamic> driver, bool isDark) {
    if (_isDriverOccupied(driver)) {
      TopNotification.info(context, AppLocalizations.of(context)!.driverCurrentlyOccupied);
      return;
    }
    _confirmDriverSelection(driver, isDark);
  }

  Future<void> _loadAvailableDrivers() async {
    setState(() => _isLoadingAvailableDrivers = true);
    try {
      final orderId = _currentOrder['id'];
      // Try progressively wider search radius to avoid false empty state.
      Map<String, dynamic> response = await ApiService.getAvailableDrivers(
        orderId,
        radiusKm: 100,
        includeOccupied: true,
      );
      List<dynamic> drivers = (response['drivers'] as List<dynamic>?) ?? [];

      if (response['success'] == true && drivers.isEmpty) {
        response = await ApiService.getAvailableDrivers(
          orderId,
          radiusKm: 250,
          includeOccupied: true,
        );
        drivers = (response['drivers'] as List<dynamic>?) ?? [];
      }

      if (response['success'] == true && drivers.isEmpty) {
        response = await ApiService.getAvailableDrivers(
          orderId,
          radiusKm: 500,
          includeOccupied: true,
        );
        drivers = (response['drivers'] as List<dynamic>?) ?? [];
      }

      if (response['success'] == true && mounted) {
        setState(() {
          _availableDrivers = drivers.map((d) => Map<String, dynamic>.from(d)).toList();
          _driverToPickupRoadKmById.clear();
          _requiredWagonType = (response['required_wagon_type'] ??
                  response['required_wagon_normalized'])
              ?.toString();
          // Merge pickup/delivery coordinates from available-drivers response into current order
          if (response['pickup_lat'] != null) {
            _currentOrder['pickup_lat'] = response['pickup_lat'];
            _currentOrder['pickup_latitude'] = response['pickup_lat'];
          }
          if (response['pickup_lng'] != null) {
            _currentOrder['pickup_lng'] = response['pickup_lng'];
            _currentOrder['pickup_longitude'] = response['pickup_lng'];
          }
          if (response['delivery_lat'] != null) {
            _currentOrder['delivery_lat'] = response['delivery_lat'];
            _currentOrder['delivery_latitude'] = response['delivery_lat'];
          }
          if (response['delivery_lng'] != null) {
            _currentOrder['delivery_lng'] = response['delivery_lng'];
            _currentOrder['delivery_longitude'] = response['delivery_lng'];
          }
        });
        _refreshRoadPickupToDeliveryKm();
        _refreshDriverToPickupOsrmLeg1Batch();
      }
    } catch (e) {
      print('❌ Error loading available drivers: $e');
    } finally {
      if (mounted) setState(() => _isLoadingAvailableDrivers = false);
    }
  }

  Future<void> _selectDriverDirectly(
    Map<String, dynamic> driver, {
    int? selectedSectionIndex,
  }) async {
    final parsedId = driver['id'] is int
        ? driver['id'] as int
        : int.tryParse(driver['id']?.toString() ?? '');
    if (parsedId == null || parsedId <= 0) {
      if (mounted) {
        TopNotification.error(
          context,
          'Invalid driver id — please refresh the driver list and try again.',
        );
      }
      return;
    }
    final driverId = parsedId;

    final double shippingAmount = _parseNumericValue(
        driver['estimated_price'] ?? driver['price'] ?? driver['bid_amount']);

    setState(() => _isSelectingDriver = true);
    try {
      final orderId = _currentOrder['id'];
      final response = await ApiService.selectDriverDirectly(
        orderId,
        driverId,
        shippingAmount: shippingAmount > 0 ? shippingAmount : null,
        selectedSectionIndex: selectedSectionIndex,
      );

      if (!mounted) return;

      if (response['success'] == true) {
        final autoCharge = response['auto_charge'] as Map<String, dynamic>?;
        setState(() {
          _currentOrder['driver_id'] = driverId;
          _currentOrder['driver_username'] = driver['username'] ?? driver['name'];
          // Keep local order in sync with server (select-driver sets these on the row).
          _currentOrder['auction_status'] = 'direct_assigned';
          _currentOrder['delvioo'] = 1;
          _driverPendingConfirmation = true;
        });
        if (autoCharge != null && autoCharge['paid'] == true) {
          final amount = (autoCharge['amount'] as num?)?.toStringAsFixed(2) ?? '';
          final method = autoCharge['method']?.toString() ?? '';
          final methodLabel = method == 'wallet' ? 'Monioo Balance' :
              (autoCharge['last4'] != null ? '**** ${autoCharge['last4']}' : method);
          TopNotification.info(
            context,
            '⏳ Processing · \$$amount charged via $methodLabel',
          );
        } else {
          TopNotification.info(
            context,
            '⏳ Processing · Driver confirming shortly',
          );
        }
        widget.onOrderUpdated?.call();
      } else {
        if (mounted) {
          TopNotification.error(context, response['message'] ?? 'Error');
        }
      }
    } catch (e) {
      print('❌ Error selecting driver: $e');
      if (mounted) {
        TopNotification.error(context, e.toString());
      }
    } finally {
      if (mounted) setState(() => _isSelectingDriver = false);
    }
  }

  void _confirmDriverSelection(Map<String, dynamic> driver, bool isDark) {
    // ── Capacity check before showing confirmation ──
    final double cargoCapacity = _parseQuantity(driver['cargo_capacity']);
    final String cargoUnit = driver['cargo_unit']?.toString() ?? '';
    final double payloadCapacity = _parseQuantity(driver['payload_capacity']);
    final String payloadUnit = driver['payload_unit']?.toString() ?? '';

    final orderInfo = _getOrderTotalQuantityAndUnit();
    final double orderQty = orderInfo['quantity'] as double;
    final String orderUnit = orderInfo['unit'] as String;

    final bool orderIsVolume = _isVolumeUnit(orderUnit);
    final double vehicleCap = orderIsVolume ? cargoCapacity : payloadCapacity;
    final String vehicleCapUnit = orderIsVolume ? cargoUnit : payloadUnit;

    // No capacity data or zero order quantity → skip check
    if (vehicleCap <= 0 || vehicleCapUnit.isEmpty || orderQty <= 0) {
      _showRegularDriverConfirmation(driver, isDark);
      return;
    }

    final double orderBase = _normalizeToBase(orderQty, orderUnit);
    final double vehicleBase = _normalizeToBase(vehicleCap, vehicleCapUnit);
    final bool orderFits = orderBase <= vehicleBase;
    final double fillPercent =
        vehicleBase > 0 ? (orderBase / vehicleBase * 100).clamp(0.0, 999.0) : 0.0;

    _showVehicleCapacityModal(
      driver: driver,
      isDark: isDark,
      orderQty: orderQty,
      orderUnit: orderUnit,
      vehicleCap: vehicleCap,
      vehicleCapUnit: vehicleCapUnit,
      orderFits: orderFits,
      fillPercent: fillPercent,
      orderBase: orderBase,
      vehicleBase: vehicleBase,
    );
  }

  void _showRegularDriverConfirmation(
    Map<String, dynamic> driver,
    bool isDark, {
    int? selectedSectionIndex,
  }) {
    final username = driver['username']?.toString().trim() ?? '';
    final driverName = username.isNotEmpty
        ? '@$username'
        : (driver['name'] ?? AppLocalizations.of(context)!.findDriver);
    final rating = driver['rating'];
    final vehicleType = driver['vehicle_type'] ?? '';
    final price = _driverEstimatedPrice(driver);
    final sectionsInfo = _driverSectionsDetail(driver);
    final pricingDetail = _driverPricingDetail(driver);
    final suggestedSplit =
        _calculateSuggestedSplitForDriver(driver) ?? _splitHintFromDriver(driver);

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      maxHeight: 420,
      child: Builder(
        builder: (sheetCtx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: TradeRepublicTheme.textColor(context).withOpacity(0.15),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Center(
                child: Text(
                  driverName.toString().isNotEmpty ? driverName.toString().substring(0, 1).toUpperCase() : 'D',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: TradeRepublicTheme.textColor(context),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              driverName.toString(),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (rating != null) ...[
                  const Icon(CupertinoIcons.star_fill, size: 14, color: Color(0xFFFF9500)),
                  const SizedBox(width: 4),
                  Text(double.tryParse(rating.toString())?.toStringAsFixed(1) ?? rating.toString(),
                    style: TextStyle(fontSize: 14, color: isDark ? Colors.white70 : Colors.black54)),
                  const SizedBox(width: 12),
                ],
                if (vehicleType.toString().isNotEmpty) ...[
                  Icon(CupertinoIcons.car_detailed, size: 14, color: isDark ? Colors.white54 : Colors.black38),
                  const SizedBox(width: 4),
                  Text(vehicleType.toString(), style: TextStyle(fontSize: 14, color: isDark ? Colors.white70 : Colors.black54)),
                ],
              ],
            ),
            if (sectionsInfo.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    CupertinoIcons.square_split_2x1,
                    size: 13,
                    color: isDark ? Colors.white54 : Colors.black38,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    sectionsInfo,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ],
            if (pricingDetail.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    CupertinoIcons.speedometer,
                    size: 13,
                    color: isDark ? Colors.white54 : Colors.black38,
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      pricingDetail,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (price != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: _kSheetTilePaddingDense,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF181818) : Colors.black.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(AppLocalizations.of(context)!.estimatedPrice,
                      style: TextStyle(fontSize: 13, color: isDark ? Colors.white54 : Colors.black45)),
                    const SizedBox(width: 8),
                    Text(_formatCurrency(price),
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: isDark ? Colors.white : Colors.black)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            Text(
              AppLocalizations.of(context)!.confirmDriverSelection,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: isDark ? Colors.white60 : Colors.black45),
            ),
            const SizedBox(height: 12),
            if (suggestedSplit != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9500).withOpacity(isDark ? 0.16 : 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      CupertinoIcons.square_split_2x1_fill,
                      size: 14,
                      color: Color(0xFFFF9500),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Split suggested: ${_fmtQty(suggestedSplit['fittingQty'])} ${suggestedSplit['unit']} fit, ${_fmtQty(suggestedSplit['remainingQty'])} ${suggestedSplit['unit']} as new order.',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
            // ── Payment auto-charge note ──────────────────────────────────
            if (price != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: TradeRepublicTheme.textColor(context).withOpacity(isDark ? 0.12 : 0.07),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      CupertinoIcons.creditcard_fill,
                      size: 14,
                      color: TradeRepublicTheme.textColor(context),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Shipping cost (${_formatCurrency(price)}) will be charged automatically upon confirmation.',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            TradeRepublicButton(
              label: AppLocalizations.of(context)!.selectThisDriver,
              tint: TradeRepublicTheme.textColor(context),
              icon: const Icon(CupertinoIcons.checkmark_circle_fill, color: Colors.white, size: 20),
              isLoading: _isSelectingDriver,
              onPressed: _isSelectingDriver ? null : () {
                Navigator.of(sheetCtx).pop();
                if (!mounted) return;
                if (suggestedSplit != null) {
                  _showDriverSplitModal(
                    driver: driver,
                    isDark: isDark,
                    fittingQty: (suggestedSplit['fittingQty'] as num).toDouble(),
                    remainingQty: (suggestedSplit['remainingQty'] as num).toDouble(),
                    unit: suggestedSplit['unit'].toString(),
                    selectedSectionIndex: selectedSectionIndex,
                  );
                } else {
                  _selectDriverDirectly(
                    driver,
                    selectedSectionIndex: selectedSectionIndex,
                  );
                }
              },
              width: double.infinity,
            ),
          ],
        ),
      ),
      ),
    );
  }

  Map<String, dynamic>? _calculateSuggestedSplitForDriver(
    Map<String, dynamic> driver,
  ) {
    final orderInfo = _getOrderTotalQuantityAndUnit();
    final double orderQty = orderInfo['quantity'] as double;
    final String orderUnit = orderInfo['unit'] as String;
    if (orderQty <= 0) return null;

    final double cargoCapacity = _parseQuantity(driver['cargo_capacity']);
    final String cargoUnit = driver['cargo_unit']?.toString() ?? '';
    final double payloadCapacity = _parseQuantity(driver['payload_capacity']);
    final String payloadUnit = driver['payload_unit']?.toString() ?? '';

    final bool orderIsVolume = _isVolumeUnit(orderUnit);
    final double vehicleCap = orderIsVolume ? cargoCapacity : payloadCapacity;
    final String vehicleCapUnit = orderIsVolume ? cargoUnit : payloadUnit;
    if (vehicleCap <= 0 || vehicleCapUnit.isEmpty) return null;

    final double orderBase = _normalizeToBase(orderQty, orderUnit);
    final double vehicleBase = _normalizeToBase(vehicleCap, vehicleCapUnit);
    if (orderBase <= 0 || vehicleBase <= 0 || orderBase <= vehicleBase) {
      return null;
    }

    final double fittingFraction = (vehicleBase / orderBase).clamp(0.0, 1.0);
    final double fittingQty = orderQty * fittingFraction;
    final double remainingQty = orderQty - fittingQty;
    if (remainingQty <= 0) return null;

    return {
      'fittingQty': fittingQty,
      'remainingQty': remainingQty,
      'unit': orderUnit,
    };
  }

  // Compute split suggestion from an auction bid (which now carries vehicle capacity)
  Map<String, dynamic>? _calculateSuggestedSplitForBid(
    Map<String, dynamic> bid,
  ) {
    final orderInfo = _getOrderTotalQuantityAndUnit();
    final double orderQty = orderInfo['quantity'] as double;
    final String orderUnit = orderInfo['unit'] as String;
    if (orderQty <= 0) {
      print('⚠️ _calculateSuggestedSplitForBid: orderQty=0, skipping');
      return null;
    }

    final double payloadCap = _parseQuantity(bid['payload_capacity']);
    final String payloadUnit = bid['payload_unit']?.toString() ?? '';
    final double cargoCap = _parseQuantity(bid['cargo_capacity']);
    final String cargoUnit = bid['cargo_unit']?.toString() ?? '';

    final bool orderIsVolume = _isVolumeUnit(orderUnit);
    double vehicleCap = orderIsVolume ? cargoCap : payloadCap;
    String vehicleCapUnit = orderIsVolume ? cargoUnit : payloadUnit;

    if (vehicleCap <= 0 || vehicleCapUnit.isEmpty) {
      print('⚠️ _calculateSuggestedSplitForBid: no vehicle capacity in bid');
      return null;
    }

    // Apply section percentage
    final sectionIdx = (bid['section_index'] as num?)?.toInt() ?? 0;
    final rawSections = bid['vehicle_sections'];
    if (rawSections != null) {
      List<dynamic> sections;
      if (rawSections is String) {
        try { sections = jsonDecode(rawSections) as List<dynamic>; } catch (_) { sections = []; }
      } else {
        sections = rawSections as List<dynamic>;
      }
      if (sectionIdx < sections.length) {
        final section = sections[sectionIdx] as Map<String, dynamic>;
        final pct = _parseQuantity(section['percentage']) / 100.0;
        if (pct > 0 && pct <= 1) vehicleCap = vehicleCap * pct;
      }
    }

    final double orderBase = _normalizeToBase(orderQty, orderUnit);
    final double vehicleBase = _normalizeToBase(vehicleCap, vehicleCapUnit);

    print('🔍 _calculateSuggestedSplitForBid: orderQty=$orderQty $orderUnit → base=$orderBase, vehicleCap=$vehicleCap $vehicleCapUnit → base=$vehicleBase');

    if (orderBase <= 0 || vehicleBase <= 0 || orderBase <= vehicleBase) return null;

    final double fittingFraction = (vehicleBase / orderBase).clamp(0.0, 1.0);
    final double fittingQty = orderQty * fittingFraction;
    final double remainingQty = orderQty - fittingQty;
    if (remainingQty <= 0) return null;

    print('✂️ Split suggested: fitting=$fittingQty, remaining=$remainingQty $orderUnit');
    return {
      'fittingQty': fittingQty,
      'remainingQty': remainingQty,
      'unit': orderUnit,
    };
  }

  Map<String, dynamic>? _splitHintFromDriver(Map<String, dynamic> driver) {
    double? readNum(List<String> keys) {
      for (final key in keys) {
        final raw = driver[key];
        if (raw == null) continue;
        final v = _parseQuantity(raw);
        if (v > 0) return v;
      }
      return null;
    }

    String? readUnit(List<String> keys) {
      for (final key in keys) {
        final raw = driver[key]?.toString().trim();
        if (raw != null && raw.isNotEmpty) return raw;
      }
      return null;
    }

    final orderInfo = _getOrderTotalQuantityAndUnit();
    final orderQty = orderInfo['quantity'] as double;
    final orderUnit = (orderInfo['unit'] as String).trim();

    double? remaining = readNum(const [
      'remaining_qty',
      'remaining_quantity',
      'split_remaining_quantity',
      'overflow_quantity',
    ]);
    double? fitting = readNum(const [
      'fitting_qty',
      'fitting_quantity',
      'section_capacity',
      'split_section_capacity',
    ]);
    final unit = readUnit(const [
          'split_unit',
          'quantity_unit',
          'order_unit',
        ]) ??
        orderUnit;

    if ((remaining == null || remaining <= 0) &&
        (fitting == null || fitting <= 0)) {
      return null;
    }

    if ((remaining == null || remaining <= 0) &&
        fitting != null &&
        fitting > 0 &&
        orderQty > fitting) {
      remaining = orderQty - fitting;
    }

    if ((fitting == null || fitting <= 0) &&
        remaining != null &&
        remaining > 0 &&
        orderQty > remaining) {
      fitting = orderQty - remaining;
    }

    if (remaining == null || remaining <= 0 || fitting == null || fitting <= 0) {
      return null;
    }

    return {
      'fittingQty': fitting,
      'remainingQty': remaining,
      'unit': unit.isNotEmpty ? unit : orderUnit,
    };
  }

  // Vehicle capacity check modal – shown before confirming a direct driver selection
  void _showVehicleCapacityModal({
    required Map<String, dynamic> driver,
    required bool isDark,
    required double orderQty,
    required String orderUnit,
    required double vehicleCap,
    required String vehicleCapUnit,
    required bool orderFits,
    required double fillPercent,
    required double orderBase,
    required double vehicleBase,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final driverName =
      driver['name'] ??
      driver['username'] ??
      AppLocalizations.of(context)!.findDriver;
    int? sectionsCount = _driverIntByKeys(driver, const [
      'sections_count',
      'section_count',
      'number_of_sections',
      'cargo_sections',
      'wagon_sections',
      'compartment_count',
      'compartments',
    ]);
    int? freeSections = _driverIntByKeys(driver, const [
      'free_sections',
      'sections_free',
      'available_sections',
      'free_compartments',
      'available_compartments',
    ]);
    freeSections ??= _freeSectionsFromLayout(driver['vehicle_sections']);
    final sectionStates = _driverSectionStates(driver);
    sectionsCount ??= sectionStates.isNotEmpty ? sectionStates.length : null;
    freeSections ??= sectionStates.where((s) => s == true).length;
    final resolvedFreeSections = freeSections;
    final bool showSectionStatus = (sectionsCount ?? 0) > 1 || sectionStates.length > 1;
    final int occupiedSections = (sectionsCount ?? 0) > 0
      ? ((sectionsCount ?? 0) - resolvedFreeSections).clamp(0, (sectionsCount ?? 0))
      : 0;
    final int sectionChipCount = sectionsCount ?? sectionStates.length;
    final List<bool?> sectionFreeStates = List<bool?>.generate(
      sectionChipCount,
      (index) => index < sectionStates.length
          ? sectionStates[index]
          : (resolvedFreeSections > index),
    );
    final List<int> selectableSectionIndices = <int>[];
    for (int i = 0; i < sectionFreeStates.length; i++) {
      // Allow selection unless a section is explicitly occupied.
      if (sectionFreeStates[i] != false) selectableSectionIndices.add(i);
    }
    int? selectedSectionIndex =
        selectableSectionIndices.isNotEmpty ? selectableSectionIndices.first : null;
    final bool canChooseSection =
        showSectionStatus && selectableSectionIndices.isNotEmpty;

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      maxHeight: 520,
      child: StatefulBuilder(
        builder: (context, setSheetState) => SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: (orderFits ? Colors.green : Colors.orange).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    CupertinoIcons.cube_box,
                    size: 20,
                    color: orderFits ? TradeRepublicTheme.textColor(context) : const Color(0xFFFF9500),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.vehicleCapacityCheck,
                        style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : Colors.black,
                          letterSpacing: -0.3,
                        ),
                      ),
                      Text(
                        driverName.toString(),
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white54 : Colors.black45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Order vs Vehicle comparison cards
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF181818) : Colors.black.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        Icon(CupertinoIcons.cube_box, size: 24,
                            color: isDark ? Colors.white70 : Colors.black54),
                        const SizedBox(height: 6),
                        Text(AppLocalizations.of(context)!.orders, style: TextStyle(fontSize: 11,
                            color: isDark ? Colors.white54 : Colors.black45)),
                        const SizedBox(height: 2),
                        Text(_fmtQty(orderQty), style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : Colors.black)),
                        Text(orderUnit, style: TextStyle(fontSize: 12,
                            color: isDark ? Colors.white60 : Colors.black45)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF181818) : Colors.black.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        Icon(CupertinoIcons.car_detailed, size: 24,
                            color: isDark ? Colors.white70 : Colors.black54),
                        const SizedBox(height: 6),
                        Text(AppLocalizations.of(context)!.vehicle, style: TextStyle(fontSize: 11,
                            color: isDark ? Colors.white54 : Colors.black45)),
                        const SizedBox(height: 2),
                        Text(_fmtQty(vehicleCap), style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : Colors.black)),
                        Text(vehicleCapUnit, style: TextStyle(fontSize: 12,
                            color: isDark ? Colors.white60 : Colors.black45)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (showSectionStatus) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF181818) : Colors.black.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Section status',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Free: $resolvedFreeSections • Occupied: $occupiedSections',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(sectionsCount ?? sectionStates.length, (index) {
                        final bool? isFree = index < sectionFreeStates.length
                            ? sectionFreeStates[index]
                            : null;
                        final Color bg = isFree == true
                            ? TradeRepublicTheme.textColor(context).withOpacity(isDark ? 0.22 : 0.14)
                            : isFree == false
                                ? const Color(0xFFFF3B30).withOpacity(isDark ? 0.22 : 0.12)
                                : (isDark ? Colors.white10 : Colors.black12);
                        final Color fg = isFree == true
                            ? TradeRepublicTheme.textColor(context)
                            : isFree == false
                                ? const Color(0xFFFF3B30)
                                : (isDark ? Colors.white70 : Colors.black54);
                        final String label = isFree == true
                            ? 'free'
                            : isFree == false
                                ? 'occupied'
                                : 'unknown';

                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: bg,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'S${index + 1}: $label',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: fg,
                            ),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],
            if (canChooseSection) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF181818) : Colors.black.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Choose section for this order',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: selectableSectionIndices.map((idx) {
                        final bool active = selectedSectionIndex == idx;
                        return GestureDetector(
                          onTap: () => setSheetState(() => selectedSectionIndex = idx),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: active
                                  ? (isDark ? Colors.white : Colors.black)
                                  : (isDark ? const Color(0xFF181818) : const Color(0xFFF2F2F2)),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'S${idx + 1}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: active
                                    ? (isDark ? Colors.black : Colors.white)
                                    : (isDark ? Colors.white70 : Colors.black87),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],
            // CullyAI-style result banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: (orderFits ? Colors.green : Colors.red)
                    .withOpacity(isDark ? 0.15 : 0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        orderFits
                            ? CupertinoIcons.checkmark_circle_fill
                            : CupertinoIcons.exclamationmark_triangle_fill,
                        size: 18,
                        color: orderFits
                            ? TradeRepublicTheme.textColor(context)
                            : const Color(0xFFFF3B30),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          orderFits
                              ? l10n.orderFitsVehicle
                              : l10n.orderDoesntFitVehicle,
                          style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600,
                            color: orderFits ? Colors.green[700] : Colors.red[700],
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: (orderFits ? Colors.green : Colors.red).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${fillPercent.toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700,
                            color: orderFits ? Colors.green[700] : Colors.red[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Fill bar
                  LayoutBuilder(builder: (ctx, constraints) {
                    final barColor = orderFits
                        ? TradeRepublicTheme.textColor(context)
                        : const Color(0xFFFF3B30);
                    final filledWidth =
                        fillPercent.clamp(0.0, 100.0) / 100.0 * constraints.maxWidth;
                    return Container(
                      height: 5,
                      decoration: BoxDecoration(
                        color: (isDark ? Colors.white : Colors.black).withOpacity(0.08),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          width: filledWidth,
                          decoration: BoxDecoration(
                            color: barColor,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Action buttons
            if (orderFits) ...[  
              TradeRepublicButton(
                label: l10n.selectThisDriver,
                icon: const Icon(CupertinoIcons.checkmark_circle_fill,
                    color: Colors.white, size: 20),
                tint: TradeRepublicTheme.textColor(context),
                onPressed: () {
                  Navigator.pop(context);
                  _showRegularDriverConfirmation(
                    driver,
                    isDark,
                    selectedSectionIndex: selectedSectionIndex,
                  );
                },
                width: double.infinity,
              ),
            ] else ...[  
              TradeRepublicButton(
                label: l10n.splitReleaseRemainder,
                icon: const Icon(CupertinoIcons.arrow_branch,
                    color: Colors.white, size: 20),
                tint: const Color(0xFFFF9500),
                onPressed: () {
                  Navigator.pop(context);
                  final fittingFraction = vehicleBase > 0
                      ? (vehicleBase / orderBase).clamp(0.0, 1.0)
                      : 0.0;
                  final fittingQty = orderQty * fittingFraction;
                  final remainingQty = orderQty - fittingQty;
                  _showDriverSplitModal(
                    driver: driver,
                    isDark: isDark,
                    fittingQty: fittingQty,
                    remainingQty: remainingQty,
                    unit: orderUnit,
                  );
                },
                width: double.infinity,
              ),
              const SizedBox(height: 10),
              TradeRepublicButton(
                label: l10n.proceedAnyway,
                isSecondary: true,
                onPressed: () {
                  Navigator.pop(context);
                  _showRegularDriverConfirmation(
                    driver,
                    isDark,
                    selectedSectionIndex: selectedSectionIndex,
                  );
                },
                width: double.infinity,
              ),
            ],
          ],
        ),
          ),
        ),
      ),
    );
  }

  // Split order modal – shows split diagram and confirms with split API call
  void _showDriverSplitModal({
    required Map<String, dynamic> driver,
    required bool isDark,
    required double fittingQty,
    required double remainingQty,
    required String unit,
    int? selectedSectionIndex,
    /// When provided, this callback replaces the default _selectDriverDirectlyWithSplit
    /// action. Used by the auction-bid-accept flow.
    Future<void> Function(double fitting, double remaining, String unit)? onSplitConfirmed,
  }) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final driverName =
      driver['name'] ??
      driver['username'] ??
      AppLocalizations.of(context)!.findDriver;

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      maxHeight: 580,
      child: Builder(
        builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFFFF9500), Color(0xFFFF6B00)]),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(CupertinoIcons.arrow_branch,
                      size: 22, color: Colors.white),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.splitOrder,
                        style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : Colors.black,
                          letterSpacing: -0.3,
                        ),
                      ),
                      Text(
                        driverName.toString(),
                        style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white54 : Colors.black45),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Split diagram: driver side | arrow | auction side
            Row(
              children: [
                // Driver portion
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: TradeRepublicTheme.fillColor(
                        context,
                        opacity: isDark ? 0.12 : 0.07,
                      ),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            color: TradeRepublicTheme.fillColor(
                              context,
                              opacity: 0.12,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            CupertinoIcons.car_detailed,
                            size: 20,
                            color: TradeRepublicTheme.textColor(context),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(AppLocalizations.of(context)!.driver,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: (isDark ? Colors.white : Colors.black)
                                    .withOpacity(0.5))),
                        const SizedBox(height: 4),
                        Text(_fmtQty(fittingQty),
                            style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: TradeRepublicTheme.textColor(context),
                            )),
                        Text(unit,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: (isDark ? Colors.white : Colors.black)
                                    .withOpacity(0.6))),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(CupertinoIcons.arrow_right, size: 20,
                    color: (isDark ? Colors.white : Colors.black).withOpacity(0.25)),
                const SizedBox(width: 8),
                // Remainder / auction portion
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: TradeRepublicTheme.textColor(context)
                          .withOpacity(isDark ? 0.14 : 0.07),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            color: TradeRepublicTheme.textColor(context).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            CupertinoIcons.arrow_up_circle,
                            size: 20,
                            color: TradeRepublicTheme.textColor(context),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(AppLocalizations.of(context)!.driverAuction,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: (isDark ? Colors.white : Colors.black)
                                    .withOpacity(0.5))),
                        const SizedBox(height: 4),
                        Text(_fmtQty(remainingQty),
                            style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: TradeRepublicTheme.textColor(context),
                            )),
                        Text(unit,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: (isDark ? Colors.white : Colors.black)
                                    .withOpacity(0.6))),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Info note
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: (isDark ? Colors.white : Colors.black).withOpacity(0.04),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(CupertinoIcons.info_circle,
                      size: 16,
                      color: (isDark ? Colors.white : Colors.black).withOpacity(0.4)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n.capacityRemainingPool(
                          _fmtQty(remainingQty), unit),
                      style: TextStyle(
                          fontSize: 12,
                          color: (isDark ? Colors.white : Colors.black)
                              .withOpacity(0.5)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Confirm split
            TradeRepublicButton(
              label: l10n.splitReleaseRemainder,
              icon: const Icon(CupertinoIcons.checkmark_circle_fill,
                  color: Colors.white, size: 20),
              tint: const Color(0xFFFF9500),
              isLoading: _isSelectingDriver,
              onPressed: _isSelectingDriver
                  ? null
                  : () async {
                      Navigator.of(sheetContext).pop();
                      if (!mounted) return;
                      if (onSplitConfirmed != null) {
                        await onSplitConfirmed(fittingQty, remainingQty, unit);
                      } else {
                        await _selectDriverDirectlyWithSplit(
                          driver: driver,
                          splitRemainingQuantity: remainingQty,
                          splitSectionCapacity: fittingQty,
                          splitUnit: unit,
                          selectedSectionIndex: selectedSectionIndex,
                        );
                      }
                    },
              width: double.infinity,
            ),
            const SizedBox(height: 10),
            TradeRepublicButton(
              label: l10n.cancel,
              isSecondary: true,
              onPressed: () => Navigator.of(sheetContext).pop(),
              width: double.infinity,
            ),
          ],
        ),
      ),
      ),
    );
  }

  // Select driver with split – creates a remainder order back in auction
  Future<void> _selectDriverDirectlyWithSplit({
    required Map<String, dynamic> driver,
    required double splitRemainingQuantity,
    required double splitSectionCapacity,
    required String splitUnit,
    int? selectedSectionIndex,
  }) async {
    final parsedId = driver['id'] is int
        ? driver['id'] as int
        : int.tryParse(driver['id']?.toString() ?? '');
    if (parsedId == null || parsedId <= 0) {
      TopNotification.error(
        context,
        'Invalid driver id — please refresh the driver list and try again.',
      );
      return;
    }
    final driverId = parsedId;

    final double shippingAmount = _parseNumericValue(
        driver['estimated_price'] ?? driver['price'] ?? driver['bid_amount']);

    setState(() => _isSelectingDriver = true);
    try {
      final orderId = _currentOrder['id'];
      dynamic remainderOrderId;

      final currentAuction =
          _auction is Map<String, dynamic> ? _auction as Map<String, dynamic> : null;
      final dynamic rawAuctionId = currentAuction == null ? null : currentAuction['id'];
      final int? auctionId = rawAuctionId is int
          ? rawAuctionId
          : int.tryParse(rawAuctionId?.toString() ?? '');
      if (auctionId != null &&
          auctionId > 0 &&
          splitRemainingQuantity > 0 &&
          splitSectionCapacity > 0 &&
          splitUnit.trim().isNotEmpty) {
        final splitResult = await ApiService.splitAuctionOrder(
          auctionId: auctionId,
          sectionIndex: selectedSectionIndex ?? 0,
          sectionCapacity: splitSectionCapacity,
          overflowQuantity: splitRemainingQuantity,
          splitUnit: splitUnit,
        );
        if (splitResult['success'] != true) {
          if (mounted) {
            TopNotification.error(
              context,
              splitResult['message']?.toString() ?? 'Split order failed',
            );
          }
          return;
        }
        final splitData = splitResult['split'] as Map<String, dynamic>?;
        remainderOrderId =
            splitData?['overflow_order_id'] ?? splitResult['remainder_order_id'];
      }

      final response = await ApiService.selectDriverDirectly(
        orderId,
        driverId,
        splitRemainingQuantity: splitRemainingQuantity,
        splitUnit: splitUnit,
        shippingAmount: shippingAmount > 0 ? shippingAmount : null,
        selectedSectionIndex: selectedSectionIndex,
      );
      if (response['success'] == true && mounted) {
        final autoCharge = response['auto_charge'] as Map<String, dynamic>?;
        final splitInfo = response['split'] as Map<String, dynamic>?;
        remainderOrderId ??=
            splitInfo?['order_id'] ?? response['remainder_order_id'];

        setState(() {
          _currentOrder['driver_id'] = driverId;
          _currentOrder['driver_username'] =
              driver['username'] ?? driver['name'];
          _currentOrder['auction_status'] = 'direct_assigned';
          _currentOrder['delvioo'] = 1;
          _driverPendingConfirmation = true;
        });

        // Fetch the new remainder order so we can open it
        Map<String, dynamic>? remainderOrder;
        if (remainderOrderId != null) {
          try {
            final fetchResult = await ApiService.getOrder(
              remainderOrderId is int
                  ? remainderOrderId
                  : int.parse(remainderOrderId.toString()),
            );
            if (fetchResult['success'] == true && fetchResult['order'] != null) {
              remainderOrder = Map<String, dynamic>.from(fetchResult['order'] as Map);
            } else if (fetchResult['id'] != null) {
              remainderOrder = Map<String, dynamic>.from(fetchResult as Map);
            }
          } catch (_) {}
        }

        widget.onOrderUpdated?.call();

        if (!mounted) return;

        // ── Show "Neue Bestellung erstellt" sheet ──────────────────────
        final isDark = Theme.of(context).brightness == Brightness.dark;
        await _showRemainderOrderSheet(
          isDark: isDark,
          remainderOrderId: remainderOrderId,
          remainderOrder: remainderOrder,
          remainingQty: splitRemainingQuantity,
          unit: splitUnit,
          autoCharge: autoCharge,
        );
      } else {
        TopNotification.error(
            context, response['message'] ?? 'Error');
      }
    } catch (e) {
      print('❌ Error selecting driver with split: $e');
      TopNotification.error(context, e.toString());
    } finally {
      if (mounted) setState(() => _isSelectingDriver = false);
    }
  }

  // Shows a sheet after split to let the user open the new remainder order
  Future<void> _showRemainderOrderSheet({
    required bool isDark,
    required dynamic remainderOrderId,
    required Map<String, dynamic>? remainderOrder,
    required double remainingQty,
    required String unit,
    required Map<String, dynamic>? autoCharge,
  }) async {
    await TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      maxHeight: 520,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header icon
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFFFF9500), Color(0xFFFF6B00)]),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Icon(CupertinoIcons.scissors, color: Colors.white, size: 30),
            ),
            const SizedBox(height: 16),
            Text(
              'Split successful!',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : Colors.black,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 6),
            if (autoCharge != null && autoCharge['paid'] == true) ...[
              Text(
                '${_formatCurrency(autoCharge['amount'])} charged via '
                '${autoCharge['method'] == 'wallet' ? 'Monioo Balance' : '**** ${autoCharge['last4'] ?? ''}'}',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: TradeRepublicTheme.textColor(context)),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              '⏳ Awaiting driver confirmation\nThe remaining quantity (${_fmtQty(remainingQty)} $unit) '
              'was created as a new order.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white60 : Colors.black54,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            // Remainder order info card
            Container(
              width: double.infinity,
              padding: _kSheetTilePadding,
              decoration: BoxDecoration(
                color: TradeRepublicTheme.textColor(context).withOpacity(isDark ? 0.13 : 0.07),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: TradeRepublicTheme.textColor(context).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      CupertinoIcons.doc_text,
                      color: TradeRepublicTheme.textColor(context),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          remainderOrder != null
                              ? 'New order #${_displayOrderNumberFor(remainderOrder)}'
                              : (remainderOrderId != null
                                  ? 'New order #$remainderOrderId'
                                  : 'New order created'),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_fmtQty(remainingQty)} $unit · Ready for auction or direct driver',
                          style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black45),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Open remainder order button
            if (remainderOrder != null)
              TradeRepublicButton(
                label: AppLocalizations.of(context)!.openNewOrderFindDriver,
                icon: const Icon(CupertinoIcons.arrow_right_circle_fill, color: Colors.white, size: 20),
                tint: TradeRepublicTheme.textColor(context),
                width: double.infinity,
                onPressed: () {
                  Navigator.pop(context); // close this sheet
                  // Open the remainder order in a new OrderDetailsModal
                  TradeRepublicBottomSheet.show(
                    context: context,
                    showDragHandle: true,
                    useRootNavigator: true,
                    maxHeight: MediaQuery.of(context).size.height * 0.85,
                    child: OrderDetailsModal(
                      order: remainderOrder,
                      numberFormat: widget.numberFormat,
                      onOrderUpdated: widget.onOrderUpdated,
                    ),
                  );
                },
              ),
            if (remainderOrder == null && remainderOrderId != null) ...[
              TradeRepublicButton(
                label: 'Open order #$remainderOrderId',
                icon: const Icon(CupertinoIcons.arrow_right_circle_fill, color: Colors.white, size: 20),
                tint: TradeRepublicTheme.textColor(context),
                width: double.infinity,
                onPressed: () async {
                  Navigator.pop(context);
                  try {
                    final fetchResult = await ApiService.getOrder(
                      remainderOrderId is int
                          ? remainderOrderId
                          : int.parse(remainderOrderId.toString()),
                    );
                    if (!mounted) return;
                    final ord = (fetchResult['order'] ?? fetchResult) as Map<String, dynamic>;
                    TradeRepublicBottomSheet.show(
                      context: context,
                      showDragHandle: true,
                      useRootNavigator: true,
                      maxHeight: MediaQuery.of(context).size.height * 0.85,
                      child: OrderDetailsModal(
                        order: Map<String, dynamic>.from(ord),
                        numberFormat: widget.numberFormat,
                        onOrderUpdated: widget.onOrderUpdated,
                      ),
                    );
                  } catch (_) {}
                },
              ),
            ],
            const SizedBox(height: 10),
            TradeRepublicButton(
              label: 'Close',
              isSecondary: true,
              width: double.infinity,
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  // Manual split order flow - shown when user clicks the + button
  void _showManualSplitFlow(BuildContext context, bool isDark) {
    final orderInfo = _getOrderTotalQuantityAndUnit();
    final double totalQty = orderInfo['quantity'] as double;
    final String unit = orderInfo['unit'] as String;

    if (totalQty <= 0) {
      TopNotification.error(context, 'Cannot split order: no quantity available');
      return;
    }

    final TextEditingController qtyController = TextEditingController();
    bool isLoading = false;
    int selectedSplitIndex = -1;

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      maxHeight: 520,
      child: StatefulBuilder(
        builder: (sheetCtx, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF9500), Color(0xFFFF6B00)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      CupertinoIcons.arrow_branch,
                      size: 22,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLocalizations.of(context)!.splitOrder,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : Colors.black,
                            letterSpacing: -0.3,
                          ),
                        ),
                        Text(
                          'Split order #${_currentOrder['id']}',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white54 : Colors.black45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Current order info
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: TradeRepublicTheme.fillColor(context, opacity: isDark ? 0.12 : 0.07),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Current order quantity',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white54 : Colors.black45,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_fmtQty(totalQty)} $unit',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Input for split quantity
              Text(
                'Quantity for first order',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
              const SizedBox(height: 8),
              TradeRepublicTextField(
                controller: qtyController,
                hintText: 'Enter quantity (e.g. ${_fmtQty(totalQty / 2)})',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                prefixIcon: Icon(
                  CupertinoIcons.arrow_right_circle,
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
              ),
              const SizedBox(height: 12),

              // Quick split buttons
              Row(
                children: [
                  Expanded(
                    child: _buildQuickSplitButton(
                      label: '50/50',
                      isSelected: selectedSplitIndex == 0,
                      onTap: () {
                        setSheetState(() => selectedSplitIndex = 0);
                        qtyController.text = _fmtQty(totalQty / 2);
                      },
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildQuickSplitButton(
                      label: '1/3 · 2/3',
                      isSelected: selectedSplitIndex == 1,
                      onTap: () {
                        setSheetState(() => selectedSplitIndex = 1);
                        qtyController.text = _fmtQty(totalQty / 3);
                      },
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildQuickSplitButton(
                      label: '2/3 · 1/3',
                      isSelected: selectedSplitIndex == 2,
                      onTap: () {
                        setSheetState(() => selectedSplitIndex = 2);
                        qtyController.text = _fmtQty(totalQty * 2 / 3);
                      },
                      isDark: isDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Info note
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9500).withOpacity(isDark ? 0.15 : 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      CupertinoIcons.info_circle,
                      size: 16,
                      color: const Color(0xFFFF9500),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'The remaining quantity will be created as a new order with the same delivery address.',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Confirm split button
              TradeRepublicButton(
                label: 'Create Split Order',
                icon: const Icon(CupertinoIcons.checkmark_circle_fill, color: Colors.white, size: 20),
                tint: const Color(0xFFFF9500),
                isLoading: isLoading,
                onPressed: isLoading
                    ? null
                    : () async {
                        final inputQty = double.tryParse(qtyController.text.replaceAll(',', '.'));
                        if (inputQty == null || inputQty <= 0 || inputQty >= totalQty) {
                          TopNotification.error(
                            context,
                            'Please enter a valid quantity between 0 and ${_fmtQty(totalQty)} $unit',
                          );
                          return;
                        }

                        setSheetState(() => isLoading = true);

                        final overflowQty = totalQty - inputQty;
                        await _executeManualSplit(
                          context: sheetCtx,
                          isDark: isDark,
                          fittingQty: inputQty,
                          remainingQty: overflowQty,
                          unit: unit,
                        );
                      },
                width: double.infinity,
              ),
              const SizedBox(height: 10),
              TradeRepublicButton(
                label: 'Cancel',
                isSecondary: true,
                onPressed: () => Navigator.of(sheetCtx).pop(),
                width: double.infinity,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickSplitButton({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    final bgColor = isSelected
        ? (isDark ? Colors.white.withOpacity(0.2) : Colors.black.withOpacity(0.12))
        : TradeRepublicTheme.fillColor(context, opacity: isDark ? 0.12 : 0.07);
    final textColor = isSelected
        ? (isDark ? Colors.white : Colors.black)
        : (isDark ? Colors.white70 : Colors.black54);

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }

  // Execute the manual split by calling the backend API
  Future<void> _executeManualSplit({
    required BuildContext context,
    required bool isDark,
    required double fittingQty,
    required double remainingQty,
    required String unit,
  }) async {
    try {
      final orderId = _currentOrder['id'];

      // First create an auction for this order if not exists
      final auctionResp = await ApiService.startDriverAuction(orderId);
      if (auctionResp['success'] != true && auctionResp['auction'] == null) {
        if (mounted) {
          TopNotification.error(
            context,
            auctionResp['message'] ?? 'Could not start auction for split',
          );
        }
        return;
      }

      final auctionId = auctionResp['auction']?['id'] ?? auctionResp['auction_id'];
      if (auctionId == null) {
        if (mounted) {
          TopNotification.error(context, 'No auction available for split');
        }
        return;
      }

      // Call the split API
      final splitResp = await ApiService.splitAuctionOrder(
        auctionId: auctionId is int ? auctionId : int.parse(auctionId.toString()),
        sectionIndex: 0,
        sectionCapacity: fittingQty,
        overflowQuantity: remainingQty,
        splitUnit: unit,
      );

      if (splitResp['success'] != true) {
        if (mounted) {
          TopNotification.error(
            context,
            splitResp['error']?.toString() ??
                splitResp['message']?.toString() ??
                'Split failed',
          );
        }
        return;
      }

      final splitData = splitResp['split'] ?? splitResp;
      final overflowOrderFromResp = splitResp['overflow_order'];
      final overflowOrderId = splitData['overflow_order_id'] ??
          splitData['remainder_order_id'] ??
          overflowOrderFromResp?['id'];

      // Fetch the new remainder order or use response data as fallback
      Map<String, dynamic>? remainderOrder;
      if (overflowOrderId != null) {
        try {
          final fetchResult = await ApiService.getOrder(
            overflowOrderId is int ? overflowOrderId : int.parse(overflowOrderId.toString()),
          );
          if (fetchResult['success'] == true && fetchResult['order'] != null) {
            remainderOrder = Map<String, dynamic>.from(fetchResult['order'] as Map);
          } else if (fetchResult['id'] != null) {
            remainderOrder = Map<String, dynamic>.from(fetchResult as Map);
          }
        } catch (_) {}
      }
      // Fallback to overflow_order from split response if fetch failed
      remainderOrder ??= overflowOrderFromResp != null
          ? Map<String, dynamic>.from(overflowOrderFromResp as Map)
          : null;

      widget.onOrderUpdated?.call();

      if (!mounted) return;

      // Close the split dialog and show success
      Navigator.pop(context);

      await _showRemainderOrderSheet(
        isDark: isDark,
        remainderOrderId: overflowOrderId,
        remainderOrder: remainderOrder,
        remainingQty: remainingQty,
        unit: unit,
        autoCharge: null,
      );
    } catch (e) {
      print('❌ Error executing manual split: $e');
      if (mounted) {
        TopNotification.error(context, 'Split failed: $e');
      }
    }
  }

  Widget _buildDelviooStyleDot({
    required List<Color> gradientColors,
    required Color glowColor,
    required double size,
    double blur = 8,
    double spread = 2,
    bool selected = false,
    bool showGlow = true,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gradientColors),
        shape: BoxShape.circle,
        boxShadow: showGlow
            ? [
                BoxShadow(
                  color: glowColor.withOpacity(selected ? 0.55 : 0.4),
                  blurRadius: selected ? (blur + 4) : blur,
                  spreadRadius: selected ? (spread + 1) : spread,
                ),
              ]
            : [],
      ),
    );
  }

  Widget _buildModernMyLocationMarker({double size = 16}) {
    return _buildDelviooStyleDot(
      gradientColors: const [Color(0xFF6E6E6E), Color(0xFF2C2C2C)],
      glowColor: const Color(0xFF4A4A4A),
      size: size,
      showGlow: false,
    );
  }

  Widget _buildModernTruckMarker({
    required bool isDark,
    required bool isOccupied,
    bool isSelected = false,
    double size = 46,
  }) {
    // Same circle style as Delvioo Maps, color-coded by availability.
    final List<Color> gradient = isOccupied
        ? const [Color(0xFFFF3B30), Color(0xFFD62919)]
        : const [Color(0xFF5C5C5C), Color(0xFF2A2A2A)];
    final Color glow = isOccupied
        ? const Color(0xFFFF3B30)
        : const Color(0xFF4A4A4A);
    final double dotSize = isSelected ? 18 : 16;

    return SizedBox(
      width: dotSize + 10,
      height: dotSize + 10,
      child: Center(
        child: _buildDelviooStyleDot(
          gradientColors: gradient,
          glowColor: glow,
          size: dotSize,
          blur: 8,
          spread: 1.6,
          selected: isSelected,
        ),
      ),
    );
  }

  Widget _buildPickupTriangleMarker({double size = 22}) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GradientPickupTrianglePainter(),
      ),
    );
  }

  Widget _buildDeliveryRectangleMarker({double width = 18, double height = 14}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6E6E6E), Color(0xFF2C2C2C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(3),
        boxShadow: [
          BoxShadow(
            color: Color(0xFF000000).withValues(alpha: 0.35),
            blurRadius: 6,
            spreadRadius: 0.8,
          ),
        ],
      ),
    );
  }

  double? _parseCoordinate(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) {
      final normalized = value.trim().replaceAll(',', '.');
      return double.tryParse(normalized);
    }
    return null;
  }

  bool _isValidCoordinatePair(double? lat, double? lng) {
    if (lat == null || lng == null) return false;
    if (lat == 0 && lng == 0) return false;
    return lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;
  }

  bool _isSameCoordinatePair(double? lat1, double? lng1, double? lat2, double? lng2) {
    if (!_isValidCoordinatePair(lat1, lng1) || !_isValidCoordinatePair(lat2, lng2)) {
      return false;
    }
    const eps = 0.0001; // ~11m
    return (lat1! - lat2!).abs() < eps && (lng1! - lng2!).abs() < eps;
  }

  LatLng? _resolveDriverCoordinates() {
    final sources = <Map<String, dynamic>>[
      _currentOrder,
      widget.order,
    ];
    for (final src in sources) {
      final lat = _parseCoordinate(
        src['driver_latitude'] ??
            src['driver_lat'] ??
            src['latitude'] ??
            src['lat'],
      );
      final lng = _parseCoordinate(
        src['driver_longitude'] ??
            src['driver_lng'] ??
            src['driver_lon'] ??
            src['longitude'] ??
            src['lng'] ??
            src['lon'],
      );
      if (_isValidCoordinatePair(lat, lng)) {
        return LatLng(lat!, lng!);
      }
    }
    return null;
  }

  LatLng _resolveDeliveryCoordinates() {
    const fallback = LatLng(51.1657, 10.4515);

    double? lat = _parseCoordinate(
      _currentOrder['delivery_latitude'] ??
          _currentOrder['delivery_lat'] ??
          _currentOrder['address_latitude'] ??
          _currentOrder['address_lat'] ??
          _currentOrder['buyer_latitude'] ??
          _currentOrder['buyer_lat'] ??
          _currentOrder['shipping_latitude'] ??
          _currentOrder['shipping_lat'],
    );
    double? lng = _parseCoordinate(
      _currentOrder['delivery_longitude'] ??
          _currentOrder['delivery_lng'] ??
          _currentOrder['address_longitude'] ??
          _currentOrder['address_lng'] ??
          _currentOrder['buyer_longitude'] ??
          _currentOrder['buyer_lng'] ??
          _currentOrder['shipping_longitude'] ??
          _currentOrder['shipping_lng'],
    );

    final address = _resolveDeliveryAddressMap();

    lat ??= _parseCoordinate(
      address['delivery_latitude'] ??
          address['delivery_lat'] ??
          address['address_latitude'] ??
          address['address_lat'] ??
          address['buyer_latitude'] ??
          address['buyer_lat'] ??
          address['shipping_latitude'] ??
          address['shipping_lat'] ??
          address['latitude'] ??
          address['lat'],
    );
    lng ??= _parseCoordinate(
      address['delivery_longitude'] ??
          address['delivery_lng'] ??
          address['address_longitude'] ??
          address['address_lng'] ??
          address['buyer_longitude'] ??
          address['buyer_lng'] ??
          address['shipping_longitude'] ??
          address['shipping_lng'] ??
          address['longitude'] ??
          address['lng'] ??
          address['lon'],
    );

    final location = address['location'];
    if (location is Map) {
      lat ??= _parseCoordinate(location['lat'] ?? location['latitude']);
      lng ??= _parseCoordinate(
        location['lng'] ?? location['longitude'] ?? location['lon'],
      );
    }

    if (!_isValidCoordinatePair(lat, lng)) {
      final driver = _resolveDriverCoordinates();
      if (driver != null &&
          _isValidCoordinatePair(driver.latitude, driver.longitude)) {
        return driver;
      }
    }

    if (!_isValidCoordinatePair(lat, lng)) {
      return fallback;
    }

    return LatLng(lat!, lng!);
  }

  LatLng _resolvePickupCoordinates() {
    const fallback = LatLng(52.520008, 13.404954);

    double? lat = _parseCoordinate(
      _currentOrder['pickup_latitude'] ??
          _currentOrder['pickup_lat'] ??
          _currentOrder['origin_latitude'] ??
          _currentOrder['origin_lat'] ??
          _currentOrder['seller_latitude'] ??
          _currentOrder['seller_lat'] ??
          _currentOrder['location_latitude'] ??
          _currentOrder['location_lat'],
    );
    double? lng = _parseCoordinate(
      _currentOrder['pickup_longitude'] ??
          _currentOrder['pickup_lng'] ??
          _currentOrder['pickup_lon'] ??
          _currentOrder['origin_longitude'] ??
          _currentOrder['origin_lng'] ??
          _currentOrder['origin_lon'] ??
          _currentOrder['seller_longitude'] ??
          _currentOrder['seller_lng'] ??
          _currentOrder['seller_lon'] ??
          _currentOrder['location_longitude'] ??
          _currentOrder['location_lng'] ??
          _currentOrder['location_lon'],
    );

    final addressRaw = _currentOrder['address'];
    Map<String, dynamic>? address;
    if (addressRaw is Map<String, dynamic>) {
      address = addressRaw;
    } else if (addressRaw is String && addressRaw.trim().isNotEmpty) {
      try {
        final parsed = json.decode(addressRaw);
        if (parsed is Map<String, dynamic>) {
          address = parsed;
        }
      } catch (_) {}
    }

    if (address != null) {
      lat ??= _parseCoordinate(
        address['pickup_latitude'] ??
            address['pickup_lat'] ??
            address['origin_latitude'] ??
            address['origin_lat'] ??
            address['seller_latitude'] ??
            address['seller_lat'] ??
            address['location_latitude'] ??
            address['location_lat'] ??
            address['latitude'] ??
            address['lat'],
      );
      lng ??= _parseCoordinate(
        address['pickup_longitude'] ??
            address['pickup_lng'] ??
            address['pickup_lon'] ??
            address['origin_longitude'] ??
            address['origin_lng'] ??
            address['origin_lon'] ??
            address['seller_longitude'] ??
            address['seller_lng'] ??
            address['seller_lon'] ??
            address['location_longitude'] ??
            address['location_lng'] ??
            address['location_lon'] ??
            address['longitude'] ??
            address['lng'] ??
            address['lon'],
      );

      final location = address['location'];
      if (location is Map) {
        lat ??= _parseCoordinate(location['lat'] ?? location['latitude']);
        lng ??= _parseCoordinate(
          location['lng'] ?? location['longitude'] ?? location['lon'],
        );
      }
    }

    List<dynamic> orderItems = const [];
    final itemsRaw = _currentOrder['items'];
    if (itemsRaw is List) {
      orderItems = itemsRaw;
    }
    dynamic cartRaw = _currentOrder['cart'];
    if (cartRaw is String && cartRaw.trim().isNotEmpty) {
      try {
        cartRaw = json.decode(cartRaw);
      } catch (_) {}
    }
    if (cartRaw is List) {
      orderItems = [...orderItems, ...cartRaw];
    } else if (cartRaw is Map) {
      final nestedItems = cartRaw['items'];
      if (nestedItems is List) {
        orderItems = [...orderItems, ...nestedItems];
      }
    }

    if (!_isValidCoordinatePair(lat, lng) && orderItems.isNotEmpty) {
      for (final item in orderItems) {
        if (item is! Map) continue;
        final data = Map<String, dynamic>.from(item);
        final itemLat = _parseCoordinate(
          data['pickup_latitude'] ??
              data['pickup_lat'] ??
              data['product_latitude'] ??
              data['product_lat'],
        );
        final itemLng = _parseCoordinate(
          data['pickup_longitude'] ??
              data['pickup_lng'] ??
              data['pickup_lon'] ??
              data['product_longitude'] ??
              data['product_lng'] ??
              data['product_lon'],
        );
        if (_isValidCoordinatePair(itemLat, itemLng)) {
          lat = itemLat;
          lng = itemLng;
          break;
        }
      }
    }

    final delivery = _resolveDeliveryCoordinates();
    if (_isSameCoordinatePair(lat, lng, delivery.latitude, delivery.longitude)) {
      lat = null;
      lng = null;
    }

    if (!_isValidCoordinatePair(lat, lng)) {
      return fallback;
    }

    return LatLng(lat!, lng!);
  }

  int? _extractOrderAddressId() {
    final raw = _currentOrder['address'];
    if (raw is Map) {
      final id = int.tryParse('${raw['id'] ?? ''}');
      if (id != null && id > 0) return id;
    }
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final parsed = json.decode(raw);
        if (parsed is Map) {
          final id = int.tryParse('${parsed['id'] ?? ''}');
          if (id != null && id > 0) return id;
        }
      } catch (_) {}
    }
    return null;
  }

  Future<LatLng?> _resolveDeliveryFromUserAddresses() async {
    try {
      final addresses = await ApiService.getUserAddresses();
      if (addresses.isEmpty) return null;

      final targetAddressId = _extractOrderAddressId();
      Map<String, dynamic>? chosen;
      if (targetAddressId != null) {
        for (final addr in addresses) {
          final aid = int.tryParse('${addr['id'] ?? ''}');
          if (aid == targetAddressId) {
            chosen = addr;
            break;
          }
        }
      }

      chosen ??= addresses.firstWhere(
        (a) =>
            a['isSelected'] == true ||
            a['is_selected'] == true ||
            a['is_selected'] == 1 ||
            '${a['is_selected']}'.toLowerCase() == 'true',
        orElse: () => addresses.first,
      );

      final lat = _parseCoordinate(
        chosen['delivery_latitude'] ??
            chosen['delivery_lat'] ??
            chosen['address_latitude'] ??
            chosen['address_lat'] ??
            chosen['lat'] ??
            chosen['latitude'],
      );
      final lng = _parseCoordinate(
        chosen['delivery_longitude'] ??
            chosen['delivery_lng'] ??
            chosen['delivery_lon'] ??
            chosen['address_longitude'] ??
            chosen['address_lng'] ??
            chosen['address_lon'] ??
            chosen['lng'] ??
            chosen['lon'] ??
            chosen['longitude'],
      );
      if (_isValidCoordinatePair(lat, lng)) return LatLng(lat!, lng!);
    } catch (_) {}
    return null;
  }

  Future<LatLng?> _geocodeDeliveryCoordinates() async {
    try {
      final addr = _resolveDeliveryAddressMap();
      String pick(List<dynamic> vals) {
        for (final v in vals) {
          final s = (v ?? '').toString().trim();
          if (s.isNotEmpty && s.toLowerCase() != 'null') return s;
        }
        return '';
      }

      final street = pick([addr['street'], addr['address_line1'], addr['line1']]);
      final house = pick([addr['house_number'], addr['houseNo']]);
      final zip = pick([addr['postal_code'], addr['zip_code'], addr['zipCode'], addr['zip']]);
      final city = pick([addr['city'], addr['town']]);
      final country = pick([addr['country']]);
      final fallback = pick([addr['address'], addr['full_address']]);

      Future<LatLng?> tryUri(Uri uri) async {
        final response = await http.get(
          uri,
          headers: const {
            'Accept': 'application/json',
            'User-Agent': 'CultiooApp/1.0',
          },
        ).timeout(const Duration(seconds: 15));
        if (response.statusCode < 200 || response.statusCode >= 300) return null;
        final data = json.decode(response.body);
        if (data is! List || data.isEmpty) return null;
        final first = data.first;
        if (first is! Map) return null;
        final lat = _parseCoordinate(first['lat']);
        final lng = _parseCoordinate(first['lon']);
        if (_isValidCoordinatePair(lat, lng)) return LatLng(lat!, lng!);
        return null;
      }

      final structuredParams = <String, String>{
        'format': 'json',
        'limit': '1',
        'addressdetails': '1',
      };
      if (street.isNotEmpty || house.isNotEmpty) structuredParams['street'] = '$street $house'.trim();
      if (zip.isNotEmpty) structuredParams['postalcode'] = zip;
      if (city.isNotEmpty) structuredParams['city'] = city;
      if (country.isNotEmpty) structuredParams['country'] = country;
      if (structuredParams.length > 3) {
        final structuredUri = Uri.https('nominatim.openstreetmap.org', '/search', structuredParams);
        final structured = await tryUri(structuredUri);
        if (structured != null) return structured;
      }

      final q = [street, house, zip, city, country].where((s) => s.isNotEmpty).join(', ').trim();
      final query = q.isNotEmpty ? q : fallback;
      if (query.isEmpty) return null;
      final freeUri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'format': 'json',
        'limit': '1',
        'q': query,
      });
      return await tryUri(freeUri);
    } catch (_) {}
    return null;
  }

  Future<LatLng> _resolveDeliveryCoordinatesForMap() async {
    final fromUserAddresses = await _resolveDeliveryFromUserAddresses();
    if (fromUserAddresses != null) return fromUserAddresses;

    final fromOrder = _resolveDeliveryCoordinates();
    // Ignore generic Germany fallback when we can geocode a real address.
    if (_isValidCoordinatePair(fromOrder.latitude, fromOrder.longitude) &&
        !(fromOrder.latitude == 51.1657 && fromOrder.longitude == 10.4515)) {
      return fromOrder;
    }

    final geocoded = await _geocodeDeliveryCoordinates();
    if (geocoded != null) return geocoded;
    return fromOrder;
  }

  LatLng? _driverCoordinates(Map<String, dynamic> driver) {
    final location = driver['location'];
    final lat = _parseCoordinate(
      driver['latitude'] ??
          driver['lat'] ??
          driver['current_latitude'] ??
          driver['currentLatitude'] ??
          (location is Map ? (location['lat'] ?? location['latitude']) : null),
    );
    final lng = _parseCoordinate(
      driver['longitude'] ??
          driver['lng'] ??
          driver['lon'] ??
          driver['current_longitude'] ??
          driver['currentLongitude'] ??
          (location is Map
              ? (location['lng'] ?? location['longitude'] ?? location['lon'])
              : null),
    );

    if (!_isValidCoordinatePair(lat, lng)) return null;
    return LatLng(lat!, lng!);
  }

  String _driverDisplayName(Map<String, dynamic> driver) {
    final username = driver['username']?.toString().trim() ?? '';
    if (username.isNotEmpty) return '@$username';
    return (driver['name'] ?? AppLocalizations.of(context)!.findDriver)
        .toString();
  }

  double? _driverDistanceToPickupKm(Map<String, dynamic> driver) {
    final km = _driverDoubleByKeys(driver, const [
      'distance_to_pickup_km',
      'driver_to_pickup_km',
      'distance_driver_to_pickup_km',
    ]);
    if (km != null && km > 0) return km;
    final miles = _driverDoubleByKeys(driver, const [
      'distance_to_pickup_miles',
      'driver_to_pickup_miles',
      'distance_driver_to_pickup_miles',
    ]);
    if (miles != null && miles > 0) return miles * 1.609344;
    return null;
  }

  /// When the API omits `distance_to_pickup_*`, use great-circle km so totals (and price) stay consistent with OSRM haul.
  double? _driverStraightLineDriverToPickupKm(Map<String, dynamic> driver) {
    final driverPoint = _driverCoordinates(driver);
    if (driverPoint == null) return null;
    final pickup = _resolvePickupCoordinates();
    if (!_isValidCoordinatePair(pickup.latitude, pickup.longitude) ||
        !_isValidCoordinatePair(driverPoint.latitude, driverPoint.longitude)) {
      return null;
    }
    return const Distance().as(
      LengthUnit.Kilometer,
      driverPoint,
      pickup,
    );
  }

  /// Leg1 km for totals: OSRM (when prefetched or from map) → API → straight-line.
  double? _driverLeg1KmForTotal(Map<String, dynamic> driver) {
    final id = _driverIntByKeys(driver, const ['id']);
    if (id != null) {
      final cached = _driverToPickupRoadKmById[id];
      if (cached != null && cached > 0) return cached;
    }
    final api = _driverDistanceToPickupKm(driver);
    if (api != null && api > 0) return api;
    return _driverStraightLineDriverToPickupKm(driver);
  }

  double? _driverDistancePickupToDeliveryKm(Map<String, dynamic> driver) {
    final km = _driverDoubleByKeys(driver, const [
      'distance_pickup_to_delivery_km',
      'pickup_to_delivery_km',
      'distance_pickup_delivery_km',
    ]);
    if (km != null && km > 0) return km;
    final miles = _driverDoubleByKeys(driver, const [
      'distance_pickup_to_delivery_miles',
      'pickup_to_delivery_miles',
      'distance_pickup_delivery_miles',
    ]);
    if (miles != null && miles > 0) return miles * 1.609344;
    return null;
  }

  double? _driverDistanceTotalKm(Map<String, dynamic> driver) {
    // Match map: OSRM leg1 (cached) + OSRM pickup→delivery when available.
    // Never add API haversine leg2 once OSRM haul is known.
    final leg2Road = _roadPickupToDeliveryKm;
    if (leg2Road != null && leg2Road > 0) {
      final leg1 = _driverLeg1KmForTotal(driver);
      if (leg1 != null && leg1 > 0) {
        return leg1 + leg2Road;
      }
    }

    final leg1Km = _driverLeg1KmForTotal(driver);
    final leg2Km = _driverDistancePickupToDeliveryKm(driver);
    if (leg1Km != null && leg1Km > 0 && leg2Km != null && leg2Km > 0) {
      final road2 = _roadPickupToDeliveryKm;
      if (road2 != null && road2 > 0) {
        return leg1Km + road2;
      }
      return leg1Km + leg2Km;
    }
    if (leg1Km != null && leg1Km > 0) return leg1Km;

    final leg1Miles = _driverDoubleByKeys(driver, const [
      'distance_to_pickup_miles',
      'driver_to_pickup_miles',
      'distance_driver_to_pickup_miles',
    ]);
    final leg2Miles = _driverDoubleByKeys(driver, const [
      'distance_pickup_to_delivery_miles',
      'pickup_to_delivery_miles',
      'distance_pickup_delivery_miles',
    ]);
    if (leg1Miles != null &&
        leg1Miles > 0 &&
        leg2Miles != null &&
        leg2Miles > 0) {
      return (leg1Miles + leg2Miles) * 1.609344;
    }
    if (leg1Miles != null && leg1Miles > 0) return leg1Miles * 1.609344;

    final kmDirect = _driverDoubleByKeys(driver, const [
      'distance_total_km',
      'total_distance_km',
      'distance_km',
    ]);
    if (kmDirect != null && kmDirect > 0) return kmDirect;

    final milesDirect = _driverDoubleByKeys(driver, const [
      'distance_total_miles',
      'total_distance_miles',
      'distance_miles',
      'distance_mi',
    ]);
    if (milesDirect != null && milesDirect > 0) {
      return milesDirect * 1.609344;
    }

    final genericDistance = _driverDoubleByKeys(driver, const ['distance']);
    final unitRaw = (driver['distance_unit'] ?? driver['unit'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
    if (genericDistance != null && genericDistance > 0) {
      if (unitRaw == 'mi' || unitRaw == 'mile' || unitRaw == 'miles') {
        return genericDistance * 1.609344;
      }
      return genericDistance;
    }

    return null;
  }

  String? _driverDistanceCompact(Map<String, dynamic> driver) {
    final totalKm = _driverDistanceTotalKm(driver);
    if (totalKm != null) {
      return _formatRouteDistance(totalKm);
    }

    final toPickupKm = _driverLeg1KmForTotal(driver);
    final pickupToDeliveryKm = _driverDistancePickupToDeliveryKm(driver);
    final leg2Road = _roadPickupToDeliveryKm;

    if (toPickupKm != null && leg2Road != null && leg2Road > 0) {
      return '${_formatRouteDistance(toPickupKm)} → ${_formatRouteDistance(leg2Road)}';
    }

    if (toPickupKm != null && pickupToDeliveryKm != null) {
      return '${_formatRouteDistance(toPickupKm)} → ${_formatRouteDistance(pickupToDeliveryKm)}';
    }

    if (toPickupKm != null) {
      return _formatRouteDistance(toPickupKm);
    }

    return null;
  }

  int? _driverIntByKeys(Map<String, dynamic> driver, List<String> keys) {
    for (final key in keys) {
      final raw = driver[key];
      if (raw == null) continue;
      if (raw is num) return raw.toInt();
      final parsed = int.tryParse(raw.toString());
      if (parsed != null) return parsed;
    }
    return null;
  }

  bool _driverHasSections(Map<String, dynamic> driver, {int? sectionsCount}) {
    final raw = driver['has_sections'] ??
        driver['sectional_loading_enabled'] ??
        driver['is_sectioned'] ??
        driver['sectioned'] ??
        driver['has_compartments'];
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    final s = raw?.toString().toLowerCase().trim() ?? '';
    if (s == '1' || s == 'true' || s == 'yes') return true;
    if (sectionsCount != null) return sectionsCount > 0;
    return false;
  }

  int? _freeSectionsFromLayout(dynamic layoutRaw) {
    if (layoutRaw == null) return null;

    dynamic layout = layoutRaw;
    if (layoutRaw is String && layoutRaw.trim().isNotEmpty) {
      try {
        layout = json.decode(layoutRaw);
      } catch (_) {
        return null;
      }
    }

    if (layout is Map) {
      final direct = _driverIntByKeys(
        Map<String, dynamic>.from(layout),
        ['free_sections', 'available_sections', 'sections_free', 'free'],
      );
      if (direct != null) return direct;

      final sections = layout['sections'];
      if (sections is List) {
        int free = 0;
        for (final s in sections) {
          if (s is! Map) continue;
          final m = Map<String, dynamic>.from(s);
          final isFreeRaw = m['is_free'] ?? m['free'] ?? m['available'];
          if (isFreeRaw == true || isFreeRaw == 1 || isFreeRaw?.toString() == '1' ||
              isFreeRaw?.toString().toLowerCase() == 'true') {
            free++;
          }
        }
        return free;
      }
    }

    if (layout is List) {
      int free = 0;
      for (final s in layout) {
        if (s is! Map) continue;
        final m = Map<String, dynamic>.from(s);
        final isFreeRaw = m['is_free'] ?? m['free'] ?? m['available'];
        if (isFreeRaw == true || isFreeRaw == 1 || isFreeRaw?.toString() == '1' ||
            isFreeRaw?.toString().toLowerCase() == 'true') {
          free++;
        }
      }
      return free;
    }

    return null;
  }

  String _driverSectionsDetail(Map<String, dynamic> driver) {
    final sectionsCount = _driverIntByKeys(driver, [
      'sections_count',
      'section_count',
      'number_of_sections',
      'cargo_sections',
      'wagon_sections',
      'compartment_count',
      'compartments',
    ]);
    int? freeSections = _driverIntByKeys(driver, [
      'free_sections',
      'sections_free',
      'available_sections',
      'free_compartments',
      'available_compartments',
    ]);
    freeSections ??= _freeSectionsFromLayout(driver['vehicle_sections']);
    final hasSections = _driverHasSections(driver, sectionsCount: sectionsCount);

    if (!hasSections && sectionsCount == null && freeSections == null) {
      return '';
    }
    if (sectionsCount != null && freeSections != null) {
      return 'Sections: $sectionsCount • Free: $freeSections';
    }
    if (sectionsCount != null) {
      return 'Sections: $sectionsCount';
    }
    if (freeSections != null) {
      return 'Free sections: $freeSections';
    }
    return 'Sectioned wagon';
  }

  bool _isTruthy(dynamic raw) {
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    final s = raw?.toString().toLowerCase().trim() ?? '';
    return s == '1' || s == 'true' || s == 'yes';
  }

  List<bool?> _driverSectionStates(Map<String, dynamic> driver) {
    final driverOccupied = _isDriverOccupied(driver);
    dynamic directStates = driver['section_states'];
    if (directStates is String && directStates.trim().isNotEmpty) {
      try {
        directStates = json.decode(directStates);
      } catch (_) {
        directStates = null;
      }
    }
    if (directStates is List && directStates.isNotEmpty) {
      final parsed = directStates
          .map<bool?>((e) {
            if (e == null) return null;
            if (e is bool) return e;
            if (e is num) return e != 0;
            final s = e.toString().toLowerCase().trim();
            if (s == 'free' || s == 'available') return true;
            if (s == 'occupied' || s == 'busy') return false;
            if (s == 'true' || s == '1' || s == 'yes') return true;
            if (s == 'false' || s == '0' || s == 'no') return false;
            return null;
          })
          .toList(growable: false);
      if (parsed.isNotEmpty && parsed.every((s) => s == null)) {
        return List<bool?>.filled(parsed.length, !driverOccupied, growable: false);
      }
      final freeSectionsHint = _driverIntByKeys(driver, const [
        'free_sections',
        'available_sections',
      ]);
      if (freeSectionsHint != null) {
        final freeCount = parsed.where((s) => s == true).length;
        final occupiedCount = parsed.where((s) => s == false).length;
        if (occupiedCount == freeSectionsHint && freeCount != freeSectionsHint) {
          return parsed.map((s) => s == null ? null : !s).toList(growable: false);
        }
      }
      return parsed;
    }

    final occupiedIndicesRaw = driver['occupied_section_indices'];
    if (occupiedIndicesRaw is List && occupiedIndicesRaw.isNotEmpty) {
      final occupiedIndices = occupiedIndicesRaw
          .map((e) => e is num ? e.toInt() : int.tryParse(e.toString()))
          .whereType<int>()
          .toSet();
      final explicitCount = _driverIntByKeys(driver, const [
        'sections_count',
        'section_count',
        'number_of_sections',
        'cargo_sections',
        'wagon_sections',
        'compartment_count',
        'compartments',
      ]);
      final count = explicitCount ??
          (occupiedIndices.isEmpty
              ? 0
              : (occupiedIndices.reduce((a, b) => a > b ? a : b) + 1));
      if (count > 0) {
        return List<bool?>.generate(
          count,
          (index) => !occupiedIndices.contains(index),
        );
      }
    }

    dynamic raw = driver['vehicle_sections'];
    if (raw == null) return const [];

    if (raw is String && raw.trim().isNotEmpty) {
      try {
        raw = json.decode(raw);
      } catch (_) {
        return const [];
      }
    }

    List<dynamic> sectionList = const [];
    if (raw is List) {
      sectionList = raw;
    } else if (raw is Map) {
      final sections = raw['sections'] ?? raw['compartments'] ?? raw['items'];
      if (sections is List) {
        sectionList = sections;
      }
    }

    if (sectionList.isEmpty) return const [];

    final states = <bool?>[];
    for (final item in sectionList) {
      if (item is! Map) {
        states.add(null);
        continue;
      }
      final m = Map<String, dynamic>.from(item);
      final occupiedRaw = m['is_occupied'] ?? m['occupied'] ?? m['busy'];
      final freeRaw = m['is_free'] ?? m['free'] ?? m['available'] ?? m['is_available'];

      if (occupiedRaw != null) {
        states.add(!_isTruthy(occupiedRaw));
        continue;
      }
      if (freeRaw != null) {
        states.add(_isTruthy(freeRaw));
        continue;
      }

      final loadRaw = m['current_load'] ?? m['load'] ?? m['quantity'] ?? m['filled'];
      final load = loadRaw is num
          ? loadRaw.toDouble()
          : double.tryParse(loadRaw?.toString().replaceAll(',', '.') ?? '');
      if (load != null) {
        states.add(load <= 0);
      } else {
        // If DB layout only contains static section metadata (id/name/percentage),
        // assume all sections share the driver's global availability.
        states.add(!driverOccupied);
      }
    }

    return states;
  }

  /// Driver summary for the expanded find-driver map — kept **inside** the same bottom
  /// sheet as [FlutterMap] so it never renders under the map (nested modal routes can
  /// lose z-order vs map layers on iOS).
  Widget _buildDriverMapDetailPanel({
    required BuildContext context,
    required Map<String, dynamic> driver,
    required bool isDark,
    required bool isLoadingRoute,
    required Map<String, dynamic>? routeMeta,
  }) {
    final sectionStates = _driverSectionStates(driver);
    final usernameRaw =
        (driver['driver_username'] ?? driver['username'] ?? driver['name'] ?? 'driver')
            .toString();
    final username = '@${usernameRaw.replaceFirst(RegExp(r'^@+'), '')}';
    final rating = _driverDoubleByKeys(driver, ['rating']) ?? 0;
    final occupied = _isDriverOccupied(driver);
    final freeCount = sectionStates.where((s) => s == true).length;
    final occupiedCount = sectionStates.where((s) => s == false).length;
    final unknownCount = sectionStates.where((s) => s == null).length;
    final textPrimary = isDark ? Colors.white : const Color(0xFF0A0A0A);
    final textSecondary = isDark ? Colors.white60 : const Color(0xFF636366);
    final mutedSurface = isDark ? const Color(0xFF3A3A3C) : const Color(0xFFE5E5EA);
    final cardBg = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final borderColor =
        isDark ? Colors.white.withValues(alpha: 0.10) : Colors.black.withValues(alpha: 0.06);

    final routePreviewTotalKm = _parseCoordinate(routeMeta?['totalKm']);
    final totalTransportEstimate = _driverEstimatedPrice(
      driver,
      totalKmOverride: routePreviewTotalKm,
    );
    final rateLabel = () {
      final detail = _driverPricingDetail(driver);
      if (detail.isEmpty) return '—';
      final first = detail.split(' • ').first.trim();
      return first.isEmpty ? '—' : first;
    }();

    Widget statBlock(String label, String value, {bool emphasize = false}) {
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
                color: textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: emphasize ? 17 : 15,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: textPrimary,
                height: 1.15,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.10),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? const [Color(0xFF3A3A3A), Color(0xFF1A1A1A)]
                        : const [Color(0xFF5A5A5A), Color(0xFF2E2E2E)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Text(
                  usernameRaw.isNotEmpty
                      ? usernameRaw.replaceFirst(RegExp(r'^@+'), '')[0].toUpperCase()
                      : 'D',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      username,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.35,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.star_rounded,
                          size: 22,
                          color: rating > 0
                              ? const Color(0xFFFFB020)
                              : textSecondary.withValues(alpha: 0.5),
                        ),
                        const SizedBox(width: 2),
                        Text(
                          rating > 0 ? rating.toStringAsFixed(1) : '—',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: textPrimary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: occupied
                                ? const Color(0xFFFF3B30).withValues(alpha: isDark ? 0.22 : 0.12)
                                : TradeRepublicTheme.textColor(context).withValues(alpha: isDark ? 0.22 : 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            occupied
                                ? AppLocalizations.of(context)!.occupied
                                : AppLocalizations.of(context)!.free,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: occupied ? const Color(0xFFFF3B30) : TradeRepublicTheme.textColor(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (sectionStates.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Sections · $freeCount ${AppLocalizations.of(context)!.free} · $occupiedCount ${AppLocalizations.of(context)!.occupied}'
              '${unknownCount > 0 ? ' · $unknownCount unknown' : ''}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.15,
                color: textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(sectionStates.length, (i) {
                final bool? freeState = sectionStates[i];
                final bool free = freeState ?? !occupied;
                final bool isUnknown = freeState == null;
                final Color accent = isUnknown
                    ? textSecondary
                    : (free ? TradeRepublicTheme.textColor(context) : const Color(0xFFFF3B30));
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: mutedSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: accent.withValues(alpha: isUnknown ? 0.2 : 0.35),
                    ),
                  ),
                  child: Text(
                    'Section ${i + 1} · ${isUnknown ? (occupied ? '?' : AppLocalizations.of(context)!.free) : (free ? AppLocalizations.of(context)!.free : AppLocalizations.of(context)!.occupied)}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: accent,
                    ),
                  ),
                );
              }),
            ),
          ] else ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: mutedSurface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'No compartment data for this vehicle.',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: textSecondary,
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (isLoadingRoute)
            Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: isDark ? Colors.white70 : TradeRepublicTheme.textColor(context),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Loading route…',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: textSecondary,
                    ),
                  ),
                ),
              ],
            )
          else if (routeMeta != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  statBlock(
                    'Total distance',
                    _formatRouteDistance(routePreviewTotalKm),
                  ),
                  const SizedBox(width: 10),
                  statBlock('Rate', rateLabel),
                  const SizedBox(width: 10),
                  statBlock(
                    'Total price',
                    totalTransportEstimate != null
                        ? _formatCurrency(totalTransportEstimate)
                        : '—',
                    emphasize: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Route',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
                color: textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: TradeRepublicTheme.textColor(context).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${AppLocalizations.of(context)!.routePreviewRouteToPickup} ${_formatRouteDistance(_parseCoordinate(routeMeta['toPickupKm']))} · ${_formatRouteDuration(_parseCoordinate(routeMeta['toPickupMin']))}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: TradeRepublicTheme.textColor(context),
                      height: 1.25,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: TradeRepublicTheme.textColor(context).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${AppLocalizations.of(context)!.routePreviewPickupToDelivery} ${_formatRouteDistance(_parseCoordinate(routeMeta['pickupToDeliveryKm']))} · ${_formatRouteDuration(_parseCoordinate(routeMeta['pickupToDeliveryMin']))}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: TradeRepublicTheme.textColor(context),
                      height: 1.25,
                    ),
                  ),
                ),
              ],
            ),
          ] else
            Text(
              'Tap the map background to clear, or wait for route preview.',
              style: TextStyle(fontSize: 12, color: textSecondary, height: 1.35),
            ),
        ],
      ),
    );
  }

  double? _driverDoubleByKeys(Map<String, dynamic> driver, List<String> keys) {
    for (final key in keys) {
      final raw = driver[key];
      if (raw == null) continue;
      if (raw is num) return raw.toDouble();
      final parsed = double.tryParse(raw.toString().replaceAll(',', '.'));
      if (parsed != null) return parsed;
    }
    return null;
  }

  /// EUR (or account currency) per km for estimates — prefers DB `price_per_km`,
  /// otherwise derives from `price_per_mile` on `delvioo_users` / driver payloads.
  double? _driverEffectivePricePerKm(Map<String, dynamic> driver) {
    final perKm = _driverDoubleByKeys(driver, ['price_per_km', 'pricePerKm']);
    if (perKm != null && perKm > 0) return perKm;
    final perMile = _driverDoubleByKeys(driver, ['price_per_mile', 'pricePerMile']);
    if (perMile != null && perMile > 0) return perMile / 1.609344;
    return null;
  }

  bool _usesMilesSystem() {
    final locale = Localizations.maybeLocaleOf(context);
    final country = (locale?.countryCode ?? '').toUpperCase();
    return country == 'US' || country == 'GB' || country == 'LR' || country == 'MM';
  }

  String _driverPricingDetail(Map<String, dynamic> driver) {
    final perKm = _driverDoubleByKeys(driver, ['price_per_km', 'pricePerKm']);
    final perMile = _driverDoubleByKeys(driver, ['price_per_mile', 'pricePerMile']);
    final cleaning = _driverDoubleByKeys(driver, ['cleaning_certificate_price']);
    final usesMiles = _usesMilesSystem();

    final parts = <String>[];
    if (usesMiles) {
      if (perMile != null && perMile > 0) {
        parts.add('${_formatCurrency(perMile)}/mi');
      } else if (perKm != null && perKm > 0) {
        parts.add('${_formatCurrency(perKm * 1.609344)}/mi');
      }
    } else {
      if (perKm != null && perKm > 0) {
        parts.add('${_formatCurrency(perKm)}/km');
      } else if (perMile != null && perMile > 0) {
        parts.add('${_formatCurrency(perMile / 1.609344)}/km');
      }
    }
    if (cleaning != null && cleaning > 0) {
      parts.add('Cleaning ${_formatCurrency(cleaning)}');
    }
    return parts.join(' • ');
  }

  bool _orderRequiresCleaningCertificate() {
    final raw = _currentOrder['requires_cleaning_certificate'];
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    final normalized = raw?.toString().trim().toLowerCase();
    return normalized == '1' || normalized == 'true' || normalized == 'yes';
  }

  /// [totalKmOverride] — e.g. sum of both route-preview legs so price matches the green Total chip.
  double? _driverEstimatedPrice(
    Map<String, dynamic> driver, {
    double? totalKmOverride,
  }) {
    final explicitPrice = _driverDoubleByKeys(driver, ['estimated_price', 'price']);
    final totalKm = (totalKmOverride != null && totalKmOverride > 0)
        ? totalKmOverride
        : _driverDistanceTotalKm(driver);
    if (totalKm == null || totalKm <= 0) {
      return (explicitPrice != null && explicitPrice > 0)
          ? double.parse(explicitPrice.toStringAsFixed(2))
          : null;
    }

    final pricePerKm = _driverEffectivePricePerKm(driver);
    final perMilePrimary = _driverDoubleByKeys(driver, ['price_per_mile', 'pricePerMile']);
    final basePrice = _driverDoubleByKeys(driver, ['estimated_base_price', 'base_price']);
    final cleaningPrice = _driverDoubleByKeys(driver, ['cleaning_certificate_price']);

    double estimatedPrice;
    if (pricePerKm != null && pricePerKm > 0) {
      // US/UK: multiply stored $/mi × miles so totals match the mi label (avoids km↔mi drift).
      if (_usesMilesSystem() && perMilePrimary != null && perMilePrimary > 0) {
        estimatedPrice = (totalKm / 1.609344) * perMilePrimary;
      } else {
        estimatedPrice = totalKm * pricePerKm;
      }
    } else if (explicitPrice != null && explicitPrice > 0) {
      estimatedPrice = explicitPrice;
    } else if (basePrice != null && basePrice >= 0) {
      estimatedPrice = basePrice + (totalKm * 1.2);
    } else {
      estimatedPrice = totalKm * 1.5;
      if (estimatedPrice < 25) estimatedPrice = 25;
    }

    if (_orderRequiresCleaningCertificate() &&
        cleaningPrice != null &&
        cleaningPrice > 0) {
      estimatedPrice += cleaningPrice;
    }

    return double.parse(estimatedPrice.toStringAsFixed(2));
  }

  String _formatRouteDistance(double? km) {
    if (km == null) return '—';
    if (_usesMilesSystem()) {
      final miles = km / 1.609344;
      if (miles >= 100) return '${miles.toStringAsFixed(0)} mi';
      return '${miles.toStringAsFixed(1)} mi';
    }
    if (km >= 100) return '${km.toStringAsFixed(0)} km';
    return '${km.toStringAsFixed(1)} km';
  }

  String _formatRouteDuration(double? minutes) {
    if (minutes == null) return '—';
    final rounded = minutes.round();
    if (rounded < 60) return '$rounded min';
    final hours = rounded ~/ 60;
    final mins = rounded % 60;
    return mins == 0 ? '${hours}h' : '${hours}h ${mins}m';
  }

  Future<Map<String, dynamic>> _fetchRouteSegmentPreview(
    LatLng start,
    LatLng end,
  ) async {
    final fallbackDistanceKm = const Distance().as(
      LengthUnit.Kilometer,
      start,
      end,
    );
    final fallbackDurationMin = fallbackDistanceKm <= 0
        ? 0.0
        : (fallbackDistanceKm / 55.0) * 60.0;

    if (!_isValidCoordinatePair(start.latitude, start.longitude) ||
        !_isValidCoordinatePair(end.latitude, end.longitude)) {
      return {
        'points': [start, end],
        'distanceKm': fallbackDistanceKm,
        'durationMin': fallbackDurationMin,
      };
    }

    final url =
        'https://router.project-osrm.org/route/v1/driving/'
        '${start.longitude},${start.latitude};${end.longitude},${end.latitude}'
        '?overview=full&geometries=geojson&alternatives=false';

    try {
      final response = await http
          .get(
            Uri.parse(url),
            headers: const {
              'User-Agent': 'CultiooApp/1.0',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['code'] == 'Ok' &&
            data['routes'] is List &&
            (data['routes'] as List).isNotEmpty) {
          final route = data['routes'][0] as Map<String, dynamic>;
          final geometry = route['geometry'];
          final coordinates = geometry is Map ? geometry['coordinates'] : null;

          final points = <LatLng>[];
          if (coordinates is List) {
            for (final coord in coordinates) {
              if (coord is List && coord.length >= 2) {
                final lng = _parseCoordinate(coord[0]);
                final lat = _parseCoordinate(coord[1]);
                if (_isValidCoordinatePair(lat, lng)) {
                  points.add(LatLng(lat!, lng!));
                }
              }
            }
          }

          final distanceMeters = _parseCoordinate(route['distance']);
          final durationSeconds = _parseCoordinate(route['duration']);

          return {
            'points': points.isNotEmpty ? points : [start, end],
            'distanceKm': distanceMeters != null
                ? distanceMeters / 1000.0
                : fallbackDistanceKm,
            'durationMin': durationSeconds != null
                ? durationSeconds / 60.0
                : fallbackDurationMin,
          };
        }
      }
    } catch (_) {}

    return {
      'points': [start, end],
      'distanceKm': fallbackDistanceKm,
      'durationMin': fallbackDurationMin,
    };
  }

  /// One OSRM request for the order haul leg; improves Find Driver list vs haversine.
  Future<void> _refreshRoadPickupToDeliveryKm() async {
    final pickup = _resolvePickupCoordinates();
    // Match expanded map: use user addresses + geocoding when order lacks precise delivery coords.
    final delivery = await _resolveDeliveryCoordinatesForMap();
    if (!_isValidCoordinatePair(pickup.latitude, pickup.longitude) ||
        !_isValidCoordinatePair(delivery.latitude, delivery.longitude)) {
      if (mounted) setState(() => _roadPickupToDeliveryKm = null);
      return;
    }
    if ((pickup.latitude - delivery.latitude).abs() < 1e-5 &&
        (pickup.longitude - delivery.longitude).abs() < 1e-5) {
      if (mounted) setState(() => _roadPickupToDeliveryKm = null);
      return;
    }
    try {
      final seg = await _fetchRouteSegmentPreview(pickup, delivery);
      final km = _parseCoordinate(seg['distanceKm']);
      if (!mounted) return;
      setState(() {
        _roadPickupToDeliveryKm = (km != null && km > 0) ? km : null;
      });
    } catch (_) {
      if (mounted) setState(() => _roadPickupToDeliveryKm = null);
    }
  }

  /// Prefetch OSRM driver→pickup for listed drivers so distance/price match the map (bounded concurrency).
  Future<void> _refreshDriverToPickupOsrmLeg1Batch() async {
    if (!mounted) return;
    final pickup = _resolvePickupCoordinates();
    if (!_isValidCoordinatePair(pickup.latitude, pickup.longitude)) return;

    final work = <Map<String, dynamic>>[];
    for (final d in _availableDrivers) {
      final id = _driverIntByKeys(d, const ['id']);
      if (id == null || id <= 0) continue;
      if (_driverToPickupRoadKmById.containsKey(id)) continue;
      if (_driverCoordinates(d) == null) continue;
      work.add(d);
    }
    const maxDrivers = 30;
    if (work.length > maxDrivers) {
      work.removeRange(maxDrivers, work.length);
    }
    if (work.isEmpty) return;

    const concurrency = 3;
    for (var i = 0; i < work.length; i += concurrency) {
      if (!mounted) return;
      final chunk = work.skip(i).take(concurrency).toList();
      final results = await Future.wait(
        chunk.map((driver) async {
          final id = _driverIntByKeys(driver, const ['id']);
          final pt = _driverCoordinates(driver);
          if (id == null || id <= 0 || pt == null) return null;
          try {
            final seg = await _fetchRouteSegmentPreview(pt, pickup);
            final km = _parseCoordinate(seg['distanceKm']);
            if (km != null && km > 0) return MapEntry(id, km);
          } catch (_) {}
          return null;
        }),
      );
      final batch = <int, double>{};
      for (final e in results) {
        if (e != null) batch[e.key] = e.value;
      }
      if (batch.isNotEmpty && mounted) {
        setState(() => _driverToPickupRoadKmById.addAll(batch));
      }
    }
  }

  Future<void> _showExpandedDriverMap(bool isDark, double mapLat, double mapLng) async {
    Map<String, dynamic>? selectedDriver = _selectedMapDriver;
    final pickupPoint = _resolvePickupCoordinates();
    final deliveryPoint = await _resolveDeliveryCoordinatesForMap();
    List<Polyline> selectedRoutePolylines = [];
    Map<String, dynamic>? selectedRouteMeta;
    bool isLoadingSelectedRoute = false;
    final driverPoints = _sortedDrivers
        .map((driver) => _driverCoordinates(driver))
        .whereType<LatLng>()
        .toList();
    final mapPoints = <LatLng>[
      pickupPoint,
      deliveryPoint,
      ...driverPoints,
      if (driverPoints.isEmpty) LatLng(mapLat, mapLng),
    ];

    Future<void> loadDriverRoutePreview(
      Map<String, dynamic> driver,
      StateSetter setSheetState,
    ) async {
      final driverPoint = _driverCoordinates(driver);
      setSheetState(() {
        selectedDriver = driver;
        isLoadingSelectedRoute = true;
        selectedRouteMeta = null;
        selectedRoutePolylines = [];
      });
      setState(() => _selectedMapDriver = driver);

      if (driverPoint == null) {
        setSheetState(() {
          isLoadingSelectedRoute = false;
        });
        return;
      }

      final toPickup = await _fetchRouteSegmentPreview(driverPoint, pickupPoint);
      final pickupToDelivery = await _fetchRouteSegmentPreview(
        pickupPoint,
        deliveryPoint,
      );

      if (!mounted) return;

      final toPickupRoadKm = _parseCoordinate(toPickup['distanceKm']);
      final pickupToDeliveryRoadKm = _parseCoordinate(pickupToDelivery['distanceKm']);
      final toPickupBackendKm = _driverDistanceToPickupKm(driver);
      final pickupToDeliveryBackendKm = _driverDistancePickupToDeliveryKm(driver);
      final totalBackendKm = _driverDistanceTotalKm(driver);
      // Prefer OSRM road distances over backend haversine legs for display + totals.
      final shownToPickupKm = toPickupRoadKm ?? toPickupBackendKm;
      final shownPickupToDeliveryKm =
          pickupToDeliveryRoadKm ?? pickupToDeliveryBackendKm;
      final minToPickup = _parseCoordinate(toPickup['durationMin']);
      final minPickupToDel = _parseCoordinate(pickupToDelivery['durationMin']);

      // Total = both legs added (full driven route). Price uses this same sum via [totalKmOverride].
      final double totalDistance;
      if (shownToPickupKm != null &&
          shownToPickupKm > 0 &&
          shownPickupToDeliveryKm != null &&
          shownPickupToDeliveryKm > 0) {
        totalDistance = shownToPickupKm + shownPickupToDeliveryKm;
      } else if (totalBackendKm != null && totalBackendKm > 0) {
        totalDistance = totalBackendKm;
      } else {
        final p1t = toPickupBackendKm ?? toPickupRoadKm;
        final p2t = pickupToDeliveryBackendKm ?? pickupToDeliveryRoadKm;
        final p1 = (p1t != null && p1t > 0) ? p1t : 0.0;
        final p2 = (p2t != null && p2t > 0) ? p2t : 0.0;
        totalDistance = p1 + p2;
      }

      final totalDuration = (minToPickup ?? 0) + (minPickupToDel ?? 0);

      List<LatLng> toPickupPoints;
      final toPickupRaw = toPickup['points'];
      if (toPickupRaw is List) {
        toPickupPoints = toPickupRaw.whereType<LatLng>().toList();
      } else {
        toPickupPoints = <LatLng>[];
      }
      if (toPickupPoints.length < 2) {
        toPickupPoints = [driverPoint, pickupPoint];
      }

      List<LatLng> pickupToDeliveryPoints;
      final pickupToDeliveryRaw = pickupToDelivery['points'];
      if (pickupToDeliveryRaw is List) {
        pickupToDeliveryPoints = pickupToDeliveryRaw.whereType<LatLng>().toList();
      } else {
        pickupToDeliveryPoints = <LatLng>[];
      }
      if (pickupToDeliveryPoints.length < 2) {
        pickupToDeliveryPoints = [pickupPoint, deliveryPoint];
      }

      setSheetState(() {
        isLoadingSelectedRoute = false;
        selectedRouteMeta = {
          'toPickupKm': shownToPickupKm,
          'toPickupMin': _parseCoordinate(toPickup['durationMin']),
          'pickupToDeliveryKm': shownPickupToDeliveryKm,
          'pickupToDeliveryMin': _parseCoordinate(pickupToDelivery['durationMin']),
          'totalKm': totalDistance,
          'totalMin': totalDuration,
        };
        selectedRoutePolylines = [
          Polyline(
            points: toPickupPoints,
            strokeWidth: 5,
            color: isDark ? Colors.white : TradeRepublicTheme.textColor(context),
          ),
          Polyline(
            points: pickupToDeliveryPoints,
            strokeWidth: 5,
            color: isDark ? Colors.white : TradeRepublicTheme.textColor(context),
          ),
        ];
      });
      if (!mounted) return;
      final driverId = _driverIntByKeys(driver, const ['id']);
      setState(() {
        if (pickupToDeliveryRoadKm != null && pickupToDeliveryRoadKm > 0) {
          _roadPickupToDeliveryKm = pickupToDeliveryRoadKm;
        }
        if (toPickupRoadKm != null &&
            toPickupRoadKm > 0 &&
            driverId != null &&
            driverId > 0) {
          _driverToPickupRoadKmById[driverId] = toPickupRoadKm;
        }
      });
    }

    TradeRepublicBottomSheet.show(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      maxHeight: MediaQuery.of(context).size.height * 0.92,
      child: StatefulBuilder(
        builder: (ctx, setSheetState) {
          final sortedDrivers = _sortedDrivers;
          final visibleDriversWithCoords = sortedDrivers
            .where((driver) => _driverCoordinates(driver) != null)
            .toList();
          final driversForMap = visibleDriversWithCoords.isNotEmpty
            ? visibleDriversWithCoords
            : _sortedDrivers
              .where((driver) => _driverCoordinates(driver) != null)
              .toList();
          final occupiedCount = sortedDrivers.where(_isDriverOccupied).length;
          final availableCount = sortedDrivers.length - occupiedCount;

          return Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: TradeRepublicTheme.textColor(context).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        CupertinoIcons.map,
                        color: TradeRepublicTheme.textColor(context),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLocalizations.of(ctx)!.findDriver,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.4,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                          ),
                          Text(
                            '${sortedDrivers.length} ${AppLocalizations.of(context)!.drivers.toLowerCase()} • $availableCount ${AppLocalizations.of(context)!.free.toLowerCase()} • $occupiedCount ${AppLocalizations.of(context)!.occupied.toLowerCase()}',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? Colors.white54 : Colors.black45,
                            ),
                          ),
                          Text(
                            '${AppLocalizations.of(context)!.requiredWagon}: ${_requiredWagonLabel()}',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white54 : Colors.black45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                child: _buildDriverSortControl(isDark, setSheetState: setSheetState),
              ),

              // Map + optional driver panel share one [Expanded] so the map always gets a
              // positive height budget (otherwise a tall panel can squeeze the map to 0
              // and trigger "Cannot hit test a render box that has never been laid out").
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: _LayoutSafeMapSlot(
                            placeholderColor: isDark
                                ? const Color(0xFF1C1C1E)
                                : const Color(0xFFE0E0E0),
                            builder: (_) => FlutterMap(
                              options: MapOptions(
                                initialCenter: LatLng(mapLat, mapLng),
                                initialZoom: 11.0,
                                initialCameraFit: mapPoints.length > 1
                                    ? CameraFit.bounds(
                                        bounds: LatLngBounds.fromPoints(mapPoints),
                                        padding: const EdgeInsets.all(56),
                                      )
                                    : null,
                                minZoom: 4.0,
                                maxZoom: 18.0,
                                keepAlive: true,
                                interactionOptions: InteractionOptions(
                                  cursorKeyboardRotationOptions:
                                      CursorKeyboardRotationOptions.disabled(),
                                ),
                                onTap: (_, _) {
                                  setSheetState(() {
                                    selectedDriver = null;
                                    selectedRoutePolylines = [];
                                    selectedRouteMeta = null;
                                  });
                                  setState(() => _selectedMapDriver = null);
                                },
                              ),
                              children: [
                                TileLayer(
                                  urlTemplate: isDark
                                      ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
                                      : 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
                                  retinaMode: RetinaMode.isHighDensity(context),
                                  subdomains: const ['a', 'b', 'c', 'd'],
                                  userAgentPackageName: 'com.cultioo.app',
                                ),
                                if (selectedRoutePolylines.isNotEmpty)
                                  PolylineLayer(polylines: selectedRoutePolylines),
                                MarkerLayer(
                                  markers: [
                                    if (selectedDriver != null)
                                      Marker(
                                        point: pickupPoint,
                                        width: 24,
                                        height: 24,
                                        child: _buildPickupTriangleMarker(),
                                      ),
                                    if (selectedDriver != null)
                                      Marker(
                                        point: deliveryPoint,
                                        width: 20,
                                        height: 16,
                                        child: _buildDeliveryRectangleMarker(),
                                      ),
                                    // Driver markers
                                    ...driversForMap.map((driver) {
                                      final driverPoint = _driverCoordinates(driver);
                                      if (driverPoint == null) return null;
                                      final isOccupied = _isDriverOccupied(driver);
                                      final isSelected = selectedDriver != null &&
                                          selectedDriver!['id'] == driver['id'];
                                      return Marker(
                                        point: driverPoint,
                                        width: isSelected ? 58 : 50,
                                        height: isSelected ? 68 : 60,
                                        child: GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: () {
                                            loadDriverRoutePreview(driver, setSheetState);
                                          },
                                          child: AnimatedSwitcher(
                                            duration: const Duration(milliseconds: 200),
                                            child: SizedBox(
                                              key: ValueKey('driver-${driver['id']}-${isSelected ? 's' : 'n'}'),
                                              child: _buildModernTruckMarker(
                                                isDark: isDark,
                                                isOccupied: isOccupied,
                                                isSelected: isSelected,
                                                size: isSelected ? 50 : 42,
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    }).whereType<Marker>(),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (selectedDriver != null) ...[
                      const SizedBox(height: 10),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: math.min(
                            420.0,
                            MediaQuery.sizeOf(ctx).height * 0.44,
                          ),
                        ),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          physics: const BouncingScrollPhysics(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildDriverMapDetailPanel(
                                context: ctx,
                                driver: selectedDriver!,
                                isDark: isDark,
                                isLoadingRoute: isLoadingSelectedRoute,
                                routeMeta: selectedRouteMeta,
                              ),
                              const SizedBox(height: 12),
                              TradeRepublicButton(
                                label: _isDriverOccupied(selectedDriver!)
                                    ? AppLocalizations.of(context)!.driverOccupied
                                    : AppLocalizations.of(context)!.selectThisDriver,
                                tint: _isDriverOccupied(selectedDriver!)
                                    ? const Color(0xFFFF3B30)
                                    : TradeRepublicTheme.textColor(context),
                                icon: Icon(
                                  _isDriverOccupied(selectedDriver!)
                                      ? CupertinoIcons.exclamationmark_triangle_fill
                                      : CupertinoIcons.checkmark_circle_fill,
                                  color: Colors.white,
                                  size: 18,
                                ),
                                width: double.infinity,
                                onPressed: _isDriverOccupied(selectedDriver!)
                                    ? null
                                    : () {
                                        Navigator.pop(context);
                                        _confirmDriverSelection(selectedDriver!, isDark);
                                      },
                              ),
                              Align(
                                alignment: Alignment.center,
                                child: TextButton(
                                  onPressed: () {
                                    setSheetState(() {
                                      selectedDriver = null;
                                      selectedRoutePolylines = [];
                                      selectedRouteMeta = null;
                                    });
                                    setState(() => _selectedMapDriver = null);
                                  },
                                  child: Text(
                                    AppLocalizations.of(context)!.close,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: isDark ? Colors.white60 : Colors.black54,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (selectedDriver == null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  child: TradeRepublicButton(
                    label: '${sortedDrivers.length} ${AppLocalizations.of(context)!.drivers}',
                    icon: const Icon(Icons.local_shipping_rounded, size: 16),
                    isSecondary: true,
                    width: double.infinity,
                    onPressed: () {
                      TradeRepublicBottomSheet.show(
                        context: context,
                        useRootNavigator: true,
                        showDragHandle: true,
                        maxHeight: MediaQuery.of(context).size.height * 0.72,
                        child: _buildExpandedDriverList(
                          isDark,
                          onSelect: (driver) {
                            Navigator.pop(context);
                            loadDriverRoutePreview(driver, setSheetState);
                          },
                        ),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildExpandedDriverList(bool isDark, {required void Function(Map<String, dynamic>) onSelect}) {
    final sortedDrivers = _sortedDrivers;
    final occupiedCount = sortedDrivers.where(_isDriverOccupied).length;
    final availableCount = sortedDrivers.length - occupiedCount;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDriverSortControl(isDark),
              const SizedBox(height: 10),
              Text(
                '$availableCount ${AppLocalizations.of(context)!.free.toLowerCase()} • $occupiedCount ${AppLocalizations.of(context)!.occupied.toLowerCase()}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${AppLocalizations.of(context)!.requiredWagon}: ${_requiredWagonLabel()}',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: sortedDrivers.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final driver = sortedDrivers[i];
        final isOccupied = _isDriverOccupied(driver);
        final statusColor = isOccupied ? const Color(0xFFFF3B30) : TradeRepublicTheme.textColor(context);
        final name = _driverDisplayName(driver);
        final rating = driver['rating'];
        final distanceLabel = _driverDistanceCompact(driver);
        final price = _driverEstimatedPrice(driver);
        final pricingInfo = _driverPricingDetail(driver);
        final initial = name.toString().isNotEmpty ? name.toString().substring(0, 1).toUpperCase() : 'D';

        return GestureDetector(
          onTap: () {
            if (isOccupied) {
              TopNotification.info(context, AppLocalizations.of(context)!.driverCurrentlyOccupied);
              return;
            }
            onSelect(driver);
          },
          child: TradeRepublicCard(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text(
                      initial,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name.toString(), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black)),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isOccupied ? AppLocalizations.of(context)!.occupied : AppLocalizations.of(context)!.available,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (rating != null) ...[
                            const Icon(CupertinoIcons.star_fill, size: 11, color: Color(0xFFFF9500)),
                            const SizedBox(width: 3),
                            Text(double.tryParse(rating.toString())?.toStringAsFixed(1) ?? rating.toString(),
                                style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.black54)),
                            const SizedBox(width: 8),
                          ],
                          if (distanceLabel != null) ...[
                            Icon(CupertinoIcons.location, size: 11, color: isDark ? Colors.white38 : Colors.black26),
                            const SizedBox(width: 3),
                            Text(
                              distanceLabel,
                                style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black45)),
                          ],
                        ],
                      ),
                      if (pricingInfo.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              CupertinoIcons.speedometer,
                              size: 11,
                              color: isDark ? Colors.white38 : Colors.black26,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                pricingInfo,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white54 : Colors.black45,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (price != null)
                  Text(
                    _formatCurrency(price),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                const SizedBox(width: 6),
                Icon(
                  isOccupied ? CupertinoIcons.lock_fill : CupertinoIcons.chevron_right,
                  size: 14,
                  color: isOccupied
                      ? const Color(0xFFFF3B30)
                      : (isDark ? Colors.white30 : Colors.black26),
                ),
              ],
            ),
          ),
        );
      },
          ),
        ),
      ],
    );
  }

  Widget _buildExpandedDriverCard(Map<String, dynamic> driver, bool isDark, {required VoidCallback onClose}) {
    final name = _driverDisplayName(driver);
    final rating = driver['rating'];
    final distanceLabel = _driverDistanceCompact(driver);
    final vehicleType = driver['vehicle_type'] ?? '';
    final price = _driverEstimatedPrice(driver);
    final sectionsInfo = _driverSectionsDetail(driver);
    final pricingInfo = _driverPricingDetail(driver);
    final initial = name.toString().isNotEmpty ? name.toString().substring(0, 1).toUpperCase() : 'D';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: TradeRepublicCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: TradeRepublicTheme.textColor(context).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Center(
                    child: Text(
                      initial,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: TradeRepublicTheme.textColor(context),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name.toString(), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: isDark ? Colors.white : Colors.black)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (rating != null) ...[
                            const Icon(CupertinoIcons.star_fill, size: 13, color: Color(0xFFFF9500)),
                            const SizedBox(width: 4),
                            Text(double.tryParse(rating.toString())?.toStringAsFixed(1) ?? rating.toString(),
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: isDark ? Colors.white70 : Colors.black54)),
                            const SizedBox(width: 10),
                          ],
                          if (vehicleType.toString().isNotEmpty) ...[
                            Icon(CupertinoIcons.car_detailed, size: 13, color: isDark ? Colors.white38 : Colors.black26),
                            const SizedBox(width: 4),
                            Text(vehicleType.toString(), style: TextStyle(fontSize: 13, color: isDark ? Colors.white54 : Colors.black45)),
                          ],
                        ],
                      ),
                      if (sectionsInfo.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              CupertinoIcons.square_split_2x1,
                              size: 12,
                              color: isDark ? Colors.white38 : Colors.black26,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              sectionsInfo,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.white54 : Colors.black45,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (pricingInfo.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              CupertinoIcons.money_dollar,
                              size: 12,
                              color: isDark ? Colors.white38 : Colors.black26,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                pricingInfo,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? Colors.white54 : Colors.black45,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                TradeRepublicButton.icon(
                  icon: Icon(CupertinoIcons.xmark, size: 14, color: isDark ? Colors.white54 : Colors.black45),
                  onPressed: onClose,
                  size: 32,
                  isSecondary: true,
                ),
              ],
            ),
            if (distanceLabel != null || price != null) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  if (distanceLabel != null)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                            Text(
                              AppLocalizations.of(context)!.kmAway,
                              style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.black38, letterSpacing: 0.3)),
                          const SizedBox(height: 2),
                            Text(
                              distanceLabel,
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: isDark ? Colors.white : Colors.black)),
                        ],
                      ),
                    ),
                  if (price != null)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                            Text(
                              'Total transport',
                              style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.black38, letterSpacing: 0.3)),
                          const SizedBox(height: 2),
                          Text(_formatCurrency(price),
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: isDark ? Colors.white : Colors.black)),
                        ],
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            TradeRepublicButton(
              label: AppLocalizations.of(context)!.selectThisDriver,
              tint: TradeRepublicTheme.textColor(context),
              icon: const Icon(CupertinoIcons.checkmark_circle_fill, color: Colors.white, size: 18),
              width: double.infinity,
              onPressed: () {
                Navigator.pop(context);
                _confirmDriverSelection(driver, isDark);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFindDriverUI(bool isDark) {
    final isLoading = _isLoadingAvailableDrivers;
    final sortedDrivers = _sortedDrivers;
    final hasDrivers = sortedDrivers.isNotEmpty;
    final occupiedCount = sortedDrivers.where(_isDriverOccupied).length;
    final availableCount = sortedDrivers.length - occupiedCount;

    // Get delivery coordinates from multiple DB fields (order-level + address).
    final deliveryPoint = _resolveDeliveryCoordinates();
    final mapLat = deliveryPoint.latitude;
    final mapLng = deliveryPoint.longitude;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TradeRepublicCard(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'What to do here',
                style: TradeRepublicTheme.titleSmall(context).copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Open map for nearby drivers, use filters, then tap one available driver to assign. '
                'Only matching wagon types are shown.',
                style: _sheetCaptionStyle(context).copyWith(
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        // ── "Processing" banner – shown after direct driver selection ──
        if (_driverPendingConfirmation || _currentOrder['driver_id'] != null) ...[
          TradeRepublicCard(
            margin: const EdgeInsets.only(bottom: 12),
            backgroundColor: const Color(0xFFFF9500).withValues(alpha: isDark ? 0.14 : 0.10),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF9500).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    CupertinoIcons.clock_fill,
                    size: 20,
                    color: Color(0xFFFF9500),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Processing',
                        style: TradeRepublicTheme.titleSmall(context).copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Request sent · Driver confirming shortly',
                        style: _sheetCaptionStyle(context).copyWith(fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],

        // Map launcher card — map itself is fully in bottom sheet
        GestureDetector(
          onTap: () => _showExpandedDriverMap(isDark, mapLat, mapLng),
          child: TradeRepublicCard(
            padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: TradeRepublicTheme.textColor(context).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    CupertinoIcons.map_pin_ellipse,
                    color: TradeRepublicTheme.textColor(context),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context)!.findDriver,
                        style: _sheetSubSheetTitleStyle(context).copyWith(fontSize: 18),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        AppLocalizations.of(context)!.findDriverDesc,
                        style: _sheetCaptionStyle(context).copyWith(fontSize: 14),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${sortedDrivers.length} ${AppLocalizations.of(context)!.drivers.toLowerCase()} • $availableCount ${AppLocalizations.of(context)!.free.toLowerCase()} • $occupiedCount ${AppLocalizations.of(context)!.occupied.toLowerCase()}',
                        style: _sheetCaptionStyle(context).copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${AppLocalizations.of(context)!.requiredWagon}: ${_requiredWagonLabel()}',
                        style: _sheetCaptionStyle(context).copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _sheetSurfaceMuted(context),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    CupertinoIcons.arrow_up_left_arrow_down_right,
                    size: 16,
                    color: TradeRepublicTheme.iconColor(context, opacity: 0.45),
                  ),
                ),
                const SizedBox(width: 8),
                TradeRepublicButton.icon(
                  icon: Icon(
                    CupertinoIcons.refresh,
                    size: 16,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                  onPressed: _loadAvailableDrivers,
                  size: 36,
                  isSecondary: true,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        if (isLoading)
          TradeRepublicCard(
            padding: const EdgeInsets.all(32),
            child: Column(
              children: [
                const CultiooLoadingIndicator(),
                const SizedBox(height: 16),
                Text(
                  AppLocalizations.of(context)!.loadingAvailableDrivers,
                  style: _sheetCaptionStyle(context).copyWith(fontSize: 14),
                ),
              ],
            ),
          )
        else if (!hasDrivers)
          const SizedBox.shrink()
        else ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Row(
              children: [
                Text(
                  '${sortedDrivers.length} ',
                  style: TradeRepublicTheme.titleSmall(context).copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  AppLocalizations.of(context)!.availableDrivers,
                  style: _sheetCaptionStyle(context).copyWith(fontSize: 15),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _buildDriverSortControl(isDark),
          ),
          const SizedBox(height: 10),

          // Driver cards list
          ...sortedDrivers.map((driver) {
            final driverName = _driverDisplayName(driver);
            final isOccupied = _isDriverOccupied(driver);
            final statusColor = isOccupied ? const Color(0xFFFF3B30) : TradeRepublicTheme.textColor(context);
            final rating = driver['rating'];
            final distanceLabel = _driverDistanceCompact(driver);
            final vehicleType = driver['vehicle_type'] ?? '';
            final price = _driverEstimatedPrice(driver);
            final sectionsInfo = _driverSectionsDetail(driver);
            final pricingInfo = _driverPricingDetail(driver);
            final initial = driverName.toString().isNotEmpty
                ? driverName.toString().substring(0, 1).toUpperCase()
                : 'D';
            final isSelected = _selectedMapDriver != null &&
                (_selectedMapDriver!['id'] == driver['id']);

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TradeRepublicCard(
                onTap: () => _onDriverTap(driver, isDark),
                padding: const EdgeInsets.all(16),
                backgroundColor: isSelected
                    ? statusColor.withValues(alpha: 0.10)
                    : null,
                child: Row(
                    children: [
                      // Avatar
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Center(
                          child: Text(
                            initial,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: statusColor,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      // Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              driverName.toString(),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : Colors.black,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: statusColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  isOccupied ? AppLocalizations.of(context)!.occupied : AppLocalizations.of(context)!.available,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: statusColor,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                if (rating != null) ...[
                                  const Icon(CupertinoIcons.star_fill, size: 12, color: Color(0xFFFF9500)),
                                  const SizedBox(width: 3),
                                  Text(
                                    double.tryParse(rating.toString())?.toStringAsFixed(1) ?? rating.toString(),
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: isDark ? Colors.white70 : Colors.black54),
                                  ),
                                  const SizedBox(width: 10),
                                ],
                                if (vehicleType.toString().isNotEmpty) ...[
                                  Icon(CupertinoIcons.car_detailed, size: 12, color: isDark ? Colors.white38 : Colors.black26),
                                  const SizedBox(width: 3),
                                  Text(
                                    vehicleType.toString(),
                                    style: TextStyle(fontSize: 13, color: isDark ? Colors.white54 : Colors.black38),
                                  ),
                                  const SizedBox(width: 10),
                                ],
                                if (distanceLabel != null) ...[
                                  Icon(CupertinoIcons.location, size: 12, color: isDark ? Colors.white38 : Colors.black26),
                                  const SizedBox(width: 3),
                                  Text(
                                    distanceLabel,
                                    style: TextStyle(fontSize: 13, color: isDark ? Colors.white54 : Colors.black38),
                                  ),
                                ],
                              ],
                            ),
                            if (sectionsInfo.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    CupertinoIcons.square_split_2x1,
                                    size: 12,
                                    color: isDark ? Colors.white38 : Colors.black26,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    sectionsInfo,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark ? Colors.white54 : Colors.black38,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            if (pricingInfo.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    CupertinoIcons.money_dollar,
                                    size: 12,
                                    color: isDark ? Colors.white38 : Colors.black26,
                                  ),
                                  const SizedBox(width: 3),
                                  Expanded(
                                    child: Text(
                                      pricingInfo,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDark ? Colors.white54 : Colors.black38,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      // Price + Arrow
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (price != null)
                            Text(
                              _formatCurrency(price),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: isDark ? Colors.white : Colors.black,
                              ),
                            ),
                          const SizedBox(height: 4),
                          Icon(
                            CupertinoIcons.chevron_right,
                            size: 16,
                            color: isDark ? Colors.white30 : Colors.black26,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            );
          }),
        ],
      ],
    );
  }

  // Cleaning Certificate Info Widget
  Widget _buildCleaningCertificateInfo(bool isDark) {
    final rawValue = _currentOrder['requires_cleaning_certificate'];
    final requiresCleaning =
        rawValue == 1 || rawValue == '1' || rawValue == true;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: requiresCleaning
            ? TradeRepublicTheme.textColor(context)
            : (isDark
                  ? const Color(0xFF141414)
                  : Colors.black.withOpacity(0.03)),
        borderRadius: BorderRadius.circular(25),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Modern icon container
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: requiresCleaning
                      ? Colors.white.withOpacity(0.25)
                      : (isDark
                            ? Colors.white.withOpacity(0.1)
                            : Colors.black.withOpacity(0.1)),
                  borderRadius: BorderRadius.circular(25),
                ),

                child: Icon(
                  requiresCleaning
                      ? CupertinoIcons.checkmark_seal
                      : CupertinoIcons.sparkles,
                  color: requiresCleaning
                      ? Colors.white
                      : (isDark
                            ? Colors.white.withOpacity(0.7)
                            : Colors.black.withOpacity(0.7)),
                  size: 26,
                ),
              ),
              const SizedBox(width: 16),
              // Text content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.cleaningCertificate,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: requiresCleaning
                            ? Colors.white
                            : (isDark ? Colors.white : Colors.black),
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      requiresCleaning
                          ? AppLocalizations.of(context)!.wagonCleaningVerificationRequired
                          : AppLocalizations.of(
                              context,
                            )!.noCleaningVerificationNeeded,
                      style: TextStyle(
                        fontSize: 13,
                        color: requiresCleaning
                            ? Colors.white.withOpacity(0.85)
                            : (isDark
                                  ? Colors.white.withOpacity(0.7)
                                  : Colors.black.withOpacity(0.6)),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              // Modern badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: requiresCleaning
                      ? Colors.white
                      : Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(25),
                ),

                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      requiresCleaning
                          ? CupertinoIcons.checkmark
                          : CupertinoIcons.minus,
                      size: 14,
                      color: requiresCleaning
                          ? TradeRepublicTheme.textColor(context)
                          : Colors.white.withOpacity(0.6),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      requiresCleaning ? AppLocalizations.of(context)!.badgeRequired : AppLocalizations.of(context)!.badgeOptional,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: requiresCleaning
                            ? TradeRepublicTheme.textColor(context)
                            : Colors.white.withOpacity(0.6),
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Fee and status section (only if required)
          if (requiresCleaning) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.15),
                borderRadius: BorderRadius.circular(25),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: const Icon(
                      CupertinoIcons.hammer_fill,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLocalizations.of(
                            context,
                          )!.driversWillIncludeCleaningFeeInTheirBid,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          AppLocalizations.of(
                            context,
                          )!.compareOffersToFindTheBestPrice,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.7),
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Customer-facing Cleaning Certificate Info Widget
  Widget _buildCustomerCleaningCertificateInfo(bool isDark) {
    final cleaningFee = _currentOrder['cleaning_certificate_fee'] ?? 0;
    final feeAmount = cleaningFee is int
        ? cleaningFee.toDouble()
        : (cleaningFee is String
              ? double.tryParse(cleaningFee) ?? 0.0
              : (cleaningFee as double? ?? 0.0));

    final desktop = CultiooDesktopLayout.isDesktopPlatform;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: desktop
            ? Colors.transparent
            : TradeRepublicTheme.surfaceColor(context),
        borderRadius: BorderRadius.circular(25),
        border: desktop
            ? null
            : Border.all(
                color:
                    TradeRepublicTheme.textColor(context).withValues(alpha: 0.08),
              ),
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: TradeRepublicTheme.fillColor(context, opacity: 0.1),
                  borderRadius: BorderRadius.circular(25),
                ),

                child: Icon(
                  CupertinoIcons.checkmark_seal_fill,
                  color: TradeRepublicTheme.textColor(context),
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.cleaningCertificate,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: TradeRepublicTheme.textColor(context),
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppLocalizations.of(context)!.requiredForThisDelivery,
                      style: TextStyle(
                        fontSize: 13,
                        color: TradeRepublicTheme.hintColor(context, opacity: 0.72),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              // Checkmark Badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: TradeRepublicTheme.backgroundColor(context),
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(
                    color: TradeRepublicTheme.textColor(context)
                        .withValues(alpha: 0.12),
                  ),
                ),

                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      CupertinoIcons.checkmark_circle_fill,
                      color: TradeRepublicTheme.textColor(context),
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      AppLocalizations.of(context)!.badgeIncluded,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: TradeRepublicTheme.textColor(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Description
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: TradeRepublicTheme.fillColor(context, opacity: 0.06),
              borderRadius: BorderRadius.circular(25),
            ),
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.info,
                  color: TradeRepublicTheme.hintColor(context, opacity: 0.85),
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    AppLocalizations.of(
                      context,
                    )!.yourDeliveryVehicleWillBeProfessionallyClean,
                    style: TextStyle(
                      fontSize: 13,
                      color: TradeRepublicTheme.hintColor(context, opacity: 0.9),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Fee Info (if applicable)
          if (feeAmount > 0) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: TradeRepublicTheme.fillColor(context, opacity: 0.08),
                borderRadius: BorderRadius.circular(25),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    AppLocalizations.of(context)!.certificateFee,
                    style: TextStyle(
                      fontSize: 14,
                      color: TradeRepublicTheme.hintColor(context, opacity: 0.85),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    '{currencySymbol}${feeAmount.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 16,
                      color: TradeRepublicTheme.textColor(context),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Duration Chip Widget
  Widget _buildDurationChip(int minutes, bool isDark) {
    final isSelected =
        _selectedAuctionDuration == minutes && !_useCustomDuration;
    final label = minutes >= 60 ? '${minutes ~/ 60}h' : '${minutes}m';
    return Expanded(
      child: TradeRepublicButton(
        label: label,
        height: 44,
        tint: isSelected ? TradeRepublicTheme.textColor(context) : null,
        isSecondary: !isSelected,
        onPressed: () {
          setState(() {
            _selectedAuctionDuration = minutes;
            _useCustomDuration = false;
          });
        },
      ),
    );
  }

  // Smart auction setting card (toggle + optional child widget)
  Widget _buildAuctionSmartCard({
    required bool isDark,
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required bool isEnabled,
    required Function(bool) onToggle,
    Widget? child,
  }) {
    return TradeRepublicCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isEnabled
                      ? color
                      : color.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  color: TradeRepublicTheme.backgroundColor(context),
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TradeRepublicTheme.titleSmall(context).copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: _sheetCaptionStyle(context).copyWith(
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TradeRepublicSwitch(
                value: isEnabled,
                onChanged: onToggle,
                selectedColor: const Color(0xFF34C759), // on = green
                unselectedColor: const Color(0xFFFF3B30), // off = red
              ),
            ],
          ),
          if (child != null) ...[
            child,
          ],
        ],
      ),
    );
  }

  // Active Auction UI - shows countdown timer and button to view bids
  Widget _buildActiveAuctionUI(bool isDark) {
    final endTimeStr = _auction!['end_time']?.toString() ?? '';
    final endTime = DateTime.tryParse(endTimeStr);
    final now = DateTime.now();
    final remaining = endTime?.difference(now) ?? Duration.zero;
    final isExpired = remaining.isNegative;
    final accentColor = isExpired ? Colors.orange : TradeRepublicTheme.textColor(context);

    return TradeRepublicCard(
      backgroundColor: accentColor.withOpacity(0.06),
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // Header: icon + timer + refresh
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isExpired ? CupertinoIcons.multiply_circle_fill : CupertinoIcons.time,
                    color: accentColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isExpired
                            ? AppLocalizations.of(context)!.auctionEnded
                            : AppLocalizations.of(context)!.driverAuction,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white54 : Colors.black45,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isExpired
                            ? AppLocalizations.of(context)!.selectADriver
                            : '${remaining.inMinutes}:${(remaining.inSeconds % 60).toString().padLeft(2, '0')}',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : Colors.black,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                // Refresh button
                SizedBox(
                  width: 36,
                  height: 36,
                  child: TradeRepublicButton(
                    icon: Icon(CupertinoIcons.refresh, color: accentColor, size: 18),
                    isSecondary: true,
                    width: 36,
                    height: 36,
                    padding: EdgeInsets.zero,
                    borderRadius: BorderRadius.circular(10),
                    onPressed: _loadAuction,
                  ),
                ),
              ],
            ),
          ),

          const TradeRepublicDivider(margin: EdgeInsets.zero),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              children: [
                // View Bids Button
                TradeRepublicButton(
                  label: _bids.isEmpty
                      ? AppLocalizations.of(context)!.waitingForDrivers
                      : AppLocalizations.of(context)!.viewDriversCount(_bids.length),
                  onPressed: () => _showBidsBottomSheet(isDark),
                  icon: const Icon(CupertinoIcons.person_2_fill),
                  tint: accentColor,
                  width: double.infinity,
                ),

                const SizedBox(height: 10),
                TradeRepublicButton(
                  label: 'Cancel driver request',
                  onPressed: _isStartingAuction ? null : _cancelAuction,
                  isSecondary: true,
                  width: double.infinity,
                ),

                // Cully AI Button - only when AI mode is active AND there are bids
                if (_cullyAiEnabled && _bids.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _buildCullyAiButton(isDark),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Cully AI Button ──
  bool _isCullyAiLoading = false;

  Widget _buildCullyAiButton(bool isDark) {
    return StatefulBuilder(
      builder: (ctx, setLocal) {
        return TradeRepublicButton(
          label: _isCullyAiLoading
              ? AppLocalizations.of(context)!.cullyAiAnalysing
              : AppLocalizations.of(context)!.cullyAiSelectBestDriver,
          icon: const Icon(CupertinoIcons.sparkles, color: Colors.white, size: 18),
          tint: TradeRepublicTheme.textColor(context),
          isLoading: _isCullyAiLoading,
          onPressed: _isCullyAiLoading ? null : () => _runCullyAiPick(isDark, setLocal),
          width: double.infinity,
        );
      },
    );
  }

  Future<void> _runCullyAiPick(bool isDark, StateSetter setLocal) async {
    setState(() => _isCullyAiLoading = true);
    try {
      final orderId = _currentOrder['id'];
      final result = await ApiService.cullyAiPickBestDriver(orderId);

      if (!mounted) return;

      if (result['success'] == true) {
        final best = result['best_bid'] as Map<String, dynamic>;

        // Show Cully AI result sheet
        await TradeRepublicBottomSheet.show(
          context: context,
          showDragHandle: true,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: TradeRepublicTheme.textColor(context),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(CupertinoIcons.sparkles, color: Colors.white, size: 26),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLocalizations.of(context)!.cullyAiRecommendation,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                        Text(
                          AppLocalizations.of(context)!.cullyAiBestPriceBestRating,
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white54 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Best driver card
                TradeRepublicCard(
                  backgroundColor: TradeRepublicTheme.textColor(context).withOpacity(0.10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            CupertinoIcons.person_crop_circle_fill,
                            color: TradeRepublicTheme.textColor(context),
                            size: 32,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              best['driver_username']?.toString() ?? AppLocalizations.of(context)!.driver,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: isDark ? Colors.white : Colors.black,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: TradeRepublicTheme.textColor(context),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Score: ${best['ai_score']}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          _buildAiStatChip(
                            CupertinoIcons.money_dollar_circle,
                            '\$${_parseBidAmount(best['bid_amount'])}',
                            TradeRepublicTheme.textColor(context),
                            isDark,
                          ),
                          const SizedBox(width: 10),
                          _buildAiStatChip(
                            CupertinoIcons.star_fill,
                            '${best['rating'] ?? '–'}',
                            const Color(0xFFFF9500),
                            isDark,
                          ),
                          const SizedBox(width: 10),
                          _buildAiStatChip(
                            CupertinoIcons.checkmark_shield_fill,
                            '${best['total_deliveries'] ?? '0'} ${AppLocalizations.of(context)!.deliveries}',
                            TradeRepublicTheme.textColor(context),
                            isDark,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        AppLocalizations.of(context)!.cullyAiPriceRatingWeight,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Accept button
                TradeRepublicButton(
                  label: AppLocalizations.of(context)!.acceptDriver,
                  tint: TradeRepublicTheme.textColor(context),
                  icon: const Icon(CupertinoIcons.checkmark_circle_fill, color: Colors.white, size: 20),
                  width: double.infinity,
                  onPressed: () {
                    Navigator.pop(context);
                    _acceptBid(best);
                  },
                ),
                const SizedBox(height: 12),
                TradeRepublicButton(
                  label: AppLocalizations.of(context)!.cullyAiViewAllBids,
                  isSecondary: true,
                  width: double.infinity,
                  onPressed: () {
                    Navigator.pop(context);
                    _showBidsBottomSheet(isDark);
                  },
                ),
              ],
            ),
          ),
        );
      } else {
        TopNotification.error(
          context,
          result['error'] ?? AppLocalizations.of(context)!.cullyAiNoDriver,
        );
      }
    } catch (e) {
      TopNotification.error(context, AppLocalizations.of(context)!.cullyAiError(e.toString()));
    } finally {
      if (mounted) setState(() => _isCullyAiLoading = false);
    }
  }

  Widget _buildAiStatChip(IconData icon, String label, Color color, bool isDark) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black,
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

  // Show Bids Bottom Sheet with sorting - Minimalist Style (same as Order Details Modal)
  void _showBidsBottomSheet(bool isDark) {
    String sortBy = 'price'; // price, rating, deliveries
    bool sortAscending = true;

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      maxHeight: MediaQuery.of(context).size.height * 0.95,
      child: Builder(
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setSheetState) {
              // Sort bids based on selection
              List<Map<String, dynamic>> sortedBids = List.from(_bids);
              sortedBids.sort((a, b) {
                dynamic aValue, bValue;

                switch (sortBy) {
                  case 'price':
                    aValue = _parseNumericValue(a['bid_amount']);
                    bValue = _parseNumericValue(b['bid_amount']);
                    break;
                  case 'rating':
                    aValue = _parseNumericValue(
                      a['avg_rating'] ?? a['rating'] ?? 0,
                    );
                    bValue = _parseNumericValue(
                      b['avg_rating'] ?? b['rating'] ?? 0,
                    );
                    break;
                  case 'deliveries':
                    aValue = _parseNumericValue(
                      a['completed_deliveries'] ?? a['total_deliveries'] ?? 0,
                    );
                    bValue = _parseNumericValue(
                      b['completed_deliveries'] ?? b['total_deliveries'] ?? 0,
                    );
                    break;
                  default:
                    aValue = 0;
                    bValue = 0;
                }

                if (sortAscending) {
                  return (aValue as num).compareTo(bValue as num);
                } else {
                  return (bValue as num).compareTo(aValue as num);
                }
              });

              return Padding(
                padding: const EdgeInsets.fromLTRB(0, 24, 0, 0),
                child: Column(
                  children: [
                    // Header - Large title + bid count
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  AppLocalizations.of(context)!.availableDrivers,
                                  style: TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  sortedBids.isEmpty
                                      ? AppLocalizations.of(context)!.noOffersYet
                                      : AppLocalizations.of(context)!.offersAvailable(sortedBids.length),
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: isDark ? Colors.white54 : Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Live indicator
                          if (sortedBids.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: const BoxDecoration(
                                      color: Colors.green,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    AppLocalizations.of(context)!.liveLabel,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.green,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Split order banner + linked orders accordion
                    Builder(builder: (context) {
                      final rawSplit = _currentOrder['split_order'];
                      final isSplit = rawSplit == true || rawSplit == 1 || rawSplit.toString() == '1';
                      final linkedOrders = _resolveLinkedSplitOrders();
                      final linkedIds = linkedOrders
                          .map((e) => _toOrderInt(e['id']))
                          .whereType<int>()
                          .toList();
                      if (!isSplit && linkedOrders.length < 2) {
                        return const SizedBox.shrink();
                      }
                      final splitPart = _currentOrder['split_order_part'];
                      final partNumber = splitPart is int ? splitPart : int.tryParse(splitPart?.toString() ?? '') ?? 1;
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                        child: Column(
                          children: [
                            Container(
                              padding: _kSheetTilePaddingCompact,
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white.withOpacity(0.06)
                                    : const Color(0xFF111111).withOpacity(0.04),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isDark
                                      ? Colors.white.withOpacity(0.12)
                                      : Colors.black.withOpacity(0.08),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(isDark ? 0.24 : 0.08),
                                    blurRadius: 18,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? Colors.white.withOpacity(0.12)
                                          : Colors.black.withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      CupertinoIcons.square_split_2x2_fill,
                                      color: isDark ? Colors.white : const Color(0xFF111111),
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${AppLocalizations.of(context)!.splitOrder} · ${_splitHeaderLabel()}',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: isDark ? Colors.white : const Color(0xFF111111),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          isSplit
                                              ? '${AppLocalizations.of(context)!.orderSplitNotice} (Part $partNumber)'
                                              : AppLocalizations.of(context)!.orderSplitNotice,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: isDark ? Colors.white60 : Colors.black54,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (linkedOrders.length >= 2) ...[
                              const SizedBox(height: 10),
                              Container(
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.white.withOpacity(0.04)
                                      : Colors.black.withOpacity(0.03),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isDark
                                        ? Colors.white.withOpacity(0.08)
                                        : Colors.black.withOpacity(0.08),
                                  ),
                                ),
                                child: Theme(
                                  data: Theme.of(context).copyWith(
                                    dividerColor: Colors.transparent,
                                  ),
                                  child: ExpansionTile(
                                    key: const PageStorageKey<String>('split-order-links'),
                                    initiallyExpanded: _splitFamilyExpanded,
                                    onExpansionChanged: (v) {
                                      if (mounted) {
                                        setState(() => _splitFamilyExpanded = v);
                                      }
                                    },
                                    tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                                    childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                                    title: const Text(
                                      'Split family',
                                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                                    ),
                                    subtitle: Text(
                                      linkedIds.map(_displayNumberForOrderId).join(' · '),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDark ? Colors.white54 : Colors.black54,
                                      ),
                                    ),
                                    children: linkedOrders.map((entry) {
                                      final id = _toOrderInt(entry['id']) ?? 0;
                                      final rawStatus = (entry['status'] ?? 'pending').toString().toLowerCase();
                                      final isActiveStatus = rawStatus == 'delivered' || rawStatus == 'completed';
                                      final statusLabel = rawStatus.replaceAll('_', ' ').toUpperCase();
                                      final isSelected = id == _toOrderInt(_currentOrder['id']);
                                      return Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: TradeRepublicListTile(
                                          title: 'Order ${_displayNumberForOrderId(id)}',
                                          subtitle: statusLabel,
                                          leading: const Icon(CupertinoIcons.doc_text, size: 16),
                                          trailing: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: isActiveStatus
                                                  ? Colors.green.withOpacity(0.14)
                                                  : Colors.orange.withOpacity(0.14),
                                              borderRadius: BorderRadius.circular(99),
                                            ),
                                            child: Text(
                                              statusLabel,
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700,
                                                color: isActiveStatus ? Colors.green : Colors.orange,
                                              ),
                                            ),
                                          ),
                                          onTap: () => _switchToSplitOrder(id),
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                          backgroundColor: isSelected
                                              ? const Color(0xFF111111).withOpacity(isDark ? 0.34 : 0.08)
                                              : null,
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    }),

                    // Sort options with label
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLocalizations.of(context)!.sortBy,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: isDark ? Colors.white38 : Colors.grey.shade500,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              _buildSortChip(
                                AppLocalizations.of(context)!.price,
                                'price',
                                sortBy,
                                sortAscending,
                                isDark,
                                CupertinoIcons.money_euro_circle,
                                (newSort, newAsc) {
                                  setSheetState(() {
                                    sortBy = newSort;
                                    sortAscending = newAsc;
                                  });
                                },
                              ),
                              const SizedBox(width: 10),
                              _buildSortChip(
                                AppLocalizations.of(context)!.rating,
                                'rating',
                                sortBy,
                                sortAscending,
                                isDark,
                                CupertinoIcons.star_fill,
                                (newSort, newAsc) {
                                  setSheetState(() {
                                    sortBy = newSort;
                                    sortAscending = newAsc;
                                  });
                                },
                              ),
                              const SizedBox(width: 10),
                              _buildSortChip(
                                AppLocalizations.of(context)!.deliveries,
                                'deliveries',
                                sortBy,
                                sortAscending,
                                isDark,
                                CupertinoIcons.cube_box_fill,
                                (newSort, newAsc) {
                                  setSheetState(() {
                                    sortBy = newSort;
                                    sortAscending = newAsc;
                                  });
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Bids List
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: sortedBids.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      CupertinoIcons.car_detailed,
                                      size: 80,
                                      color: isDark
                                          ? Colors.white24
                                          : Colors.grey.shade300,
                                    ),
                                    const SizedBox(height: 20),
                                    Text(
                                      AppLocalizations.of(
                                        context,
                                      )!.waitingForDrivers1,
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      AppLocalizations.of(
                                        context,
                                      )!.driversWillAppearHereOnceTheyBid,
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: isDark
                                            ? Colors.white54
                                            : Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                itemCount: sortedBids.length,
                                itemBuilder: (context, index) {
                                  return _buildBidCardExpanded(
                                    sortedBids[index],
                                    isDark,
                                    context,
                                    rank: index + 1,
                                    isTop: index == 0,
                                  );
                                },
                              ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  // Helper to parse numeric values from dynamic types
  double _parseNumericValue(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  // Sort chip widget - Minimalist
  Widget _buildSortChip(
    String label,
    String value,
    String currentSort,
    bool currentAscending,
    bool isDark,
    IconData chipIcon,
    Function(String, bool) onTap,
  ) {
    final isSelected = currentSort == value;

    return GestureDetector(
      onTap: () {
        if (isSelected) {
          // Toggle direction
          onTap(value, !currentAscending);
        } else {
          // Select this sort, default ascending for price, descending for rating/deliveries
          onTap(value, value == 'price');
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? Colors.white : Colors.black)
              : (isDark ? const Color(0xFF1C1C1E) : Colors.black.withOpacity(0.05)),
          borderRadius: BorderRadius.circular(25),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              chipIcon,
              size: 14,
              color: isSelected
                  ? (isDark ? Colors.black : Colors.white)
                  : (isDark ? Colors.white54 : Colors.black54),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isSelected
                    ? (isDark ? Colors.black : Colors.white)
                    : (isDark ? Colors.white70 : Colors.black87),
              ),
            ),
            if (isSelected) ...[
              const SizedBox(width: 5),
              Icon(
                currentAscending
                    ? CupertinoIcons.arrow_up
                    : CupertinoIcons.arrow_down,
                size: 13,
                color: isDark ? Colors.black : Colors.white,
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Expanded Bid Card for Bottom Sheet - Minimalist Style
  Widget _buildBidCardExpanded(
    Map<String, dynamic> bid,
    bool isDark,
    BuildContext sheetContext, {
    int rank = 1,
    bool isTop = false,
  }) {
    final rawRating = bid['avg_rating'] ?? bid['rating'];
    final double? rating = rawRating is num
        ? rawRating.toDouble()
        : (rawRating is String ? double.tryParse(rawRating) : null);
    final deliveries =
        bid['completed_deliveries'] ?? bid['total_deliveries'] ?? 0;
    final int reviewCount = (bid['review_count'] is num)
        ? (bid['review_count'] as num).toInt()
        : int.tryParse(bid['review_count']?.toString() ?? '') ?? 0;
    final bool hasRating = rating != null && reviewCount > 0;
    final priceType = bid['price_type'] ?? 'total'; // total, per_km, per_mile

    String priceLabel;
    switch (priceType) {
      case 'per_km':
        priceLabel = '/km';
        break;
      case 'per_mile':
        priceLabel = '/mi';
        break;
      default:
        priceLabel = AppLocalizations.of(context)!.total;
    }

    return TradeRepublicCard(
      margin: const EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top badge row
          if (isTop)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(25),
                  topRight: Radius.circular(25),
                ),
              ),
              child: Row(
                children: [
                  const Icon(CupertinoIcons.star_fill, size: 14, color: Colors.green),
                  const SizedBox(width: 6),
                  Text(
                    AppLocalizations.of(context)!.recommended,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
          // Driver Info Row
          Row(
            children: [
              // Rank badge + Avatar
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 35,
                    backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.grey.shade200,
                    backgroundImage: bid['driver_image'] != null
                        ? NetworkImage(bid['driver_image'])
                        : null,
                    child: bid['driver_image'] == null
                        ? Icon(
                            CupertinoIcons.person_solid,
                            color: isDark ? Colors.white54 : Colors.grey.shade600,
                            size: 40,
                          )
                        : null,
                  ),
                  Positioned(
                    top: -4,
                    left: -4,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: isTop ? Colors.green : (isDark ? const Color(0xFF2C2C2E) : Colors.grey.shade400),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '$rank',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isTop ? Colors.white : (isDark ? Colors.black : Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              // Name & Stats
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bid['driver_username'] ?? AppLocalizations.of(context)!.driver,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        // Rating (only if reviews exist)
                        if (hasRating) ...[
                          Icon(
                            CupertinoIcons.star_fill,
                            color: Colors.amber,
                            size: 20,
                          ),
                          Text(
                            rating.toStringAsFixed(1),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                          ),
                          Text(
                            '($reviewCount)',
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark
                                  ? Colors.white60
                                  : Colors.grey.shade600,
                            ),
                          ),
                        ] else ...[
                          Icon(
                            CupertinoIcons.star,
                            color: isDark ? Colors.white38 : Colors.grey,
                            size: 20,
                          ),
                          Text(
                            AppLocalizations.of(context)!.noReviewsYet,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? Colors.white60
                                  : Colors.grey.shade600,
                            ),
                          ),
                        ],
                        // Deliveries
                        Icon(
                          CupertinoIcons.cube_box_fill,
                          color: isDark ? Colors.white54 : Colors.grey.shade600,
                          size: 20,
                        ),
                        Text(
                          AppLocalizations.of(context)!.deliveriesCount(deliveries is int ? deliveries : int.tryParse(deliveries.toString()) ?? 0),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: isDark
                                ? Colors.white70
                                : Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Price Row - Large & Prominent
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context)!.price,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white54 : Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '\$${_parseBidAmount(bid['bid_amount'])}',
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          priceLabel,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: isDark
                                ? Colors.white54
                                : Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (bid['estimated_delivery_time'] != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.etaLabel,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white54 : Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      AppLocalizations.of(context)!.etaMinutes(bid['estimated_delivery_time'].toString()),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                  ],
                ),
            ],
          ),

          // Vehicle & Message
          if (bid['vehicle_type'] != null || bid['message'] != null) ...[
            const SizedBox(height: 20),
            if (bid['vehicle_type'] != null)
              Row(
                children: [
                  Icon(
                    Icons.directions_car_rounded,
                    size: 20,
                    color: isDark ? Colors.white54 : Colors.grey.shade600,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    bid['vehicle_type'],
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white70 : Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            if (bid['message'] != null) ...[
              const SizedBox(height: 12),
              Text(
                '"${bid['message']}"',
                style: TextStyle(
                  fontSize: 15,
                  color: isDark ? Colors.white54 : Colors.grey.shade600,
                  fontStyle: FontStyle.italic,
                  height: 1.4,
                ),
              ),
            ],
          ],

          const SizedBox(height: 24),

          // Accept Button - Minimalist Black/White
          TradeRepublicButton(
            label: AppLocalizations.of(context)!.acceptDriver,
            onPressed: () {
              Navigator.pop(sheetContext);
              _acceptBid(bid);
            },
            width: double.infinity,
          ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Auction Completed UI
  Widget _buildAuctionCompletedUI(bool isDark) {
    final status = _currentOrder['status']?.toString().toLowerCase() ?? '';
    final isCompleted = status == 'completed';
    final isInTransitFlow =
        status == 'picked_up' || status == 'shipped' || status == 'delivered';
    final auctionStatus =
        (_currentOrder['auction_status'] ?? '').toString().toLowerCase();
    final awaitingDriverConfirm =
        _driverPendingConfirmation || auctionStatus == 'direct_assigned';
    final winningBidId =
        _auction?['winning_bid_id'] ?? _auction?['accepted_bid_id'];
    final winningBid = (winningBidId != null && _bids.isNotEmpty)
        ? _bids.firstWhere(
            (b) => b['id'].toString() == winningBidId.toString(),
            orElse: () => {},
          )
        : <String, dynamic>{};
    final driverName = winningBid['driver_username']?.toString() ?? '';
    final bidAmount = winningBid.isNotEmpty
        ? _parseNumericValue(winningBid['bid_amount'])
        : null;
    final rating = winningBid.isNotEmpty
        ? _parseNumericValue(winningBid['rating'])
        : null;
    final l10n = AppLocalizations.of(context)!;
    final headerTitle = awaitingDriverConfirm && !isInTransitFlow && !isCompleted
        ? 'Driver request sent'
        : l10n.driverSelected;
    final headerSubtitle = awaitingDriverConfirm && !isInTransitFlow && !isCompleted
        ? 'Awaiting confirmation from the selected driver'
        : 'Driver assignment is active for this order';
    final headerIcon = awaitingDriverConfirm && !isInTransitFlow && !isCompleted
        ? CupertinoIcons.clock_fill
        : CupertinoIcons.checkmark_circle_fill;
    final Color accent = awaitingDriverConfirm && !isInTransitFlow && !isCompleted
        ? const Color(0xFFFF9500)
        : TradeRepublicTheme.textColor(context);

    return Column(
      children: [
        TradeRepublicCard(
          backgroundColor: isDark
              ? Colors.white.withOpacity(0.04)
              : Colors.black.withOpacity(0.03),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: accent.withOpacity(isDark ? 0.22 : 0.14),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    headerIcon,
                    color: accent,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  headerTitle,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  headerSubtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
                if (driverName.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  TradeRepublicCard(
                    backgroundColor: isDark
                        ? Colors.white.withOpacity(0.03)
                        : Colors.black.withOpacity(0.02),
                    child: TradeRepublicListTile(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      leading: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: accent.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(
                          CupertinoIcons.car_fill,
                          color: accent,
                          size: 18,
                        ),
                      ),
                      title: driverName,
                      subtitle: [
                        if (bidAmount != null)
                          '\$${bidAmount.toStringAsFixed(2)}',
                        if (rating != null)
                          '⭐ ${rating.toStringAsFixed(1)}',
                      ].join('  ·  '),
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  Text(
                    l10n.aDriverHasBeenAssignedToYourOrder,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        // Shipping payment status — reuse the same compact row used in Delivery Info
        if (_shippingPaymentStatus != null && _shippingPaymentStatus!.isNotEmpty) ...[
          const SizedBox(height: 10),
          _buildShippingStatusRow(isDark),
        ],

        // Live location is available only after a driver is assigned.
        if (!isCompleted &&
            _currentOrder['driver_id'] != null &&
            _currentOrder['driver_id'].toString().isNotEmpty &&
            _currentOrder['driver_id'].toString() != 'null') ...[
          const SizedBox(height: 10),
          TradeRepublicButton(
            label: AppLocalizations.of(context)!.liveLocation,
            icon: const Icon(CupertinoIcons.location_fill, size: 16),
            onPressed: _showLiveLocation,
          ),
        ],
      ],
    );
  }



  bool _isChargingShipping = false;

  void _showShippingPaymentPicker(bool isDark, double? amount) async {
    final l10n = AppLocalizations.of(context)!;

    // ── 1. Fetch default payment method + saved methods ───────────────────
    String defaultType = 'card';
    Map<String, dynamic>? defaultMethod;

    try {
      final results = await Future.wait([
        ApiService.getPaymentDefaults(),
        ApiService.getPaymentMethods(),
      ]);
      final defaults = results[0] as Map<String, dynamic>;
      final methods = results[1] as List<Map<String, dynamic>>;

      final rawDefault = defaults['default_payment_shipping']?.toString() ?? 'card';

      // Check if the stored key matches a saved method ID
      final matchedById = methods.firstWhere(
        (m) => m['id']?.toString() == rawDefault,
        orElse: () => {},
      );
      if (matchedById.isNotEmpty) {
        defaultMethod = matchedById;
        defaultType = matchedById['type']?.toString() ?? 'card';
      } else if (rawDefault == 'wallet') {
        defaultType = 'wallet';
      } else {
        // Legacy: stored as type string — pick the first card of that type
        defaultType = rawDefault;
        final matchedByType = methods.firstWhere(
          (m) => m['type']?.toString() == rawDefault,
          orElse: () => {},
        );
        if (matchedByType.isNotEmpty) defaultMethod = matchedByType;
      }
    } catch (_) {}

    if (!mounted) return;

    // ── 2. Build display label for the default method ─────────────────────
    String defaultLabel;
    IconData defaultIcon;
    Color defaultColor;

    if (defaultType == 'wallet') {
      defaultLabel = l10n.moniooWallet;
      defaultIcon = CupertinoIcons.money_dollar_circle_fill;
      defaultColor = TradeRepublicTheme.textColor(context);
    } else if (defaultMethod != null) {
      final type = defaultMethod['type']?.toString() ?? 'card';
      if (type == 'card') {
        final brand = defaultMethod['brand']?.toString() ?? 'Card';
        final last4 = defaultMethod['last4']?.toString() ?? '••••';
        defaultLabel = '$brand ••$last4';
        defaultIcon = CupertinoIcons.creditcard_fill;
        defaultColor = TradeRepublicTheme.textColor(context);
      } else if (type == 'sepa') {
        final last4 = defaultMethod['iban_last4']?.toString() ?? '••••';
        defaultLabel = 'IBAN ••$last4';
        defaultIcon = CupertinoIcons.arrow_right_arrow_left_circle_fill;
        defaultColor = TradeRepublicTheme.textColor(context);
      } else if (type == 'ach') {
        final last4 = defaultMethod['account_number_last4']?.toString() ?? '••••';
        defaultLabel = 'ACH ••$last4';
        defaultIcon = CupertinoIcons.building_2_fill;
        defaultColor = TradeRepublicTheme.textColor(context);
      } else {
        defaultLabel = type.toUpperCase();
        defaultIcon = CupertinoIcons.creditcard_fill;
        defaultColor = TradeRepublicTheme.textColor(context);
      }
    } else {
      // No saved method — fall back to type label
      switch (defaultType) {
        case 'card':
          defaultLabel = l10n.payNowCard;
          defaultIcon = CupertinoIcons.creditcard_fill;
          defaultColor = TradeRepublicTheme.textColor(context);
          break;
        case 'sepa':
          defaultLabel = 'SEPA';
          defaultIcon = CupertinoIcons.arrow_right_arrow_left_circle_fill;
          defaultColor = TradeRepublicTheme.textColor(context);
          break;
        case 'ach':
          defaultLabel = 'ACH';
          defaultIcon = CupertinoIcons.building_2_fill;
          defaultColor = TradeRepublicTheme.textColor(context);
          break;
        default:
          defaultLabel = defaultType.toUpperCase();
          defaultIcon = CupertinoIcons.creditcard_fill;
          defaultColor = TradeRepublicTheme.textColor(context);
      }
    }

    final amountStr = amount != null ? '\$${amount.toStringAsFixed(2)}' : '';

    // ── 3. Show confirm sheet ─────────────────────────────────────────────
    if (!mounted) return;
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      useRootNavigator: true,
      maxHeight: MediaQuery.of(context).size.height * 0.6,
      child: StatefulBuilder(builder: (ctx, setLocal) {
        return Column(
          children: [
            // ── Large header ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pay Driver Now',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                        if (amountStr.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            amountStr,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFFF9500),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Scrollable content ────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Section label
                    TradeRepublicSectionHeader(
                      title: AppLocalizations.of(context)!.defaultPaymentMethod,
                      padding: const EdgeInsets.only(bottom: 10),
                    ),

                    // Default method card
                    TradeRepublicCard(
                      backgroundColor: defaultColor.withOpacity(0.07),
                      child: TradeRepublicListTile(
                        padding: _kSheetTilePadding,
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: defaultColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(defaultIcon, color: defaultColor, size: 20),
                        ),
                        title: defaultLabel,
                        subtitle: AppLocalizations.of(context)!.savedTapBelowToPay,
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: defaultColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            AppLocalizations.of(context)!.defaultLabel,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: defaultColor),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Pay now button
                    TradeRepublicButton(
                      label: amountStr.isNotEmpty ? 'Pay Driver Now · $amountStr' : 'Pay Driver Now',
                      backgroundColor: defaultColor,
                      onPressed: () {
                        Navigator.pop(ctx);
                        _chargeShipping(defaultType);
                      },
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        );
      }),
    );
  }

  Future<void> _chargeShipping(String paymentType) async {
    final orderId = widget.order['id'];
    final sellerUsername = widget.order['seller_username']?.toString();
    setState(() => _isChargingShipping = true);
    try {
      final result = await ApiService.chargeShippingPayment(orderId, paymentType: paymentType, sellerUsername: sellerUsername);
      if (!mounted) return;
      if (result['success'] == true) {
        if (result['deferred'] == true) {
          setState(() {
            _shippingPaymentStatus = 'deferred';
            _shippingPaymentType = result['payment_type']?.toString();
            _shippingPaymentDueDate = result['due_date']?.toString();
          });
          _showSuccessSnackBar('📅 ${result['message'] ?? 'Shipping deferred'}');
        } else {
          setState(() {
            _shippingPaymentStatus = 'paid';
            _shippingPaymentType = paymentType;
          });
          if (paymentType == 'wallet') {
            final newBal = (result['wallet_balance'] ?? 0.0);
            _showSuccessSnackBar(
              '💰 Paid from Monioo Wallet: \$${(result['amount'] ?? 0.0).toStringAsFixed(2)} — Balance: \$${newBal is num ? newBal.toStringAsFixed(2) : newBal}',
            );
          } else {
            _showSuccessSnackBar(
              '✅ Shipping paid: \$${(result['amount'] ?? 0.0).toStringAsFixed(2)} ••••${result['payment_method']?['last4'] ?? ''}',
            );
          }
        }
      } else if (result['error'] == 'insufficient_balance') {
        _showErrorDialog(
          AppLocalizations.of(context)!.insufficientBalance,
          '${result['message'] ?? 'Not enough funds.'}\n${AppLocalizations.of(context)!.topUpFirst}',
        );
      } else if (result['error'] == 'no_wallet') {
        _showErrorDialog(
          AppLocalizations.of(context)!.moniooWallet,
          result['message'] ?? 'No wallet found. Please top up first.',
        );
      } else if (result['error'] == 'no_payment_method') {
        _showErrorDialog(
          AppLocalizations.of(context)!.noPaymentMethodTitle,
          AppLocalizations.of(context)!.noPaymentMethodDescription,
        );
      } else {
        _showErrorDialog('Payment failed', result['message'] ?? result['error'] ?? 'Unknown error');
      }
    } catch (e) {
      if (mounted) _showErrorDialog('Payment failed', e.toString());
    } finally {
      if (mounted) setState(() => _isChargingShipping = false);
    }
  }

  void _showSuccessSnackBar(String message) {
    TopNotification.show(
      context,
      message: message,
      type: NotificationType.success,
    );
  }

  void _showErrorDialog(String title, String message) {
    TopNotification.show(
      context,
      title: title,
      message: message,
      type: NotificationType.error,
    );
  }

  // Compact row shown in Delivery Info – always visible when incoterms apply
  Widget _buildShippingStatusRow(bool isDark) {
    final l10n = AppLocalizations.of(context)!;
    final status = _shippingPaymentStatus ?? '';
    final incoterm = _shippingIncoterm;
    final cost = _shippingCostDue > 0 ? '\$${_shippingCostDue.toStringAsFixed(2)}' : null;
    final payNowLabel = cost != null ? 'Pay Driver Now $cost' : 'Pay Driver Now';
    final mono = isDark ? Colors.white : Colors.black;

    Color bgColor;
    Color iconColor;
    IconData icon;
    String title;
    String? subtitle;

    switch (status) {
      case 'paid':
        bgColor = mono.withOpacity(0.08);
        iconColor = mono;
        icon = CupertinoIcons.checkmark_seal_fill;
        title = l10n.shippingPaymentPaid;
        subtitle = [
          ?cost,
          if (_shippingPaymentType != null) _shippingPaymentType!.toUpperCase().replaceAll('_', ' '),
        ].join('  ·  ');
        break;
      case 'seller_pays':
        bgColor = mono.withOpacity(0.08);
        iconColor = mono;
        icon = CupertinoIcons.cube_box_fill;
        title = l10n.sellerPaysShipping;
        subtitle = [
          ?cost,
          ?incoterm,
        ].join('  ·  ');
        break;
      case 'deferred':
        bgColor = mono.withOpacity(0.08);
        iconColor = mono;
        icon = CupertinoIcons.calendar_badge_plus;
        title = l10n.shippingDeferredTitle;
        subtitle = [
          ?cost,
          if (_shippingPaymentDueDate != null) () {
            try {
              final d = DateTime.parse(_shippingPaymentDueDate!);
              return '${l10n.shippingDeferredDueOn} ${d.day}.${d.month}.${d.year}';
            } catch (_) { return _shippingPaymentDueDate!; }
          }(),
        ].whereType<String>().join('  ·  ');
        break;
      case 'pending':
      default:
        bgColor = mono.withOpacity(0.08);
        iconColor = mono;
        icon = CupertinoIcons.exclamationmark_circle_fill;
        title = l10n.shippingPaymentRequired;
        subtitle = [
          ?cost,
          ?incoterm,
        ].join('  ·  ');
    }

    // Only show Pay button to the party responsible per incoterms.
    // Decode the logged-in username from the JWT (zero network calls).
    final me = ApiService.currentUsername ?? '';
    final orderBuyer  = (_currentOrder['username']         ?? '').toString();
    final orderSeller = (_currentOrder['seller_username']   ?? '').toString();
    final isBuyer  = me.isNotEmpty && me == orderBuyer;
    final isSeller = me.isNotEmpty && me == orderSeller;
    final canPayNow = (status == 'pending'     && isBuyer)
                   || (status == 'seller_pays' && isSeller);

    return TradeRepublicCard(
      backgroundColor: bgColor,
      child: TradeRepublicListTile(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.13),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: iconColor, size: 18),
        ),
        title: title,
        titleColor: status == 'pending' ? iconColor : null,
        subtitle: subtitle.isEmpty ? null : subtitle,
        trailing: canPayNow
            ? GestureDetector(
                onTap: _isChargingShipping ? null : () => _showShippingPaymentPicker(isDark, _shippingCostDue > 0 ? _shippingCostDue : null),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _isChargingShipping ? Colors.grey : (isDark ? Colors.white : Colors.black),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _isChargingShipping
                      ? const SizedBox(width: 14, height: 14, child: CupertinoActivityIndicator(color: Colors.white))
                      : Text(
                          payNowLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              )
            : null,
      ),
    );
  }

  Widget _buildDeliveryInfoSection(bool isDark) {
    final status = _currentOrder['status']?.toLowerCase() ?? '';
    final isDelivered = status == 'delivered';
    final isCompleted = status == 'completed';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
          TradeRepublicSectionHeader(
            title: AppLocalizations.of(context)!.deliveryInformation1,
            padding: const EdgeInsets.only(bottom: 14),
          ),

          // Delivery countdown or delivered time
          if (isDelivered && _currentOrder['received_date'] != null)
            TradeRepublicCard(
              backgroundColor: (isDark ? Colors.white : Colors.black).withOpacity(0.08),
              child: TradeRepublicListTile(
                padding: _kSheetTilePadding,
                title: _formatDate(_currentOrder['received_date']),
                subtitle: AppLocalizations.of(context)!.delivered,
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white : Colors.black,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(CupertinoIcons.checkmark_alt, color: isDark ? Colors.black : Colors.white, size: 20),
                ),
              ),
            )
          else
            TradeRepublicCard(
              child: TradeRepublicListTile(
                padding: _kSheetTilePadding,
                title: _getDeliveryCountdown(),
                subtitle: AppLocalizations.of(context)!.estimatedDelivery,
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: TradeRepublicTheme.textColor(context).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    CupertinoIcons.clock,
                    color: TradeRepublicTheme.textColor(context),
                    size: 20,
                  ),
                ),
              ),
            ),

          // Delivery details - only show shipped date if not delivered
          if (!isDelivered && _currentOrder['shipped_date'] != null) ...[
            const SizedBox(height: 8),
            TradeRepublicCard(
              child: TradeRepublicListTile(
                padding: _kSheetTilePaddingCompact,
                title: _formatDate(_currentOrder['shipped_date']),
                subtitle: AppLocalizations.of(context)!.shippedDate,
                leading: Icon(
                  CupertinoIcons.cube_box,
                  size: 18,
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
              ),
            ),
          ],

          // Shipping payment status row — always visible when incoterms apply
          if (_shippingPaymentStatus != null && _shippingPaymentStatus!.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildShippingStatusRow(isDark),
          ],

          // Live location is available only after a driver is assigned.
          if (!isCompleted &&
              _currentOrder['driver_id'] != null &&
              _currentOrder['driver_id'].toString().isNotEmpty &&
              _currentOrder['driver_id'].toString() != 'null') ...[
            const SizedBox(height: 8),
            TradeRepublicButton(
              label: AppLocalizations.of(context)!.liveLocation,
              icon: const Icon(CupertinoIcons.location_fill, size: 16),
              onPressed: _showLiveLocation,
            ),
          ],
        ],
    );
  }

  Widget _buildItemsSection(bool isDark, List<dynamic> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TradeRepublicSectionHeader(
          title: AppLocalizations.of(context)!.orderItemsCount(items.length),
          padding: const EdgeInsets.only(bottom: 12),
        ),
        TradeRepublicCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: List.generate(items.length, (i) {
              return Column(
                children: [
                  if (i > 0) const TradeRepublicDivider(margin: EdgeInsets.zero),
                  _buildItemCard(isDark, items[i] as Map<String, dynamic>),
                ],
              );
            }),
          ),
        ),

        // Incoterm display if available
        if (_shippingIncoterm != null && _shippingIncoterm!.isNotEmpty) ...[
          const SizedBox(height: 10),
          TradeRepublicCard(
            child: TradeRepublicListTile(
              padding: _kSheetTilePaddingCompact,
              title: _shippingIncoterm!.toUpperCase(),
              subtitle: AppLocalizations.of(context)!.incoterm,
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: TradeRepublicTheme.textColor(context).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  CupertinoIcons.hammer_fill,
                  color: TradeRepublicTheme.textColor(context),
                  size: 20,
                ),
              ),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _buyerPaysShipping
                      ? const Color(0xFFFF9500).withOpacity(0.12)
                      : TradeRepublicTheme.textColor(context).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _buyerPaysShipping
                      ? AppLocalizations.of(context)!.buyerPaysShipping
                      : AppLocalizations.of(context)!.sellerPaysShipping,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _buyerPaysShipping
                        ? const Color(0xFFFF9500)
                        : TradeRepublicTheme.textColor(context),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildItemCard(bool isDark, Map<String, dynamic> item) {
    final imageUrl = item['image_url']?.toString() ?? '';
    final name = item['name'] ?? item['product_name'] ?? item['title'] ??
        AppLocalizations.of(context)!.unknownProduct;
    final qty = _parseQuantity(item['quantity'] ?? item['qty'] ?? item['amount']);
    final unit = _getItemUnit(item);

    return TradeRepublicListTile(
      padding: _kSheetTilePaddingCompact,
      title: name.toString(),
      subtitle: AppLocalizations.of(context)!.qtyWithUnit(qty.toStringAsFixed(2), unit),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.black.withOpacity(0.04),
          borderRadius: BorderRadius.circular(12),
          image: imageUrl.isNotEmpty
              ? DecorationImage(
                  image: imageUrl.startsWith('data:image')
                      ? MemoryImage(base64Decode(imageUrl.split(',')[1]))
                      : NetworkImage(imageUrl) as ImageProvider,
                  fit: BoxFit.cover,
                )
              : null,
        ),
        child: imageUrl.isEmpty
            ? Icon(
                CupertinoIcons.bag,
                color: isDark ? Colors.white38 : Colors.black38,
                size: 20,
              )
            : null,
      ),
      trailing: Text(
        _formatCurrency(_parsePrice(item['price'])),
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: isDark ? Colors.white : Colors.black,
          letterSpacing: -0.3,
        ),
      ),
    );
  }

  Widget _buildAddressSection(bool isDark, Map<String, dynamic> address) {
    String pickString(List<dynamic> values) {
      for (final v in values) {
        final s = (v ?? '').toString().trim();
        if (s.isNotEmpty && s.toLowerCase() != 'null') return s;
      }
      return '';
    }

    final displayName = pickString([
      address['name'],
      address['full_name'],
      address['username'],
      address['first_name'],
      address['user_name'],
    ]);

    final street = pickString([
      address['street'],
      address['address_line1'],
      address['line1'],
      address['address'],
      address['full_address'],
    ]);
    final houseNumber = pickString([
      address['house_number'],
      address['houseNo'],
    ]);
    final fullAddress = [street, houseNumber].where((s) => s.isNotEmpty).join(' ').trim();

    final city = pickString([address['city'], address['town']]);
    final zipCode = pickString([
      address['zipCode'],
      address['zip_code'],
      address['postal_code'],
      address['postalCode'],
      address['zip'],
      address['plz'],
    ]);
    final country = pickString([address['country']]);

    final hasNoAddress =
        fullAddress.isEmpty && city.isEmpty && zipCode.isEmpty && country.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            AppLocalizations.of(context)!.deliveryAddress.toUpperCase(),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
        ),
        if (hasNoAddress)
          TradeRepublicCard(
            child: TradeRepublicListTile(
              padding: _kSheetTilePadding,
              title: AppLocalizations.of(context)!.addressInformationNotAvailable,
              leading: Icon(CupertinoIcons.exclamationmark_triangle_fill,
                  color: isDark ? Colors.white70 : Colors.black87, size: 20),
              titleColor: isDark ? Colors.white : Colors.black,
            ),
          )
        else
          TradeRepublicCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                if (displayName.isNotEmpty)
                  TradeRepublicListTile(
                    padding: _kSheetTilePaddingCompact,
                    title: displayName,
                    subtitle: AppLocalizations.of(context)!.recipient,
                    leading: Icon(CupertinoIcons.person,
                        size: 18,
                        color: isDark ? Colors.white54 : Colors.black45),
                  ),
                if (fullAddress.isNotEmpty) ...[
                  if (displayName.isNotEmpty)
                    const TradeRepublicDivider(margin: EdgeInsets.zero),
                  TradeRepublicListTile(
                    padding: _kSheetTilePaddingCompact,
                    title: fullAddress,
                    subtitle: AppLocalizations.of(context)!.street,
                    leading: Icon(CupertinoIcons.location,
                        size: 18,
                        color: isDark ? Colors.white54 : Colors.black45),
                  ),
                ],
                if (city.isNotEmpty || zipCode.isNotEmpty) ...[
                  const TradeRepublicDivider(margin: EdgeInsets.zero),
                  TradeRepublicListTile(
                    padding: _kSheetTilePaddingCompact,
                    title: '$zipCode $city'.trim(),
                    subtitle: AppLocalizations.of(context)!.city,
                    leading: Icon(CupertinoIcons.building_2_fill,
                        size: 18,
                        color: isDark ? Colors.white54 : Colors.black45),
                  ),
                ],
                if (country.isNotEmpty) ...[
                  const TradeRepublicDivider(margin: EdgeInsets.zero),
                  TradeRepublicListTile(
                    padding: _kSheetTilePaddingCompact,
                    title: country,
                    subtitle: AppLocalizations.of(context)!.country,
                    leading: Icon(CupertinoIcons.flag,
                        size: 18,
                        color: isDark ? Colors.white54 : Colors.black45),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildPaymentSection(bool isDark) {
    final totalAmount = _parsePrice(_currentOrder['total_amount']);
    final paymentId =
        _currentOrder['payment_intent_id'] ?? _currentOrder['paymentIntentId'];
    final actualType = _getActualPaymentType();
    final methodColor = _getPaymentMethodColor(actualType);
    final isBankTransfer = actualType == 'ach' || actualType == 'sepa' || actualType == 'wire';
    final rawPaymentTermsDetails = _currentOrder['payment_terms_details'];

    Map<String, dynamic>? paymentTermsDetails;
    if (rawPaymentTermsDetails is Map<String, dynamic>) {
      paymentTermsDetails = rawPaymentTermsDetails;
    } else if (rawPaymentTermsDetails is String &&
        rawPaymentTermsDetails.trim().isNotEmpty) {
      try {
        final decoded = json.decode(rawPaymentTermsDetails);
        if (decoded is Map<String, dynamic>) {
          paymentTermsDetails = decoded;
        }
      } catch (_) {}
    }

    final businessInfo = paymentTermsDetails?['business_info'];
    final verificationStatusRaw =
        (businessInfo is Map<String, dynamic>
                ? businessInfo['verification_status']
                : null)
            ?.toString()
            .toLowerCase() ??
        '';

    final verificationStatus = verificationStatusRaw == 'approved'
        ? 'Accepted'
        : verificationStatusRaw == 'rejected'
        ? 'Rejected'
        : verificationStatusRaw == 'pending'
        ? 'Pending'
        : null;
    final paymentReceived = _currentOrder['payment_received'] == true ||
      _currentOrder['status']?.toString().toLowerCase() == 'completed';
    final paymentStatusLabel = paymentReceived ? 'PAID' : 'OPEN';
    final paymentStatusColor = isDark ? Colors.white : Colors.black;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            AppLocalizations.of(context)!.payment.toUpperCase(),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Main payment summary card ──
            TradeRepublicCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  // Total amount row
                  TradeRepublicListTile(
                    padding: _kSheetTilePadding,
                    title: _formatCurrency(totalAmount),
                    subtitle: AppLocalizations.of(context)!.totalAmount,
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: paymentStatusColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        paymentReceived
                            ? CupertinoIcons.checkmark_circle_fill
                            : CupertinoIcons.time,
                        color: Colors.black,
                        size: 20,
                      ),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: paymentStatusColor.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        paymentStatusLabel,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: paymentStatusColor, letterSpacing: 0.5),
                      ),
                    ),
                  ),
                  if (paymentTermsDetails == null) ...[
                    const TradeRepublicDivider(margin: EdgeInsets.zero),
                    // Payment method row
                    TradeRepublicListTile(
                      padding: _kSheetTilePadding,
                      title: _getPaymentMethodName(actualType),
                      subtitle: AppLocalizations.of(context)!.paymentMethod,
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: methodColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(_getPaymentMethodIcon(actualType), color: methodColor, size: 20),
                      ),
                    ),
                  ],
                  if (paymentId != null && paymentTermsDetails == null) ...[
                    const TradeRepublicDivider(margin: EdgeInsets.zero),
                    TradeRepublicListTile(
                      padding: _kSheetTilePadding,
                      title: paymentId.length > 20 ? '${paymentId.substring(0, 17)}...' : paymentId,
                      subtitle: AppLocalizations.of(context)!.paymentId,
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: paymentId));
                        TopNotification.info(context, AppLocalizations.of(context)!.paymentIdCopiedToClipboard);
                      },
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1C1C1E) : Colors.black.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(CupertinoIcons.doc_text, size: 18, color: isDark ? Colors.white54 : Colors.black45),
                      ),
                      trailing: Icon(CupertinoIcons.doc_on_doc, size: 15, color: isDark ? Colors.white38 : Colors.black38),
                    ),
                  ],
                  // Verification badge inside card
                  if (verificationStatus != null && paymentTermsDetails == null) ...[
                    const TradeRepublicDivider(margin: EdgeInsets.zero),
                    TradeRepublicListTile(
                      padding: _kSheetTilePaddingCompact,
                      title: 'Verification: $verificationStatus',
                      leading: Icon(
                        verificationStatus == 'Accepted'
                            ? CupertinoIcons.checkmark_seal_fill
                            : verificationStatus == 'Rejected'
                            ? CupertinoIcons.xmark_octagon_fill
                            : CupertinoIcons.time_solid,
                        size: 20,
                        color: verificationStatus == 'Accepted'
                            ? Colors.green
                            : verificationStatus == 'Rejected'
                            ? Colors.red
                            : Colors.orange,
                      ),
                      titleColor: verificationStatus == 'Accepted'
                          ? Colors.green
                          : verificationStatus == 'Rejected'
                          ? Colors.red
                          : Colors.orange,
                    ),
                  ],
                ],
              ),
            ),

            // Bank transfer details card (SEPA / ACH / Wire)
            if (isBankTransfer && paymentTermsDetails == null) ...[
              const SizedBox(height: 12),
              _buildBankTransferDetails(isDark, actualType),
            ],

              // ========== NET 30/60 PAYMENT TERMS DETAILS ==========
              if (paymentTermsDetails != null) ...[
                const SizedBox(height: 12),

                // --- Net Terms Header ---
                TradeRepublicCard(
                  backgroundColor: TradeRepublicTheme.textColor(context).withOpacity(isDark ? 0.12 : 0.07),
                  child: TradeRepublicListTile(
                    padding: EdgeInsets.zero,
                    title: 'Net ${paymentTermsDetails['term_days'] ?? '30'}',
                    subtitle: AppLocalizations.of(context)!.paymentTerms,
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF3A3A3A)
                            : const Color(0xFF2C2C2C),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        CupertinoIcons.doc_text_fill,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    trailing: verificationStatus != null
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: (verificationStatus == 'Accepted'
                                      ? Colors.green
                                      : verificationStatus == 'Rejected'
                                      ? Colors.red
                                      : Colors.orange)
                                  .withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  verificationStatus == 'Accepted'
                                      ? CupertinoIcons.checkmark_circle_fill
                                      : verificationStatus == 'Rejected'
                                      ? CupertinoIcons.xmark_circle_fill
                                      : CupertinoIcons.clock_fill,
                                  size: 12,
                                  color: verificationStatus == 'Accepted'
                                      ? Colors.green
                                      : verificationStatus == 'Rejected'
                                      ? Colors.red
                                      : Colors.orange,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  verificationStatus == 'Accepted' ? AppLocalizations.of(context)!.paid : verificationStatus,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: verificationStatus == 'Accepted'
                                        ? Colors.green
                                        : verificationStatus == 'Rejected'
                                        ? Colors.red
                                        : Colors.orange,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : null,
                  ),
                ),

                // --- Due Date Card ---
                if (paymentTermsDetails['due_date'] != null) ...[
                  const SizedBox(height: 10),
                  Builder(builder: (context) {
                    final dueDateStr = paymentTermsDetails?['due_date']?.toString() ?? '';
                    final dueDate = DateTime.tryParse(dueDateStr);
                    final remaining = dueDate?.difference(DateTime.now());
                    final isOverdue = remaining != null && remaining.isNegative;
                    final isUrgent = remaining != null && !remaining.isNegative && remaining.inDays < 7;
                    final daysLeft = remaining?.inDays ?? 0;
                    final statusColor = isOverdue
                        ? Colors.red
                        : isUrgent
                        ? Colors.orange
                        : TradeRepublicTheme.textColor(context);

                    return TradeRepublicCard(
                      backgroundColor: statusColor.withOpacity(isDark ? 0.10 : 0.06),
                      child: TradeRepublicListTile(
                        padding: EdgeInsets.zero,
                        title: _formatPaymentTermsDate(paymentTermsDetails?['due_date']),
                        subtitle: AppLocalizations.of(context)!.dueDate,
                        titleColor: statusColor,
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            isOverdue ? CupertinoIcons.exclamationmark_triangle_fill : CupertinoIcons.calendar,
                            color: statusColor,
                            size: 20,
                          ),
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            isOverdue ? 'Overdue' : daysLeft == 0 ? 'Today' : '${daysLeft}d left',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor),
                          ),
                        ),
                      ),
                    );
                  }),
                ],

                // --- Business Info Card ---
                if (businessInfo is Map<String, dynamic>) ...[
                  const SizedBox(height: 10),
                  TradeRepublicCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TradeRepublicListTile(
                          padding: _kSheetTilePaddingCompact,
                          title: businessInfo['business_name']?.toString() ?? AppLocalizations.of(context)!.business,
                          subtitle: AppLocalizations.of(context)!.business,
                          leading: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: TradeRepublicTheme.textColor(context).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              CupertinoIcons.building_2_fill,
                              size: 18,
                              color: TradeRepublicTheme.textColor(context),
                            ),
                          ),
                        ),
                        if (businessInfo['tax_id'] != null || businessInfo['email'] != null || businessInfo['phone'] != null) ...[
                          const TradeRepublicDivider(margin: EdgeInsets.zero),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (businessInfo['tax_id'] != null)
                                  _buildInfoChip(icon: CupertinoIcons.number, text: businessInfo['tax_id'].toString(), isDark: isDark),
                                if (businessInfo['email'] != null)
                                  _buildInfoChip(icon: CupertinoIcons.mail, text: businessInfo['email'].toString(), isDark: isDark),
                                if (businessInfo['phone'] != null)
                                  _buildInfoChip(icon: CupertinoIcons.phone, text: businessInfo['phone'].toString(), isDark: isDark),
                              ],
                            ),
                          ),
                        ],
                        if (businessInfo['street'] != null || businessInfo['city'] != null) ...[
                          const TradeRepublicDivider(margin: EdgeInsets.zero),
                          TradeRepublicListTile(
                            padding: _kSheetTilePaddingCompact,
                            title: [
                              if (businessInfo['street'] != null)
                                '${businessInfo['street']}${businessInfo['house_number'] != null ? ' ${businessInfo['house_number']}' : ''}',
                              if (businessInfo['postal_code'] != null || businessInfo['city'] != null)
                                '${businessInfo['postal_code'] ?? ''} ${businessInfo['city'] ?? ''}'.trim(),
                              if (businessInfo['country'] != null) businessInfo['country'].toString(),
                            ].where((s) => s.isNotEmpty).join(', '),
                            leading: Icon(CupertinoIcons.location_solid, size: 18, color: isDark ? Colors.white54 : Colors.black45),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],

                // --- Virtual Account Card ---
                if (paymentTermsDetails['virtual_account_number'] != null) ...[
                  const SizedBox(height: 10),
                  TradeRepublicCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TradeRepublicListTile(
                          padding: _kSheetTilePaddingCompact,
                          title: AppLocalizations.of(context)!.virtualAchAccount,
                          leading: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: TradeRepublicTheme.textColor(context).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              CupertinoIcons.creditcard,
                              size: 18,
                              color: TradeRepublicTheme.textColor(context),
                            ),
                          ),
                        ),
                        const TradeRepublicDivider(margin: EdgeInsets.zero),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(
                            children: [
                              _buildCopyableField(
                                label: AppLocalizations.of(context)!.accountNumber,
                                value: paymentTermsDetails['virtual_account_number'].toString(),
                                isDark: isDark,
                              ),
                              if (paymentTermsDetails['virtual_routing_number'] != null) ...[
                                const TradeRepublicDivider(margin: EdgeInsets.zero),
                                _buildCopyableField(
                                  label: AppLocalizations.of(context)!.routingNumber,
                                  value: paymentTermsDetails['virtual_routing_number'].toString(),
                                  isDark: isDark,
                                ),
                              ],
                              if (paymentTermsDetails['account_holder'] != null) ...[
                                const TradeRepublicDivider(margin: EdgeInsets.zero),
                                _buildCopyableField(
                                  label: AppLocalizations.of(context)!.accountHolder,
                                  value: paymentTermsDetails['account_holder'].toString(),
                                  isDark: isDark,
                                  copyable: false,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // --- Over Limit Fee ---
                if (paymentTermsDetails['is_over_limit'] == true &&
                    paymentTermsDetails['over_limit_fee'] != null &&
                    (paymentTermsDetails['over_limit_fee'] as num) > 0) ...[
                  const SizedBox(height: 10),
                  TradeRepublicCard(
                    backgroundColor: Colors.orange.withOpacity(isDark ? 0.10 : 0.07),
                    child: TradeRepublicListTile(
                      padding: EdgeInsets.zero,
                      title: _formatCurrency(paymentTermsDetails['over_limit_fee']),
                      subtitle: AppLocalizations.of(context)!.overLimitFee,
                      titleColor: Colors.orange,
                      leading: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(CupertinoIcons.exclamationmark_triangle_fill, color: Colors.orange, size: 18),
                      ),
                    ),
                  ),
                ],

                // --- Late Fee Schedule ---
                if (paymentTermsDetails['late_fee_schedule'] != null) ...[
                  const SizedBox(height: 10),
                  TradeRepublicCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TradeRepublicListTile(
                          padding: _kSheetTilePaddingCompact,
                          title: AppLocalizations.of(context)!.lateFeeSchedule,
                          leading: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(CupertinoIcons.clock, size: 18, color: Colors.red.shade400),
                          ),
                        ),
                        const TradeRepublicDivider(margin: EdgeInsets.zero),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                          child: Column(
                            children: _buildLateFeeScheduleItems(
                              paymentTermsDetails['late_fee_schedule'],
                              isDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
            ],
          ],
        ),
      ],
    );
  }

  // Helper method to get payment method icon
  IconData _getPaymentMethodIcon(String paymentMethod) {
    switch (paymentMethod.toLowerCase()) {
      case 'card':
        return CupertinoIcons.creditcard;
      case 'sepa':
      case 'sepa_debit':
        return CupertinoIcons.building_2_fill;
      case 'ach':
      case 'us_bank_account':
        return CupertinoIcons.money_dollar_circle_fill;
      case 'wire':
      case 'wire_transfer':
        return CupertinoIcons.arrow_right_arrow_left;
      case 'payment_30_days':
      case 'payment_60_days':
        return CupertinoIcons.clock;
      default:
        return CupertinoIcons.creditcard;
    }
  }

  // Helper method to get payment method display name
  String _getPaymentMethodName(String paymentMethod) {
    switch (paymentMethod.toLowerCase()) {
      case 'card':
        return AppLocalizations.of(context)!.creditCard;
      case 'sepa':
      case 'sepa_debit':
        return AppLocalizations.of(context)!.sepaDirectDebit;
      case 'ach':
      case 'us_bank_account':
        return AppLocalizations.of(context)!.achBankTransfer;
      case 'wire':
      case 'wire_transfer':
        return AppLocalizations.of(context)!.wireTransfer;
      case 'payment_30_days':
        return AppLocalizations.of(context)!.paymentTerms30Days;
      case 'payment_60_days':
        return AppLocalizations.of(context)!.paymentTerms60Days;
      default:
        return paymentMethod.replaceAll('_', ' ').toUpperCase();
    }
  }

  /// Detects actual payment type from order detail fields first,
  /// falling back to payment_method_type. Fixes cases where the stored
  /// type may be incorrect (e.g. shows 'card' for ACH orders).
  String _getActualPaymentType() {
    final stored =
        _currentOrder['payment_method_type']?.toString().toLowerCase() ?? '';
    if (_currentOrder['ach_details'] != null ||
        stored == 'ach' ||
        stored == 'us_bank_account') {
      return 'ach';
    }
    if (_currentOrder['sepa_details'] != null ||
        stored == 'sepa' ||
        stored == 'sepa_debit') {
      return 'sepa';
    }
    if (_currentOrder['wire_details'] != null ||
        stored == 'wire' ||
        stored == 'wire_transfer') {
      return 'wire';
    }
    return stored;
  }

  /// Returns the brand color for each payment method.
  Color _getPaymentMethodColor(String paymentType) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? Colors.white : Colors.black;
  }

  // Helper: Small info chip (tag-style)
  Widget _buildInfoChip({
    required IconData icon,
    required String text,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1C1C1E)
            : Colors.black.withOpacity(0.04),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 13,
            color: isDark ? Colors.white.withOpacity(0.45) : Colors.black38,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // Helper: Copyable field row (monospace value, tap to copy)
  Widget _buildCopyableField({
    required String label,
    required String value,
    required bool isDark,
    bool copyable = true,
  }) {
    return TradeRepublicListTile(
      padding: _kSheetTilePaddingCompact,
      title: value,
      subtitle: label,
      leading: copyable
          ? Icon(CupertinoIcons.doc_on_doc, size: 16, color: isDark ? Colors.white38 : Colors.black38)
          : Icon(CupertinoIcons.info_circle, size: 16, color: isDark ? Colors.white38 : Colors.black38),
      trailing: copyable
          ? Icon(CupertinoIcons.doc_on_clipboard, size: 15, color: isDark ? Colors.white30 : Colors.black26)
          : null,
      onTap: copyable
          ? () {
              Clipboard.setData(ClipboardData(text: value));
              TopNotification.info(context, '$label copied');
            }
          : null,
    );
  }

  // Helper: Format date for payment terms display
  String _formatPaymentTermsDate(dynamic dateValue) {
    if (dateValue == null) return 'N/A';
    DateTime? date;
    if (dateValue is String) {
      date = DateTime.tryParse(dateValue);
    } else if (dateValue is DateTime) {
      date = dateValue;
    }
    if (date == null) return dateValue.toString();

    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  // Helper: Build late fee schedule items (modern card-style)
  List<Widget> _buildLateFeeScheduleItems(
    dynamic schedule,
    bool isDark,
  ) {
    if (schedule == null || schedule is! Map) return [];

    final items = <Widget>[];

    void addItem(String key, IconData icon, Color color) {
      final entry = schedule[key];
      if (entry == null || entry is! Map) return;
      final day = entry['day']?.toString() ?? '';
      final action = entry['action']?.toString() ?? '';
      final fee = entry['fee_percent'];
      final feeStr = fee != null && fee != 0 ? '+$fee%' : '';

      items.add(
        TradeRepublicListTile(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          title: action,
          subtitle: 'Day $day${feeStr.isNotEmpty ? ' · $feeStr fee' : ''}',
          titleColor: color,
          leading: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 15, color: color),
          ),
        ),
      );
    }

    final mono = isDark ? Colors.white : Colors.black;
    addItem('first_reminder', CupertinoIcons.exclamationmark_triangle, mono);
    addItem('account_suspended', CupertinoIcons.nosign, mono);
    addItem('legal_action', CupertinoIcons.shield_fill, mono);

    return items;
  }

  Widget _buildContactSection(bool isDark) {
    final status = _currentOrder['status']?.toString().toLowerCase() ?? '';
    final showDriver = status == 'picked_up' || status == 'shipped';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            'CONTACT',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
        ),
        TradeRepublicCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              _buildContactButton(
                isDark: isDark,
                icon: CupertinoIcons.person_crop_circle,
                label: AppLocalizations.of(context)!.contactSeller,
                subtitle: AppLocalizations.of(context)!.sendMessage,
                color: isDark ? Colors.white : Colors.black,
                onTap: () => _contactSeller(),
              ),
              if (showDriver) ...[
                const TradeRepublicDivider(margin: EdgeInsets.zero),
                _buildContactButton(
                  isDark: isDark,
                  icon: CupertinoIcons.car_detailed,
                  label: AppLocalizations.of(context)!.contactDriver,
                  subtitle: AppLocalizations.of(context)!.liveLocation,
                  color: isDark ? Colors.white : Colors.black,
                  onTap: () => _contactDriver(),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildContactButton({
    required bool isDark,
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return TradeRepublicListTile.navigation(
      title: label,
      subtitle: subtitle,
      padding: _kSheetTilePaddingCompact,
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 18, color: color),
      ),
      onTap: onTap,
    );
  }

  void _contactSeller() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TradeRepublicSectionHeader(
              title: AppLocalizations.of(context)!.contactSeller,
              subtitle: AppLocalizations.of(context)!.getInTouchDirectly,
              padding: const EdgeInsets.only(bottom: 24),
            ),
            TradeRepublicListTile.navigation(
              title: AppLocalizations.of(context)!.sendMessage,
              subtitle: AppLocalizations.of(context)!.quickAndSecureMessaging,
              leading: Icon(
                CupertinoIcons.bubble_left,
                size: 20,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
              onTap: () {
                Navigator.pop(context);
                _showMessageModal('seller');
              },
            ),
            TradeRepublicDivider.spaced(),
            TradeRepublicListTile(
              title: _getSellerPhone() ?? AppLocalizations.of(context)!.phoneNumber,
              subtitle: _getSellerPhone() != null
                  ? AppLocalizations.of(context)!.tapToCall
                  : AppLocalizations.of(context)!.notAvailable1,
              leading: Icon(
                CupertinoIcons.phone,
                size: 20,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
              onTap: _getSellerPhone() != null ? () { Navigator.pop(context); } : null,
            ),
          ],
        ),
      ),
    );
  }

  // Helper method to get seller phone number
  String? _getSellerPhone() {
    return _currentOrder['seller_phone'] ??
        _currentOrder['phone'] ??
        _currentOrder['contact_phone'];
  }

  // Modern contact option widget (legacy - kept for potential reuse)
  Widget _buildModernContactOption({
    required bool isDark,
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Color> gradient,
    VoidCallback? onTap,
  }) {
    return TradeRepublicListTile.navigation(
      title: title,
      subtitle: subtitle,
      leading: Icon(icon, size: 20),
      onTap: onTap ?? () {},
    );
  }

  void _contactDriver() {
    // Show contact options for driver
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: _buildContactOptionsModal(
        title: AppLocalizations.of(context)!.contactDriver,
        icon: CupertinoIcons.car_detailed,
        color: const Color(0xFFFF9500),
      ),
    );
  }

  Widget _buildContactOptionsModal({
    required String title,
    required IconData icon,
    required Color color,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TradeRepublicSectionHeader(
            title: title,
            subtitle: AppLocalizations.of(context)!.getInTouchDirectly,
            padding: const EdgeInsets.only(bottom: 24),
          ),
          // Phone Number
          TradeRepublicListTile(
            title: () {
              String? phoneNumber;
              if (title == AppLocalizations.of(context)!.contactDriver) {
                phoneNumber = _currentOrder['driver_phone'];
              } else {
                phoneNumber = _currentOrder['seller_phone'];
              }
              return phoneNumber ?? AppLocalizations.of(context)!.noPhoneNumber;
            }(),
            subtitle: AppLocalizations.of(context)!.tapToCall,
            leading: Icon(
              CupertinoIcons.phone,
              size: 20,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
            onTap: null,
          ),
          TradeRepublicDivider.spaced(),
          // Message Option
          TradeRepublicListTile.navigation(
            title: AppLocalizations.of(context)!.message,
            leading: Icon(
              CupertinoIcons.bubble_left,
              size: 20,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
            onTap: () {
              Navigator.pop(context);
              _showMessageModal(
                title == AppLocalizations.of(context)!.contactDriver ? 'driver' : 'seller',
              );
            },
          ),
        ],
      ),
    );
  }

  void _showMessageModal(String recipientType) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final TextEditingController messageController = TextEditingController();
    bool isSending = false;

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: Builder(
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setModalState) => Container(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              decoration: BoxDecoration(
                color: isDark ? Colors.black : Colors.white,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(25),
                          ),

                          child: Icon(
                            CupertinoIcons.bubble_left,
                            color: Colors.blue,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                AppLocalizations.of(context)!.sendMessage,
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: isDark ? Colors.white : Colors.black,
                                ),
                              ),
                              Text(
                                'to ${recipientType == 'driver' ? 'Driver' : 'Seller'}',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isDark
                                      ? Colors.grey[400]
                                      : Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Message input
                    TradeRepublicTextField.multiline(
                      controller: messageController,
                      hintText: AppLocalizations.of(context)!.typeYourMessage,
                      maxLines: 4,
                    ),

                    const SizedBox(height: 24),

                    // Send button
                    TradeRepublicButton(
                      label: AppLocalizations.of(context)!.sendMessage,
                      onPressed: isSending
                          ? null
                          : () async {
                              if (messageController.text.trim().isEmpty) {
                                TopNotification.error(
                                  context,
                                  AppLocalizations.of(
                                    context,
                                  )!.pleaseEnterAMessage,
                                );
                                return;
                              }

                              setModalState(() {
                                isSending = true;
                              });

                              try {
                                // Send message via API
                                await ApiService.sendMessage(
                                  orderId: _currentOrder['id'],
                                  recipientType: recipientType,
                                  message: messageController.text.trim(),
                                );

                                if (context.mounted) {
                                  Navigator.pop(context);
                                  TopNotification.success(
                                    context,
                                    '✅ Message sent successfully!',
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  TopNotification.error(
                                    context,
                                    AppLocalizations.of(
                                      context,
                                    )!.failedToSendMessage(e.toString()),
                                  );
                                }
                              } finally {
                                setModalState(() {
                                  isSending = false;
                                });
                              }
                            },
                      icon: const Icon(
                        CupertinoIcons.paperplane_fill,
                        size: 20,
                      ),
                      isLoading: isSending,
                      width: double.infinity,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildContactOptionTile({
    required bool isDark,
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onTap,
  }) {
    if (onTap != null) {
      return TradeRepublicListTile.navigation(
        title: label,
        leading: Icon(icon, size: 20, color: isDark ? Colors.white70 : Colors.black87),
        onTap: onTap,
      );
    }
    return TradeRepublicListTile(
      title: label,
      leading: Icon(icon, size: 20, color: isDark ? Colors.white38 : Colors.black38),
    );
  }

  Widget _buildTrackingSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TradeRepublicSectionHeader(
          title: AppLocalizations.of(context)!.trackingInformation,
          padding: const EdgeInsets.only(bottom: 12),
        ),
        TradeRepublicCard(
          child: TradeRepublicListTile(
            padding: _kSheetTilePadding,
            title: _currentOrder['tracking_number']?.toString() ?? 'N/A',
            subtitle: AppLocalizations.of(context)!.trackingNumber,
            onTap: () {
              Clipboard.setData(ClipboardData(text: _currentOrder['tracking_number']?.toString() ?? ''));
              TopNotification.info(context, 'Tracking number copied');
            },
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: TradeRepublicTheme.textColor(context).withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                CupertinoIcons.location_solid,
                size: 17,
                color: TradeRepublicTheme.textColor(context),
              ),
            ),
            trailing: Icon(CupertinoIcons.doc_on_doc, size: 15,
                color: isDark ? Colors.white38 : Colors.black38),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value, bool isDark) {
    return TradeRepublicListTile(
      padding: _kSheetTilePaddingCompact,
      title: value,
      subtitle: label,
    );
  }

  String _formatDate(dynamic dateValue) {
    if (dateValue == null) return 'N/A';

    DateTime? date;
    if (dateValue is String) {
      date = DateTime.tryParse(dateValue);
    } else if (dateValue is DateTime) {
      date = dateValue;
    }

    if (date != null) {
      // Use local time
      return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }
    return AppLocalizations.of(context)!.invalidDate;
  }

  String _formatOrderDate() {
    final orderDate = DateTime.tryParse(
      _currentOrder['order_date']?.toString() ?? '',
    );
    if (orderDate != null) {
      // Use local time
      return '${orderDate.day.toString().padLeft(2, '0')}.${orderDate.month.toString().padLeft(2, '0')}.${orderDate.year} at ${orderDate.hour.toString().padLeft(2, '0')}:${orderDate.minute.toString().padLeft(2, '0')}';
    }
    return AppLocalizations.of(context)!.unknownDate;
  }

  // Buyer Check-In Verification Card – shown when driver has arrived (buyer_check_in status)
  Widget _buildBuyerCheckInVerificationCard(bool isDark) {
    final securityCode = (_currentOrder['securityCode'] ??
            _currentOrder['security_code'] ??
            '')
        .toString();

    // qrCode in DB is a JSON string – render it directly as a QR code
    final qrData = (_currentOrder['qrCode'] ??
            _currentOrder['qr_code'] ??
            securityCode)
        .toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sheetSectionLabelWidget(
          context,
          'DRIVER ARRIVED',
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'Show QR code & verification code to the driver',
            style: _sheetCaptionStyle(context).copyWith(fontSize: 14),
          ),
        ),

        // ── Status banner ─────────────────────────────────────────────
        TradeRepublicCard(
          padding: _kSheetTilePaddingCompact,
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1E1E20)
                      : Colors.black.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  CupertinoIcons.location_fill,
                  color: isDark ? Colors.white : Colors.black,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Your driver has checked in and is waiting at your location.',
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
        const SizedBox(height: 12),

        // ── QR Code card ──────────────────────────────────────────────
        if (qrData.isNotEmpty)
          TradeRepublicCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                TradeRepublicListTile(
                  padding: _kSheetTilePaddingCompact,
                  title: AppLocalizations.of(context)!.qrCode,
                  subtitle: AppLocalizations.of(context)!.driverScansCodeToConfirmHandover,
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1E1E20)
                          : Colors.black.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      CupertinoIcons.qrcode,
                      size: 18,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                ),
                const TradeRepublicDivider(margin: EdgeInsets.zero),
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 20, 0, 12),
                  child: Center(
                    child: Container(
                      width: 236,
                      height: 236,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(isDark ? 0.25 : 0.08),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: QrImageView(
                        data: qrData,
                        version: QrVersions.auto,
                        size: 204,
                        backgroundColor: Colors.white,
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: Colors.black,
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Text(
                    AppLocalizations.of(context)!.showThisCodeToTheDriver,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white54 : Colors.black45,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),

        // ── Verification Code card ────────────────────────────────────
        if (securityCode.isNotEmpty)
          TradeRepublicCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                TradeRepublicListTile(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  title: AppLocalizations.of(context)!.verificationCode,
                  subtitle: AppLocalizations.of(context)!.showThisCodeToTheDriver,
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1E1E20)
                          : Colors.black.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      CupertinoIcons.lock_shield_fill,
                      color: isDark ? Colors.white : Colors.black,
                      size: 18,
                    ),
                  ),
                  trailing: TradeRepublicButton.icon(
                    icon: Icon(CupertinoIcons.doc_on_clipboard, size: 18, color: isDark ? Colors.white38 : Colors.black38),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: securityCode));
                      _showSuccessSnackBar('Code copied');
                    },
                    size: 36,
                    isSecondary: true,
                  ),
                ),
                const TradeRepublicDivider(margin: EdgeInsets.zero),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 22),
                  child: Text(
                    securityCode.split('').join('  '),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : Colors.black,
                      letterSpacing: 4,
                      fontFamily: 'monospace',
                      height: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // Security Code Card Widget
  Widget _buildSecurityCodeCard(bool isDark) {
    final securityCode =
        _currentOrder['securityCode'] ??
        _currentOrder['security_code'] ??
        'N/A';

    return TradeRepublicCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          TradeRepublicListTile(
            padding: _kSheetTilePadding,
            title: AppLocalizations.of(context)!.verificationCode,
            subtitle: AppLocalizations.of(context)!.showThisCodeToTheDriver,
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(CupertinoIcons.lock_shield_fill, color: Colors.orange.shade700, size: 18),
            ),
          ),
          const TradeRepublicDivider(margin: EdgeInsets.zero),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 22),
            child: Text(
              securityCode,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w700,
                color: Colors.orange.shade700,
                letterSpacing: 8,
                fontFamily: 'monospace',
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Review Section Widget for delivered orders
  Widget _buildReviewSection(bool isDark) {
    if (_isLoadingReviewStatus) {
      return const TradeRepublicCard(
        child: Center(child: CultiooLoadingIndicator()),
      );
    }

    if (_hasReviewed) {
      return TradeRepublicCard(
        backgroundColor: TradeRepublicTheme.textColor(context).withOpacity(0.08),
        child: TradeRepublicListTile(
          padding: EdgeInsets.zero,
          title: AppLocalizations.of(context)!.reviewSubmitted,
          subtitle: AppLocalizations.of(context)!.thankYouForYourFeedback,
          titleColor: TradeRepublicTheme.textColor(context),
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: TradeRepublicTheme.textColor(context).withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              CupertinoIcons.checkmark_seal_fill,
              color: TradeRepublicTheme.textColor(context),
              size: 18,
            ),
          ),
        ),
      );
    }

    return TradeRepublicCard(
      backgroundColor: TradeRepublicTheme.textColor(context).withOpacity(0.07),
      child: Column(
        children: [
          TradeRepublicListTile(
            padding: EdgeInsets.zero,
            title: AppLocalizations.of(context)!.rateYourExperience,
            subtitle: AppLocalizations.of(context)!.shareYourFeedbackAboutThisOrder,
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: TradeRepublicTheme.textColor(context).withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                CupertinoIcons.star_fill,
                color: TradeRepublicTheme.textColor(context),
                size: 18,
              ),
            ),
          ),
          const SizedBox(height: 12),
          TradeRepublicButton(
            label: AppLocalizations.of(context)!.writeReview,
            onPressed: () => _showReviewModal(isDark),
            icon: const Icon(CupertinoIcons.square_pencil),
            width: double.infinity,
          ),
        ],
      ),
    );
  }

  // Show Review Modal
  void _showReviewModal(bool isDark) {
    int? sellerRating;
    int? driverRating;
    final TextEditingController sellerReviewController =
        TextEditingController();
    final TextEditingController driverReviewController =
        TextEditingController();
    bool isSubmittingSeller = false;
    bool isSubmittingDriver = false;
    bool sellerSubmitted = false;
    bool driverSubmitted = false;

    // Extract seller and driver info from order - use item seller as fallback
    String? sellerUsername = _currentOrder['seller_username'];
    String? driverUsername = _currentOrder['driver_username'];

    // Fallback 1: If seller_username is null, get it from the first item
    if (sellerUsername == null || sellerUsername.isEmpty) {
      final items = _currentOrder['items'] as List<dynamic>? ?? [];
      if (items.isNotEmpty && items[0]['seller'] != null) {
        sellerUsername = items[0]['seller'].toString();
      }
    }

    // Fallback 2: Check for sellerUsername (camelCase) in order
    if (sellerUsername == null || sellerUsername.isEmpty) {
      sellerUsername = _currentOrder['sellerUsername'];
    }

    // Fallback 3: Check items for sellerUsername
    if (sellerUsername == null || sellerUsername.isEmpty) {
      final items = _currentOrder['items'] as List<dynamic>? ?? [];
      if (items.isNotEmpty && items[0]['sellerUsername'] != null) {
        sellerUsername = items[0]['sellerUsername'].toString();
      }
    }

    // Debug output
    print('🔍 Review Modal Debug:');
    print('  Full order data: $_currentOrder');
    print('  seller_username (initial): $sellerUsername');
    print('  driver_username (initial): $driverUsername');
    print('  driver_username type: ${driverUsername.runtimeType}');
    print('  driver_username isEmpty: ${driverUsername?.isEmpty}');
    print('  Items: ${_currentOrder['items']}');
    print('  Order status: ${_currentOrder['status']}');

    // --- Build robust seller/driver identifiers and display names with multiple fallbacks ---
    // Seller username fallbacks: check order-level fields, nested maps, and first item
    String? resolvedSellerUsername = sellerUsername;
    String sellerDisplayName = '';

    // If order has a 'seller' object with username/name
    final sellerObj = _currentOrder['seller'];
    if ((resolvedSellerUsername == null || resolvedSellerUsername.isEmpty) &&
        sellerObj is Map) {
      resolvedSellerUsername =
          sellerObj['username']?.toString() ??
          sellerObj['user']?['username']?.toString();
      sellerDisplayName =
          sellerObj['name']?.toString() ??
          sellerObj['full_name']?.toString() ??
          sellerObj['username']?.toString() ??
          '';
    }

    // Check order-level alternative fields
    if ((resolvedSellerUsername == null || resolvedSellerUsername.isEmpty) &&
        _currentOrder['sellerUsername'] != null) {
      resolvedSellerUsername = _currentOrder['sellerUsername'].toString();
    }
    if (sellerDisplayName.isEmpty) {
      sellerDisplayName =
          _currentOrder['seller_name']?.toString() ??
          _currentOrder['seller_fullname']?.toString() ??
          '';
    }

    // Inspect first item for seller info
    final items = _currentOrder['items'] as List<dynamic>? ?? [];
    if ((resolvedSellerUsername == null || resolvedSellerUsername.isEmpty) &&
        items.isNotEmpty) {
      final first = items[0];
      if (first is Map) {
        resolvedSellerUsername =
            resolvedSellerUsername ?? first['seller']?.toString();
        resolvedSellerUsername =
            resolvedSellerUsername ?? first['sellerUsername']?.toString();
        // Nested seller object inside item
        final itemSeller = first['seller'];
        if (itemSeller is Map) {
          resolvedSellerUsername =
              resolvedSellerUsername ?? itemSeller['username']?.toString();
          sellerDisplayName = sellerDisplayName.isEmpty
              ? (itemSeller['name']?.toString() ??
                    itemSeller['full_name']?.toString() ??
                    '')
              : sellerDisplayName;
        }
        // Also try name fields on item
        sellerDisplayName = sellerDisplayName.isEmpty
            ? (first['seller_name']?.toString() ??
                  first['sellerFullName']?.toString() ??
                  '')
            : sellerDisplayName;
      }
    }

    // Final fallbacks
    resolvedSellerUsername =
        (resolvedSellerUsername != null && resolvedSellerUsername.isNotEmpty)
        ? resolvedSellerUsername
        : null;
    sellerDisplayName = sellerDisplayName.isNotEmpty
        ? sellerDisplayName
        : (resolvedSellerUsername ??
              AppLocalizations.of(context)!.sellerNotAvailable);

    // Driver display name fallbacks
    String? resolvedDriverUsername = driverUsername;
    String driverDisplayName = '';
    final driverObj = _currentOrder['driver'];
    if ((resolvedDriverUsername == null || resolvedDriverUsername.isEmpty) &&
        driverObj is Map) {
      resolvedDriverUsername =
          driverObj['username']?.toString() ??
          driverObj['user']?['username']?.toString();
      driverDisplayName =
          driverObj['name']?.toString() ??
          driverObj['full_name']?.toString() ??
          '';
    }
    driverDisplayName = driverDisplayName.isNotEmpty
        ? driverDisplayName
        : (resolvedDriverUsername != null && resolvedDriverUsername.isNotEmpty
              ? resolvedDriverUsername
              : (_currentOrder['driver_name']?.toString() ??
                    AppLocalizations.of(context)!.driverNotAvailable));

    // Update the local variables used later in closures
    sellerUsername = resolvedSellerUsername;
    driverUsername = resolvedDriverUsername;

    // Do NOT block showing the modal if seller info is missing; we'll show placeholders and disable seller review submit if needed.
    if (resolvedSellerUsername == null) {
      print(
        '⚠️ Warning: seller username could not be resolved. Showing modal with disabled seller submit.',
      );
    }

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: Builder(
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setModalState) => AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              height: MediaQuery.of(context).size.height * 0.8,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF121212) : Colors.white,
              ),
              child: Column(
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: Text(
                      AppLocalizations.of(context)!.rateYourTrip,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),

                  // Scrollable Content with padding
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        children: [
                          // Seller Rating Section with Submit Button
                          if (!sellerSubmitted &&
                              ((sellerDisplayName.isNotEmpty &&
                                      sellerDisplayName !=
                                          AppLocalizations.of(
                                            context,
                                          )!.sellerNotAvailable) ||
                                  (sellerUsername != null &&
                                      sellerUsername.isNotEmpty))) ...[
                            _buildRatingSection(
                              title: AppLocalizations.of(context)!.rateSeller,
                              subtitle: sellerDisplayName,
                              rating: sellerRating,
                              controller: sellerReviewController,
                              isDark: isDark,
                              onRatingChanged: (rating) {
                                setModalState(() {
                                  sellerRating = rating;
                                });
                              },
                            ),
                            // Uber-style Submit Button
                            TradeRepublicButton(
                              label: AppLocalizations.of(context)!.submit,
                              onPressed:
                                  (isSubmittingSeller ||
                                      sellerRating == null ||
                                      sellerUsername == null)
                                  ? null
                                  : () async {
                                      setModalState(() {
                                        isSubmittingSeller = true;
                                      });

                                      try {
                                        print('📝 Submitting seller review...');
                                        print(
                                          '  Order ID: ${_currentOrder['id']}',
                                        );
                                        print(
                                          '  Seller Username: $sellerUsername',
                                        );
                                        print('  Seller Rating: $sellerRating');
                                        print(
                                          '  Review Text: ${sellerReviewController.text}',
                                        );

                                        final response =
                                            await ApiService.submitReview(
                                              orderId: _currentOrder['id'],
                                              sellerUsername: sellerUsername,
                                              driverUsername: null,
                                              sellerRating: sellerRating,
                                              driverRating: null,
                                              sellerReviewText:
                                                  sellerReviewController
                                                      .text
                                                      .isNotEmpty
                                                  ? sellerReviewController.text
                                                  : null,
                                              driverReviewText: null,
                                            );

                                        print(
                                          '✅ Seller review response: $response',
                                        );

                                        setModalState(() {
                                          sellerSubmitted = true;
                                          isSubmittingSeller = false;
                                        });

                                        if (mounted) {
                                          TopNotification.success(
                                            context,
                                            '✅ Seller review submitted!',
                                          );

                                          // Close modal only if both are submitted or driver doesn't exist
                                          if (driverUsername == null ||
                                              driverSubmitted) {
                                            setState(() {
                                              _hasReviewed = true;
                                            });
                                            Future.delayed(
                                              const Duration(milliseconds: 500),
                                              () {
                                                if (mounted) {
                                                  Navigator.pop(context);
                                                }
                                              },
                                            );
                                          }
                                        }
                                      } catch (e) {
                                        if (mounted) {
                                          TopNotification.error(
                                            context,
                                            '❌ Error: $e',
                                          );
                                        }
                                        setModalState(() {
                                          isSubmittingSeller = false;
                                        });
                                      }
                                    },
                              isLoading: isSubmittingSeller,
                              width: double.infinity,
                            ),
                            const SizedBox(height: 32),
                          ],

                          // Driver Rating Section with Submit Button
                          if (!driverSubmitted &&
                              ((driverDisplayName.isNotEmpty &&
                                      driverDisplayName !=
                                          AppLocalizations.of(
                                            context,
                                          )!.driverNotAvailable) ||
                                  (driverUsername != null &&
                                      driverUsername.isNotEmpty))) ...[
                            _buildRatingSection(
                              title: AppLocalizations.of(context)!.rateDriver,
                              subtitle: driverDisplayName,
                              rating: driverRating,
                              controller: driverReviewController,
                              isDark: isDark,
                              onRatingChanged: (rating) {
                                setModalState(() {
                                  driverRating = rating;
                                });
                              },
                            ),
                            // Uber-style Submit Button
                            TradeRepublicButton(
                              label: AppLocalizations.of(context)!.submit,
                              onPressed:
                                  (isSubmittingDriver ||
                                      driverRating == null ||
                                      driverUsername == null)
                                  ? null
                                  : () async {
                                      setModalState(() {
                                        isSubmittingDriver = true;
                                      });

                                      try {
                                        print('🚗 Submitting driver review:');
                                        print(
                                          '  orderId: ${_currentOrder['id']}',
                                        );
                                        print(
                                          '  driverUsername: $driverUsername',
                                        );
                                        print('  driverRating: $driverRating');
                                        print(
                                          '  driverReviewText: ${driverReviewController.text}',
                                        );

                                        final response =
                                            await ApiService.submitReview(
                                              orderId: _currentOrder['id'],
                                              sellerUsername: null,
                                              driverUsername: driverUsername,
                                              sellerRating: null,
                                              driverRating: driverRating,
                                              sellerReviewText: null,
                                              driverReviewText:
                                                  driverReviewController
                                                      .text
                                                      .isNotEmpty
                                                  ? driverReviewController.text
                                                  : null,
                                            );

                                        print(
                                          '✅ Driver review response: $response',
                                        );

                                        setModalState(() {
                                          driverSubmitted = true;
                                          isSubmittingDriver = false;
                                        });

                                        if (mounted) {
                                          TopNotification.success(
                                            context,
                                            '✅ Driver review submitted!',
                                          );

                                          // Close modal only if both reviews are submitted
                                          // or if there's no seller to review
                                          print(
                                            '🔍 Check if modal should close:',
                                          );
                                          print(
                                            '  sellerUsername exists: ${sellerUsername != null && sellerUsername.isNotEmpty}',
                                          );
                                          print(
                                            '  sellerSubmitted: $sellerSubmitted',
                                          );
                                          print(
                                            '  driverSubmitted: $driverSubmitted',
                                          );

                                          final hasSellerToReview =
                                              sellerUsername != null &&
                                              sellerUsername.isNotEmpty;
                                          final shouldClose =
                                              !hasSellerToReview ||
                                              (hasSellerToReview &&
                                                  sellerSubmitted);

                                          print('  Should close: $shouldClose');

                                          if (shouldClose) {
                                            setState(() {
                                              _hasReviewed = true;
                                            });

                                            // Wait a bit before closing to show the success state
                                            Future.delayed(
                                              const Duration(milliseconds: 500),
                                              () {
                                                if (mounted) {
                                                  Navigator.pop(context);
                                                }
                                              },
                                            );
                                          }
                                        }
                                      } catch (e) {
                                        if (mounted) {
                                          TopNotification.error(
                                            context,
                                            '❌ Error: $e',
                                          );
                                        }
                                        setModalState(() {
                                          isSubmittingDriver = false;
                                        });
                                      }
                                    },
                              isLoading: isSubmittingDriver,
                              width: double.infinity,
                            ),
                            const SizedBox(height: 32),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // Build Rating Section Widget - Uber Style
  Widget _buildRatingSection({
    required String title,
    required String subtitle,
    required int? rating,
    required TextEditingController controller,
    required bool isDark,
    required Function(int) onRatingChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(25),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title - Uber style
          Text(
            title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),

          // Subtitle - smaller, lighter
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 15,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 28),

          // Uber-style Star Rating - Horizontal with labels
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(5, (index) {
              final starValue = index + 1;
              final isSelected = rating != null && starValue <= rating;
              return Expanded(
                child: GestureDetector(
                  onTap: () => onRatingChanged(starValue),
                  child: Container(
                    margin: EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      children: [
                        TweenAnimationBuilder<double>(
                          duration: Duration(milliseconds: 150 + (index * 20)),
                          curve: Curves.easeOut,
                          tween: Tween(
                            begin: 0.95,
                            end: isSelected ? 1.0 : 0.95,
                          ),
                          builder: (context, scale, child) {
                            return Transform.scale(
                              scale: scale,
                              child: Icon(
                                isSelected ? Icons.star : Icons.star_border,
                                color: isSelected
                                    ? const Color(0xFFFFD700)
                                    : (isDark
                                          ? Colors.grey[700]
                                          : Colors.grey[300]),
                                size: 40,
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '$starValue',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: isSelected
                                ? (isDark ? Colors.white : Colors.black)
                                : (isDark
                                      ? Colors.grey[600]
                                      : Colors.grey[400]),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),

          // Optional comment section - Uber style
          if (rating != null) ...[
            const SizedBox(height: 28),
            TradeRepublicTextField.multiline(
              controller: controller,
              hintText: AppLocalizations.of(context)!.addACommentOptional,
              maxLines: 3,
            ),
          ],
        ],
      ),
    );
  }

  // Show Live Location Modal
  void _showLiveLocation() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      maxHeight: MediaQuery.of(context).size.height * 0.85,
      child: _LiveLocationModal(
        orderId: _currentOrder['id'],
        orderData: _currentOrder,
        isDark: isDark,
      ),
    );
  }

  // Show Request Information Modal with options
  void _showRequestInformationModal(bool isDark) {
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Row(
                children: [
                  Icon(
                    CupertinoIcons.info,
                    color: isDark ? Colors.white : Colors.black,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context)!.requestInformation,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Request Photos Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: TradeRepublicButton(
                label: AppLocalizations.of(context)!.requestPhotos,
                icon: const Icon(CupertinoIcons.camera, color: Colors.white, size: 20),
                tint: const Color(0xFF1976D2),
                onPressed: () {
                  Navigator.pop(context);
                  _showRequestPhotosDialog(isDark);
                },
                width: double.infinity,
              ),
            ),

            // Request Temperature Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: TradeRepublicButton(
                label: AppLocalizations.of(context)!.requestTemperature,
                icon: const Icon(CupertinoIcons.thermometer, color: Colors.white, size: 20),
                tint: const Color(0xFFFF6F00),
                onPressed: () {
                  Navigator.pop(context);
                  _showRequestTemperatureDialog(isDark);
                },
                width: double.infinity,
              ),
            ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // Show Request Temperature Dialog
  void _showRequestTemperatureDialog(bool isDark) {
    final TextEditingController noteController = TextEditingController();
    bool isRequesting = false;
    String selectedInterval = 'once'; // once, 5min, 10min, 15min, 30min

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: Builder(
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setModalState) => Container(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              decoration: BoxDecoration(
                color: isDark ? Colors.black : Colors.white,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(25),
                          ),

                          child: const Icon(
                            CupertinoIcons.thermometer,
                            color: Colors.orange,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                AppLocalizations.of(
                                  context,
                                )!.requestTemperature,
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: isDark ? Colors.white : Colors.black,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                AppLocalizations.of(
                                  context,
                                )!.askDriverToCheckProductTemperature,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isDark
                                      ? Colors.grey[400]
                                      : Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Interval Selection
                    Text(
                      AppLocalizations.of(context)!.measurementInterval,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildIntervalChip(
                          'Once',
                          'once',
                          selectedInterval,
                          (val) {
                            setModalState(() => selectedInterval = val);
                          },
                          isDark,
                          isTemperature: true,
                        ),
                        _buildIntervalChip(
                          AppLocalizations.of(context)!.every1Hour,
                          '1h',
                          selectedInterval,
                          (val) {
                            setModalState(() => selectedInterval = val);
                          },
                          isDark,
                          isTemperature: true,
                        ),
                        _buildIntervalChip(
                          AppLocalizations.of(context)!.every3Hours,
                          '3h',
                          selectedInterval,
                          (val) {
                            setModalState(() => selectedInterval = val);
                          },
                          isDark,
                          isTemperature: true,
                        ),
                        _buildIntervalChip(
                          AppLocalizations.of(context)!.every6Hours,
                          '6h',
                          selectedInterval,
                          (val) {
                            setModalState(() => selectedInterval = val);
                          },
                          isDark,
                          isTemperature: true,
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Note input
                    TradeRepublicTextField.multiline(
                      controller: noteController,
                      hintText: AppLocalizations.of(context)!.addANoteOptional,
                      maxLines: 3,
                    ),

                    const SizedBox(height: 24),

                    // Send button
                    TradeRepublicButton(
                      label: AppLocalizations.of(context)!.sendRequest,
                      icon: const Icon(CupertinoIcons.paperplane_fill, color: Colors.white, size: 20),
                      tint: const Color(0xFFFF6F00),
                      isLoading: isRequesting,
                      onPressed: isRequesting
                          ? null
                          : () async {
                              print('🔥 Temperature Request Button Clicked');
                              print('Selected Interval: $selectedInterval');

                              setModalState(() {
                                isRequesting = true;
                              });

                              try {
                                print('💾 Sending temperature request...');
                                // TODO: Add API call for temperature request with interval
                                // For now, just show success
                                await Future.delayed(
                                  const Duration(seconds: 1),
                                );

                                print('✅ Request completed');

                                if (context.mounted) {
                                  Navigator.of(context).pop();

                                  final intervalText =
                                      selectedInterval == 'once'
                                      ? 'once'
                                      : 'every ${selectedInterval.replaceAll('h', ' hours')}';

                                  print(
                                    '📢 Showing success message: $intervalText',
                                  );

                                  TopNotification.success(
                                    context,
                                    AppLocalizations.of(
                                      context,
                                    )!.temperatureRequestSent(
                                      intervalText,
                                    ),
                                  );
                                }
                              } catch (e) {
                                print('❌ Error: $e');
                                if (context.mounted) {
                                  TopNotification.error(
                                    context,
                                    AppLocalizations.of(
                                      context,
                                    )!.errorGeneric(e.toString()),
                                  );
                                }
                              } finally {
                                setModalState(() {
                                  isRequesting = false;
                                });
                              }
                            },
                      width: double.infinity,
                    ),

                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // Build interval selection chip
  Widget _buildIntervalChip(
    String label,
    String value,
    String selectedValue,
    Function(String) onSelect,
    bool isDark, {
    bool isTemperature = false,
  }) {
    final isSelected = selectedValue == value;
    final gradientColors = isTemperature
        ? [const Color(0xFFFF6F00), const Color(0xFFFFB74D)]
        : [const Color(0xFF1976D2), const Color(0xFF64B5F6)];

    return InkWell(
      onTap: () => onSelect(value),
      borderRadius: BorderRadius.circular(25),

      child: Container(
        padding: _kSheetTilePaddingDense,
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  colors: gradientColors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isSelected
              ? null
              : isDark
              ? const Color(0xFF1E1E1E)
              : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(25),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected
                ? Colors.white
                : isDark
                ? Colors.white
                : Colors.black,
          ),
        ),
      ),
    );
  }

  // Show Request Photos Dialog
  void _showRequestPhotosDialog(bool isDark) {
    final TextEditingController noteController = TextEditingController();
    bool isRequesting = false;
    String selectedInterval = 'once'; // once, 5min, 10min, 15min, 30min

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: Builder(
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setModalState) => Container(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              decoration: BoxDecoration(
                color: isDark ? Colors.black : Colors.white,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(25),
                          ),
                          child: const Icon(
                            CupertinoIcons.camera,
                            color: Colors.blue,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                AppLocalizations.of(context)!.requestPhotos,
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: isDark ? Colors.white : Colors.black,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                AppLocalizations.of(
                                  context,
                                )!.askDriverToTakePhotos,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isDark
                                      ? Colors.grey[400]
                                      : Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Interval Selection
                    Text(
                      AppLocalizations.of(context)!.photoInterval,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildIntervalChip('Once', 'once', selectedInterval, (
                          val,
                        ) {
                          setModalState(() => selectedInterval = val);
                        }, isDark),
                        _buildIntervalChip(
                          AppLocalizations.of(context)!.everyOneHour,
                          '1h',
                          selectedInterval,
                          (val) {
                            setModalState(() => selectedInterval = val);
                          },
                          isDark,
                        ),
                        _buildIntervalChip(
                          AppLocalizations.of(context)!.every3Hours,
                          '3h',
                          selectedInterval,
                          (val) {
                            setModalState(() => selectedInterval = val);
                          },
                          isDark,
                        ),
                        _buildIntervalChip(
                          AppLocalizations.of(context)!.every6Hours,
                          '6h',
                          selectedInterval,
                          (val) {
                            setModalState(() => selectedInterval = val);
                          },
                          isDark,
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Note field
                    TradeRepublicTextField.multiline(
                      controller: noteController,
                      hintText: AppLocalizations.of(
                        context,
                      )!.addANoteOptionalnexamplePleaseTakePhotosOf,
                      maxLines: 4,
                    ),

                    const SizedBox(height: 24),

                    // Send button
                    TradeRepublicButton(
                      label: AppLocalizations.of(context)!.sendRequest,
                      icon: const Icon(CupertinoIcons.paperplane_fill, color: Colors.white, size: 20),
                      tint: const Color(0xFF1976D2),
                      isLoading: isRequesting,
                      onPressed: isRequesting
                          ? null
                          : () async {
                              print('🔥 Photo Request Button Clicked');
                              print('Selected Interval: $selectedInterval');

                              final note = noteController.text.trim();

                              setModalState(() {
                                isRequesting = true;
                              });

                              try {
                                print('💾 Sending photo request...');
                                await ApiService.requestDriverPhotos(
                                  orderId: _currentOrder['id'],
                                  note: note.isEmpty
                                      ? AppLocalizations.of(
                                          context,
                                        )!.pleaseSendPhotosOfTheProducts
                                      : note,
                                );

                                print('✅ Request completed');

                                if (context.mounted) {
                                  Navigator.of(context).pop();

                                  final intervalText =
                                      selectedInterval == 'once'
                                      ? 'once'
                                      : 'every ${selectedInterval.replaceAll('h', ' hours')}';

                                  print(
                                    '📢 Showing success message: $intervalText',
                                  );

                                  TopNotification.success(
                                    context,
                                    AppLocalizations.of(
                                      context,
                                    )!.photoRequestSent(intervalText),
                                  );

                                  // Show photo requests modal
                                  Future.delayed(
                                    const Duration(milliseconds: 500),
                                    () {
                                      if (context.mounted) {
                                        _showPhotoRequestsModal(isDark);
                                      }
                                    },
                                  );
                                }
                              } catch (e) {
                                print('❌ Error: $e');
                                if (context.mounted) {
                                  TopNotification.error(
                                    context,
                                    AppLocalizations.of(
                                      context,
                                    )!.errorGeneric(e.toString()),
                                  );
                                }
                              } finally {
                                setModalState(() {
                                  isRequesting = false;
                                });
                              }
                            },
                      width: double.infinity,
                    ),

                    const SizedBox(height: 16),

                    // View previous requests button
                    TradeRepublicButton(
                      label: AppLocalizations.of(
                        context,
                      )!.viewPreviousPhotoRequests,
                      onPressed: () {
                        Navigator.of(context).pop();
                        _showPhotoRequestsModal(isDark);
                      },
                      isSecondary: true,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // Show Photo Requests Modal
  void _showPhotoRequestsModal(bool isDark) {
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      maxHeight: MediaQuery.of(context).size.height * 0.85,
      child: _PhotoRequestsModal(orderId: _currentOrder['id'], isDark: isDark),
    );
  }

  // Show Scan QR Code Modal with Scanner
  void _showScanQRCode() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final expectedQrCode = _currentOrder['qrCode'] ?? _currentOrder['qr_code'];
    final securityCode =
        _currentOrder['securityCode'] ?? _currentOrder['security_code'];

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      maxHeight: MediaQuery.of(context).size.height * 0.85,
      child: _QRCodeScannerModal(
        isDark: isDark,
        expectedQrCode: expectedQrCode,
        securityCode: securityCode,
        orderId: _currentOrder['id'],
        onScanSuccess: () {
          // Refresh order details after successful scan
          if (widget.onOrderUpdated != null) {
            widget.onOrderUpdated!();
          }
        },
      ),
    );
  }
}

// Photo Requests Modal Widget
class _PhotoRequestsModal extends StatefulWidget {
  final int orderId;
  final bool isDark;

  const _PhotoRequestsModal({required this.orderId, required this.isDark});

  @override
  State<_PhotoRequestsModal> createState() => _PhotoRequestsModalState();
}

class _PhotoRequestsModalState extends State<_PhotoRequestsModal> {
  bool _isLoading = true;
  List<dynamic> _requests = [];
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadRequests();
    // Auto-refresh every 10 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _loadRequests();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadRequests() async {
    try {
      final response = await ApiService.getPhotoRequests(widget.orderId);
      if (mounted) {
        setState(() {
          _requests = response['requests'] ?? [];
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading photo requests: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(25),
                ),

                child: const Icon(
                  CupertinoIcons.photo_on_rectangle,
                  color: Colors.blue,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.photoRequests,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: widget.isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    Text(
                      AppLocalizations.of(context)!.photosFromDriver,
                      style: TextStyle(
                        fontSize: 14,
                        color: widget.isDark
                            ? Colors.grey[400]
                            : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              TradeRepublicButton(
                icon: Icon(
                  CupertinoIcons.refresh,
                  size: 18,
                ),
                isSecondary: true,
                width: 44,
                height: 44,
                padding: EdgeInsets.zero,
                borderRadius: BorderRadius.circular(25),
                onPressed: _loadRequests,
              ),
            ],
          ),
        ),

        // Content
        Expanded(
          child: _isLoading
              ? const Center(child: CultiooLoadingIndicator())
              : _requests.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        CupertinoIcons.camera,
                        size: 64,
                        color: widget.isDark
                            ? Colors.grey[700]
                            : Colors.grey[300],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        AppLocalizations.of(context)!.noPhotoRequestsYet,
                        style: TextStyle(
                          fontSize: 16,
                          color: widget.isDark
                              ? Colors.grey[400]
                              : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: _requests.length,
                  itemBuilder: (context, index) {
                    final request = _requests[index];
                    return _buildRequestCard(request);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> request) {
    final requestType = request['request_type'] ?? 'photo';
    final intervalType = request['interval_type'] ?? 'once';
    final isPhotoRequest = requestType == 'photo';

    final hasPhotos =
        request['photos'] != null && (request['photos'] as List).isNotEmpty;
    final photoCount = hasPhotos ? (request['photos'] as List).length : 0;
    final createdAt = request['created_at'] != null
        ? DateTime.tryParse(request['created_at'].toString())
        : null;

    final isCompleted = request['status'] == 'completed';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: widget.isDark
            ? const Color(0xFF1E1E1E)
            : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(25),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Icon(
                isCompleted
                    ? CupertinoIcons.checkmark_circle_fill
                    : CupertinoIcons.clock,
                color: isCompleted ? Colors.green : Colors.orange,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isPhotoRequest
                          ? (isCompleted
                                ? AppLocalizations.of(context)!.photosReceived
                                : AppLocalizations.of(
                                    context,
                                  )!.waitingForPhotos)
                          : (isCompleted
                                ? AppLocalizations.of(
                                    context,
                                  )!.temperatureRecorded
                                : AppLocalizations.of(
                                    context,
                                  )!.waitingForTemperature),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isCompleted ? Colors.green : Colors.orange,
                      ),
                    ),
                    if (intervalType != 'once')
                      Text(
                        'Interval: ${intervalType.replaceAll('h', ' hours')}',
                        style: TextStyle(
                          fontSize: 12,
                          color: widget.isDark
                              ? Colors.grey[500]
                              : Colors.grey[600],
                        ),
                      ),
                  ],
                ),
              ),
              if (createdAt != null)
                Text(
                  _formatTime(createdAt),
                  style: TextStyle(
                    fontSize: 12,
                    color: widget.isDark ? Colors.grey[500] : Colors.grey[600],
                  ),
                ),
            ],
          ),

          // Show photos if available
          if (isPhotoRequest && hasPhotos) ...[
            const SizedBox(height: 16),
            Text(
              '$photoCount ${photoCount == 1 ? 'Photo' : 'Photos'}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: widget.isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 12),
            // Photo grid
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: photoCount,
              itemBuilder: (context, photoIndex) {
                final photo = (request['photos'] as List)[photoIndex];
                return GestureDetector(
                  onTap: () {
                    // Show full image
                    _showFullImage(photo['url']);
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(25),

                      image: DecorationImage(
                        image: NetworkImage(photo['url']),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inMinutes < 1) {
      return AppLocalizations.of(context)!.justNow;
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  void _showFullImage(String url) {
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      maxHeight: MediaQuery.of(context).size.height * 0.85,
      child: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: InteractiveViewer(child: Image.network(url)),
        ),
      ),
    );
  }
}

// QR Code Scanner Modal Widget
class _QRCodeScannerModal extends StatefulWidget {
  final bool isDark;
  final String? expectedQrCode;
  final String? securityCode;
  final int orderId;
  final VoidCallback onScanSuccess;

  const _QRCodeScannerModal({
    required this.isDark,
    required this.expectedQrCode,
    required this.securityCode,
    required this.orderId,
    required this.onScanSuccess,
  });

  @override
  State<_QRCodeScannerModal> createState() => _QRCodeScannerModalState();
}

class _QRCodeScannerModalState extends State<_QRCodeScannerModal> {
  late MobileScannerController cameraController;
  bool _isProcessing = false;
  bool? _isValid;

  @override
  void initState() {
    super.initState();
    cameraController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
  }

  @override
  void dispose() {
    cameraController.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final scannedValue = barcodes.first.rawValue;
    if (scannedValue == null || scannedValue.isEmpty) return;

    setState(() {
      _isProcessing = true;
    });

    // Stop the scanner
    await cameraController.stop();

    // Validate the scanned QR code
    await _validateQRCode(scannedValue);
  }

  Future<void> _validateQRCode(String scannedCode) async {
    try {
      // Call backend API to validate and mark as delivered
      final response = await ApiService.scanOrderQRCode(
        widget.orderId,
        scannedCode,
        widget.securityCode,
      );

      if (response['success'] == true) {
        setState(() {
          _isValid = true;
        });

        // Show success message
        await Future.delayed(const Duration(seconds: 2));

        if (mounted) {
          widget.onScanSuccess();
          Navigator.of(context).pop();

          TopNotification.success(
            context,
            '✅ Order verified and marked as delivered!',
          );
        }
      } else {
        setState(() {
          _isValid = false;
        });
      }
    } catch (e) {
      setState(() {
        _isValid = false;
      });
      print('❌ QR Code validation error: $e');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  void _restartScanner() {
    setState(() {
      _isValid = null;
      _isProcessing = false;
    });
    cameraController.start();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header - Uber minimalist style
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              Text(
                AppLocalizations.of(context)!.scanQrCode,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: widget.isDark ? Colors.white : Colors.black,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),

        // Subtitle - clean and minimal
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  AppLocalizations.of(
                    context,
                  )!.positionTheQrCodeWithinTheFrameToComplete,
                  style: TextStyle(
                    fontSize: 15,
                    color: widget.isDark ? Colors.grey[400] : Colors.grey[600],
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Camera Scanner or Result
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _buildScannerContent(),
          ),
        ),

        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildScannerContent() {
    if (_isValid == true) {
      // Success state - Uber style
      return Container(
        decoration: BoxDecoration(
          color: widget.isDark
              ? const Color(0xFF1E1E1E)
              : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(25),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
                child: const Icon(CupertinoIcons.checkmark_alt, size: 48, color: Colors.white),
              ),
              const SizedBox(height: 32),
              Text(
                AppLocalizations.of(context)!.pickupComplete,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: widget.isDark ? Colors.white : Colors.black,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                AppLocalizations.of(context)!.orderHasBeenDelivered,
                style: TextStyle(
                  fontSize: 16,
                  color: widget.isDark ? Colors.grey[400] : Colors.grey[600],
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      );
    } else if (_isValid == false) {
      // Error state - Uber style
      return Container(
        decoration: BoxDecoration(
          color: widget.isDark
              ? const Color(0xFF1E1E1E)
              : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(25),
        ),

        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: widget.isDark ? Colors.grey[800] : Colors.grey[300],
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.close,
                  size: 48,
                  color: widget.isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                AppLocalizations.of(context)!.invalidCode,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: widget.isDark ? Colors.white : Colors.black,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  AppLocalizations.of(context)!.thisQrCodeDoesntMatch,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: widget.isDark ? Colors.grey[400] : Colors.grey[600],
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              TradeRepublicButton(
                label: AppLocalizations.of(context)!.tryAgain,
                onPressed: _restartScanner,
              ),
            ],
          ),
        ),
      );
    } else {
      // Scanner state - Uber clean style
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(25),

          color: Colors.black,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            MobileScanner(controller: cameraController, onDetect: _onDetect),
            // Scanning guide overlay - minimal Uber style
            Center(
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(25),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withOpacity(0.26),
                      blurRadius: 22,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ),
            // Validating indicator at bottom - Uber style
            if (_isProcessing)
              Positioned(
                bottom: 32,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(25),
                    ),

                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CultiooLoadingIndicator(),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Validating',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }
  }
}

// Live Location Modal with auto-refresh
class _LiveLocationModal extends StatefulWidget {
  final int orderId;
  final Map<String, dynamic> orderData;
  final bool isDark;

  const _LiveLocationModal({
    required this.orderId,
    required this.orderData,
    required this.isDark,
  });

  @override
  State<_LiveLocationModal> createState() => _LiveLocationModalState();
}

class _LiveLocationModalState extends State<_LiveLocationModal> {
  late MapController _mapController;
  Timer? _refreshTimer;
  double _latitude = 52.520008; // Default: Berlin
  double _longitude = 13.404954;
  double? _deliveryLatitude;
  double? _deliveryLongitude;
  DateTime? _lastUpdate;
  bool _isLoading = false;
  List<Map<String, dynamic>> _nearbyDrivers = [];

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    // Wait for first frame to be rendered before loading location
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadLocation();
      _startAutoRefresh();
      _loadNearbyDrivers();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _loadLocation();
      _loadNearbyDrivers();
    });
  }

  Future<void> _loadNearbyDrivers() async {
    try {
      final resp = await ApiService.getAvailableDrivers(widget.orderId, radiusKm: 250);
      if (!mounted) return;
      final list = (resp['drivers'] as List<dynamic>? ?? [])
          .map((d) => Map<String, dynamic>.from(d as Map))
          .where((d) {
            final lat = double.tryParse(d['latitude']?.toString() ?? '') ?? 0;
            final lng = double.tryParse(d['longitude']?.toString() ?? '') ?? 0;
            return lat != 0 || lng != 0;
          })
          .toList();
      setState(() => _nearbyDrivers = list);
    } catch (_) {}
  }

  Future<void> _loadLocation() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      double? lat;
      double? lng;
      DateTime? locationUpdateTime;

      // Resolve delivery destination independently (used as map marker and fallback center).
      // Priority:
      // 1) user_addresses (matching address id or selected)
      // 2) order payload coordinates
      // 3) geocoded textual address
      var delivery = await _resolveDeliveryCoordsFromUserAddresses(widget.orderData);
      if (!_isValidLiveCoordPair(delivery.$1, delivery.$2)) {
        delivery = _resolveDeliveryCoordsFromOrderData(widget.orderData);
      }
      if (!_isValidLiveCoordPair(delivery.$1, delivery.$2)) {
        delivery = await _geocodeDeliveryCoords(widget.orderData);
      }
      if (_isValidLiveCoordPair(delivery.$1, delivery.$2) && mounted) {
        setState(() {
          _deliveryLatitude = delivery.$1;
          _deliveryLongitude = delivery.$2;
        });
      }

      // First, try to get LIVE driver location from API
      try {
        final data = await ApiService.getDriverLocation(widget.orderId);
        final location = data['location'];
        if (location != null) {
          final apiLat = location['latitude'];
          final apiLng = location['longitude'];
          final apiUpdatedAt = location['updatedAt'];
          if (apiLat != null && apiLng != null) {
            lat = double.tryParse(apiLat.toString());
            lng = double.tryParse(apiLng.toString());
            if (apiUpdatedAt != null) {
              try {
                locationUpdateTime = DateTime.parse(apiUpdatedAt.toString());
              } catch (_) {}
            }
            if (lat != null && lng != null) {
              print('🚗 Using LIVE API driver location: lat=\$lat, lng=\$lng');
            }
          }
        }
      } catch (e) {
        print('⚠️ API location fetch failed, falling back to static data: \$e');
      }

      // Fallback: use static orderData fields
      if (lat == null || lng == null) {
        final driverLat = widget.orderData['driver_latitude'];
        final driverLng = widget.orderData['driver_longitude'];
        final driverLocationUpdated =
            widget.orderData['driver_location_updated_at'];

        if (driverLat != null && driverLng != null) {
          lat = double.tryParse(driverLat.toString());
          lng = double.tryParse(driverLng.toString());
          if (driverLocationUpdated != null) {
            try {
              locationUpdateTime = DateTime.parse(
                driverLocationUpdated.toString(),
              );
            } catch (e) {
              print('⚠️ Error parsing driver location timestamp: \$e');
            }
          }
          if (lat != null && lng != null) {
            print('🚗 Using static DRIVER location: lat=\$lat, lng=\$lng');
          }
        }
      }

      // Fallback: If no driver location, use delivery destination coordinates.
      if (lat == null || lng == null) {
        print(
          '📍 No driver location available, falling back to delivery coordinates',
        );
        lat = delivery.$1;
        lng = delivery.$2;
        print('📍 Using DELIVERY location: lat=$lat, lng=$lng');
      }

      // Final fallback: use already resolved delivery coordinates from above.
      if (lat == null || lng == null) {
        lat = _deliveryLatitude;
        lng = _deliveryLongitude;
      }

      // Update coordinates if found
      if (lat != null && lng != null) {
        // Update state with new coordinates and timestamp
        if (mounted) {
          setState(() {
            _latitude = lat!;
            _longitude = lng!;
            _lastUpdate = locationUpdateTime ?? DateTime.now();
          });
        }

        // Animate map to new position (after state update)
        try {
          await Future.delayed(const Duration(milliseconds: 100));
          final points = <LatLng>[LatLng(_latitude, _longitude)];
          if (_isValidLiveCoordPair(_deliveryLatitude, _deliveryLongitude)) {
            points.add(LatLng(_deliveryLatitude!, _deliveryLongitude!));
          }
          if (points.length >= 2) {
            _mapController.fitCamera(
              CameraFit.bounds(
                bounds: LatLngBounds.fromPoints(points),
                padding: const EdgeInsets.all(64),
              ),
            );
          } else {
            _mapController.move(LatLng(_latitude, _longitude), 15.0);
          }
        } catch (e) {
          print('⚠️ Map animation error: $e');
        }

        print(
          '✅ Location updated: lat=$_latitude, lng=$_longitude, time=$_lastUpdate',
        );
      } else {
        print('⚠️ No valid coordinates found');
      }
    } catch (e) {
      print('❌ Error loading location: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  double? _parseLiveCoord(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    final s = value.toString().trim().replaceAll(',', '.');
    return double.tryParse(s);
  }

  (double?, double?) _coordsFromMap(
    Map<String, dynamic> data,
    List<String> latKeys,
    List<String> lngKeys,
  ) {
    double? lat;
    double? lng;
    for (final k in latKeys) {
      lat = _parseLiveCoord(data[k]);
      if (lat != null) break;
    }
    for (final k in lngKeys) {
      lng = _parseLiveCoord(data[k]);
      if (lng != null) break;
    }
    return (lat, lng);
  }

  bool _isValidLiveCoordPair(double? lat, double? lng) {
    if (lat == null || lng == null) return false;
    if (lat == 0 && lng == 0) return false;
    return lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;
  }

  (double?, double?) _resolveDeliveryCoordsFromOrderData(Map<String, dynamic> orderData) {
    const latKeys = [
      'delivery_latitude',
      'delivery_lat',
      'address_latitude',
      'address_lat',
      'buyer_latitude',
      'buyer_lat',
      'shipping_latitude',
      'shipping_lat',
    ];
    const lngKeys = [
      'delivery_longitude',
      'delivery_lng',
      'delivery_lon',
      'address_longitude',
      'address_lng',
      'address_lon',
      'buyer_longitude',
      'buyer_lng',
      'buyer_lon',
      'shipping_longitude',
      'shipping_lng',
      'shipping_lon',
    ];

    var direct = _coordsFromMap(orderData, latKeys, lngKeys);
    if (_isValidLiveCoordPair(direct.$1, direct.$2)) return direct;

    Map<String, dynamic>? address;
    final addressData = orderData['address'];
    if (addressData is String && addressData.trim().isNotEmpty) {
      try {
        final parsed = json.decode(addressData);
        if (parsed is Map) {
          address = Map<String, dynamic>.from(parsed);
        }
      } catch (_) {}
    } else if (addressData is Map) {
      address = Map<String, dynamic>.from(addressData);
    }

    if (address != null) {
      direct = _coordsFromMap(address, latKeys, lngKeys);
      if (_isValidLiveCoordPair(direct.$1, direct.$2)) return direct;

      final locationRaw = address['location'];
      if (locationRaw is Map) {
        final location = Map<String, dynamic>.from(locationRaw);
        direct = _coordsFromMap(location, ['latitude', 'lat'], ['longitude', 'lng', 'lon']);
        if (_isValidLiveCoordPair(direct.$1, direct.$2)) return direct;
      }
    }

    return (null, null);
  }

  ({String street, String house, String zip, String city, String country, String fallback}) _extractDeliveryAddressParts(Map<String, dynamic> orderData) {
    Map<String, dynamic>? address;
    final raw = orderData['address'];
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final parsed = json.decode(raw);
        if (parsed is Map) address = Map<String, dynamic>.from(parsed);
      } catch (_) {}
    } else if (raw is Map) {
      address = Map<String, dynamic>.from(raw);
    }

    String pick(List<dynamic> vals) {
      for (final v in vals) {
        final s = (v ?? '').toString().trim();
        if (s.isNotEmpty && s.toLowerCase() != 'null') return s;
      }
      return '';
    }

    final street = pick([
      address?['street'],
      address?['address_line1'],
      address?['line1'],
    ]);
    final house = pick([address?['house_number'], address?['houseNo']]);
    final zip = pick([
      address?['postal_code'],
      address?['zip_code'],
      address?['zipCode'],
      address?['zip'],
    ]);
    final city = pick([address?['city'], address?['town']]);
    final country = pick([address?['country']]);
    final fallbackAddressLine = pick([address?['address'], address?['full_address']]);

    return (
      street: street,
      house: house,
      zip: zip,
      city: city,
      country: country,
      fallback: fallbackAddressLine,
    );
  }

  String _buildDeliveryAddressQuery(Map<String, dynamic> orderData) {
    final parts = _extractDeliveryAddressParts(orderData);
    final composed = [parts.street, parts.house, parts.zip, parts.city, parts.country]
        .where((s) => s.isNotEmpty)
        .join(', ')
        .trim();
    if (composed.isNotEmpty) return composed;
    return parts.fallback;
  }

  Future<(double?, double?)> _geocodeDeliveryCoords(Map<String, dynamic> orderData) async {
    try {
      Future<(double?, double?)> tryUri(Uri uri) async {
        final resp = await http.get(uri, headers: {
          'Accept': 'application/json',
          'User-Agent': 'cultioo-app/1.0 (delivery geocode)',
        });
        if (resp.statusCode < 200 || resp.statusCode >= 300) return (null, null);
        final data = json.decode(resp.body);
        if (data is! List || data.isEmpty) return (null, null);
        final first = data.first;
        if (first is! Map) return (null, null);
        final lat = _parseLiveCoord(first['lat']);
        final lng = _parseLiveCoord(first['lon']);
        if (_isValidLiveCoordPair(lat, lng)) return (lat, lng);
        return (null, null);
      }

      final p = _extractDeliveryAddressParts(orderData);

      // 1) Structured query (more precise than free-text).
      final params = <String, String>{
        'format': 'json',
        'limit': '1',
        'addressdetails': '1',
      };
      if (p.street.isNotEmpty || p.house.isNotEmpty) {
        params['street'] = '${p.street} ${p.house}'.trim();
      }
      if (p.city.isNotEmpty) params['city'] = p.city;
      if (p.zip.isNotEmpty) params['postalcode'] = p.zip;
      if (p.country.isNotEmpty) params['country'] = p.country;

      if (params.length > 3) {
        final structured = Uri.https('nominatim.openstreetmap.org', '/search', params);
        final structuredResult = await tryUri(structured);
        if (_isValidLiveCoordPair(structuredResult.$1, structuredResult.$2)) {
          return structuredResult;
        }
      }

      // 2) Free text fallback.
      final query = _buildDeliveryAddressQuery(orderData);
      if (query.isEmpty) return (null, null);
      final freeText = Uri.https('nominatim.openstreetmap.org', '/search', {
        'format': 'json',
        'limit': '1',
        'q': query,
      });
      final freeTextResult = await tryUri(freeText);
      if (_isValidLiveCoordPair(freeTextResult.$1, freeTextResult.$2)) {
        return freeTextResult;
      }
    } catch (_) {}
    return (null, null);
  }

  int? _extractOrderAddressIdFromOrderData(Map<String, dynamic> orderData) {
    final raw = orderData['address'];
    if (raw is Map) {
      final id = int.tryParse('${raw['id'] ?? ''}');
      if (id != null && id > 0) return id;
    }
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final parsed = json.decode(raw);
        if (parsed is Map) {
          final id = int.tryParse('${parsed['id'] ?? ''}');
          if (id != null && id > 0) return id;
        }
      } catch (_) {}
    }
    return null;
  }

  (double?, double?) _coordsFromAddressRecord(Map<String, dynamic> address) {
    return _coordsFromMap(
      address,
      const ['delivery_latitude', 'delivery_lat', 'address_latitude', 'address_lat', 'lat', 'latitude'],
      const ['delivery_longitude', 'delivery_lng', 'delivery_lon', 'address_longitude', 'address_lng', 'address_lon', 'lng', 'lon', 'longitude'],
    );
  }

  Future<(double?, double?)> _resolveDeliveryCoordsFromUserAddresses(Map<String, dynamic> orderData) async {
    try {
      final addresses = await ApiService.getUserAddresses();
      if (addresses.isEmpty) return (null, null);

      final targetAddressId = _extractOrderAddressIdFromOrderData(orderData);
      Map<String, dynamic>? chosen;

      if (targetAddressId != null) {
        for (final addr in addresses) {
          final aid = int.tryParse('${addr['id'] ?? ''}');
          if (aid == targetAddressId) {
            chosen = addr;
            break;
          }
        }
      }

      chosen ??= addresses.firstWhere(
        (a) =>
            a['isSelected'] == true ||
            a['is_selected'] == true ||
            a['is_selected'] == 1 ||
            '${a['is_selected']}'.toLowerCase() == 'true',
        orElse: () => addresses.first,
      );

      final coords = _coordsFromAddressRecord(chosen);
      if (_isValidLiveCoordPair(coords.$1, coords.$2)) return coords;
    } catch (e) {
      print('⚠️ user_addresses coords lookup failed: $e');
    }
    return (null, null);
  }

  String _formatLastUpdate() {
    if (_lastUpdate == null) return 'Loading...';
    final now = DateTime.now();
    final difference = now.difference(_lastUpdate!);

    if (difference.inSeconds < 60) {
      return '${difference.inSeconds}s ago';
    } else {
      return '${difference.inMinutes}m ago';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 24, 0, 0),
      child: Column(
        children: [
          // Header with refresh indicator
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.location_fill,
                  color: widget.isDark ? Colors.white : Colors.black,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context)!.liveLocation,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: widget.isDark ? Colors.white : Colors.black,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _isLoading ? Colors.orange : Colors.green,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _isLoading ? 'Updating...' : _formatLastUpdate(),
                            style: TextStyle(
                              fontSize: 13,
                              color: widget.isDark
                                  ? Colors.grey[400]
                                  : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Manual refresh button
                TradeRepublicButton(
                  icon: Icon(
                    Icons.refresh,
                    size: 18,
                  ),
                  isSecondary: true,
                  width: 44,
                  height: 44,
                  padding: EdgeInsets.zero,
                  borderRadius: BorderRadius.circular(25),
                  onPressed: _loadLocation,
                ),
              ],
            ),
          ),

          // OpenStreetMap
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(25),
              ),

              clipBehavior: Clip.antiAlias,
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: LatLng(_latitude, _longitude),
                  initialZoom: 15.0,
                  minZoom: 5.0,
                  maxZoom: 18.0,
                ),
                children: [
                  TileLayer(
                    urlTemplate: widget.isDark
                        ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
                        : 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
                    retinaMode: RetinaMode.isHighDensity(context),
                    subdomains: const ['a', 'b', 'c', 'd'],
                    userAgentPackageName: 'com.cultioo.app',
                    maxZoom: 19,
                  ),
                  MarkerLayer(
                    markers: [
                      // ── Nearby drivers (grey truck markers) ──────────────
                      ..._nearbyDrivers.map((driver) {
                        final dLat = double.tryParse(driver['latitude']?.toString() ?? '') ?? 0;
                        final dLng = double.tryParse(driver['longitude']?.toString() ?? '') ?? 0;
                        if (dLat == 0 && dLng == 0) return null;
                        final name = (driver['name'] ?? driver['username'] ?? '?').toString();
                        final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
                        return Marker(
                          point: LatLng(dLat, dLng),
                          width: 40,
                          height: 40,
                          child: Container(
                            decoration: BoxDecoration(
                              color: widget.isDark ? const Color(0xFF2C2C2E) : Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: TradeRepublicTheme.textColor(context).withOpacity(0.6),
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.18),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Center(
                              child: Text(
                                initial,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: TradeRepublicTheme.textColor(context),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).whereType<Marker>(),

                      // ── Delivery destination marker ───────────────────────
                      if (_isValidLiveCoordPair(_deliveryLatitude, _deliveryLongitude))
                        Marker(
                          point: LatLng(_deliveryLatitude!, _deliveryLongitude!),
                          width: 28,
                          height: 28,
                          child: Container(
                            decoration: BoxDecoration(
                              color: TradeRepublicTheme.textColor(context),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: TradeRepublicTheme.textColor(context).withOpacity(0.35),
                                  blurRadius: 10,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Icon(
                              CupertinoIcons.location_solid,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),

                      // ── Assigned driver (primary marker) ─────────────────
                      Marker(
                        point: LatLng(_latitude, _longitude),
                        width: 50,
                        height: 50,
                        alignment: Alignment.topCenter,
                        child: Stack(
                          alignment: Alignment.topCenter,
                          children: [
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: widget.isDark
                                    ? Colors.white.withOpacity(0.2)
                                    : Colors.black.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                            ),
                            Container(
                              width: 36,
                              height: 36,
                              margin: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: widget.isDark ? Colors.white : Colors.black,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: widget.isDark ? Colors.black : Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                ),
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
    );
  }
}

// Input formatter to group card numbers as 1234 5678 9012 3456
class _CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final truncated = digits.length > 16 ? digits.substring(0, 16) : digits;

    final buffer = StringBuffer();
    for (int i = 0; i < truncated.length; i++) {
      if (i > 0 && i % 4 == 0) buffer.write(' ');
      buffer.write(truncated[i]);
    }
    final formatted = buffer.toString();

    // Preserve cursor position relative to digits typed
    final selectionDigits = _clampSelectionToDigits(newValue);
    final newSelection = _mapDigitSelectionToFormatted(
      formatted,
      selectionDigits,
    );

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: newSelection),
    );
  }

  int _clampSelectionToDigits(TextEditingValue value) {
    final clampedCursor = value.selection.baseOffset.clamp(
      0,
      value.text.length,
    );
    final digitsBeforeCursor = value.text
        .substring(0, clampedCursor)
        .replaceAll(RegExp(r'\D'), '')
        .length;
    return digitsBeforeCursor > 16 ? 16 : digitsBeforeCursor;
  }

  int _mapDigitSelectionToFormatted(String formatted, int digitIndex) {
    if (digitIndex <= 0) return 0;

    int digitsSeen = 0;
    for (int i = 0; i < formatted.length; i++) {
      if (formatted[i] != ' ') {
        digitsSeen++;
        if (digitsSeen == digitIndex) {
          return i + 1; // place cursor after the digit
        }
      }
    }
    return formatted.length;
  }
}

// Input formatter to enforce MM/YY with slash auto-inserted
class _ExpiryDateFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final truncated = digits.length > 4 ? digits.substring(0, 4) : digits;

    String formatted;
    if (truncated.length <= 2) {
      formatted = truncated;
    } else {
      formatted = '${truncated.substring(0, 2)}/${truncated.substring(2)}';
    }

    final clampedCursor = newValue.selection.baseOffset.clamp(
      0,
      truncated.length,
    );
    final selectionDigits = truncated.substring(0, clampedCursor).length;
    final selectionOffset = selectionDigits <= 2
        ? selectionDigits
        : selectionDigits + 1; // Account for slash

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(
        offset: selectionOffset.clamp(0, formatted.length),
      ),
    );
  }
}

// Formats a currency field RTL-style: digits push from the right through a
// fixed 2-decimal-place slot. Typing "12345" produces "123.45".
// Formats a currency field RTL-style with thousands separators.
// Typing "123456" produces "1,234.56". Only digits are accepted;
// commas and the decimal point are inserted automatically.
class _CurrencyRtlFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Keep only raw digits
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');

    // Cap at 10 digits → max 99,999,999.99
    final capped = digits.length > 10 ? digits.substring(0, 10) : digits;

    if (capped.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    // Always treat last 2 digits as decimals
    final padded  = capped.padLeft(3, '0');
    final rawInt  = padded.substring(0, padded.length - 2);
    final decPart = padded.substring(padded.length - 2);

    // Strip leading zeros from integer part (keep at least "0")
    final cleanInt = rawInt.replaceFirst(RegExp(r'^0+'), '').isEmpty
        ? '0'
        : rawInt.replaceFirst(RegExp(r'^0+'), '');

    // Insert thousands commas: reverse → chunk by 3 → reverse back
    final withCommas = cleanInt.split('').reversed
        .toList()
        .asMap()
        .entries
        .map((e) => (e.key > 0 && e.key % 3 == 0) ? '${e.value},' : e.value)
        .toList()
        .reversed
        .join();

    final formatted = '$withCommas.$decPart';

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

// ==========================================
// Progress Step Data Model
// ==========================================
class _ProgressStep {
  final String id;
  final String label;
  final IconData icon;
  final Color color;

  const _ProgressStep({
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
  });
}

// ==========================================
// Shipping Net Payment Sheet (Net 30/60)
// ==========================================
class _ShippingNetPaymentSheet extends StatefulWidget {
  final bool isDark;
  final String title;
  final String description;
  final int? days;
  final double shippingCost;
  final double remainingLimit;
  final bool isOverLimit;
  final double overLimitFee;
  final String paymentType;
  final Map<String, dynamic> bid;
  final TextEditingController businessNameController;
  final TextEditingController businessTaxIdController;
  final TextEditingController businessEmailController;
  final TextEditingController businessPhoneController;
  final TextEditingController businessStreetController;
  final TextEditingController businessHouseNumberController;
  final TextEditingController businessPostalCodeController;
  final TextEditingController businessCityController;
  final TextEditingController businessCountryController;
  final bool isLoadingBusinessInfo;
  final String Function(dynamic) formatCurrency;
  final double monthlyPaymentLimit;
  final double currentMonthUsage;
  final double overLimitFeePercent;
  final bool Function() validateBusinessInfo;
  final Future<void> Function(String) submitBusinessInfo;
  final VoidCallback onClose;

  const _ShippingNetPaymentSheet({
    required this.isDark,
    required this.title,
    required this.description,
    this.days,
    required this.shippingCost,
    required this.remainingLimit,
    required this.isOverLimit,
    required this.overLimitFee,
    required this.paymentType,
    required this.bid,
    required this.businessNameController,
    required this.businessTaxIdController,
    required this.businessEmailController,
    required this.businessPhoneController,
    required this.businessStreetController,
    required this.businessHouseNumberController,
    required this.businessPostalCodeController,
    required this.businessCityController,
    required this.businessCountryController,
    required this.isLoadingBusinessInfo,
    required this.formatCurrency,
    required this.monthlyPaymentLimit,
    required this.currentMonthUsage,
    required this.overLimitFeePercent,
    required this.validateBusinessInfo,
    required this.submitBusinessInfo,
    required this.onClose,
  });

  @override
  State<_ShippingNetPaymentSheet> createState() =>
      _ShippingNetPaymentSheetState();
}

class _ShippingNetPaymentSheetState extends State<_ShippingNetPaymentSheet> {
  int _currentPage = 0; // 0 = info page, 1 = business form
  bool _isSubmitting = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Content based on current page
        Expanded(
          child: _currentPage == 0
              ? _buildInfoPage()
              : _buildBusinessFormPage(),
        ),
      ],
    );
  }

  // Info Page - First page with payment terms and late fee info
  Widget _buildInfoPage() {
    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Text(
                widget.title,
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.w900,
                  color: widget.isDark ? Colors.white : Colors.black,
                  letterSpacing: -2.0,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.description,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: widget.isDark ? Colors.white60 : Colors.black54,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Content
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Payment Terms - Grid Layout
                if (widget.days != null) ...[
                  Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _buildStatCard(
                              label: AppLocalizations.of(context)!.paymentDue,
                              value: '${widget.days} days',
                              icon: CupertinoIcons.calendar,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildStatCard(
                              label: AppLocalizations.of(context)!.shippingCost,
                              value: widget.formatCurrency(widget.shippingCost),
                              icon: CupertinoIcons.cube_box,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildStatCard(
                              label: AppLocalizations.of(context)!.creditLimit,
                              value: widget.formatCurrency(
                                widget.monthlyPaymentLimit,
                              ),
                              icon: CupertinoIcons.money_dollar_circle_fill,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildStatCard(
                              label: AppLocalizations.of(context)!.available,
                              value: widget.formatCurrency(
                                widget.remainingLimit,
                              ),
                              icon: CupertinoIcons.checkmark_circle_fill,
                              isPositive: true,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],

                // Late Payment Section - Modern Design
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Section Header
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(25),
                            ),

                            child: Icon(
                              CupertinoIcons.exclamationmark_triangle_fill,
                              color: Colors.red.shade600,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  AppLocalizations.of(
                                    context,
                                  )!.latePaymentConsequences,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: widget.isDark
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  AppLocalizations.of(
                                    context,
                                  )!.whatHappensIfPaymentIsDelayed,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: widget.isDark
                                        ? Colors.white60
                                        : Colors.black45,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Timeline Steps
                    _buildPenaltyCard(
                      day: 'Day ${widget.days ?? 30}',
                      title: AppLocalizations.of(context)!.paymentReminder,
                      penalty: '+5% Late Fee',
                      color: Colors.orange.shade400,
                      icon: CupertinoIcons.bell_fill,
                    ),
                    const SizedBox(height: 12),
                    _buildPenaltyCard(
                      day: 'Day ${(widget.days ?? 30) + 2}',
                      title: AppLocalizations.of(context)!.accountSuspended,
                      penalty: '+15% Total Fee',
                      color: Colors.red.shade400,
                      icon: CupertinoIcons.nosign,
                    ),
                    const SizedBox(height: 12),
                    _buildPenaltyCard(
                      day: 'Day ${(widget.days ?? 30) + 4}',
                      title: AppLocalizations.of(context)!.legalAction,
                      penalty: AppLocalizations.of(context)!.lawsuitFiled,
                      color: Colors.red.shade700,
                      icon: CupertinoIcons.hammer_fill,
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Over limit warning if applicable
                if (widget.isOverLimit) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.orange.withOpacity(0.15),
                          Colors.orange.withOpacity(0.05),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(25),
                    ),

                    child: Row(
                      children: [
                        Icon(
                          CupertinoIcons.exclamationmark_triangle,
                          color: Colors.orange,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Over Limit: +${widget.formatCurrency(widget.overLimitFee)} (${widget.overLimitFeePercent}%)',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.orange.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Terms acceptance note
                Row(
                  children: [
                    Icon(
                      CupertinoIcons.info,
                      color: widget.isDark ? Colors.white38 : Colors.black38,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        AppLocalizations.of(
                          context,
                        )!.byContinuingYouAgreeToTheseTerms,
                        style: TextStyle(
                          fontSize: 13,
                          color: widget.isDark
                              ? Colors.white54
                              : Colors.black45,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),

        // Continue Button
        Padding(
          padding: const EdgeInsets.all(24),
          child: TradeRepublicButton(
            label: AppLocalizations.of(context)!.continueButton,
            onPressed: () {
              setState(() {
                _currentPage = 1;
              });
            },
            width: double.infinity,
          ),
        ),
      ],
    );
  }

  // Stat card for payment terms grid
  Widget _buildStatCard({
    required String label,
    required String value,
    required IconData icon,
    bool isPositive = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: widget.isDark
            ? const Color(0xFF141414)
            : Colors.black.withOpacity(0.02),
        borderRadius: BorderRadius.circular(25),
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 24,
            color: isPositive
                ? Colors.green.shade400
                : (widget.isDark ? Colors.white70 : Colors.black54),
          ),
          const SizedBox(height: 16),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              color: widget.isDark ? Colors.white60 : Colors.black54,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: isPositive
                  ? Colors.green.shade400
                  : (widget.isDark ? Colors.white : Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  // Penalty card for late payment timeline
  Widget _buildPenaltyCard({
    required String day,
    required String title,
    required String penalty,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(25),
      ),

      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(25),
            ),

            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      day,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: color,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(25),
                      ),

                      child: Text(
                        penalty,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: widget.isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Business Form Page - Second page with business info form
  Widget _buildBusinessFormPage() {
    return Column(
      children: [
        // Back button and header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              TradeRepublicButton(
                icon: Icon(
                  Icons.arrow_back,
                  size: 18,
                ),
                isSecondary: true,
                width: 44,
                height: 44,
                padding: EdgeInsets.zero,
                borderRadius: BorderRadius.circular(25),
                onPressed: () {
                  setState(() {
                    _currentPage = 0;
                  });
                },
              ),
              Expanded(
                child: Text(
                  AppLocalizations.of(context)!.businessInformation,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: widget.isDark ? Colors.white : Colors.black,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // Form Content
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildBusinessTextField(
                  controller: widget.businessNameController,
                  label: AppLocalizations.of(context)!.businessName,
                  hint: AppLocalizations.of(
                    context,
                  )!.enterYourRegisteredBusinessName,
                  icon: Icons.business,
                ),
                const SizedBox(height: 16),

                _buildBusinessTextField(
                  controller: widget.businessTaxIdController,
                  label: AppLocalizations.of(context)!.taxIdEin,
                  hint: AppLocalizations.of(context)!.taxIdEinHint,
                  icon: Icons.badge,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),

                _buildBusinessTextField(
                  controller: widget.businessEmailController,
                  label: AppLocalizations.of(context)!.businessEmail,
                  hint: 'accounting@business.com',
                  icon: Icons.email,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),

                _buildBusinessTextField(
                  controller: widget.businessPhoneController,
                  label: AppLocalizations.of(context)!.businessPhone,
                  hint: '+1 (555) 123-4567',
                  icon: Icons.phone,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 16),

                _buildBusinessTextField(
                  controller: widget.businessStreetController,
                  label: AppLocalizations.of(context)!.street,
                  hint: AppLocalizations.of(context)!.enterStreetName,
                  icon: Icons.location_on,
                ),
                const SizedBox(height: 16),

                _buildBusinessTextField(
                  controller: widget.businessHouseNumberController,
                  label: AppLocalizations.of(context)!.houseNumber1,
                  hint: AppLocalizations.of(context)!.enterHouseNumber,
                  icon: Icons.home,
                ),
                const SizedBox(height: 16),

                _buildBusinessTextField(
                  controller: widget.businessPostalCodeController,
                  label: AppLocalizations.of(context)!.postalCode,
                  hint: AppLocalizations.of(context)!.enterPostalCode,
                  icon: Icons.mail,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),

                _buildBusinessTextField(
                  controller: widget.businessCityController,
                  label: AppLocalizations.of(context)!.city,
                  hint: AppLocalizations.of(context)!.enterCity,
                  icon: Icons.location_city,
                ),
                const SizedBox(height: 16),

                _buildBusinessTextField(
                  controller: widget.businessCountryController,
                  label: AppLocalizations.of(context)!.country,
                  hint: AppLocalizations.of(context)!.enterCountry,
                  icon: Icons.public,
                ),

                const SizedBox(height: 24),

                // Terms & Conditions
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: widget.isDark
                        ? const Color(0xFF141414)
                        : Colors.black.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(25),
                  ),

                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context)!.termsConditions,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: widget.isDark ? Colors.white : Colors.black,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '• Information will be verified with credit bureaus\n'
                        '• Payment due within ${widget.days ?? 30} days\n'
                        '• Late fees: +5% (1st reminder), +15% total (2nd reminder)\n'
                        '• Subject to approval and credit check',
                        style: TextStyle(
                          fontSize: 13,
                          color: widget.isDark
                              ? Colors.white70
                              : Colors.black54,
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

        // Submit Button
        Padding(
          padding: const EdgeInsets.all(24),
          child: TradeRepublicButton(
            label: AppLocalizations.of(context)!.submitContinue,
            onPressed: _isSubmitting
                ? null
                : () async {
                    if (widget.validateBusinessInfo()) {
                      setState(() => _isSubmitting = true);
                      try {
                        await widget.submitBusinessInfo(widget.paymentType);
                        widget.onClose();
                      } finally {
                        if (mounted) {
                          setState(() => _isSubmitting = false);
                        }
                      }
                    }
                  },
            isLoading: _isSubmitting,
            width: double.infinity,
          ),
        ),
      ],
    );
  }

  // Business TextField Helper
  Widget _buildBusinessTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: widget.isDark ? Colors.white : Colors.black,
          ),
        ),
        const SizedBox(height: 12),
        TradeRepublicTextField(
          controller: controller,
          hintText: hint,
          prefixIcon: Icon(icon, size: 24),
          maxLines: maxLines,
          keyboardType: keyboardType,
        ),
      ],
    );
  }
}
