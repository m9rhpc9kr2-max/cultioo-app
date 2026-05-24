import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import 'device_storage.dart';

class ApiService {
  // Zentrale URL-Konfiguration verwenden
  static String get baseUrl => AppConfig.apiUrl;

  static String? _accessToken;
  
  // Session ID to prevent race conditions
  static String _currentSessionId = '';

  // HTTP Client with timeouts for better performance
  static const Duration _timeoutDuration = Duration(seconds: 10);

  // Load token from DeviceStorage ONLY for auto-login
  static Future<void> loadTokensForAutoLogin() async {
    try {
      final storedToken = await DeviceStorage.getString('access_token');
      if (storedToken != null && storedToken.isNotEmpty) {
        _accessToken = storedToken;
        print('🔄 Auto-login token loaded from DeviceStorage');
      }
    } catch (e) {
      print('⚠️ Failed to load auto-login token: $e');
    }
  }

  // Check if logged in
  static bool get isLoggedIn {
    if (_accessToken != null) return true;
    // Fallback: Check SharedPreferences synchronously if possible
    return false;
  }

  // Asynchronous check of login status
  static Future<bool> get isLoggedInAsync async {
    if (_accessToken != null) return true;
    try {
      final token = await DeviceStorage.getString('auth_token');
      if (token != null) {
        _accessToken = token;
        return true;
      }
    } catch (e) {
      print('⚠️ Failed to check login status from DeviceStorage: $e');
    }
    return false;
  }

  /// Decodes the [username] claim from the in-memory JWT without a network call.
  /// Returns null if there is no token or the payload cannot be parsed.
  static String? get currentUsername {
    if (_accessToken == null) return null;
    try {
      final parts = _accessToken!.split('.');
      if (parts.length != 3) return null;
      final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final map = json.decode(payload) as Map<String, dynamic>;
      return map['username']?.toString();
    } catch (_) {
      return null;
    }
  }

  // Get token from MEMORY ONLY (DeviceStorage only for auto-login)
  static Future<String?> getToken() async {
    print('🔑 getToken() MEMORY ONLY: ${_accessToken != null ? "${_accessToken!.substring(0, min(30, _accessToken!.length))}..." : "NULL"}');
    return _accessToken;
  }

  // Set access token directly (for OAuth flows)
  static void setAccessToken(String token) {
    print('🔑 setAccessToken() - Direct token assignment');
    _accessToken = token;
    // Generate NEW session ID for new login
    _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
    print('✅ Token set with session: $_currentSessionId');
    print('✅ Token (first 30): ${token.substring(0, min(30, token.length))}...');
  }

  // Save token for NEW LOGIN (creates new session)
  static Future<void> saveTokenForLogin(String token) async {
    print('💾 saveTokenForLogin() - NEW SESSION');
    _accessToken = token;
    // Generate NEW session ID for new login
    _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
    print('✅ Token saved with NEW session: $_currentSessionId');
    print('✅ Token (first 30): ${token.substring(0, min(30, token.length))}...');
  }

  // Save token WITHOUT changing session (for token refresh)
  static Future<void> saveToken(String token) async {
    print('💾 saveToken() - keeping same session');
    _accessToken = token;
    print('✅ Token updated (Session unchanged: $_currentSessionId)');
  }

  // Delete token from MEMORY
  static Future<void> clearToken() async {
    print('🗑️ clearToken() clearing memory token');
    _accessToken = null;
    // Invalidate current session
    _currentSessionId = '';
    print('✅ Memory token cleared (Session invalidated)');
  }

