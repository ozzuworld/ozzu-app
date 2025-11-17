import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logger/logger.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'keycloak_service.dart';

class JellyfinService {
  static final JellyfinService _instance = JellyfinService._internal();
  factory JellyfinService() => _instance;
  JellyfinService._internal();

  final Logger _logger = Logger();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final AuthService _authService = AuthService();

  final String baseUrl = 'https://tv.ozzu.world';
  String? _accessToken;
  String? _userId;
  String? _serverId;

  // Authentication
  Future<bool> authenticate(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/Users/AuthenticateByName'),
        headers: {
          'Content-Type': 'application/json',
          'X-Emby-Authorization': 'MediaBrowser Client="Ozzu App", Device="Flutter", DeviceId="ozzu-flutter-app", Version="1.0.0"',
        },
        body: json.encode({
          'Username': username,
          'Pw': password,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _accessToken = data['AccessToken'];
        _userId = data['User']['Id'];
        _serverId = data['ServerId'];

        // Store credentials securely
        await _storage.write(key: 'jellyfin_token', value: _accessToken);
        await _storage.write(key: 'jellyfin_user_id', value: _userId);

        _logger.i('✅ Jellyfin authentication successful');
        return true;
      } else {
        _logger.e('❌ Jellyfin auth failed: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      _logger.e('❌ Jellyfin auth error: $e');
      return false;
    }
  }

  // Load saved token
  Future<bool> loadSavedCredentials() async {
    _accessToken = await _storage.read(key: 'jellyfin_token');
    _userId = await _storage.read(key: 'jellyfin_user_id');
    return _accessToken != null && _userId != null;
  }

  // Get authorization headers
  Map<String, String> _getHeaders() {
    return {
      'Content-Type': 'application/json',
      'X-Emby-Authorization': 'MediaBrowser Client="Ozzu App", Device="Flutter", DeviceId="ozzu-flutter-app", Version="1.0.0", Token="$_accessToken"',
    };
  }

  // Get all movies
  Future<List<dynamic>> getMovies() async {
    if (_accessToken == null || _userId == null) {
      await loadSavedCredentials();
    }

    try {
      _logger.i('📽️ Fetching movies from Jellyfin...');
      final response = await http.get(
        Uri.parse('$baseUrl/Users/$_userId/Items?IncludeItemTypes=Movie&Recursive=true&Fields=PrimaryImageAspectRatio,Overview&ImageTypeLimit=1'),
        headers: _getHeaders(),
      );

      _logger.i('📽️ Movies response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final items = data['Items'] ?? [];
        _logger.i('📽️ Found ${items.length} movies');

        // Log first movie details if available
        if (items.isNotEmpty) {
          _logger.d('📽️ First movie: ${items[0]['Name']} (ID: ${items[0]['Id']})');
        } else {
          _logger.w('📽️ Response body: ${response.body}');
        }

        return items;
      }
      _logger.w('📽️ Failed to fetch movies: ${response.statusCode}');
      _logger.w('📽️ Response: ${response.body}');
      return [];
    } catch (e) {
      _logger.e('❌ Error fetching movies: $e');
      return [];
    }
  }

  // Get all TV shows
  Future<List<dynamic>> getTVShows() async {
    if (_accessToken == null || _userId == null) {
      await loadSavedCredentials();
    }

    try {
      _logger.i('📺 Fetching TV shows from Jellyfin...');
      final response = await http.get(
        Uri.parse('$baseUrl/Users/$_userId/Items?IncludeItemTypes=Series&Recursive=true&Fields=PrimaryImageAspectRatio,Overview&ImageTypeLimit=1'),
        headers: _getHeaders(),
      );

      _logger.i('📺 TV shows response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final items = data['Items'] ?? [];
        _logger.i('📺 Found ${items.length} TV shows');

        // Log first show details if available
        if (items.isNotEmpty) {
          _logger.d('📺 First show: ${items[0]['Name']} (ID: ${items[0]['Id']})');
        } else {
          _logger.w('📺 Response body: ${response.body}');
        }

        return items;
      }
      _logger.w('📺 Failed to fetch TV shows: ${response.statusCode}');
      _logger.w('📺 Response: ${response.body}');
      return [];
    } catch (e) {
      _logger.e('❌ Error fetching TV shows: $e');
      return [];
    }
  }

  // Get recently added items
  Future<List<dynamic>> getRecentlyAdded() async {
    if (_accessToken == null || _userId == null) {
      await loadSavedCredentials();
    }

    try {
      _logger.i('🆕 Fetching recently added from Jellyfin...');
      final response = await http.get(
        Uri.parse('$baseUrl/Users/$_userId/Items/Latest?Fields=PrimaryImageAspectRatio,Overview&ImageTypeLimit=1&Limit=20'),
        headers: _getHeaders(),
      );

      _logger.i('🆕 Recently added response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final items = json.decode(response.body) as List;
        _logger.i('🆕 Found ${items.length} recently added items');

        // Log first item details if available
        if (items.isNotEmpty) {
          _logger.d('🆕 First item: ${items[0]['Name']} (Type: ${items[0]['Type']}, ID: ${items[0]['Id']})');
        } else {
          _logger.w('🆕 Response body: ${response.body}');
        }

        return items;
      }
      _logger.w('🆕 Failed to fetch recently added: ${response.statusCode}');
      _logger.w('🆕 Response: ${response.body}');
      return [];
    } catch (e) {
      _logger.e('❌ Error fetching recently added: $e');
      return [];
    }
  }

  // Get item details
  Future<Map<String, dynamic>?> getItemDetails(String itemId) async {
    if (_accessToken == null || _userId == null) {
      await loadSavedCredentials();
    }

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/Users/$_userId/Items/$itemId'),
        headers: _getHeaders(),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      _logger.e('Error fetching item details: $e');
      return null;
    }
  }

  // Get video stream URL
  String getStreamUrl(String itemId) {
    // Direct play - serve the file as-is without transcoding
    // Static=true tells Jellyfin to serve the original file directly
    // This minimizes server processing and works with default Jellyfin config
    return '$baseUrl/Videos/$itemId/stream?'
        'api_key=$_accessToken&'
        'Static=true';
  }

  // Get continue watching items (items with playback progress)
  Future<List<dynamic>> getContinueWatching() async {
    if (_accessToken == null || _userId == null) {
      await loadSavedCredentials();
    }

    try {
      _logger.i('▶️ Fetching continue watching items...');
      final response = await http.get(
        Uri.parse('$baseUrl/Users/$_userId/Items/Resume?'
            'Recursive=true&'
            'Fields=PrimaryImageAspectRatio,Overview&'
            'ImageTypeLimit=1&'
            'EnableImageTypes=Primary,Backdrop,Thumb&'
            'MediaTypes=Video'),
        headers: _getHeaders(),
      );

      _logger.i('▶️ Continue watching response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final items = data['Items'] ?? [];
        _logger.i('▶️ Found ${items.length} continue watching items');
        return items;
      }
      return [];
    } catch (e) {
      _logger.e('❌ Error fetching continue watching: $e');
      return [];
    }
  }

  // Report playback started
  Future<void> reportPlaybackStart(String itemId, {int? positionTicks}) async {
    if (_accessToken == null || _userId == null) {
      await loadSavedCredentials();
    }

    try {
      await http.post(
        Uri.parse('$baseUrl/Sessions/Playing'),
        headers: _getHeaders(),
        body: json.encode({
          'ItemId': itemId,
          'PositionTicks': positionTicks ?? 0,
          'IsPaused': false,
          'IsMuted': false,
          'PlayMethod': 'DirectPlay',
        }),
      );
      _logger.d('▶️ Reported playback start for $itemId');
    } catch (e) {
      _logger.e('❌ Error reporting playback start: $e');
    }
  }

  // Report playback progress
  Future<void> reportPlaybackProgress(String itemId, int positionTicks, bool isPaused) async {
    if (_accessToken == null || _userId == null) {
      await loadSavedCredentials();
    }

    try {
      await http.post(
        Uri.parse('$baseUrl/Sessions/Playing/Progress'),
        headers: _getHeaders(),
        body: json.encode({
          'ItemId': itemId,
          'PositionTicks': positionTicks,
          'IsPaused': isPaused,
          'PlayMethod': 'DirectPlay',
        }),
      );
      _logger.d('▶️ Reported playback progress: ${positionTicks ~/ 10000000}s');
    } catch (e) {
      _logger.e('❌ Error reporting playback progress: $e');
    }
  }

  // Report playback stopped
  Future<void> reportPlaybackStopped(String itemId, int positionTicks) async {
    if (_accessToken == null || _userId == null) {
      await loadSavedCredentials();
    }

    try {
      await http.post(
        Uri.parse('$baseUrl/Sessions/Playing/Stopped'),
        headers: _getHeaders(),
        body: json.encode({
          'ItemId': itemId,
          'PositionTicks': positionTicks,
          'PlayMethod': 'DirectPlay',
        }),
      );
      _logger.i('⏹️ Reported playback stopped at ${positionTicks ~/ 10000000}s');
    } catch (e) {
      _logger.e('❌ Error reporting playback stopped: $e');
    }
  }

  // Get seasons for a TV show
  Future<List<dynamic>> getSeasons(String seriesId) async {
    if (_accessToken == null || _userId == null) {
      await loadSavedCredentials();
    }

    try {
      _logger.i('📺 Fetching seasons for series: $seriesId');
      final response = await http.get(
        Uri.parse('$baseUrl/Shows/$seriesId/Seasons?userId=$_userId&Fields=Overview'),
        headers: _getHeaders(),
      );

      _logger.i('📺 Seasons response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final items = data['Items'] ?? [];
        _logger.i('📺 Found ${items.length} seasons');
        return items;
      }
      return [];
    } catch (e) {
      _logger.e('❌ Error fetching seasons: $e');
      return [];
    }
  }

  // Get episodes for a season
  Future<List<dynamic>> getEpisodes(String seriesId, String seasonId) async {
    if (_accessToken == null || _userId == null) {
      await loadSavedCredentials();
    }

    try {
      _logger.i('📺 Fetching episodes for season: $seasonId');
      final response = await http.get(
        Uri.parse('$baseUrl/Shows/$seriesId/Episodes?seasonId=$seasonId&userId=$_userId&Fields=Overview'),
        headers: _getHeaders(),
      );

      _logger.i('📺 Episodes response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final items = data['Items'] ?? [];
        _logger.i('📺 Found ${items.length} episodes');
        return items;
      }
      return [];
    } catch (e) {
      _logger.e('❌ Error fetching episodes: $e');
      return [];
    }
  }

  // Get image URL (poster/backdrop)
  String getImageUrl(String itemId, {String type = 'Primary'}) {
    return '$baseUrl/Items/$itemId/Images/$type?api_key=$_accessToken';
  }

  // Logout
  Future<void> logout() async {
    await _storage.delete(key: 'jellyfin_token');
    await _storage.delete(key: 'jellyfin_user_id');
    _accessToken = null;
    _userId = null;
  }
}
