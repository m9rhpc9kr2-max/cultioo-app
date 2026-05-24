import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_config.dart';
import '../services/storage_service.dart';
import '../services/device_storage.dart';
import '../services/api_service.dart';
import '../services/app_localizations.dart';
import '../services/trade_republic_widgets.dart';
import '../services/cultioo_spinner.dart';

class ChatModal extends StatefulWidget {
  final String partnerId;
  final String partnerName;
  final bool isDark;
  final String? initialProfileImage;

  const ChatModal({
    super.key,
    required this.partnerId,
    required this.partnerName,
    required this.isDark,
    this.initialProfileImage,
  });

  @override
  State<ChatModal> createState() => _ChatModalState();
}

class _ChatModalState extends State<ChatModal> with TickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();
  final FocusNode _messageFocusNode = FocusNode(); // Added for input animations

  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  bool _isBlocked = false;
  String? _currentUsername;
  String? _partnerProfileImage; // Partner's profile image URL (pre-loaded from overview or fetched)

  // File preview functionality
  final List<Map<String, dynamic>> _selectedFiles = [];
  static const int _maxFiles = 2;

  late AnimationController _messageAnimationController;
  late AnimationController
  _inputAnimationController; // New animation controller for input
  late AnimationController _appearanceAnimationController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  bool get _isGroupConversation =>
      widget.partnerId.toLowerCase().startsWith('group:');

  String? _usernameFromJwt(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final map = json.decode(payload) as Map<String, dynamic>;
      final user = map['username']?.toString().trim();
      return (user != null && user.isNotEmpty) ? user : null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _resolveAuthToken() async {
    // Keep chat auth in sync with the rest of the app.
    final inMemory = await ApiService.getToken();
    if (inMemory != null && inMemory.isNotEmpty) return inMemory;

    final access = await DeviceStorage.getString('access_token');
    if (access != null && access.isNotEmpty) return access;

    final auth = await DeviceStorage.getString('auth_token');
    if (auth != null && auth.isNotEmpty) return auth;

    return null;
  }

  Map<String, String> _authHeaders(String token) {
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      if ((_currentUsername ?? '').isNotEmpty) 'X-Username': _currentUsername!,
    };
  }

  String _normalizeFileUrl(String? rawUrl) {
    final raw = (rawUrl ?? '').trim();
    if (raw.isEmpty) return '';

    // Defensive cleanup: dev tools / logs can accidentally append file refs
    // like "...png@cultioo_app/...". Keep only the actual URL/path part.
    String cleaned = raw;
    final markerIndex = cleaned.indexOf('@cultioo_app/');
    if (markerIndex > 0) {
      cleaned = cleaned.substring(0, markerIndex).trim();
    }

    final parsed = Uri.tryParse(cleaned);
    if (parsed != null &&
        (parsed.hasScheme && (parsed.scheme == 'http' || parsed.scheme == 'https'))) {
      return parsed.toString();
    }

    final noLeadingSlash =
        cleaned.startsWith('/') ? cleaned.substring(1) : cleaned;
    return '${AppConfig.baseUrl}/$noLeadingSlash';
  }

  List<String> _buildFileUrlCandidates(String? rawUrl) {
    final normalized = _normalizeFileUrl(rawUrl);
    if (normalized.isEmpty) return const [];

    final candidates = <String>[normalized];

    try {
      final uri = Uri.parse(normalized);
      final path = uri.path;
      if (path.contains('/backend/uploads/')) {
        candidates.add(
          uri
              .replace(
                path: path.replaceFirst('/backend/uploads/', '/uploads/'),
              )
              .toString(),
        );
      } else if (path.contains('/uploads/')) {
        candidates.add(
          uri
              .replace(
                path: path.replaceFirst('/uploads/', '/backend/uploads/'),
              )
              .toString(),
        );
      }
    } catch (_) {
      // Keep normalized candidate only.
    }

    final unique = <String>[];
    final seen = <String>{};
    for (final url in candidates) {
      final clean = url.trim();
      if (clean.isEmpty || seen.contains(clean)) continue;
      seen.add(clean);
      unique.add(clean);
    }
    return unique;
  }

  @override
  void initState() {
    super.initState();
    // Pre-populate profile image passed from the conversations list
    if (widget.initialProfileImage != null && widget.initialProfileImage!.isNotEmpty) {
      _partnerProfileImage = widget.initialProfileImage;
    }

    // Initialize animations
    _messageAnimationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    // Input field animation controller
    _inputAnimationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    // Appearance animation controller
    _appearanceAnimationController = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(begin: Offset.zero, end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _appearanceAnimationController,
            curve: Curves.easeOutCubic,
          ),
        );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _appearanceAnimationController,
        curve: Curves.easeOut,
      ),
    );

    // Start appearance animation
    _appearanceAnimationController.forward();

    // Focus listener for input animations
    _messageFocusNode.addListener(() {
      setState(() {});

      if (_messageFocusNode.hasFocus) {
        _inputAnimationController.forward();
      } else {
        _inputAnimationController.reverse();
      }
    });

    _initializeChat();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _messageFocusNode.dispose(); // Dispose focus node
    _messageAnimationController.dispose();
    _inputAnimationController.dispose(); // Dispose input animation controller
    _appearanceAnimationController.dispose();
    super.dispose();
  }

  Future<void> _initializeChat() async {
    try {
      final token = await _resolveAuthToken();
      if (token == null || token.isEmpty) {
        print('❌ No auth token found during chat init');
        if (!mounted) return;
        setState(() => _isLoading = false);
        TopNotification.error(
          context,
          AppLocalizations.of(context)!.pleaseLoginAgain,
        );
        return;
      }

      _currentUsername =
          (await DeviceStorage.getString('username'))?.trim();
      _currentUsername ??= ApiService.currentUsername?.trim();
      _currentUsername ??= _usernameFromJwt(token);

      if (_currentUsername == null || _currentUsername!.isEmpty) {
        // Don't block loading when username is unavailable locally.
        // Auth is token-based; conversation messages can still be loaded.
        print('❌ No current username found');
      }

      await _loadMessages();
      if (!_isGroupConversation) {
        await _checkBlockStatus();
      } else {
        _isBlocked = false;
      }
      await _loadPartnerInfo();
    } catch (e) {
      //print('❌ Error initializing chat: $e');
    }
  }

  Future<void> _loadMessages() async {
    try {
      if (!mounted) return;
      setState(() => _isLoading = true);

      final token = await _resolveAuthToken();

      if (token == null) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        TopNotification.error(
          context,
          AppLocalizations.of(context)!.pleaseLoginAgain,
        );
        return;
      }

      final response = await http.get(
        Uri.parse(
          '${AppConfig.apiUrl}/messages/conversations/${widget.partnerId}/messages',
        ),
        headers: _authHeaders(token),
      );

      //print('📨 Messages response status: ${response.statusCode}');
      //print('📨 Messages response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          if (!mounted) return;
          setState(() {
            _messages = List<Map<String, dynamic>>.from(data['data'] ?? []);
            _isLoading = false;
          });

          // Debug: Print all messages to see their structure
          print('✅ Loaded ${_messages.length} messages');
          for (int i = 0; i < _messages.length; i++) {
            final msg = _messages[i];
            print(
              '📨 Message $i: type=${msg['message_type']}, content=${msg['content']}, file_url=${msg['file_url']}, fileUrl=${msg['fileUrl']}',
            );
          }

          _scrollToBottom();
        } else {
          throw Exception(data['message'] ?? AppLocalizations.of(context)!.failedToLoadMessages);
        }
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error loading messages: $e');
      if (!mounted) return;
      setState(() {
        _messages = [];
        _isLoading = false;
      });
    }
  }

  Future<void> _checkBlockStatus() async {
    try {
      final token = await _resolveAuthToken();

      if (token == null) {
        print('❌ No auth token found for block status check');
        return;
      }

      final response = await http.get(
        Uri.parse('${AppConfig.apiUrl}/users/blocked/${widget.partnerId}'),
        headers: _authHeaders(token),
      );

      print('🔍 Block status response: ${response.statusCode}');
      print('🔍 Block status body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          if (!mounted) return;
          setState(() => _isBlocked = data['is_blocked'] ?? false);
          print('🔍 User ${widget.partnerId} is blocked: $_isBlocked');
        }
      } else {
        print('❌ Failed to check block status: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error checking block status: $e');
      // Don't show error to user, just continue with unblocked state
      if (!mounted) return;
      setState(() => _isBlocked = false);
    }
  }

  Future<void> _loadPartnerInfo() async {
    try {
      if (_isGroupConversation) return;

      final token = await _resolveAuthToken();

      if (token == null) {
        print('❌ No auth token found for loading partner info');
        return;
      }

      // Try to get user info from the conversations endpoint
      final response = await http.get(
        Uri.parse('${AppConfig.apiUrl}/messages/conversations'),
        headers: _authHeaders(token),
      );

      print('📱 Partner info response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final conversations = data['data'] as List;

          // Find the conversation with this partner
          final partnerConversation = conversations.firstWhere(
            (conv) => conv['conversation_id'] == widget.partnerId,
            orElse: () => null,
          );

          if (partnerConversation != null &&
              partnerConversation['profile_image'] != null) {
            if (!mounted) return;
            setState(() {
              _partnerProfileImage = partnerConversation['profile_image'];
            });
            print('✅ Loaded partner profile image: $_partnerProfileImage');
          }
        }
      }
    } catch (e) {
      print('❌ Error loading partner info: $e');
      // Don't show error to user, just continue without profile image
    }
  }

  Future<void> _sendMessage() async {
    print('🔵 _sendMessage called');
    final messageText = _messageController.text.trim();
    print('🔵 Message text: "$messageText"');
    print('🔵 Selected files: ${_selectedFiles.length}');
    print('🔵 Is sending: $_isSending');

    if ((messageText.isEmpty && _selectedFiles.isEmpty) || _isSending) {
      print('❌ Returning early - empty message or already sending');
      return;
    }

    if (!mounted) return;
    setState(() => _isSending = true);

    try {
      final token = await _resolveAuthToken();

      if (token == null) {
        print('❌ No auth token found');
        throw Exception('No auth token found');
      }

      print('✅ Auth token found');

      // Send text message first if there is text
      if (messageText.isNotEmpty) {
        print('📤 Sending text message...');
        await _sendTextMessage(messageText, token);
      }

      // Send each selected file
      for (final fileData in _selectedFiles) {
        final file = fileData['file'] as File;
        final messageType = fileData['type'] as String;
        await _sendFileMessage(file, token, messageType);
      }

      // Clear input and selected files
      if (!mounted) return;
      setState(() {
        _messageController.clear();
        _selectedFiles.clear();
      });

      print('✅ Message sent successfully');
      _scrollToBottom();
    } catch (e) {
      print('❌ Error sending message: $e');

      if (mounted) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)!.errorSendingMessage,
        );
      }
    } finally {
      if (!mounted) return;
      setState(() => _isSending = false);
    }
  }

  Future<void> _sendTextMessage(String messageText, String token) async {
    print('📤 _sendTextMessage called');
    print('📤 Message text: "$messageText"');
    print('📤 Partner ID: ${widget.partnerId}');
    print('📤 Current username: $_currentUsername');

    // Add message optimistically to UI
    final optimisticMessage = {
      'id': DateTime.now().millisecondsSinceEpoch,
      'sender_id': _currentUsername,
      'receiver_id': widget.partnerId,
      'content': messageText,
      'message_type': 'text',
      'created_at': DateTime.now().toIso8601String(),
      'current_user_id': _currentUsername,
      'isPending': true,
    };

    if (!mounted) return;
    setState(() {
      _messages.add(optimisticMessage);
    });

    _scrollToBottom();

    final url =
        '${AppConfig.apiUrl}/messages/conversations/${widget.partnerId}/messages';
    print('📤 API URL: $url');

    final requestBody = {'message_text': messageText, 'message_type': 'text'};
    print('📤 Request body: $requestBody');

    final response = await http.post(
      Uri.parse(url),
      headers: _authHeaders(token),
      body: json.encode(requestBody),
    );

    print('📤 Response status: ${response.statusCode}');
    print('📤 Response body: ${response.body}');

    if (response.statusCode == 201) {
      final data = json.decode(response.body);
      print('📤 Response data: $data');

      if (data['success'] == true) {
        print('✅ Message sent successfully');
        // Remove pending status from the specific text message
        if (!mounted) return;
        setState(() {
          final index = _messages.indexWhere(
            (msg) =>
                msg['isPending'] == true &&
                msg['content'] == messageText &&
                msg['message_type'] == 'text',
          );
          if (index != -1) {
            _messages[index].remove('isPending');
            _messages[index]['id'] = data['messageId'];
            print('✅ Updated message at index $index');
          }
        });
      }
    } else {
      print('❌ Failed to send message - Status: ${response.statusCode}');
      print('❌ Response body: ${response.body}');

      // Remove specific optimistic text message on error
      if (!mounted) return;
      setState(() {
        _messages.removeWhere(
          (msg) =>
              msg['isPending'] == true &&
              msg['content'] == messageText &&
              msg['message_type'] == 'text',
        );
      });
      throw Exception(
        'Failed to send message - Status: ${response.statusCode}, Body: ${response.body}',
      );
    }
  }

  /// Multipart upload to backend: stores file and creates the message in one step.
  /// Use on desktop where Firebase Auth/Storage is unreliable; also as mobile fallback.
  Future<({int messageId, String fileUrl})?> _uploadChatFileViaBackend(
    File file,
    String fileName,
    String messageType,
    String token,
  ) async {
    try {
      final uri = Uri.parse(
        '${AppConfig.apiUrl}/messages/conversations/${widget.partnerId}/messages/file',
      );
      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer $token';
      if ((_currentUsername ?? '').isNotEmpty) {
        request.headers['X-Username'] = _currentUsername!;
      }
      request.fields['message_type'] = messageType;
      request.files.add(
        await http.MultipartFile.fromPath('file', file.path, filename: fileName),
      );

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);

      print('📤 Backend file upload: ${response.statusCode} ${response.body}');

      if (response.statusCode != 201) return null;

      final data = json.decode(response.body) as Map<String, dynamic>;
      if (data['success'] != true) return null;

      final dynamic mid = data['messageId'];
      if (mid == null) return null;
      final int messageId = mid is int ? mid : (mid as num).toInt();

      String? fileUrl = data['fileUrl'] as String?;
      if (fileUrl == null || fileUrl.isEmpty) return null;
      if (fileUrl.startsWith('/')) {
        fileUrl = '${AppConfig.baseUrl}$fileUrl';
      } else if (!fileUrl.startsWith('http://') &&
          !fileUrl.startsWith('https://')) {
        fileUrl = '${AppConfig.baseUrl}/$fileUrl';
      }

      return (messageId: messageId, fileUrl: fileUrl);
    } catch (e) {
      print('❌ Backend file upload error: $e');
      return null;
    }
  }

  Future<void> _sendFileMessage(
    File file,
    String token,
    String messageType,
  ) async {
    final fileName = file.path.split('/').last;

    // Add optimistic message
    final optimisticMessage = {
      'id': DateTime.now().millisecondsSinceEpoch,
      'sender_id': _currentUsername,
      'receiver_id': widget.partnerId,
      'content': fileName,
      'message_type': messageType,
      'created_at': DateTime.now().toIso8601String(),
      'current_user_id': _currentUsername,
      'isPending': true,
      'local_file_path': file.path, // For preview while pending
    };

    if (!mounted) return;
    setState(() => _messages.add(optimisticMessage));
    _scrollToBottom();

    try {
      late final String downloadUrl;
      late final int serverMessageId;

      // Prefer backend multipart first on all platforms: server uploads to GCS
      // (Firebase bucket) and stores a stable HTTPS URL in the DB for web + other apps.
      print('📤 Uploading file via API (server / GCS)...');
      final backendFirst = await _uploadChatFileViaBackend(
        file,
        fileName,
        messageType,
        token,
      );
      if (backendFirst != null) {
        downloadUrl = backendFirst.fileUrl;
        serverMessageId = backendFirst.messageId;
      } else {
        print('⚠️ Server upload failed, trying Firebase Storage + URL endpoint...');
        final String folder = 'chat/${_currentUsername}_${widget.partnerId}';
        final String? firebaseUrl = await StorageService.uploadImage(
          file: file,
          folder: folder,
        );
        if (firebaseUrl == null) {
          throw Exception('Failed to upload file (server and Firebase)');
        }
        final response = await http.post(
          Uri.parse(
            '${AppConfig.apiUrl}/messages/conversations/${widget.partnerId}/messages/url',
          ),
          headers: _authHeaders(token),
          body: json.encode({
            'message_type': messageType,
            'file_url': firebaseUrl,
            'file_name': fileName,
          }),
        );
        print('📤 File message response: ${response.statusCode}');
        print('📤 File message body: ${response.body}');
        if (response.statusCode != 201) {
          throw Exception(
            'Failed to save message - Status: ${response.statusCode}',
          );
        }
        final data = json.decode(response.body) as Map<String, dynamic>;
        if (data['success'] != true) {
          throw Exception('Failed to save message: ${data['message']}');
        }
        final dynamic mid = data['messageId'];
        serverMessageId = mid is int ? mid : (mid as num).toInt();
        downloadUrl = firebaseUrl;
      }

      if (!mounted) return;
      setState(() {
        final index = _messages.indexWhere(
          (msg) =>
              msg['isPending'] == true &&
              msg['content'] == fileName &&
              msg['message_type'] == messageType,
        );
        print('📤 Updating optimistic message at index: $index');
        if (index != -1) {
          _messages[index].remove('isPending');
          _messages[index].remove('local_file_path');
          _messages[index]['id'] = serverMessageId;
          _messages[index]['file_url'] = downloadUrl;
          print('📤 Updated message: ${_messages[index]}');
        } else {
          print('❌ Could not find optimistic message to update');
        }
      });
    } catch (e) {
      print('❌ Error sending file message: $e');
      if (!mounted) rethrow;
      setState(() {
        _messages.removeWhere(
          (msg) =>
              msg['isPending'] == true &&
              msg['content'] == fileName &&
              msg['message_type'] == messageType,
        );
      });
      rethrow;
    }
  }

  Future<void> _addImageToPreview() async {
    if (_selectedFiles.length >= _maxFiles) {
      _showErrorSnackBar(
        AppLocalizations.of(context)!.maximumFilesAllowed(_maxFiles),
      );
      return;
    }

    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (image == null) return;

      if (!mounted) return;
      setState(() {
        _selectedFiles.add({
          'file': File(image.path),
          'name': image.path.split('/').last,
          'type': 'image',
        });
      });
    } catch (e) {
      //print('❌ Error picking image: $e');
      _showErrorSnackBar(AppLocalizations.of(context)!.errorSelectingImage);
    }
  }

  Future<void> _addPdfToPreview() async {
    if (_selectedFiles.length >= _maxFiles) {
      _showErrorSnackBar(
        AppLocalizations.of(context)!.maximumFilesAllowed(_maxFiles),
      );
      return;
    }

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        if (!mounted) return;
        setState(() {
          _selectedFiles.add({
            'file': file,
            'name': file.path.split('/').last,
            'type': 'pdf',
          });
        });
      }
    } catch (e) {
      //print('❌ Error picking PDF: $e');
      _showErrorSnackBar(AppLocalizations.of(context)!.errorSelectingPdfFile);
    }
  }

  void _removeFileFromPreview(int index) {
    if (!mounted) return;
    setState(() {
      _selectedFiles.removeAt(index);
    });
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      TopNotification.error(context, message);
    }
  }

  void _showSuccessSnackBar(String message) {
    if (mounted) {
      TopNotification.success(context, message);
    }
  }

  Future<void> _downloadFile(String fileUrl, String fileName) async {
    try {
      print('📥 Starting download: $fileName');
      print('📥 File URL: $fileUrl');

      // Check Android version and request appropriate permissions
      if (Platform.isAndroid) {
        // For Android 13+, request specific media permissions
        if (fileName.toLowerCase().endsWith('.png') ||
            fileName.toLowerCase().endsWith('.jpg') ||
            fileName.toLowerCase().endsWith('.jpeg') ||
            fileName.toLowerCase().endsWith('.gif') ||
            fileName.toLowerCase().endsWith('.webp')) {
          final imageStatus = await Permission.photos.request();
          print('📥 Photos permission status: $imageStatus');
          if (!imageStatus.isGranted) {
            _showErrorSnackBar(
              AppLocalizations.of(context)!.photoStoragePermissionRequired,
            );
            return;
          }
        } else {
          // For documents, try multiple permission strategies
          var hasPermission = false;

          // Try storage permission first
          final storageStatus = await Permission.storage.request();
          print('📥 Storage permission status: $storageStatus');

          if (storageStatus.isGranted) {
            hasPermission = true;
          } else {
            // Try manage external storage for Android 11+
            final manageStatus = await Permission.manageExternalStorage
                .request();
            print('📥 Manage storage permission: $manageStatus');

            if (manageStatus.isGranted) {
              hasPermission = true;
            } else {
              // Try requesting all at once
              Map<Permission, PermissionStatus> statuses = await [
                Permission.storage,
                Permission.photos,
                Permission.manageExternalStorage,
              ].request();

              if (statuses[Permission.storage]?.isGranted == true ||
                  statuses[Permission.photos]?.isGranted == true ||
                  statuses[Permission.manageExternalStorage]?.isGranted ==
                      true) {
                hasPermission = true;
              }
            }
          }

          if (!hasPermission) {
            _showPermissionDialog();
            return;
          }
        }
      }

      _showSuccessSnackBar(
        AppLocalizations.of(context)!.downloadingFile(fileName),
      );

      // Get the downloads directory
      Directory? downloadsDirectory;
      if (Platform.isAndroid) {
        // Try different Android download paths
        try {
          // First try the public Downloads directory
          downloadsDirectory = Directory('/storage/emulated/0/Download');
          if (!await downloadsDirectory.exists()) {
            // Fallback to app-specific external storage
            final externalDir = await getExternalStorageDirectory();
            if (externalDir != null) {
              downloadsDirectory = Directory('${externalDir.path}/Download');
              if (!await downloadsDirectory.exists()) {
                await downloadsDirectory.create(recursive: true);
              }
            } else {
              // Final fallback to app documents
              downloadsDirectory = await getApplicationDocumentsDirectory();
            }
          }
        } catch (e) {
          print('📥 Error accessing Android downloads directory: $e');
          downloadsDirectory = await getApplicationDocumentsDirectory();
        }
      } else {
        downloadsDirectory = await getDownloadsDirectory();
      }

      print('📥 Downloads directory: ${downloadsDirectory?.path}');

      if (downloadsDirectory == null) {
        _showErrorSnackBar(
          AppLocalizations.of(context)!.couldNotAccessDownloadsDirectory,
        );
        return;
      }

      final downloadCandidates = _buildFileUrlCandidates(fileUrl);
      if (downloadCandidates.isEmpty) {
        _showErrorSnackBar(AppLocalizations.of(context)!.couldNotLoadImage);
        return;
      }

      http.Response? response;
      for (final downloadUrl in downloadCandidates) {
        print('📥 Downloading from: $downloadUrl');
        try {
          final r = await http.get(Uri.parse(downloadUrl));
          print('📥 Download response status: ${r.statusCode}');
          if (r.statusCode == 200) {
            response = r;
            break;
          }
        } catch (e) {
          print('📥 Download attempt failed: $e');
        }
      }

      if (response != null && response.statusCode == 200) {
        print('📥 Download response headers: ${response.headers}');
        // Create unique filename if file already exists
        String finalFileName = fileName;
        File file = File('${downloadsDirectory.path}/$finalFileName');
        int counter = 1;

        while (await file.exists()) {
          final extension = fileName.contains('.')
              ? fileName.split('.').last
              : '';
          final nameWithoutExt = fileName.contains('.')
              ? fileName.substring(0, fileName.lastIndexOf('.'))
              : fileName;
          finalFileName = extension.isNotEmpty
              ? '${nameWithoutExt}_$counter.$extension'
              : '${nameWithoutExt}_$counter';
          file = File('${downloadsDirectory.path}/$finalFileName');
          counter++;
        }

        print('📥 Saving to: ${file.path}');

        await file.writeAsBytes(response.bodyBytes);
        print('📥 File saved successfully');

        // Show success message with file location
        final shortPath = file.path.contains('/Download/')
            ? 'Downloads/$finalFileName'
            : file.path
                  .split('/')
                  .skip(file.path.split('/').length - 2)
                  .join('/');
        _showSuccessSnackBar(
          AppLocalizations.of(context)!.downloadedToPath(shortPath),
        );

        // Notify media scanner on Android
        if (Platform.isAndroid) {
          try {
            await Process.run('am', [
              'broadcast',
              '-a',
              'android.intent.action.MEDIA_SCANNER_SCAN_FILE',
              '-d',
              'file://${file.path}',
            ]);
            print('📥 Media scanner notified');
          } catch (e) {
            print('📥 Could not notify media scanner: $e');
          }
        }
      } else {
        final code = response?.statusCode ?? 0;
        print('❌ Download failed with status: $code');
        _showErrorSnackBar(
          AppLocalizations.of(
            context,
          )!.failedToDownloadFile(code),
        );
      }
    } catch (e) {
      print('❌ Error downloading file: $e');
      _showErrorSnackBar('Error downloading file: ${e.toString()}');
    }
  }

  void _showPermissionDialog() {
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(CupertinoIcons.folder, size: 48, color: Colors.orange),

          const SizedBox(height: 16),

          Text(
            AppLocalizations.of(context)!.storagePermissionNeeded.toUpperCase(),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: widget.isDark ? Colors.white : Colors.black,
              letterSpacing: 0.4,
            ),
          ),

          const SizedBox(height: 12),

          Text(
            AppLocalizations.of(
              context,
            )!.toDownloadFilesThisAppNeedsPermissionToAcc,
            style: TextStyle(
              fontSize: 16,
              color: widget.isDark ? Colors.grey[300] : Colors.grey[700],
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 24),

          Row(
            children: [
              Expanded(
                child: TradeRepublicButton(
                  label: AppLocalizations.of(context)!.cancel,
                  onPressed: () => Navigator.pop(context),
                  isSecondary: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TradeRepublicButton(
                  label: AppLocalizations.of(context)!.openSettings,
                  onPressed: () async {
                    Navigator.pop(context);
                    final opened = await openAppSettings();
                    if (!opened) {
                      _showErrorSnackBar(
                        AppLocalizations.of(
                          context,
                        )!.couldNotOpenAppSettingsPleaseEnableStorage,
                      );
                    } else {
                      _showSuccessSnackBar(
                        AppLocalizations.of(
                          context,
                        )!.pleaseEnableStoragePermissionsAndTryDownload,
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showImageViewer(String rawImageUrl, String fileName) {
    final candidates = _buildFileUrlCandidates(rawImageUrl);
    if (candidates.isEmpty) return;

    Widget buildViewerImage(int index) {
      if (index >= candidates.length) {
        return Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                CupertinoIcons.exclamationmark_triangle,
                size: 64,
                color: widget.isDark ? Colors.grey[400] : Colors.grey[600],
              ),
              const SizedBox(height: 16),
              Text(
                AppLocalizations.of(context)!.couldNotLoadImage,
                style: TextStyle(
                  color: widget.isDark ? Colors.grey[400] : Colors.grey[600],
                  fontSize: 16,
                ),
              ),
            ],
          ),
        );
      }
      final url = candidates[index];
      return Image.network(
        url,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          print('❌ Image viewer error: $error');
          print('❌ Attempted URL: $url');
          if (index + 1 < candidates.length) {
            return buildViewerImage(index + 1);
          }
          return Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  CupertinoIcons.exclamationmark_triangle,
                  size: 64,
                  color: widget.isDark ? Colors.grey[400] : Colors.grey[600],
                ),
                const SizedBox(height: 16),
                Text(
                  AppLocalizations.of(context)!.couldNotLoadImage,
                  style: TextStyle(
                    color: widget.isDark ? Colors.grey[400] : Colors.grey[600],
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          );
        },
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CultiooLoadingIndicator(),
                const SizedBox(height: 16),
                Text(
                  AppLocalizations.of(context)!.loadingImage,
                  style: TextStyle(
                    color: widget.isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      maxHeight: MediaQuery.of(context).size.height * 0.9,
      child: Column(
        children: [
          // Header with title and close button
          Container(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    fileName,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: widget.isDark ? Colors.white : Colors.black,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // Image
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(25),
                  child: buildViewerImage(0),
                ),
              ),
            ),
          ),

          // Action buttons
          Container(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Expanded(
                  child: TradeRepublicButton(
                    label: AppLocalizations.of(context)!.download,
                    icon: const Icon(
                      CupertinoIcons.arrow_down_circle,
                      color: Colors.white,
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      _downloadFile(rawImageUrl, fileName);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TradeRepublicButton(
                    label: AppLocalizations.of(context)!.open,
                    icon: const Icon(CupertinoIcons.globe, color: Colors.white),
                    onPressed: () async {
                      Navigator.pop(context);
                      var opened = false;
                      for (final c in candidates) {
                        final url = Uri.tryParse(c);
                        if (url != null && await canLaunchUrl(url)) {
                          await launchUrl(
                            url,
                            mode: LaunchMode.externalApplication,
                          );
                          opened = true;
                          break;
                        }
                      }
                      if (!opened) {
                        _showErrorSnackBar(
                          AppLocalizations.of(
                            context,
                          )!.couldNotOpenImageInBrowser,
                        );
                      }
                    },
                    isSecondary: true,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showPdfViewer(String pdfUrl, String fileName) {
    final fullPdfUrl = _normalizeFileUrl(pdfUrl);

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(CupertinoIcons.doc_text_fill, size: 64, color: Colors.red),
          const SizedBox(height: 16),

          Text(
            fileName,
            style: TextStyle(
              color: widget.isDark ? Colors.white : Colors.black,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),

          Text(
            AppLocalizations.of(context)!.pdfDocument.toUpperCase(),
            style: TextStyle(
              color: widget.isDark ? Colors.white : Colors.black,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 8),

          Text(
            AppLocalizations.of(context)!.chooseAnActionForThisPdfFile,
            style: TextStyle(
              color: widget.isDark ? Colors.grey[400] : Colors.grey[600],
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 24),

          Row(
            children: [
              Expanded(
                child: TradeRepublicButton(
                  label: AppLocalizations.of(context)!.download,
                  icon: const Icon(
                    CupertinoIcons.arrow_down_circle,
                    color: Colors.white,
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    _downloadFile(fullPdfUrl, fileName);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TradeRepublicButton(
                  label: AppLocalizations.of(context)!.open,
                  icon: const Icon(CupertinoIcons.globe, color: Colors.white),
                  onPressed: () async {
                    Navigator.pop(context);
                    final url = Uri.parse(fullPdfUrl);
                    if (await canLaunchUrl(url)) {
                      await launchUrl(
                        url,
                        mode: LaunchMode.externalApplication,
                      );
                    } else {
                      _showErrorSnackBar(
                        AppLocalizations.of(context)!.couldNotOpenPdf,
                      );
                    }
                  },
                  isSecondary: true,
                ),
              ),
            ],
          ),

        ],
      ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showBlockDialog() {
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(CupertinoIcons.slash_circle, size: 48, color: Colors.red),

          const SizedBox(height: 16),

          Text(
            AppLocalizations.of(context)!.blockUser.toUpperCase(),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: widget.isDark ? Colors.white : Colors.black,
              letterSpacing: 0.4,
            ),
          ),

          const SizedBox(height: 12),

          Text(
            'Do you want to block ${widget.partnerName}? You will no longer receive messages from this user.',
            style: TextStyle(
              fontSize: 16,
              color: widget.isDark ? Colors.grey[300] : Colors.grey[700],
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 24),

          Row(
            children: [
              Expanded(
                child: TradeRepublicButton(
                  label: AppLocalizations.of(context)!.cancel,
                  onPressed: () => Navigator.pop(context),
                  isSecondary: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TradeRepublicButton(
                  label: AppLocalizations.of(context)!.block,
                  onPressed: () {
                    Navigator.pop(context);
                    _blockUser();
                  },
                  isDestructive: true,
                ),
              ),
            ],
          ),

        ],
      ),
    );
  }

  Future<void> _blockUser() async {
    try {
      final token = await _resolveAuthToken();

      if (token == null) {
        throw Exception('No auth token found');
      }

      // Show loading
      if (mounted) {
        TopNotification.success(context, 'Blocking ${widget.partnerName}...');
      }

      // Call block API
      final response = await http.post(
        Uri.parse('${AppConfig.apiUrl}/users/block'),
        headers: _authHeaders(token),
        body: json.encode({'blocked_user_id': widget.partnerId}),
      );

      print('🚫 Block response status: ${response.statusCode}');
      print('🚫 Block response body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          if (!mounted) return;
          setState(() => _isBlocked = true);

          if (mounted) {
            TopNotification.error(
              context,
              '${widget.partnerName} has been blocked',
            );
          }
        } else {
          throw Exception(data['message'] ?? 'Failed to block user');
        }
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error blocking user: $e');
      _showErrorSnackBar(
        AppLocalizations.of(context)!.errorBlockingUser(e.toString()),
      );
    }
  }

  Future<void> _unblockUser() async {
    try {
      final token = await _resolveAuthToken();

      if (token == null) {
        throw Exception('No auth token found');
      }

      // Show loading
      if (mounted) {
        TopNotification.success(context, 'Unblocking ${widget.partnerName}...');
      }

      // Call unblock API
      final response = await http.delete(
        Uri.parse('${AppConfig.apiUrl}/users/unblock/${widget.partnerId}'),
        headers: _authHeaders(token),
      );

      print('✅ Unblock response status: ${response.statusCode}');
      print('✅ Unblock response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          if (!mounted) return;
          setState(() => _isBlocked = false);

          if (mounted) {
            TopNotification.success(
              context,
              '${widget.partnerName} has been unblocked',
            );
          }

          // Reload messages after unblocking
          _loadMessages();
        } else {
          throw Exception(data['message'] ?? 'Failed to unblock user');
        }
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error unblocking user: $e');
      _showErrorSnackBar(
        AppLocalizations.of(context)!.errorUnblockingUser(e.toString()),
      );
    }
  }

  void _showOptionsBottomSheet() {
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildOptionTile(
            icon: CupertinoIcons.photo,
            title: AppLocalizations.of(context)!.sendImage,
            onTap: () {
              Navigator.pop(context);
              _addImageToPreview();
            },
          ),

          _buildOptionTile(
            icon: CupertinoIcons.doc_text,
            title: AppLocalizations.of(context)!.sendPdf,
            onTap: () {
              Navigator.pop(context);
              _addPdfToPreview();
            },
          ),

          if (!_isGroupConversation)
            _buildOptionTile(
              icon: _isBlocked
                  ? CupertinoIcons.person_badge_plus
                  : CupertinoIcons.slash_circle,
              title: _isBlocked
                  ? AppLocalizations.of(context)!.unblockUser
                  : AppLocalizations.of(context)!.blockUser,
              color: _isBlocked ? Colors.green : Colors.red,
              onTap: () {
                Navigator.pop(context);
                if (_isBlocked) {
                  _unblockUser();
                } else {
                  _showBlockDialog();
                }
              },
            ),
        ],
      ),
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? color,
  }) {
    return TradeRepublicListTile(
      title: title.toUpperCase(),
      leading: Icon(
        icon,
        color: color ?? (widget.isDark ? Colors.white : Colors.black),
      ),
      titleColor: color ?? (widget.isDark ? Colors.white : Colors.black),
      onTap: onTap,
      borderRadius: BorderRadius.circular(25),
    );
  }

  String _formatTime(String timestamp) {
    try {
      final DateTime dateTime = DateTime.parse(timestamp);
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inDays > 0) {
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

  Widget _buildMessage(Map<String, dynamic> message, int index) {
    // Verbesserte Logik um zu erkennen wer der aktuelle Benutzer ist
    final messageSenderId = message['sender_id'];
    final currentUserId =
        message['current_user_id']; // Das ist aus der API-Antwort

    // Der Benutzer ist der Sender wenn sender_id dem current_user_id aus der API entspricht
    final isCurrentUser = messageSenderId == currentUserId;

    //print('🔍 Message debug: sender_id=$messageSenderId, current_user_id=$currentUserId, isCurrentUser=$isCurrentUser');

    final messageType = message['message_type'] ?? 'text';
    final isPending = message['isPending'] == true;

    // Debug: Print message info
    print(
      '🔍 Building message: id=${message['id']}, type=$messageType, content=${message['content']}, file_url=${message['file_url']}, fileUrl=${message['fileUrl']}',
    );

    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 300 + (index * 50)),
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset((isCurrentUser ? 30 : -30) * (1 - value), 0),
          child: Opacity(
            opacity: value,
            child: Container(
              margin: EdgeInsets.only(
                left: isCurrentUser ? 60 : 0,
                right: isCurrentUser ? 0 : 60,
                bottom: 12,
              ),
              child: Column(
                crossAxisAlignment: isCurrentUser
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: isCurrentUser
                          ? (widget.isDark ? Colors.white : Colors.black)
                          : (widget.isDark
                                ? Colors.white.withOpacity(0.06)
                                : Colors.black.withOpacity(0.04)),
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (messageType == 'image')
                          _buildImageMessage(message, isCurrentUser)
                        else if (messageType == 'pdf')
                          _buildPdfMessage(message, isCurrentUser)
                        else
                          _buildTextMessage(message, isCurrentUser),

                        if (isCurrentUser && isPending)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 10,
                                  height: 10,
                                  child: CultiooLoadingIndicator(),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Sending...',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: widget.isDark
                                        ? Colors.black.withOpacity(0.4)
                                        : Colors.white.withOpacity(0.6),
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      _formatTime(message['created_at']),
                      style: TextStyle(
                        fontSize: 11,
                        color: widget.isDark
                            ? Colors.white.withOpacity(0.4)
                            : Colors.black.withOpacity(0.4),
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTextMessage(Map<String, dynamic> message, bool isCurrentUser) {
    return Text(
      message['content'] ?? '',
      style: TextStyle(
        color: isCurrentUser
            ? (widget.isDark ? Colors.black : Colors.white)
            : (widget.isDark ? Colors.white : Colors.black),
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 1.5,
        letterSpacing: 0,
      ),
    );
  }

  Widget _buildImageMessage(Map<String, dynamic> message, bool isCurrentUser) {
    final imageUrl = message['file_url'] ?? message['fileUrl'];
    final fileName = message['content'] ?? 'Image';
    final imageCandidates = _buildFileUrlCandidates(imageUrl?.toString());
    final String? fullImageUrl = imageCandidates.isNotEmpty
        ? imageCandidates.first
        : null;

    if (imageUrl != null) {
      print('📸 Image URL debug:');
      print('   - Original: $imageUrl');
      print('   - Candidates: $imageCandidates');
      print('   - Base URL: ${AppConfig.baseUrl}');
    }

    Widget buildImageCandidate(int index) {
      if (index >= imageCandidates.length) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                CupertinoIcons.exclamationmark_triangle,
                size: 40,
                color: widget.isDark ? Colors.grey[400] : Colors.grey[600],
              ),
              const SizedBox(height: 8),
              Text(
                AppLocalizations.of(context)!.couldNotLoadImage,
                style: TextStyle(
                  fontSize: 10,
                  color: widget.isDark ? Colors.grey[400] : Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      }

      final candidateUrl = imageCandidates[index];
      return Image.network(
        candidateUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (context, error, stackTrace) {
          print('❌ Image loading error: $error');
          print('❌ Attempted URL: $candidateUrl');
          if (index + 1 < imageCandidates.length) {
            print('🔁 Trying next image candidate: ${imageCandidates[index + 1]}');
            return buildImageCandidate(index + 1);
          }
          return Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  CupertinoIcons.exclamationmark_triangle,
                  size: 40,
                  color: widget.isDark ? Colors.grey[400] : Colors.grey[600],
                ),
                const SizedBox(height: 8),
                Text(
                  AppLocalizations.of(context)!.couldNotLoadImage,
                  style: TextStyle(
                    fontSize: 10,
                    color: widget.isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        },
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            padding: const EdgeInsets.all(20),
            child: Center(child: CultiooLoadingIndicator()),
          );
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () {
            if (imageUrl != null && imageUrl.toString().trim().isNotEmpty) {
              _showImageViewer(imageUrl.toString(), fileName);
            }
          },
          child: Container(
            constraints: const BoxConstraints(maxWidth: 200, maxHeight: 200),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(
                25,
              ), // Changed to 25px for consistency
              color: widget.isDark ? Colors.grey[700] : Colors.grey[300],
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(
                    25,
                  ), // Changed to 25px for consistency
                  child: fullImageUrl != null
                      ? buildImageCandidate(0)
                      : message['local_file_path'] != null
                      ? Image.file(
                          File(message['local_file_path']),
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              padding: const EdgeInsets.all(20),
                              child: Icon(
                                CupertinoIcons.exclamationmark_triangle,
                                size: 40,
                                color: widget.isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
                              ),
                            );
                          },
                        )
                      : Container(
                          padding: const EdgeInsets.all(20),
                          child: Icon(
                            CupertinoIcons.photo,
                            size: 40,
                            color: widget.isDark
                                ? Colors.grey[400]
                                : Colors.grey[600],
                          ),
                        ),
                ),
                // View overlay when image is loaded
                if (fullImageUrl != null)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(25),
                      ),
                      child: const Icon(
                        CupertinoIcons.fullscreen,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        // Only show filename if it's different from the default filename pattern
        if (message['content'] != null &&
            message['content'].isNotEmpty &&
            !message['content'].toString().toLowerCase().endsWith('.png') &&
            !message['content'].toString().toLowerCase().endsWith('.jpg') &&
            !message['content'].toString().toLowerCase().endsWith('.jpeg') &&
            !message['content'].toString().toLowerCase().endsWith('.gif') &&
            !message['content'].toString().toLowerCase().endsWith('.webp')) ...[
          const SizedBox(height: 8),
          Text(
            message['content'],
            style: TextStyle(
              color: isCurrentUser
                  ? Colors.white70
                  : (widget.isDark ? Colors.grey[300] : Colors.grey[700]),
              fontSize: 14,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPdfMessage(Map<String, dynamic> message, bool isCurrentUser) {
    final pdfUrl = message['file_url'] ?? message['fileUrl'];
    final fileName = message['content'] ?? 'Document';

    final String? fullPdfUrl = pdfUrl != null
        ? _normalizeFileUrl(pdfUrl.toString())
        : null;

    return GestureDetector(
      onTap: () {
        if (fullPdfUrl != null) {
          _showPdfViewer(fullPdfUrl, fileName);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: (isCurrentUser
              ? Colors.white.withOpacity(0.15)
              : (widget.isDark
                    ? Colors.white.withOpacity(0.1)
                    : Colors.black.withOpacity(0.05))),
          borderRadius: BorderRadius.circular(25),
          boxShadow: [
            BoxShadow(
              color: widget.isDark
                  ? Colors.black.withOpacity(0.3)
                  : Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              CupertinoIcons.doc_text_fill,
              color: Colors.red,
              size: 24,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileName,
                    style: TextStyle(
                      color: isCurrentUser
                          ? Colors.white
                          : (widget.isDark ? Colors.white : Colors.black),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    AppLocalizations.of(context)!.tapToView,
                    style: TextStyle(
                      color: isCurrentUser
                          ? Colors.white70
                          : (widget.isDark
                                ? Colors.grey[400]
                                : Colors.grey[600]),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              CupertinoIcons.arrow_up_right_square,
              color: isCurrentUser
                  ? Colors.white70
                  : (widget.isDark ? Colors.grey[400] : Colors.grey[600]),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Material(
          color: Colors.transparent,
          child: SafeArea(
            top: false,
            bottom: false,
            child: Column(
            children: [
              // Header - Minimal style
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    // Back button
                    TradeRepublicButton(
                      icon: const Icon(CupertinoIcons.chevron_back, size: 18),
                      isSecondary: true,
                      width: 44,
                      height: 44,
                      padding: EdgeInsets.zero,
                      borderRadius: BorderRadius.circular(25),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 12),
                    // Minimal avatar
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: (_partnerProfileImage != null && _partnerProfileImage!.isNotEmpty)
                          ? Colors.transparent
                          : (widget.isDark
                              ? const Color(0xFF1C1C1E)
                              : const Color(0xFFF2F2F7)),
                      backgroundImage:
                          _partnerProfileImage != null &&
                              _partnerProfileImage!.isNotEmpty
                          ? (_partnerProfileImage!.startsWith('data:image/')
                              ? MemoryImage(base64Decode(_partnerProfileImage!.split(',')[1])) as ImageProvider
                              : NetworkImage(
                                  _partnerProfileImage!.startsWith('http')
                                      ? _partnerProfileImage!
                                      : '${AppConfig.baseUrl}/${_partnerProfileImage!.startsWith('/') ? _partnerProfileImage!.substring(1) : _partnerProfileImage}',
                                ))
                          : null,
                      child:
                          (_partnerProfileImage == null ||
                              _partnerProfileImage!.isEmpty)
                          ? Text(
                              widget.partnerName[0].toUpperCase(),
                              style: TextStyle(
                                color: widget.isDark
                                    ? Colors.white
                                    : Colors.black,
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.partnerName,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: widget.isDark
                                  ? Colors.white
                                  : Colors.black,
                              letterSpacing: -0.2,
                            ),
                          ),
                          Text(
                            '@${widget.partnerId}',
                            style: TextStyle(
                              fontSize: 12,
                              color: widget.isDark
                                  ? Colors.grey[500]
                                  : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Options button
                    TradeRepublicButton(
                      icon: const Icon(
                        CupertinoIcons.ellipsis,
                        size: 18,
                      ),
                      isSecondary: true,
                      width: 44,
                      height: 44,
                      padding: EdgeInsets.zero,
                      borderRadius: BorderRadius.circular(25),
                      onPressed: _showOptionsBottomSheet,
                    ),
                  ],
                ),
              ),

              // Messages
              Expanded(
                child: _isLoading
                    ? Center(
                        child: CultiooLoadingIndicator(),
                      )
                    : _isBlocked
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              CupertinoIcons.slash_circle,
                              size: 64,
                              color: widget.isDark
                                  ? Colors.grey[600]
                                  : Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              AppLocalizations.of(context)!.userBlocked,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: widget.isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              AppLocalizations.of(
                                context,
                              )!.youHaveBlockedThisUser,
                              style: TextStyle(
                                color: widget.isDark
                                    ? Colors.grey[500]
                                    : Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      )
                    : _messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              CupertinoIcons.chat_bubble,
                              size: 64,
                              color: widget.isDark
                                  ? Colors.grey[600]
                                  : Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              AppLocalizations.of(context)!.noMessagesYet,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: widget.isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              AppLocalizations.of(context)!.sendTheFirstMessage,
                              style: TextStyle(
                                color: widget.isDark
                                    ? Colors.grey[500]
                                    : Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          return _buildMessage(_messages[index], index);
                        },
                      ),
              ),

              // File Preview Area
              if (_selectedFiles.isNotEmpty)
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: widget.isDark
                        ? Colors.transparent
                        : const Color(0xFFF2F2F7),
                    borderRadius: BorderRadius.circular(25),
                    boxShadow: [
                      BoxShadow(
                        color: widget.isDark
                            ? Colors.transparent
                            : Colors.black.withOpacity(0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            CupertinoIcons.paperclip,
                            size: 16,
                            color: widget.isDark
                                ? Colors.white.withOpacity(0.7)
                                : Colors.grey[600],
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Selected files (${_selectedFiles.length}/$_maxFiles):',
                            style: TextStyle(
                              fontSize: 12,
                              color: widget.isDark
                                  ? Colors.white.withOpacity(0.7)
                                  : Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _selectedFiles.asMap().entries.map((entry) {
                          final index = entry.key;
                          final fileData = entry.value;
                          final fileName = fileData['name'] as String;
                          final isImage = fileData['type'] == 'image';

                          return Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: widget.isDark
                                  ? Colors.transparent
                                  : const Color(0xFFF2F2F7),
                              borderRadius: BorderRadius.circular(25),
                              boxShadow: [
                                BoxShadow(
                                  color: widget.isDark
                                      ? Colors.transparent
                                      : Colors.black.withOpacity(0.1),
                                  blurRadius: 10,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isImage
                                      ? CupertinoIcons.photo
                                      : CupertinoIcons.doc_text_fill,
                                  size: 16,
                                  color: isImage ? Colors.blue : Colors.red,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    fileName.length > 20
                                        ? '${fileName.substring(0, 17)}...'
                                        : fileName,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: widget.isDark
                                          ? Colors.white
                                          : Colors.black,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                TradeRepublicButton(
                                  onPressed: () => _removeFileFromPreview(index),
                                  icon: const Icon(
                                    CupertinoIcons.xmark,
                                    size: 10,
                                    color: Colors.white,
                                  ),
                                  backgroundColor: Colors.red,
                                  width: 16,
                                  height: 16,
                                  padding: EdgeInsets.zero,
                                  borderRadius: BorderRadius.circular(25),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),

              // Input Area - Trade Republic Minimal Style
              if (!_isBlocked)
                Container(
                  margin: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: Column(
                    children: [
                      // Top border divider
                      Container(
                        height: 1,
                        color: widget.isDark
                            ? Colors.white.withOpacity(0.08)
                            : Colors.black.withOpacity(0.08),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          // Chat options
                          Container(
                            margin: const EdgeInsets.only(bottom: 4),
                            child: TradeRepublicButton(
                              icon: const Icon(
                                CupertinoIcons.add,
                                size: 16,
                              ),
                              isSecondary: true,
                              width: 44,
                              height: 44,
                              padding: EdgeInsets.zero,
                              borderRadius: BorderRadius.circular(25),
                              onPressed: () {
                                TradeRepublicBottomSheet.show(
                                  context: context,
                                  showDragHandle: true,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      TradeRepublicListTile(
                                        title: AppLocalizations.of(context)!.photo,
                                        leading: Icon(
                                          CupertinoIcons.photo,
                                          color: widget.isDark
                                              ? Colors.white
                                              : Colors.black,
                                        ),
                                        onTap: () {
                                          Navigator.pop(context);
                                          _addImageToPreview();
                                        },
                                      ),
                                      TradeRepublicListTile(
                                        title: AppLocalizations.of(context)!.pdf,
                                        leading: Icon(
                                          CupertinoIcons.doc,
                                          color: widget.isDark
                                              ? Colors.white
                                              : Colors.black,
                                        ),
                                        onTap: () {
                                          Navigator.pop(context);
                                          _addPdfToPreview();
                                        },
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Text input
                          Expanded(
                            child: TradeRepublicTextField(
                              controller: _messageController,
                              hintText: AppLocalizations.of(context)!.typeMessage,
                              maxLines: 4,
                              minLines: 1,
                              focusNode: _messageFocusNode,
                              textInputAction: TextInputAction.newline,
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Send button - CNButton.icon like Cully
                          Container(
                            margin: const EdgeInsets.only(bottom: 4),
                            child: _isSending
                                ? Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: widget.isDark
                                          ? Colors.white.withOpacity(0.06)
                                          : Colors.black.withOpacity(0.04),
                                      borderRadius: BorderRadius.circular(25),
                                    ),
                                    child: Center(
                                      child: SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CultiooLoadingIndicator(),
                                      ),
                                    ),
                                  )
                                : TradeRepublicButton(
                                    onPressed:
                                        _messageController.text.isNotEmpty
                                        ? _sendMessage
                                        : null,
                                    isSecondary: true,
                                    width: 44,
                                    height: 44,
                                    padding: EdgeInsets.zero,
                                    borderRadius: BorderRadius.circular(25),
                                    icon: const Icon(
                                      CupertinoIcons.arrow_up,
                                      size: 16,
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
              ),
            ),
          ),
        ),
    );
  }
}
