import 'dart:async';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:logger/logger.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:android_intent_plus/android_intent.dart';

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

  /// Check if Tailscale app can be launched
  /// We try to check if the URL scheme is available
  Future<bool> isTailscaleInstalled() async {
    try {
      if (Platform.isAndroid) {
        // On Android, we'll just try to launch and handle the error
        // This is simpler than checking if the package is installed
        return true; // We'll handle the error when launching
      } else if (Platform.isIOS) {
        // Check if Tailscale URL scheme can be opened
        final url = Uri.parse('tailscale://');
        return await canLaunchUrl(url);
      }
      return true; // Default to true, handle errors on launch
    } catch (e) {
      _logger.e('Error checking Tailscale installation: $e');
      return true; // Return true and let the launch attempt fail gracefully
    }
  }

  /// Open Tailscale app store page for installation
  Future<void> openTailscaleInstallPage() async {
    try {
      if (Platform.isAndroid) {
        final playStoreUrl = Uri.parse('https://play.google.com/store/apps/details?id=com.tailscale.ipn');
        await launchUrl(playStoreUrl, mode: LaunchMode.externalApplication);
      } else if (Platform.isIOS) {
        final appStoreUrl = Uri.parse('https://apps.apple.com/app/tailscale/id1470499037');
        await launchUrl(appStoreUrl, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      _logger.e('Error opening Tailscale install page: $e');
    }
  }

  /// Get pre-authentication key from Headscale for Tailscale connection
  /// Uses Keycloak access token for authentication
  Future<Map<String, dynamic>?> getPreAuthKey(String accessToken) async {
    try {
      _logger.d('Getting pre-auth key from Headscale using Keycloak token');

      // Get device name
      final deviceName = Platform.isAndroid
          ? 'android-${DateTime.now().millisecondsSinceEpoch}'
          : 'ios-${DateTime.now().millisecondsSinceEpoch}';

      final response = await http.post(
        Uri.parse('${_serverUrl ?? defaultServerUrl}/api/v1/device/register'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'device_name': deviceName,
          'platform': Platform.isAndroid ? 'android' : 'ios',
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200 || response.statusCode == 201) {
        _logger.d('Pre-auth key obtained successfully');
        _logger.d('Response body: ${response.body}');

        final data = json.decode(response.body);
        _logger.d('Parsed JSON data: $data');

        // Mark as registered
        await _storage.write(key: _keyNodeRegistered, value: 'true');
        _nodeRegistered = true;

        return data;
      } else {
        _logger.e('Failed to get pre-auth key: ${response.statusCode} - ${response.body}');
        throw Exception('Failed to get pre-auth key: ${response.statusCode}');
      }
    } catch (e) {
      _logger.e('Error getting pre-auth key: $e');
      rethrow;
    }
  }

  /// Register device with Headscale and get WireGuard configuration
  /// Uses Keycloak access token for authentication
  /// Note: This method is deprecated - use getPreAuthKey with Tailscale instead
  Future<WireGuardConfig?> registerDevice(String accessToken) async {
    try {
      _logger.d('Registering device with Headscale using Keycloak token');

      // Get device name
      final deviceName = Platform.isAndroid
          ? 'android-${DateTime.now().millisecondsSinceEpoch}'
          : 'ios-${DateTime.now().millisecondsSinceEpoch}';

      // TODO: Your backend needs to provide this endpoint
      // The endpoint should:
      // 1. Validate the Keycloak access token
      // 2. Register/authenticate the device with Headscale
      // 3. Return Wire Guard configuration
      final response = await http.post(
        Uri.parse('${_serverUrl ?? defaultServerUrl}/api/v1/device/register'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'device_name': deviceName,
          'platform': Platform.isAndroid ? 'android' : 'ios',
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200 || response.statusCode == 201) {
        _logger.d('Device registered successfully');
        _logger.d('Response body: ${response.body}');

        final data = json.decode(response.body);
        _logger.d('Parsed JSON data: $data');

        // Mark as registered
        await _storage.write(key: _keyNodeRegistered, value: 'true');
        _nodeRegistered = true;

        // Parse and return WireGuard configuration
        final config = WireGuardConfig.fromJson(data);
        _logger.d('WireGuard config created - IP: ${config.address}, Server: ${config.serverEndpoint}');

        return config;
      } else {
        _logger.e('Device registration failed: ${response.statusCode} - ${response.body}');
        throw Exception('Device registration failed: ${response.statusCode}');
      }
    } catch (e) {
      _logger.e('Error registering device: $e');
      rethrow;
    }
  }

  /// Launch Tailscale with Headscale server configured
  /// This is the proper way to connect - let Tailscale handle VPN
  Future<OIDCRegistrationResult> registerWithOIDC() async {
    try {
      _logger.d('Starting Tailscale launch with Headscale server');

      final serverUrl = _serverUrl ?? defaultServerUrl;
      _logger.d('Launching Tailscale with server: $serverUrl');

      if (Platform.isAndroid) {
        // Android: Use Intent to open Tailscale with custom server
        try {
          // Try to launch Tailscale with server URL
          final intent = AndroidIntent(
            action: 'android.intent.action.VIEW',
            package: 'com.tailscale.ipn',
            data: 'tailscale://login?server=$serverUrl',
          );

          await intent.launch();

          _logger.d('Tailscale launched successfully');

          // Mark as potentially registered (user will complete in Tailscale app)
          await _storage.write(key: _keyNodeRegistered, value: 'true');
          _nodeRegistered = true;

          return OIDCRegistrationResult(
            success: true,
            authUrl: serverUrl,
          );
        } catch (e) {
          _logger.w('Intent launch failed: $e');

          // Check if error indicates app not installed
          if (e.toString().contains('No Activity found') ||
              e.toString().contains('ActivityNotFoundException')) {
            return OIDCRegistrationResult(
              success: false,
              error: 'Tailscale app not installed. Please install it first.',
            );
          }

          // Try fallback: Open Tailscale app directly
          try {
            final appIntent = AndroidIntent(
              action: 'android.intent.action.MAIN',
              package: 'com.tailscale.ipn',
            );
            await appIntent.launch();

            return OIDCRegistrationResult(
              success: true,
              authUrl: serverUrl,
              error: 'Tailscale opened. Please configure server manually: $serverUrl',
            );
          } catch (fallbackError) {
            _logger.e('Fallback launch also failed: $fallbackError');
            return OIDCRegistrationResult(
              success: false,
              error: 'Tailscale app not installed. Please install it first.',
            );
          }
        }
      } else if (Platform.isIOS) {
        // iOS: Use URL scheme
        final tailscaleUrl = Uri.parse('tailscale://login?server=$serverUrl');

        try {
          final launched = await launchUrl(
            tailscaleUrl,
            mode: LaunchMode.externalApplication,
          );

          if (!launched) {
            _logger.e('Failed to launch Tailscale');
            return OIDCRegistrationResult(
              success: false,
              error: 'Tailscale app not installed. Please install it first.',
            );
          }

          await _storage.write(key: _keyNodeRegistered, value: 'true');
          _nodeRegistered = true;

          return OIDCRegistrationResult(
            success: true,
            authUrl: serverUrl,
          );
        } catch (e) {
          _logger.e('iOS launch failed: $e');
          return OIDCRegistrationResult(
            success: false,
            error: 'Tailscale app not installed. Please install it first.',
          );
        }
      }

      return OIDCRegistrationResult(
        success: false,
        error: 'Unsupported platform',
      );
    } catch (e) {
      _logger.e('Error launching Tailscale: $e');
      return OIDCRegistrationResult(
        success: false,
        error: 'Failed to launch Tailscale: ${e.toString()}',
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

/// WireGuard configuration for VPN connection
class WireGuardConfig {
  final String privateKey;
  final String publicKey;
  final String address;
  final String serverPublicKey;
  final String serverEndpoint;
  final String allowedIPs;
  final String? dns;
  final int? persistentKeepalive;

  WireGuardConfig({
    required this.privateKey,
    required this.publicKey,
    required this.address,
    required this.serverPublicKey,
    required this.serverEndpoint,
    required this.allowedIPs,
    this.dns,
    this.persistentKeepalive,
  });

  factory WireGuardConfig.fromJson(Map<String, dynamic> json) {
    return WireGuardConfig(
      privateKey: json['privateKey'] ?? json['private_key'] ?? '',
      publicKey: json['publicKey'] ?? json['public_key'] ?? '',
      address: json['address'] ?? json['ipv4'] ?? '',
      serverPublicKey: json['serverPublicKey'] ?? json['server_public_key'] ?? '',
      serverEndpoint: json['serverEndpoint'] ?? json['server_endpoint'] ?? '',
      allowedIPs: json['allowedIPs'] ?? json['allowed_ips'] ?? '0.0.0.0/0',
      dns: json['dns'],
      persistentKeepalive: json['persistentKeepalive'] ?? json['persistent_keepalive'] ?? 25,
    );
  }

  /// Generate wg-quick compatible configuration
  String toWgQuickConfig() {
    final buffer = StringBuffer();
    buffer.writeln('[Interface]');
    buffer.writeln('PrivateKey = $privateKey');
    buffer.writeln('Address = $address');
    if (dns != null) {
      buffer.writeln('DNS = $dns');
    }
    buffer.writeln();
    buffer.writeln('[Peer]');
    buffer.writeln('PublicKey = $serverPublicKey');
    buffer.writeln('Endpoint = $serverEndpoint');
    buffer.writeln('AllowedIPs = $allowedIPs');
    if (persistentKeepalive != null) {
      buffer.writeln('PersistentKeepalive = $persistentKeepalive');
    }
    return buffer.toString();
  }
}
