import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/app_config.dart';
import '../services/trade_republic_widgets.dart';
import '../services/app_localizations.dart';
import '../services/cultioo_spinner.dart';

class BlockedUsersModal extends StatefulWidget {
  final bool isDark;

  const BlockedUsersModal({super.key, required this.isDark});

  @override
  State<BlockedUsersModal> createState() => _BlockedUsersModalState();
}

class _BlockedUsersModalState extends State<BlockedUsersModal> {
  List<Map<String, dynamic>> _blockedUsers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBlockedUsers();
  }

  Future<void> _loadBlockedUsers() async {
    try {
      setState(() => _isLoading = true);

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      if (token == null) {
        setState(() {
          _blockedUsers = [];
          _isLoading = false;
        });
        return;
      }

      final response = await http.get(
        Uri.parse('${AppConfig.apiUrl}/users/blocked'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['success'] == true) {
          if (mounted) {
            setState(() {
              _blockedUsers = List<Map<String, dynamic>>.from(
                data['data'] ?? [],
              );
              _isLoading = false;
            });
          }
        }
      } else {
        throw Exception('Failed to load blocked users');
      }
    } catch (e) {
      print('❌ Error loading blocked users: $e');
      if (mounted) {
        setState(() {
          _blockedUsers = [];
          _isLoading = false;
        });

        TopNotification.error(context, AppLocalizations.of(context)!.failedToLoadBlockedUsers);
      }
    }
  }

  Future<void> _unblockUser(String username, String name) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      if (token == null) return;

      // Show loading indicator
      TradeRepublicBottomSheet.show(
        context: context,
        showDragHandle: true,
        isDismissible: false,
        enableDrag: false,
        child: const Center(child: CultiooLoadingIndicator()),
      );

      final response = await http.delete(
        Uri.parse('${AppConfig.apiUrl}/users/unblock/$username'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      // Close loading dialog
      if (mounted) Navigator.of(context).pop();

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['success'] == true) {
          if (mounted) {
            TopNotification.success(context, '$name unblocked');
          }

          // Reload the list
          _loadBlockedUsers();
        }
      } else {
        throw Exception('Failed to unblock user');
      }
    } catch (e) {
      print('❌ Error unblocking user: $e');

      if (mounted) {
        TopNotification.error(context, AppLocalizations.of(context)!.failedToUnblockUser);
      }
    }
  }

  String _formatBlockedTime(String timestamp) {
    try {
      final DateTime dateTime = DateTime.parse(timestamp);
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inDays > 30) {
        return '${(difference.inDays / 30).floor()} month${(difference.inDays / 30).floor() > 1 ? 's' : ''} ago';
      } else if (difference.inDays > 0) {
        return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
      } else if (difference.inHours > 0) {
        return '${difference.inHours} hour${difference.inHours > 1 ? 's' : ''} ago';
      } else {
        return AppLocalizations.of(context)!.justNow;
      }
    } catch (e) {
      return '';
    }
  }

  Widget _buildBlockedUserItem(Map<String, dynamic> user) {
    final username = user['username'] ?? '';
    final name = user['name'] ?? username;
    final blockedAt = user['blocked_at'] ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          // Avatar
          CircleAvatar(
            radius: 24,
            backgroundColor: Colors.red.withOpacity(0.2),
            child: Icon(CupertinoIcons.slash_circle, color: Colors.red, size: 20),
          ),

          const SizedBox(width: 12),

          // User info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: widget.isDark ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '@$username',
                  style: TextStyle(
                    fontSize: 13,
                    color: widget.isDark ? Colors.grey[500] : Colors.grey[600],
                  ),
                ),
                if (blockedAt.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    AppLocalizations.of(context)!.blockedTime(_formatBlockedTime(blockedAt)),
                    style: TextStyle(
                      fontSize: 11,
                      color: widget.isDark
                          ? Colors.grey[600]
                          : Colors.grey[500],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Unblock button
          TradeRepublicButton(
            label: AppLocalizations.of(context)!.unblock,
            backgroundColor: const Color(0xFF007AFF),
            foregroundColor: Colors.white,
            onPressed: () => _unblockUser(username, name),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.slash_circle_fill,
                  color: widget.isDark ? Colors.white : Colors.black,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context)!.blockedUsers,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: widget.isDark ? Colors.white : Colors.black,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: _isLoading
                ? Center(
                    child: CultiooLoadingIndicator(),
                  )
                : _blockedUsers.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          CupertinoIcons.slash_circle,
                          size: 64,
                          color: (widget.isDark ? Colors.white : Colors.black)
                              .withOpacity(0.3),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          AppLocalizations.of(context)!.noBlockedUsers,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: widget.isDark
                                ? Colors.white70
                                : Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          AppLocalizations.of(context)!.usersYouBlockWillAppearHere,
                          style: TextStyle(
                            fontSize: 14,
                            color: widget.isDark
                                ? Colors.white54
                                : Colors.black45,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    children: _blockedUsers.map((user) {
                      return _buildBlockedUserItem(user);
                    }).toList(),
                  ),
          ),
        ],

    );
  }
}
