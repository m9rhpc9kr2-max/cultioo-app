import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/app_config.dart';
import '../services/device_storage.dart';
import '../services/trade_republic_widgets.dart';
import 'chat_modal.dart';
import '../services/app_localizations.dart';

class FindUsersModal extends StatefulWidget {
  final bool isDark;
  final Function(String username, String name)? onStartChat;

  const FindUsersModal({
    super.key, 
    required this.isDark,
    this.onStartChat,
  });

  @override
  State<FindUsersModal> createState() => _FindUsersModalState();
}

class _FindUsersModalState extends State<FindUsersModal> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> searchResults = [];
  bool isSearching = false;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.person_2_fill,
                  color: widget.isDark ? Colors.white : Colors.black,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context)!.findUsers,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: widget.isDark ? Colors.white : Colors.black,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Search Bar - Trade Republic minimal style
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TradeRepublicTextField.search(
              controller: _searchController,
              hintText: AppLocalizations.of(context)!.searchUsers,
              onChanged: (value) {
                setState(() {
                  isSearching = value.isNotEmpty;
                });
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 300), () {
                  _performSearch(value);
                });
              },
            ),
          ),

          const SizedBox(height: 24),

          // Results
          Expanded(
            child: _searchController.text.isEmpty
                ? _buildEmptyState()
                : searchResults.isEmpty && isSearching
                    ? _buildNoResults()
                    : _buildResults(),
          ),
        ],
      );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: widget.isDark
                  ? Colors.white.withOpacity(0.04)
                  : Colors.black.withOpacity(0.03),
              shape: BoxShape.circle,
            ),
            child: Icon(
              CupertinoIcons.search,
              size: 44,
              color: widget.isDark ? Colors.white.withOpacity(0.3) : Colors.black.withOpacity(0.3),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            AppLocalizations.of(context)!.searchForUsers,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
              color: widget.isDark ? Colors.white.withOpacity(0.7) : Colors.black.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.of(context)!.startTypingToFindPeople,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              letterSpacing: 0,
              color: widget.isDark ? Colors.white.withOpacity(0.4) : Colors.black.withOpacity(0.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResults() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: widget.isDark
                  ? Colors.white.withOpacity(0.04)
                  : Colors.black.withOpacity(0.03),
              shape: BoxShape.circle,
            ),
            child: Icon(
              CupertinoIcons.person_crop_circle_badge_xmark,
              size: 44,
              color: widget.isDark ? Colors.white.withOpacity(0.3) : Colors.black.withOpacity(0.3),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            AppLocalizations.of(context)!.noUsersFound,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
              color: widget.isDark ? Colors.white.withOpacity(0.7) : Colors.black.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.of(context)!.tryADifferentSearch,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              letterSpacing: 0,
              color: widget.isDark ? Colors.white.withOpacity(0.4) : Colors.black.withOpacity(0.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      itemCount: searchResults.length,
      itemBuilder: (context, index) {
        final user = searchResults[index];
        return _buildUserCard(user);
      },
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    final username = user['username'] ?? '';
    final displayName = user['display_name'] ?? username;
    final avatar = user['avatar'];
    final isBusiness = user['type'] == 'business';

    return TradeRepublicListTile(
      title: displayName,
      subtitle: '@$username',
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(25),
        child: SizedBox(
          width: 40,
          height: 40,
          child: avatar != null
              ? Image.network(
                  avatar.startsWith('http')
                      ? avatar
                      : '${AppConfig.baseUrl}$avatar',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      _buildDefaultAvatar(isBusiness),
                )
              : _buildDefaultAvatar(isBusiness),
        ),
      ),
      trailing: TradeRepublicButton(
        icon: const Icon(CupertinoIcons.chat_bubble_fill),
        onPressed: () => _startConversation(username),
      ),
      onTap: () => _startConversation(username),
    );
  }

  Widget _buildDefaultAvatar(bool isBusiness) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0xFF007AFF).withOpacity(0.15),
        borderRadius: BorderRadius.circular(25),
      ),
      child: Icon(
        isBusiness ? CupertinoIcons.building_2_fill : CupertinoIcons.person_fill,
        color: const Color(0xFF007AFF),
        size: 22,
      ),
    );
  }

  void _performSearch(String query) async {
    if (query.isEmpty || query.length < 2) {
      setState(() {
        searchResults.clear();
      });
      return;
    }

    try {
      final token = await DeviceStorage.getString('access_token');

      if (token == null || token.isEmpty) {
        print('❌ No auth token found');
        setState(() {
          searchResults.clear();
        });
        return;
      }

      final response = await http.get(
        Uri.parse(
          '${AppConfig.apiUrl}/users/search?q=${Uri.encodeComponent(query)}',
        ),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final users = List<Map<String, dynamic>>.from(data['users']);

          final formattedResults = users
              .map(
                (user) => {
                  'type': user['isBusiness'] == true ? 'business' : 'user',
                  'username': user['username'],
                  'display_name': user['name'],
                  'avatar': user['avatar'],
                  'verified': user['isBusiness'] == true,
                },
              )
              .toList();

          setState(() {
            searchResults.clear();
            searchResults.addAll(formattedResults);
          });
        } else {
          setState(() {
            searchResults.clear();
          });
        }
      } else {
        setState(() {
          searchResults.clear();
        });
      }
    } catch (e) {
      print('❌ Search error: $e');
      setState(() {
        searchResults.clear();
      });
    }
  }

  void _startConversation(String username) {
    if (widget.onStartChat != null) {
      widget.onStartChat!(username, username);
      return;
    }

    Navigator.pop(context);

    Future.delayed(const Duration(milliseconds: 100), () {
      TradeRepublicBottomSheet.show(
        context: context,
        showDragHandle: true,
        maxHeight: MediaQuery.of(context).size.height * 0.94,
        child: ChatModal(
          partnerId: username,
          partnerName: username,
          isDark: widget.isDark,
        ),
      );
    });
  }
}
