import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import '../services/api_service.dart';
import '../services/trade_republic_widgets.dart';

import '../main.dart';
import '../services/app_localizations.dart';

class ProfileEditModal extends StatefulWidget {
  final String accessToken;
  final Map<String, dynamic> userData;

  const ProfileEditModal({
    super.key,
    required this.accessToken,
    required this.userData,
  });

  @override
  State<ProfileEditModal> createState() => _ProfileEditModalState();
}

class _ProfileEditModalState extends State<ProfileEditModal>
    with TickerProviderStateMixin {
  late TextEditingController _usernameController;
  late TextEditingController _firstnameController;
  late TextEditingController _lastnameController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;
  late TextEditingController _streetController;
  late TextEditingController _houseNumberController;
  late TextEditingController _postalCodeController;
  late TextEditingController _cityController;
  late TextEditingController _countryController;
  late TextEditingController _businessNameController;
  late TextEditingController _businessDescriptionController;
  late TextEditingController _businessSizeController;
  late TextEditingController _businessCountryController;

  String _selectedCountryCode = '+49';
  DateTime? _selectedBirthdate;
  bool _isLoading = false;
  String? _profileImage; // base64 data URL

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

  // Static list for phone parsing in initState (no context needed)
  static const List<Map<String, String>> _phoneCodeList = [
    {'code': '+1',   'flag': '��'},
    {'code': '+1',   'flag': '��'},
    {'code': '+52',  'flag': '��'},
    {'code': '+44',  'flag': '��'},
    {'code': '+43',  'flag': '��'},
    {'code': '+32',  'flag': '��'},
    {'code': '+359', 'flag': '��'},
    {'code': '+385', 'flag': '��'},
    {'code': '+357', 'flag': '��'},
    {'code': '+420', 'flag': '��'},
    {'code': '+45',  'flag': '��'},
    {'code': '+372', 'flag': '��'},
    {'code': '+358', 'flag': '��'},
    {'code': '+33',  'flag': '��'},
    {'code': '+49',  'flag': '��'},
    {'code': '+30',  'flag': '��'},
    {'code': '+36',  'flag': '��'},
    {'code': '+353', 'flag': '��'},
    {'code': '+39',  'flag': '🇮🇹'},
    {'code': '+371', 'flag': '��'},
    {'code': '+370', 'flag': '🇱�'},
    {'code': '+352', 'flag': '��'},
    {'code': '+356', 'flag': '��'},
    {'code': '+31',  'flag': '��'},
    {'code': '+47',  'flag': '�🇴'},
    {'code': '+48',  'flag': '��'},
    {'code': '+351', 'flag': '��'},
    {'code': '+40',  'flag': '��'},
    {'code': '+421', 'flag': '🇸�'},
    {'code': '+386', 'flag': '��'},
    {'code': '+34',  'flag': '��'},
    {'code': '+46',  'flag': '��'},
    {'code': '+41',  'flag': '��'},
    {'code': '+7',   'flag': '��'},
  ];

  // Localized list for UI display (needs context)
  List<Map<String, String>> _getCountryCodes(BuildContext ctx) {
    final l = AppLocalizations.of(ctx)!;
    return [
      {'code': '+1',   'country': l.countryUS, 'flag': '��'},
      {'code': '+1',   'country': l.countryCA, 'flag': '��'},
      {'code': '+52',  'country': l.countryMX, 'flag': '��'},
      {'code': '+44',  'country': l.countryGB, 'flag': '��'},
      {'code': '+43',  'country': l.countryAT, 'flag': '��'},
      {'code': '+32',  'country': l.countryBE, 'flag': '��'},
      {'code': '+359', 'country': l.countryBG, 'flag': '��'},
      {'code': '+385', 'country': l.countryHR, 'flag': '��'},
      {'code': '+357', 'country': l.countryCY, 'flag': '��'},
      {'code': '+420', 'country': l.countryCZ, 'flag': '��'},
      {'code': '+45',  'country': l.countryDK, 'flag': '��'},
      {'code': '+372', 'country': l.countryEE, 'flag': '��'},
      {'code': '+358', 'country': l.countryFI, 'flag': '��'},
      {'code': '+33',  'country': l.countryFR, 'flag': '��'},
      {'code': '+49',  'country': l.countryDE, 'flag': '��'},
      {'code': '+30',  'country': l.countryGR, 'flag': '��'},
      {'code': '+36',  'country': l.countryHU, 'flag': '��'},
      {'code': '+353', 'country': l.countryIE, 'flag': '��'},
      {'code': '+39',  'country': l.countryIT, 'flag': '🇮🇹'},
      {'code': '+371', 'country': l.countryLV, 'flag': '��'},
      {'code': '+370', 'country': l.countryLT, 'flag': '🇱�'},
      {'code': '+352', 'country': l.countryLU, 'flag': '��'},
      {'code': '+356', 'country': l.countryMT, 'flag': '��'},
      {'code': '+31',  'country': l.countryNL, 'flag': '��'},
      {'code': '+47',  'country': l.countryNO, 'flag': '�🇴'},
      {'code': '+48',  'country': l.countryPL, 'flag': '��'},
      {'code': '+351', 'country': l.countryPT, 'flag': '��'},
      {'code': '+40',  'country': l.countryRO, 'flag': '��'},
      {'code': '+421', 'country': l.countrySK, 'flag': '🇸�'},
      {'code': '+386', 'country': l.countrySI, 'flag': '��'},
      {'code': '+34',  'country': l.countryES, 'flag': '��'},
      {'code': '+46',  'country': l.countrySE, 'flag': '��'},
      {'code': '+41',  'country': l.countryCH, 'flag': '��'},
      {'code': '+7',   'country': l.countryRU, 'flag': '��'},
    ];
  }

  // Only field animations - no modal opening animations
  late List<AnimationController> _fieldControllers;
  late List<Animation<Offset>> _fieldSlideAnimations;
  late List<Animation<double>> _fieldOpacityAnimations;

  @override
  void initState() {
    super.initState();
    _initializeControllers();
    _initializeFieldAnimations();
    _startFieldAnimations();
  }

  void _initializeControllers() {
    final userData = widget.userData;
    _profileImage = userData['profilePic'] as String? ?? userData['profile_image'] as String?;

    // Username handling
    _usernameController = TextEditingController(
      text: userData['username'] ?? '',
    );

    // Name parsing - check multiple possible field names
    String fullName = userData['name'] ?? '';
    String firstName = userData['firstname'] ?? userData['first_name'] ?? '';
    String lastName = userData['lastname'] ?? userData['last_name'] ?? '';

    // If we have a full name but no separate first/last names, try to split it
    if (fullName.isNotEmpty && firstName.isEmpty && lastName.isEmpty) {
      List<String> nameParts = fullName.split(' ');
      if (nameParts.length >= 2) {
        firstName = nameParts.first;
        lastName = nameParts.sublist(1).join(' ');
      } else if (nameParts.length == 1) {
        firstName = nameParts.first;
      }
    }

    _firstnameController = TextEditingController(text: firstName);
    _lastnameController = TextEditingController(text: lastName);
    _emailController = TextEditingController(text: userData['email'] ?? '');

    _streetController = TextEditingController(
      text: userData['street']?.toString() ?? '',
    );
    _houseNumberController = TextEditingController(
      text:
          userData['house_number']?.toString() ??
          userData['houseNumber']?.toString() ??
          '',
    );
    _postalCodeController = TextEditingController(
      text:
          userData['postal_code']?.toString() ??
          userData['postalCode']?.toString() ??
          '',
    );
    _cityController = TextEditingController(
      text: userData['city']?.toString() ?? '',
    );
    _countryController = TextEditingController(
      text:
          userData['country']?.toString() ??
          userData['business_country']?.toString() ??
          '',
    );

    _businessNameController = TextEditingController(
      text:
          userData['businessName']?.toString() ??
          userData['business_company']?.toString() ??
          '',
    );
    _businessDescriptionController = TextEditingController(
      text: userData['businessDescription']?.toString() ?? '',
    );
    _businessSizeController = TextEditingController(
      text: userData['business_size']?.toString() ?? '',
    );
    _businessCountryController = TextEditingController(
      text:
          userData['business_country']?.toString() ??
          userData['country']?.toString() ??
          '',
    );

    // Phone parsing
    String fullPhone = userData['phone'] ?? '';
    if (fullPhone.isNotEmpty) {
      for (var country in _phoneCodeList) {
        if (fullPhone.startsWith(country['code']!)) {
          _selectedCountryCode = country['code']!;
          _phoneController = TextEditingController(
            text: fullPhone.substring(country['code']!.length),
          );
          break;
        }
      }
    } else {
      _phoneController = TextEditingController();
    }

    // Birthdate parsing
    if (userData['birthdate'] != null) {
      _selectedBirthdate = DateTime.tryParse(userData['birthdate']);
    }
  }

  void _initializeFieldAnimations() {
    // Create field animations for all profile fields shown in this modal.
    _fieldControllers = List.generate(
      15,
      (index) => AnimationController(
        duration: Duration(milliseconds: 400 + (index * 100)),
        vsync: this,
      ),
    );

    _fieldSlideAnimations = _fieldControllers
        .map(
          (controller) =>
              Tween<Offset>(
                begin: const Offset(0, 0.2),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(parent: controller, curve: Curves.easeOutCubic),
              ),
        )
        .toList();

    _fieldOpacityAnimations = _fieldControllers
        .map(
          (controller) => Tween<double>(
            begin: 0.0,
            end: 1.0,
          ).animate(CurvedAnimation(parent: controller, curve: Curves.easeOut)),
        )
        .toList();
  }

  void _startFieldAnimations() {
    // Stagger field animations
    for (int i = 0; i < _fieldControllers.length; i++) {
      Future.delayed(Duration(milliseconds: i * 80), () {
        if (mounted) _fieldControllers[i].forward();
      });
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _firstnameController.dispose();
    _lastnameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _streetController.dispose();
    _houseNumberController.dispose();
    _postalCodeController.dispose();
    _cityController.dispose();
    _countryController.dispose();
    _businessNameController.dispose();
    _businessDescriptionController.dispose();
    _businessSizeController.dispose();
    _businessCountryController.dispose();
    for (var controller in _fieldControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _selectBirthdate() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    DateTime tempDate = _selectedBirthdate ?? DateTime(2000);

    await TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      maxHeight: 300,
      child: Builder(
        builder: (context) {
          return Column(
            children: [
              // Header with Done button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.selectBirthdate,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    TradeRepublicButton(
                      label: AppLocalizations.of(context)!.done,
                      onPressed: () {
                        setState(() {
                          _selectedBirthdate = tempDate;
                        });
                        Navigator.pop(context);
                      },
                      isSecondary: true,
                    ),
                  ],
                ),
              ),

              // Date Picker
              Expanded(
                child: CupertinoTheme(
                  data: CupertinoThemeData(
                    brightness: isDark ? Brightness.dark : Brightness.light,
                    textTheme: CupertinoTextThemeData(
                      dateTimePickerTextStyle: TextStyle(
                        color: isDark ? Colors.white : Colors.black,
                        fontSize: 22,
                      ),
                    ),
                  ),
                  child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.date,
                    initialDateTime: tempDate,
                    minimumYear: 1900,
                    maximumDate: DateTime.now(),
                    onDateTimeChanged: (DateTime newDate) {
                      tempDate = newDate;
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showCountryCodeSelector() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      maxHeight: MediaQuery.of(context).size.height * 0.6,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text(
                  AppLocalizations.of(context)!.selectCountryCode,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Country list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _getCountryCodes(context).length,
              itemBuilder: (context, index) {
                final country = _getCountryCodes(context)[index];
                final isSelected = country['code'] == _selectedCountryCode;

                final selBg =
                    TradeRepublicTheme.selectionContainerBackground(context);
                final selFg =
                    TradeRepublicTheme.selectionContainerForeground(context);
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? selBg : Colors.transparent,
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: ListTile(
                    onTap: () {
                      setState(() {
                        _selectedCountryCode = country['code']!;
                      });
                      Navigator.pop(context);
                    },
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: Text(
                      country['flag']!,
                      style: const TextStyle(fontSize: 28),
                    ),
                    title: Text(
                      country['country']!,
                      style: TextStyle(
                        color: isSelected
                            ? selFg
                            : (isDark ? Colors.white : Colors.black),
                        fontSize: 16,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                    trailing: Text(
                      country['code']!,
                      style: TextStyle(
                        color: isSelected
                            ? selFg
                            : (isDark ? Colors.grey[400] : Colors.grey[600]),
                        fontSize: 16,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _showCountrySelector() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final countries = [
      'Germany', 'Austria', 'Switzerland', 'Netherlands', 'Belgium', 'Luxembourg',
      'France', 'Spain', 'Italy', 'Portugal', 'Greece', 'Poland', 'Czech Republic',
      'Hungary', 'Romania', 'Bulgaria', 'Croatia', 'Slovakia', 'Slovenia', 'Estonia',
      'Latvia', 'Lithuania', 'Malta', 'Cyprus', 'Sweden', 'Norway', 'Denmark',
      'Finland', 'Ireland', 'United Kingdom', 'United States', 'Canada', 'Mexico',
      'Russia', 'Ukraine', 'Other'
    ]..sort();

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      maxHeight: MediaQuery.of(context).size.height * 0.6,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Select Country',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: countries.length,
              itemBuilder: (context, index) {
                final country = countries[index];
                final isSelected = _countryController.text == country;
                final selBg =
                    TradeRepublicTheme.selectionContainerBackground(context);
                final selFg =
                    TradeRepublicTheme.selectionContainerForeground(context);
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? selBg : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    onTap: () {
                      setState(() {
                        _countryController.text = country;
                      });
                      Navigator.pop(context);
                    },
                    title: Text(
                      country,
                      style: TextStyle(
                        color: isSelected
                            ? selFg
                            : (isDark ? Colors.white : Colors.black),
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _showBusinessSizeSelector() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sizes = ['Self-employed', '1-10', '11-50', '51-200', '201-500', '501-1000', '1001+'];

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      maxHeight: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Select Business Size',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: sizes.length,
              itemBuilder: (context, index) {
                final size = sizes[index];
                final isSelected = _businessSizeController.text == size;
                final selBg =
                    TradeRepublicTheme.selectionContainerBackground(context);
                final selFg =
                    TradeRepublicTheme.selectionContainerForeground(context);
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? selBg : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    onTap: () {
                      setState(() {
                        _businessSizeController.text = size;
                      });
                      Navigator.pop(context);
                    },
                    title: Text(
                      size,
                      style: TextStyle(
                        color: isSelected
                            ? selFg
                            : (isDark ? Colors.white : Colors.black),
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _saveProfile() async {
    if (_isLoading) return;

    // Basic validation
    if (_usernameController.text.trim().isEmpty ||
        _firstnameController.text.trim().isEmpty ||
        _lastnameController.text.trim().isEmpty ||
        _emailController.text.trim().isEmpty) {
      _showErrorSnackBar(AppLocalizations.of(context)!.pleaseFillInAllFields);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await ApiService.updateUserProfile(
        username: _usernameController.text.trim(),
        name:
            '${_firstnameController.text.trim()} ${_lastnameController.text.trim()}',
        email: _emailController.text.trim(),
        phone: _selectedCountryCode + _phoneController.text.trim(),
        birthdate: _selectedBirthdate?.toIso8601String().split('T')[0],
        address: _buildComposedAddress(),
        street: _streetController.text.trim().isEmpty
          ? null
          : _streetController.text.trim(),
        houseNumber: _houseNumberController.text.trim().isEmpty
          ? null
          : _houseNumberController.text.trim(),
        postalCode: _postalCodeController.text.trim().isEmpty
          ? null
          : _postalCodeController.text.trim(),
        city: _cityController.text.trim().isEmpty
          ? null
          : _cityController.text.trim(),
        country: _countryController.text.trim().isEmpty
          ? null
          : _countryController.text.trim(),
        businessName: _businessNameController.text.trim().isEmpty
          ? null
          : _businessNameController.text.trim(),
        businessDescription: _businessDescriptionController.text.trim().isEmpty
          ? null
          : _businessDescriptionController.text.trim(),
        businessSize: _businessSizeController.text.trim().isEmpty
          ? null
          : _businessSizeController.text.trim(),
        businessCountry: _businessCountryController.text.trim().isEmpty
          ? null
          : _businessCountryController.text.trim(),
        profileImage: _profileImage,
      );

      if (mounted) {
        // Return updated user data
        final updatedUserData = {
          'name':
              '${_firstnameController.text.trim()} ${_lastnameController.text.trim()}',
          'email': _emailController.text.trim(),
          'phone': _selectedCountryCode + _phoneController.text.trim(),
          'birthdate': _selectedBirthdate?.toIso8601String().split('T')[0],
          'address': _buildComposedAddress(),
          'street': _streetController.text.trim(),
          'house_number': _houseNumberController.text.trim(),
          'postal_code': _postalCodeController.text.trim(),
          'city': _cityController.text.trim(),
          'country': _countryController.text.trim(),
          'businessName': _businessNameController.text.trim(),
          'businessDescription': _businessDescriptionController.text.trim(),
          'business_size': _businessSizeController.text.trim(),
          'business_country': _businessCountryController.text.trim(),
        };

        //print('🔍 Edit Profile returning data: $updatedUserData');

        Navigator.of(context).pop(updatedUserData); // Return updated data
        TopNotification.success(
          context,
          AppLocalizations.of(context)!.profileUpdatedSuccess,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _showErrorSnackBar(
          AppLocalizations.of(context)!.failedToUpdateProfile(e.toString()),
        );
      }
    }
  }

  void _showErrorSnackBar(String message) {
    TopNotification.error(context, message);
  }

  String? _buildComposedAddress() {
    final parts = <String>[
      _countryController.text.trim(),
      _cityController.text.trim(),
      [
        _streetController.text.trim(),
        _houseNumberController.text.trim(),
      ].where((v) => v.isNotEmpty).join(' ').trim(),
      _postalCodeController.text.trim(),
    ].where((v) => v.isNotEmpty).toList();

    if (parts.isEmpty) return null;
    return parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
          child: Row(
            children: [
              Icon(
                CupertinoIcons.pencil,
                color: isDark ? Colors.white : Colors.black,
                size: 32,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  AppLocalizations.of(context)!.editProfile,
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

        // Content
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                // Profile image picker
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
                          bytes[4] == 0x66 &&
                          bytes[5] == 0x74 &&
                          bytes[6] == 0x79 &&
                          bytes[7] == 0x70 &&
                          bytes[8] == 0x61 &&
                          bytes[9] == 0x76 &&
                          bytes[10] == 0x69 &&
                          bytes[11] == 0x66;
                      if (isAvif) {
                        _showErrorSnackBar(
                          'Please select JPG or PNG (AVIF is not supported).',
                        );
                        return;
                      }
                      final encoded = _encodeProfileImageForUpload(bytes);
                      if (encoded == null) {
                        _showErrorSnackBar(
                          'Image could not be processed. Please use a smaller JPG/PNG.',
                        );
                        return;
                      }
                      setState(() {
                        _profileImage = encoded;
                      });
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 24),
                    child: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        Builder(builder: (context) {
                          final isDark = Theme.of(context).brightness == Brightness.dark;
                          final hasPhoto = _profileImage != null && _profileImage!.isNotEmpty;
                          return Container(
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
                            child: hasPhoto
                                ? ClipOval(
                                    child: _buildProfileImageWidget(_profileImage!),
                                  )
                                : Icon(
                                    CupertinoIcons.person_fill,
                                    size: 40,
                                    color: isDark
                                        ? Colors.white.withOpacity(0.4)
                                        : Colors.black.withOpacity(0.25),
                                  ),
                          );
                        }),
                        Builder(builder: (context) {
                          final isDark = Theme.of(context).brightness == Brightness.dark;
                          return Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                            child: Icon(
                              CupertinoIcons.camera_fill,
                              size: 14,
                              color: isDark ? Colors.black : Colors.white,
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),

                // Username field
                _buildAnimatedField(
                  0,
                  _buildTextField(
                    controller: _usernameController,
                    label: AppLocalizations.of(context)!.username,
                    icon: CupertinoIcons.person,
                  ),
                ),

                const SizedBox(height: 20),

                // First name field
                _buildAnimatedField(
                  1,
                  _buildTextField(
                    controller: _firstnameController,
                    label: AppLocalizations.of(context)!.firstName,
                    icon: CupertinoIcons.person_crop_square,
                  ),
                ),

                const SizedBox(height: 20),

                // Last name field
                _buildAnimatedField(
                  2,
                  _buildTextField(
                    controller: _lastnameController,
                    label: AppLocalizations.of(context)!.lastName,
                    icon: CupertinoIcons.person_crop_square,
                  ),
                ),

                const SizedBox(height: 20),

                // Email field
                _buildAnimatedField(
                  3,
                  _buildTextField(
                    controller: _emailController,
                    label: AppLocalizations.of(context)!.email,
                    icon: CupertinoIcons.mail,
                    keyboardType: TextInputType.emailAddress,
                  ),
                ),

                const SizedBox(height: 20),

                // Phone field
                _buildAnimatedField(4, _buildPhoneField()),

                const SizedBox(height: 20),

                // Birthdate field
                _buildAnimatedField(5, _buildBirthdateField()),

                const SizedBox(height: 20),

                // Address section
                _buildAnimatedField(
                  6,
                  _buildSectionTitle('Address'),
                ),

                const SizedBox(height: 12),

                _buildAnimatedField(
                  7,
                  _buildTextField(
                    controller: _streetController,
                    label: l10n.street,
                    icon: CupertinoIcons.location,
                  ),
                ),

                const SizedBox(height: 20),

                _buildAnimatedField(
                  8,
                  _buildTextField(
                    controller: _houseNumberController,
                    label: l10n.houseNumber,
                    icon: CupertinoIcons.number,
                  ),
                ),

                const SizedBox(height: 20),

                _buildAnimatedField(
                  9,
                  _buildTextField(
                    controller: _postalCodeController,
                    label: l10n.postalCode,
                    icon: CupertinoIcons.mail_solid,
                  ),
                ),

                const SizedBox(height: 20),

                _buildAnimatedField(
                  10,
                  _buildTextField(
                    controller: _cityController,
                    label: l10n.city,
                    icon: CupertinoIcons.building_2_fill,
                  ),
                ),

                const SizedBox(height: 20),

                _buildAnimatedField(
                  11,
                  _buildSelectionField(
                    label: l10n.country,
                    value: _countryController.text,
                    icon: CupertinoIcons.flag_fill,
                    onTap: _showCountrySelector,
                  ),
                ),

                const SizedBox(height: 20),

                // Business section
                _buildAnimatedField(
                  12,
                  _buildSectionTitle('Business'),
                ),

                const SizedBox(height: 12),

                _buildAnimatedField(
                  13,
                  _buildTextField(
                    controller: _businessNameController,
                    label: l10n.businessName,
                    icon: CupertinoIcons.briefcase_fill,
                  ),
                ),

                const SizedBox(height: 20),

                _buildAnimatedField(
                  14,
                  _buildTextField(
                    controller: _businessDescriptionController,
                    label: l10n.businessDescription,
                    icon: CupertinoIcons.doc_text_fill,
                    maxLines: 3,
                  ),
                ),

                const SizedBox(height: 20),

                _buildSelectionField(
                  label: l10n.businessSize,
                  value: _businessSizeController.text,
                  icon: CupertinoIcons.person_2_fill,
                  onTap: _showBusinessSizeSelector,
                ),

                const SizedBox(height: 20),

                _buildTextField(
                  controller: _businessCountryController,
                  label: l10n.businessCountry,
                  icon: CupertinoIcons.globe,
                ),

                const SizedBox(height: 24),

                // Save button with gradient
                TradeRepublicButton(
                  label: _isLoading
                      ? AppLocalizations.of(context)!.saving
                      : AppLocalizations.of(context)!.saveChanges,
                  onPressed: _isLoading ? null : _saveProfile,
                  isLoading: _isLoading,
                  width: double.infinity,
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAnimatedField(int index, Widget child) {
    return SlideTransition(
      position: _fieldSlideAnimations[index],
      child: FadeTransition(
        opacity: _fieldOpacityAnimations[index],
        child: child,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Force multiline keyboard when maxLines > 1
    final effectiveKeyboardType = maxLines > 1 ? TextInputType.multiline : keyboardType;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: (isDark ? Colors.white : Colors.black).withOpacity(0.7),
          ),
        ),
        const SizedBox(height: 10),
        TradeRepublicTextField(
          controller: controller,
          hintText: label,
          prefixIcon: Icon(
            icon,
            color: (isDark ? Colors.white : Colors.black).withOpacity(0.5),
            size: 20,
          ),
          keyboardType: effectiveKeyboardType,
          maxLines: maxLines,
        ),
      ],
    );
  }

  Widget _buildSelectionField({
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: (isDark ? Colors.white : Colors.black).withOpacity(0.7),
          ),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              color: (isDark ? Colors.white : Colors.black).withOpacity(0.04),
              borderRadius: BorderRadius.circular(25),
              border: Border.all(
                color: (isDark ? Colors.white : Colors.black).withOpacity(0.08),
                width: 1,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: (isDark ? Colors.white : Colors.black).withOpacity(0.5),
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    value.isEmpty ? label : value,
                    style: TextStyle(
                      fontSize: 16,
                      color: value.isEmpty
                          ? (isDark ? Colors.white : Colors.black).withOpacity(0.4)
                          : (isDark ? Colors.white : Colors.black),
                    ),
                  ),
                ),
                Icon(
                  CupertinoIcons.chevron_down,
                  color: (isDark ? Colors.white : Colors.black).withOpacity(0.4),
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: isDark ? Colors.white : Colors.black,
        ),
      ),
    );
  }

  Widget _buildPhoneField() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context)!.phone,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: (isDark ? Colors.white : Colors.black).withOpacity(0.7),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: (isDark ? Colors.white : Colors.black).withOpacity(0.06),
            borderRadius: BorderRadius.circular(25),
            border: Border.all(
              color: (isDark ? Colors.white : Colors.black).withOpacity(0.08),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              // Country code selector
              GestureDetector(
                onTap: _showCountryCodeSelector,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _getCountryCodes(context).firstWhere(
                          (country) => country['code'] == _selectedCountryCode,
                          orElse: () => _getCountryCodes(context).first,
                        )['flag']!,
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _selectedCountryCode,
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        CupertinoIcons.chevron_down,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),

              // Vertical divider
              Container(
                height: 24,
                width: 1,
                color: isDark
                    ? const Color(0xFF3A3A3A)
                    : const Color(0xFFD0D0D0),
                margin: const EdgeInsets.symmetric(horizontal: 12),
              ),

              // Phone number field
              Expanded(
                child: TradeRepublicTextField(
                  controller: _phoneController,
                  hintText: AppLocalizations.of(context)!.phoneNumber1,
                  keyboardType: TextInputType.phone,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBirthdateField() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Birthdate',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: (isDark ? Colors.white : Colors.black).withOpacity(0.7),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: (isDark ? Colors.white : Colors.black).withOpacity(0.04),
            borderRadius: BorderRadius.circular(25),
            border: Border.all(
              color: (isDark ? Colors.white : Colors.black).withOpacity(0.08),
              width: 1,
            ),
          ),
          child: GestureDetector(
            onTap: _selectBirthdate,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              child: Row(
                children: [
                  Icon(
                    CupertinoIcons.calendar,
                    color: (isDark ? Colors.white : Colors.black).withOpacity(
                      0.5,
                    ),
                    size: 22,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      _selectedBirthdate != null
                          ? (_selectedBirthdate != null
                                ? MyApp.formatDateGlobally(
                                    _selectedBirthdate!,
                                    MyApp.getCurrentDateFormat() ??
                                        'dd.MM.yyyy',
                                  )
                                : '')
                          : AppLocalizations.of(context)!.selectBirthdate1,
                      style: TextStyle(
                        color: _selectedBirthdate != null
                            ? (isDark ? Colors.white : Colors.black)
                            : (isDark ? Colors.white : Colors.black)
                                  .withOpacity(0.3),
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileImageWidget(String src) {
    try {
      if (src.startsWith('data:image')) {
        final comma = src.indexOf(',');
        if (comma != -1) {
          final bytes = base64Decode(src.substring(comma + 1));
          return Image.memory(bytes, fit: BoxFit.cover, width: double.infinity, height: double.infinity);
        }
      }
      return Image.network(src, fit: BoxFit.cover, width: double.infinity, height: double.infinity);
    } catch (_) {
      return const SizedBox.shrink();
    }
  }
}
