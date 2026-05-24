import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path/path.dart' as path;

class StorageService {
  /// Uses the bucket from [Firebase.initializeApp] so uploads and URLs stay consistent.
  static FirebaseStorage get _resolvedStorage {
    final FirebaseApp app = Firebase.app();
    final String? bucket = app.options.storageBucket;
    if (bucket == null || bucket.isEmpty) {
      return FirebaseStorage.instance;
    }
    final String gs = bucket.startsWith('gs://') ? bucket : 'gs://$bucket';
    return FirebaseStorage.instanceFor(app: app, bucket: gs);
  }

  /// Storage rules often require [request.auth]. The app logs in via your API, not Firebase Auth,
  /// so we sign in anonymously when needed. Enable "Anonymous" in Firebase Console → Authentication.
  static Future<void> _ensureStorageAuth() async {
    if (FirebaseAuth.instance.currentUser != null) return;
    try {
      await FirebaseAuth.instance.signInAnonymously();
    } catch (e) {
      print(
        '⚠️ Anonymous sign-in for Storage failed (enable Anonymous auth in Firebase if uploads fail): $e',
      );
    }
  }

  /// Avoids invalid GCS object name segments (e.g. `[`, `*`, `\`).
  static String _sanitizeStoragePath(String folder) {
    return folder
        .split('/')
        .map(
          (String segment) =>
              segment.replaceAll(RegExp(r'[#\[\]?*\\]'), '_').trim(),
        )
        .where((String s) => s.isNotEmpty)
        .join('/');
  }

  static Future<String> _getDownloadUrlWithRetry(Reference ref) async {
    Object? lastError;
    for (int attempt = 0; attempt < 5; attempt++) {
      try {
        return await ref.getDownloadURL();
      } catch (e) {
        lastError = e;
        if (attempt < 4) {
          await Future<void>.delayed(
            Duration(milliseconds: 200 * (attempt + 1)),
          );
        }
      }
    }
    throw lastError ?? StateError('getDownloadURL failed');
  }

  static void _assertUploadSucceeded(TaskSnapshot snapshot, int byteLength) {
    if (snapshot.state != TaskState.success) {
      throw FirebaseException(
        plugin: 'firebase_storage',
        message: 'Upload ended in state ${snapshot.state}',
      );
    }
    if (byteLength > 0 && snapshot.bytesTransferred == 0) {
      throw FirebaseException(
        plugin: 'firebase_storage',
        message: 'Upload reported 0 bytes transferred',
      );
    }
  }

