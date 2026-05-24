import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import '../utils/number_formatters.dart';
import '../services/api_service.dart';
import '../services/app_localizations.dart';
import '../services/trade_republic_widgets.dart';
import '../services/cultioo_spinner.dart';

class CartModal extends StatefulWidget {
  final Function(String, {required bool isSuccess})? showBottomMessage;
  final VoidCallback? onCartChanged;
  final Function(
    bool isDark,
    List<Map<String, dynamic>> cartItems,
    double totalPrice,
  )?
  onProceedToCheckout;
  final String? currency; // Currency preference ('usd', 'eur')
  final double? exchangeRate; // USD to EUR exchange rate
  final String? numberFormat; // Number format preference

  const CartModal({
    super.key,
    this.showBottomMessage,
    this.onCartChanged,
    this.onProceedToCheckout,
    this.currency,
    this.exchangeRate,
    this.numberFormat,
  });

  @override
  State<CartModal> createState() => _CartModalState();
}

class _CartModalState extends State<CartModal> {
  List<Map<String, dynamic>> _cartItems = [];
  final Map<String, Map<String, dynamic>> _productDetails = {};
  bool _isLoading = true;
  bool _isCheckoutPressed = false; // Add debounce flag
  bool _hasPaymentMethod = false; // true once at least one saved method exists

  double _parseNumericValue(dynamic value, {double fallback = 0.0}) {
    if (value is num) {
      return value.toDouble();
    }

    if (value is String) {
      return double.tryParse(value.trim().replaceAll(',', '.')) ?? fallback;
    }

    return fallback;
  }

  double _normalizeCartQuantity(
    dynamic storedQuantity, {
    Map<String, dynamic>? product,
    int variantIdx = 0,
  }) {
    return _parseNumericValue(storedQuantity, fallback: 1.0);
  }

  @override
  void initState() {
    super.initState();
    _loadCartContents();
    _checkPaymentMethods();
  }

