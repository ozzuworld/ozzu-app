import 'dart:async';
import 'package:logger/logger.dart';
import 'package:wireguard_flutter/wireguard_flutter.dart';
import 'headscale_service.dart';
import 'keycloak_service.dart';

/// Manager for WireGuard VPN connections
/// Handles tunnel setup, connection state, and statistics
class VPNManager {
  static final VPNManager _instance = VPNManager._internal();
  factory VPNManager() => _instance;
  VPNManager._internal();

  final _logger = Logger();
  final _headscaleService = HeadscaleService();
  final _wireguardFlutterPlugin = WireGuardFlutter.instance;

  // Connection state
  final _connectionStateController = StreamController<VPNConnectionState>.broadcast();
  Stream<VPNConnectionState> get connectionStateStream => _connectionStateController.stream;
  VPNConnectionState _currentState = VPNConnectionState.disconnected;
  VPNConnectionState get currentState => _currentState;

  // VPN statistics
  VPNStats? _currentStats;
  VPNStats? get currentStats => _currentStats;

  Timer? _statsUpdateTimer;
  DateTime? _connectionStartTime;

  String? _currentTunnelName;
  String? _assignedIpAddress;

  String? get assignedIpAddress => _assignedIpAddress;
  Duration? get connectionDuration {
    if (_connectionStartTime == null) return null;
    return DateTime.now().difference(_connectionStartTime!);
  }

  /// Initialize the VPN manager
  Future<void> initialize() async {
    _logger.d('Initializing VPNManager');

    try {
      // Initialize WireGuard plugin
      await _wireguardFlutterPlugin.initialize(interfaceName: 'ozzu_wg0');
      _logger.d('WireGuard plugin initialized');

      // Check if there's an existing active tunnel
      await _checkExistingTunnel();
    } catch (e) {
      _logger.e('Failed to initialize VPN manager: $e');
    }
  }

  /// Check for existing active tunnel
  Future<void> _checkExistingTunnel() async {
    try {
      // This is a placeholder - actual implementation depends on wireguard_flutter API
      _logger.d('Checking for existing tunnels');
    } catch (e) {
      _logger.e('Error checking existing tunnel: $e');
    }
  }

  /// Connect to VPN using WireGuard with Headscale
  /// Seamlessly authenticates using Keycloak and connects
  Future<bool> connect() async {
    if (_currentState == VPNConnectionState.connected ||
        _currentState == VPNConnectionState.connecting) {
      _logger.w('Already connected or connecting');
      return false;
    }

    _updateState(VPNConnectionState.connecting);
    _headscaleService.updateConnectionStatus(ConnectionStatus.connecting);

    try {
      _logger.d('Starting VPN connection with Headscale');

      // Get Keycloak access token
      final authService = AuthService();
      final accessToken = await authService.getAccessToken();

      if (accessToken == null || accessToken.isEmpty) {
        throw Exception('Not authenticated. Please log in first.');
      }

      _logger.d('Got access token, registering device with Headscale');

      // Register device with Headscale using Keycloak token
      // This will return WireGuard configuration
      final wgConfig = await _headscaleService.registerDevice(accessToken);

      if (wgConfig == null) {
        throw Exception('Failed to get WireGuard configuration from Headscale');
      }

      _logger.d('Device registered, starting WireGuard tunnel');
      _logger.d('Assigned IP: ${wgConfig.address}');

      // Initialize WireGuard interface
      await _wireguardFlutterPlugin.initialize(interfaceName: 'ozzu_wg0');

      // Start VPN with WireGuard configuration
      await _wireguardFlutterPlugin.startVpn(
        serverAddress: wgConfig.serverEndpoint,
        wgQuickConfig: wgConfig.toWgQuickConfig(),
        providerBundleIdentifier: 'com.example.livekitvoiceapp',
      );

      _logger.d('WireGuard tunnel started successfully');

      // Update connection state
      _connectionStartTime = DateTime.now();
      _assignedIpAddress = wgConfig.address;
      _currentTunnelName = 'ozzu_wg0';

      _updateState(VPNConnectionState.connected);
      _headscaleService.updateConnectionStatus(ConnectionStatus.connected);

      // Start monitoring
      _startStatsMonitoring();

      return true;
    } catch (e) {
      _logger.e('Failed to connect VPN: $e');
      _updateState(VPNConnectionState.error);
      _headscaleService.updateConnectionStatus(ConnectionStatus.error);
      rethrow; // Re-throw so UI can handle specific errors
    }
  }