  /// Uploads a file to Firebase Storage and returns the download URL.
  /// Uses [putData] after reading bytes so macOS/desktop sandboxes and temp paths work reliably
  /// (avoids [firebase_storage/object-not-found] after [putFile] when the native layer never stored the object).
  static Future<String?> uploadImage({
    required File file,
    required String folder,
    String? customFileName,
  }) async {
    try {
      await _ensureStorageAuth();

      if (!await file.exists()) {
        print('❌ Upload file does not exist: ${file.path}');
        return null;
      }

      final String extension = path.extension(file.path);
      final String fileName =
          customFileName ??
          '${DateTime.now().millisecondsSinceEpoch}$extension';
      final String safeFolder = _sanitizeStoragePath(folder);
      final FirebaseStorage storage = _resolvedStorage;
      final Reference ref = storage.ref().child('$safeFolder/$fileName');

      final Uint8List bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        print('❌ Upload file is empty: ${file.path}');
        return null;
      }

      final SettableMetadata metadata = SettableMetadata(
        contentType: _getContentType(extension),
        cacheControl: 'public, max-age=31536000',
      );

      final TaskSnapshot snapshot = await ref.putData(bytes, metadata);
      _assertUploadSucceeded(snapshot, bytes.length);

      final String downloadUrl = await _getDownloadUrlWithRetry(ref);
      print('✅ Image uploaded successfully: $downloadUrl');
      return downloadUrl;
    } catch (e) {
      print('❌ Error uploading image: $e');
      return null;
    }
  }

  /// Uploads image data (bytes) to Firebase Storage.
  static Future<String?> uploadImageData({
    required Uint8List data,
    required String folder,
    required String fileName,
  }) async {
    try {
      await _ensureStorageAuth();

      final String extension = path.extension(fileName);
      final String uniqueFileName =
          '${DateTime.now().millisecondsSinceEpoch}_$fileName';
      final String safeFolder = _sanitizeStoragePath(folder);
      final FirebaseStorage storage = _resolvedStorage;
      final Reference ref = storage.ref().child('$safeFolder/$uniqueFileName');

      final SettableMetadata metadata = SettableMetadata(
        contentType: _getContentType(extension),
        cacheControl: 'public, max-age=31536000',
      );

      final TaskSnapshot snapshot = await ref.putData(data, metadata);
      _assertUploadSucceeded(snapshot, data.length);

      final String downloadUrl = await _getDownloadUrlWithRetry(ref);
      print('✅ Image data uploaded successfully: $downloadUrl');
      return downloadUrl;
    } catch (e) {
      print('❌ Error uploading image data: $e');
      return null;
    }
  }

  /// Deletes a file from Firebase Storage using its URL or path
  static Future<bool> deleteFile(String urlOrPath) async {
    try {
      await _ensureStorageAuth();
      final FirebaseStorage storage = _resolvedStorage;
      late final Reference ref;

      if (urlOrPath.startsWith('https://') || urlOrPath.startsWith('gs://')) {
        ref = storage.refFromURL(urlOrPath);
      } else {
        ref = storage.ref().child(_sanitizeStoragePath(urlOrPath));
      }

      await ref.delete();
      print('✅ File deleted successfully: $urlOrPath');
      return true;
    } catch (e) {
      print('❌ Error deleting file: $e');
      return false;
    }
  }

  /// Gets the download URL for an existing file
  static Future<String?> getDownloadUrl(String storagePath) async {
    try {
      await _ensureStorageAuth();
      final Reference ref = _resolvedStorage
          .ref()
          .child(_sanitizeStoragePath(storagePath));
      return await ref.getDownloadURL();
    } catch (e) {
      print('❌ Error getting download URL: $e');
      return null;
    }
  }

  /// Lists all files in a folder
  static Future<List<String>> listFiles(String folder) async {
    try {
      await _ensureStorageAuth();
      final Reference ref =
          _resolvedStorage.ref().child(_sanitizeStoragePath(folder));
      final ListResult result = await ref.listAll();

      final List<String> urls = <String>[];
      for (final Reference item in result.items) {
        final String url = await item.getDownloadURL();
        urls.add(url);
      }

      return urls;
    } catch (e) {
      print('❌ Error listing files: $e');
      return <String>[];
    }
  }

  /// Upload progress stream for showing progress indicator
  static Stream<TaskSnapshot> uploadImageWithProgress({
    required File file,
    required String folder,
    String? customFileName,
  }) {
    final String extension = path.extension(file.path);
    final String fileName =
        customFileName ?? '${DateTime.now().millisecondsSinceEpoch}$extension';
    final String safeFolder = _sanitizeStoragePath(folder);
    final Reference ref =
        _resolvedStorage.ref().child('$safeFolder/$fileName');

    return ref
        .putFile(
          file,
          SettableMetadata(
            contentType: _getContentType(extension),
            cacheControl: 'public, max-age=31536000',
          ),
        )
        .snapshotEvents;
  }

  /// Helper to determine content type from file extension
  static String _getContentType(String extension) {
    switch (extension.toLowerCase()) {
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.gif':
        return 'image/gif';
      case '.webp':
        return 'image/webp';
      case '.heic':
        return 'image/heic';
      case '.heif':
        return 'image/heif';
      case '.pdf':
        return 'application/pdf';
      case '.mp4':
        return 'video/mp4';
      case '.mov':
        return 'video/quicktime';
      default:
        return 'application/octet-stream';
    }
  }
}
