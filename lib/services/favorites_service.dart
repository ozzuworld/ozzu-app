import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logger/logger.dart';

class FavoritesService {
  static final FavoritesService _instance = FavoritesService._internal();
  factory FavoritesService() => _instance;
  FavoritesService._internal();

  final Logger _logger = Logger();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  static const String _favoritesKey = 'user_favorites';
  List<Map<String, dynamic>> _favorites = [];

  // Load favorites from storage
  Future<void> loadFavorites() async {
    try {
      final favoritesJson = await _storage.read(key: _favoritesKey);
      if (favoritesJson != null) {
        final List<dynamic> decoded = json.decode(favoritesJson);
        _favorites = decoded.map((item) => Map<String, dynamic>.from(item)).toList();
        _logger.i('⭐ Loaded ${_favorites.length} favorites');
      }
    } catch (e) {
      _logger.e('❌ Error loading favorites: $e');
      _favorites = [];
    }
  }

  // Save favorites to storage
  Future<void> _saveFavorites() async {
    try {
      final favoritesJson = json.encode(_favorites);
      await _storage.write(key: _favoritesKey, value: favoritesJson);
      _logger.i('⭐ Saved ${_favorites.length} favorites');
    } catch (e) {
      _logger.e('❌ Error saving favorites: $e');
    }
  }

  // Add item to favorites
  Future<void> addFavorite(Map<String, dynamic> item) async {
    try {
      // Check if already favorited
      final exists = _favorites.any((fav) =>
        fav['id'] == item['id'] || fav['Id'] == item['Id']
      );

      if (!exists) {
        _favorites.add(item);
        await _saveFavorites();
        _logger.i('⭐ Added to favorites: ${item['title'] ?? item['name'] ?? item['Name']}');
      }
    } catch (e) {
      _logger.e('❌ Error adding favorite: $e');
    }
  }

  // Remove item from favorites
  Future<void> removeFavorite(String itemId) async {
    try {
      _favorites.removeWhere((fav) =>
        fav['id'] == itemId || fav['Id'] == itemId
      );
      await _saveFavorites();
      _logger.i('⭐ Removed from favorites: $itemId');
    } catch (e) {
      _logger.e('❌ Error removing favorite: $e');
    }
  }

  // Check if item is favorited
  bool isFavorite(String itemId) {
    return _favorites.any((fav) =>
      fav['id'] == itemId || fav['Id'] == itemId
    );
  }

  // Toggle favorite status
  Future<bool> toggleFavorite(Map<String, dynamic> item) async {
    final itemId = item['id']?.toString() ?? item['Id']?.toString() ?? '';
    if (isFavorite(itemId)) {
      await removeFavorite(itemId);
      return false;
    } else {
      await addFavorite(item);
      return true;
    }
  }

  // Get all favorites
  List<Map<String, dynamic>> getFavorites() {
    return List.from(_favorites);
  }

  // Clear all favorites
  Future<void> clearFavorites() async {
    _favorites = [];
    await _saveFavorites();
    _logger.i('⭐ Cleared all favorites');
  }
}
