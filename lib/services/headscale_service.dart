import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:logger/logger.dart';
import 'package:url_launcher/url_launcher.dart';

/// Service for managing Headscale VPN connections
/// Handles OIDC authentication and API communication with the headscale control server
class HeadscaleService {
  static final HeadscaleService _instance = HeadscaleService._internal();
  factory HeadscaleService() => _instance;
  HeadscaleService._internal();

  final _storage = const FlutterSecureStorage();
  final _logger = Logger();

  // Headscale server URL (configured by backend)
  static const String defaultServerUrl = 'https://headscale.ozzu.world';

  // Storage keys
  static const _keyServerUrl = 'headscale_server_url';
  static const _keyApiKey = 'headscale_api_key';
  static const _keyUsername = 'headscale_username';
  static const _keyNodeRegistered = 'headscale_node_registered';

  String? _serverUrl;
  String? _apiKey;
  String? _username;
  bool _nodeRegistered = false;

  // Connection status stream
  final _connectionStatusController = StreamController<ConnectionStatus>.broadcast();
  Stream<ConnectionStatus> get connectionStatusStream => _connectionStatusController.stream;
  ConnectionStatus _currentStatus = ConnectionStatus.disconnected;
  ConnectionStatus get currentStatus => _currentStatus;

  /// Initialize the service and load saved credentials
  Future<void> initialize() async {
    _logger.d('Initializing HeadscaleService');

    _serverUrl = await _storage.read(key: _keyServerUrl) ?? defaultServerUrl;
    _apiKey = await _storage.read(key: _keyApiKey);
    _username = await _storage.read(key: _keyUsername);
    final registeredStr = await _storage.read(key: _keyNodeRegistered);
    _nodeRegistered = registeredStr == 'true';

    _logger.d('Loaded config - Server: $_serverUrl, Username: $_username, Registered: $_nodeRegistered');
  }

  /// Save server configuration (optional - only needed for API access to view nodes)
  Future<void> saveConfiguration({
    required String serverUrl,
    required String apiKey,
    required String username,
  }) async {
    _logger.d('Saving headscale configuration');

    await _storage.write(key: _keyServerUrl, value: serverUrl);
    await _storage.write(key: _keyApiKey, value: apiKey);
    await _storage.write(key: _keyUsername, value: username);

    _serverUrl = serverUrl;
    _apiKey = apiKey;
    _username = username;

    _logger.d('Configuration saved successfully');
  }