  Future<void> _checkPaymentMethods() async {
    try {
      final methods = await ApiService.getUserPaymentMethods();
      if (mounted) {
        setState(() {
          _hasPaymentMethod = methods.isNotEmpty;
        });
      }
    } catch (_) {
      // silently ignore – button stays disabled
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  String _formatCurrency(double amount) {
    double finalAmount = amount;
    String symbol = '\$';
    if (widget.currency == 'eur') {
      finalAmount = amount * (widget.exchangeRate ?? 0.85);
      symbol = '{currencySymbol}';
    }
    setNumberFormatStyleIndex(widget.numberFormat == 'de' ? 1 : 0);
    return '$symbol${formatNumberUS(finalAmount)}';
  }

  Future<void> _loadCartContents() async {
    try {
      setState(() {
        _isLoading = true;
      });

      final response = await ApiService.getCart();
      debugPrint('🛒 Cart response: $response');

      if (response['success'] == true) {
        final cartData = response['cartItems'];
        debugPrint('🛒 Cart data type: ${cartData.runtimeType}');
        debugPrint('🛒 Cart data: $cartData');

        if (cartData != null) {
          final List<Map<String, dynamic>> cartItems = [];
          final List<Map<String, int>> itemsToRemove =
              []; // Track items to remove with variant info

          debugPrint('🛒 Processing ${cartData.length} cart items');

          for (var item in cartData) {
            debugPrint('🛒 Cart item: $item');
            final rawProductId = item['productId'];
            // Parse productId to int (handles String "2", int 2, or BigInt-string "2n")
            final productId = rawProductId is int
                ? rawProductId
                : int.tryParse(rawProductId.toString().replaceAll(RegExp(r'[^0-9]'), ''));
            final variantIdx = item['variantIdx'] ?? 0;
            debugPrint(
              '🛒 Product ID: $productId (type: ${productId.runtimeType}), Variant: $variantIdx',
            );

            if (productId == null) {
              debugPrint('⚠️ Skipping item with unparseable productId: $rawProductId');
              continue;
            }

            try {
              // Fetch product details
              debugPrint('📦 Fetching product with ID: $productId');
              final productResponse = await ApiService.getProduct(productId);
              if (!mounted) return;

              if (productResponse['success'] == true) {
                final product = productResponse['product'];
                debugPrint('✅ Product fetched successfully: ${product['name']}');
                debugPrint('🛒 Product response for $productId: $productResponse');

                // Store product details with proper key type
                _productDetails[productId.toString()] = product;
                debugPrint(
                  '🛒 Added product details for $productId (key type: ${productId.runtimeType})',
                );

                final normalizedQuantity = _normalizeCartQuantity(
                  item['quantity'],
                  product: product,
                  variantIdx: variantIdx,
                );

                // Get price and name from the correct variant
                String productName = product['name'] ?? AppLocalizations.of(context)!.unknownProduct;
                dynamic productPrice = product['price'] ?? '0.00';
                String? productUnit; // Add unit variable

                // Check if variants exist and get the correct one
                if (product['variants'] != null &&
                    product['variants'] is List) {
                  final variants = product['variants'] as List;
                  debugPrint('🔍 Product has ${variants.length} variants');
                  if (variantIdx < variants.length) {
                    final selectedVariant = variants[variantIdx];
                    debugPrint('🔍 Selected variant at index $variantIdx: $selectedVariant');
                    debugPrint('🔍 Unit from variant: ${selectedVariant['unit']}');
                    if (selectedVariant['title'] != null &&
                        selectedVariant['title'].toString().isNotEmpty) {
                      productName =
                          '${product['name']} - ${selectedVariant['title']}';
                    }
                    productPrice = selectedVariant['price'] ?? productPrice;
                    productUnit = selectedVariant['unit']; // Extract unit from variant
                    debugPrint('🔍 Extracted unit: $productUnit');
                  } else if (variants.isNotEmpty) {
                    // Fallback to first variant if variantIdx is out of bounds
                    debugPrint('🔍 variantIdx out of bounds, using first variant');
                    productPrice = variants[0]['price'] ?? productPrice;
                    productUnit = variants[0]['unit']; // Get unit from first variant
                    debugPrint('🔍 Unit from first variant: $productUnit');
                  }
                }

                // Add to cart items with product details for checkout
                cartItems.add({
                  'productId': productId,
                  'variantIdx': variantIdx,
                  'quantity': normalizedQuantity,
                  'addedAt': item['addedAt'],
                  'name': productName,
                  'price': productPrice,
                  'unit': productUnit ?? 'kg', // Add unit to cart item
                  'seller':
                      product['username'] ??
                      AppLocalizations.of(context)!.unknownSeller, // Add seller username
                  'category': product['category'] ?? 'General', // Add category
                });
              } else {
                debugPrint('❌ Product fetch failed: ${productResponse['message']}');
                // Track for removal - product doesn't exist anymore
                itemsToRemove.add({
                  'productId': productId,
                  'variantIdx': variantIdx,
                });
              }
            } catch (e) {
              debugPrint('🛒 Error fetching product $productId: $e');
              itemsToRemove.add({
                'productId': productId,
                'variantIdx': variantIdx,
              });
            }
          }

          // Remove invalid items from cart
          for (var item in itemsToRemove) {
            try {
              debugPrint(
                '🛒 Removing invalid product ${item['productId']} (variant ${item['variantIdx']}) from cart',
              );
              await ApiService.removeFromCart(
                item['productId']!,
                variantIdx: item['variantIdx']!,
              );
              if (!mounted) return;
            } catch (e) {
              debugPrint(
                '🛒 Error removing invalid product ${item['productId']}: $e',
              );
            }
          }

          await _loadCartContents();
          if (!mounted) return;

          setState(() {
            _cartItems = cartItems;
            _isLoading = false;
          });

          debugPrint('🛒 Final cart items: ${_cartItems.length}');
          debugPrint('🛒 Final product details: ${_productDetails.length}');
        } else {
          setState(() {
            _cartItems = [];
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _cartItems = [];
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('🛒 Error loading cart: $e');
      setState(() {
        _cartItems = [];
        _isLoading = false;
      });
    }
  }

  Future<void> _updateQuantity(
    int productId,
    int newQuantity, {
    int variantIdx = 0,
  }) async {
    if (newQuantity <= 0) {
      await _removeItem(productId, variantIdx: variantIdx);
      return;
    }

    try {
      final updateResponse = await ApiService.updateCartQuantity(
        productId,
        newQuantity,
        variantIdx: variantIdx,
      );
      if (!mounted) return;

      if (updateResponse['success'] == true) {
        await _loadCartContents();
        widget.onCartChanged?.call();
        widget.showBottomMessage?.call(AppLocalizations.of(context)!.quantityUpdated, isSuccess: true);
      } else {
        widget.showBottomMessage?.call(
          AppLocalizations.of(context)!.failedToUpdateQuantity,
          isSuccess: false,
        );
      }
    } catch (e) {
      debugPrint('Error updating quantity: $e');
      widget.showBottomMessage?.call(
        AppLocalizations.of(context)!.errorUpdatingQuantity,
        isSuccess: false,
      );
    }
  }

  Future<void> _removeItem(int productId, {int variantIdx = 0}) async {
    try {
      debugPrint('🛒 Removing product $productId (variant $variantIdx) from cart');
      final removalResponse = await ApiService.removeFromCart(
        productId,
        variantIdx: variantIdx,
      );
      if (!mounted) return;

      if (removalResponse['success'] == true) {
        await _loadCartContents();
        widget.onCartChanged?.call();
        widget.showBottomMessage?.call(
          AppLocalizations.of(context)!.itemRemovedFromCart,
          isSuccess: true,
        );
      } else {
        widget.showBottomMessage?.call(
          AppLocalizations.of(context)!.failedToRemoveItem,
          isSuccess: false,
        );
      }
    } catch (e) {
      debugPrint('Error removing item: $e');
      widget.showBottomMessage?.call(AppLocalizations.of(context)!.errorRemovingItem, isSuccess: false);
    }
  }

  Future<void> _clearCart() async {
    try {
      final response = await ApiService.clearCart();
      if (response['success'] == true) {
        await _loadCartContents();
        widget.onCartChanged?.call();
        widget.showBottomMessage?.call(AppLocalizations.of(context)!.cartCleared, isSuccess: true);
      } else {
        widget.showBottomMessage?.call(
          AppLocalizations.of(context)!.failedToClearCart,
          isSuccess: false,
        );
      }
    } catch (e) {
      debugPrint('Error clearing cart: $e');
      widget.showBottomMessage?.call(AppLocalizations.of(context)!.errorClearingCart, isSuccess: false);
    }
  }

  double _calculateSubtotal() {
    double subtotal = 0.0;
    for (var item in _cartItems) {
      final productId = item['productId'];
      final variantIdx = item['variantIdx'] ?? 0;
      final product = _productDetails[productId?.toString() ?? ''];
      if (product != null) {
        // Get the correct variant price based on variantIdx
        dynamic priceValue;
        
        // First try to get price from the specific variant
        if (product['variants'] != null && product['variants'] is List) {
          final variants = product['variants'] as List;
          if (variantIdx < variants.length && variants[variantIdx]['price'] != null) {
            priceValue = variants[variantIdx]['price'];
          } else if (variants.isNotEmpty) {
            // Fallback to first variant if variantIdx is out of bounds
            priceValue = variants[0]['price'];
          }
        }
        
        // Fallback to product price if no variant price found
        priceValue ??= product['price'];

        double price = 0.0;
        if (priceValue is String) {
          price = double.tryParse(priceValue) ?? 0.0;
        } else if (priceValue is num) {
          price = priceValue.toDouble();
        }

        final quantity = item['quantity'] ?? 1;
        final actualQuantity = _parseNumericValue(quantity, fallback: 1.0);
        subtotal += price * actualQuantity;
      }
    }
    return subtotal;
  }

  double _getTotalItemCount() {
    double totalCount = 0.0;
    for (var item in _cartItems) {
      final quantity = item['quantity'] ?? 1;
      final actualQuantity = _parseNumericValue(quantity, fallback: 1.0);
      totalCount += actualQuantity;
    }
    return totalCount;
  }

  double _calculateTotal() {
    return _calculateSubtotal();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        // Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  Icon(
                    CupertinoIcons.shopping_cart,
                    color: isDark ? Colors.white : Colors.black,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context)!.shoppingCart,
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
            if (_cartItems.isNotEmpty)
              TradeRepublicButton(
                label: AppLocalizations.of(context)!.clearAll,
                isDestructive: true,
                onPressed: _clearCart,
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
          ],
        ),

        const SizedBox(height: 16),

          // Cart Content
          Expanded(
            child: _isLoading
                ? const Center(child: CultiooLoadingIndicator())
                : _cartItems.isEmpty
                ? _buildEmptyCart(isDark)
                : _buildCartList(isDark),
          ),

          // Checkout Section
          if (_cartItems.isNotEmpty) _buildCheckoutSection(isDark),
        ],
    );
  }

  Widget _buildEmptyCart(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            CupertinoIcons.shopping_cart,
            size: 80,
            color: isDark ? Colors.white38 : Colors.black38,
          ),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.of(context)!.yourCartIsEmpty,
            style: TextStyle(
              fontSize: 18,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartList(bool isDark) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: _cartItems.length,
      itemBuilder: (context, index) {
        final item = _cartItems[index];
        final productId = item['productId'];
        debugPrint(
          '🛒 Building cart item $index: productId=$productId (type: ${productId.runtimeType}), hasProduct=${_productDetails.containsKey(productId?.toString() ?? "")}',
        );
        debugPrint(
          '🛒 Available keys in productDetails: ${_productDetails.keys.toList()}',
        );

        final product = _productDetails[productId?.toString() ?? ''];
        if (product != null) {
          return _buildCartItem(item, product, isDark);
        } else {
          return _buildCartItemFallback(item, isDark);
        }
      },
    );
  }

  Widget _buildCartItem(
    Map<String, dynamic> item,
    Map<String, dynamic> product,
    bool isDark,
  ) {
    final quantity = item['quantity'] ?? 1;
    final variantIdx =
        item['variantIdx'] ?? 0; // Get the selected variant index

    // Get the correct variant based on variantIdx
    Map<String, dynamic>? selectedVariant;
    String variantTitle = '';

    if (product['variants'] != null && product['variants'] is List) {
      final variants = product['variants'] as List;
      if (variantIdx < variants.length) {
        selectedVariant = variants[variantIdx];
        variantTitle = selectedVariant?['title']?.toString() ?? '';
      }
    }

    // Try to get price from selected variant first, then fallback
    dynamic priceValue;
    if (selectedVariant != null && selectedVariant['price'] != null) {
      priceValue = selectedVariant['price'];
    } else if (product['variants'] != null && product['variants'] is List) {
      final variants = product['variants'] as List;
      if (variants.isNotEmpty) {
        priceValue = variants[0]['price'];
      }
    } else {
      priceValue = product['price'];
    }

    double price = 0.0;
    if (priceValue is String) {
      price = double.tryParse(priceValue) ?? 0.0;
    } else if (priceValue is num) {
      price = priceValue.toDouble();
    }

    // Use variant title if available, otherwise use product name
    String name = product['name'] ?? product['title'] ?? AppLocalizations.of(context)!.unknownProduct;
    if (variantTitle.isNotEmpty) {
      name = '$name - $variantTitle';
    }

    // Try to get image from selected variant first, then product
    String imageUrl = '';

    // First try variant-specific image
    if (selectedVariant != null) {
      if (selectedVariant['image_url'] != null &&
          selectedVariant['image_url'].toString().isNotEmpty) {
        imageUrl = selectedVariant['image_url'];
      } else if (selectedVariant['primary_image'] != null &&
          selectedVariant['primary_image'].toString().isNotEmpty) {
        imageUrl = selectedVariant['primary_image'];
      }
    }

    // Fallback to product-level image
    if (imageUrl.isEmpty) {
      if (product['image_url'] != null &&
          product['image_url'].toString().isNotEmpty) {
        imageUrl = product['image_url'];
      } else if (product['primary_image'] != null &&
          product['primary_image'].toString().isNotEmpty) {
        imageUrl = product['primary_image'];
      } else if (product['images'] != null && product['images'] is List) {
        final images = product['images'] as List;
        if (images.isNotEmpty) {
          imageUrl = images[0]['url'] ?? images[0]['image_url'] ?? '';
        }
      }
    }

    final actualQuantity = _parseNumericValue(quantity, fallback: 1.0);
    final totalItemPrice = price * actualQuantity;

    debugPrint(
      '🛒 Cart item details: name=$name, price=$price, quantity=$actualQuantity units, variantIdx=$variantIdx, imageUrl=${imageUrl.isNotEmpty ? "found" : "missing"}',
    );

    debugPrint(
      '🛒 Cart item details: name=$name, price=$price, quantity=$actualQuantity units, imageUrl=${imageUrl.isNotEmpty ? "found" : "missing"}',
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.black : Colors.white,
        borderRadius: BorderRadius.circular(25),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.1)
              : Colors.black.withOpacity(0.05),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          // Product Image
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(25),
              color: isDark ? Colors.grey[700] : Colors.grey[200],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(25),
              child: imageUrl.isNotEmpty
                  ? (imageUrl.startsWith('data:image')
                        ? Image.memory(
                            base64Decode(imageUrl.split(',')[1]),
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Icon(
                                CupertinoIcons.photo,
                                color: isDark ? Colors.white38 : Colors.black38,
                              );
                            },
                          )
                        : Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Icon(
                                CupertinoIcons.photo,
                                color: isDark ? Colors.white38 : Colors.black38,
                              );
                            },
                          ))
                  : Icon(
                      CupertinoIcons.bag,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
            ),
          ),

          const SizedBox(width: 16),

          // Product Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '${_formatCurrency(price)} / ${item['unit'] ?? 'kg'}',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 8),
                // Total Price
                Text(
                  AppLocalizations.of(context)!.totalWithAmount(_formatCurrency(totalItemPrice)),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                // Quantity Controls
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        // Decrease quantity
                        _buildQuantityButton(
                          icon: CupertinoIcons.minus,
                          onPressed: () {
                            final currentQty = _parseNumericValue(
                              quantity,
                              fallback: 1.0,
                            );
                            if (currentQty > 1.0) {
                              _updateQuantity(
                                item['productId'],
                                ((currentQty - 1.0) * 100).round(), // Convert to int
                                variantIdx: item['variantIdx'] ?? 0,
                              );
                            }
                          },
                          isEnabled: _parseNumericValue(
                                quantity,
                                fallback: 1.0,
                              ) >
                              1.0,
                          isDark: isDark,
                        ),

                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          constraints: const BoxConstraints(maxWidth: 100),
                          child: Text(
                            NumberFormat('#,##0.00', 'en_US').format(
                              _parseNumericValue(quantity, fallback: 1.0),
                            ),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),

                        // Increase quantity
                        _buildQuantityButton(
                          icon: CupertinoIcons.plus,
                          onPressed: () {
                            final currentQty = _parseNumericValue(
                              quantity,
                              fallback: 1.0,
                            );
                            _updateQuantity(
                              item['productId'],
                              ((currentQty + 1.0) * 100).round(), // Convert to int
                              variantIdx: item['variantIdx'] ?? 0,
                            );
                          },
                          isEnabled: true,
                          isDark: isDark,
                        ),
                      ],
                    ),

                    // Remove item
                    _buildQuantityButton(
                      icon: CupertinoIcons.trash,
                      onPressed: () => _removeItem(
                        item['productId'],
                        variantIdx: item['variantIdx'] ?? 0,
                      ),
                      isEnabled: true,
                      isDark: isDark,
                      isDeleteButton: true,
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

  Widget _buildQuantityButton({
    required IconData icon,
    required VoidCallback? onPressed,
    required bool isEnabled,
    required bool isDark,
    bool isDeleteButton = false,
  }) {
    return TradeRepublicButton(
      icon: Icon(
        icon,
        size: 15,
        color: isEnabled
            ? (isDeleteButton
                  ? Colors.red.withOpacity(0.8)
                  : (isDark ? Colors.white70 : Colors.black54))
            : (isDark ? Colors.white24 : Colors.black26),
      ),
      isSecondary: true,
      onPressed: isEnabled ? onPressed : null,
      width: 36,
      height: 36,
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(12),
    );
  }

  Widget _buildCartItemFallback(Map<String, dynamic> item, bool isDark) {
    final quantity = item['quantity'] ?? 1;
    final actualQuantity = _parseNumericValue(quantity, fallback: 1.0);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.black : Colors.white,
        borderRadius: BorderRadius.circular(25),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.1)
              : Colors.black.withOpacity(0.05),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(25),
              color: isDark ? Colors.grey[700] : Colors.grey[200],
            ),
            child: Icon(
              CupertinoIcons.bag,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),

          const SizedBox(width: 16),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['name']?.toString() ?? AppLocalizations.of(context)!.loadingProductDetails,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  AppLocalizations.of(context)!.loadingProductDetails,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),

          Text(
            AppLocalizations.of(context)!.qtyWithCount(
              NumberFormat('#,##0.00', 'en_US').format(actualQuantity),
            ),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckoutSection(bool isDark) {
    final subtotal = _calculateSubtotal();
    final total = _calculateTotal();
    final totalItemCount = _getTotalItemCount();

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? Colors.black : Colors.white,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(25)),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.1)
              : Colors.black.withOpacity(0.05),
          width: 0.5,
        ),
      ),
      child: Column(
        children: [
          // Subtotal
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Subtotal (${formatNumberUS(totalItemCount)} units)',
                style: TextStyle(
                  fontSize: 16,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
              Text(
                _formatCurrency(subtotal),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Total
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                AppLocalizations.of(context)!.total,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              Text(
                _formatCurrency(total),
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.green[300] : Colors.green[700],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          if (!_hasPaymentMethod)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    CupertinoIcons.creditcard,
                    size: 13,
                    color: isDark
                        ? Colors.white.withOpacity(0.4)
                        : Colors.black.withOpacity(0.35),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    AppLocalizations.of(context)!.noPaymentMethodDescription,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? Colors.white.withOpacity(0.4)
                          : Colors.black.withOpacity(0.35),
                    ),
                  ),
                ],
              ),
            ),
          TradeRepublicButton(
            width: double.infinity,
            height: 56,
            label: AppLocalizations.of(context)!.proceedToCheckout,
            onPressed: _isCheckoutPressed
                ? null
                : () async {
                    // Prevent multiple rapid taps
                    if (_isCheckoutPressed) return;

                    if (!_hasPaymentMethod) {
                      widget.showBottomMessage?.call(
                        'Please add a payment method in your account settings first.',
                        isSuccess: false,
                      );
                      return;
                    }

                    setState(() {
                      _isCheckoutPressed = true;
                    });

                    // Capture necessary state and callback before popping,
                    // because the widget will be unmounted after Navigator.pop on Desktop
                    final onProceedToCheckout = widget.onProceedToCheckout;
                    final cartItems = _cartItems;
                    final currentTotal = total;

                    // Close the cart modal first
                    Navigator.pop(context);

                    // Then show checkout modal with a small delay to prevent double-triggering
                    await Future.delayed(
                      const Duration(milliseconds: 150),
                    );

                    if (onProceedToCheckout != null) {
                      onProceedToCheckout(
                        isDark,
                        cartItems,
                        currentTotal,
                      );
                    }

                    // Reset flag after some time (if we are still mounted)
                    Future.delayed(
                      const Duration(milliseconds: 500),
                      () {
                        if (mounted) {
                          setState(() {
                            _isCheckoutPressed = false;
                          });
                        }
                      },
                    );
                  },
          ),
        ],
      ),
    );
  }
}
