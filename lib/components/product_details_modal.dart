import 'dart:convert';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:cupertino_native_better/cupertino_native_better.dart';
import '../services/api_service.dart';
import '../services/trade_republic_widgets.dart';
import '../services/app_localizations.dart';
import '../utils/number_formatters.dart';
import '../utils/wagon_catalog.dart';
import 'seller_profile_modal.dart';

import '../main.dart';
import '../services/cultioo_spinner.dart';

class ProductDetailsModal extends StatefulWidget {
  final Map<String, dynamic> product;
  final Function(int)? onFavoriteToggle;
  final Function(String, {bool isSuccess})? showBottomMessage;
  final VoidCallback? onCartChanged;
  final List<int>? favoriteProductIds;
  final bool? isMainAppLoggedIn;
  final String? numberFormat;
  final String? currency;
  final double? exchangeRate;
  final Function(String username, String name)? onStartChat;

  const ProductDetailsModal({
    super.key,
    required this.product,
    this.onFavoriteToggle,
    this.showBottomMessage,
    this.onCartChanged,
    this.favoriteProductIds,
    this.isMainAppLoggedIn,
    this.numberFormat,
    this.currency,
    this.exchangeRate,
    this.onStartChat,
  });

  @override
  State<ProductDetailsModal> createState() => _ProductDetailsModalState();
}

