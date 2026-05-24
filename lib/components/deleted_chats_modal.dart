import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../services/api_service.dart';
import '../services/trade_republic_widgets.dart';

import '../main.dart';
import '../services/app_localizations.dart';
import '../services/cultioo_spinner.dart';

class DeletedChatsModal extends StatefulWidget {
  final bool isDark;

  const DeletedChatsModal({super.key, required this.isDark});

  @override
  State<DeletedChatsModal> createState() => _DeletedChatsModalState();
}

class _DeletedChatsModalState extends State<DeletedChatsModal> {
  Set<String> _hiddenConversations = {};
  List<Map<String, dynamic>> _deletedChats = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDeletedChats();
  }

  Future<void> _loadDeletedChats() async {
    try {
      setState(() => _isLoading = true);

      final prefs = await SharedPreferences.getInstance();
      final hidden = prefs.getStringList('hidden_conversations') ?? [];
      _hiddenConversations = hidden.map((id) => id.toString()).toSet();

      // Load all conversations from server
      final token = await ApiService.getToken() ??
          prefs.getString('auth_token') ??
          prefs.getString('access_token');
      if (token == null) {
        setState(() {
          _deletedChats = [];
          _isLoading = false;
        });
        return;
      }

      final response = await http
          .get(
            Uri.parse('${AppConfig.apiUrl}/messages/conversations'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final allConversations = List<Map<String, dynamic>>.from(
            data['data'] ?? [],
          );

          // Filter only hidden conversations
          final deleted = allConversations
              .where(
                (conv) =>
                    _hiddenConversations.contains(
                      conv['conversation_id']?.toString(),
                    ),
              )
              .toList();

          setState(() {
            _deletedChats = deleted;
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _deletedChats = [];
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Error loading deleted chats: $e');
      setState(() {
        _deletedChats = [];
        _isLoading = false;
      });
    }
  }

  Future<void> _restoreChat(String conversationId) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      setState(() {
        _hiddenConversations.remove(conversationId);
        _deletedChats.removeWhere(
          (conv) => conv['conversation_id']?.toString() == conversationId,
        );
      });

      await prefs.setStringList(
        'hidden_conversations',
        _hiddenConversations.toList(),
      );

      if (mounted) {
        TopNotification.success(context, AppLocalizations.of(context)!.chatRestored);
      }
    } catch (e) {
      print('❌ Error restoring chat: $e');
    }
  }

  Future<void> _permanentlyDelete(String conversationId) async {
    try {
      setState(() {
        _deletedChats.removeWhere(
          (conv) => conv['conversation_id']?.toString() == conversationId,
        );
      });

      if (mounted) {
        TopNotification.error(context, AppLocalizations.of(context)!.chatPermanentlyDeleted);
      }
    } catch (e) {
      print('❌ Error permanently deleting chat: $e');
    }
  }

  String _formatLastMessageTime(String timestamp) {
    try {
      final DateTime dateTime = DateTime.parse(timestamp);
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inDays > 7) {
        final currentFormat = MyApp.getCurrentDateFormat() ?? 'dd.MM.yyyy';
        return MyApp.formatDateGlobally(dateTime, currentFormat);
      } else if (difference.inDays > 0) {
        return '${difference.inDays}d';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}h';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}m';
      } else {
        return AppLocalizations.of(context)!.now;
      }
    } catch (e) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: _isLoading
              ? Center(
                  child: CultiooLoadingIndicator(),
                )
              : _deletedChats.isEmpty
              ? _buildEmptyState()
              : _buildDeletedChatsList(),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                CupertinoIcons.trash_fill,
                color: widget.isDark ? Colors.white : Colors.black,
                size: 32,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  AppLocalizations.of(context)!.deletedChats,
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
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              '${_deletedChats.length} deleted chat${_deletedChats.length != 1 ? 's' : ''}',
              style: TextStyle(
                fontSize: 14,
                color: widget.isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.trash,
              size: 64,
              color: (widget.isDark ? Colors.white : Colors.black).withOpacity(
                0.3,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              AppLocalizations.of(context)!.noDeletedChats,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: widget.isDark ? Colors.white70 : Colors.black54,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context)!.deletedChatsWillAppearHere,
              style: TextStyle(
                fontSize: 14,
                color: widget.isDark ? Colors.white54 : Colors.black45,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeletedChatsList() {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: _deletedChats.length,
      itemBuilder: (context, index) {
        final chat = _deletedChats[index];
        return _buildDeletedChatItem(chat);
      },
    );
  }

  Widget _buildDeletedChatItem(Map<String, dynamic> chat) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: widget.isDark
            ? Colors.white.withOpacity(0.05)
            : Colors.black.withOpacity(0.02),
        borderRadius: BorderRadius.circular(25),
      ),
      child: Row(
        children: [
          // Avatar
          CircleAvatar(
            radius: 28,
            backgroundColor: Colors.red.withOpacity(0.7),
            child: Text(
              chat['other_user_name'][0].toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        chat['other_user_name'],
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: widget.isDark ? Colors.white : Colors.black,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      _formatLastMessageTime(chat['last_message_time']),
                      style: TextStyle(
                        fontSize: 12,
                        color: widget.isDark
                            ? Colors.grey[500]
                            : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '@${chat['other_user_username']}',
                  style: TextStyle(
                    fontSize: 12,
                    color: widget.isDark ? Colors.grey[500] : Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Restore button
          TradeRepublicButton(
            icon: const Icon(CupertinoIcons.arrow_counterclockwise),
            onPressed: () => _restoreChat(chat['conversation_id'].toString()),
          ),
        ],
      ),
    );
  }
}