  // User login
  static Future<Map<String, dynamic>> login(
    String email,
    String password,
  ) async {
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('🔐 LOGIN REQUEST');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('📤 Sending to: $baseUrl/auth/login');
    print('📤 Email/Username: $email');
    print('📤 Password length: ${password.length} chars');

    final response = await http.post(
      Uri.parse('${ApiService.baseUrl}/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'email': email, 'password': password}),
    );

    print('📥 Response status: ${response.statusCode}');
    print('📥 Response body: ${response.body}');

    if (response.statusCode == 200) {
      final data = json.decode(response.body);

      if (data['success']) {
        print('✅ Login successful!');
        print('👤 User from server: ${data['user']}');
        
        // For 2FA-enabled accounts, we need to handle the response differently
        if (data['requiresTwoFactor'] == true) {
          print('🔐 2FA required');
          // Don't save token yet, wait for 2FA completion
          return {
            'success': true,
            'requiresTwoFactor': true,
            'twoFactorCode': data['twoFactorCode'],
            'username': data['username'],
            'tempAccessToken':
                data['accessToken'], // Temporary token if provided
            'user': {
              'email': email,
              'username': data['username'],
              'has_2fa_enabled': true,
              'twofa': data['twoFactorCode'],
            },
          };
        } else {
          // Regular login without 2FA
          print('✅ No 2FA required, proceeding with login');
          if (data['accessToken'] != null) {
            await saveTokenForLogin(data['accessToken']); // NEW SESSION for login
            print('💾 Token saved');
          }
          print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
          return data;
        }
      } else {
        print('❌ Login failed - server returned success=false');
        return data;
      }
    } else {
      final errorData = json.decode(response.body);
      print('❌ Login failed with status ${response.statusCode}: ${errorData['message']}');
      throw Exception(errorData['message'] ?? 'Login error');
    }
  }

  // Google Sign In with Firebase ID Token
  static Future<Map<String, dynamic>> googleSignIn(String idToken) async {
    print('🔐 Google Sign-In with Firebase ID Token');
    print('📤 Sending to: $baseUrl/auth/firebase-google');

    final response = await http.post(
      Uri.parse('${ApiService.baseUrl}/auth/firebase-google'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'idToken': idToken,
      }),
    );

    print('📥 Response status: ${response.statusCode}');
    print('📥 Response body: ${response.body}');

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = json.decode(response.body);

      if (data['success']) {
        print('✅ Google Sign-In successful');
        print('👤 User from server: ${data['user']}');
        
        if (data['accessToken'] != null) {
          await saveTokenForLogin(data['accessToken']); // NEW SESSION for Google login
          print('💾 Token saved');
        }

        return data;
      } else {
        throw Exception(data['message'] ?? 'Google Sign-In failed');
      }
    } else {
      final errorData = json.decode(response.body);
      throw Exception(errorData['message'] ?? 'Google Sign-In error');
    }
  }

  // Firebase Google Sign-In - uses Firebase ID token 
  // Works on all platforms (iOS, Android, macOS)
  static Future<Map<String, dynamic>> firebaseGoogleSignIn({
    required String idToken,
    required String email,
    required String name,
    String? photoUrl,
    required String uid,
  }) async {
    print('🔐 Firebase Google Sign-In');
    print('📤 Sending to: $baseUrl/auth/firebase-google');
    print('   Email: $email');
    print('   Name: $name');
    print('   UID: $uid');

    final response = await http.post(
      Uri.parse('${ApiService.baseUrl}/auth/firebase-google'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'idToken': idToken,
        'email': email,
        'name': name,
        'photoUrl': photoUrl,
        'uid': uid,
      }),
    );

    print('📥 Response status: ${response.statusCode}');

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = json.decode(response.body);

      if (data['success'] == true) {
        print('✅ Firebase Google Sign-In successful');
        print('👤 User: ${data['user']}');
        
        if (data['accessToken'] != null) {
          setAccessToken(data['accessToken']);
          print('💾 Token set in memory');
        }

        return data;
      } else {
        throw Exception(data['message'] ?? 'Google Sign-In failed');
      }
    } else {
      final errorData = json.decode(response.body);
      throw Exception(errorData['message'] ?? 'Google Sign-In error');
    }
  }

  // Native Google Sign-In for iOS/Android
  // Uses tokens from google_sign_in Flutter package
  static Future<Map<String, dynamic>> googleNativeSignIn({
    String? idToken,
    String? accessToken,
  }) async {
    print('🔐 Native Google Sign-In');
    print('📤 Sending to: $baseUrl/auth/google-native');
    print('   ID Token: ${idToken != null ? "${idToken.substring(0, 20)}..." : "null"}');
    print('   Access Token: ${accessToken != null ? "${accessToken.substring(0, 20)}..." : "null"}');

    final response = await http.post(
      Uri.parse('${ApiService.baseUrl}/auth/google-native'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'idToken': idToken,
        'accessToken': accessToken,
      }),
    );

    print('📥 Response status: ${response.statusCode}');
    print('📥 Response body: ${response.body}');

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = json.decode(response.body);

      if (data['success'] == true) {
        print('✅ Native Google Sign-In successful');
        print('👤 User: ${data['user']}');
        
        if (data['accessToken'] != null) {
          setAccessToken(data['accessToken']);
          print('💾 Token set in memory');
        }

        return data;
      } else {
        throw Exception(data['message'] ?? 'Google Sign-In failed');
      }
    } else {
      final errorData = json.decode(response.body);
      throw Exception(errorData['message'] ?? 'Google Sign-In error');
    }
  }

  // Native Apple Sign-In for iOS/macOS
  static Future<Map<String, dynamic>> appleNativeSignIn({
    required String? identityToken,
    required String? authorizationCode,
    required String userIdentifier,
    String? email,
    String? fullName,
  }) async {
    print('🔐 Native Apple Sign-In');
    print('📤 Sending to: $baseUrl/auth/apple-native');

    final response = await http.post(
      Uri.parse('${ApiService.baseUrl}/auth/apple-native'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'identityToken': identityToken,
        'authorizationCode': authorizationCode,
        'userIdentifier': userIdentifier,
        'email': email,
        'fullName': fullName,
      }),
    );

    print('📥 Apple response status: ${response.statusCode}');
    print('📥 Apple response body: ${response.body}');

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = json.decode(response.body);

      if (data['success'] == true) {
        if (data['accessToken'] != null) {
          await saveTokenForLogin(data['accessToken']);
        }
        return data;
      }

      throw Exception(data['message'] ?? 'Apple Sign-In failed');
    }

    final errorData = json.decode(response.body);
    throw Exception(errorData['message'] ?? 'Apple Sign-In error');
  }

  // Check Google OAuth session status
  static Future<Map<String, dynamic>> checkGoogleSession(String state) async {
    final response = await http.get(
      Uri.parse('${ApiService.baseUrl}/auth/check-session?state=$state'),
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to check session');
    }
  }

  // User registration
  static Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    required String password,
    String? family,
    String? phone,
    String? address,
    String? username,
    String? birthdate,
    double? latitude,
    double? longitude,
    String? companyName,
    String? companyWebsite,
    String? companyDescription,
    String? businessSize,
    String? country,
    String? taxId,
    String? profileImage,
  }) async {
    final response = await http.post(
      Uri.parse('${ApiService.baseUrl}/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'name': name,
        'email': email,
        'password': password,
        'family': family,
        'phone': phone,
        'address': address,
        'username': username,
        'birthdate': birthdate,
        'latitude': latitude,
        'longitude': longitude,
        'company_name': companyName,
        'company_website': companyWebsite,
        'company_description': companyDescription,
        'business_size': businessSize,
        'country': country,
        'tax_id': taxId,
        'profileImage': ?profileImage,
      }),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      // Note: Registration now returns success without tokens
      // Tokens are only provided after email verification
      return data;
    } else {
      final errorData = json.decode(response.body);
      // Use the specific error message from backend
      final errorMessage =
          errorData['message'] ?? errorData['error'] ?? 'Registration failed';
      throw Exception(errorMessage);
    }
  }

  // Check username availability across all user tables
  static Future<Map<String, dynamic>> checkUsernameAvailability(
    String username,
  ) async {
    final normalized = username.trim().toLowerCase();
    if (normalized.isEmpty) {
      return {
        'success': false,
        'available': false,
        'message': 'Username is required',
      };
    }

    final response = await http
        .get(
          Uri.parse(
            '${ApiService.baseUrl}/auth/check-username/${Uri.encodeComponent(normalized)}',
          ),
          headers: {'Content-Type': 'application/json'},
        )
        .timeout(ApiService._timeoutDuration);

    final data = json.decode(response.body);
    if (response.statusCode == 200) {
      return data;
    }

    final errorMessage = data['message'] ?? data['error'] ?? 'Username check failed';
    throw Exception(errorMessage);
  }

  // Resend email verification code
  static Future<Map<String, dynamic>> resendVerificationCode(
    String email,
  ) async {
    final response = await http
        .post(
          Uri.parse('${ApiService.baseUrl}/auth/resend-verification-code'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'email': email}),
        )
        .timeout(ApiService._timeoutDuration);

    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    } else {
      final errorData = json.decode(response.body);
      throw Exception(
        errorData['message'] ?? errorData['error'] ?? 'Failed to resend code',
      );
    }
  }

  // Verify email with code
  static Future<Map<String, dynamic>> verifyEmail({
    required String email,
    required String code,
  }) async {
    final response = await http.post(
      Uri.parse('${ApiService.baseUrl}/auth/verify-email'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'email': email, 'code': code}),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = json.decode(response.body);
      if (data['success'] && data['accessToken'] != null) {
        await saveTokenForLogin(data['accessToken']); // NEW SESSION after email verification
      }
      return data;
    } else {
      final errorData = json.decode(response.body);
      throw Exception(errorData['message'] ?? 'Verification error');
    }
  }

  // Send login email OTP (called after credentials verified)
  static Future<Map<String, dynamic>> sendLoginEmailCode(String username) async {
    final response = await http
        .post(
          Uri.parse('${ApiService.baseUrl}/auth/send-login-email-code'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'username': username}),
        )
        .timeout(ApiService._timeoutDuration);
    final data = json.decode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200) return data;
    throw Exception(data['message'] ?? 'Failed to send login code');
  }

  // Verify login email OTP and get full login response with tokens
  static Future<Map<String, dynamic>> verifyLoginEmailCode(
    String username,
    String code,
  ) async {
    final response = await http
        .post(
          Uri.parse('${ApiService.baseUrl}/auth/verify-login-email-code'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'username': username, 'code': code}),
        )
        .timeout(ApiService._timeoutDuration);
    final data = json.decode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200 && data['success'] == true) {
      // Save token into ApiService memory the same way login() does
      if (data['accessToken'] != null) {
        await saveTokenForLogin(data['accessToken']);
      }
      return data;
    }
    throw Exception(data['message'] ?? 'Invalid login code');
  }

  // Request password reset
  static Future<Map<String, dynamic>> requestPasswordReset(String email) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/auth/forgot-password'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'email': email}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data;
      } else {
        final errorData = json.decode(response.body);
        return {
          'success': false,
          'message': errorData['message'] ?? 'Failed to send reset link',
        };
      }
    } catch (e) {
      print('❌ Error requesting password reset: $e');
      return {
        'success': false,
        'message': 'An error occurred. Please try again.',
      };
    }
  }

  // Reset password with code
  static Future<Map<String, dynamic>> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/auth/reset-password'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': email,
          'code': code,
          'newPassword': newPassword,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data;
      } else {
        final errorData = json.decode(response.body);
        return {
          'success': false,
          'message': errorData['message'] ?? 'Failed to reset password',
        };
      }
    } catch (e) {
      print('❌ Error resetting password: $e');
      return {
        'success': false,
        'message': 'An error occurred. Please try again.',
      };
    }
  }

  // Verify 2FA code
  static Future<Map<String, dynamic>> verify2FA(
    String username,
    String twoFactorCode,
  ) async {
    //print('📡 Verifying 2FA code via API for user: $username');

    final response = await http.post(
      Uri.parse('${ApiService.baseUrl}/auth/verify-2fa'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'username': username, 'twoFactorCode': twoFactorCode}),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] && data['accessToken'] != null) {
        await saveTokenForLogin(data['accessToken']); // NEW SESSION after 2FA verification
      }
      //print(' 2FA verification successful via API');
      return data;
    } else {
      final errorData = json.decode(response.body);
      //print(' 2FA verification failed via API: ${errorData['message']}');
      throw Exception(errorData['message'] ?? '2FA verification error');
    }
  }

  // Get user profile
  static Future<Map<String, dynamic>?> getUserProfile() async {
    print('👤 getUserProfile() called...');
    final sessionAtRequest = _currentSessionId;  // Capture session BEFORE request
    print('📍 Request session ID: $sessionAtRequest');
    
    final token = await ApiService.getToken();
    if (token == null) {
      print('❌ getUserProfile(): No token available!');
      throw Exception('Not authenticated');
    }
    print('🔑 getUserProfile() using token (first 30): ${token.substring(0, min(30, token.length))}...');
    print('🔑 FULL TOKEN: $token');  // DEBUG: Full token to verify

    final response = await http
        .get(
          Uri.parse('${ApiService.baseUrl}/users/profile'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        )
        .timeout(ApiService._timeoutDuration);

    // Validate session AFTER response arrives
    if (sessionAtRequest != _currentSessionId) {
      print('⚠️ Session changed! Request was from session: $sessionAtRequest, but current is: $_currentSessionId');
      print('🚫 IGNORING this response (from old login session)');
      return null;
    }

    if (response.statusCode == 200) {
      final result = json.decode(response.body);
      print('✅ getUserProfile() success (session valid): ${result["user"]?["username"]} - ${result["user"]?["email"]}');
      return result;
    } else {
      final errorData = json.decode(response.body);
      print('❌ getUserProfile() failed: ${errorData["message"]}');
      throw Exception(errorData['message'] ?? 'Error loading profile');
    }
  }

  // Get user by username (for viewing other users/sellers)
  static Future<Map<String, dynamic>?> getUserByUsername(
    String username,
  ) async {
    try {
      final response = await http
          .get(
            Uri.parse('${ApiService.baseUrl}/users/by-username/$username'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(ApiService._timeoutDuration);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['message'] ?? 'Error loading user');
      }
    } catch (e) {
      print('Error in getUserByUsername: $e');
      return null;
    }
  }

  // Update user profile
  static Future<Map<String, dynamic>> updateUserProfile({
    String? username,
    String? name,
    String? email,
    String? phone,
    String? birthdate,
    String? address,
    String? street,
    String? houseNumber,
    String? postalCode,
    String? city,
    String? country,
    double? latitude,
    double? longitude,
    String? businessName,
    String? businessAddress,
    String? businessPhone,
    String? businessEmail,
    String? businessDescription,
    String? businessCompany,
    String? businessSize,
    String? businessCountry,
    String? userTimezone,
    bool? isBusiness,
    bool? notificationsLogin,
    bool? notificationsNewsletter,
    String? profileImage,
  }) async {
    final token = await ApiService.getToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final body = <String, dynamic>{};
    if (username != null) body['username'] = username;
    if (name != null) body['name'] = name;
    if (email != null) body['email'] = email;
    if (phone != null) body['phone'] = phone;
    if (birthdate != null) body['birthdate'] = birthdate;
    if (profileImage != null) body['profileImage'] = profileImage;
    if (address != null) body['address'] = address;
    if (street != null) body['street'] = street;
    if (houseNumber != null) body['house_number'] = houseNumber;
    if (postalCode != null) body['postal_code'] = postalCode;
    if (city != null) body['city'] = city;
    if (country != null) body['country'] = country;
    if (latitude != null) body['latitude'] = latitude;
    if (longitude != null) body['longitude'] = longitude;
    if (businessName != null) body['businessName'] = businessName;
    if (businessAddress != null) body['businessAddress'] = businessAddress;
    if (businessPhone != null) body['businessPhone'] = businessPhone;
    if (businessEmail != null) body['businessEmail'] = businessEmail;
    if (businessDescription != null) {
      body['businessDescription'] = businessDescription;
    }
    if (businessCompany != null) body['businessCompany'] = businessCompany;
    if (businessSize != null) body['businessSize'] = businessSize;
    if (businessCountry != null) body['businessCountry'] = businessCountry;
    if (userTimezone != null) body['userTimezone'] = userTimezone;
    if (isBusiness != null) body['isBusiness'] = isBusiness;
    if (notificationsLogin != null) {
      body['notificationsLogin'] = notificationsLogin;
    }
    if (notificationsNewsletter != null) {
      body['notificationsNewsletter'] = notificationsNewsletter;
    }

    final response = await http.put(
      Uri.parse('${ApiService.baseUrl}/users/profile'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: json.encode(body),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      final errorData = json.decode(response.body);
      throw Exception(errorData['message'] ?? 'Error updating profile');
    }
  }

  // Get user settings
  static Future<Map<String, dynamic>> getUserSettings() async {
    final token = await ApiService.getToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final response = await http.get(
      Uri.parse('${ApiService.baseUrl}/users/settings'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      final errorData = json.decode(response.body);
      throw Exception(errorData['message'] ?? 'Error loading settings');
    }
  }

  // Update user settings
  static Future<Map<String, dynamic>> updateUserSettings(
    Map<String, dynamic> settings,
  ) async {
    final token = await ApiService.getToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final response = await http.put(
      Uri.parse('${ApiService.baseUrl}/users/settings'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: json.encode(settings),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      final errorData = json.decode(response.body);
      throw Exception(errorData['message'] ?? 'Error updating settings');
    }
  }

  // Get Stripe payment methods
  static Future<List<Map<String, dynamic>>> getPaymentMethods() async {
    print('🔍 Loading payment methods...');
    final token = await ApiService.getToken();
    if (token == null) {
      print('❌ No token found');
      throw Exception('Not authenticated');
    }

    print('🔍 Token found, making API request...');
    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/stripe/payment-methods'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print('🔍 API Response Status: ${response.statusCode}');
      print('🔍 API Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('🔍 Stripe API Response: $data');

        if (data['success'] == true && data['paymentMethods'] != null) {
          final methods = List<Map<String, dynamic>>.from(
            data['paymentMethods'],
          );
          print('✅ Found ${methods.length} payment methods');
          return methods;
        } else {
          print('❌ API returned success=false or no paymentMethods');
          return [];
        }
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        print('❌ Authentication failed: ${response.statusCode}');
        final errorData = json.decode(response.body);
        throw Exception(errorData['message'] ?? 'Authentication failed');
      } else {
        print(
          '❌ Stripe Payment Methods Error: ${response.statusCode} - ${response.body}',
        );
        return [];
      }
    } catch (e) {
      print('❌ Error loading payment methods: $e');
      rethrow;
    }
  }

  // === NEW PAYMENT METHODS API ===

  // Get all saved payment methods
  static Future<List<Map<String, dynamic>>> getUserPaymentMethods() async {
    print('💳 Loading user payment methods...');
    final url = '${ApiService.baseUrl}/stripe/payment-methods';
    print('🌐 Full URL: $url');
    final token = await ApiService.getToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['paymentMethods'] != null) {
          return List<Map<String, dynamic>>.from(data['paymentMethods']);
        }
        print('⚠️ Stripe endpoint returned no methods, trying fallback endpoint...');
      } else {
        print('❌ Error loading payment methods: ${response.statusCode} ${response.body}');
      }

      final fallbackResponse = await http.get(
        Uri.parse('${ApiService.baseUrl}/payment-methods'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (fallbackResponse.statusCode == 200) {
        final fallbackData = json.decode(fallbackResponse.body);
        if (fallbackData['success'] == true && fallbackData['paymentMethods'] != null) {
          print('✅ Loaded payment methods via fallback endpoint');
          return List<Map<String, dynamic>>.from(fallbackData['paymentMethods']);
        }
      }

      print('❌ Fallback payment methods failed: ${fallbackResponse.statusCode} ${fallbackResponse.body}');
      return [];
    } catch (e) {
      print('❌ Error loading payment methods: $e');
      rethrow;
    }
  }

  // Save a card
  static Future<Map<String, dynamic>> saveCard({
    required String cardNumber,
    required int expiryMonth,
    required int expiryYear,
    required String cvv,
    required String cardholderName,
    bool setAsDefault = false,
  }) async {
    final token = await ApiService.getToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    try {
      print('💳 Saving card via Stripe API...');
      final stripeResponse = await http.post(
        Uri.parse('${ApiService.baseUrl}/stripe/payment-methods'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'type': 'card',
          'card': {
            'number': cardNumber,
            'exp_month': expiryMonth,
            'exp_year': expiryYear,
            'cvc': cvv,
          },
        }),
      );

      final stripeResult = json.decode(stripeResponse.body);
      print('💳 Stripe save status: ${stripeResponse.statusCode}');
      print('💳 Stripe save body: ${stripeResponse.body}');

      if (stripeResponse.statusCode == 200 && stripeResult['success'] == true) {
        print('✅ Card save response: true');
        return stripeResult;
      }

      print('⚠️ Stripe card save failed, trying fallback /payment-methods/card endpoint...');
      final fallbackResponse = await http.post(
        Uri.parse('${ApiService.baseUrl}/payment-methods/card'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'cardNumber': cardNumber,
          'expiryMonth': expiryMonth,
          'expiryYear': expiryYear,
          'cvv': cvv,
          'cardholderName': cardholderName,
          'setAsDefault': setAsDefault,
        }),
      );

      final fallbackResult = json.decode(fallbackResponse.body);
      print('💳 Fallback save status: ${fallbackResponse.statusCode}');
      print('💳 Fallback save body: ${fallbackResponse.body}');
      return fallbackResult;
    } catch (e) {
      print('❌ Error saving card: $e');
      rethrow;
    }
  }

  // Save SEPA account
  static Future<Map<String, dynamic>> saveSepaAccount({
    required String iban,
    required String accountHolderName,
    String? bankName,
    bool setAsDefault = false,
  }) async {
    final token = await ApiService.getToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/payment-methods/sepa'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'iban': iban,
          'accountHolderName': accountHolderName,
          'bankName': bankName,
          'setAsDefault': setAsDefault,
        }),
      );

      return json.decode(response.body);
    } catch (e) {
      print('❌ Error saving SEPA account: $e');
      rethrow;
    }
  }

  // Save ACH account
  static Future<Map<String, dynamic>> saveAchAccount({
    required String routingNumber,
    required String accountNumber,
    required String accountHolderName,
    String? bankName,
    bool setAsDefault = false,
    String paymentType = 'ach',
  }) async {
    final token = await ApiService.getToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/payment-methods/ach'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'routingNumber': routingNumber,
          'accountNumber': accountNumber,
          'accountHolderName': accountHolderName,
          'bankName': bankName,
          'setAsDefault': setAsDefault,
          'paymentType': paymentType,
        }),
      );

      return json.decode(response.body);
    } catch (e) {
      print('❌ Error saving ACH account: $e');
      rethrow;
    }
  }

  // Save Wise account
  static Future<Map<String, dynamic>> saveWiseAccount({
    required String email,
    required String accountHolderName,
    bool setAsDefault = false,
  }) async {
    final token = await ApiService.getToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/payment-methods/wise'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'email': email,
          'accountHolderName': accountHolderName,
          'setAsDefault': setAsDefault,
        }),
      );

      return json.decode(response.body);
    } catch (e) {
      print('❌ Error saving Wise account: $e');
      rethrow;
    }
  }

  // Delete payment method
  static Future<Map<String, dynamic>> deletePaymentMethod(int id) async {
    final token = await ApiService.getToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    try {
      final response = await http.delete(
        Uri.parse('${ApiService.baseUrl}/payment-methods/$id'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      return json.decode(response.body);
    } catch (e) {
      print('❌ Error deleting payment method: $e');
      rethrow;
    }
  }

  // Charge the responsible party's default payment method for shipping
  // paymentType: 'card' | 'ach_net30' | 'ach_net60' | 'sepa_net30' | 'sepa_net60'
  static Future<Map<String, dynamic>> chargeShippingPayment(
    dynamic orderId, {
    String paymentType = 'card',
    String? paymentMethodId,
    String? sellerUsername,
  }) async {
    final token = await ApiService.getToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    try {
      final body = <String, dynamic>{
        'payment_type': paymentType,
      };
      if (paymentMethodId != null) {
        body['payment_method_id'] = paymentMethodId;
      }
      if (sellerUsername != null && sellerUsername.isNotEmpty) {
        body['seller_username'] = sellerUsername;
      }
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/api/delvioo/orders/$orderId/pay-shipping'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode(body),
      );

      return json.decode(response.body);
    } catch (e) {
      print('❌ Error charging shipping payment: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> payBuyerWaitingCharges(dynamic orderId) async {
    final token = await ApiService.getToken();
    if (token == null) throw Exception('Not authenticated');
    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/api/orders/$orderId/pay-buyer-waiting-charges'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({}),
      );
      return json.decode(response.body);
    } catch (e) {
      print('❌ Error paying buyer waiting charges: $e');
      rethrow;
    }
  }

  // Set payment method as default
  static Future<Map<String, dynamic>> setDefaultPaymentMethod(int id) async {
    final token = await ApiService.getToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    try {
      final response = await http.patch(
        Uri.parse('${ApiService.baseUrl}/payment-methods/$id/default'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      return json.decode(response.body);
    } catch (e) {
      print('❌ Error setting default payment method: $e');
      rethrow;
    }
  }

  // Get payment terms status
  static Future<Map<String, dynamic>> getPaymentTermsStatus() async {
    final token = await ApiService.getToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/payment-methods/terms/status'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return {'success': false, 'enabled': false};
      }
    } catch (e) {
      print('❌ Error getting payment terms status: $e');
      return {'success': false, 'enabled': false};
    }
  }

  // ─── MONIOO WALLET ──────────────────────────────────────────────────────

  // Get wallet balance + transactions
  static Future<Map<String, dynamic>> getWallet() async {
    final token = await ApiService.getToken();
    if (token == null) throw Exception('Not authenticated');

    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/wallet'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      return json.decode(response.body);
    } catch (e) {
      print('❌ Error getting wallet: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // Top up wallet
  static Future<Map<String, dynamic>> topUpWallet(
    double amount, {
    String? paymentMethodId,       // Stripe pm_ ID for cards
    String? localPaymentMethodId,  // Local DB id for SEPA/ACH/Wire
  }) async {
    final token = await ApiService.getToken();
    if (token == null) throw Exception('Not authenticated');

    try {
      final body = <String, dynamic>{'amount': amount};
      if (paymentMethodId != null) body['paymentMethodId'] = paymentMethodId;
      if (localPaymentMethodId != null) body['localPaymentMethodId'] = localPaymentMethodId;

      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/wallet/topup'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode(body),
      );
      return json.decode(response.body);
    } catch (e) {
      print('❌ Error topping up wallet: $e');
      rethrow;
    }
  }

  // Download PDF receipt for a wallet top-up transaction
  static Future<Uint8List> downloadWalletReceipt(int transactionId) async {
    final token = await ApiService.getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await http.get(
      Uri.parse('${ApiService.baseUrl}/wallet/receipt/$transactionId'),
      headers: {
        'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode == 200) {
      return response.bodyBytes;
    }
    throw Exception('Failed to download receipt: ${response.statusCode}');
  }

  // Pay from wallet
  static Future<Map<String, dynamic>> payFromWallet({
    required double amount,
    String? description,
    String? referenceType,
    String? referenceId,
  }) async {
    final token = await ApiService.getToken();
    if (token == null) throw Exception('Not authenticated');

    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/wallet/pay'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'amount': amount,
          'description': description,
          'reference_type': referenceType,
          'reference_id': referenceId,
        }),
      );
      return json.decode(response.body);
    } catch (e) {
      print('❌ Error paying from wallet: $e');
      rethrow;
    }
  }

  // Get payment defaults (product vs shipping)
  static Future<Map<String, dynamic>> getPaymentDefaults() async {
    final token = await ApiService.getToken();
    if (token == null) throw Exception('Not authenticated');

    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/wallet/defaults'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return {'success': false, 'default_payment_product': 'card', 'default_payment_shipping': 'card'};
    } catch (e) {
      print('❌ Error getting payment defaults: $e');
      return {'success': false, 'default_payment_product': 'card', 'default_payment_shipping': 'card'};
    }
  }

  // Set payment defaults
  static Future<Map<String, dynamic>> setPaymentDefaults({
    String? defaultProduct,
    String? defaultShipping,
  }) async {
    final token = await ApiService.getToken();
    if (token == null) throw Exception('Not authenticated');

    try {
      final body = <String, dynamic>{};
      if (defaultProduct != null) body['default_payment_product'] = defaultProduct;
      if (defaultShipping != null) body['default_payment_shipping'] = defaultShipping;

      final response = await http.put(
        Uri.parse('${ApiService.baseUrl}/wallet/defaults'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode(body),
      );
      return json.decode(response.body);
    } catch (e) {
      print('❌ Error setting payment defaults: $e');
      rethrow;
    }
  }

  // Get saved Stripe cards
  static Future<List<Map<String, dynamic>>> getSavedCards(
    String accessToken,
  ) async {
    print('💳 Loading saved Stripe cards...');

    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/stripe/saved-cards'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
      );

      print('💳 Saved cards response status: ${response.statusCode}');
      print('💳 Saved cards response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['success'] == true && data['cards'] != null) {
          final cards = List<Map<String, dynamic>>.from(data['cards']);
          print('✅ Found ${cards.length} saved cards');
          return cards;
        } else {
          print('❌ API returned success=false or no cards');
          return [];
        }
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        print('❌ Authentication failed: ${response.statusCode}');
        final errorData = json.decode(response.body);
        throw Exception(errorData['message'] ?? 'Authentication failed');
      } else {
        print('❌ Saved cards error: ${response.statusCode} - ${response.body}');
        return [];
      }
    } catch (e) {
      print('❌ Error loading saved cards: $e');
      rethrow;
    }
  }

  // Create Setup Intent for Stripe Payment Sheet
  static Future<Map<String, dynamic>?> createSetupIntent() async {
    final token = await ApiService.getToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/stripe/setup-intent'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data;
      } else {
        //print('Setup Intent Error: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      //print('Error creating Setup Intent: $e');
      return null;
    }
  }

  // Create Payment Intent for checkout
  static Future<Map<String, dynamic>?> createPaymentIntent({
    required double amount,
    required String currency,
    List<Map<String, dynamic>>? cartItems,
    Map<String, dynamic>? shippingAddress,
    String? addressId,
  }) async {
    final token = await ApiService.getToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/stripe/payment-intent'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'amount': (amount * 100).round(), // Stripe expects amount in cents
          'currency': currency,
          'cart_items': cartItems,
          'shipping_address': shippingAddress,
          'address_id': addressId,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data;
      } else {
        //print('Payment Intent Error: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      //print('Error creating Payment Intent: $e');
      return null;
    }
  }

  // Get Stripe transactions
  static Future<List<Map<String, dynamic>>> getTransactions() async {
    final token = await ApiService.getToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/stripe/transactions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['transactions'] ?? []);
      } else {
        //print('Stripe Transactions Error: ${response.statusCode} - ${response.body}');
        return [];
      }
    } catch (e) {
      //print('Error loading transactions: $e');
      return [];
    }
  }

  // Get addresses
  static Future<Map<String, dynamic>> getAddresses(String accessToken) async {
    print('🌐 Making GET request to $baseUrl/addresses');
    print('🔑 Using token: ${accessToken.substring(0, 10)}...');

    final response = await http.get(
      Uri.parse('${ApiService.baseUrl}/addresses'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
    );

    print('📡 Response status: ${response.statusCode}');
    print('📄 Response body: ${response.body}');

    if (response.statusCode == 200) {
      final result = json.decode(response.body);
      print('✅ Parsed response: $result');
      return result;
    } else {
      print('❌ Error response: ${response.body}');
      final errorData = json.decode(response.body);
      throw Exception(errorData['message'] ?? 'Error loading addresses');
    }
  }

  // Add address
  static Future<Map<String, dynamic>> addAddress(
    String accessToken,
    String address,
    String? country,
    bool isSelected, {
    double? lat,
    double? lng,
    String? street,
    String? houseNumber,
    String? zipCode,
    String? city,
  }) async {
    final response = await http.post(
      Uri.parse('${ApiService.baseUrl}/addresses'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: json.encode({
        'address': address,
        'country': country,
        'isSelected': isSelected,
        'lat': lat,
        'lng': lng,
        'street': street,
        'house_number': houseNumber,
        'zip_code': zipCode,
        'city': city,
      }),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      final errorData = json.decode(response.body);
      throw Exception(errorData['message'] ?? 'Error adding address');
    }
  }

  static Future<Map<String, dynamic>> updateAddress(
    String accessToken,
    int addressId,
    String address,
    String? country,
    bool isSelected, {
    double? lat,
    double? lng,
    String? street,
    String? houseNumber,
    String? zipCode,
    String? city,
  }) async {
    final response = await http.put(
      Uri.parse('${ApiService.baseUrl}/addresses/$addressId'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: json.encode({
        'address': address,
        'country': country,
        'isSelected': isSelected,
        'lat': lat,
        'lng': lng,
        'street': street,
        'house_number': houseNumber,
        'zip_code': zipCode,
        'city': city,
      }),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      final errorData = json.decode(response.body);
      throw Exception(errorData['message'] ?? 'Error updating address');
    }
  }

  // Set main address
  static Future<Map<String, dynamic>> setMainAddress(
    String accessToken,
    int addressId,
  ) async {
    final response = await http.put(
      Uri.parse('${ApiService.baseUrl}/addresses/$addressId/select'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      final errorData = json.decode(response.body);
      throw Exception(errorData['message'] ?? 'Error setting main address');
    }
  }

  // Delete address
  static Future<Map<String, dynamic>> deleteAddress(
    String accessToken,
    int addressId,
  ) async {
    final response = await http.delete(
      Uri.parse('${ApiService.baseUrl}/addresses/$addressId'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      final errorData = json.decode(response.body);
      throw Exception(errorData['message'] ?? 'Error deleting address');
    }
  }

  // Change password
  static Future<Map<String, dynamic>> changePassword(
    String accessToken,
    String currentPassword,
    String newPassword,
  ) async {
    //print('🔍 Debug: ApiService.changePassword called');
    //print('🔍 Debug: accessToken = "${accessToken.substring(0, 20)}..."');
    //print('🔍 Debug: URL = $baseUrl/auth/change-password');

    final response = await http.post(
      Uri.parse('${ApiService.baseUrl}/auth/change-password'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: json.encode({
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      }),
    );

    //print('🔍 Debug: Response status code: ${response.statusCode}');
    //print('🔍 Debug: Response body: ${response.body}');

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      final errorData = json.decode(response.body);
      throw Exception(errorData['message'] ?? 'Error changing password');
    }
  }

  // Test connection method
  static Future<bool> testConnection() async {
    try {
      final response = await http
          .get(
            Uri.parse('${ApiService.baseUrl}/health'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (e) {
      //print('Connection test failed: $e');
      return false;
    }
  }

  // Update 2FA Code
  static Future<Map<String, dynamic>> update2FACode(String code) async {
    final token = await ApiService.getToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final response = await http
        .put(
          Uri.parse('${ApiService.baseUrl}/users/2fa'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: json.encode({'twofa': code, 'has_2fa_enabled': true}),
        )
        .timeout(ApiService._timeoutDuration);

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      final errorData = json.decode(response.body);
      throw Exception(errorData['message'] ?? 'Error updating 2FA code');
    }
  }

  // Disable 2FA
  static Future<Map<String, dynamic>> disable2FA() async {
    //print('📡 Disabling 2FA via API');

    final token = await ApiService.getToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final response = await http
        .put(
          Uri.parse('${ApiService.baseUrl}/users/2fa'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: json.encode({'twofa': '', 'has_2fa_enabled': false}),
        )
        .timeout(ApiService._timeoutDuration);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      //print(' 2FA disable successful via API');
      return data;
    } else {
      final errorData = json.decode(response.body);
      //print(' 2FA disable failed via API: ${errorData['message']}');
      throw Exception(errorData['message'] ?? '2FA disable error');
    }
  }

  static Future<Map<String, dynamic>> save2FACode(
    String username,
    String code,
  ) async {
    //print('📡 Saving 2FA code via API for user: $username');

    final token = await ApiService.getToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final response = await http
        .put(
          Uri.parse('${ApiService.baseUrl}/users/2fa'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: json.encode({'twofa': code, 'has_2fa_enabled': true}),
        )
        .timeout(ApiService._timeoutDuration);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      //print(' 2FA code save successful via API');
      return data;
    } else {
      final errorData = json.decode(response.body);
      //print(' 2FA code save failed via API: ${errorData['message']}');
      throw Exception(errorData['message'] ?? '2FA save error');
    }
  }

  static Future<Map<String, dynamic>> generateNew2FA(
    String username,
    String newCode,
  ) async {
    //print('📡 Generating new 2FA code via API for user: $username');

    final token = await ApiService.getToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final response = await http.post(
      Uri.parse('${ApiService.baseUrl}/auth/generate-new-2fa'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: json.encode({'username': username, 'newTwoFactorCode': newCode}),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      //print(' New 2FA code generation successful via API');
      return data;
    } else {
      final errorData = json.decode(response.body);
      //print(' New 2FA code generation failed via API: ${errorData['message']}');
      throw Exception(errorData['message'] ?? '2FA code generation error');
    }
  }

  // Products APIs - Updated for localhost connection
  static Future<Map<String, dynamic>> getProducts() async {
    print('📦 DEBUG: Fetching products from API: $baseUrl/products');

    try {
      final response = await http
          .get(
            Uri.parse('${ApiService.baseUrl}/products'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(ApiService._timeoutDuration);

      print('📦 DEBUG: Response status: ${response.statusCode}');
      print('📦 DEBUG: Response body length: ${response.body.length}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is List) {
          print('✅ Products fetched successfully: ${data.length} products');
          return {'products': data, 'count': data.length};
        } else {
          print('✅ Products fetched successfully: ${data['count']} products');
          return data;
        }
      } else {
        print(
          '❌ Products fetch failed: ${response.statusCode} - ${response.body}',
        );
        throw Exception('Server returned status ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Network error fetching products: $e');
      if (e.toString().contains('SocketException')) {
        throw Exception('Network error: No internet connection available');
      } else if (e.toString().contains('TimeoutException')) {
        throw Exception('Timeout: Server not responding');
      } else if (e.toString().contains('Failed host lookup')) {
        throw Exception('DNS error: Server not reachable');
      } else {
        throw Exception('Unknown network error: $e');
      }
    }
  }

  static Future<Map<String, dynamic>> searchProducts(
    String query, {
    String? category,
  }) async {
    //print('🔍 Searching products: query="$query", category="$category"');

    String url = '${ApiService.baseUrl}/products/search?q=${Uri.encodeComponent(query)}';
    if (category != null && category.isNotEmpty) {
      url += '&category=${Uri.encodeComponent(category)}';
    }

    final response = await http.get(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      //print('✅ Product search successful: ${data['count']} results');
      return data;
    } else {
      final errorData = json.decode(response.body);
      //print('❌ Product search failed: ${errorData['message']}');
      throw Exception(errorData['message'] ?? 'Error in product search');
    }
  }

  // Favorites APIs
  static Future<Map<String, dynamic>> getFavorites() async {
    print('⭐ Fetching user favorites from API');

    final token = await ApiService.getToken();
    if (token == null) {
      throw Exception('Not logged in');
    }

    final response = await http.get(
      Uri.parse('${ApiService.baseUrl}/users/favorites'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      print('✅ Favorites fetched successfully: ${data['count']} favorites');
      return data;
    } else {
      final errorData = json.decode(response.body);
      print('❌ Favorites fetch failed: ${errorData['message']}');
      throw Exception(errorData['message'] ?? 'Error loading favorites');
    }
  }

  static Future<Map<String, dynamic>> addToFavorites(int productId) async {
    print('⭐ Adding product $productId to favorites');

    final token = await ApiService.getToken();
    if (token == null) {
      throw Exception('Not logged in');
    }

    final response = await http.post(
      Uri.parse('${ApiService.baseUrl}/products/$productId/favorite'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      //print('✅ Product added to favorites: ${data['product_name']}');
      return data;
    } else if (response.statusCode == 409) {
      final errorData = json.decode(response.body);
      //print('⚠️ Product already in favorites: ${errorData['message']}');
      throw Exception(errorData['message'] ?? 'Produkt bereits in Favoriten');
    } else {
      final errorData = json.decode(response.body);
      //print('❌ Add to favorites failed: ${errorData['message']}');
      throw Exception(errorData['message'] ?? 'Error adding to favorites');
    }
  }

  static Future<Map<String, dynamic>> removeFromFavorites(int productId) async {
    //print('⭐ Removing product $productId from favorites');

    final token = await ApiService.getToken();
    if (token == null) {
      throw Exception('Not logged in');
    }

    final response = await http.post(
      Uri.parse('${ApiService.baseUrl}/products/$productId/favorite'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      //print('✅ Product favorite toggled: ${data['is_favorite']}');
      return data;
    } else {
      final errorData = json.decode(response.body);
      //print('❌ Toggle favorite failed: ${errorData['message']}');
      throw Exception(errorData['message'] ?? 'Error toggling favorite');
    }
  }

  static Future<Map<String, dynamic>> checkIsFavorite(int productId) async {
    //print('⭐ Checking if product $productId is favorite');

    final token = await ApiService.getToken();
    if (token == null) {
      throw Exception('Not logged in');
    }

    final response = await http.get(
      Uri.parse('${ApiService.baseUrl}/users/favorites/check/$productId'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      //print('✅ Favorite status checked: ${data['is_favorite']}');
      return data;
    } else {
      final errorData = json.decode(response.body);
      //print('❌ Check favorite failed: ${errorData['message']}');
      throw Exception(errorData['message'] ?? 'Error checking favorite status');
    }
  }

  // Following Users APIs
  static Future<Map<String, dynamic>> getFollowedUsers() async {
    print('👥 Fetching followed users from API');

    final token = await ApiService.getToken();
    if (token == null) {
      throw Exception('Not logged in');
    }

    final response = await http.get(
      Uri.parse('${ApiService.baseUrl}/users/following'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      print(
        '✅ Followed users fetched successfully: ${data['count'] ?? data.length} users',
      );
      return {
        'success': true,
        'users': data['users'] ?? data,
        'count': data['count'] ?? data.length,
      };
    } else if (response.statusCode == 404) {
      print(
        'ℹ️ Following API endpoint not found - feature not yet implemented',
      );
      return {
        'success': false,
        'message': 'Following feature not yet implemented',
        'users': [],
        'count': 0,
      };
    } else {
      final errorBody = response.body;
      print(
        '❌ Followed users fetch failed: Status ${response.statusCode}, Body: $errorBody',
      );
      throw Exception(
        'Error loading followed users: Status ${response.statusCode}',
      );
    }
  }

  static Future<Map<String, dynamic>> followUser(String userId) async {
    print('👥 Following user $userId');

    final token = await ApiService.getToken();
    if (token == null) {
      throw Exception('Not logged in');
    }

    final response = await http.post(
      Uri.parse('${ApiService.baseUrl}/users/$userId/follow'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      print('✅ User followed successfully');
      return data;
    } else {
      final errorData = json.decode(response.body);
      print('❌ Follow user failed: ${errorData['message']}');
      throw Exception(errorData['message'] ?? 'Error following user');
    }
  }

  static Future<Map<String, dynamic>> unfollowUser(String userId) async {
    print('👥 Unfollowing user $userId');

    final token = await ApiService.getToken();
    if (token == null) {
      throw Exception('Not logged in');
    }

    final response = await http.delete(
      Uri.parse('${ApiService.baseUrl}/users/$userId/follow'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      print('✅ User unfollowed successfully');
      return data;
    } else {
      final errorData = json.decode(response.body);
      print('❌ Unfollow user failed: ${errorData['message']}');
      throw Exception(errorData['message'] ?? 'Error unfollowing user');
    }
  }

  static Future<Map<String, dynamic>> getProductCategories() async {
    //print('📂 Fetching product categories');

    final response = await http.get(
      Uri.parse('${ApiService.baseUrl}/products/categories'),
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data is List) {
        //print('✅ Categories fetched successfully: ${data.length} categories');
        return {'categories': data, 'count': data.length};
      } else {
        //print('✅ Categories fetched successfully');
        return data;
      }
    } else {
      //print('❌ Categories fetch failed: ${response.body}');
      throw Exception('Error loading categories');
    }
  }

  static Future<Map<String, dynamic>> getProduct(int productId) async {
    //print('📦 Fetching product with ID: $productId');

    final response = await http.get(
      Uri.parse('${ApiService.baseUrl}/products/$productId'),
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      //print('✅ Product fetched successfully: ${data['product']['name']}');
      return data;
    } else {
      final errorData = json.decode(response.body);
      //print('❌ Product fetch failed: ${errorData['message']}');
      throw Exception(errorData['message'] ?? 'Error loading product');
    }
  }

  static Future<Map<String, dynamic>> incrementProductView(
    int productId,
  ) async {
    //print('📊 Incrementing view count for product $productId');

    final response = await http.post(
      Uri.parse('${ApiService.baseUrl}/products/$productId/view'),
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      //print('✅ Product view count incremented');
      return data;
    } else {
      final errorData = json.decode(response.body);
      //print('❌ Failed to increment view count: ${response.statusCode}');
      throw Exception(errorData['message'] ?? 'Error increasing views');
    }
  }

  static Future<Map<String, dynamic>> toggleProductFavorite(
    int productId,
  ) async {
    //print('⭐ Toggling favorite for product $productId');

    final response = await http.post(
      Uri.parse('${ApiService.baseUrl}/products/$productId/favorite'),
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      //print('✅ Product favorite toggled: ${data['action']} (${data['favorite_count']} total)');
      return data;
    } else {
      final errorData = json.decode(response.body);
      //print('❌ Failed to toggle favorite: ${response.statusCode}');
      throw Exception(errorData['message'] ?? 'Error toggling favorite');
    }
  }

  // Cart API methods
  static Future<Map<String, dynamic>> getCart({String? userId}) async {
    //print('🛒 Fetching cart contents');

    final token = await ApiService.getToken();
    final url = userId != null ? '${ApiService.baseUrl}/cart/$userId' : '${ApiService.baseUrl}/cart';
    final response = await http.get(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      //print('✅ Cart fetched successfully: ${data['totalItems']} items');
      return data;
    } else {
      final errorData = json.decode(response.body);
      //print('❌ Failed to fetch cart: ${response.statusCode}');
      throw Exception(errorData['message'] ?? 'Error loading cart');
    }
  }

  static Future<Map<String, dynamic>> addToCart(
    int productId, {
    double quantity = 1,
    int variantIdx = 0,
    String? userId,
  }) async {
    //print('🛒 Adding product $productId (variant $variantIdx) to cart (quantity: $quantity)');

    final token = await ApiService.getToken();
    final url = userId != null
        ? '${ApiService.baseUrl}/cart/$userId/add'
        : '${ApiService.baseUrl}/cart/add';
    final response = await http.post(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: json.encode({
        'productId': productId,
        'quantity': quantity,
        'variantIdx': variantIdx,
      }),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      //print('✅ Product added to cart: ${data['totalItems']} total items');
      return data;
    } else {
      final errorData = json.decode(response.body);
      //print('❌ Failed to add to cart: ${response.statusCode}');
      throw Exception(errorData['message'] ?? 'Error adding to cart');
    }
  }

  static Future<Map<String, dynamic>> removeFromCart(
    int productId, {
    int variantIdx = 0,
    String? userId,
  }) async {
    //print('🛒 Removing product $productId (variant $variantIdx) from cart');

    final token = await ApiService.getToken();
    final baseUrlPath = userId != null
        ? '${ApiService.baseUrl}/cart/$userId/remove/$productId'
        : '${ApiService.baseUrl}/cart/remove/$productId';
    final url = '$baseUrlPath?variantIdx=$variantIdx';
    final response = await http.delete(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      //print('✅ Product removed from cart: ${data['totalItems']} total items');
      return data;
    } else {
      final errorData = json.decode(response.body);
      //print('❌ Failed to remove from cart: ${response.statusCode}');
      throw Exception(errorData['message'] ?? 'Error removing from cart');
    }
  }

  static Future<Map<String, dynamic>> updateCartQuantity(
    int productId,
    int quantity, {
    int variantIdx = 0,
    String? userId,
  }) async {
    //print('🛒 Updating cart quantity for product $productId (variant $variantIdx) to $quantity');

    final token = await ApiService.getToken();
    final url = userId != null
        ? '${ApiService.baseUrl}/cart/$userId/update'
        : '${ApiService.baseUrl}/cart/update';
    final response = await http.put(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: json.encode({
        'productId': productId,
        'quantity': quantity,
        'variantIdx': variantIdx,
      }),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      //print('✅ Cart quantity updated: ${data['totalItems']} total items');
      return data;
    } else {
      final errorData = json.decode(response.body);
      //print('❌ Failed to update cart quantity: ${response.statusCode}');
      throw Exception(errorData['message'] ?? 'Error updating quantity');
    }
  }

  static Future<Map<String, dynamic>> clearCart({String? userId}) async {
    //print('🛒 Clearing cart');

    final token = await ApiService.getToken();
    final url = userId != null
        ? '${ApiService.baseUrl}/cart/$userId/clear'
        : '${ApiService.baseUrl}/cart/clear';
    final response = await http.delete(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      //print('✅ Cart cleared successfully');
      return data;
    } else {
      final errorData = json.decode(response.body);
      //print('❌ Failed to clear cart: ${response.statusCode}');
      throw Exception(errorData['message'] ?? 'Error clearing cart');
    }
  }

  static Future<Map<String, dynamic>> getCartSummary({String? userId}) async {
    //print('🛒 Fetching cart summary');

    final token = await ApiService.getToken();
    final url = userId != null
        ? '${ApiService.baseUrl}/cart/$userId/summary'
        : '${ApiService.baseUrl}/cart/summary';
    final response = await http.get(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      //print('✅ Cart summary fetched: ${data['totalItems']} items');
      return data;
    } else {
      final errorData = json.decode(response.body);
      //print('❌ Failed to fetch cart summary: ${response.statusCode}');
      throw Exception(errorData['message'] ?? 'Error loading cart summary');
    }
  }

  // ==================== ORDERS API ====================

  // Get user orders (New implementation)
  static Future<Map<String, dynamic>> getUserOrders() async {
    print('📦 Fetching user orders');
    final sessionAtRequest = _currentSessionId;  // Capture session BEFORE request
    print('📍 Orders request session ID: $sessionAtRequest');

    final token = await ApiService.getToken();
    print('🔑 Token: ${token?.substring(0, 20)}...');
    if (token == null || token.isEmpty) {
      print('❌ No auth token found');
      throw Exception('User is not logged in');
    }

    final response = await http.get(
      Uri.parse('${ApiService.baseUrl}/orders'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    // Validate session AFTER response arrives
    if (sessionAtRequest != _currentSessionId) {
      print('⚠️ Session changed during orders request!');
      print('🚫 IGNORING orders response (from old login session)');
      throw Exception('Session changed - please retry');
    }

    print('📡 Response status: ${response.statusCode}');
    if (response.statusCode == 200) {
      try {
        final data = json.decode(response.body);
        print('✅ Orders fetched successfully (session valid): ${data['count']} orders');
        print('📊 Orders data: success=${data['success']}, orders length=${(data['orders'] as List?)?.length}');
        return data;
      } catch (e) {
        //print('❌ Failed to parse orders response: $e');
        throw Exception('Invalid response format');
      }
    } else if (response.statusCode == 429) {
      //print('❌ Rate limit exceeded');
      throw Exception('Too many requests. Please wait a moment and try again.');
    } else {
      try {
        final errorData = json.decode(response.body);
        //print('❌ Failed to fetch orders: ${response.statusCode}');
        throw Exception(errorData['message'] ?? 'Error loading orders');
      } catch (e) {
        // If response is not JSON, use the status code
        //print('❌ Non-JSON error response: ${response.body}');
        throw Exception('Server error (${response.statusCode}). Please try again later.');
      }
    }
  }

  // Get single order by ID
  static Future<Map<String, dynamic>> getOrder(int orderId) async {
    //print('📦 Fetching order $orderId');

    final token = await ApiService.getToken();
    final response = await http.get(
      Uri.parse('${ApiService.baseUrl}/orders/$orderId'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      //print('✅ Order $orderId fetched successfully');
      return data;
    } else {
      final errorData = json.decode(response.body);
      //print('❌ Failed to fetch order $orderId: ${response.statusCode}');
      throw Exception(errorData['message'] ?? 'Error loading order');
    }
  }

  // Sync order statuses with Stripe
  static Future<Map<String, dynamic>> syncOrderStatusesWithStripe() async {
    //print('🔄 Syncing order statuses with Stripe');

    final token = await ApiService.getToken();
    if (token == null || token.isEmpty) {
      //print('❌ No auth token found');
      throw Exception('User is not logged in');
    }

    try {
      final response = await http
          .get(
            Uri.parse('${ApiService.baseUrl}/stripe/sync-order-statuses'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw Exception('Request timeout');
            },
          );

      // Check for rate limiting before parsing JSON
      if (response.statusCode == 429) {
        //print('⚠️ Rate limited by server');
        throw Exception('Too many requests - please try again later');
      }

      if (response.statusCode == 200) {
        try {
          final data = json.decode(response.body);
          //print('✅ Order statuses synced successfully: ${data['updated']} orders updated');
          return data;
        } catch (jsonError) {
          //print('❌ Invalid JSON response from server');
          throw Exception('Invalid response from server');
        }
      } else {
        // Try to parse error response, but handle non-JSON responses
        try {
          final errorData = json.decode(response.body);
          //print('❌ Failed to sync order statuses: ${response.statusCode}');
          throw Exception(
            errorData['message'] ?? 'Error syncing order statuses',
          );
        } catch (jsonError) {
          // If response is not JSON (e.g., HTML error page), use status code
          //print('❌ Non-JSON error response: ${response.statusCode}');
          if (response.statusCode == 429) {
            throw Exception('Too many requests - please try again later');
          }
          throw Exception('Server error: ${response.statusCode}');
        }
      }
    } catch (e) {
      // Silently fail for rate limiting during background sync
      if (e.toString().contains('Too many requests') ||
          e.toString().contains('Rate limit')) {
        //print('⚠️ Skipping sync due to rate limiting');
        return {'success': false, 'message': 'Rate limited'};
      }
      rethrow;
    }
  }

  // Mark order as received by customer
  static Future<Map<String, dynamic>> markOrderAsReceived(int orderId) async {
    //print('📦 Marking order $orderId as received');

    final token = await ApiService.getToken();
    if (token == null || token.isEmpty) {
      //print('❌ No auth token found');
      throw Exception('User is not logged in');
    }

    final response = await http.put(
      Uri.parse('${ApiService.baseUrl}/orders/$orderId/received'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      //print('✅ Order marked as received successfully');
      return data;
    } else {
      final errorData = json.decode(response.body);
      //print('❌ Failed to mark order as received: ${response.statusCode}');
      throw Exception(
        errorData['error'] ?? errorData['message'] ?? 'Error marking order as received',
      );
    }
  }

  // Download invoice PDF for an order
  static Future<Uint8List> downloadInvoicePdf(int orderId) async {
    final token = await ApiService.getToken();
    if (token == null || token.isEmpty) {
      throw Exception('User is not logged in');
    }

    final response = await http
        .get(
          Uri.parse('${ApiService.baseUrl}/orders/$orderId/invoice'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(_timeoutDuration * 3); // Longer timeout for PDF download

    if (response.statusCode == 200) {
      return response.bodyBytes;
    } else {
      String errorMessage = 'Error downloading invoice';
      try {
        final errorData = json.decode(response.body);
        errorMessage = errorData['error'] ?? errorMessage;
      } catch (_) {}
      throw Exception(errorMessage);
    }
  }

  // Send invoice email for an order
  static Future<Map<String, dynamic>> sendInvoiceEmail(int orderId) async {
    final token = await ApiService.getToken();
    if (token == null || token.isEmpty) {
      return {'success': false, 'message': 'User is not logged in'};
    }

    try {
      final response = await http
          .post(
            Uri.parse('${ApiService.baseUrl}/orders/$orderId/send-invoice'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(ApiService._timeoutDuration);

      final data = json.decode(response.body);
      
      if (response.statusCode == 200) {
        return data;
      } else {
        return {
          'success': false,
          'message': data['error'] ?? 'Failed to send invoice'
        };
      }
    } catch (e) {
      print('❌ Error sending invoice email: $e');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}'
      };
    }
  }

  // Get driver's live location for an order
  static Future<Map<String, dynamic>> getDriverLocation(int orderId) async {
    final token = await ApiService.getToken();
    if (token == null || token.isEmpty) {
      throw Exception('User is not logged in');
    }

    final response = await http
        .get(
          Uri.parse('${ApiService.baseUrl}/orders/$orderId/driver-location'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        )
        .timeout(ApiService._timeoutDuration);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data;
    } else {
      final errorData = json.decode(response.body);
      throw Exception(errorData['message'] ?? 'Error loading driver location');
    }
  }

  // Scan and validate QR code for order delivery
  static Future<Map<String, dynamic>> scanOrderQRCode(
    int orderId,
    String scannedQRCode,
    String? securityCode,
  ) async {
    final token = await ApiService.getToken();
    if (token == null || token.isEmpty) {
      throw Exception('User is not logged in');
    }

    final response = await http
        .put(
          Uri.parse('${ApiService.baseUrl}/orders/$orderId/scan-qr'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: json.encode({
            'scannedQRCode': scannedQRCode,
            'securityCode': securityCode,
          }),
        )
        .timeout(ApiService._timeoutDuration);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data;
    } else {
      final errorData = json.decode(response.body);
      throw Exception(errorData['message'] ?? 'QR Code validation failed');
    }
  }

  // Request photos from driver
  static Future<Map<String, dynamic>> requestDriverPhotos({
    required int orderId,
    required String note,
  }) async {
    final token = await ApiService.getToken();
    if (token == null || token.isEmpty) {
      throw Exception('User is not logged in');
    }

    final response = await http
        .post(
          Uri.parse('${ApiService.baseUrl}/orders/$orderId/request-photos'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: json.encode({'note': note}),
        )
        .timeout(ApiService._timeoutDuration);

    if (response.statusCode == 200 || response.statusCode == 201) {
      return json.decode(response.body);
    } else {
      final errorData = json.decode(response.body);
      throw Exception(errorData['message'] ?? 'Failed to request photos');
    }
  }

  // Get photo requests for an order
  static Future<Map<String, dynamic>> getPhotoRequests(int orderId) async {
    final token = await ApiService.getToken();
    if (token == null || token.isEmpty) {
      throw Exception('User is not logged in');
    }

    final response = await http
        .get(
          Uri.parse('${ApiService.baseUrl}/orders/$orderId/photo-requests'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        )
        .timeout(ApiService._timeoutDuration);

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      final errorData = json.decode(response.body);
      throw Exception(errorData['message'] ?? 'Failed to get photo requests');
    }
  }

  // Send message to seller or driver
  static Future<Map<String, dynamic>> sendMessage({
    required int orderId,
    required String recipientType,
    required String message,
  }) async {
    final token = await ApiService.getToken();
    if (token == null || token.isEmpty) {
      throw Exception('User is not logged in');
    }

    final response = await http
        .post(
          Uri.parse('${ApiService.baseUrl}/messages/order/$orderId'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: json.encode({
            'recipientType': recipientType, // 'seller' or 'driver'
            'message': message,
          }),
        )
        .timeout(ApiService._timeoutDuration);

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = json.decode(response.body);
      return data;
    } else {
      final errorData = json.decode(response.body);
      throw Exception(errorData['message'] ?? 'Failed to send message');
    }
  }

  // Create Stripe Payment Intent for checkout
  static Future<Map<String, dynamic>> createStripePayment(
    Map<String, dynamic> paymentData,
    String accessToken,
  ) async {
    try {
      print('💳 Creating Stripe Payment Intent...');
      print('🌐 API URL: $baseUrl/stripe/create-payment-intent');

      // DEVELOPMENT: Use test token for local server testing
      String debugToken = accessToken;
      if (baseUrl.contains('192.168.0.183')) {
        debugToken =
            'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VybmFtZSI6ImFya2FkaXkiLCJlbWFpbCI6ImFya2FkaXlAZXhhbXBsZS5jb20iLCJmaXJzdG5hbWUiOiJBcmthZGl5IiwibGFzdG5hbWUiOiJUZXN0IiwiaWF0IjoxNzU4MjA1NzI0LCJleHAiOjE3NTg4MTA1MjR9.hoIjzKzfjMrCl4AoiAdDQ3ZZdPYhtFvD8yDOp0XB9Mc';
        print('🔧 Using debug token for local server');
      }

      print('🔑 Token (first 20 chars): ${debugToken.substring(0, 20)}...');
      print('💰 Payment data: $paymentData');

      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/stripe/create-payment-intent'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $debugToken',
        },
        body: json.encode(paymentData),
      );

      print('💳 Stripe Payment response status: ${response.statusCode}');
      print('💳 Stripe Payment response body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return data['paymentIntent'] ?? data;
        } else {
          throw Exception(data['message'] ?? 'Stripe payment creation failed');
        }
      } else {
        final errorData = json.decode(response.body);
        throw Exception(
          errorData['message'] ??
              'Stripe payment error: ${response.statusCode}',
        );
      }
    } catch (e) {
      print('❌ Error creating Stripe payment: $e');
      throw Exception('Payment creation failed: $e');
    }
  }

  // Create Stripe Virtual Account for payment terms
  static Future<Map<String, dynamic>> createVirtualAccount(
    Map<String, dynamic> accountData,
    String accessToken,
  ) async {
    try {
      print('🏦 Creating Stripe Virtual Account for payment terms...');
      print('🌐 API URL: $baseUrl/stripe/create-virtual-account');

      // DEVELOPMENT: Use test token for local server testing
      String debugToken = accessToken;
      if (baseUrl.contains('192.168.0.183')) {
        debugToken =
            'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VybmFtZSI6ImFya2FkaXkiLCJlbWFpbCI6ImFya2FkaXlAZXhhbXBsZS5jb20iLCJmaXJzdG5hbWUiOiJBcmthZGl5IiwibGFzdG5hbWUiOiJUZXN0IiwiaWF0IjoxNzU4MjA1NzI0LCJleHAiOjE3NTg4MTA1MjR9.hoIjzKzfjMrCl4AoiAdDQ3ZZdPYhtFvD8yDOp0XB9Mc';
        print('🔧 Using debug token for local server');
      }

      print('🔑 Token (first 20 chars): ${debugToken.substring(0, 20)}...');
      print('🏢 Account data: $accountData');

      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/stripe/create-virtual-account'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $debugToken',
        },
        body: json.encode(accountData),
      );

      print('🏦 Virtual Account response status: ${response.statusCode}');
      print('🏦 Virtual Account response body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return data;
        } else {
          throw Exception(data['message'] ?? 'Virtual account creation failed');
        }
      } else {
        final errorData = json.decode(response.body);
        throw Exception(
          errorData['message'] ??
              'Virtual account error: ${response.statusCode}',
        );
      }
    } catch (e) {
      print('❌ Error creating virtual account: $e');
      throw Exception('Virtual account creation failed: $e');
    }
  }

  // Create new order
  static Future<Map<String, dynamic>> createOrder(
    Map<String, dynamic> orderData,
    String accessToken,
  ) async {
    try {
      // DEVELOPMENT: Use debug token for local server testing
      String debugToken = accessToken;
      if (baseUrl.contains('192.168.0.183')) {
        debugToken =
            'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VybmFtZSI6ImFya2FkaXkiLCJlbWFpbCI6ImFya2FkaXlAZXhhbXBsZS5jb20iLCJmaXJzdG5hbWUiOiJBcmthZGl5IiwibGFzdG5hbWUiOiJUZXN0IiwiaWF0IjoxNzU4MjA1NzI0LCJleHAiOjE3NTg4MTA1MjR9.hoIjzKzfjMrCl4AoiAdDQ3ZZdPYhtFvD8yDOp0XB9Mc';
        print('🔧 Using debug token for local server order creation');
      }

      print('📦 Creating order at: $baseUrl/orders/create');
      print('📦 Order data: $orderData');

      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/orders/create'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $debugToken',
        },
        body: json.encode(orderData),
      );

      print('📦 Order creation response status: ${response.statusCode}');
      print('📦 Order creation response body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        return data;
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['message'] ?? 'Error creating order');
      }
    } catch (e) {
      print('❌ Error creating order: $e');
      throw Exception('Error creating order: $e');
    }
  }

  // ==================== MESSAGES API ====================

  // Get user conversations
  static Future<Map<String, dynamic>> getConversations() async {
    //print('💬 Fetching user conversations');

    final token = await ApiService.getToken();
    final response = await http.get(
      Uri.parse('${ApiService.baseUrl}/messages/conversations'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      //print('✅ Conversations fetched successfully: ${data['data'].length} conversations');
      return data;
    } else {
      final errorData = json.decode(response.body);
      //print('❌ Failed to fetch conversations: ${response.statusCode}');
      throw Exception(errorData['message'] ?? 'Error loading conversations');
    }
  }

  // Get messages for a conversation
  static Future<Map<String, dynamic>> getConversationMessages(
    String conversationId, {
    int page = 1,
    int limit = 50,
  }) async {
    //print('💬 Fetching messages for conversation $conversationId');

    final token = await ApiService.getToken();
    final response = await http.get(
      Uri.parse(
        '${ApiService.baseUrl}/messages/conversations/$conversationId/messages?page=$page&limit=$limit',
      ),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      //print('✅ Messages fetched successfully: ${data['data'].length} messages');
      return data;
    } else {
      final errorData = json.decode(response.body);
      //print('❌ Failed to fetch messages: ${response.statusCode}');
      throw Exception(errorData['message'] ?? 'Error loading messages');
    }
  }

  // Send a message in a conversation
  static Future<Map<String, dynamic>> sendConversationMessage(
    String conversationId,
    String messageText, {
    String messageType = 'text',
    String? fileUrl,
  }) async {
    //print('💬 Sending message to conversation $conversationId');

    final token = await ApiService.getToken();
    final response = await http.post(
      Uri.parse('${ApiService.baseUrl}/messages/conversations/$conversationId/messages'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: json.encode({
        'message_text': messageText,
        'message_type': messageType,
        'file_url': ?fileUrl,
      }),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      //print('✅ Message sent successfully');
      return data;
    } else {
      final errorData = json.decode(response.body);
      //print('❌ Failed to send message: ${response.statusCode}');
      throw Exception(errorData['message'] ?? 'Error sending message');
    }
  }

  // Create or get conversation with another user
  static Future<Map<String, dynamic>> createConversation(
    String otherUsername,
  ) async {
    //print('💬 Creating/getting conversation with $otherUsername');

    final token = await ApiService.getToken();
    final response = await http.post(
      Uri.parse('${ApiService.baseUrl}/messages/conversations'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: json.encode({'other_username': otherUsername}),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      //print('✅ Conversation created/found successfully');
      return data;
    } else {
      final errorData = json.decode(response.body);
      //print('❌ Failed to create conversation: ${response.statusCode}');
      throw Exception(errorData['message'] ?? 'Error creating conversation');
    }
  }

  // Search users
  static Future<Map<String, dynamic>> searchUsers(String query) async {
    //print('🔍 Searching users with query: $query');

    final token = await ApiService.getToken();
    final response = await http.get(
      Uri.parse(
        '${ApiService.baseUrl}/messages/users/search?q=${Uri.encodeComponent(query)}',
      ),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      //print('✅ User search completed: ${data['data'].length} users found');
      return data;
    } else {
      final errorData = json.decode(response.body);
      //print('❌ Failed to search users: ${response.statusCode}');
      throw Exception(errorData['message'] ?? 'Error searching users');
    }
  }

  // Get user addresses (with automatic token)
  static Future<List<Map<String, dynamic>>> getUserAddresses() async {
    print('🔐 Starting getUserAddresses...');
    final token = await ApiService.getToken();
    if (token == null) {
      print('❌ No token found - user not logged in');
      throw Exception('Not logged in');
    }
    print('✅ Token found: ${token.substring(0, 10)}...');

    try {
      print('📡 Calling getAddresses with token...');
      final result = await getAddresses(token);
      print('📍 getAddresses result: $result');
      print('📍 getAddresses result type: ${result.runtimeType}');
      print('📍 Response keys: ${result.keys}');

      // Handle different possible response formats
      List<Map<String, dynamic>> addresses = [];

      if (result['addresses'] != null && result['addresses'] is List) {
        addresses = List<Map<String, dynamic>>.from(result['addresses']);
        print(
          '✅ Found addresses in result["addresses"]: ${addresses.length} addresses',
        );
      } else if (result['data'] != null && result['data'] is List) {
        addresses = List<Map<String, dynamic>>.from(result['data']);
        print(
          '✅ Found addresses in result["data"]: ${addresses.length} addresses',
        );
      } else {
        // Try to find any array in the response
        for (var key in result.keys) {
          final value = result[key];
          if (value is List) {
            addresses = List<Map<String, dynamic>>.from(value);
            print(
              '✅ Found addresses in result["$key"]: ${addresses.length} addresses',
            );
            break;
          }
        }

        // If still no addresses found, show what we got
        if (addresses.isEmpty) {
          print(
            '⚠️ No address arrays found in response. Available keys: ${result.keys}',
          );
          for (var key in result.keys) {
            print('  $key: ${result[key]} (${result[key].runtimeType})');
          }
        }
      }

      print('✅ Final addresses list: $addresses');
      return addresses;
    } catch (e, stackTrace) {
      print('❌ Error loading user addresses: $e');
      print('Stack trace: $stackTrace');
      return [];
    }
  }

  // Process Stripe payment
  static Future<Map<String, dynamic>> processStripePayment(
    Map<String, dynamic> paymentData,
  ) async {
    //print('💳 Processing Stripe payment...');

    final token = await ApiService.getToken();
    if (token == null) {
      throw Exception('Not logged in');
    }

    try {
      final response = await http
          .post(
            Uri.parse('${ApiService.baseUrl}/stripe/process-payment'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: json.encode(paymentData),
          )
          .timeout(ApiService._timeoutDuration);

      final responseData = json.decode(response.body);

      if (response.statusCode == 200) {
        //print('✅ Payment processed successfully');
        return {
          'success': true,
          'payment_intent': responseData['payment_intent'],
          'order_id': responseData['order_id'],
          'message': responseData['message'] ?? 'Payment successful',
        };
      } else {
        //print('❌ Payment failed: ${response.statusCode}');
        return {
          'success': false,
          'message': responseData['message'] ?? 'Payment failed',
          'error': responseData['error'],
        };
      }
    } catch (e) {
      //print('❌ Payment processing error: $e');
      return {
        'success': false,
        'message': 'Payment processing failed: ${e.toString()}',
      };
    }
  }

  // Delete account
  static Future<Map<String, dynamic>> deleteAccount({
    required String password,
  }) async {
    final token = await ApiService.getToken();
    if (token == null) {
      return {'success': false, 'message': 'Not authenticated'};
    }

    try {
      final response = await http
          .delete(
            Uri.parse('${ApiService.baseUrl}/users/account'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: json.encode({
              'password': password,
              'confirmation': 'DELETE_MY_ACCOUNT',
            }),
          )
          .timeout(ApiService._timeoutDuration);

      final responseData = json.decode(response.body);

      if (response.statusCode == 200) {
        print('✅ Account deleted successfully');
        // Clear tokens after deletion
        await clearToken();
        return {
          'success': true,
          'message': responseData['message'] ?? 'Account deleted successfully',
        };
      } else {
        print('❌ Account deletion failed: ${response.statusCode}');
        return {
          'success': false,
          'message': responseData['message'] ?? 'Failed to delete account',
          'error': responseData['error'],
        };
      }
    } catch (e) {
      print('❌ Account deletion error: $e');
      return {
        'success': false,
        'message': 'Error deleting account: ${e.toString()}',
      };
    }
  }

  // Submit review for an order
  static Future<Map<String, dynamic>> submitReview({
    required int orderId,
    String? sellerUsername,
    String? driverUsername,
    int? sellerRating,
    int? driverRating,
    String? sellerReviewText,
    String? driverReviewText,
    int? productId,
  }) async {
    final token = await ApiService.getToken();
    if (token == null || token.isEmpty) {
      throw Exception('User is not logged in');
    }

    final response = await http
        .post(
          Uri.parse('${ApiService.baseUrl}/reviews'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: json.encode({
            'orderId': orderId,
            'sellerUsername': sellerUsername,
            'driverUsername': driverUsername,
            'sellerRating': sellerRating,
            'driverRating': driverRating,
            'sellerReviewText': sellerReviewText,
            'driverReviewText': driverReviewText,
            'productId': productId,
          }),
        )
        .timeout(ApiService._timeoutDuration);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data;
    } else {
      final errorData = json.decode(response.body);
      throw Exception(errorData['message'] ?? 'Failed to submit review');
    }
  }

  // Check review status for an order
  static Future<Map<String, dynamic>> getReviewStatus(int orderId) async {
    final token = await ApiService.getToken();
    if (token == null || token.isEmpty) {
      throw Exception('User is not logged in');
    }

    final response = await http
        .get(
          Uri.parse('${ApiService.baseUrl}/reviews/status/$orderId'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        )
        .timeout(ApiService._timeoutDuration);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data;
    } else {
      final errorData = json.decode(response.body);
      throw Exception(errorData['message'] ?? 'Failed to get review status');
    }
  }

  // ==================== PUSH NOTIFICATIONS ====================

  static Future<bool> registerDevicePushToken({
    required String token,
    String? platform,
    String appName = 'cultioo_app',
  }) async {
    final accessToken = await ApiService.getToken();
    if (accessToken == null || accessToken.isEmpty || token.isEmpty) {
      return false;
    }

    try {
      final response = await http
          .post(
            Uri.parse('${ApiService.baseUrl}/notifications/register-device'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $accessToken',
            },
            body: json.encode({
              'token': token,
              'platform': platform,
              'app_name': appName,
            }),
          )
          .timeout(ApiService._timeoutDuration);

      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      print('⚠️ Failed to register push token: $e');
      return false;
    }
  }

  static Future<bool> unregisterDevicePushToken(String token) async {
    final accessToken = await ApiService.getToken();
    if (accessToken == null || accessToken.isEmpty || token.isEmpty) {
      return false;
    }

    try {
      final response = await http
          .post(
            Uri.parse('${ApiService.baseUrl}/notifications/unregister-device'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $accessToken',
            },
            body: json.encode({'token': token}),
          )
          .timeout(ApiService._timeoutDuration);

      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      print('⚠️ Failed to unregister push token: $e');
      return false;
    }
  }

  // Send order success push notification
  static Future<void> sendOrderNotification({
    required String accessToken,
    required String productName,
    required double totalAmount,
    required String orderId,
  }) async {
    try {
      print('📱 Sending order notification...');
      print('  - Product: $productName');
      print('  - Amount: \$$totalAmount');
      print('  - Order ID: $orderId');

      final response = await http
          .post(
            Uri.parse('${ApiService.baseUrl}/notifications/order-success'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $accessToken',
            },
            body: json.encode({
              'productName': productName,
              'totalAmount': totalAmount,
              'orderId': orderId,
            }),
          )
          .timeout(ApiService._timeoutDuration);

      if (response.statusCode == 200) {
        print('✅ Order notification sent successfully');
      } else {
        print('⚠️ Failed to send notification: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error sending order notification: $e');
      // Don't throw - notification failure shouldn't block order creation
    }
  }

  // Generate Virtual Stripe Account for Payment Terms
  static Future<Map<String, dynamic>> generateVirtualAccount(
    String accessToken,
    String paymentType,
    String businessName,
    String businessEmail,
    String country,
  ) async {
    try {
      print('🏦 Generating virtual account...');
      print('  - Payment Type: $paymentType');
      print('  - Business Name: $businessName');
      print('  - Country: $country');

      final response = await http
          .post(
            Uri.parse('${ApiService.baseUrl}/stripe/generate-virtual-account'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $accessToken',
            },
            body: json.encode({
              'payment_type': paymentType,
              'business_name': businessName,
              'business_email': businessEmail,
              'country': country,
            }),
          )
          .timeout(ApiService._timeoutDuration);

      print('🏦 Virtual account response status: ${response.statusCode}');
      print('🏦 Virtual account response body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return data;
        } else {
          throw Exception(data['error'] ?? 'Virtual account generation failed');
        }
      } else {
        final errorData = json.decode(response.body);
        throw Exception(
          errorData['error'] ?? 'Virtual account error: ${response.statusCode}',
        );
      }
    } catch (e) {
      print('❌ Error generating virtual account: $e');
      throw Exception('Virtual account generation failed: $e');
    }
  }

  // Schedule Payment Reminder Email via Mailgun
  static Future<void> schedulePaymentReminder({
    required String accessToken,
    required String orderId,
    required String customerEmail,
    required String businessName,
    required double totalAmount,
    required DateTime dueDate,
    required DateTime reminderDate,
  }) async {
    try {
      print('📧 Scheduling payment reminder...');
      print('  - Order ID: $orderId');
      print('  - Customer Email: $customerEmail');
      print('  - Reminder Date (Day 25): ${reminderDate.toIso8601String()}');

      final response = await http
          .post(
            Uri.parse('${ApiService.baseUrl}/stripe/schedule-payment-reminder'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $accessToken',
            },
            body: json.encode({
              'order_id': orderId,
              'customer_email': customerEmail,
              'business_name': businessName,
              'total_amount': totalAmount,
              'due_date': dueDate.toIso8601String(),
              'reminder_date': reminderDate.toIso8601String(),
            }),
          )
          .timeout(ApiService._timeoutDuration);

      print('📧 Reminder schedule response status: ${response.statusCode}');
      print('📧 Reminder schedule response body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          print('✅ Payment reminder scheduled successfully');
        } else {
          print('⚠️ Reminder scheduling failed: ${data['error']}');
        }
      } else {
        print('⚠️ Failed to schedule reminder: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error scheduling payment reminder: $e');
      // Don't throw - reminder failure shouldn't block order creation
    }
  }

  // Business Verification Methods

  // Check if business is eligible for Net Payment
  static Future<Map<String, dynamic>> checkBusinessEligibility(
    String accessToken,
    String taxId, {
    String? businessPhone,
  }) async {
    try {
      print('🏢 Checking business eligibility for tax ID: $taxId');

      final response = await http
          .post(
            Uri.parse('${ApiService.baseUrl}/stripe/check-business-eligibility'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $accessToken',
            },
            body: json.encode({
              'tax_id': taxId,
              if (businessPhone != null && businessPhone.isNotEmpty)
                'business_phone': businessPhone,
            }),
          )
          .timeout(ApiService._timeoutDuration);

      print('📋 Eligibility check response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('✅ Eligibility check result: ${data['status']}');
        return data;
      } else {
        print('❌ Eligibility check failed: ${response.statusCode}');
        return {
          'success': false,
          'eligible': false,
          'status': 'error',
          'message': 'Failed to check business eligibility',
        };
      }
    } catch (e) {
      print('❌ Error checking business eligibility: $e');
      return {
        'success': false,
        'eligible': false,
        'status': 'error',
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  // Realtime business registry check (SEC EDGAR, SAM.gov, EU VIES)
  // Called BEFORE submitBusinessVerification to give instant user feedback.
  // No auth token required — returns confidence level and found company details.
  static Future<Map<String, dynamic>> verifyBusinessRealtime({
    required String businessName,
    String? taxId,
    String? postalCode,
    String? city,
    String? state,
    String? country,
    String? dunsNumber,
  }) async {
    try {
      print('🔍 Realtime business registry check: $businessName');
      final response = await http
          .post(
            Uri.parse('${ApiService.baseUrl}/stripe/verify-business-realtime'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'businessName': businessName,
              if (taxId != null && taxId.isNotEmpty) 'taxId': taxId,
              if (postalCode != null && postalCode.isNotEmpty) 'postalCode': postalCode,
              if (city != null && city.isNotEmpty) 'city': city,
              if (state != null && state.isNotEmpty) 'state': state,
              'country': country ?? 'US',
              if (dunsNumber != null && dunsNumber.isNotEmpty) 'dunsNumber': dunsNumber,
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
      return {'success': false, 'confidence': 'not_found'};
    } catch (e) {
      print('⚠️ verifyBusinessRealtime error (non-fatal): $e');
      return {'success': false, 'confidence': 'unavailable'};
    }
  }

  // Submit business verification request
  static Future<Map<String, dynamic>> submitBusinessVerification({
    required String accessToken,
    required String businessName,
    required String taxId,
    // Separate address fields (preferred — matches backend validators exactly)
    String? street,
    String? houseNumber,
    String? postalCode,
    String? city,
    String? state,
    String? country,
    // Legacy combined address (kept for backwards compat)
    String? businessAddress,
    required String businessPhone,
    required String businessEmail,
    String? businessType,
    int? yearsInBusiness,
    double? annualRevenue,
    String? dunsNumber,
  }) async {
    try {
      print('📝 Submitting business verification request');
      print('  - Business: $businessName');
      print('  - Tax ID: $taxId');
      if (dunsNumber != null) print('  - DUNS: $dunsNumber');

      // Parse combined businessAddress into parts if separate fields not provided
      String resolvedStreet     = street     ?? '';
      String resolvedHouseNum   = houseNumber ?? '';
      String resolvedPostal     = postalCode  ?? '';
      String resolvedCity       = city        ?? '';
      String resolvedState      = state       ?? '';
      String resolvedCountry    = country     ?? 'US';

      if ((resolvedStreet.isEmpty || resolvedCity.isEmpty) && businessAddress != null) {
        // best-effort parse of "Street HouseNum, ZIP City, State, Country"
        final parts = businessAddress.split(',').map((s) => s.trim()).toList();
        if (parts.isNotEmpty && resolvedStreet.isEmpty) resolvedStreet     = parts[0];
        if (parts.length > 1 && resolvedCity.isEmpty)   resolvedCity       = parts[1].replaceFirst(RegExp(r'^\d[\d\- ]*'), '').trim();
        if (parts.length > 1 && resolvedPostal.isEmpty) {
          final zipMatch = RegExp(r'\b(\d{5}(?:-\d{4})?)\b').firstMatch(parts[1]);
          if (zipMatch != null) resolvedPostal = zipMatch.group(1)!;
        }
        if (parts.length > 2 && resolvedState.isEmpty)   resolvedState   = parts[2];
        if (parts.length > 3 && resolvedCountry == 'US') resolvedCountry = parts[3];
      }

      final body = <String, dynamic>{
        'businessName':   businessName,
        'taxId':          taxId,
        'street':         resolvedStreet,
        'houseNumber':    resolvedHouseNum,
        'postalCode':     resolvedPostal,
        'city':           resolvedCity,
        'state':          resolvedState,
        'country':        resolvedCountry,
        'businessPhone':  businessPhone,
        'businessEmail':  businessEmail,
        'businessType':     ?businessType,
        'yearsInBusiness':  ?yearsInBusiness,
        'annualRevenue':     ?annualRevenue,
        if (dunsNumber != null && dunsNumber.isNotEmpty) 'dunsNumber': dunsNumber,
      };

      final response = await http
          .post(
            Uri.parse('${ApiService.baseUrl}/stripe/submit-business-verification'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $accessToken',
            },
            body: json.encode(body),
          )
          .timeout(ApiService._timeoutDuration);

      print('📋 Verification submission response: ${response.statusCode}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        print('✅ Verification submission: ${data['message']}');
        return data;
      } else {
        print('❌ Verification submission failed: ${response.statusCode}');
        return {
          'success': false,
          'message': 'Failed to submit business verification',
        };
      }
    } catch (e) {
      print('❌ Error submitting business verification: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  // Get monthly payment terms usage
  static Future<Map<String, dynamic>> getMonthlyPaymentTermsUsage(
    String accessToken,
  ) async {
    try {
      print('📊 Fetching monthly payment terms usage');

      final response = await http
          .get(
            Uri.parse('${ApiService.baseUrl}/stripe/monthly-payment-terms-usage'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $accessToken',
            },
          )
          .timeout(ApiService._timeoutDuration);

      print('📊 Monthly usage response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data;
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['message'] ?? 'Error fetching monthly usage');
      }
    } catch (e) {
      print('❌ Error fetching monthly usage: $e');
      // Return default values instead of throwing
      return {'success': true, 'total_usage': 0.0, 'limit': 75000.0};
    }
  }

  // ==========================================
  // GROUP MANAGEMENT API METHODS
  // ==========================================

  // Get all groups for current user
  static Future<Map<String, dynamic>> getGroups() async {
    try {
      final token = await ApiService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http
          .get(
            Uri.parse('${ApiService.baseUrl}/groups'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
              'Cache-Control': 'no-cache, no-store',
              'Pragma': 'no-cache',
            },
          )
          .timeout(ApiService._timeoutDuration);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return json.decode(response.body);
      }
    } catch (e) {
      print('❌ Error fetching groups: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  // Get single group details
  static Future<Map<String, dynamic>> getGroup(int groupId) async {
    try {
      final token = await ApiService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http
          .get(
            Uri.parse('${ApiService.baseUrl}/groups/$groupId'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(ApiService._timeoutDuration);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return json.decode(response.body);
      }
    } catch (e) {
      print('❌ Error fetching group: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  // Create new group
  static Future<Map<String, dynamic>> createGroup({
    required String name,
    String? description,
    String? imageUrl,
  }) async {
    try {
      final token = await ApiService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http
          .post(
            Uri.parse('${ApiService.baseUrl}/groups'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: json.encode({
              'name': name,
              'description': description,
              'image_url': imageUrl,
            }),
          )
          .timeout(
            const Duration(seconds: 30),
          ); // Longer timeout for group creation

      return json.decode(response.body);
    } catch (e) {
      print('❌ Error creating group: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  // Update group
  static Future<Map<String, dynamic>> updateGroup(
    int groupId, {
    String? name,
    String? description,
    String? imageUrl,
  }) async {
    try {
      final token = await ApiService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http
          .put(
            Uri.parse('${ApiService.baseUrl}/groups/$groupId'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: json.encode({
              'name': ?name,
              'description': ?description,
              'image_url': ?imageUrl,
            }),
          )
          .timeout(ApiService._timeoutDuration);

      return json.decode(response.body);
    } catch (e) {
      print('❌ Error updating group: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  // Delete group
  static Future<Map<String, dynamic>> deleteGroup(int groupId) async {
    try {
      final token = await ApiService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http
          .delete(
            Uri.parse('${ApiService.baseUrl}/groups/$groupId'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(ApiService._timeoutDuration);

      return json.decode(response.body);
    } catch (e) {
      print('❌ Error deleting group: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  // Join group by invite code
  static Future<Map<String, dynamic>> joinGroupByCode(String inviteCode) async {
    try {
      final token = await ApiService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http
          .post(
            Uri.parse('${ApiService.baseUrl}/groups/join-by-code'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: json.encode({'invite_code': inviteCode}),
          )
          .timeout(ApiService._timeoutDuration);

      return json.decode(response.body);
    } catch (e) {
      print('❌ Error joining group: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  // Leave group
  static Future<Map<String, dynamic>> leaveGroup(int groupId) async {
    try {
      final token = await ApiService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http
          .post(
            Uri.parse('${ApiService.baseUrl}/groups/$groupId/leave'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(ApiService._timeoutDuration);

      return json.decode(response.body);
    } catch (e) {
      print('❌ Error leaving group: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  // Remove member from group
  static Future<Map<String, dynamic>> removeMember(
    int groupId,
    String username,
  ) async {
    try {
      final token = await ApiService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http
          .delete(
            Uri.parse('${ApiService.baseUrl}/groups/$groupId/members/$username'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(ApiService._timeoutDuration);

      return json.decode(response.body);
    } catch (e) {
      print('❌ Error removing member: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  // Change member role
  static Future<Map<String, dynamic>> changeMemberRole(
    int groupId,
    String username,
    String role,
  ) async {
    try {
      final token = await ApiService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http
          .put(
            Uri.parse('${ApiService.baseUrl}/groups/$groupId/members/$username/role'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: json.encode({'role': role}),
          )
          .timeout(ApiService._timeoutDuration);

      return json.decode(response.body);
    } catch (e) {
      print('❌ Error changing member role: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  // Transfer ownership
  static Future<Map<String, dynamic>> transferOwnership(
    int groupId,
    String newOwnerUsername,
  ) async {
    try {
      final token = await ApiService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http
          .post(
            Uri.parse('${ApiService.baseUrl}/groups/$groupId/transfer-ownership'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: json.encode({'new_owner_username': newOwnerUsername}),
          )
          .timeout(ApiService._timeoutDuration);

      return json.decode(response.body);
    } catch (e) {
      print('❌ Error transferring ownership: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  // Update member settings (spending limit, approval requirement)
  static Future<Map<String, dynamic>> updateMemberSettings(
    int groupId,
    String username, {
    double? spendingLimit,
    double? monthlyLimit,
    bool? requiresApproval,
    bool? canApprovePurchases,
  }) async {
    try {
      final token = await ApiService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http
          .put(
            Uri.parse('${ApiService.baseUrl}/groups/$groupId/members/$username/settings'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: json.encode({
              'spending_limit': ?spendingLimit,
              'monthly_limit': ?monthlyLimit,
              'requires_approval': ?requiresApproval,
              'can_approve_purchases': ?canApprovePurchases,
            }),
          )
          .timeout(ApiService._timeoutDuration);

      return json.decode(response.body);
    } catch (e) {
      print('❌ Error updating member settings: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  // Update group settings
  static Future<Map<String, dynamic>> updateGroupSettings(
    int groupId, {
    bool? requireApprovalForAll,
    double? approvalThreshold,
    bool? allowMemberInvites,
    bool? notifyOwnerOnPurchase,
    bool? autoApproveBelowThreshold,
    int? maxMembers,
    double? defaultSpendingLimit,
  }) async {
    try {
      final token = await ApiService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http
          .put(
            Uri.parse('${ApiService.baseUrl}/groups/$groupId/settings'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: json.encode({
              'require_approval_for_all': ?requireApprovalForAll,
              'approval_threshold': ?approvalThreshold,
              'allow_member_invites': ?allowMemberInvites,
              'notify_owner_on_purchase': ?notifyOwnerOnPurchase,
              'auto_approve_below_threshold': ?autoApproveBelowThreshold,
              'max_members': ?maxMembers,
              'default_spending_limit': ?defaultSpendingLimit,
            }),
          )
          .timeout(ApiService._timeoutDuration);

      return json.decode(response.body);
    } catch (e) {
      print('❌ Error updating group settings: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  // Regenerate invite code
  static Future<Map<String, dynamic>> regenerateInviteCode(int groupId) async {
    try {
      final token = await ApiService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http
          .post(
            Uri.parse('${ApiService.baseUrl}/groups/$groupId/regenerate-invite-code'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(ApiService._timeoutDuration);

      return json.decode(response.body);
    } catch (e) {
      print('❌ Error regenerating invite code: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  // ==========================================
  // PURCHASE APPROVAL API METHODS
  // ==========================================

  // Get pending approvals for groups where user can approve
  static Future<Map<String, dynamic>> getPendingApprovals() async {
    try {
      final token = await ApiService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http
          .get(
            Uri.parse('${ApiService.baseUrl}/groups/my-pending-approvals'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
              'Cache-Control': 'no-cache, no-store',
              'Pragma': 'no-cache',
            },
          )
          .timeout(ApiService._timeoutDuration);

      return json.decode(response.body);
    } catch (e) {
      print('❌ Error fetching pending approvals: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  // Get approvals for a specific group
  static Future<Map<String, dynamic>> getGroupApprovals(
    int groupId, {
    String? status,
  }) async {
    try {
      final token = await ApiService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      String url = '${ApiService.baseUrl}/groups/$groupId/approvals';
      if (status != null) {
        url += '?status=$status';
      }

      final response = await http
          .get(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(ApiService._timeoutDuration);

      return json.decode(response.body);
    } catch (e) {
      print('❌ Error fetching group approvals: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  // Request purchase approval
  static Future<Map<String, dynamic>> requestPurchaseApproval(
    int groupId, {
    required List<Map<String, dynamic>> cartItems,
    required double totalAmount,
    double? shippingCost,
    String? message,
    Map<String, dynamic>? shippingAddress,
    String? paymentMethodId,
    String? paymentMethodType,
  }) async {
    try {
      final token = await ApiService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http
          .post(
            Uri.parse('${ApiService.baseUrl}/groups/$groupId/approvals'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: json.encode({
              'cart_items': cartItems,
              'total_amount': totalAmount,
              'shipping_cost': ?shippingCost,
              'message': ?message,
              'shipping_address': ?shippingAddress,
              'payment_method_id': ?paymentMethodId,
              'payment_method_type': ?paymentMethodType,
            }),
          )
          .timeout(ApiService._timeoutDuration);

      return json.decode(response.body);
    } catch (e) {
      print('❌ Error requesting purchase approval: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  // Approve or reject purchase request
  static Future<Map<String, dynamic>> processPurchaseApproval(
    int groupId,
    int approvalId,
    String status, {
    String? rejectionReason,
  }) async {
    try {
      final token = await ApiService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http
          .put(
            Uri.parse('${ApiService.baseUrl}/groups/$groupId/approvals/$approvalId'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: json.encode({
              'status': status,
              'rejection_reason': ?rejectionReason,
            }),
          )
          .timeout(ApiService._timeoutDuration);

      return json.decode(response.body);
    } catch (e) {
      print('❌ Error processing purchase approval: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  // Cancel purchase approval request
  static Future<Map<String, dynamic>> cancelPurchaseApproval(
    int groupId,
    int approvalId,
  ) async {
    try {
      final token = await ApiService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http
          .delete(
            Uri.parse('${ApiService.baseUrl}/groups/$groupId/approvals/$approvalId'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(ApiService._timeoutDuration);

      return json.decode(response.body);
    } catch (e) {
      print('❌ Error cancelling purchase approval: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  // Pay for an approved order
  static Future<Map<String, dynamic>> payApprovedOrder(
    int orderId, {
    required String paymentMethodId,
    required String paymentMethodType,
  }) async {
    try {
      final token = await ApiService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http
          .post(
            Uri.parse('${ApiService.baseUrl}/orders/$orderId/pay-approved'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: json.encode({
              'payment_method_id': paymentMethodId,
              'payment_method_type': paymentMethodType,
            }),
          )
          .timeout(ApiService._timeoutDuration);

      return json.decode(response.body);
    } catch (e) {
      print('❌ Error paying approved order: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  // Check if user requires approval for checkout
  static Future<Map<String, dynamic>> checkApprovalRequired({
    double? totalAmount,
  }) async {
    try {
      final token = await ApiService.getToken();
      if (token == null) {
        return {'success': true, 'requires_approval': false};
      }

      String url = '${ApiService.baseUrl}/groups/check-approval-required';
      if (totalAmount != null) {
        url += '?total_amount=$totalAmount';
      }

      final response = await http
          .get(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(ApiService._timeoutDuration);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        // Default to not requiring approval if error
        return {'success': true, 'requires_approval': false};
      }
    } catch (e) {
      print('❌ Error checking approval requirement: $e');
      return {'success': true, 'requires_approval': false};
    }
  }

  // Get group activity log
  static Future<Map<String, dynamic>> getGroupActivity(
    int groupId, {
    int limit = 50,
  }) async {
    try {
      final token = await ApiService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http
          .get(
            Uri.parse('${ApiService.baseUrl}/groups/activity/$groupId?limit=$limit'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(ApiService._timeoutDuration);

      return json.decode(response.body);
    } catch (e) {
      print('❌ Error fetching group activity: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  // ==========================================
  // DRIVER AUCTION SYSTEM
  // ==========================================

  // Start a driver auction for an order
  static Future<Map<String, dynamic>> startDriverAuction(
    int orderId, {
    int durationMinutes = 60,
    double? maxBidPrice,
    double? autoAcceptThreshold,
    bool cullyAiEnabled = false,
    int? minBids,
  }) async {
    try {
      final token = await ApiService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final body = <String, dynamic>{'duration_minutes': durationMinutes};
      if (maxBidPrice != null) body['max_bid_price'] = maxBidPrice;
      if (autoAcceptThreshold != null) body['auto_accept_threshold'] = autoAcceptThreshold;
      if (cullyAiEnabled) body['cully_ai_enabled'] = true;
      if (minBids != null) body['min_bids'] = minBids;

      final response = await http
          .post(
            Uri.parse('${ApiService.baseUrl}/orders/$orderId/auction'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: json.encode(body),
          )
          .timeout(ApiService._timeoutDuration);

      return json.decode(response.body);
    } catch (e) {
      print('❌ Error starting auction: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  // Cully AI – pick best driver for an order's auction
  static Future<Map<String, dynamic>> cullyAiPickBestDriver(int orderId) async {
    try {
      final token = await ApiService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }
      final response = await http
          .get(
            Uri.parse('${ApiService.baseUrl}/orders/$orderId/auction/ai-pick'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(ApiService._timeoutDuration);
      return json.decode(response.body);
    } catch (e) {
      print('❌ Error calling Cully AI: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  // Get auction details and bids for an order
  static Future<Map<String, dynamic>> getOrderAuction(int orderId) async {
    try {
      final token = await ApiService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http
          .get(
            Uri.parse('${ApiService.baseUrl}/orders/$orderId/auction'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(ApiService._timeoutDuration);

      return json.decode(response.body);
    } catch (e) {
      print('❌ Error getting auction: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  // Reset/Delete an expired auction to allow starting a new one
  static Future<Map<String, dynamic>> resetDriverAuction(int orderId) async {
    try {
      final token = await ApiService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http
          .delete(
            Uri.parse('${ApiService.baseUrl}/orders/$orderId/auction'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(ApiService._timeoutDuration);

      // If backend doesn't have this endpoint yet, treat 404 as success
      if (response.statusCode == 404) {
        return {'success': true, 'message': 'Auction reset'};
      }

      return json.decode(response.body);
    } catch (e) {
      print('❌ Error resetting auction: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  // Submit a bid as a driver
  static Future<Map<String, dynamic>> submitDriverBid(
    int orderId, {
    required double bidAmount,
    int? estimatedDeliveryTime,
    String? vehicleType,
    String? message,
  }) async {
    try {
      final token = await ApiService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http
          .post(
            Uri.parse('${ApiService.baseUrl}/orders/$orderId/auction/bid'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: json.encode({
              'bid_amount': bidAmount,
              'estimated_delivery_time': estimatedDeliveryTime,
              'vehicle_type': vehicleType,
              'message': message,
            }),
          )
          .timeout(ApiService._timeoutDuration);

      return json.decode(response.body);
    } catch (e) {
      print('❌ Error submitting bid: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  // Accept a driver bid
  static Future<Map<String, dynamic>> acceptDriverBid(
    dynamic orderId,
    dynamic bidId,
  ) async {
    try {
      final token = await ApiService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      // Safely convert to int
      final int parsedOrderId = orderId is int
          ? orderId
          : int.tryParse(orderId.toString()) ?? 0;
      final int parsedBidId = bidId is int
          ? bidId
          : int.tryParse(bidId.toString()) ?? 0;

      if (parsedOrderId == 0 || parsedBidId == 0) {
        return {'success': false, 'message': 'Invalid order or bid ID'};
      }

      print('📤 Accepting bid: orderId=$parsedOrderId, bidId=$parsedBidId');

      final response = await http
          .post(
            Uri.parse('${ApiService.baseUrl}/orders/$parsedOrderId/auction/accept'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: json.encode({'bid_id': parsedBidId}),
          )
          .timeout(ApiService._timeoutDuration);

      print(
        '📥 Accept bid response: ${response.statusCode} - ${response.body}',
      );
      return json.decode(response.body);
    } catch (e) {
      print('❌ Error accepting bid: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  // Get available drivers near an order for direct selection
  static Future<Map<String, dynamic>> getAvailableDrivers(
    int orderId, {
    double? radiusKm,
    bool includeOccupied = false,
  }) async {
    try {
      final token = await ApiService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      String url = '${ApiService.baseUrl}/orders/$orderId/available-drivers';
      final queryParams = <String>[];
      if (radiusKm != null) queryParams.add('radius_km=$radiusKm');
      if (includeOccupied) queryParams.add('include_occupied=true');
      if (queryParams.isNotEmpty) {
        url += '?${queryParams.join('&')}';
      }

      final response = await http
          .get(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(ApiService._timeoutDuration);

      return json.decode(response.body);
    } catch (e) {
      print('❌ Error getting available drivers: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  // Select a specific driver directly (without auction)
  static Future<Map<String, dynamic>> selectDriverDirectly(
    int orderId,
    int driverId, {
    double? splitRemainingQuantity,
    String? splitUnit,
    double? shippingAmount,
    int? selectedSectionIndex,
  }) async {
    try {
      final token = await ApiService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final body = <String, dynamic>{'driver_id': driverId};
      if (splitRemainingQuantity != null && splitRemainingQuantity > 0 && splitUnit != null) {
        body['split_remaining_quantity'] = splitRemainingQuantity;
        body['split_remaining_unit'] = splitUnit;
      }
      if (shippingAmount != null && shippingAmount > 0) {
        body['shipping_amount'] = shippingAmount;
      }
      if (selectedSectionIndex != null && selectedSectionIndex >= 0) {
        body['selected_section_index'] = selectedSectionIndex;
      }

      final response = await http
          .post(
            Uri.parse('${ApiService.baseUrl}/orders/$orderId/select-driver'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: json.encode(body),
          )
          .timeout(ApiService._timeoutDuration);

      return json.decode(response.body);
    } catch (e) {
      print('❌ Error selecting driver: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  // Split an active auction order into original + overflow part.
  static Future<Map<String, dynamic>> splitAuctionOrder({
    required int auctionId,
    required int sectionIndex,
    required double sectionCapacity,
    required double overflowQuantity,
    required String splitUnit,
  }) async {
    try {
      final token = await ApiService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      print('📦 splitAuctionOrder request: auctionId=$auctionId, sectionIndex=$sectionIndex, capacity=$sectionCapacity, overflow=$overflowQuantity, unit=$splitUnit');

      final response = await http
          .post(
            Uri.parse('${ApiService.baseUrl}/auctions/$auctionId/split-order'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: json.encode({
              'section_index': sectionIndex,
              'section_capacity': sectionCapacity,
              'overflow_quantity': overflowQuantity,
              'split_unit': splitUnit,
            }),
          )
          .timeout(ApiService._timeoutDuration);

      print('📦 splitAuctionOrder response status: ${response.statusCode}');
      print('📦 splitAuctionOrder response body: ${response.body}');

      final decoded = json.decode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      } else {
        return {'success': false, 'message': 'Invalid response format from server'};
      }
    } catch (e) {
      print('❌ Error splitting auction order: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  // Get shipping info for a bid without accepting it
  static Future<Map<String, dynamic>> getShippingInfo(
    dynamic orderId,
    dynamic bidId,
  ) async {
    try {
      final token = await ApiService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      // Safely convert to int
      final int parsedOrderId = orderId is int
          ? orderId
          : int.tryParse(orderId.toString()) ?? 0;
      final int parsedBidId = bidId is int
          ? bidId
          : int.tryParse(bidId.toString()) ?? 0;

      if (parsedOrderId == 0 || parsedBidId == 0) {
        return {'success': false, 'message': 'Invalid order or bid ID'};
      }

      print('📤 Getting shipping info: orderId=$parsedOrderId, bidId=$parsedBidId');

      final response = await http
          .get(
            Uri.parse('${ApiService.baseUrl}/orders/$parsedOrderId/auction/shipping-info/$parsedBidId'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(ApiService._timeoutDuration);

      print(
        '📥 Shipping info response: ${response.statusCode} - ${response.body}',
      );
      return json.decode(response.body);
    } catch (e) {
      print('❌ Error getting shipping info: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  // Close/Delete an order
  static Future<Map<String, dynamic>> closeOrder(int orderId) async {
    try {
      final token = await ApiService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http
          .delete(
            Uri.parse('${ApiService.baseUrl}/orders/$orderId'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(ApiService._timeoutDuration);

      return json.decode(response.body);
    } catch (e) {
      print('❌ Error closing order: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  // Cancel auction
  static Future<Map<String, dynamic>> cancelDriverAuction(int orderId) async {
    try {
      final token = await ApiService.getToken();
      if (token == null) {
        print('❌ Cancel auction: No token');
        return {'success': false, 'message': 'Not authenticated'};
      }

      final url = Uri.parse('${ApiService.baseUrl}/orders/$orderId/auction');
      print('🔴 Cancel auction URL: $url');
      print('🔴 Cancel auction orderId: $orderId');

      final response = await http
          .delete(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(ApiService._timeoutDuration);

      print('🔴 Cancel auction response status: ${response.statusCode}');
      print('🔴 Cancel auction response body: ${response.body}');

      // If backend doesn't have this endpoint yet, treat 404 as success
      if (response.statusCode == 404) {
        return {'success': true, 'message': 'Auction cancelled'};
      }

      return json.decode(response.body);
    } catch (e) {
      print('❌ Error cancelling auction: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  // Toggle Delvioo on/off for a buyer order (before driver is assigned)
  static Future<Map<String, dynamic>> setDelviooEnabled(int orderId, bool enabled) async {
    try {
      final token = await ApiService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http
          .patch(
            Uri.parse('${ApiService.baseUrl}/orders/$orderId/delvioo'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: json.encode({'delvioo': enabled}),
          )
          .timeout(ApiService._timeoutDuration);

      return json.decode(response.body);
    } catch (e) {
      print('❌ Error toggling Delvioo: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  // Get all active auctions (for drivers)
  static Future<Map<String, dynamic>> getActiveAuctions() async {
    try {
      final token = await ApiService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http
          .get(
            Uri.parse('${ApiService.baseUrl}/orders/auctions/active'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(ApiService._timeoutDuration);

      return json.decode(response.body);
    } catch (e) {
      print('❌ Error getting active auctions: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }
}