class _ProductDetailsModalState extends State<ProductDetailsModal> {
  bool _isFavorite = false;
  Map<String, dynamic>? _detailedProduct;
  bool _isLoading = true;
  bool _isUserLoggedIn = false;
  int _selectedVariantIndex = 0;
  int _currentImageIndex = 0;
  String _quantityInput = '';
  String _selectedUnit = 'kg'; // Current selected unit
  String? _sellerProfileImage;
  String? _sellerDisplayName;

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
    _initializeFavoriteState();
    _loadProductDetails();
    final sellerUser = widget.product['username']?.toString();
    if (sellerUser != null && sellerUser.isNotEmpty) {
      _loadSellerProfileImage(sellerUser);
    }
  }

  Future<void> _loadSellerProfileImage(String username) async {
    try {
      final result = await ApiService.getUserByUsername(username);
      if (result != null && result['success'] == true) {
        final user = result['user'];
        final pic = user?['profilePic']?.toString();
        final biz = user?['businessName']?.toString();
        if (mounted) {
          setState(() {
            if (pic != null && pic.isNotEmpty && pic != 'null') {
              _sellerProfileImage = pic;
            }
            if (biz != null && biz.isNotEmpty && biz != 'null') {
              _sellerDisplayName = biz;
            }
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _checkLoginStatus() async {
    if (widget.isMainAppLoggedIn != null && !widget.isMainAppLoggedIn!) {
      if (mounted) setState(() => _isUserLoggedIn = false);
      return;
    }
    final isLoggedIn = await ApiService.isLoggedInAsync;
    if (mounted) setState(() => _isUserLoggedIn = isLoggedIn);
  }

  void _openFullscreenImageViewer(
    List<dynamic> images, {
    int initialIndex = 0,
  }) {
    if (images.isEmpty) return;

    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        pageBuilder: (_, _, _) => _FullscreenProductImageViewer(
          images: images,
          initialIndex: initialIndex,
        ),
        transitionsBuilder: (_, animation, _, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOut,
            ),
            child: child,
          );
        },
      ),
    );
  }

  void _initializeFavoriteState() {
    if (widget.favoriteProductIds != null && currentProduct['id'] != null) {
      _isFavorite = widget.favoriteProductIds!.contains(currentProduct['id']);
    }
  }

  Future<void> _loadProductDetails() async {
    try {
      final productId = widget.product['id'];
      if (productId != null) {
        final data = await ApiService.getProduct(productId);
        if (data['success'] && data['product'] != null) {
          if (mounted) {
            setState(() {
              _detailedProduct = data['product'];
              _isLoading = false;
              _initializeFavoriteState();
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Map<String, dynamic> get currentProduct => _detailedProduct ?? widget.product;

  Map<String, dynamic>? get currentVariant {
    final variants = currentProduct['variants'];
    if (variants is List &&
        variants.isNotEmpty &&
        _selectedVariantIndex < variants.length) {
      return variants[_selectedVariantIndex];
    }
    return null;
  }

  double _parseFlexibleDecimal(String rawValue) {
    final value = rawValue.trim();
    if (value.isEmpty) return 0.0;

    final lastComma = value.lastIndexOf(',');
    final lastDot = value.lastIndexOf('.');

    if (lastComma >= 0 && lastDot >= 0) {
      if (lastComma > lastDot) {
        return double.tryParse(
              value.replaceAll('.', '').replaceAll(',', '.'),
            ) ??
            0.0;
      }

      return double.tryParse(value.replaceAll(',', '')) ?? 0.0;
    }

    if (lastComma >= 0) {
      return double.tryParse(value.replaceAll(',', '.')) ?? 0.0;
    }

    return double.tryParse(value) ?? 0.0;
  }

  String _formatPrice(double amount) {
    setNumberFormatStyleIndex(widget.numberFormat == 'de' ? 1 : 0);
    return formatCurrencyUsd(amount);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              child: _isLoading
                  ? Center(
                      child: CultiooLoadingIndicator(),
                    )
                  : _buildContent(isDark),
            ),
          ],
        ),
        // Action Bar positioned at bottom
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _buildActionBar(isDark),
        ),
      ],
    );
  }

  Widget _buildContent(bool isDark) {
    final textColor = isDark ? Colors.white : Colors.black;
    final subtextColor = isDark
        ? const Color(0xFFBDBDBD)
        : const Color(0xFF757575);
    final dividerColor = isDark
        ? const Color(0xFF424242)
        : const Color(0xFFEEEEEE);

    final variant = currentVariant;
    final price = variant?['price']?.toString() ?? '0';
    final priceDouble = double.tryParse(price) ?? 0;
    final unit = variant?['unit']?.toString() ?? '';

    print(
      '🔥🔥🔥 _buildContent() called - currentProduct id: ${currentProduct['id']}',
    );
    print('🔥🔥🔥 variant keys: ${variant?.keys.toList()}');
    print('🔥🔥🔥 Will call _buildShippingInfo in ScrollView');

    // Location from products table
    final city = currentProduct['locationCity']?.toString() ?? '';
    final zip = currentProduct['locationZip']?.toString() ?? '';
    final street = currentProduct['locationStreet']?.toString() ?? '';
    final country = currentProduct['locationCountry']?.toString() ?? '';
    String location = city;
    if (zip.isNotEmpty) location = '$zip $city';
    if (street.isNotEmpty) location = '$street, $location';
    if (country.isNotEmpty && country != city) location = '$location, $country';

    // Seller info
    final sellerUsername =
      currentProduct['username']?.toString() ??
      AppLocalizations.of(context)!.seller;

    // Get all product images
    final productImages = currentProduct['images'] as List<dynamic>? ?? [];

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image Gallery with favorite overlay
          Stack(
            children: [
              if (productImages.isNotEmpty)
                _buildImageGallery(productImages, isDark)
              else if (currentProduct['image_url'] != null)
                SizedBox(
                  height: 320,
                  child: GestureDetector(
                    onTap: () => _openFullscreenImageViewer([
                      {'image_url': currentProduct['image_url']},
                    ]),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Container(
                            width: double.infinity,
                            color: isDark
                                ? const Color(0xFF212121)
                                : const Color(0xFFF5F5F5),
                            child: ClipRect(
                              child: SizedBox.expand(
                                child: FittedBox(
                                  fit: BoxFit.cover,
                                  alignment: Alignment.center,
                                  clipBehavior: Clip.hardEdge,
                                  child: Image.network(
                                    currentProduct['image_url'],
                                    errorBuilder: (_, _, _) => Container(
                                      color: isDark
                                          ? const Color(0xFF212121)
                                          : const Color(0xFFEEEEEE),
                                      child: Icon(
                                        CupertinoIcons.photo,
                                        size: 80,
                                        color: isDark
                                            ? const Color(0xFF616161)
                                            : const Color(0xFF9E9E9E),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.black.withOpacity(0.25),
                                    Colors.transparent,
                                    Colors.black.withOpacity(0.3),
                                  ],
                                  stops: const [0.0, 0.55, 1.0],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (_isUserLoggedIn &&
                  (productImages.isNotEmpty ||
                      currentProduct['image_url'] != null))
                Positioned(
                  top: 16,
                  right: 16,
                  child: GestureDetector(
                    onTap: _toggleFavorite,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.35),
                        borderRadius: BorderRadius.circular(25),
                      ),
                      child: Icon(
                        _isFavorite
                            ? CupertinoIcons.heart_fill
                            : CupertinoIcons.heart,
                        size: 20,
                        color: _isFavorite
                            ? CupertinoColors.systemRed
                            : Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 32),

          // Variant Selector if multiple variants
          if (_detailedProduct != null &&
              ((_detailedProduct!['variants'] as List?)?.length ?? 0) > 1)
            _buildVariantSelector(isDark),

          const SizedBox(height: 24),

          // Title - TRADE REPUBLIC STYLE: Huge & Bold
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
                variant?['title'] ??
                  currentProduct['title'] ??
                  AppLocalizations.of(context)!.productLabel,
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: textColor,
                height: 1.2,
                letterSpacing: -0.5,
              ),
            ),
          ),

          // Subtitle if available
          if (variant?['subtitle'] != null &&
              variant!['subtitle'].toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: Text(
                variant['subtitle'].toString(),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: subtextColor,
                ),
              ),
            ),

          const SizedBox(height: 24),

          // Price - MASSIVE
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _formatPrice(priceDouble),
                      style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.w900,
                        color: textColor,
                        height: 1,
                        letterSpacing: -1,
                      ),
                    ),
                    if (unit.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 8, bottom: 4),
                        child: Text(
                          '/ $unit',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: subtextColor,
                            height: 1,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Divider
          Container(
            height: 1,
            color: dividerColor,
            margin: const EdgeInsets.symmetric(horizontal: 24),
          ),

          const SizedBox(height: 32),

          // Pickup Location
          if (location.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1C1C1E)
                      : const Color(0xFFF2F2F7),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withOpacity(0.08)
                            : Colors.black.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        CupertinoIcons.location_fill,
                        size: 18,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLocalizations.of(context)!.pickupLocation,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF9E9E9E),
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            location,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: textColor,
                              height: 1.3,
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

          // Stock Status
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: _isOutOfStock()
                    ? (isDark
                        ? const Color(0xFF2D1515)
                        : const Color(0xFFFFEBEB))
                    : (isDark
                        ? const Color(0xFF152D15)
                        : const Color(0xFFEBF5EB)),
                borderRadius: BorderRadius.circular(25),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isOutOfStock()
                        ? CupertinoIcons.xmark_circle_fill
                        : CupertinoIcons.checkmark_circle_fill,
                    size: 16,
                    color: _isOutOfStock()
                        ? (isDark
                            ? const Color(0xFFEF9A9A)
                            : const Color(0xFFC62828))
                        : (isDark
                            ? const Color(0xFFA5D6A7)
                            : const Color(0xFF2E7D32)),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _getStockText(),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _isOutOfStock()
                          ? (isDark
                              ? const Color(0xFFEF9A9A)
                              : const Color(0xFFC62828))
                          : (isDark
                              ? const Color(0xFFA5D6A7)
                              : const Color(0xFF2E7D32)),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 40),

          // Description
          if (variant?['longDesc'] != null &&
              variant!['longDesc'].toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context)!.description.toUpperCase(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF9E9E9E),
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    variant['longDesc'].toString(),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                      color: isDark
                          ? const Color(0xFFE0E0E0)
                          : const Color(0xFF424242),
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 40),

          // Seller Info - Modern Container
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: GestureDetector(
              onTap: () {
                // Open seller profile modal
                TradeRepublicBottomSheet.show(
                  context: context,
                  showDragHandle: true,
                  child: SellerProfileModal(
                    sellerId: sellerUsername,
                    sellerName: sellerUsername,
                    onStartChat: widget.onStartChat,
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1C1C1E)
                      : const Color(0xFFF2F2F7),
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Row(
                  children: [
                    // Profile avatar
                    Builder(builder: (context) {
                      ImageProvider? imgProvider;
                      final pic = _sellerProfileImage;
                      if (pic != null && pic.isNotEmpty) {
                        if (pic.startsWith('data:')) {
                          try {
                            imgProvider = MemoryImage(base64Decode(pic.split(',').last));
                          } catch (_) {}
                        } else if (pic.startsWith('http')) {
                          imgProvider = NetworkImage(pic);
                        }
                      }
                      return Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withOpacity(0.1)
                              : Colors.black.withOpacity(0.05),
                          shape: BoxShape.circle,
                        ),
                        child: ClipOval(
                          child: imgProvider != null
                              ? Image(
                                  image: imgProvider,
                                  width: 48,
                                  height: 48,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => Icon(
                                    CupertinoIcons.person_fill,
                                    color: isDark ? Colors.white60 : Colors.black45,
                                    size: 22,
                                  ),
                                )
                              : Icon(
                                  CupertinoIcons.person_fill,
                                  color: isDark ? Colors.white60 : Colors.black45,
                                  size: 22,
                                ),
                        ),
                      );
                    }),
                    const SizedBox(width: 16),
                    // Seller name
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLocalizations.of(context)!.seller.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF9E9E9E),
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          if (_sellerDisplayName != null)
                            Text(
                              _sellerDisplayName!,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: textColor,
                              ),
                            ),
                          Text(
                            '@$sellerUsername',
                            style: TextStyle(
                              fontSize: _sellerDisplayName != null ? 13 : 18,
                              fontWeight: _sellerDisplayName != null
                                  ? FontWeight.w500
                                  : FontWeight.w700,
                              color: _sellerDisplayName != null
                                  ? subtextColor
                                  : textColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Arrow icon
                    Icon(
                      CupertinoIcons.chevron_right,
                      color: isDark
                          ? Colors.white.withOpacity(0.3)
                          : Colors.black.withOpacity(0.3),
                      size: 24,
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 40),

          // Product Details
          _buildProductDetailsTable(),

          const SizedBox(height: 40),

          // Nutrition Facts
          _buildNutritionTable(),

          const SizedBox(height: 40),

          // Ingredients & Origin
          _buildIngredientsSection(),

          const SizedBox(height: 40),

          // Shipping & Trade Info
          _buildShippingInfo(),

          const SizedBox(height: 140), // Space for fixed action bar
        ],
      ),
    );
  }

  Widget _buildImageGallery(List<dynamic> images, bool isDark) {
    if (images.isEmpty) return const SizedBox.shrink();

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

    // Filter images for current variant
    List<dynamic> variantImages = images;
    final variants = _detailedProduct?['variants'] as List?;

    if (variants != null && _selectedVariantIndex < variants.length) {
      final currentVariant = variants[_selectedVariantIndex];
      final variantIdx = currentVariant['variantIdx'];

      // Filter images that match current variant index
      final filteredImages = images
          .where(
            (img) =>
                img['variant_index'] == variantIdx ||
                img['variantIndex'] == variantIdx ||
                img['variant_idx'] == variantIdx,
          )
          .toList();

      // Use filtered images if available, otherwise show all images
      if (filteredImages.isNotEmpty) {
        variantImages = filteredImages;
      }
    }

    print(
      '🖼️ Image Gallery: Showing ${variantImages.length} of ${images.length} total images',
    );

    if (_currentImageIndex >= variantImages.length) {
      _currentImageIndex = 0;
    }

    return SizedBox(
      height: 360,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              itemCount: variantImages.length,
              physics: variantImages.length > 1
                  ? const BouncingScrollPhysics()
                  : const NeverScrollableScrollPhysics(),
              onPageChanged: (index) {
                if (!mounted) return;
                setState(() => _currentImageIndex = index);
              },
              itemBuilder: (context, index) {
                final imageUrl =
                    variantImages[index]['image_url'] ??
                    variantImages[index]['imageUrl'] ??
                    variantImages[index]['url'] ??
                    '';

                if (imageUrl.isEmpty) {
                  return Container(
                    width: double.infinity,
                    color: isDark
                        ? const Color(0xFF1A1A1A)
                        : const Color(0xFFFAFAFA),
                    child: Icon(
                      CupertinoIcons.photo,
                      size: 80,
                      color: isDark
                          ? const Color(0xFF424242)
                          : const Color(0xFFBDBDBD),
                    ),
                  );
                }

                if (imageUrl.startsWith('data:image')) {
                  try {
                    final base64String = imageUrl.split(',').last;
                    final bytes = base64Decode(base64String);

                    return GestureDetector(
                      onTap: () => _openFullscreenImageViewer(
                        variantImages,
                        initialIndex: index,
                      ),
                      child: Container(
                        width: double.infinity,
                        color: isDark
                            ? const Color(0xFF1A1A1A)
                            : const Color(0xFFFAFAFA),
                        child: buildCoverMedia(
                          Image.memory(
                            bytes,
                            errorBuilder: (context, error, stackTrace) {
                              print('🖼️ Base64 Image decode error: $error');
                              return Container(
                                color: isDark
                                    ? const Color(0xFF1A1A1A)
                                    : const Color(0xFFFAFAFA),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      CupertinoIcons.exclamationmark_triangle,
                                      size: 80,
                                      color: isDark
                                          ? const Color(0xFF424242)
                                          : const Color(0xFFBDBDBD),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      AppLocalizations.of(context)!.imageDecodeError,
                                      style: TextStyle(
                                        color: isDark
                                            ? const Color(0xFF616161)
                                            : const Color(0xFFC0C0C0),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  } catch (e) {
                    print('🖼️ Error processing base64 image: $e');
                    return Container(
                      color: isDark
                          ? const Color(0xFF1A1A1A)
                          : const Color(0xFFFAFAFA),
                      child: Center(
                        child: Icon(
                          CupertinoIcons.exclamationmark_triangle,
                          size: 80,
                          color: isDark
                              ? const Color(0xFF424242)
                              : const Color(0xFFBDBDBD),
                        ),
                      ),
                    );
                  }
                }

                return GestureDetector(
                  onTap: () => _openFullscreenImageViewer(
                    variantImages,
                    initialIndex: index,
                  ),
                  child: Container(
                    width: double.infinity,
                    color: isDark
                        ? const Color(0xFF1A1A1A)
                        : const Color(0xFFFAFAFA),
                    child: Image.network(
                      imageUrl,
                      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                        if (wasSynchronouslyLoaded || frame != null) {
                          return buildCoverMedia(child);
                        }
                        return const Center(child: CultiooLoadingIndicator());
                      },
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return const Center(child: CultiooLoadingIndicator());
                      },
                      errorBuilder: (context, error, stackTrace) {
                        print('🖼️ Image load error: $error');
                        return Container(
                          color: isDark
                              ? const Color(0xFF1A1A1A)
                              : const Color(0xFFFAFAFA),
                          child: Center(
                            child: Icon(
                              CupertinoIcons.exclamationmark_triangle,
                              size: 80,
                              color: isDark
                                  ? const Color(0xFF424242)
                                  : const Color(0xFFBDBDBD),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
            // Premium gradient overlay for depth
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.18),
                      Colors.transparent,
                      Colors.black.withOpacity(0.22),
                    ],
                    stops: const [0.0, 0.6, 1.0],
                  ),
                ),
              ),
            ),
            // Modern dot indicators at bottom
            if (variantImages.length > 1)
              Positioned(
                bottom: 12,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.42),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.12),
                        width: 0.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(
                        variantImages.length,
                        (index) => Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: index < variantImages.length - 1 ? 4 : 0,
                          ),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: _currentImageIndex == index ? 24 : 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: _currentImageIndex == index
                                  ? Colors.white
                                  : Colors.white.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            // Image counter (top right for fallback single image)
            if (variantImages.length > 1 && variantImages.length <= 1)
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.42),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.12),
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    '${_currentImageIndex + 1}/${variantImages.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),
            if (variantImages.length > 1)
              Positioned(
                left: 0,
                right: 0,
                bottom: 16,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(variantImages.length, (dotIndex) {
                    final isActive = dotIndex == _currentImageIndex;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: isActive ? 22 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: isActive
                            ? Colors.white
                            : Colors.white.withOpacity(0.45),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    );
                  }),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildVariantSelector(bool isDark) {
    final variants = _detailedProduct?['variants'] as List?;
    if (variants == null || variants.length <= 1) {
      return const SizedBox.shrink();
    }

    final textColor = isDark ? Colors.white : Colors.black;
    final bgColor = isDark ? Colors.black : const Color(0xFFF2F2F7);
    final selectedBg =
        TradeRepublicTheme.selectionContainerBackground(context);
    final selectedFg =
        TradeRepublicTheme.selectionContainerForeground(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context)!.variant.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6E6E73),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 60,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: variants.length,
              itemBuilder: (context, index) {
                final isSelected = _selectedVariantIndex == index;
                final variantTitle =
                    variants[index]['title']?.toString() ??
                    AppLocalizations.of(context)!.variantNumber(index + 1);
                final variantPrice =
                    variants[index]['price']?.toString() ?? '0';
                final priceDouble = double.tryParse(variantPrice) ?? 0;
                final variantUnit = variants[index]['unit']?.toString() ?? '';

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedVariantIndex = index;
                      _currentImageIndex = 0;
                    });
                    HapticFeedback.lightImpact();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected ? selectedBg : bgColor,
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          variantTitle,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isSelected ? selectedFg : textColor,
                            letterSpacing: -0.2,
                          ),
                        ),
                        if (variantUnit.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          Text(
                            variantUnit,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                              color: isSelected
                                  ? selectedFg.withValues(alpha: 0.72)
                                  : (isDark
                                      ? const Color(0xFF8E8E93)
                                      : const Color(0xFF6E6E73)),
                              letterSpacing: -0.2,
                            ),
                          ),
                        ],
                        const SizedBox(width: 8),
                        Text(
                          _formatPrice(priceDouble),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            color: isSelected
                                ? selectedFg.withValues(alpha: 0.72)
                                : (isDark
                                    ? const Color(0xFF8E8E93)
                                    : const Color(0xFF6E6E73)),
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNutritionTable() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final variant = currentVariant;
    if (variant == null) return const SizedBox.shrink();

    List<Map<String, String>> rows = [];

    final l10n = AppLocalizations.of(context)!;
    final kcal = variant['nutr_energy_kcal']?.toString();
    if (kcal != null && kcal.isNotEmpty && kcal != 'null') {
      rows.add({'label': l10n.energy, 'value': '$kcal kcal'});
    }

    final kj = variant['nutr_energy_kj']?.toString();
    if (kj != null && kj.isNotEmpty && kj != 'null') {
      rows.add({'label': l10n.energyKj, 'value': '$kj kJ'});
    }

    final fat = variant['nutr_fat']?.toString();
    if (fat != null && fat.isNotEmpty && fat != 'null') {
      rows.add({'label': l10n.fat, 'value': '$fat g'});
    }

    final fsat = variant['nutr_fsat']?.toString();
    if (fsat != null && fsat.isNotEmpty && fsat != 'null') {
      rows.add({'label': l10n.saturatedFat, 'value': '$fsat g'});
    }

    final carb = variant['nutr_carb']?.toString();
    if (carb != null && carb.isNotEmpty && carb != 'null') {
      rows.add({'label': l10n.carbs, 'value': '$carb g'});
    }

    final sugar = variant['nutr_sugar']?.toString();
    if (sugar != null && sugar.isNotEmpty && sugar != 'null') {
      rows.add({'label': l10n.sugar, 'value': '$sugar g'});
    }

    final protein = variant['nutr_protein']?.toString();
    if (protein != null && protein.isNotEmpty && protein != 'null') {
      rows.add({'label': l10n.protein, 'value': '$protein g'});
    }

    final salt = variant['nutr_salt']?.toString();
    if (salt != null && salt.isNotEmpty && salt != 'null') {
      rows.add({'label': l10n.salt, 'value': '$salt g'});
    }

    if (rows.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context)!.nutritionFacts,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF9E9E9E),
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            AppLocalizations.of(context)!.per100g,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF9E9E9E),
            ),
          ),
          const SizedBox(height: 16),
          ...rows.map((row) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _buildInfoValueCard(
                label: row['label']!,
                value: row['value']!,
                isDark: isDark,
                icon: CupertinoIcons.heart_fill,
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildProductDetailsTable() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final variant = currentVariant;
    if (variant == null) return const SizedBox.shrink();

    final details = <String, String>{};

    // Variant details
    if (variant['mainCategory'] != null &&
        variant['mainCategory'].toString().isNotEmpty) {
      details['Category'] = variant['mainCategory'].toString();
    }

    if (variant['unit'] != null && variant['unit'].toString().isNotEmpty) {
      details['Unit'] = variant['unit'].toString();
    }

    if (variant['minOrder'] != null && variant['minOrder'].toString() != '0') {
      details['Min. Order'] = variant['minOrder'].toString();
    }

    if (variant['stock'] != null && variant['alwaysAvailable'] != 1) {
      details['Stock'] = variant['stock'].toString();
    }

    // Product metadata
    if (currentProduct['views'] != null) {
      details['Views'] = currentProduct['views'].toString();
    }

    if (currentProduct['created_at'] != null) {
      details['Listed'] = _formatDate(currentProduct['created_at'].toString());
    }

    if (details.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context)!.productDetails,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF9E9E9E),
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          ...details.entries.map((e) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _buildInfoValueCard(
                label: e.key,
                value: e.value,
                isDark: isDark,
                icon: CupertinoIcons.info_circle_fill,
              ),
            );
          }),
        ],
      ),
    );
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final diff = now.difference(date);

      if (diff.inDays == 0) return AppLocalizations.of(context)!.today;
      if (diff.inDays == 1) return AppLocalizations.of(context)!.yesterday;
      if (diff.inDays < 7) return '${diff.inDays} days ago';
      if (diff.inDays < 30) return '${(diff.inDays / 7).floor()} weeks ago';
      if (diff.inDays < 365) return '${(diff.inDays / 30).floor()} months ago';

      // For older dates, use the user's preferred format
      final currentFormat = MyApp.getCurrentDateFormat() ?? 'dd.MM.yyyy';
      return MyApp.formatDateGlobally(date, currentFormat);
    } catch (e) {
      return dateStr;
    }
  }

  Widget _buildIngredientsSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;
    final subtextColor = isDark
        ? const Color(0xFFE0E0E0)
        : const Color(0xFF424242);

    final variant = currentVariant;
    if (variant == null) return const SizedBox.shrink();

    final ingredients = variant['ingredients']?.toString();
    final origin = variant['origin']?.toString();
    final bioControlNr = variant['bioControlNr']?.toString();

    // Parse features and allergens if they are JSON
    List<dynamic> features = [];
    List<dynamic> allergens = [];

    try {
      if (variant['features'] != null) {
        if (variant['features'] is String) {
          // Parse JSON string
          final featuresStr = variant['features'].toString();
          if (featuresStr.isNotEmpty && featuresStr != 'null') {
            features = (featuresStr.split(',').map((e) => e.trim()).toList());
          }
        } else if (variant['features'] is List) {
          features = variant['features'] as List;
        }
      }

      if (variant['allergens'] != null) {
        if (variant['allergens'] is String) {
          final allergensStr = variant['allergens'].toString();
          if (allergensStr.isNotEmpty && allergensStr != 'null') {
            allergens = (allergensStr.split(',').map((e) => e.trim()).toList());
          }
        } else if (variant['allergens'] is List) {
          allergens = variant['allergens'] as List;
        }
      }
    } catch (e) {
      print('Error parsing features/allergens: $e');
    }

    if ((ingredients == null || ingredients.isEmpty || ingredients == 'null') &&
        (origin == null || origin.isEmpty || origin == 'null') &&
        (bioControlNr == null ||
            bioControlNr.isEmpty ||
            bioControlNr == 'null') &&
        features.isEmpty &&
        allergens.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context)!.ingredientsOrigin,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF9E9E9E),
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 16),

          // Ingredients
          if (ingredients != null &&
              ingredients.isNotEmpty &&
              ingredients != 'null') ...[
            Text(
              AppLocalizations.of(context)!.ingredients,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              ingredients,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w400,
                color: subtextColor,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Origin
          if (origin != null && origin.isNotEmpty && origin != 'null')
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _buildInfoValueCard(
                label: AppLocalizations.of(context)!.origin,
                value: origin,
                isDark: isDark,
                icon: CupertinoIcons.globe,
              ),
            ),

          // Bio Control Number
          if (bioControlNr != null &&
              bioControlNr.isNotEmpty &&
              bioControlNr != 'null')
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _buildInfoValueCard(
                label: AppLocalizations.of(context)!.bioControl,
                value: bioControlNr,
                isDark: isDark,
                icon: CupertinoIcons.checkmark_shield_fill,
              ),
            ),

          // Features
          if (features.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context)!.features,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: features.map((feature) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withOpacity(0.05)
                        : Colors.black.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: Text(
                    feature.toString(),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? const Color(0xFF81C784)
                          : const Color(0xFF1B5E20),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],

          // Allergens
          if (allergens.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context)!.allergens,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: allergens.map((allergen) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
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
                        CupertinoIcons.exclamationmark_triangle_fill,
                        size: 16,
                        color: isDark
                            ? const Color(0xFFFFB74D)
                            : const Color(0xFFE65100),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        allergen.toString(),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? Colors.orange[300]
                              : Colors.orange[900],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildShippingInfo() {
    print('🔍 _buildShippingInfo() called');
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Get current variant data
    final variants = currentProduct['variants'] as List<dynamic>?;
    print('🔍 variants: $variants');
    print('🔍 variants length: ${variants?.length}');
    print('🔍 _selectedVariantIndex: $_selectedVariantIndex');

    final currentVariant = variants != null && variants.isNotEmpty
        ? variants[_selectedVariantIndex]
        : null;

    print('🔍 currentVariant is null: ${currentVariant == null}');
    if (currentVariant != null) {
      print('🔍 currentVariant keys: ${currentVariant.keys.toList()}');
    }

    // Group data into categories (NO SHIPPING OPTIONS)
    final tradeInfo = <Map<String, dynamic>>[];
    final deliveryDetails = <Map<String, dynamic>>[];
    final productInfo =
        <Map<String, dynamic>>[]; // New category for product-specific info

    // Delivery Details
    if (currentProduct['deliveryTime'] != null) {
      final time = currentProduct['deliveryTime'].toString();
      if (time.isNotEmpty && time != 'null') {
        deliveryDetails.add({
          'icon': CupertinoIcons.time,
          'title': AppLocalizations.of(context)!.deliveryTime,
          'value': '$time days',
        });
      }
    }

    if (currentProduct['delivery_area'] != null) {
      final area = currentProduct['delivery_area'].toString().trim();
      if (area.isNotEmpty && area != 'null') {
        deliveryDetails.add({
          'icon': CupertinoIcons.globe,
          'title': AppLocalizations.of(context)!.deliveryArea,
          'value': area,
        });
      }
    }

    if (currentProduct['tracking_available'] != null) {
      final tracking = currentProduct['tracking_available'];
      deliveryDetails.add({
        'icon': CupertinoIcons.location_fill,
        'title': AppLocalizations.of(context)!.tracking,
        'value': (tracking == 1 || tracking == true)
            ? AppLocalizations.of(context)!.available
            : AppLocalizations.of(context)!.notAvailable,
      });
    }

    // Trade Information
    if (currentProduct['country'] != null) {
      final country = currentProduct['country'].toString();
      if (country.isNotEmpty && country != 'null') {
        tradeInfo.add({
          'icon': CupertinoIcons.flag,
          'title': AppLocalizations.of(context)!.originCountry,
          'value': country,
        });
      }
    }

    if (currentProduct['incoterm'] != null) {
      final incoterm = currentProduct['incoterm'].toString();
      if (incoterm.isNotEmpty && incoterm != 'null') {
        tradeInfo.add({
          'icon': CupertinoIcons.briefcase,
          'title': AppLocalizations.of(context)!.incotermsTitle,
          'value': incoterm,
        });
      }
    }

    if (currentProduct['wagon_type'] != null) {
      final wagonType = currentProduct['wagon_type'].toString();
      if (wagonType.isNotEmpty && wagonType != 'null') {
        final l10n = AppLocalizations.of(context)!;
        tradeInfo.add({
          'icon': CupertinoIcons.tram_fill,
          'title': l10n.wagonType,
          'value': wagonLabelFromType(wagonType, l10n),
        });
      }
    }

    if (currentProduct['cleaning_certificate'] != null) {
      final cert = currentProduct['cleaning_certificate'];
      if (cert == 1 || cert == true) {
        tradeInfo.add({
          'icon': CupertinoIcons.checkmark_seal_fill,
          'title': AppLocalizations.of(context)!.cleaningCertificate,
          'value': AppLocalizations.of(context)!.available,
        });
      }
    }

    if (currentProduct['temperature_requirements'] != null) {
      final temp = currentProduct['temperature_requirements'].toString();
      final unit = currentProduct['temperature_unit']?.toString() ?? 'celsius';
      if (temp.isNotEmpty && temp != 'null') {
        final unitSymbol = unit == 'fahrenheit' ? '°F' : '°C';
        tradeInfo.add({
          'icon': CupertinoIcons.thermometer,
          'title': AppLocalizations.of(context)!.temperature,
          'value': '$temp$unitSymbol',
        });
      }
    }

    // Product-specific information from variant
    if (currentVariant != null) {
      // DEBUG: Print all variant keys to check if new fields are present
      print('🔍 DEBUG currentVariant keys: ${currentVariant.keys.toList()}');
      print('🔍 DEBUG organic value: ${currentVariant['organic']}');
      print('🔍 DEBUG bioControlNr value: ${currentVariant['bioControlNr']}');
      print(
        '🔍 DEBUG dailyProduction value: ${currentVariant['dailyProduction']}',
      );
      print('🔍 DEBUG terpenes value: ${currentVariant['terpenes']}');
      print('🔍 DEBUG ingredients value: ${currentVariant['ingredients']}');

      // Bio/Organic status
      if (currentVariant['organic'] == 1 || currentVariant['organic'] == true) {
        print('✅ Adding organic to productInfo');
        productInfo.add({
          'icon': CupertinoIcons.leaf_arrow_circlepath,
            'title': AppLocalizations.of(context)!.organic,
            'value': AppLocalizations.of(context)!.certified,
        });
      }

      // Bio Control Number
      if (currentVariant['bioControlNr'] != null) {
        final bioNr = currentVariant['bioControlNr'].toString();
        print('🔍 DEBUG bioNr after toString: "$bioNr"');
        if (bioNr.isNotEmpty && bioNr != 'null') {
          print('✅ Adding bioControlNr to productInfo');
          productInfo.add({
            'icon': CupertinoIcons.checkmark_shield_fill,
            'title': AppLocalizations.of(context)!.bioControl,
            'value': bioNr,
          });
        }
      }

      // Daily Production
      if (currentVariant['dailyProduction'] != null) {
        final daily = currentVariant['dailyProduction'].toString();
        print('🔍 DEBUG daily after toString: "$daily"');
        if (daily.isNotEmpty &&
            daily != 'null' &&
            daily != '0' &&
            daily != '0.00') {
          print('✅ Adding dailyProduction to productInfo');
          final unit = currentVariant['unit']?.toString() ?? 'kg';
          productInfo.add({
            'icon': CupertinoIcons.chart_bar_fill,
            'title': AppLocalizations.of(context)!.dailyProduction,
            'value': '$daily $unit',
          });
        }
      }

      // Terpenes (important for cannabis products)
      if (currentVariant['terpenes'] != null) {
        final terpenes = currentVariant['terpenes'].toString();
        print('🔍 DEBUG terpenes after toString: "$terpenes"');
        if (terpenes.isNotEmpty && terpenes != 'null' && terpenes != 'none') {
          print('✅ Adding terpenes to productInfo');
          productInfo.add({
            'icon': CupertinoIcons.lab_flask,
            'title': AppLocalizations.of(context)!.terpenes,
            'value': terpenes,
          });
        }
      }

      // Ingredients
      if (currentVariant['ingredients'] != null) {
        final ingredients = currentVariant['ingredients'].toString();
        print(
          '🔍 DEBUG ingredients after toString: "$ingredients" (length: ${ingredients.length})',
        );
        if (ingredients.isNotEmpty &&
            ingredients != 'null' &&
            ingredients.length <= 50) {
          print('✅ Adding ingredients to productInfo');
          productInfo.add({
            'icon': CupertinoIcons.list_bullet,
            'title': AppLocalizations.of(context)!.ingredients,
            'value': ingredients,
          });
        }
      }

      print('🔍 DEBUG productInfo final count: ${productInfo.length}');
    }

    if (tradeInfo.isEmpty && deliveryDetails.isEmpty && productInfo.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product Information (new section for variant-specific data)
          if (productInfo.isNotEmpty) ...[
            _buildTradeRepublicSection(
              AppLocalizations.of(context)!.productInformation,
              productInfo,
              isDark,
            ),
            if (deliveryDetails.isNotEmpty || tradeInfo.isNotEmpty)
              const SizedBox(height: 12),
          ],

          // Delivery Details
          if (deliveryDetails.isNotEmpty) ...[
            _buildTradeRepublicSection(
              AppLocalizations.of(context)!.deliveryInformation,
              deliveryDetails,
              isDark,
            ),
            if (tradeInfo.isNotEmpty) const SizedBox(height: 12),
          ],

          // Trade Information
          if (tradeInfo.isNotEmpty) ...[
            _buildTradeRepublicSection(
              AppLocalizations.of(context)!.tradeDetails,
              tradeInfo,
              isDark,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoValueCard({
    required String label,
    required String value,
    required bool isDark,
    IconData? icon,
    VoidCallback? onTap,
  }) {
    final valueColor = isDark ? const Color(0xFFE0E0E0) : const Color(0xFF424242);
    final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8F8F8);

    final child = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    icon,
                    size: 15,
                    color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6E6E73),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF9E9E9E),
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              if (onTap != null)
                Icon(
                  CupertinoIcons.doc_on_doc,
                  size: 14,
                  color: isDark ? Colors.white54 : Colors.black38,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: valueColor,
              height: 1.35,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return child;

    return GestureDetector(
      onTap: onTap,
      child: child,
    );
  }

  Widget _buildTradeRepublicSection(
    String title,
    List<Map<String, dynamic>> items,
    bool isDark,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Title
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF9E9E9E),
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 12),

        // Items list - stacked values (mobile friendly / no squeezed rows)
        ...items.asMap().entries.map((entry) {
          final item = entry.value;
          final isLast = entry.key == items.length - 1;
          final value = item['value'].toString();

          return Column(
            children: [
              _buildInfoValueCard(
                label: item['title'].toString(),
                value: value,
                isDark: isDark,
                icon: item['icon'] as IconData?,
                onTap: () {
                  Clipboard.setData(ClipboardData(text: value));
                  HapticFeedback.lightImpact();
                  widget.showBottomMessage?.call(
                    AppLocalizations.of(context)!.codeCopied,
                    isSuccess: true,
                  );
                },
                ),
              if (!isLast) const SizedBox(height: 8),
            ],
          );
        }),
      ],
    );
  }

  Widget _buildActionBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: TradeRepublicButton(
        label: _isOutOfStock()
            ? AppLocalizations.of(context)!.outOfStock2
            : AppLocalizations.of(context)!.addToCart,
        onPressed: _isOutOfStock() ? null : _showQuantityBottomSheet,
        width: double.infinity,
      ),
    );
  }

  String _getStockText() {
    final variant = currentVariant;
    if (variant?['alwaysAvailable'] == 1) {
      return AppLocalizations.of(context)!.inStock;
    }

    final stock = variant?['stock']?.toString();
    if (stock != null) {
      final stockInt = int.tryParse(stock) ?? 0;
      return stockInt > 0
          ? AppLocalizations.of(context)!.inStock
          : AppLocalizations.of(context)!.outOfStock2;
    }
    return AppLocalizations.of(context)!.outOfStock1;
  }

  bool _isOutOfStock() {
    final variant = currentVariant;
    if (variant?['alwaysAvailable'] == 1) return false;

    final stock = variant?['stock']?.toString();
    if (stock != null) {
      final stockInt = int.tryParse(stock) ?? 0;
      return stockInt <= 0;
    }
    return true;
  }

  bool _isMultiplierMode = false; // Track if we're in multiplier mode
  String _multiplierInput = ''; // Store multiplier value separately
  bool _isConverterMode = false; // Track if we're in converter mode
  String _converterInput = ''; // Store converter input value
  String _converterInputUnit = 'lbs'; // Selected input unit for conversion

  // Unit conversion factors: how many units equal 1 kg
  final Map<String, double> _unitConversions = {
    'kg': 1.0,
    'kilogram': 1.0,
    'g': 1000.0, // 1 kg = 1000 g
    'gram': 1000.0, // 1 kg = 1000 g
    'grams': 1000.0,
    'lbs': 2.20462, // 1 kg = 2.20462 lbs
    'lb': 2.20462,
    'pound': 2.20462,
    'pounds': 2.20462,
    'oz': 35.274, // 1 kg = 35.274 oz
    'ounce': 35.274,
    'ounces': 35.274,
    't': 0.001, // 1 kg = 0.001 metric ton
    'ton': 0.001,
    'tons': 0.001,
    'mg': 1000000.0, // 1 kg = 1,000,000 mg
    'milligram': 1000000.0,
    'milligrams': 1000000.0,
  };

  String _normalizeUnit(String unit) {
    final normalized = unit.toLowerCase().trim();
    // Return the normalized unit for lookup
    if (normalized == 'kilogram' || normalized == 'kilograms') return 'kg';
    if (normalized == 'gram' || normalized == 'grams') return 'g';
    if (normalized == 'lb' || normalized == 'pound' || normalized == 'pounds') {
      return 'lbs';
    }
    if (normalized == 'ounce' || normalized == 'ounces') return 'oz';
    if (normalized == 'ton' || normalized == 'tons') return 't';
    if (normalized == 'milligram' || normalized == 'milligrams') return 'mg';
    return normalized;
  }

  String _getConvertedValue() {
    if (_converterInput.isEmpty) return '0.00';

    // Parse auto-formatted input (e.g., "12345" displays as "123.45")
    final digitsOnly = _converterInput.replaceAll('.', '').replaceAll(',', '');
    if (digitsOnly.isEmpty) return '0.00';
    final inputValue = int.parse(digitsOnly) / 100.0;
    if (inputValue <= 0) return '0.00';

    // Normalize units for lookup
    final normalizedInputUnit = _normalizeUnit(_converterInputUnit);
    final normalizedProductUnit = _normalizeUnit(_selectedUnit);

    // Convert input to kg first
    final inputFactor = _unitConversions[normalizedInputUnit] ?? 1.0;
    final inputInKg = inputValue / inputFactor;

    // Convert from kg to product unit
    final productFactor = _unitConversions[normalizedProductUnit] ?? 1.0;
    final outputValue = inputInKg * productFactor;

    print('🔄 CONVERSION DEBUG:');
    print(
      '   Input: $inputValue $_converterInputUnit (normalized: $normalizedInputUnit)',
    );
    print('   Input factor: $inputFactor');
    print('   In kg: $inputInKg kg');
    print(
      '   Product unit: $_selectedUnit (normalized: $normalizedProductUnit)',
    );
    print('   Product factor: $productFactor');
    print('   Output: $outputValue $_selectedUnit');

    // Format with thousand separators based on app settings
    final numberFormat = widget.numberFormat ?? 'en_US';
    final formatter = NumberFormat('#,##0.00', numberFormat);
    return formatter.format(outputValue);
  }

  Future<void> _toggleFavorite() async {
    if (!_isUserLoggedIn) {
      widget.showBottomMessage?.call(AppLocalizations.of(context)!.pleaseLoginFirst, isSuccess: false);
      return;
    }

    try {
      final response = _isFavorite
          ? await ApiService.removeFromFavorites(currentProduct['id'])
          : await ApiService.addToFavorites(currentProduct['id']);

      if (response['success']) {
        setState(() => _isFavorite = !_isFavorite);
        widget.onFavoriteToggle?.call(currentProduct['id']);
        HapticFeedback.mediumImpact();
      }
    } catch (e) {
      widget.showBottomMessage?.call(AppLocalizations.of(context)!.errorTitle, isSuccess: false);
    }
  }

  void _showQuantityBottomSheet() {
    setState(() {
      _quantityInput = '';
      _isMultiplierMode = false; // Reset to quantity mode
      _multiplierInput = '';
      _isConverterMode = false; // Reset converter mode
      _converterInput = '';
      _converterInputUnit = 'lbs'; // Default to pounds
      _selectedUnit = currentVariant?['unit']?.toString() ?? 'kg';
    });

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;
    final macInputController = TextEditingController();

    void syncMacInputController() {
      final currentValue = _isConverterMode
          ? _converterInput
          : (_isMultiplierMode ? _multiplierInput : _quantityInput);
      if (macInputController.text == currentValue) return;
      macInputController.value = TextEditingValue(
        text: currentValue,
        selection: TextSelection.collapsed(offset: currentValue.length),
      );
    }

    syncMacInputController();

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      maxHeight: MediaQuery.of(context).size.height * 0.95,
      child: StatefulBuilder(
        builder: (context, setModalState) {
          // Format display value with thousand separators
          String getDisplayValue() {
            if (_isConverterMode) {
              // Converter mode: auto-format with decimal and thousand separators
              if (_converterInput.isEmpty) return '0.00';
              final digitsOnly = _converterInput
                  .replaceAll('.', '')
                  .replaceAll(',', '');
              if (digitsOnly.isEmpty) return '0.00';
              final numValue = int.parse(digitsOnly);
              final double value = numValue / 100.0;

              // Format with thousand separators
              final formatter = NumberFormat('#,##0.00', 'en_US');
              return formatter.format(value);
            } else if (_isMultiplierMode) {
              // Multiplier mode: show whole number with 'x'
              if (_multiplierInput.isEmpty) return '0x';
              return '${_multiplierInput}x';
            } else {
              // Quantity mode: digit keypad uses ×100 representation
              // (e.g. typing 100 means 1.00)
              if (_quantityInput.isEmpty) return '0.00';
              final digitsOnly = _quantityInput
                  .replaceAll('.', '')
                  .replaceAll(',', '');
              if (digitsOnly.isEmpty) return '0.00';
              final numValue = int.parse(digitsOnly);
              final double value = numValue / 100.0;

              // Format with thousand separators
              final formatter = NumberFormat('#,##0.00', 'en_US');
              return formatter.format(value);
            }
          }

          return SafeArea(
            top: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox.shrink(),

                      // Title
                      Text(
                        _isConverterMode
                            ? AppLocalizations.of(context)!.unitConverter1
                            : (_isMultiplierMode
                                  ? AppLocalizations.of(
                                      context,
                                    )!.multiplierMode.toUpperCase()
                                  : AppLocalizations.of(
                                      context,
                                    )!.quantity.toUpperCase()),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF9E9E9E),
                          letterSpacing: 1.5,
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Display area
                      if (_isConverterMode) ...[
                        // Converter mode: Input + Unit selector
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Input label
                              Text(
                                AppLocalizations.of(context)!.fromLabel,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? const Color(0xFF8E8E93)
                                      : const Color(0xFF6E6E73),
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 8),
                              // Input value + unit selector
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Text(
                                      getDisplayValue(),
                                      style: TextStyle(
                                        fontSize: 48,
                                        fontWeight: FontWeight.w800,
                                        color: textColor,
                                        height: 1.0,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  // Unit selector dropdown
                                  if (Platform.isIOS)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? const Color(0xFF2C2C2E)
                                            : const Color(0xFFF2F2F7),
                                        borderRadius: BorderRadius.circular(25),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            _converterInputUnit.toUpperCase(),
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                              color: textColor,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          CNPopupMenuButton.icon(
                                            buttonIcon: const CNSymbol(
                                              'chevron.down',
                                              size: 20,
                                            ),
                                            tint: textColor,
                                            items: [
                                              CNPopupMenuItem(
                                                label: AppLocalizations.of(
                                                  context,
                                                )!.kilogram,
                                                icon: const CNSymbol(
                                                  'scalemass',
                                                  size: 18,
                                                ),
                                              ),
                                              CNPopupMenuItem(
                                                label: AppLocalizations.of(
                                                  context,
                                                )!.gram,
                                                icon: const CNSymbol(
                                                  'scalemass',
                                                  size: 18,
                                                ),
                                              ),
                                              CNPopupMenuItem(
                                                label: AppLocalizations.of(
                                                  context,
                                                )!.pound,
                                                icon: const CNSymbol(
                                                  'scalemass',
                                                  size: 18,
                                                ),
                                              ),
                                              CNPopupMenuItem(
                                                label: AppLocalizations.of(
                                                  context,
                                                )!.ounce,
                                                icon: const CNSymbol(
                                                  'scalemass',
                                                  size: 18,
                                                ),
                                              ),
                                              CNPopupMenuItem(
                                                label: AppLocalizations.of(
                                                  context,
                                                )!.ton,
                                                icon: const CNSymbol(
                                                  'scalemass',
                                                  size: 18,
                                                ),
                                              ),
                                              CNPopupMenuItem(
                                                label: AppLocalizations.of(
                                                  context,
                                                )!.milligram,
                                                icon: const CNSymbol(
                                                  'scalemass',
                                                  size: 18,
                                                ),
                                              ),
                                            ],
                                            onSelected: (index) {
                                              final units = [
                                                'kg',
                                                'g',
                                                'lbs',
                                                'oz',
                                                't',
                                                'mg',
                                              ];
                                              setState(
                                                () => _converterInputUnit =
                                                    units[index],
                                              );
                                              setModalState(() {});
                                              HapticFeedback.lightImpact();
                                            },
                                          ),
                                        ],
                                      ),
                                    )
                                  else
                                    GestureDetector(
                                      onTap: () {
                                        _showUnitPicker(setModalState, isDark);
                                        HapticFeedback.lightImpact();
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isDark
                                              ? const Color(0xFF2C2C2E)
                                              : const Color(0xFFF2F2F7),
                                          borderRadius: BorderRadius.circular(
                                            25,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              _converterInputUnit.toUpperCase(),
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w700,
                                                color: textColor,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Icon(
                                              CupertinoIcons.chevron_down,
                                              color: textColor,
                                              size: 24,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 32),
                              // Converted output
                              Text(
                                AppLocalizations.of(context)!.toLabel,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? const Color(0xFF8E8E93)
                                      : const Color(0xFF6E6E73),
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Flexible(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        _getConvertedValue(),
                                        style: TextStyle(
                                          fontSize: 48,
                                          fontWeight: FontWeight.w800,
                                          color: isDark
                                              ? const Color(0xFF4CAF50)
                                              : const Color(0xFF2E7D32),
                                          height: 1.0,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Text(
                                    _selectedUnit.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                      color: isDark
                                          ? const Color(0xFF8E8E93)
                                          : const Color(0xFF6E6E73),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        // Quantity/Multiplier mode: Single display with consistent height
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: SizedBox(
                            height: 160, // Match converter mode vertical space
                            child: Center(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Text(
                                    getDisplayValue(),
                                    style: TextStyle(
                                      fontSize: _getDynamicFontSize(
                                        getDisplayValue(),
                                      ),
                                      fontWeight: FontWeight.w700,
                                      color: textColor,
                                      height: 1,
                                      letterSpacing: -2,
                                    ),
                                  ),
                                  if (!_isMultiplierMode) ...[
                                    const SizedBox(width: 10),
                                    Text(
                                      _selectedUnit.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w700,
                                        color: isDark
                                            ? const Color(0xFF8E8E93)
                                            : const Color(0xFF6E6E73),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 36),

                      // Input area - TextField on macOS, Number pad on mobile
                      if (Platform.isMacOS) ...[
                        // macOS: TextField input
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 40),
                          child: Column(
                            children: [
                              // Mode selector buttons
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  _buildMacOSModeButton(
                                    AppLocalizations.of(context)!.quantity,
                                    !_isMultiplierMode && !_isConverterMode,
                                    () {
                                      setState(() {
                                        _isMultiplierMode = false;
                                        _isConverterMode = false;
                                        _quantityInput = '';
                                      });
                                      syncMacInputController();
                                      setModalState(() {});
                                    },
                                    isDark,
                                    textColor,
                                  ),
                                  _buildMacOSModeButton(
                                    AppLocalizations.of(context)!.multiplierMode,
                                    _isMultiplierMode,
                                    () {
                                      setState(() {
                                        _isMultiplierMode = true;
                                        _isConverterMode = false;
                                        _multiplierInput = '';
                                      });
                                      syncMacInputController();
                                      setModalState(() {});
                                    },
                                    isDark,
                                    textColor,
                                  ),
                                  _buildMacOSModeButton(
                                    AppLocalizations.of(context)!.unitConverter,
                                    _isConverterMode,
                                    () {
                                      setState(() {
                                        _isMultiplierMode = false;
                                        _isConverterMode = true;
                                        _converterInput = '';
                                      });
                                      syncMacInputController();
                                      setModalState(() {});
                                    },
                                    isDark,
                                    textColor,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),
                              // TextField
                              TradeRepublicTextField(
                                controller: macInputController,
                                autofocus: true,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                hintText: _isConverterMode
                                    ? AppLocalizations.of(context)!.enterAmount
                                    : (_isMultiplierMode
                                          ? AppLocalizations.of(
                                              context,
                                            )!.enterMultiplier
                                          : AppLocalizations.of(context)!.enterQuantity),
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w600,
                                  color: textColor,
                                ),
                                onChanged: (value) {
                                  setState(() {
                                    if (_isConverterMode) {
                                      _converterInput = value;
                                    } else if (_isMultiplierMode) {
                                      _multiplierInput = value;
                                    } else {
                                      _quantityInput =
                                          _normalizeQuantityDigitsToDecimal(
                                            value,
                                          );
                                      syncMacInputController();
                                    }
                                  });
                                  setModalState(() {});
                                },
                              ),
                              if (_isConverterMode) ...[
                                const SizedBox(height: 16),
                                // Unit selector for converter - Bottom Sheet
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'From:',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: isDark
                                            ? const Color(0xFF8E8E93)
                                            : const Color(0xFF6E6E73),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    GestureDetector(
                                      onTap: () {
                                        _showUnitPicker(setModalState, isDark);
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isDark
                                              ? const Color(0xFF1C1C1E)
                                              : const Color(0xFFF2F2F7),
                                          borderRadius: BorderRadius.circular(
                                            25,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              _converterInputUnit.toUpperCase(),
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                                color: textColor,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Icon(
                                              CupertinoIcons.chevron_down,
                                              color: textColor,
                                              size: 20,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 24),
                                    Text(
                                      AppLocalizations.of(
                                        context,
                                      )!.toUnit(_selectedUnit.toUpperCase()),
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: textColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ] else ...[
                        // Mobile: Number pad
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 40),
                          child: SizedBox(
                            height: 340, // Fixed height for number pad
                            child: GridView.count(
                              crossAxisCount: 3,
                              mainAxisSpacing: 16,
                              crossAxisSpacing: 32,
                              childAspectRatio: 1.2,
                              physics: const NeverScrollableScrollPhysics(),
                              children: [
                                for (var i = 1; i <= 9; i++)
                                  _buildNumberButton(
                                    i.toString(),
                                    textColor,
                                    isDark,
                                    setModalState,
                                  ),
                                // Mode switch button (bottom left)
                                _buildMultiplierButton(
                                  textColor,
                                  isDark,
                                  setModalState,
                                ),
                                _buildNumberButton(
                                  '0',
                                  textColor,
                                  isDark,
                                  setModalState,
                                ),
                                _buildDeleteButton(
                                  textColor,
                                  isDark,
                                  setModalState,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 14),

                      // Add to cart button
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: TradeRepublicButton(
                          label: AppLocalizations.of(context)!.addToCart,
                          onPressed: () {
                            _addToCartFromBottomSheet();
                            Navigator.pop(context);
                          },
                          width: double.infinity,
                        ),
                      ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    ).whenComplete(macInputController.dispose);
  }

  String _normalizeQuantityDigitsToDecimal(String rawValue) {
    final digitsOnly = rawValue.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.isEmpty) return '';
    final digitsValue = int.tryParse(digitsOnly) ?? 0;
    if (digitsValue <= 0) return '';
    return (digitsValue / 100.0).toStringAsFixed(2);
  }

  double _getDynamicFontSize(String displayValue) {
    final length = displayValue.length;

    // Adjust font size based on length
    if (length <= 6) return 72.0; // e.g., "123.45"
    if (length <= 8) return 64.0; // e.g., "1,234.56"
    if (length <= 10) return 56.0; // e.g., "12,345.67"
    if (length <= 12) return 48.0; // e.g., "123,456.78"
    if (length <= 14) return 42.0; // e.g., "1,234,567.89"
    if (length <= 16) return 36.0; // e.g., "12,345,678.90"
    return 32.0; // Very long numbers
  }

  Widget _buildNumberButton(
    String number,
    Color textColor,
    bool isDark,
    StateSetter setModalState,
  ) {
    if (Platform.isIOS) {
      // iOS: Use CNButton with custom text styling
      return Center(
        child: GestureDetector(
          onTap: () {
            if (_isConverterMode) {
              // Converter mode: max 10 digits (auto-formatted)
              final digitsOnly = _converterInput
                  .replaceAll('.', '')
                  .replaceAll(',', '');
              if (digitsOnly.length >= 10) return;

              setState(() {
                _converterInput += number;
              });
              setModalState(() {});
            } else if (_isMultiplierMode) {
              // Multiplier mode: only whole numbers, max 3 digits
              if (_multiplierInput.length >= 3) return;

              setState(() {
                _multiplierInput += number;
              });
              setModalState(() {});
            } else {
              // Quantity mode: max 10 digits in ×100 representation.
              final digitsOnly = _quantityInput
                  .replaceAll('.', '')
                  .replaceAll(',', '');
              if (digitsOnly.length >= 10) return;

              setState(() {
                _quantityInput += number;
              });
              setModalState(() {});
            }
            HapticFeedback.lightImpact();
          },
          child: Text(
            number,
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
        ),
      );
    }

    // Android: Use GestureDetector
    return GestureDetector(
      onTap: () {
        if (_isConverterMode) {
          // Converter mode: max 10 digits (auto-formatted)
          final digitsOnly = _converterInput
              .replaceAll('.', '')
              .replaceAll(',', '');
          if (digitsOnly.length >= 10) return;

          setState(() {
            _converterInput += number;
          });
          setModalState(() {});
        } else if (_isMultiplierMode) {
          // Multiplier mode: only whole numbers, max 3 digits
          if (_multiplierInput.length >= 3) return;

          setState(() {
            _multiplierInput += number;
          });
          setModalState(() {});
        } else {
          // Quantity mode: max 10 digits in ×100 representation.
          final digitsOnly = _quantityInput
              .replaceAll('.', '')
              .replaceAll(',', '');
          if (digitsOnly.length >= 10) return;

          setState(() {
            _quantityInput += number;
          });
          setModalState(() {});
        }
        HapticFeedback.lightImpact();
      },
      child: Center(
        child: Text(
          number,
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w700,
            color: textColor,
          ),
        ),
      ),
    );
  }

  Widget _buildDeleteButton(
    Color textColor,
    bool isDark,
    StateSetter setModalState,
  ) {
    return GestureDetector(
      onTap: () {
        if (_isConverterMode) {
          if (_converterInput.isNotEmpty) {
            setState(() {
              _converterInput = _converterInput.substring(
                0,
                _converterInput.length - 1,
              );
            });
            setModalState(() {});
            HapticFeedback.lightImpact();
          }
        } else if (_isMultiplierMode) {
          if (_multiplierInput.isNotEmpty) {
            setState(() {
              _multiplierInput = _multiplierInput.substring(
                0,
                _multiplierInput.length - 1,
              );
            });
            setModalState(() {});
            HapticFeedback.lightImpact();
          }
        } else {
          if (_quantityInput.isNotEmpty) {
            setState(() {
              _quantityInput = _quantityInput.substring(
                0,
                _quantityInput.length - 1,
              );
            });
            setModalState(() {});
            HapticFeedback.lightImpact();
          }
        }
      },
      child: Center(
        child: Icon(
          CupertinoIcons.delete_left,
          color: textColor.withOpacity(0.6),
          size: 28,
        ),
      ),
    );
  }

  Widget _buildMultiplierButton(
    Color textColor,
    bool isDark,
    StateSetter setModalState,
  ) {
    if (Platform.isIOS) {
      // iOS: Use CNPopupMenuButton with 3 modes
      return CNPopupMenuButton.icon(
        buttonIcon: CNSymbol(
          _isConverterMode
              ? 'arrow.left.arrow.right.circle.fill'
              : (_isMultiplierMode
                    ? 'xmark.circle.fill'
                    : 'number.circle.fill'),
          size: 28,
        ),
        tint: (_isMultiplierMode || _isConverterMode)
            ? (isDark ? Colors.white : Colors.black)
            : textColor,
        items: [
          CNPopupMenuItem(
            label: AppLocalizations.of(context)!.quantityMode,
            icon: CNSymbol('number.circle', size: 18),
          ),
          CNPopupMenuItem(
            label: AppLocalizations.of(context)!.multiplierMode,
            icon: CNSymbol('xmark.circle', size: 18),
          ),
          CNPopupMenuItem(
            label: AppLocalizations.of(context)!.unitConverter,
            icon: CNSymbol('arrow.left.arrow.right.circle', size: 18),
          ),
        ],
        onSelected: (index) {
          HapticFeedback.mediumImpact();
          setState(() {
            _isMultiplierMode = index == 1;
            _isConverterMode = index == 2;
            // Clear inputs when switching modes
            _quantityInput = '';
            _multiplierInput = '';
            _converterInput = '';
          });
          setModalState(() {});
        },
      );
    }

    // Android: Use GestureDetector with Container - cycle through modes
    final isActive = _isMultiplierMode || _isConverterMode;
    final buttonColor = isActive
        ? (isDark ? Colors.white : Colors.black)
        : (isDark ? const Color(0xFF424242) : const Color(0xFFEEEEEE));
    final iconColor = isActive
        ? (isDark ? Colors.black : Colors.white)
        : textColor;

    IconData icon;
    if (_isConverterMode) {
      icon = CupertinoIcons.arrow_left_right;
    } else if (_isMultiplierMode) {
      icon = CupertinoIcons.multiply;
    } else {
      icon = CupertinoIcons.number;
    }

    return GestureDetector(
      onTap: () {
        // Medium haptic feedback for mode switching
        HapticFeedback.mediumImpact();

        setState(() {
          // Cycle through: Quantity -> Multiplier -> Converter -> Quantity
          if (_isConverterMode) {
            _isConverterMode = false;
            _isMultiplierMode = false;
          } else if (_isMultiplierMode) {
            _isMultiplierMode = false;
            _isConverterMode = true;
          } else {
            _isMultiplierMode = true;
          }
          // Clear inputs when switching modes
          _quantityInput = '';
          _multiplierInput = '';
          _converterInput = '';
        });
        setModalState(() {});
      },
      child: Center(
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: buttonColor,
            borderRadius: BorderRadius.circular(25),
          ),
          child: Icon(icon, color: iconColor, size: 28),
        ),
      ),
    );
  }

  void _showUnitPicker(StateSetter setModalState, bool isDark) {
    final units = ['kg', 'g', 'lbs', 'oz', 't', 'mg'];

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppLocalizations.of(context)!.selectUnit,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF9E9E9E),
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: units
                      .map(
                        (unit) => TradeRepublicListTile(
                          title: unit.toUpperCase(),
                          backgroundColor: _converterInputUnit == unit
                              ? TradeRepublicTheme.selectionContainerBackground(
                                  context,
                                )
                              : null,
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                          trailing: _converterInputUnit == unit
                              ? Icon(
                                  CupertinoIcons.checkmark_circle_fill,
                                  color: TradeRepublicTheme
                                      .selectionContainerForeground(context),
                                  size: 20,
                                )
                              : null,
                          onTap: () {
                            setState(() {
                              _converterInputUnit = unit;
                            });
                            setModalState(() {});
                            Navigator.pop(context);
                            HapticFeedback.lightImpact();
                          },
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _addToCartFromBottomSheet() async {
    // Check which mode we're in and validate accordingly
    String inputValue;
    if (_isConverterMode) {
      inputValue = _converterInput;
    } else if (_isMultiplierMode) {
      inputValue = _multiplierInput;
    } else {
      inputValue = _quantityInput;
    }

    if (inputValue.isEmpty) {
      widget.showBottomMessage?.call(AppLocalizations.of(context)!.pleaseEnterQuantity, isSuccess: false);
      return;
    }

    try {
      double quantityValue;

      if (_isConverterMode) {
        if (Platform.isMacOS) {
          // macOS: direct text input, convert to product units
          final inputDouble = _parseFlexibleDecimal(_converterInput);
          if (inputDouble <= 0) {
            widget.showBottomMessage?.call(
              AppLocalizations.of(context)!.invalidQuantity,
              isSuccess: false,
            );
            return;
          }

          // Convert to product units
          final normalizedInputUnit = _normalizeUnit(_converterInputUnit);
          final normalizedProductUnit = _normalizeUnit(_selectedUnit);

          final inputFactor = _unitConversions[normalizedInputUnit] ?? 1.0;
          final inputInKg = inputDouble / inputFactor;

          final productFactor = _unitConversions[normalizedProductUnit] ?? 1.0;
          final outputValue = inputInKg * productFactor;

          quantityValue = outputValue;
        } else {
          // Mobile: get converted value in product units
          final convertedStr = _getConvertedValue();
          final convertedValue = _parseFlexibleDecimal(convertedStr);
          if (convertedValue <= 0) {
            widget.showBottomMessage?.call(
              AppLocalizations.of(context)!.invalidQuantity,
              isSuccess: false,
            );
            return;
          }
          quantityValue = convertedValue;
        }
      } else if (_isMultiplierMode) {
        if (Platform.isMacOS) {
          // macOS: direct text input
          final multiplierValue = _parseFlexibleDecimal(_multiplierInput);
          if (multiplierValue <= 0) {
            widget.showBottomMessage?.call(
              AppLocalizations.of(context)!.invalidMultiplier,
              isSuccess: false,
            );
            return;
          }

          // Multiplier mode should map directly to quantity units.
          // Example: "3" => 3 units in cart (not 300).
          quantityValue = multiplierValue;
        } else {
          // Mobile: parse digits
          final multiplierValue = int.tryParse(_multiplierInput) ?? 0;
          if (multiplierValue <= 0) {
            widget.showBottomMessage?.call(
              AppLocalizations.of(context)!.invalidMultiplier,
              isSuccess: false,
            );
            return;
          }

          // Multiplier mode should map directly to quantity units.
          // Example: "3" => 3 units in cart (not 300).
          quantityValue = multiplierValue.toDouble();
        }
      } else {
        if (Platform.isMacOS) {
          // macOS quantity input follows the same digit keypad semantics as mobile:
          // digits are interpreted as ×100 (e.g. "100" => 1.00, "1.00" => 1.00).
          final digitsOnly = _quantityInput
              .replaceAll('.', '')
              .replaceAll(',', '');
          if (digitsOnly.isEmpty) {
            widget.showBottomMessage?.call(
              AppLocalizations.of(context)!.invalidQuantity,
              isSuccess: false,
            );
            return;
          }
          final digitsValue = int.tryParse(digitsOnly) ?? 0;
          if (digitsValue <= 0) {
            widget.showBottomMessage?.call(
              AppLocalizations.of(context)!.invalidQuantity,
              isSuccess: false,
            );
            return;
          }
          quantityValue = digitsValue / 100.0;
        } else {
          // Mobile quantity keypad stores ×100 quantity digits.
          final digitsOnly = _quantityInput
              .replaceAll('.', '')
              .replaceAll(',', '');
          if (digitsOnly.isEmpty) {
            widget.showBottomMessage?.call(
              AppLocalizations.of(context)!.invalidQuantity,
              isSuccess: false,
            );
            return;
          }
          final digitsValue = int.tryParse(digitsOnly) ?? 0;
          if (digitsValue <= 0) {
            widget.showBottomMessage?.call(
              AppLocalizations.of(context)!.invalidQuantity,
              isSuccess: false,
            );
            return;
          }
          quantityValue = digitsValue / 100.0;
        }
      }

      if (quantityValue <= 0) {
        widget.showBottomMessage?.call(AppLocalizations.of(context)!.invalidQuantity, isSuccess: false);
        return;
      }

      // Send actual quantity value to DB (e.g. 1.00, 4.56, 12).
      final response = await ApiService.addToCart(
        currentProduct['id'],
        quantity: quantityValue,
        variantIdx: _selectedVariantIndex,
      );

      if (response['success']) {
        widget.showBottomMessage?.call(AppLocalizations.of(context)!.addedToCart, isSuccess: true);
        widget.onCartChanged?.call();
        Navigator.pop(context); // Close the bottom sheet
        HapticFeedback.mediumImpact();
      }
    } catch (e) {
      widget.showBottomMessage?.call(AppLocalizations.of(context)!.invalidQuantity, isSuccess: false);
    }
  }

  // Helper widgets for macOS
  Widget _buildMacOSModeButton(
    String label,
    bool isSelected,
    VoidCallback onTap,
    bool isDark,
    Color textColor,
  ) {
    return TradeRepublicButton(
      label: label,
      isSecondary: !isSelected,
      onPressed: onTap,
    );
  }
}

class _FullscreenProductImageViewer extends StatefulWidget {
  final List<dynamic> images;
  final int initialIndex;

  const _FullscreenProductImageViewer({
    required this.images,
    required this.initialIndex,
  });

  @override
  State<_FullscreenProductImageViewer> createState() =>
      _FullscreenProductImageViewerState();
}

class _FullscreenProductImageViewerState
    extends State<_FullscreenProductImageViewer> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.images.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  ImageProvider? _resolveImageProvider(dynamic imageEntry) {
    final imageUrl =
        imageEntry['image_url'] ?? imageEntry['imageUrl'] ?? imageEntry['url'] ?? '';
    if (imageUrl is! String || imageUrl.isEmpty) return null;

    if (imageUrl.startsWith('data:image')) {
      try {
        return MemoryImage(base64Decode(imageUrl.split(',').last));
      } catch (_) {
        return null;
      }
    }

    return NetworkImage(imageUrl);
  }

  @override
  Widget build(BuildContext context) {
    final hasMultiple = widget.images.length > 1;

    return Scaffold(
      backgroundColor: Colors.black.withOpacity(0.96),
      body: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: widget.images.length,
              onPageChanged: (index) {
                setState(() => _currentIndex = index);
              },
              itemBuilder: (context, index) {
                final provider = _resolveImageProvider(widget.images[index]);

                return InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Center(
                    child: provider != null
                        ? Image(
                            image: provider,
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => const Icon(
                              CupertinoIcons.photo,
                              color: Colors.white38,
                              size: 56,
                            ),
                          )
                        : const Icon(
                            CupertinoIcons.photo,
                            color: Colors.white38,
                            size: 56,
                          ),
                  ),
                );
              },
            ),
            Positioned(
              top: 8,
              left: 12,
              child: CupertinoButton(
                padding: const EdgeInsets.all(10),
                color: Colors.black.withOpacity(0.28),
                borderRadius: BorderRadius.circular(24),
                onPressed: () => Navigator.of(context).pop(), minimumSize: Size(0, 0),
                child: const Icon(
                  CupertinoIcons.xmark,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
            if (hasMultiple)
              Positioned(
                top: 14,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    '${_currentIndex + 1}/${widget.images.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
