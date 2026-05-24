import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';

/// Device-specific storage to prevent iCloud sync issues
/// Each device gets its own isolated storage for credentials
class DeviceStorage {
  static String? _deviceId;
  
  /// Get unique device identifier
  static Future<String> getDeviceId() async {
    if (_deviceId != null) return _deviceId!;
    
    final deviceInfo = DeviceInfoPlugin();
    
    try {
      if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        _deviceId = iosInfo.identifierForVendor ?? 'ios_unknown';
      } else if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        _deviceId = androidInfo.id;
      } else if (Platform.isMacOS) {
        final macInfo = await deviceInfo.macOsInfo;
        _deviceId = macInfo.systemGUID ?? 'macos_unknown';
      } else {
        _deviceId = 'desktop_unknown';
      }
    } catch (e) {
      print('⚠️ Error getting device ID: $e');
      _deviceId = 'fallback_${DateTime.now().millisecondsSinceEpoch}';
    }
    
    print('📱 Device ID: $_deviceId');
    return _deviceId!;
  }
  
  /// Get device-specific key to prevent iCloud sync conflicts
  static Future<String> _getKey(String key) async {
    final deviceId = await getDeviceId();
    return '${key}_$deviceId';
  }
  
  /// Save string with device-specific key
  static Future<void> setString(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    final deviceKey = await _getKey(key);
    await prefs.setString(deviceKey, value);
    print('💾 Saved: $deviceKey');
  }
  
  /// Get string with device-specific key
  static Future<String?> getString(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final deviceKey = await _getKey(key);
    return prefs.getString(deviceKey);
  }
  
  /// Save bool with device-specific key
  static Future<void> setBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    final deviceKey = await _getKey(key);
    await prefs.setBool(deviceKey, value);
    print('💾 Saved: $deviceKey = $value');
  }
  
  /// Get bool with device-specific key
  static Future<bool> getBool(String key, {bool defaultValue = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final deviceKey = await _getKey(key);
    return prefs.getBool(deviceKey) ?? defaultValue;
  }
  
  /// Remove device-specific key
  static Future<void> remove(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final deviceKey = await _getKey(key);
    await prefs.remove(deviceKey);
    print('🗑️ Removed: $deviceKey');
  }
  
  /// Clear ALL device-specific data (logout)
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final deviceId = await getDeviceId();
    
    final keys = prefs.getKeys().where((key) => key.endsWith('_$deviceId')).toList();
    
    for (final key in keys) {
      await prefs.remove(key);
    }
    
    print('🗑️ Cleared ${keys.length} device-specific keys for device: $deviceId');
  }
}
