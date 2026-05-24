import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/app_config.dart';
import '../services/device_storage.dart';
import '../services/api_service.dart';
import '../services/app_localizations.dart';
import 'chat_modal.dart';
import 'find_users_modal.dart';
import 'blocked_users_modal.dart';
import 'deleted_chats_modal.dart';
import 'cully_chat_page.dart';
import '../services/cultioo_spinner.dart';

import '../main.dart';
import '../services/trade_republic_widgets.dart';
import '../services/cultioo_desktop_layout.dart';

class ChatOverviewPage extends StatefulWidget {
  final bool isDark;

  const ChatOverviewPage({super.key, required this.isDark});

  @override
  State<ChatOverviewPage> createState() => _ChatOverviewPageState();
}

class _ChatOverviewPageState extends State<ChatOverviewPage>
    with WidgetsBindingObserver {
  List<Map<String, dynamic>> _conversations = [];
  bool _isLoading = true;
  String? _currentUsername;
  Set<String> _pinnedConversations = {}; // Store pinned conversation IDs
  Set<String> _hiddenConversations =
      {}; // Store locally deleted conversation IDs
  bool _isModalOpen = false; // Track if any modal is open

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPinnedAndHiddenConversations();
    _loadConversations();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Reload conversations when app comes back to foreground
    if (state == AppLifecycleState.resumed && mounted) {
      _loadConversations();
    }
  }

  // Load pinned and hidden conversations from local storage
  Future<void> _loadPinnedAndHiddenConversations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;

      final pinned = prefs.getStringList('pinned_conversations') ?? [];
      final hidden = prefs.getStringList('hidden_conversations') ?? [];

      if (!mounted) return;
      setState(() {
        _pinnedConversations = pinned.toSet();
        _hiddenConversations = hidden.toSet();
      });
    } catch (e) {
      if (mounted) {
        print('❌ Error loading pinned/hidden conversations: $e');
      }
    }
  }

  // Toggle pin status for a conversation
  Future<void> _togglePin(String conversationId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;

      setState(() {
        if (_pinnedConversations.contains(conversationId)) {
          _pinnedConversations.remove(conversationId);
        } else {
          _pinnedConversations.add(conversationId);
        }
      });

      await prefs.setStringList(
        'pinned_conversations',
        _pinnedConversations.toList(),
      );

      // Re-sort conversations to move pinned ones to top
      if (mounted) _sortConversations();
    } catch (e) {
      if (mounted) print('❌ Error toggling pin: $e');
    }
  }

  // Hide (locally delete) a conversation
  Future<void> _hideConversation(String conversationId) async {
    if (conversationId.startsWith('group:')) {
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;

      setState(() {
        _hiddenConversations.add(conversationId);
        _conversations.removeWhere(
          (conv) => conv['conversation_id']?.toString() == conversationId,
        );
      });

      await prefs.setStringList(
        'hidden_conversations',
        _hiddenConversations.toList(),
      );

      // Show notification at top with undo option
      if (mounted) {
        TopNotification.error(context, AppLocalizations.of(context)!.chatDeletedLocally);
        // Note: Undo action not supported in TopNotification, user can restore from Deleted Chats
      }
    } catch (e) {
      if (mounted) print('❌ Error hiding conversation: $e');
    }
  }

  // Undo hiding a conversation
  Future<void> _unhideConversation(String conversationId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;

      setState(() {
        _hiddenConversations.remove(conversationId);
      });

      await prefs.setStringList(
        'hidden_conversations',
        _hiddenConversations.toList(),
      );

      // Reload to show the conversation again
      if (mounted) _loadConversations();
    } catch (e) {
      if (mounted) print('❌ Error unhiding conversation: $e');
    }
  }

  // Sort conversations: Cully first, then pinned, then by time
  void _sortConversations() {
    if (!mounted) return;
    setState(() {
      _conversations.sort((a, b) {
        final aId = a['conversation_id'];
        final bId = b['conversation_id'];
        final aIsCully = a['is_chatbot'] == true;
        final bIsCully = b['is_chatbot'] == true;
        final aPinned = _pinnedConversations.contains(aId);
        final bPinned = _pinnedConversations.contains(bId);

        // Cully chatbot always comes first
        if (aIsCully && !bIsCully) return -1;
        if (!aIsCully && bIsCully) return 1;

        // Pinned conversations come second
        if (aPinned && !bPinned) return -1;
        if (!aPinned && bPinned) return 1;

        // If both pinned or both not pinned, sort by time
        try {
          final aTime = DateTime.parse(a['last_message_time']);
          final bTime = DateTime.parse(b['last_message_time']);
          return bTime.compareTo(aTime); // Most recent first
        } catch (e) {
          return 0;
        }
      });
    });
  }

  Future<void> _loadConversations() async {
    try {
      if (!mounted) return;
      setState(() => _isLoading = true);

      // Always refresh hidden conversations from storage (e.g. after restore)
      final prefs = await SharedPreferences.getInstance();
      final hidden = prefs.getStringList('hidden_conversations') ?? [];
      _hiddenConversations = hidden.where((id) => !id.startsWith('group:')).toSet();

      if (_hiddenConversations.length != hidden.length) {
        await prefs.setStringList(
          'hidden_conversations',
          _hiddenConversations.toList(),
        );
      }

      final token = await ApiService.getToken();
      _currentUsername = await DeviceStorage.getString('username');

      if (token == null) {
        print('❌ No auth token found');
        if (!mounted) return;
        setState(() {
          _conversations = [];
          _isLoading = false;
        });
        return;
      }

      print('🔄 Loading conversations from API...');
      print('🔑 Token: ${token.substring(0, 20)}...');
      print('📍 API URL: ${AppConfig.apiUrl}/messages/conversations');

      final response = await http
          .get(
            Uri.parse('${AppConfig.apiUrl}/messages/conversations'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
              if ((_currentUsername ?? '').isNotEmpty)
                'X-Username': _currentUsername!,
            },
          )
          .timeout(
            const Duration(seconds: 10), // Add timeout to prevent hanging
            onTimeout: () {
              throw Exception(
                AppLocalizations.of(context)!.requestTimeoutServerTookTooLongToRespond,
              );
            },
          );

      print('📨 Conversations response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        try {
          final data = json.decode(response.body);
          print('📨 Conversations response data: $data');

          if (data['success'] == true) {
            final conversations = List<Map<String, dynamic>>.from(
              data['data'] ?? [],
            );

            // Filter out hidden conversations AND driver/delvioo conversations
            final visibleConversations = conversations
                .where(
                  (conv) =>
                      ((conv['conversation_id']?.toString().startsWith('group:') ?? false) ||
                          !_hiddenConversations.contains(
                            conv['conversation_id']?.toString(),
                          )) &&
                      conv['conversation_type'] != 'driver' &&
                      conv['conversation_type'] != 'delvioo',
                )
                .toList();

            // Cache conversations locally for offline use (without driver chats)
            await _cacheConversations(visibleConversations);

            if (mounted) {
              setState(() {
                _conversations = visibleConversations;
                _isLoading = false;
              });

              // Sort to put pinned conversations at top
              _sortConversations();
            }

            print('✅ Loaded ${_conversations.length} conversations from server');
          } else {
            throw Exception(data['message'] ?? 'API returned success=false');
          }
        } catch (jsonError) {
          //print('❌ JSON parsing error: $jsonError');
          //print('📨 Raw response body: ${response.body}');
          throw Exception('Invalid JSON response from server');
        }
      } else if (response.statusCode == 401) {
        //print('❌ Unauthorized - token may be expired');
        // Clear invalid token
        await DeviceStorage.remove('auth_token');
        throw Exception('Authentication failed - please login again');
      } else if (response.statusCode == 500) {
        //print('⚠️ Server temporarily unavailable - using cached data');
        // Don't throw exception for 500 errors, just use cached data
        final cachedConversations = await _loadCachedConversations();
        if (cachedConversations.isNotEmpty && mounted) {
          setState(() {
            _conversations = cachedConversations;
            _isLoading = false;
          });
          //print('📱 Loaded ${_conversations.length} conversations from cache');
          return; // Exit early with cached data
        } else if (mounted) {
          // No cache available - show empty state
          setState(() {
            _conversations = [];
            _isLoading = false;
          });
          return;
        }
      } else {
        //print('❌ HTTP Error ${response.statusCode}: ${response.body}');
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      // Only log serious errors, not server unavailability
      if (!e.toString().contains('500')) {
        //print('❌ Error loading conversations: $e');
      }

      // Show user-friendly error message only for critical errors
      String? errorMessage;
      bool showSnackbar = true;

      if (e.toString().contains('timeout')) {
        errorMessage = AppLocalizations.of(context)!.connectionTimeoutPleaseCheckYourInternet;
      } else if (e.toString().contains('500')) {
        // Don't show snackbar for 500 errors, just silently use cache
        showSnackbar = false;
      } else if (e.toString().contains('401')) {
        errorMessage = AppLocalizations.of(context)!.pleaseLoginAgain;
      } else if (e.toString().contains('SocketException')) {
        errorMessage = AppLocalizations.of(context)!.noInternetConnection;
      } else {
        // Don't show generic error message, just silently use cache
        showSnackbar = false;
      }

      // Show notification with error only if it's not a 500 server error or generic error
      if (mounted && showSnackbar && errorMessage != null) {
        TopNotification.error(context, errorMessage);
        // Note: Retry action not supported in TopNotification, user can use refresh button
      }

      // Try to load from cache first if server fails
      final cachedConversations = await _loadCachedConversations();
      if (cachedConversations.isNotEmpty && mounted) {
        //print('📱 Using cached conversations as fallback');
        setState(() {
          _conversations = cachedConversations;
          _isLoading = false;
        });
      } else if (mounted) {
        setState(() {
          _conversations = [];
          _isLoading = false;
        });
      }
    }
  }

  // Cache conversations locally for offline use
  Future<void> _cacheConversations(
    List<Map<String, dynamic>> conversations,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final conversationsJson = conversations
          .map((conv) => json.encode(conv))
          .toList();
      await prefs.setStringList('cached_conversations', conversationsJson);
      await prefs.setInt(
        'conversations_cache_time',
        DateTime.now().millisecondsSinceEpoch,
      );
      //print('💾 Cached ${conversations.length} conversations locally');
    } catch (e) {
      //print('❌ Error caching conversations: $e');
    }
  }

  // Load cached conversations
  Future<List<Map<String, dynamic>>> _loadCachedConversations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final conversationsJson =
          prefs.getStringList('cached_conversations') ?? [];
      final cacheTime = prefs.getInt('conversations_cache_time') ?? 0;

      // Check if cache is not too old (24 hours)
      final now = DateTime.now().millisecondsSinceEpoch;
      final isExpired =
          (now - cacheTime) > (24 * 60 * 60 * 1000); // 24 hours in milliseconds

      if (isExpired) {
        //print('📱 Cache expired, not using cached data');
        return [];
      }

      final conversations = conversationsJson
          .map((jsonStr) => json.decode(jsonStr) as Map<String, dynamic>)
          .toList();

      // Filter out driver/delvioo conversations from cache (safety check)
      final filteredConversations = conversations
          .where((conv) =>
              conv['conversation_type'] != 'driver' &&
              conv['conversation_type'] != 'delvioo')
          .toList();

      //print('📱 Loaded ${filteredConversations.length} conversations from cache');
      return filteredConversations;
    } catch (e) {
      //print('❌ Error loading cached conversations: $e');
      return [];
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

  void _openChat(Map<String, dynamic> conversation) {
    // Check if this is the Cully chatbot
    final isChatbot = conversation['is_chatbot'] == true;

    if (isChatbot) {
      // Navigate to Cully chat page
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CullyChatPage(isDark: widget.isDark),
        ),
      ).then((_) {
        // Refresh conversations when returning
        _loadConversations();
      });
      return;
    }

    setState(() {
      _isModalOpen = true;
    });

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      useRootNavigator: true,
      maxHeight: MediaQuery.of(context).size.height * 0.94,
      child: ChatModal(
        partnerId: conversation['other_user_username'],
        partnerName: conversation['other_user_name'],
        isDark: widget.isDark,
        initialProfileImage: (conversation['profile_image'] as String?) ?? '',
      ),
    ).whenComplete(() {
      if (mounted) {
        setState(() {
          _isModalOpen = false;
        });
      }
      if (mounted) {
        // Refresh conversations when chat modal is closed
        _loadConversations();
      }
    });
  }

  // Build special Cully chatbot item with minimalist design
  Widget _buildChatbotItem(Map<String, dynamic> conversation) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: widget.isDark 
            ? Colors.black
            : const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(25),
      ),
      child: GestureDetector(
        onTap: () => _openChat(conversation),
        child: Row(
          children: [
            // Cully Avatar
            CircleAvatar(
              radius: 24,
              backgroundColor: Colors.transparent,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(25),
                child: Image.asset(
                  widget.isDark
                      ? 'logo/cully_dark.png'
                      : 'logo/cully_light.png',
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                ),
              ),
            ),

            const SizedBox(width: 12),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '@cully',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: widget.isDark ? Colors.white : Colors.black,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Minimal AI Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF007AFF).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(25),
                        ),
                        child: const Text(
                          'AI',
                          style: TextStyle(
                            color: Color(0xFF007AFF),
                            fontSize: 8.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    conversation['last_message'] ?? AppLocalizations.of(context)!.yourAiAssistant,
                    style: TextStyle(
                      fontSize: 14,
                      color: widget.isDark
                          ? Colors.grey[600]
                          : Colors.grey[500],
                      fontWeight: FontWeight.normal,
                      letterSpacing: -0.1,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Minimal Arrow
            Icon(
              CupertinoIcons.chevron_right,
              size: 18,
              color: widget.isDark ? Colors.grey[700] : Colors.grey[400],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConversationItem(Map<String, dynamic> conversation) {
    final hasUnread = conversation['has_unread'] == true;
    final conversationId = conversation['conversation_id'].toString();
    final isPinned = _pinnedConversations.contains(conversationId);
    final isChatbot = conversation['is_chatbot'] == true;
    final isGroup = conversation['is_group'] == true ||
        (conversation['conversation_type']?.toString() == 'group') ||
        conversationId.startsWith('group:');
    final userRole = conversation['user_role']; // buyer or seller (no drivers in Cultioo app)
    
    // Get profile image - backend returns full URL or base64 data URI
    final profileImage = conversation['profile_image'] ?? '';
    final ImageProvider? profileImageProvider = profileImage.isNotEmpty
        ? (profileImage.startsWith('data:image/')
            ? MemoryImage(base64Decode(profileImage.split(',')[1]))
            : NetworkImage(profileImage) as ImageProvider)
        : null;
    
    // Chatbot should not be dismissible
    if (isChatbot) {
      return _buildChatbotItem(conversation);
    }

    return TradeRepublicSwipeAction(
      margin: const EdgeInsets.only(bottom: 8),
      borderRadius: 25,
      foregroundColor: widget.isDark ? Colors.black : Colors.white,
      onTap: () => _openChat(conversation),
      leading: TradeRepublicSwipeSpec(
        icon: CupertinoIcons.pin_fill,
        label: 'Pin',
        activeIcon: CupertinoIcons.pin_slash_fill,
        activeLabel: 'Unpin',
        isActive: isPinned,
        onActivate: () => _togglePin(conversationId),
        iconRotation: -0.4,
      ),
      trailing: isGroup
          ? null
          : TradeRepublicSwipeSpec(
              icon: CupertinoIcons.trash,
              label: 'Delete',
              onActivate: () => _hideConversation(conversationId),
              backgroundColor: Colors.red,
            ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isPinned
              ? (widget.isDark
                    ? Colors.transparent
                    : const Color(0xFFF2F2F7))
              : (widget.isDark 
                    ? Colors.transparent
                    : const Color(0xFFF8F9FA)),
          borderRadius: BorderRadius.circular(25),
        ),
        child: Row(
          children: [
            // Avatar
            Stack(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: profileImageProvider != null
                      ? Colors.transparent
                      : const Color(0xFF007AFF),
                  backgroundImage: profileImageProvider,
                  onBackgroundImageError: profileImageProvider != null
                      ? (exception, stackTrace) {
                          print('❌ Error loading profile image: $exception');
                        }
                      : null,
                  child: profileImage.isEmpty
                      ? Text(
                        (conversation['other_user_name'] as String?)
                            ?.trim()
                            .isNotEmpty ==
                          true
                          ? conversation['other_user_name'][0].toUpperCase()
                          : 'G',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        )
                      : null,
                ),
                if (hasUnread)
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: const Color(0xFF34C759),
                        borderRadius: BorderRadius.circular(25),
                        border: Border.all(
                          color: widget.isDark ? Colors.black : Colors.white,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(width: 12),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (isPinned) ...[
                        Icon(
                          CupertinoIcons.pin_fill,
                          size: 11,
                          color: widget.isDark ? Colors.grey[600] : Colors.grey[400],
                        ),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          isGroup
                              ? (conversation['other_user_name'] ?? AppLocalizations.of(context)!.groups)
                              : (conversation['other_user_name'] != null &&
                                      conversation['other_user_name'] != conversation['other_user_username']
                                  ? conversation['other_user_name']
                                  : '@${conversation['other_user_username']}'),
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight:
                                hasUnread ? FontWeight.w800 : FontWeight.w700,
                            color: widget.isDark ? Colors.white : Colors.black,
                            letterSpacing: -0.2,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isGroup) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF007AFF).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(25),
                          ),
                          child: const Text(
                            'GROUP',
                            style: TextStyle(
                              fontSize: 8.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF007AFF),
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ] else if (userRole != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: userRole == 'driver'
                                ? const Color(0xFFFF9500).withOpacity(0.12)
                                : userRole == 'buyer'
                                    ? const Color(0xFF34C759).withOpacity(0.12)
                                    : const Color(0xFF007AFF).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(25),
                          ),
                          child: Text(
                            userRole == 'driver'
                                ? AppLocalizations.of(context)!.driver
                                : userRole == 'buyer'
                                    ? AppLocalizations.of(context)!.buyer
                                    : AppLocalizations.of(context)!.seller,
                            style: TextStyle(
                              fontSize: 8.5,
                              fontWeight: FontWeight.w600,
                              color: userRole == 'driver'
                                  ? const Color(0xFFFF9500)
                                  : userRole == 'buyer'
                                      ? const Color(0xFF34C759)
                                      : const Color(0xFF007AFF),
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(width: 6),
                      Text(
                        _formatLastMessageTime(
                          conversation['last_message_time'],
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          color: hasUnread
                              ? const Color(0xFF007AFF)
                              : (widget.isDark
                                  ? Colors.grey[600]
                                  : Colors.grey[500]),
                          fontWeight:
                              hasUnread ? FontWeight.w500 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 3),

                  // Show @username below if there's a separate display name
                  if (!isGroup &&
                      conversation['other_user_name'] != null &&
                      conversation['other_user_name'] != conversation['other_user_username']) ...[
                    Text(
                      '@${conversation['other_user_username']}',
                      style: TextStyle(
                        fontSize: 12,
                        color: widget.isDark ? Colors.grey[600] : Colors.grey[500],
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.1,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                  ],

                  Row(
                    children: [
                      Expanded(
                        child: RichText(
                          overflow: TextOverflow.ellipsis,
                          text: TextSpan(
                            children: [
                              // Show sender username if available
                              if (conversation['last_message_sender'] != null) ...[
                                TextSpan(
                                  text: '@${conversation['last_message_sender']}: ',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: widget.isDark
                                        ? Colors.grey[500]
                                        : Colors.grey[600],
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.1,
                                  ),
                                ),
                              ],
                              // Show message text
                              TextSpan(
                                text: conversation['last_message'] ?? AppLocalizations.of(context)!.tapToStartConversation,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: widget.isDark
                                      ? Colors.grey[600]
                                      : Colors.grey[500],
                                  fontWeight: FontWeight.normal,
                                  letterSpacing: -0.1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Arrow - minimal icon
            Icon(
              CupertinoIcons.chevron_right,
              size: 18,
              color: widget.isDark ? Colors.grey[700] : Colors.grey[400],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWideScreen = MediaQuery.of(context).size.width > 900 &&
        (defaultTargetPlatform == TargetPlatform.macOS ||
         defaultTargetPlatform == TargetPlatform.windows ||
         defaultTargetPlatform == TargetPlatform.linux);

    final hPad = CultiooDesktopLayout.isDesktopPlatform
        ? CultiooDesktopLayout.mainHorizontalPadding
        : (isWideScreen ? 32.0 : 24.0);

    return Scaffold(
      backgroundColor: CultiooDesktopLayout.isDesktopPlatform
          ? Colors.transparent
          : (widget.isDark ? Colors.black : Colors.white),
      body: CustomScrollView(
        physics: CultiooDesktopLayout.adaptiveScrollPhysics(context),
        slivers: [
          if (!CultiooDesktopLayout.isDesktopPlatform)
            CultiooSliverRefreshControl(
              onRefresh: () async {
                await _loadConversations();
              },
            ),

          // ── Header ──────────────────────────────────────────────────
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              hPad,
              CultiooDesktopLayout.isDesktopPlatform
                  ? 20
                  : MediaQuery.of(context).padding.top + 44,
              hPad,
              0,
            ),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        CupertinoIcons.chat_bubble_fill,
                        color: widget.isDark ? Colors.white : Colors.black,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          AppLocalizations.of(context)!.messages,
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                            color: widget.isDark ? Colors.white : Colors.black,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                      TradeRepublicButton(
                        icon: const Icon(CupertinoIcons.ellipsis_vertical, size: 18),
                        isSecondary: true,
                        width: 48,
                        height: 48,
                        padding: EdgeInsets.zero,
                        borderRadius: BorderRadius.circular(25),
                        onPressed: () => _showAndroidOptionsMenu(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),

          // ── Loading state ────────────────────────────────────────────
          if (_isLoading)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 120),
                child: Center(
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: CultiooLoadingIndicator(),
                  ),
                ),
              ),
            )

          // ── Empty state ──────────────────────────────────────────────
          else if (_conversations.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 80),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        CupertinoIcons.chat_bubble,
                        size: 64,
                        color: widget.isDark ? Colors.grey[700] : Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        AppLocalizations.of(context)!.noConversations,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: widget.isDark ? Colors.grey[400] : Colors.grey[700],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        AppLocalizations.of(context)!.startANewChatToGetStarted,
                        style: TextStyle(
                          fontSize: 14,
                          color: widget.isDark ? Colors.grey[600] : Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )

          // ── Conversation list (lazy builder — no eager Column) ───────
          else
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: hPad),
              sliver: SliverList.builder(
                itemCount: _conversations.length,
                itemBuilder: (context, index) {
                  return RepaintBoundary(
                    child: _buildConversationItem(_conversations[index]),
                  );
                },
              ),
            ),

          // ── Bottom spacing for dock ──────────────────────────────────
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
    );
  }

  void _showUserSearchModal() {
    setState(() {
      _isModalOpen = true;
    });

    bool chatOpened = false;

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      useRootNavigator: true,
      child: FindUsersModal(
        isDark: widget.isDark,
        onStartChat: (username, name) {
          chatOpened = true;
          
          // Close Find Users Modal
          Navigator.pop(context);
          
          // Open Chat Modal after a short delay
          Future.delayed(const Duration(milliseconds: 150), () {
            if (mounted) {
              TradeRepublicBottomSheet.show(
                context: context,
                showDragHandle: true,
                useRootNavigator: true,
                maxHeight: MediaQuery.of(context).size.height * 0.94,
                child: ChatModal(
                  partnerId: username,
                  partnerName: name,
                  isDark: widget.isDark,
                ),
              ).whenComplete(() {
                if (mounted) {
                  setState(() {
                    _isModalOpen = false;
                  });
                  _loadConversations();
                }
              });
            }
          });
        },
      ),
    ).whenComplete(() {
      if (mounted && !chatOpened) {
        setState(() {
          _isModalOpen = false;
        });
      }
    });
  }

  void _showAndroidOptionsMenu() {
    setState(() {
      _isModalOpen = true;
    });

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: Builder(builder: (BuildContext context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final iconColor = isDark ? Colors.white : Colors.black;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  CupertinoIcons.chat_bubble_2_fill,
                  size: 28,
                  color: iconColor,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context)!.messageOptions,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: iconColor,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Menu items
            TradeRepublicListTile.navigation(
              title: AppLocalizations.of(context)!.findUsers,
              leading: Icon(CupertinoIcons.person_badge_plus, size: 20, color: iconColor),
              onTap: () {
                Navigator.pop(context);
                _showUserSearchModal();
              },
            ),
            TradeRepublicListTile.navigation(
              title: AppLocalizations.of(context)!.blockedUsers,
              leading: Icon(CupertinoIcons.slash_circle, size: 20, color: iconColor),
              onTap: () {
                Navigator.pop(context);
                _showBlockedUsersModal();
              },
            ),
            TradeRepublicListTile.navigation(
              title: AppLocalizations.of(context)!.deletedChats,
              leading: Icon(CupertinoIcons.trash, size: 20, color: iconColor),
              onTap: () {
                Navigator.pop(context);
                _showDeletedChatsModal();
              },
            ),

            const TradeRepublicDivider(),

            TradeRepublicListTile.navigation(
              title: AppLocalizations.of(context)!.refresh,
              leading: Icon(CupertinoIcons.arrow_clockwise, size: 20, color: iconColor),
              onTap: () {
                Navigator.pop(context);
                _loadConversations();
              },
            ),

            SizedBox(height: MediaQuery.of(context).viewInsets.bottom + 16),
          ],
        );
      }),
    ).whenComplete(() {
      if (mounted) {
        setState(() {
          _isModalOpen = false;
        });
      }
    });
  }

  void _showBlockedUsersModal() {
    setState(() {
      _isModalOpen = true;
    });

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      useRootNavigator: true,
      child: BlockedUsersModal(isDark: widget.isDark),
    ).whenComplete(() {
      if (mounted) {
        setState(() {
          _isModalOpen = false;
        });
      }
    });
  }

  void _showDeletedChatsModal() {
    setState(() {
      _isModalOpen = true;
    });

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      useRootNavigator: true,
      child: DeletedChatsModal(isDark: widget.isDark),
    ).whenComplete(() {
      if (mounted) {
        setState(() {
          _isModalOpen = false;
        });
        // Reload conversations to show restored chats
        _loadConversations();
      }
    });
  }
}

