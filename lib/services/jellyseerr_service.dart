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
  String? _sessionCookie;

  // Login to get session cookie
  Future<bool> login(String email, String password) async {
    try {
      _logger.i('🔑 Attempting Jellyseerr login...');
      final response = await http.post(
        Uri.parse('$baseUrl/auth/local'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': email,
          'password': password,
        }),
      );

      _logger.i('📡 Jellyseerr response: ${response.statusCode}');

      if (response.statusCode == 200) {
        // Extract session cookie from response headers
        final setCookie = response.headers['set-cookie'];
        if (setCookie != null) {
          // Parse the cookie - typically in format: "connect.sid=xxx; Path=/; HttpOnly"
          _sessionCookie = setCookie.split(';')[0];
          await _storage.write(key: 'jellyseerr_session', value: _sessionCookie);
          _logger.i('✅ Jellyseerr authentication successful');
          _logger.i('🍪 Session cookie: ${_sessionCookie?.substring(0, 20)}...');
          return true;
        } else {
          _logger.w('⚠️ No session cookie found in response headers');
          _logger.w('Headers: ${response.headers}');
        }
      } else {
        _logger.e('❌ Jellyseerr auth failed: ${response.statusCode}');
        _logger.e('Response body: ${response.body}');
      }
      return false;
    } catch (e) {
      _logger.e('❌ Jellyseerr auth error: $e');
      return false;
    }
  }

  // Load saved session cookie
  Future<bool> loadSavedSession() async {
    _sessionCookie = await _storage.read(key: 'jellyseerr_session');
    return _sessionCookie != null;
  }

  // Get headers with session cookie
  Map<String, String> _getHeaders() {
    return {
      'Content-Type': 'application/json',
      if (_sessionCookie != null) 'Cookie': _sessionCookie!,
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
    await _storage.delete(key: 'jellyseerr_session');
    _sessionCookie = null;
  }
}
