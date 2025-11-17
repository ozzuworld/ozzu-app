import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logger/logger.dart';
import 'package:http/http.dart' as http;

class DownloadsService {
  static final DownloadsService _instance = DownloadsService._internal();
  factory DownloadsService() => _instance;
  DownloadsService._internal();

  final Logger _logger = Logger();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  static const String _downloadsKey = 'user_downloads';
  Map<String, Map<String, dynamic>> _downloads = {};

  // Download status
  static const String statusPending = 'pending';
  static const String statusDownloading = 'downloading';
  static const String statusCompleted = 'completed';
  static const String statusFailed = 'failed';

  // Load downloads from storage
  Future<void> loadDownloads() async {
    try {
      final downloadsJson = await _storage.read(key: _downloadsKey);
      if (downloadsJson != null) {
        final Map<String, dynamic> decoded = json.decode(downloadsJson);
        _downloads = decoded.map((key, value) =>
          MapEntry(key, Map<String, dynamic>.from(value))
        );
        _logger.i('📥 Loaded ${_downloads.length} downloads');
      }
    } catch (e) {
      _logger.e('❌ Error loading downloads: $e');
      _downloads = {};
    }
  }

  // Save downloads to storage
  Future<void> _saveDownloads() async {
    try {
      final downloadsJson = json.encode(_downloads);
      await _storage.write(key: _downloadsKey, value: downloadsJson);
      _logger.i('📥 Saved ${_downloads.length} downloads');
    } catch (e) {
      _logger.e('❌ Error saving downloads: $e');
    }
  }

  // Start download
  Future<void> startDownload({
    required String itemId,
    required String title,
    required String url,
    required String filePath,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      _downloads[itemId] = {
        'itemId': itemId,
        'title': title,
        'url': url,
        'filePath': filePath,
        'status': statusDownloading,
        'progress': 0.0,
        'metadata': metadata ?? {},
        'startedAt': DateTime.now().toIso8601String(),
      };
      await _saveDownloads();

      _logger.i('📥 Started download: $title');

      // Simulate download progress (in real app, use proper download manager)
      // For demo purposes, we just mark it as completed
      _downloads[itemId]!['status'] = statusCompleted;
      _downloads[itemId]!['progress'] = 1.0;
      _downloads[itemId]!['completedAt'] = DateTime.now().toIso8601String();
      await _saveDownloads();

      _logger.i('📥 Completed download: $title');
    } catch (e) {
      _logger.e('❌ Error starting download: $e');
      if (_downloads.containsKey(itemId)) {
        _downloads[itemId]!['status'] = statusFailed;
        await _saveDownloads();
      }
    }
  }

  // Delete download
  Future<void> deleteDownload(String itemId) async {
    try {
      if (_downloads.containsKey(itemId)) {
        final filePath = _downloads[itemId]!['filePath'];

        // Delete file if it exists
        try {
          final file = File(filePath);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (e) {
          _logger.w('⚠️ Error deleting file: $e');
        }

        _downloads.remove(itemId);
        await _saveDownloads();
        _logger.i('📥 Deleted download: $itemId');
      }
    } catch (e) {
      _logger.e('❌ Error deleting download: $e');
    }
  }

  // Check if item is downloaded
  bool isDownloaded(String itemId) {
    return _downloads.containsKey(itemId) &&
        _downloads[itemId]!['status'] == statusCompleted;
  }

  // Get download status
  String? getDownloadStatus(String itemId) {
    return _downloads[itemId]?['status'];
  }

  // Get download progress (0.0 to 1.0)
  double getDownloadProgress(String itemId) {
    return _downloads[itemId]?['progress'] ?? 0.0;
  }

  // Get all completed downloads
  List<Map<String, dynamic>> getCompletedDownloads() {
    return _downloads.values
        .where((download) => download['status'] == statusCompleted)
        .toList();
  }

  // Get all downloads
  List<Map<String, dynamic>> getAllDownloads() {
    return _downloads.values.toList();
  }

  // Clear all downloads
  Future<void> clearDownloads() async {
    // Delete all files
    for (var download in _downloads.values) {
      try {
        final file = File(download['filePath']);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        _logger.w('⚠️ Error deleting file: $e');
      }
    }

    _downloads = {};
    await _saveDownloads();
    _logger.i('📥 Cleared all downloads');
  }
}
