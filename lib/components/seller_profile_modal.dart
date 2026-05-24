import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/trade_republic_widgets.dart';
import '../services/app_localizations.dart';
import 'product_details_modal.dart';
import 'chat_modal.dart';
import '../services/cultioo_spinner.dart';

class SellerProfileModal extends StatefulWidget {
  final String sellerId;
  final String sellerName;
  final VoidCallback?
  onFollowChanged; // Callback for when follow status changes
  final Function(String username, String name)?
  onStartChat; // Callback for starting a chat

  const SellerProfileModal({
    super.key,
    required this.sellerId,
    required this.sellerName,
    this.onFollowChanged,
    this.onStartChat,
  });

  @override
  State<SellerProfileModal> createState() => _SellerProfileModalState();
}

class _SellerProfileModalState extends State<SellerProfileModal> {
  bool _isLoading = true;
  bool _isFollowing = false;
  bool _isFollowLoading = false;
  Map<String, dynamic>? _sellerInfo;

  @override
  void initState() {
    super.initState();
    _loadSellerProfile();
    _checkFollowStatus();
  }

  Future<void> _checkFollowStatus() async {
    try {
      // Check SharedPreferences for follow status
      final prefs = await SharedPreferences.getInstance();
      final isFollowing =
          prefs.getBool('following_${widget.sellerId}') ?? false;

      setState(() {
        _isFollowing = isFollowing;
      });

      // TODO: Also check with backend API to sync status
    } catch (e) {
      // Handle error silently
    }
  }

