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

  // Login to get session cookie using Jellyfin authentication
  Future<bool> login(String username, String password) async {
    try {
      _logger.i('🔑 Attempting Jellyseerr login via Jellyfin auth...');
      final response = await http.post(
        Uri.parse('$baseUrl/api/v1/auth/jellyfin'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': username,
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

  // Get all trending content (movies and TV)
  Future<List<dynamic>> getTrending() async {
    try {
      _logger.i('🔥 Fetching trending content from Jellyseerr...');
      final response = await http.get(
        Uri.parse('$baseUrl/api/v1/discover/trending'),
        headers: _getHeaders(),
      );

      _logger.i('🔥 Trending response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final results = data['results'] ?? [];
        _logger.i('🔥 Found ${results.length} trending items');
        if (results.isNotEmpty) {
          _logger.d('🔥 First item: ${results[0]['title'] ?? results[0]['name']} (Type: ${results[0]['mediaType']})');
        }
        return results;
      }
      _logger.w('🔥 Failed to fetch trending: ${response.statusCode}');
      _logger.w('Response: ${response.body}');
      return [];
    } catch (e) {
      _logger.e('❌ Error fetching trending: $e');
      return [];
    }
  }

  // Get trending movies (filter from trending)
  Future<List<dynamic>> getTrendingMovies() async {
    final trending = await getTrending();
    return trending.where((item) => item['mediaType'] == 'movie').toList();
  }

  // Get trending TV shows (filter from trending)
  Future<List<dynamic>> getTrendingTV() async {
    final trending = await getTrending();
    return trending.where((item) => item['mediaType'] == 'tv').toList();
  }

  // Get popular movies
  Future<List<dynamic>> getPopularMovies() async {
    try {
      _logger.i('⭐ Fetching popular movies from Jellyseerr...');
      final response = await http.get(
        Uri.parse('$baseUrl/api/v1/discover/movies'),
        headers: _getHeaders(),
      );

      _logger.i('⭐ Popular movies response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final results = data['results'] ?? [];
        _logger.i('⭐ Found ${results.length} popular movies');
        return results;
      }
      _logger.w('⭐ Failed to fetch popular movies: ${response.statusCode}');
      _logger.w('Response: ${response.body}');
      return [];
    } catch (e) {
      _logger.e('❌ Error fetching popular movies: $e');
      return [];
    }
  }

  // Get popular TV shows
  Future<List<dynamic>> getPopularTV() async {
    try {
      _logger.i('📺 Fetching popular TV from Jellyseerr...');
      final response = await http.get(
        Uri.parse('$baseUrl/api/v1/discover/tv'),
        headers: _getHeaders(),
      );

      _logger.i('📺 Popular TV response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final results = data['results'] ?? [];
        _logger.i('📺 Found ${results.length} popular TV shows');
        return results;
      }
      _logger.w('📺 Failed to fetch popular TV: ${response.statusCode}');
      _logger.w('Response: ${response.body}');
      return [];
    } catch (e) {
      _logger.e('❌ Error fetching popular TV: $e');
      return [];
    }
  }

  // Get upcoming movies
  Future<List<dynamic>> getUpcomingMovies() async {
    try {
      _logger.i('🎬 Fetching upcoming movies from Jellyseerr...');
      final response = await http.get(
        Uri.parse('$baseUrl/api/v1/discover/movies/upcoming'),
        headers: _getHeaders(),
      );

      _logger.i('🎬 Upcoming movies response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final results = data['results'] ?? [];
        _logger.i('🎬 Found ${results.length} upcoming movies');
        return results;
      }
      _logger.w('🎬 Failed to fetch upcoming movies: ${response.statusCode}');
      _logger.w('Response: ${response.body}');
      return [];
    } catch (e) {
      _logger.e('❌ Error fetching upcoming movies: $e');
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

  // Search for content
  Future<List<dynamic>> search(String query) async {
    if (query.trim().isEmpty) {
      return [];
    }

    try {
      _logger.i('🔍 Searching Jellyseerr for: $query');
      final response = await http.get(
        Uri.parse('$baseUrl/api/v1/search?query=${Uri.encodeComponent(query)}'),
        headers: _getHeaders(),
      );

      _logger.i('🔍 Search response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final results = data['results'] ?? [];
        _logger.i('🔍 Found ${results.length} results in Jellyseerr');
        return results;
      }
      return [];
    } catch (e) {
      _logger.e('❌ Error searching Jellyseerr: $e');
      return [];
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
