import '../services/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../services/address_search_service.dart';
import 'dart:async';
import '../services/cultioo_spinner.dart';
import '../services/trade_republic_widgets.dart';

class AddressSearchField extends StatefulWidget {
  final Function(AddressSuggestion) onAddressSelected;
  final String? initialValue;

  const AddressSearchField({
    super.key,
    required this.onAddressSelected,
    this.initialValue,
  });

  @override
  State<AddressSearchField> createState() => _AddressSearchFieldState();
}

class _AddressSearchFieldState extends State<AddressSearchField> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  List<AddressSuggestion> _suggestions = [];
  bool _isLoading = false;
  bool _showSuggestions = false;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null) {
      _controller.text = widget.initialValue!;
    }

    _controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onTextChanged() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _searchAddresses(_controller.text);
    });
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      // Delay so suggestion tap works
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted) {
          setState(() {
            _showSuggestions = false;
          });
        }
      });
    }
  }

  Future<void> _searchAddresses(String query) async {
    if (query.trim().isEmpty || query.length < 3) {
      setState(() {
        _suggestions = [];
        _showSuggestions = false;
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _showSuggestions = true;
    });

    try {
      final suggestions = await AddressSearchService.searchAddresses(query);

      if (mounted) {
        setState(() {
          _suggestions = suggestions;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _suggestions = [];
          _isLoading = false;
        });
      }
    }
  }

  void _selectSuggestion(AddressSuggestion suggestion) {
    _controller.text = suggestion.formattedAddress;
    setState(() {
      _showSuggestions = false;
      _suggestions = [];
    });
    _focusNode.unfocus();
    widget.onAddressSelected(suggestion);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Input field
        TextFormField(
          controller: _controller,
          focusNode: _focusNode,
          style: TextStyle(color: isDark ? Colors.white : Colors.black),
          decoration: InputDecoration(
            hintText: AppLocalizations.of(context)!.typeAddress,
            hintStyle: TextStyle(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
            prefixIcon: Icon(
              CupertinoIcons.search,
              color: isDark ? Colors.white : Colors.black,
              size: 20,
            ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            suffixIcon: _isLoading
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CultiooLoadingIndicator(),
                    ),
                  )
                : null,
          ),
          onTap: () {
            if (_suggestions.isNotEmpty) {
              setState(() {
                _showSuggestions = true;
              });
            }
          },
        ),

        // Suggestion list with elevated position using Material elevation
        if (_showSuggestions && _suggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          TradeRepublicCard(
            padding: EdgeInsets.zero,
            boxShadow: const [],
            borderRadius: BorderRadius.circular(25),
            backgroundColor: isDark ? const Color(0xFF000000) : Colors.white,
            child: Container(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _suggestions.length,
                separatorBuilder: (context, index) => Divider(
                  height: 1,
                  color: isDark
                      ? Colors.white.withOpacity(0.08)
                      : Colors.black.withOpacity(0.08),
                ),
                itemBuilder: (context, index) {
                  final suggestion = _suggestions[index];

                  return TradeRepublicListTile(
                    title: suggestion.formattedAddress,
                    subtitle: suggestion.country,
                    leading: Icon(
                      CupertinoIcons.location_solid,
                      color: isDark ? Colors.white : Colors.black,
                      size: 16,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    onTap: () => _selectSuggestion(suggestion),
                  );
                },
              ),
            ),
          ),
        ],

        // Help texts
        if (_showSuggestions &&
            _suggestions.isEmpty &&
            !_isLoading &&
            _controller.text.length >= 3) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? Colors.black.withOpacity(0.6) : Colors.grey[100],
              borderRadius: BorderRadius.circular(25),
              boxShadow: const [],
            ),
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.search,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context)!.noAddressesFound,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