  /// Disconnect from VPN
  Future<bool> disconnect() async {
    if (_currentState == VPNConnectionState.disconnected) {
      _logger.w('Already disconnected');
      return true;
    }

    try {
      _logger.d('Disconnecting VPN');

      // Stop WireGuard tunnel
      await _wireguardFlutterPlugin.stopVpn();

      _logger.d('VPN disconnected successfully');

      _connectionStartTime = null;
      _assignedIpAddress = null;
      _currentTunnelName = null;
      _currentStats = null;

      _stopStatsMonitoring();
      _updateState(VPNConnectionState.disconnected);
      _headscaleService.updateConnectionStatus(ConnectionStatus.disconnected);

      return true;
    } catch (e) {
      _logger.e('Failed to disconnect VPN: $e');
      return false;
    }
  }

  /// Generate WireGuard tunnel configuration
  /// In production, this should fetch the actual config from Headscale API
  Future<Map<String, String>?> _generateTunnelConfig() async {
    try {
      _logger.d('Generating WireGuard configuration');

      // Use the Headscale server URL
      final serverUrl = HeadscaleService.defaultServerUrl;

      // In a production implementation, you would:
      // 1. Fetch the device's WireGuard config from Headscale API
      // 2. Parse the response to get the actual keys and IP addresses
      // 3. Build the proper WireGuard configuration
      //
      // For now, we return a mock configuration
      // The actual VPN connection happens through OIDC registration above

      return {
        'serverAddress': serverUrl,
        'clientAddress': '100.64.0.1', // This should come from headscale API
        'wgQuickConfig': '''
[Interface]
PrivateKey = <GENERATED_PRIVATE_KEY>
Address = 100.64.0.1/32
DNS = 100.100.100.100

[Peer]
PublicKey = <SERVER_PUBLIC_KEY>
Endpoint = $serverUrl:51820
AllowedIPs = 100.64.0.0/10
PersistentKeepalive = 25
''',
      };
    } catch (e) {
      _logger.e('Failed to generate tunnel config: $e');
      return null;
    }
  }

  /// Start monitoring VPN statistics
  void _startStatsMonitoring() {
    _stopStatsMonitoring();

    _statsUpdateTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      await _updateStats();
    });

    _logger.d('Started statistics monitoring');
  }

  /// Stop monitoring VPN statistics
  void _stopStatsMonitoring() {
    _statsUpdateTimer?.cancel();
    _statsUpdateTimer = null;
    _logger.d('Stopped statistics monitoring');
  }

  /// Update VPN statistics
  Future<void> _updateStats() async {
    try {
      // This is a placeholder - actual implementation depends on wireguard_flutter API
      // In a real implementation, you would query the WireGuard interface for stats

      _currentStats = VPNStats(
        bytesReceived: 0,
        bytesSent: 0,
        lastHandshake: DateTime.now(),
      );
    } catch (e) {
      _logger.e('Failed to update stats: $e');
    }
  }

  /// Update connection state
  void _updateState(VPNConnectionState state) {
    if (_currentState != state) {
      _currentState = state;
      _connectionStateController.add(state);
      _logger.d('VPN state updated: $state');
    }
  }

  /// Dispose resources
  void dispose() {
    _stopStatsMonitoring();
    _connectionStateController.close();
  }
}

/// VPN connection state
enum VPNConnectionState {
  disconnected,
  connecting,
  connected,
  disconnecting,
  error,
}

/// VPN statistics model
class VPNStats {
  final int bytesReceived;
  final int bytesSent;
  final DateTime? lastHandshake;

  VPNStats({
    required this.bytesReceived,
    required this.bytesSent,
    this.lastHandshake,
  });

  String get formattedBytesReceived => _formatBytes(bytesReceived);
  String get formattedBytesSent => _formatBytes(bytesSent);

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