  /// Test connection to headscale server (requires API key)
  Future<bool> testConnection() async {
    if (_apiKey == null || _apiKey!.isEmpty) {
      _logger.w('Cannot test connection - API key not configured');
      return false;
    }

    try {
      _logger.d('Testing connection to $_serverUrl');

      final response = await http.get(
        Uri.parse('${_serverUrl ?? defaultServerUrl}/api/v1/user'),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      _logger.d('Connection test response: ${response.statusCode}');
      return response.statusCode == 200 || response.statusCode == 401; // 401 means server is reachable
    } catch (e) {
      _logger.e('Connection test failed: $e');
      return false;
    }
  }

  /// Get list of nodes (devices) from headscale (requires API key)
  Future<List<HeadscaleNode>> getNodes() async {
    if (_apiKey == null || _apiKey!.isEmpty) {
      throw Exception('API key not configured. This is optional - VPN works without it.');
    }

    try {
      _logger.d('Fetching nodes from headscale');

      final response = await http.get(
        Uri.parse('${_serverUrl ?? defaultServerUrl}/api/v1/node'),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final nodes = (data['nodes'] as List?)?.map((node) => HeadscaleNode.fromJson(node)).toList() ?? [];
        _logger.d('Retrieved ${nodes.length} nodes');
        return nodes;
      } else {
        _logger.e('Failed to fetch nodes: ${response.statusCode} - ${response.body}');
        throw Exception('Failed to fetch nodes: ${response.statusCode}');
      }
    } catch (e) {
      _logger.e('Error fetching nodes: $e');
      rethrow;
    }
  }

  /// Get current user information (requires API key)
  Future<Map<String, dynamic>?> getUserInfo() async {
    if (_apiKey == null || _apiKey!.isEmpty || _username == null) {
      throw Exception('API key and username not configured');
    }

    try {
      _logger.d('Fetching user info for $_username');

      final response = await http.get(
        Uri.parse('${_serverUrl ?? defaultServerUrl}/api/v1/user/$_username'),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        _logger.w('Failed to fetch user info: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      _logger.e('Error fetching user info: $e');
      return null;
    }
  }

  /// Create a pre-authentication key for registering new devices (requires API key)
  Future<String?> createPreAuthKey({
    bool reusable = false,
    bool ephemeral = false,
    Duration? expiration,
  }) async {
    if (_apiKey == null || _apiKey!.isEmpty || _username == null) {
      throw Exception('API key and username not configured');
    }

    try {
      _logger.d('Creating pre-auth key');

      final response = await http.post(
        Uri.parse('${_serverUrl ?? defaultServerUrl}/api/v1/preauthkey'),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'user': _username,
          'reusable': reusable,
          'ephemeral': ephemeral,
          if (expiration != null) 'expiration': DateTime.now().add(expiration).toIso8601String(),
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        final key = data['preAuthKey']?['key'] ?? data['key'];
        _logger.d('Pre-auth key created successfully');
        return key;
      } else {
        _logger.e('Failed to create pre-auth key: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      _logger.e('Error creating pre-auth key: $e');
      return null;
    }
  }

  /// Update connection status
  void updateConnectionStatus(ConnectionStatus status) {
    if (_currentStatus != status) {
      _currentStatus = status;
      _connectionStatusController.add(status);
      _logger.d('Connection status updated: $status');
    }
  }

  /// Register device using OIDC (seamless SSO with Keycloak)
  /// This opens a browser window that uses the existing Keycloak session
  /// Returns the auth URL that was used for registration
  Future<OIDCRegistrationResult> registerWithOIDC() async {
    try {
      _logger.d('Starting OIDC registration with Headscale');

      // Use configured server URL or default
      final serverUrl = _serverUrl ?? defaultServerUrl;

      // Headscale OIDC registration endpoint
      final oidcUrl = Uri.parse('$serverUrl/oidc/register');

      _logger.d('Opening OIDC URL: $oidcUrl');

      // Launch browser for OIDC authentication
      // This will use the existing Keycloak session if user is already logged in
      final launched = await launchUrl(
        oidcUrl,
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        _logger.e('Failed to launch OIDC URL');
        return OIDCRegistrationResult(
          success: false,
          error: 'Failed to open authentication page',
        );
      }

      // Mark as registered (in real implementation, you'd verify this)
      await _storage.write(key: _keyNodeRegistered, value: 'true');
      _nodeRegistered = true;

      _logger.d('OIDC registration initiated successfully');

      return OIDCRegistrationResult(
        success: true,
        authUrl: oidcUrl.toString(),
      );
    } catch (e) {
      _logger.e('OIDC registration error: $e');
      return OIDCRegistrationResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  /// Check if node is already registered
  bool get isNodeRegistered => _nodeRegistered;

  /// Clear all saved configuration
  Future<void> clearConfiguration() async {
    _logger.d('Clearing headscale configuration');

    await _storage.delete(key: _keyServerUrl);
    await _storage.delete(key: _keyApiKey);
    await _storage.delete(key: _keyUsername);
    await _storage.delete(key: _keyNodeRegistered);

    _serverUrl = null;
    _apiKey = null;
    _username = null;
    _nodeRegistered = false;

    updateConnectionStatus(ConnectionStatus.disconnected);
  }

  /// Dispose resources
  void dispose() {
    _connectionStatusController.close();
  }
}

/// Connection status enum
enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
}

/// Headscale node model
class HeadscaleNode {
  final String id;
  final String name;
  final String user;
  final List<String> ipAddresses;
  final DateTime? lastSeen;
  final bool online;
  final String? hostname;

  HeadscaleNode({
    required this.id,
    required this.name,
    required this.user,
    required this.ipAddresses,
    this.lastSeen,
    this.online = false,
    this.hostname,
  });

  factory HeadscaleNode.fromJson(Map<String, dynamic> json) {
    return HeadscaleNode(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? json['givenName'] ?? 'Unknown',
      user: json['user']?['name'] ?? json['user'] ?? 'Unknown',
      ipAddresses: (json['ipAddresses'] as List?)?.map((ip) => ip.toString()).toList() ?? [],
      lastSeen: json['lastSeen'] != null ? DateTime.tryParse(json['lastSeen']) : null,
      online: json['online'] ?? false,
      hostname: json['hostname'],
    );
  }

  String get primaryIp => ipAddresses.isNotEmpty ? ipAddresses.first : 'N/A';

  String get deviceIcon {
    final lowerName = name.toLowerCase();
    if (lowerName.contains('iphone') || lowerName.contains('ios')) return '📱';
    if (lowerName.contains('ipad')) return '📱';
    if (lowerName.contains('mac')) return '💻';
    if (lowerName.contains('windows') || lowerName.contains('pc')) return '🖥️';
    if (lowerName.contains('linux')) return '🐧';
    if (lowerName.contains('android')) return '📱';
    return '💻';
  }
}

/// Result of OIDC registration
class OIDCRegistrationResult {
  final bool success;
  final String? authUrl;
  final String? error;

  OIDCRegistrationResult({
    required this.success,
    this.authUrl,
    this.error,
  });
}
