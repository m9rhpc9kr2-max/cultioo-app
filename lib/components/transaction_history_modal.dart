import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../services/api_service.dart';
import 'dart:convert';
import 'dart:typed_data';
import '../utils/number_formatters.dart';

import '../main.dart';
import '../services/app_localizations.dart';
import '../services/cultioo_spinner.dart';

class TransactionHistoryModal extends StatefulWidget {
  final String? numberFormat; // Number format preference

  const TransactionHistoryModal({super.key, this.numberFormat});

  @override
  State<TransactionHistoryModal> createState() =>
      _TransactionHistoryModalState();
}

class _TransactionHistoryModalState extends State<TransactionHistoryModal> {
  List<Map<String, dynamic>> orders = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  // Format currency according to number format preference
  String _formatCurrency(double amount) {
    setNumberFormatStyleIndex(widget.numberFormat == 'de' ? 1 : 0);
    return formatCurrencyUsd(amount);
  }

  Future<void> _loadOrders() async {
    try {
      final response = await ApiService.getUserOrders();
      if (response['success'] == true) {
        setState(() {
          orders = List<Map<String, dynamic>>.from(response['orders'] ?? []);
          isLoading = false;
        });
      } else {
        setState(() {
          orders = [];
          isLoading = false;
        });
      }
    } catch (e) {
      //print('Error loading orders: $e');
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        // Title
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
                AppLocalizations.of(context)!.orderHistory,
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
        const SizedBox(height: 20),
        // Content
        Expanded(
          child: isLoading
              ? _buildLoadingState(isDark)
              : orders.isEmpty
              ? _buildEmptyState(isDark)
              : ListView.builder(
                  itemCount: orders.length,
                  itemBuilder: (context, index) {
                    final order = orders[index];
                    return _buildOrderItem(order, isDark);
                  },
                ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildLoadingState(bool isDark) {
    return Center(
      child: CultiooLoadingIndicator(),
    );
  }

  Widget _buildOrderItem(Map<String, dynamic> order, bool isDark) {
    final orderNumber =
        (order['order_number'] ?? order['id'])?.toString() ?? 'N/A';
    final status = order['status'] as String? ?? 'pending';
    final totalAmount = (order['total_amount'] as num?)?.toDouble() ?? 0.0;
    final createdAt =
        (order['created_at'] ?? order['order_date']) as String? ??
        DateTime.now().toIso8601String();
    final items = order['items'] as List<dynamic>? ?? [];

    // Format delivery address from address object
    String deliveryAddress = '';
    final addressData = order['address'];
    if (addressData != null && addressData is Map) {
      final street = addressData['street'] ?? '';
      final city = addressData['city'] ?? '';
      final postalCode =
          addressData['postalCode'] ?? addressData['postal_code'] ?? '';
      final country = addressData['country'] ?? '';

      List<String> parts = [];
      if (street.toString().isNotEmpty) parts.add(street.toString());
      if (city.toString().isNotEmpty) parts.add(city.toString());
      if (postalCode.toString().isNotEmpty) parts.add(postalCode.toString());
      if (country.toString().isNotEmpty) parts.add(country.toString());

      deliveryAddress = parts.join(', ');
    } else if (addressData is String && addressData.isNotEmpty) {
      deliveryAddress = addressData;
    }

    // Determine status color and display text
    Color statusColor;
    String statusLabel;
    switch (status.toLowerCase()) {
      case 'delivered':
      case 'completed':
        statusColor = const Color(0xFF34C759);
        statusLabel = AppLocalizations.of(context)!.delivered;
        break;
      case 'accepted':
        statusColor = const Color(0xFF34C759);
        statusLabel = AppLocalizations.of(context)!.accepted;
        break;
      case 'succeeded':
        statusColor = const Color(0xFF34C759);
        statusLabel = AppLocalizations.of(context)!.paymentSuccessful;
        break;
      case 'shipped':
        statusColor = const Color(0xFF007AFF);
        statusLabel = AppLocalizations.of(context)!.shipped;
        break;
      case 'picked_up':
        statusColor = const Color(0xFF007AFF);
        statusLabel = AppLocalizations.of(context)!.pickedUp;
        break;
      case 'confirmed':
        statusColor = const Color(0xFF5856D6);
        statusLabel = AppLocalizations.of(context)!.confirmed;
        break;
      case 'processing':
        statusColor = const Color(0xFFFF9500);
        statusLabel = AppLocalizations.of(context)!.processing;
        break;
      case 'pending':
        statusColor = const Color(0xFFFF9500);
        statusLabel = AppLocalizations.of(context)!.pending;
        break;
      case 'awaiting':
        statusColor = const Color(0xFFFF9500);
        statusLabel = AppLocalizations.of(context)!.awaitingPayment;
        break;
      case 'cancelled':
      case 'canceled':
        statusColor = const Color(0xFFFF3B30);
        statusLabel = AppLocalizations.of(context)!.cancelled;
        break;
      case 'failed':
        statusColor = const Color(0xFFFF3B30);
        statusLabel = AppLocalizations.of(context)!.failed;
        break;
      case 'requires_payment_method':
        statusColor = const Color(0xFFFF9500);
        statusLabel = AppLocalizations.of(context)!.paymentRequired;
        break;
      case 'requires_confirmation':
        statusColor = const Color(0xFFFF9500);
        statusLabel = AppLocalizations.of(context)!.confirmationRequired;
        break;
      case 'requires_action':
        statusColor = const Color(0xFFFF9500);
        statusLabel = AppLocalizations.of(context)!.actionRequired;
        break;
      case 'requires_capture':
        statusColor = const Color(0xFFFF9500);
        statusLabel = AppLocalizations.of(context)!.captureRequired;
        break;
      default:
        statusColor = const Color(0xFF8E8E93);
        // Format unknown status nicely
        final words = status.split('_');
        statusLabel = words.map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: isDark 
              ? Colors.white.withOpacity(0.03)
              : Colors.black.withOpacity(0.04),
            offset: const Offset(0, 2),
            blurRadius: 8,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Order number and Amount
          Row(
            children: [
              Expanded(
                child: Text(
                  '#$orderNumber',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
              Text(
                _formatCurrency(totalAmount),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : Colors.black,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Status and Date
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _formatDate(createdAt),
                style: TextStyle(
                  fontSize: 13,
                  color: isDark
                      ? const Color(0xFF8E8E93)
                      : const Color(0xFF8E8E93),
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),

          // Items
          if (items.isNotEmpty) ...[
            const SizedBox(height: 16),
            ...items.take(2).map((item) {
              final itemName =
                  (item['name'] ?? item['title'] ?? item['productName'])
                      as String? ??
                  AppLocalizations.of(context)!.unknownItem;
              final quantity =
                  (item['quantity'] ?? item['qty'] ?? 1 as num).toInt();
              
              // Get product image with debug output
              String imageUrl = '';
              print('🖼️ Item data: ${item.toString()}');
              
              if (item['image_url'] != null && item['image_url'].toString().isNotEmpty) {
                imageUrl = item['image_url'].toString();
                print('✅ Using image_url: $imageUrl');
              } else if (item['primary_image'] != null && item['primary_image'].toString().isNotEmpty) {
                imageUrl = item['primary_image'].toString();
                print('✅ Using primary_image: $imageUrl');
              } else if (item['images'] != null && item['images'] is List) {
                final images = item['images'] as List;
                print('📦 Images array length: ${images.length}');
                if (images.isNotEmpty) {
                  if (images[0] is Map) {
                    imageUrl = images[0]['url']?.toString() ?? images[0]['image_url']?.toString() ?? '';
                    print('✅ Using images[0]: $imageUrl');
                  } else if (images[0] is String) {
                    imageUrl = images[0].toString();
                    print('✅ Using images[0] string: $imageUrl');
                  }
                }
              }
              
              if (imageUrl.isEmpty) {
                print('❌ No image found for item: ${item['name']}');
              }
              
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    if (imageUrl.isNotEmpty)
                      Container(
                        width: 40,
                        height: 40,
                        margin: const EdgeInsets.only(right: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(25),
                          color: isDark
                              ? Colors.white.withOpacity(0.03)
                              : Colors.black.withOpacity(0.02),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(25),
                          child: imageUrl.startsWith('data:image') || imageUrl.startsWith('/9j/')
                              ? Image.memory(
                                  _decodeBase64Image(imageUrl),
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Icon(
                                      CupertinoIcons.photo,
                                      size: 20,
                                      color: isDark
                                          ? const Color(0xFF636366)
                                          : const Color(0xFFC7C7CC),
                                    );
                                  },
                                )
                              : Image.network(
                                  imageUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Icon(
                                      CupertinoIcons.photo,
                                      size: 20,
                                      color: isDark
                                          ? const Color(0xFF636366)
                                          : const Color(0xFFC7C7CC),
                                    );
                                  },
                                ),
                        ),
                      )
                    else
                      Container(
                        width: 40,
                        height: 40,
                        margin: const EdgeInsets.only(right: 12),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withOpacity(0.03)
                              : Colors.black.withOpacity(0.02),
                          borderRadius: BorderRadius.circular(25),
                        ),
                        child: Icon(
                          CupertinoIcons.photo,
                          size: 20,
                          color: isDark
                              ? const Color(0xFF636366)
                              : const Color(0xFFC7C7CC),
                        ),
                      ),
                    Expanded(
                      child: Text(
                        '$quantity× $itemName',
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.white : Colors.black,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            }),
            if (items.length > 2)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '+${items.length - 2} more',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? const Color(0xFF636366)
                        : const Color(0xFF8E8E93),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Uint8List _decodeBase64Image(String base64String) {
    // Remove data:image/jpeg;base64, prefix if present
    String cleanBase64 = base64String;
    if (base64String.startsWith('data:image')) {
      cleanBase64 = base64String.split(',')[1];
    }
    return base64Decode(cleanBase64);
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
                borderRadius: BorderRadius.circular(25),
                boxShadow: [
                  BoxShadow(
                    color: isDark 
                      ? Colors.white.withOpacity(0.03)
                      : Colors.black.withOpacity(0.04),
                    offset: const Offset(0, 2),
                    blurRadius: 8,
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: Icon(
                CupertinoIcons.bag,
                size: 40,
                color: isDark ? Colors.grey[600] : Colors.grey[400],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              AppLocalizations.of(context)!.noOrders,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context)!.yourOrderHistoryWillAppearHereWhenYouMake,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final transactionDate = DateTime(date.year, date.month, date.day);

      final timeStr =
          '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

      if (transactionDate == today) {
        return AppLocalizations.of(context)!.todayAtTime(timeStr);
      } else if (transactionDate == yesterday) {
        return AppLocalizations.of(context)!.yesterdayAtTime(timeStr);
      } else {
        final currentFormat = MyApp.getCurrentDateFormat() ?? 'dd.MM.yyyy';
        final dateStr = MyApp.formatDateGlobally(date, currentFormat);
        return '$dateStr, $timeStr';
      }
    } catch (e) {
      return dateStr;
    }
  }
}
