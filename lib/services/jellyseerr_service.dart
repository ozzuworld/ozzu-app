import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logger/logger.dart';

class JellyseerrService {
  static final JellyseerrService _instance = JellyseerrService._internal();
  factory JellyseerrService() => _instance;
  JellyseerrService._internal();

  final Logger _logger = Logger();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  final String baseUrl = 'https://requests.ozzu.world';
  String? _apiKey;

  // Login to get API key
  Future<bool> login(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/v1/auth/local'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': email,
          'password': password,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _apiKey = data['token'] ?? data['apiKey'];

        if (_apiKey != null) {
          await _storage.write(key: 'jellyseerr_api_key', value: _apiKey);
          _logger.i('✅ Jellyseerr authentication successful');
          return true;
        }
      }
      _logger.e('❌ Jellyseerr auth failed: ${response.statusCode}');
      return false;
    } catch (e) {
      _logger.e('❌ Jellyseerr auth error: $e');
      return false;
    }
  }

  // Load saved API key
  Future<bool> loadSavedApiKey() async {
    _apiKey = await _storage.read(key: 'jellyseerr_api_key');
    return _apiKey != null;
  }

  // Get headers with API key
  Map<String, String> _getHeaders() {
    return {
      'Content-Type': 'application/json',
      if (_apiKey != null) 'X-Api-Key': _apiKey!,
    };
  }

  // Get trending movies
  Future<List<dynamic>> getTrendingMovies() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/v1/discover/movies/trending'),
        headers: _getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['results'] ?? [];
      }
      return [];
    } catch (e) {
      _logger.e('Error fetching trending movies: $e');
      return [];
    }
  }

  // Get trending TV shows
  Future<List<dynamic>> getTrendingTV() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/v1/discover/tv/trending'),
        headers: _getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['results'] ?? [];
      }
      return [];
    } catch (e) {
      _logger.e('Error fetching trending TV: $e');
      return [];
    }
  }

  // Get popular movies
  Future<List<dynamic>> getPopularMovies() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/v1/discover/movies/popular'),
        headers: _getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['results'] ?? [];
      }
      return [];
    } catch (e) {
      _logger.e('Error fetching popular movies: $e');
      return [];
    }
  }

  // Get popular TV shows
  Future<List<dynamic>> getPopularTV() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/v1/discover/tv/popular'),
        headers: _getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['results'] ?? [];
      }
      return [];
    } catch (e) {
      _logger.e('Error fetching popular TV: $e');
      return [];
    }
  }

  // Get upcoming movies
  Future<List<dynamic>> getUpcomingMovies() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/v1/discover/movies/upcoming'),
        headers: _getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['results'] ?? [];
      }
      return [];
    } catch (e) {
      _logger.e('Error fetching upcoming movies: $e');
      return [];
    }
  }

  // Get movie details
  Future<Map<String, dynamic>?> getMovieDetails(int movieId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/v1/movie/$movieId'),
        headers: _getHeaders(),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      _logger.e('Error fetching movie details: $e');
      return null;
    }
  }

  // Get TV show details
  Future<Map<String, dynamic>?> getTVDetails(int tvId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/v1/tv/$tvId'),
        headers: _getHeaders(),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      _logger.e('Error fetching TV details: $e');
      return null;
    }
  }

  // Get TMDb image URL (Jellyseerr uses TMDb images)
  String getImageUrl(String? path, {String size = 'w500'}) {
    if (path == null) return '';
    return 'https://image.tmdb.org/t/p/$size$path';
  }

  // Logout
  Future<void> logout() async {
    await _storage.delete(key: 'jellyseerr_api_key');
    _apiKey = null;
  }
}
