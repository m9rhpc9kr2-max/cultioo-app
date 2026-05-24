import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../services/api_service.dart';
import '../services/address_search_service.dart';
import '../services/trade_republic_widgets.dart';
import '../services/app_localizations.dart';
import '../services/cultioo_spinner.dart';

class AddressesModal extends StatefulWidget {
  final String accessToken;

  const AddressesModal({super.key, required this.accessToken});

  @override
  State<AddressesModal> createState() => _AddressesModalState();
}

class _AddressesModalState extends State<AddressesModal> {
  List<Map<String, dynamic>> _addresses = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAddresses();
  }

  Future<void> _loadAddresses() async {
    print('🏠 Starting _loadAddresses...');
    setState(() {
      _isLoading = true;
    });

    try {
      // Use the newer getUserAddresses method which handles token automatically
      final addresses = await ApiService.getUserAddresses();
      print('🏠 Retrieved ${addresses.length} addresses from API');

      setState(() {
        _addresses = addresses;
        _isLoading = false;
      });

      if (addresses.isEmpty) {
        print('ℹ️ No addresses found for user');
      } else {
        print('✅ Successfully loaded addresses:');
        for (int i = 0; i < addresses.length; i++) {
          print('   Address $i: ${addresses[i]}');
        }
      }
    } catch (e) {
      print('❌ Error loading addresses: $e');
      setState(() {
        _addresses = [];
        _isLoading = false;
      });

      // Show error message to user
      if (mounted) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)!.errorLoadingAddresses(e.toString()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        children: [
          // Header
          Row(
            children: [
              Icon(
                CupertinoIcons.location_fill,
                color: isDark ? Colors.white : Colors.black,
                size: 32,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  AppLocalizations.of(context)!.manageAddresses,
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
          const SizedBox(height: 24),

          // Content (scrollable)
          Expanded(
            child: _isLoading
                ? const Center(child: CultiooLoadingIndicator())
                : _addresses.isEmpty
                ? _buildEmptyState(isDark)
                : _buildAddressesList(isDark),
          ),

          // Add Address Button
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: TradeRepublicButton(
              onPressed: _showAddAddressDialog,
              label: AppLocalizations.of(context)!.addNewAddress,
              showShadow: false,
              width: double.infinity,
              height: 50,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(32),
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withOpacity(0.05)
              : Colors.black.withOpacity(0.05),
          borderRadius: BorderRadius.circular(25),
          boxShadow: const [],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.location_slash,
              size: 64,
              color: isDark ? Colors.grey[600] : Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context)!.noAddressesFound,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context)!.addYourFirstAddressToGetStarted,
              style: TextStyle(
                color: isDark ? Colors.grey[500] : Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddressesList(bool isDark) {
    // Sort addresses to show main address first
    final sortedAddresses = List<Map<String, dynamic>>.from(_addresses);
    sortedAddresses.sort((a, b) {
      final aIsMain = a['isSelected'] == 1 || a['isSelected'] == true;
      final bIsMain = b['isSelected'] == 1 || b['isSelected'] == true;

      if (aIsMain && !bIsMain) return -1;
      if (!aIsMain && bIsMain) return 1;
      return 0;
    });

    return ListView.builder(
      itemCount: sortedAddresses.length,
      itemBuilder: (context, index) {
        final address = sortedAddresses[index];
        return _buildAddressCard(address, isDark);
      },
    );
  }

  /// Parse and format address string to be more readable
  String _parseAndFormatAddress(String rawAddress) {
    if (rawAddress == AppLocalizations.of(context)!.noAddress ||
        rawAddress.isEmpty) {
      return rawAddress;
    }

    // Clean up common formatting issues
    String cleaned = rawAddress
        .replaceAll(RegExp(r'\s+'), ' ') // Multiple spaces to single space
        .replaceAll(RegExp(r',\s*,'), ',') // Remove double commas
        .trim();

    // Handle specific patterns from the examples:
    // "eiderstrasse 21, 38120 Braunschweig, Germany"
    // "Germany, Berlin, Unter den Linden 1, 10117"

    // If it starts with a country name, rearrange it
    final l = AppLocalizations.of(context)!;
    final List<String> countryPrefixes = [
      l.countryDE,
      l.countryUS,
      l.countryFR,
      l.countryNL,
      l.countryBE,
      l.countryAT,
      l.countryCH,
      l.countryGB,
      l.countryIT,
      l.countryES,
      l.countryPT,
      l.countryPL,
      l.countryRU,
      l.countrySE,
      l.countryNO,
      l.countryDK,
      l.countryFI,
      l.countryIE,
      l.countryLU,
      l.countryGR,
      l.countryCZ,
      l.countryHU,
      l.countryRO,
      l.countryBG,
      l.countryHR,
      l.countrySK,
      l.countrySI,
      l.countryEE,
      l.countryLV,
      l.countryLT,
      l.countryMT,
      l.countryCY,
      l.countryCA,
      l.countryMX,
    ];
    for (String country in countryPrefixes) {
      if (cleaned.toLowerCase().startsWith(country.toLowerCase())) {
        // Move country to the end
        String withoutCountry = cleaned
            .substring(country.length)
            .replaceFirst(RegExp(r'^,\s*'), '');
        cleaned = '$withoutCountry, $country';
        break;
      }
    }

    return cleaned;
  }

  Widget _buildAddressCard(Map<String, dynamic> address, bool isDark) {
    // Handle different possible field names from API
    final street = address['street'] ?? '';
    final houseNumber = address['house_number'] ?? address['number'] ?? '';
    final zipCode =
        address['zip_code'] ??
        address['postal_code'] ??
        address['zip'] ??
        address['postalCode'] ??
        '';
    final city = address['city'] ?? '';
    final country = address['country'] ?? '';

    // Build full address string for display
    String fullAddress = '';

    // Try to build from structured fields first
    if (street.isNotEmpty) {
      fullAddress = street;
      if (houseNumber.isNotEmpty) {
        fullAddress += ' $houseNumber';
      }
    }
    if (zipCode.isNotEmpty || city.isNotEmpty) {
      if (fullAddress.isNotEmpty) fullAddress += ', ';
      if (zipCode.isNotEmpty) fullAddress += '$zipCode ';
      if (city.isNotEmpty) fullAddress += city;
    }
    if (country.isNotEmpty) {
      if (fullAddress.isNotEmpty) fullAddress += ', ';
      fullAddress += country;
    }

    // If structured fields are empty, use the complete 'address' field directly
    if (fullAddress.isEmpty || fullAddress.trim() == country) {
      final rawAddress =
          address['address'] ?? AppLocalizations.of(context)!.noAddress;
      fullAddress = _parseAndFormatAddress(rawAddress);
    }

    final isSelected =
        address['isSelected'] == 1 || address['isSelected'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isSelected
            ? (isDark
                  ? Colors.blue.withOpacity(0.3)
                  : Colors.blue.withOpacity(0.15))
            : (isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7)),
        borderRadius: BorderRadius.circular(25),
        // Glass effect
        boxShadow: const [],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Main Address Badge (always visible for main address)
                if (isSelected)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Colors.blue, Colors.blueAccent],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(25),
                        boxShadow: const [],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            CupertinoIcons.house_fill,
                            color: Colors.white,
                            size: 16,
                          ),
                          SizedBox(width: 4),
                          Text(
                            AppLocalizations.of(context)!.mainAddress,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                // Display full address
                if (fullAddress.isNotEmpty)
                  Text(
                    fullAddress,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          // Three dots menu button
          TradeRepublicButton(
            icon: Icon(
              CupertinoIcons.ellipsis,
              size: 18,
            ),
            isSecondary: true,
            showShadow: false,
            width: 44,
            height: 44,
            padding: EdgeInsets.zero,
            borderRadius: BorderRadius.circular(25),
            onPressed: () => _showAddressActionsBottomSheet(address, isDark),
          ),
        ],
      ),
    );
  }

  void _handleAddressAction(String action, Map<String, dynamic> address) {
    switch (action) {
      case 'select':
        _selectAddress(address);
        break;
      case 'edit':
        _editAddress(address);
        break;
      case 'delete':
        _deleteAddress(address);
        break;
    }
  }

  void _showAddressActionsBottomSheet(
    Map<String, dynamic> address,
    bool isDark,
  ) {
    final isSelected =
        address['isSelected'] == 1 || address['isSelected'] == true;

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      useRootNavigator: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.map_pin_ellipse,
                  color: isDark ? Colors.white : Colors.black,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context)!.addressActions,
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

          // Action buttons
          if (!isSelected) ...[
            _buildActionButton(
              icon: CupertinoIcons.house_fill,
              title: AppLocalizations.of(context)!.setAsMainAddress,
              subtitle: AppLocalizations.of(
                context,
              )!.makeThisYourDefaultDeliveryAddress,
              onTap: () {
                Navigator.of(context).pop();
                _handleAddressAction('select', address);
              },
              isDark: isDark,
              color: Colors.blue,
            ),
          ],

          _buildActionButton(
            icon: CupertinoIcons.pencil,
            title: AppLocalizations.of(context)!.editAddress,
            subtitle: AppLocalizations.of(context)!.modifyAddressDetails,
            onTap: () {
              Navigator.of(context).pop();
              _handleAddressAction('edit', address);
            },
            isDark: isDark,
            color: Colors.orange,
          ),
          const TradeRepublicDivider(),

          _buildActionButton(
            icon: CupertinoIcons.trash,
            title: AppLocalizations.of(context)!.deleteAddress,
            subtitle: AppLocalizations.of(
              context,
            )!.removeThisAddressPermanently,
            onTap: () {
              Navigator.of(context).pop();
              _handleAddressAction('delete', address);
            },
            isDark: isDark,
            color: Colors.red,
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required bool isDark,
    required Color color,
  }) {
    return TradeRepublicListTile.navigation(
      title: title,
      subtitle: subtitle,
      leading: Icon(icon, color: color, size: 20),
      onTap: onTap,
    );
  }

  Future<void> _selectAddress(Map<String, dynamic> address) async {
    try {
      final addressId = address['id'];
      if (addressId != null) {
        await ApiService.setMainAddress(widget.accessToken, addressId);
        _loadAddresses(); // Reload to show updated selection

        if (mounted) {
          TopNotification.success(
            context,
            AppLocalizations.of(context)!.mainAddressUpdated,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)!.errorSelectingAddress(e.toString()),
        );
      }
    }
  }

  Future<void> _editAddress(Map<String, dynamic> address) async {
    // Show edit dialog with pre-filled values
    final result = await _showAddressDialog(address: address);
    if (result == true) {
      _loadAddresses();
    }
  }

  Future<void> _deleteAddress(Map<String, dynamic> address) async {
    // Show confirmation in bottom sheet
    final confirmed = await TradeRepublicBottomSheet.show<bool>(
      context: context,
      showDragHandle: true,
      useRootNavigator: true,
      maxHeight: 300,
      child: _buildDeleteConfirmationSheet(context),
    );

    if (confirmed == true) {
      try {
        final addressId = address['id'];
        if (addressId != null) {
          await ApiService.deleteAddress(widget.accessToken, addressId);
          _loadAddresses(); // Reload addresses

          if (mounted) {
            TopNotification.success(
              context,
              AppLocalizations.of(context)!.addressDeletedSuccess,
            );
          }
        }
      } catch (e) {
        if (mounted) {
          TopNotification.error(
            context,
            AppLocalizations.of(context)!.errorDeletingAddress(e.toString()),
          );
        }
      }
    }
  }

  Widget _buildDeleteConfirmationSheet(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        Text(
          AppLocalizations.of(context)!.deleteAddress,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        const SizedBox(height: 16),

        Text(
          AppLocalizations.of(context)!.areYouSureYouWantToDeleteThisAddress,
          style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600]),
          textAlign: TextAlign.center,
        ),

        const Spacer(),

        // Action buttons
        Row(
          children: [
            Expanded(
              child: TradeRepublicButton(
                onPressed: () => Navigator.of(context).pop(false),
                label: AppLocalizations.of(context)!.cancel,
                isSecondary: true,
                showShadow: false,
                height: 50,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TradeRepublicButton(
                onPressed: () => Navigator.of(context).pop(true),
                label: AppLocalizations.of(context)!.delete,
                isDestructive: true,
                showShadow: false,
                height: 50,
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showAddAddressDialog() async {
    // Close current modal first
    Navigator.of(context).pop();

    // Small delay to ensure smooth transition
    await Future.delayed(const Duration(milliseconds: 100));

    // Show add address modal
    final result = await TradeRepublicBottomSheet.show<bool>(
      context: context,
      showDragHandle: true,
      useRootNavigator: true,
      child: _buildAddressBottomSheet(),
    );

    // If address was added successfully, show the addresses modal again
    if (result == true) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (context.mounted) {
        TradeRepublicBottomSheet.show(
          context: context,
          showDragHandle: true,
          useRootNavigator: true,
          child: AddressesModal(accessToken: widget.accessToken),
        );
      }
    }
  }

  Future<bool?> _showAddressDialog({Map<String, dynamic>? address}) async {
    final result = await TradeRepublicBottomSheet.show<bool>(
      context: context,
      showDragHandle: true,
      useRootNavigator: true,
      child: _buildAddressBottomSheet(address: address),
    );
    return result;
  }

  Widget _buildAddressBottomSheet({Map<String, dynamic>? address}) {
    return _AddressFormBottomSheet(
      address: address,
      accessToken: widget.accessToken,
    );
  }
}

class _AddressFormBottomSheet extends StatefulWidget {
  final Map<String, dynamic>? address;
  final String accessToken;

  const _AddressFormBottomSheet({this.address, required this.accessToken});

  @override
  State<_AddressFormBottomSheet> createState() =>
      _AddressFormBottomSheetState();
}

class _AddressFormBottomSheetState extends State<_AddressFormBottomSheet> {
  late final TextEditingController streetController;
  late final TextEditingController houseNumberController;
  late final TextEditingController postalCodeController;
  late final TextEditingController cityController;
  late final TextEditingController countryController;
  late bool isMainAddress;
  double? _latitude;
  double? _longitude;
  String _selectedCountry = '';
  bool _initialized = false;
  bool _isGeocoding = false;

  @override
  void initState() {
    super.initState();
    final isEditing = widget.address != null;

    // Initialize controllers with individual address components
    streetController = TextEditingController(
      text: isEditing ? (widget.address!['street'] ?? '') : '',
    );
    houseNumberController = TextEditingController(
      text: isEditing
          ? (widget.address!['house_number'] ?? widget.address!['number'] ?? '')
          : '',
    );
    postalCodeController = TextEditingController(
      text: isEditing
          ? (widget.address!['zip_code'] ??
                widget.address!['postal_code'] ??
                widget.address!['zip'] ??
                widget.address!['postalCode'] ??
                '')
          : '',
    );
    cityController = TextEditingController(
      text: isEditing ? (widget.address!['city'] ?? '') : '',
    );
    countryController = TextEditingController(
      text: isEditing ? (widget.address!['country'] ?? '') : '',
    );
    _selectedCountry = isEditing ? (widget.address!['country'] ?? '') : '';
    _latitude = (widget.address?['lat'] as num?)?.toDouble();
    _longitude = (widget.address?['lng'] as num?)?.toDouble();
    isMainAddress = isEditing
        ? (widget.address!['isSelected'] == 1 ||
              widget.address!['isSelected'] == true)
        : false;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      final isEditing = widget.address != null;
      if (!isEditing || _selectedCountry.isEmpty) {
        final localizedCountry = AppLocalizations.of(context)!.countryUS;
        if (countryController.text.isEmpty) {
          countryController.text = localizedCountry;
        }
        if (_selectedCountry.isEmpty) {
          _selectedCountry = localizedCountry;
        }
      }
    }
  }

  @override
  void dispose() {
    streetController.dispose();
    houseNumberController.dispose();
    postalCodeController.dispose();
    cityController.dispose();
    countryController.dispose();
    super.dispose();
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required bool isDark,
    TextInputType? keyboardType,
  }) {
    return TradeRepublicTextField(
      controller: controller,
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, color: isDark ? Colors.white70 : Colors.black54),
      keyboardType: keyboardType,
    );
  }

  void _showCountrySelector(bool isDark) {
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      useRootNavigator: true,
      child: Column(
        children: [
          Text(
            AppLocalizations.of(context)!.selectCountry,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(height: 24),

          // Country options
          Expanded(
            child: ListView(
              children: [
                _buildCountryOption(
                  '🇺🇸 ${AppLocalizations.of(context)!.countryUS}',
                  AppLocalizations.of(context)!.countryUS,
                ),
                const SizedBox(height: 8),
                _buildCountryOption(
                  '🇨🇦 ${AppLocalizations.of(context)!.countryCA}',
                  AppLocalizations.of(context)!.countryCA,
                ),
                const SizedBox(height: 8),
                _buildCountryOption(
                  '🇲🇽 ${AppLocalizations.of(context)!.countryMX}',
                  AppLocalizations.of(context)!.countryMX,
                ),
                const SizedBox(height: 8),
                _buildCountryOption(
                  '🇩🇪 ${AppLocalizations.of(context)!.countryDE}',
                  AppLocalizations.of(context)!.countryDE,
                ),
                const SizedBox(height: 8),
                _buildCountryOption(
                  '🇦🇹 ${AppLocalizations.of(context)!.countryAT}',
                  AppLocalizations.of(context)!.countryAT,
                ),
                const SizedBox(height: 8),
                _buildCountryOption(
                  '🇨🇭 ${AppLocalizations.of(context)!.countryCH}',
                  AppLocalizations.of(context)!.countryCH,
                ),
                const SizedBox(height: 8),
                _buildCountryOption(
                  '🇬🇧 ${AppLocalizations.of(context)!.countryGB}',
                  AppLocalizations.of(context)!.countryGB,
                ),
                const SizedBox(height: 8),
                _buildCountryOption(
                  '🇫🇷 ${AppLocalizations.of(context)!.countryFR}',
                  AppLocalizations.of(context)!.countryFR,
                ),
                const SizedBox(height: 8),
                _buildCountryOption(
                  '🇮🇹 ${AppLocalizations.of(context)!.countryIT}',
                  AppLocalizations.of(context)!.countryIT,
                ),
                const SizedBox(height: 8),
                _buildCountryOption(
                  '🇪🇸 ${AppLocalizations.of(context)!.countryES}',
                  AppLocalizations.of(context)!.countryES,
                ),
                const SizedBox(height: 8),
                _buildCountryOption(
                  '🇵🇹 ${AppLocalizations.of(context)!.countryPT}',
                  AppLocalizations.of(context)!.countryPT,
                ),
                const SizedBox(height: 8),
                _buildCountryOption(
                  '🇳🇱 ${AppLocalizations.of(context)!.countryNL}',
                  AppLocalizations.of(context)!.countryNL,
                ),
                const SizedBox(height: 8),
                _buildCountryOption(
                  '🇧🇪 ${AppLocalizations.of(context)!.countryBE}',
                  AppLocalizations.of(context)!.countryBE,
                ),
                const SizedBox(height: 8),
                _buildCountryOption(
                  '🇵🇱 ${AppLocalizations.of(context)!.countryPL}',
                  AppLocalizations.of(context)!.countryPL,
                ),
                const SizedBox(height: 8),
                _buildCountryOption(
                  '🇷🇺 ${AppLocalizations.of(context)!.countryRU}',
                  AppLocalizations.of(context)!.countryRU,
                ),
                const SizedBox(height: 8),
                _buildCountryOption(
                  '🇸🇪 ${AppLocalizations.of(context)!.countrySE}',
                  AppLocalizations.of(context)!.countrySE,
                ),
                const SizedBox(height: 8),
                _buildCountryOption(
                  '🇳🇴 ${AppLocalizations.of(context)!.countryNO}',
                  AppLocalizations.of(context)!.countryNO,
                ),
                const SizedBox(height: 8),
                _buildCountryOption(
                  '🇩🇰 ${AppLocalizations.of(context)!.countryDK}',
                  AppLocalizations.of(context)!.countryDK,
                ),
                const SizedBox(height: 8),
                _buildCountryOption(
                  '🇫🇮 ${AppLocalizations.of(context)!.countryFI}',
                  AppLocalizations.of(context)!.countryFI,
                ),
                const SizedBox(height: 8),
                _buildCountryOption(
                  '🇮🇪 ${AppLocalizations.of(context)!.countryIE}',
                  AppLocalizations.of(context)!.countryIE,
                ),
                const SizedBox(height: 8),
                _buildCountryOption(
                  '🇱🇺 ${AppLocalizations.of(context)!.countryLU}',
                  AppLocalizations.of(context)!.countryLU,
                ),
                const SizedBox(height: 8),
                _buildCountryOption(
                  '🇬🇷 ${AppLocalizations.of(context)!.countryGR}',
                  AppLocalizations.of(context)!.countryGR,
                ),
                const SizedBox(height: 8),
                _buildCountryOption(
                  '🇨🇿 ${AppLocalizations.of(context)!.countryCZ}',
                  AppLocalizations.of(context)!.countryCZ,
                ),
                const SizedBox(height: 8),
                _buildCountryOption(
                  '🇭🇺 ${AppLocalizations.of(context)!.countryHU}',
                  AppLocalizations.of(context)!.countryHU,
                ),
                const SizedBox(height: 8),
                _buildCountryOption(
                  '🇷🇴 ${AppLocalizations.of(context)!.countryRO}',
                  AppLocalizations.of(context)!.countryRO,
                ),
                const SizedBox(height: 8),
                _buildCountryOption(
                  '🇧🇬 ${AppLocalizations.of(context)!.countryBG}',
                  AppLocalizations.of(context)!.countryBG,
                ),
                const SizedBox(height: 8),
                _buildCountryOption(
                  '🇭🇷 ${AppLocalizations.of(context)!.countryHR}',
                  AppLocalizations.of(context)!.countryHR,
                ),
                const SizedBox(height: 8),
                _buildCountryOption(
                  '🇸🇰 ${AppLocalizations.of(context)!.countrySK}',
                  AppLocalizations.of(context)!.countrySK,
                ),
                const SizedBox(height: 8),
                _buildCountryOption(
                  '🇸🇮 ${AppLocalizations.of(context)!.countrySI}',
                  AppLocalizations.of(context)!.countrySI,
                ),
                const SizedBox(height: 8),
                _buildCountryOption(
                  '🇪🇪 ${AppLocalizations.of(context)!.countryEE}',
                  AppLocalizations.of(context)!.countryEE,
                ),
                const SizedBox(height: 8),
                _buildCountryOption(
                  '🇱🇻 ${AppLocalizations.of(context)!.countryLV}',
                  AppLocalizations.of(context)!.countryLV,
                ),
                const SizedBox(height: 8),
                _buildCountryOption(
                  '🇱🇹 ${AppLocalizations.of(context)!.countryLT}',
                  AppLocalizations.of(context)!.countryLT,
                ),
                const SizedBox(height: 8),
                _buildCountryOption(
                  '🇲🇹 ${AppLocalizations.of(context)!.countryMT}',
                  AppLocalizations.of(context)!.countryMT,
                ),
                const SizedBox(height: 8),
                _buildCountryOption(
                  '🇨🇾 ${AppLocalizations.of(context)!.countryCY}',
                  AppLocalizations.of(context)!.countryCY,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCountryOption(String label, String value) {
    final isSelected = _selectedCountry == value;

    return TradeRepublicListTile(
      title: label,
      backgroundColor: isSelected
          ? TradeRepublicTheme.selectionContainerBackground(context)
          : null,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      trailing: isSelected
          ? Icon(
              CupertinoIcons.checkmark_circle_fill,
              color: TradeRepublicTheme.selectionContainerForeground(context),
              size: 20,
            )
          : null,
      onTap: () {
        setState(() {
          _selectedCountry = value;
          countryController.text = value;
        });
        Navigator.of(context).pop();
      },
    );
  }

  String _countryToEnglish(String country) {
    final c = country.trim();
    if (c.isEmpty) return c;

    final l = AppLocalizations.of(context)!;
    final map = <String, String>{
      l.countryUS: 'United States',
      l.countryCA: 'Canada',
      l.countryMX: 'Mexico',
      l.countryDE: 'Germany',
      l.countryAT: 'Austria',
      l.countryCH: 'Switzerland',
      l.countryGB: 'United Kingdom',
      l.countryFR: 'France',
      l.countryIT: 'Italy',
      l.countryES: 'Spain',
      l.countryPT: 'Portugal',
      l.countryNL: 'Netherlands',
      l.countryBE: 'Belgium',
      l.countryPL: 'Poland',
      l.countryRU: 'Russia',
      l.countrySE: 'Sweden',
      l.countryNO: 'Norway',
      l.countryDK: 'Denmark',
      l.countryFI: 'Finland',
      l.countryIE: 'Ireland',
      l.countryLU: 'Luxembourg',
      l.countryGR: 'Greece',
      l.countryCZ: 'Czech Republic',
      l.countryHU: 'Hungary',
      l.countryRO: 'Romania',
      l.countryBG: 'Bulgaria',
      l.countryHR: 'Croatia',
      l.countrySK: 'Slovakia',
      l.countrySI: 'Slovenia',
      l.countryEE: 'Estonia',
      l.countryLV: 'Latvia',
      l.countryLT: 'Lithuania',
      l.countryMT: 'Malta',
      l.countryCY: 'Cyprus',
    };

    return map[c] ?? c;
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.address != null;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: Column(
        children: [
          // Header
          Text(
            isEditing
                ? AppLocalizations.of(context)!.editAddress
                : AppLocalizations.of(context)!.addNewAddress,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(height: 24),

          // Form fields
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Street
                  _buildTextField(
                    controller: streetController,
                    label: AppLocalizations.of(context)!.street,
                    hint: 'e.g. Congress Ave',
                    icon: CupertinoIcons.house,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 16),

                  // House Number
                  _buildTextField(
                    controller: houseNumberController,
                    label: AppLocalizations.of(context)!.houseNumber,
                    hint: 'e.g. 123',
                    icon: CupertinoIcons.textformat_123,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 16),

                  // Postal Code and City in Row
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: _buildTextField(
                          controller: postalCodeController,
                          label: AppLocalizations.of(context)!.postalCode,
                          hint: 'e.g. 78701',
                          icon: CupertinoIcons.envelope,
                          isDark: isDark,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 3,
                        child: _buildTextField(
                          controller: cityController,
                          label: AppLocalizations.of(context)!.city,
                          hint: 'e.g. Austin',
                          icon: CupertinoIcons.building_2_fill,
                          isDark: isDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Country Selector
                  TradeRepublicListTile.navigation(
                    title: _selectedCountry,
                    subtitle: AppLocalizations.of(context)!.country,
                    leading: Icon(
                      CupertinoIcons.globe,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                    onTap: () => _showCountrySelector(isDark),
                  ),
                  const SizedBox(height: 24),

                  // Main address toggle
                  TradeRepublicListTile.toggle(
                    title: AppLocalizations.of(context)!.setAsMainAddress1,
                    subtitle: AppLocalizations.of(context)!.thisWillBeYourDefaultDeliveryAddress,
                    leading: Icon(
                      CupertinoIcons.house_fill,
                      color: isMainAddress ? Colors.blue : (isDark ? Colors.grey[400] : Colors.grey[600]),
                    ),
                    value: isMainAddress,
                    onChanged: (_) {
                      setState(() {
                        isMainAddress = !isMainAddress;
                      });
                    },
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),

          // Action button
          TradeRepublicButton(
            width: double.infinity,
            height: 50,
            showShadow: false,
            onPressed: _isGeocoding ? null : () async {
              try {
                final street = streetController.text.trim();
                final houseNumber = houseNumberController.text.trim();
                final postalCode = postalCodeController.text.trim();
                final city = cityController.text.trim();
                final country = _countryToEnglish(_selectedCountry);

                if (street.isEmpty || city.isEmpty) {
                  TopNotification.error(
                    context,
                    AppLocalizations.of(context)!.enterStreetAndCity,
                  );
                  return;
                }

                // Build full address string
                String fullAddress = street;
                if (houseNumber.isNotEmpty) fullAddress += ' $houseNumber';
                if (postalCode.isNotEmpty) fullAddress += ', $postalCode';
                if (city.isNotEmpty) fullAddress += ' $city';
                if (country.isNotEmpty) fullAddress += ', $country';

                // Geocode with multiple fallback queries
                double? lat = _latitude;
                double? lng = _longitude;

                if (lat == null || lng == null) {
                  setState(() => _isGeocoding = true);
                  final queries = [
                    if (street.isNotEmpty && postalCode.isNotEmpty && city.isNotEmpty)
                      '$street $houseNumber, $postalCode $city, $country',
                    if (postalCode.isNotEmpty && city.isNotEmpty)
                      '$postalCode $city, $country',
                    if (city.isNotEmpty && country.isNotEmpty)
                      '$city, $country',
                  ];
                  for (final q in queries) {
                    try {
                      final results = await AddressSearchService.searchAddresses(q);
                      if (results.isNotEmpty) {
                        lat = results.first.lat;
                        lng = results.first.lng;
                        break;
                      }
                    } catch (_) {}
                  }
                  setState(() => _isGeocoding = false);
                }

                if (lat == null || lng == null) {
                  TopNotification.error(
                    context,
                    'Address coordinates could not be determined. Please refine street/zip/city and try again.',
                  );
                  return;
                }

                final addressId = widget.address?['id'];
                if (isEditing && addressId != null) {
                  await ApiService.updateAddress(
                    widget.accessToken,
                    addressId is int ? addressId : int.parse(addressId.toString()),
                    fullAddress,
                    country.isNotEmpty ? country : null,
                    isMainAddress,
                    lat: lat,
                    lng: lng,
                    street: street,
                    houseNumber: houseNumber.isNotEmpty ? houseNumber : null,
                    zipCode: postalCode.isNotEmpty ? postalCode : null,
                    city: city,
                  );
                } else {
                  await ApiService.addAddress(
                    widget.accessToken,
                    fullAddress,
                    country.isNotEmpty ? country : null,
                    isMainAddress,
                    lat: lat,
                    lng: lng,
                    street: street,
                    houseNumber: houseNumber.isNotEmpty ? houseNumber : null,
                    zipCode: postalCode.isNotEmpty ? postalCode : null,
                    city: city,
                  );
                }

                if (mounted) {
                  Navigator.of(context).pop(true);
                }
              } catch (e) {
                if (mounted) {
                  setState(() => _isGeocoding = false);
                  TopNotification.error(
                    context,
                    AppLocalizations.of(context)!.errorGeneric(e.toString()),
                  );
                }
              }
            },
            label: _isGeocoding
                ? 'Locating…'
                : (isEditing
                    ? AppLocalizations.of(context)!.updateAddress
                    : AppLocalizations.of(context)!.addAddress),
          ),
        ],
      ),
      ),
    );
  }
}
