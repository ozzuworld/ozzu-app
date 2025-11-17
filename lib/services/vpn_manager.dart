import 'dart:async';
import 'package:logger/logger.dart';
import 'headscale_service.dart';
import 'keycloak_service.dart';
import 'tailscale_vpn_service.dart';

/// Manager for Tailscale VPN connections with Headscale
/// Handles tunnel setup, connection state, and statistics
class VPNManager {
  static final VPNManager _instance = VPNManager._internal();
  factory VPNManager() => _instance;
  VPNManager._internal();

  final _logger = Logger();
  final _headscaleService = HeadscaleService();
  final _tailscaleService = TailscaleVpnService();

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
      // Initialize Headscale service
      await _headscaleService.initialize();
      _logger.d('Headscale service initialized');

      // Listen to Tailscale connection state
      _tailscaleService.connectionStateStream.listen((state) {
        _handleTailscaleStateChange(state);
      });

      // Check current VPN status
      await _checkCurrentStatus();
    } catch (e) {
      _logger.e('Failed to initialize VPN manager: $e');
    }
  }

  /// Check current VPN status
  Future<void> _checkCurrentStatus() async {
    try {
      _logger.d('Checking current VPN status');
      final status = await _tailscaleService.getStatus();

      if (status != null && status['connected'] == true) {
        _assignedIpAddress = status['ipAddress'];
        _updateState(VPNConnectionState.connected);
      }
    } catch (e) {
      _logger.e('Error checking VPN status: $e');
    }
  }

  /// Handle Tailscale state changes
  void _handleTailscaleStateChange(TailscaleConnectionState state) {
    switch (state) {
      case TailscaleConnectionState.connected:
        _updateState(VPNConnectionState.connected);
        _headscaleService.updateConnectionStatus(ConnectionStatus.connected);
        _startStatsMonitoring();
        break;
      case TailscaleConnectionState.connecting:
        _updateState(VPNConnectionState.connecting);
        _headscaleService.updateConnectionStatus(ConnectionStatus.connecting);
        break;
      case TailscaleConnectionState.disconnected:
        _updateState(VPNConnectionState.disconnected);
        _headscaleService.updateConnectionStatus(ConnectionStatus.disconnected);
        _stopStatsMonitoring();
        break;
      case TailscaleConnectionState.disconnecting:
        _updateState(VPNConnectionState.disconnecting);
        _headscaleService.updateConnectionStatus(ConnectionStatus.disconnecting);
        break;
      case TailscaleConnectionState.error:
        _updateState(VPNConnectionState.error);
        _headscaleService.updateConnectionStatus(ConnectionStatus.error);
        break;
    }
  }

  /// Connect to VPN using Tailscale with Headscale
  /// Seamlessly authenticates using Keycloak and connects with pre-auth key
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

      _logger.d('Got access token, getting pre-auth key from Headscale');

      // Get pre-auth key from backend
      final response = await _headscaleService.getPreAuthKey(accessToken);

      if (response == null || response['pre_auth_key'] == null) {
        throw Exception('Failed to get pre-auth key from Headscale');
      }

      final preAuthKey = response['pre_auth_key'] as String;
      final loginServer = response['login_server'] as String? ?? 'https://headscale.ozzu.world';

      _logger.d('Got pre-auth key, connecting to Tailscale');
      _logger.d('Login server: $loginServer');

      // Connect using Tailscale with the pre-auth key
      final success = await _tailscaleService.connect(loginServer, preAuthKey);

      if (success) {
        _connectionStartTime = DateTime.now();
        _logger.d('Tailscale VPN connection initiated successfully');

        // The actual connection state will be updated via the stream listener
        return true;
      } else {
        throw Exception('Failed to initiate Tailscale connection');
      }
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

      // Disconnect Tailscale
      final success = await _tailscaleService.disconnect();

      if (success) {
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