  Future<void> _toggleFollow() async {
    if (!ApiService.isLoggedIn) {
      TopNotification.error(context, AppLocalizations.of(context)!.pleaseLoginToFollow);
      return;
    }

    if (_isFollowLoading) return;

    setState(() {
      _isFollowLoading = true;
    });

    try {
      final newFollowStatus = !_isFollowing;
      print(
        '🔵 SellerProfileModal: Toggle follow - new status will be: $newFollowStatus',
      );
      print(
        '🔵 SellerProfileModal: Seller ID: ${widget.sellerId}, Seller Name: ${widget.sellerName}',
      );

      // Save to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('following_${widget.sellerId}', newFollowStatus);

      // Update followed users list
      if (newFollowStatus) {
        print('📝 SellerProfileModal: Adding to followed users list');
        await _addToFollowedUsers();
        // Also call the backend API to follow the user
        await _followUserOnServer();
      } else {
        print('📝 SellerProfileModal: Removing from followed users list');
        await _removeFromFollowedUsers();
        // Also call the backend API to unfollow the user
        await _unfollowUserOnServer();
      }

      // Simulate API call delay
      await Future.delayed(const Duration(milliseconds: 500));

      setState(() {
        _isFollowing = newFollowStatus;
        _isFollowLoading = false;
      });

      // Show feedback to user
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        TopNotification.success(
          context,
          _isFollowing
              ? '${l10n.follow}: ${widget.sellerName}'
              : '${l10n.remove}: ${widget.sellerName}',
        );
      }
    } catch (e) {
      setState(() {
        _isFollowLoading = false;
      });

      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        TopNotification.error(
          context,
          l10n.unknownError,
        );
      }
    }
  }

  Future<void> _addToFollowedUsers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final followedUsersJson = prefs.getStringList('followed_users') ?? [];

      // Check if seller is already in the list
      final followedUsers = followedUsersJson.map((jsonStr) {
        try {
          return Map<String, dynamic>.from(jsonDecode(jsonStr));
        } catch (e) {
          return <String, dynamic>{};
        }
      }).toList();

      final sellerExists = followedUsers.any(
        (user) =>
            (user['seller_id'] ?? user['username'] ?? user['id']?.toString()) ==
                widget.sellerId ||
            (user['username'] ?? user['id']?.toString()) == widget.sellerName,
      );

      if (!sellerExists) {
        // Create seller entry with both username formats for compatibility
        final usernameForStorage = _sellerInfo?['username'] ?? widget.sellerId;
        final sellerEntry = {
          'id': widget.sellerId,
          'username': usernameForStorage,
          'name': widget.sellerName,
          'bio': _sellerInfo?['bio'] ?? AppLocalizations.of(context)!.seller,
          'avatar': null,
          'avatar_url': null,
          'is_seller': true,
          'isBusiness': true,
          'seller_id': widget.sellerId,
          'product_count': _sellerInfo?['totalProducts'] ?? 0,
          'isVerified': false,
          'followed_since': DateTime.now().toIso8601String(),
        };

        followedUsers.add(sellerEntry);
        print(
          '✅ SellerProfileModal: Added seller to list. Total followed: ${followedUsers.length}',
        );
        print(
          '📦 SellerProfileModal: Seller entry: ${sellerEntry['username']}',
        );

        // Save back to SharedPreferences
        final updatedJson = followedUsers
            .map((user) => jsonEncode(user))
            .toList();
        await prefs.setStringList('followed_users', updatedJson);
        print(
          '💾 SellerProfileModal: Saved ${updatedJson.length} users to SharedPreferences',
        );

        // Immediately notify parent to update the UI
        if (widget.onFollowChanged != null) {
          print('📢 SellerProfileModal: Calling onFollowChanged callback');
          widget.onFollowChanged!();
        } else {
          print('⚠️ SellerProfileModal: onFollowChanged callback is null!');
        }
      } else {
        print('⚠️ SellerProfileModal: Seller already exists in followed list');
      }
    } catch (e) {
      // Handle error silently or show user-friendly message if needed
    }
  }

  Future<void> _removeFromFollowedUsers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final followedUsersJson = prefs.getStringList('followed_users') ?? [];

      // Remove seller from the list
      final followedUsers = followedUsersJson.map((jsonStr) {
        try {
          return Map<String, dynamic>.from(jsonDecode(jsonStr));
        } catch (e) {
          return <String, dynamic>{};
        }
      }).toList();

      followedUsers.removeWhere(
        (user) =>
            (user['seller_id'] ?? user['username'] ?? user['id']?.toString()) ==
                widget.sellerId ||
            (user['username'] ?? user['id']?.toString()) == widget.sellerName,
      );

      // Save back to SharedPreferences
      final updatedJson = followedUsers
          .map((user) => jsonEncode(user))
          .toList();
      await prefs.setStringList('followed_users', updatedJson);

      // Immediately notify parent to update the UI
      if (widget.onFollowChanged != null) {
        widget.onFollowChanged!();
      }
    } catch (e) {
      // Handle error silently or show user-friendly message if needed
    }
  }

  Future<void> _followUserOnServer() async {
    try {
      // Use the actual username from seller info if available, otherwise use sellerId
      final usernameToFollow = _sellerInfo?['username'] ?? widget.sellerId;
      final response = await ApiService.followUser(usernameToFollow);

      if (response['success'] != true) {
        // Optionally handle server errors - could show user message or retry logic
      }
    } catch (e) {
      // Handle server errors silently or implement retry logic
    }
  }

  Future<void> _unfollowUserOnServer() async {
    try {
      // Use the actual username from seller info if available, otherwise use sellerId
      final usernameToUnfollow = _sellerInfo?['username'] ?? widget.sellerId;
      final response = await ApiService.unfollowUser(usernameToUnfollow);

      if (response['success'] != true) {
        // Optionally handle server errors - could show user message or retry logic
      }
    } catch (e) {
      // Handle server errors silently or implement retry logic
    }
  }

  void _openChat() {
    if (!ApiService.isLoggedIn) {
      TopNotification.error(context, AppLocalizations.of(context)!.pleaseLoginToChat);
      return;
    }

    // Close seller profile and open chat with seller
    Navigator.of(context).pop();

    // If callback is provided, use it to switch to message page and open chat
    if (widget.onStartChat != null) {
      widget.onStartChat!(widget.sellerId, widget.sellerName);
      return;
    }

    // Fallback: Open chat modal directly (but this won't navigate to message page)
    final isDark = Theme.of(context).brightness == Brightness.dark;

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      maxHeight: MediaQuery.of(context).size.height * 0.94,
      child: ChatModal(
        partnerId: widget.sellerId,
        partnerName: widget.sellerName,
        isDark: isDark,
      ),
    );
  }

  Future<void> _loadSellerProfile() async {
    try {
      print('🔍 DEBUG: Loading seller profile for: ${widget.sellerId}');

      // PRIORITY 1: Try to get user profile from users table
      try {
        final userProfile = await ApiService.getUserByUsername(widget.sellerId);
        if (userProfile != null && userProfile['success'] == true) {
          print('🔍 DEBUG: User profile loaded from users table');
          final user = userProfile['user'];

          // Save user info temporarily
          Map<String, dynamic> tempUserInfo = {
            'username': user['username'] ?? widget.sellerName,
            'profilePic': user['profilePic'], // Profilbild aus users Tabelle
            'isBusiness': user['isBusiness'] ?? false,
            'businessName': user['businessName'],
            'createdAt': user['createdAt'],
            'showPhone': user['showPhone'] ?? false,
          };

          print(
            '🔍 DEBUG: Profile picture: ${user['profilePic'] != null ? "Available" : "Not available"}',
          );

          // Now get products to complete the info
          final productsResponse = await ApiService.getProducts();
          if (productsResponse['success'] &&
              productsResponse['products'] != null) {
            final products = productsResponse['products'] as List;
            final sellerProducts = products.where((product) {
              final productUsername = product['username']
                  ?.toString()
                  .toLowerCase();
              final searchId = widget.sellerId.toLowerCase();
              return productUsername == searchId;
            }).toList();

            // Merge user info with product location data
            if (sellerProducts.isNotEmpty) {
              final firstProduct = sellerProducts.first;
              tempUserInfo.addAll({
                'locationCity':
                    firstProduct['locationCity'] ?? firstProduct['city'] ?? '',
                'locationCountry':
                    firstProduct['locationCountry'] ??
                    firstProduct['country'] ??
                    '',
                'locationStreet':
                    firstProduct['locationStreet'] ??
                    firstProduct['address'] ??
                    '',
                'locationZip': firstProduct['locationZip'] ?? '',
                'totalProducts': sellerProducts.length,
                'products': sellerProducts,
                'showLocation': true,
              });
            }
          }

          setState(() {
            _sellerInfo = tempUserInfo;
            _isLoading = false;
          });
          print(
            '🔍 DEBUG: Seller profile loaded with user data and ${tempUserInfo['totalProducts'] ?? 0} products',
          );
          return;
        }
      } catch (e) {
        print(
          '🔍 DEBUG: Could not load user profile, falling back to products: $e',
        );
      }

      // FALLBACK: Try to get seller products first to get real seller data
      final productsResponse = await ApiService.getProducts();
      print(
        '🔍 DEBUG: Products response success: ${productsResponse['success']}',
      );

      if (productsResponse['success'] && productsResponse['products'] != null) {
        final products = productsResponse['products'] as List;
        print('🔍 DEBUG: Total products loaded: ${products.length}');

        // Debug: Print first few products to see structure
        if (products.isNotEmpty) {
          print('🔍 DEBUG: First product structure: ${products.first.keys}');
          print(
            '🔍 DEBUG: First product username: ${products.first['username']}',
          );
          print(
            '🔍 DEBUG: First product seller_id: ${products.first['seller_id']}',
          );
        }

        // Find products by this seller - more flexible matching
        final sellerProducts = products.where((product) {
          final productUsername = product['username']?.toString().toLowerCase();
          final productSellerId = product['seller_id']
              ?.toString()
              .toLowerCase();
          final searchId = widget.sellerId.toLowerCase();
          final searchName = widget.sellerName.toLowerCase();

          return productUsername == searchId ||
              productUsername == searchName ||
              productSellerId == searchId ||
              productSellerId == searchName;
        }).toList();

        print('🔍 DEBUG: Found ${sellerProducts.length} products for seller');
        print(
          '🔍 DEBUG: Searching for: ID=${widget.sellerId}, Name=${widget.sellerName}',
        );

        if (sellerProducts.isNotEmpty) {
          // Get seller info from the first product
          final firstProduct = sellerProducts.first;
          print(
            '🔍 DEBUG: Using product data from: ${firstProduct['username']}',
          );
          print('🔍 DEBUG: Available location fields in product:');
          print('  - locationCity: ${firstProduct['locationCity']}');
          print('  - locationCountry: ${firstProduct['locationCountry']}');
          print('  - locationStreet: ${firstProduct['locationStreet']}');
          print('  - locationZip: ${firstProduct['locationZip']}');
          print('  - city: ${firstProduct['city']}');
          print('  - country: ${firstProduct['country']}');
          print('  - address: ${firstProduct['address']}');
          print('  - businessAddress: ${firstProduct['businessAddress']}');
          print('  - businessCity: ${firstProduct['businessCity']}');
          print('  - businessCountry: ${firstProduct['businessCountry']}');
          print('🔍 DEBUG: All product keys: ${firstProduct.keys.toList()}');

          // Instead of getUserProfile (which gets current user), we need to get specific seller data
          // For now, use product data but respect privacy settings by not showing real contact info
          setState(() {
            _sellerInfo = {
              'username': firstProduct['username'] ?? widget.sellerName,
              'seller_id': firstProduct['seller_id'] ?? widget.sellerId,
              // Try multiple location field combinations
              'locationCity':
                  firstProduct['locationCity'] ??
                  firstProduct['city'] ??
                  firstProduct['businessCity'] ??
                  '',
              'locationCountry':
                  firstProduct['locationCountry'] ??
                  firstProduct['country'] ??
                  firstProduct['businessCountry'] ??
                  '',
              'locationStreet':
                  firstProduct['locationStreet'] ??
                  firstProduct['address'] ??
                  firstProduct['businessAddress'] ??
                  '',
              'locationZip': firstProduct['locationZip'] ?? '',
              'createdAt': firstProduct['created_at'] ?? '',
              'updatedAt': firstProduct['updated_at'] ?? '',
              'email': AppLocalizations.of(context)!.notAvailable,
              'phone': AppLocalizations.of(context)!.notAvailable,
              'showEmail': false, // Privacy: don't show real contact data
              'showPhone': false, // Privacy: don't show real contact data
              'showLocation': true, // Location is usually okay to show
              'totalProducts': sellerProducts.length,
              'products': sellerProducts,
            };
            _isLoading = false;
          });
          print(
            '🔍 DEBUG: Seller info loaded successfully with ${sellerProducts.length} products',
          );
          print('🔍 DEBUG: Final location data:');
          print('  - City: ${_sellerInfo!['locationCity']}');
          print('  - Country: ${_sellerInfo!['locationCountry']}');
          print('  - Street: ${_sellerInfo!['locationStreet']}');
          return;
        } else {
          print('🔍 DEBUG: No products found for this seller');
        }
      }

      // Fallback: create seller info with available data
      setState(() {
        _sellerInfo = {
          'username': widget.sellerName,
          'seller_id': widget.sellerId,
          'locationCity': AppLocalizations.of(context)!.locationNotAvailable,
          'locationCountry': '',
          'email': AppLocalizations.of(context)!.notAvailable,
          'phone': AppLocalizations.of(context)!.notAvailable,
          'showEmail': false,
          'showPhone': false,
          'showLocation': false,
          'totalProducts': 0,
          'products': [],
        };
        _isLoading = false;
      });
      //print('🔍 DEBUG: Using fallback seller info');
    } catch (e) {
      //print('🔍 DEBUG: Error loading seller profile: $e');
      setState(() {
        _sellerInfo = {
          'username': widget.sellerName,
          'seller_id': widget.sellerId,
          'locationCity': AppLocalizations.of(context)!.errorLoadingData,
          'locationCountry': '',
          'email': AppLocalizations.of(context)!.notAvailable,
          'phone': AppLocalizations.of(context)!.notAvailable,
          'showEmail': false,
          'showPhone': false,
          'showLocation': false,
          'totalProducts': 0,
          'products': [],
        };
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
              _buildHeader(isDark),
              Expanded(
                child: _isLoading
                    ? Center(
                        child: CultiooLoadingIndicator(),
                      )
                    : _buildContent(isDark),
              ),
            ],
          );
  }

  ImageProvider? _getProfileImageProvider() {
    final pic = _sellerInfo?['profilePic'];
    if (pic == null || pic.toString().isEmpty || pic.toString() == 'null') return null;
    final picStr = pic.toString();
    if (picStr.startsWith('data:')) {
      try {
        final base64Str = picStr.split(',').last;
        return MemoryImage(base64Decode(base64Str));
      } catch (_) {
        return null;
      }
    }
    if (picStr.startsWith('http://') || picStr.startsWith('https://')) {
      return NetworkImage(picStr);
    }
    return null;
  }

  Widget _buildHeader(bool isDark) {
    final l10n = AppLocalizations.of(context)!;
    final profileImageProvider = _getProfileImageProvider();
    final displayName = (_sellerInfo?['businessName'] != null &&
            _sellerInfo!['businessName'].toString().isNotEmpty)
        ? _sellerInfo!['businessName'].toString()
        : widget.sellerName;
    final username = _sellerInfo?['username']?.toString() ?? widget.sellerId;
    final location = _getSellerLocation();
    final memberSince = _getMemberSince();

    return TradeRepublicCard.transparent(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Profile row
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Avatar
              TradeRepublicCard(
                width: 64,
                height: 64,
                padding: EdgeInsets.zero,
                boxShadow: const [],
                borderRadius: BorderRadius.circular(32),
                backgroundColor: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
                child: ClipOval(
                  child: profileImageProvider != null
                      ? Image(
                          image: profileImageProvider,
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Icon(
                            CupertinoIcons.building_2_fill,
                            color: isDark ? Colors.white54 : Colors.black38,
                            size: 28,
                          ),
                        )
                      : Icon(
                          CupertinoIcons.building_2_fill,
                          color: isDark ? Colors.white54 : Colors.black38,
                          size: 28,
                        ),
                ),
              ),
              const SizedBox(width: 14),
              // Name + meta
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    if (displayName != username)
                      Text(
                        '@$username',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.grey[500] : Colors.grey[500],
                        ),
                      ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(CupertinoIcons.checkmark_seal_fill,
                            size: 13, color: Colors.green[600]),
                        const SizedBox(width: 4),
                        Text(
                          AppLocalizations.of(context)!.verifiedSeller,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.green[600],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Stats row
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _buildStatChip(
                icon: CupertinoIcons.bag_fill,
                value: '${_sellerInfo?['totalProducts'] ?? 0}',
                label: l10n.products0,
                isDark: isDark,
              ),
              if (location != AppLocalizations.of(context)!.locationPrivate &&
                  location != AppLocalizations.of(context)!.locationNotSpecified)
                _buildStatChip(
                  icon: CupertinoIcons.location_fill,
                  value: location,
                  label: '',
                  isDark: isDark,
                ),
              if (memberSince != l10n.unknown && memberSince != l10n.notAvailable)
                _buildStatChip(
                  icon: CupertinoIcons.calendar,
                  value: memberSince,
                  label: '',
                  isDark: isDark,
                ),
            ],
          ),
          const SizedBox(height: 16),
          // Action buttons
          if (ApiService.isLoggedIn)
            Row(
              children: [
                Expanded(
                  child: TradeRepublicButton(
                    label: l10n.message,
                    icon: const Icon(CupertinoIcons.chat_bubble_fill, size: 16),
                    onPressed: _openChat,
                    backgroundColor: const Color(0xFFFF9500),
                    foregroundColor: Colors.white,
                    height: 46,
                    showShadow: false,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TradeRepublicButton(
                    label: _isFollowing ? l10n.done : l10n.follow,
                    icon: Icon(
                      _isFollowing
                          ? CupertinoIcons.checkmark_circle_fill
                          : CupertinoIcons.person_add,
                      size: 16,
                    ),
                    onPressed: _isFollowLoading ? null : _toggleFollow,
                    isLoading: _isFollowLoading,
                    isSecondary: !_isFollowing,
                    backgroundColor: _isFollowing ? Colors.green : null,
                    foregroundColor: _isFollowing
                        ? Colors.white
                        : (isDark ? Colors.white : Colors.black),
                    height: 46,
                    showShadow: false,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildStatChip({
    required IconData icon,
    required String value,
    required String label,
    required bool isDark,
  }) {
    return TradeRepublicCard(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      boxShadow: const [],
      borderRadius: BorderRadius.circular(20),
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: isDark ? Colors.white60 : Colors.black54),
          const SizedBox(width: 5),
          Text(
            label.isNotEmpty ? '$value $label' : value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildContactInfo(isDark),
          const SizedBox(height: 16),
          if (_sellerInfo != null &&
              _sellerInfo!['products'] != null &&
              (_sellerInfo!['products'] as List).isNotEmpty)
            _buildSellerProducts(isDark),
        ],
      ),
    );
  }

  // _buildSellerInfo removed — profile info is now in _buildHeader

  Widget _buildContactInfo(bool isDark) {
    if (_sellerInfo == null) return const SizedBox.shrink();

    final showEmail =
        _sellerInfo!['showEmail'] == true &&
      _sellerInfo!['email'] != AppLocalizations.of(context)!.notAvailable;
    final showPhone =
        _sellerInfo!['showPhone'] == true &&
      _sellerInfo!['phone'] != AppLocalizations.of(context)!.notAvailable;

    if (!showEmail && !showPhone) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context)!.contactInformation,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        const SizedBox(height: 10),
        TradeRepublicCard(
          padding: EdgeInsets.zero,
          boxShadow: const [],
          borderRadius: BorderRadius.circular(16),
          backgroundColor: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
          child: Column(
            children: [
              if (showEmail)
                _buildFlatRow(
                  AppLocalizations.of(context)!.email,
                  _sellerInfo!['email']?.toString() ?? '',
                  CupertinoIcons.mail_solid,
                  isDark,
                  showDivider: showPhone,
                ),
              if (showPhone)
                _buildFlatRow(
                  AppLocalizations.of(context)!.phone,
                  _sellerInfo!['phone']?.toString() ?? '',
                  CupertinoIcons.phone_fill,
                  isDark,
                  showDivider: false,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFlatRow(
    String label,
    String value,
    IconData icon,
    bool isDark, {
    bool showDivider = false,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(icon,
                  size: 16,
                  color: isDark ? Colors.white54 : Colors.black45),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            indent: 44,
            color: isDark
                ? Colors.white.withOpacity(0.08)
                : Colors.black.withOpacity(0.08),
          ),
      ],
    );
  }

  String _getSellerLocation() {
    if (_sellerInfo == null) return AppLocalizations.of(context)!.unknown;

    // Check if location should be shown based on privacy settings
    final showLocation = _sellerInfo!['showLocation'] == true;

    if (!showLocation) {
      return AppLocalizations.of(context)!.locationPrivate;
    }

    final city = _sellerInfo!['locationCity']?.toString();
    final country = _sellerInfo!['locationCountry']?.toString();

    if (city != null &&
        city.isNotEmpty &&
        country != null &&
        country.isNotEmpty) {
      return '$city, $country';
    } else if (city != null && city.isNotEmpty) {
      return city;
    } else if (country != null && country.isNotEmpty) {
      return country;
    }

    return AppLocalizations.of(context)!.locationNotSpecified;
  }

  String _getMemberSince() {
    if (_sellerInfo == null) return AppLocalizations.of(context)!.unknown;

    final createdAt = _sellerInfo!['createdAt']?.toString();
    if (createdAt != null) {
      try {
        final date = DateTime.parse(createdAt);
        final months = [
          'Jan',
          'Feb',
          'Mar',
          'Apr',
          'May',
          'Jun',
          'Jul',
          'Aug',
          'Sep',
          'Oct',
          'Nov',
          'Dec',
        ];
        return '${months[date.month - 1]} ${date.year}';
      } catch (e) {
        return createdAt;
      }
    }

    return AppLocalizations.of(context)!.notAvailable;
  }

  Widget _buildSellerProducts(bool isDark) {
    if (_sellerInfo == null || _sellerInfo!['products'] == null) {
      return const SizedBox.shrink();
    }

    final products = _sellerInfo!['products'] as List;
    if (products.isEmpty) return const SizedBox.shrink();

    final displayedProducts = products.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context)!.productsCount(products.length),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        const SizedBox(height: 10),
        TradeRepublicCard(
          padding: EdgeInsets.zero,
          boxShadow: const [],
          borderRadius: BorderRadius.circular(16),
          backgroundColor: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
          child: Column(
            children: [
              for (int i = 0; i < displayedProducts.length; i++) ...[
                InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    Navigator.of(context).pop();
                    TradeRepublicBottomSheet.show(
                      context: context,
                      showDragHandle: true,
                      child: ProductDetailsModal(product: displayedProducts[i]),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        TradeRepublicCard(
                          width: 40,
                          height: 40,
                          padding: EdgeInsets.zero,
                          boxShadow: const [],
                          borderRadius: BorderRadius.circular(10),
                          backgroundColor: isDark
                              ? Colors.white.withOpacity(0.08)
                              : Colors.black.withOpacity(0.06),
                          child: _buildProductThumb(displayedProducts[i], isDark),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayedProducts[i]['title'] ?? AppLocalizations.of(context)!.unknownProduct,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: isDark ? Colors.white : Colors.black,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (displayedProducts[i]['price'] != null)
                                Text(
                                  '{currencySymbol}${displayedProducts[i]['price']}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isDark
                                        ? Colors.white60
                                        : Colors.black54,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Icon(
                          CupertinoIcons.chevron_right,
                          size: 14,
                          color: isDark ? Colors.white38 : Colors.black26,
                        ),
                      ],
                    ),
                  ),
                ),
                if (i < displayedProducts.length - 1)
                  Divider(
                    height: 1,
                    indent: 68,
                    color: isDark
                        ? Colors.white.withOpacity(0.07)
                        : Colors.black.withOpacity(0.07),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProductThumb(Map<String, dynamic> product, bool isDark) {
    final images = product['images'];
    String? imageUrl;

    if (images is List && images.isNotEmpty) {
      final firstImage = images.first;
      if (firstImage is String) {
        imageUrl = firstImage;
      } else if (firstImage is Map) {
        imageUrl =
            firstImage['image_url']?.toString() ??
            firstImage['imageUrl']?.toString() ??
            firstImage['url']?.toString();
      }
    }

    imageUrl ??=
        product['image_url']?.toString() ??
        product['imageUrl']?.toString() ??
        product['image']?.toString();

    if (imageUrl != null &&
        (imageUrl.trim().isEmpty || imageUrl.trim() == 'null')) {
      imageUrl = null;
    }

    if (imageUrl != null && imageUrl.isNotEmpty) {
      if (imageUrl.startsWith('data:')) {
        try {
          return ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.memory(
              base64Decode(imageUrl.split(',').last),
              fit: BoxFit.cover,
              width: 40,
              height: 40,
              errorBuilder: (_, _, _) => Icon(
                CupertinoIcons.bag,
                size: 18,
                color: isDark ? Colors.white54 : Colors.black38,
              ),
            ),
          );
        } catch (_) {}
      } else if (imageUrl.startsWith('http')) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.network(
            imageUrl,
            fit: BoxFit.cover,
            width: 40,
            height: 40,
            errorBuilder: (_, _, _) => Icon(
              CupertinoIcons.bag,
              size: 18,
              color: isDark ? Colors.white54 : Colors.black38,
            ),
          ),
        );
      }
    }
    return Icon(
      CupertinoIcons.bag,
      size: 18,
      color: isDark ? Colors.white54 : Colors.black38,
    );
  }
}
