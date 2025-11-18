import 'dart:async';
import 'package:logger/logger.dart';
import 'package:wireguard_flutter/wireguard_flutter.dart';
import 'headscale_service.dart';
import 'keycloak_service.dart';

/// Manager for WireGuard VPN connections with Headscale
/// Handles tunnel setup, connection state, and statistics
class VPNManager {
  static final VPNManager _instance = VPNManager._internal();
  factory VPNManager() => _instance;
  VPNManager._internal();

  final _logger = Logger();
  final _headscaleService = HeadscaleService();
  final _wireguard = WireGuardFlutter.instance;

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

      // Initialize WireGuard
      await _wireguard.initialize(interfaceName: 'ozzu-vpn');
      _logger.d('WireGuard initialized');

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

      // Check if tunnel exists and is active
      final tunnelName = _currentTunnelName ?? 'ozzu-vpn';
      final stats = await _wireguard.tunnelGetStats(tunnelName: tunnelName);

      if (stats != null) {
        _updateState(VPNConnectionState.connected);
        _startStatsMonitoring();
      }
    } catch (e) {
      _logger.d('No active tunnel found');
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

      // Register device and get WireGuard configuration
      final config = await _headscaleService.registerDevice(accessToken);

      if (config == null) {
        throw Exception('Failed to get WireGuard configuration from Headscale');
      }

      _logger.d('Got WireGuard config:');
      _logger.d('  Address: ${config.address}');
      _logger.d('  Server endpoint: ${config.serverEndpoint}');
      _logger.d('  Allowed IPs: ${config.allowedIPs}');

      // Validate server public key
      if (config.serverPublicKey.isEmpty ||
          config.serverPublicKey == 'PLACEHOLDER_SERVER_KEY' ||
          config.serverPublicKey.contains('PLACEHOLDER')) {
        throw Exception(
          'Invalid server public key received from backend. '
          'Backend must provide the actual Headscale WireGuard public key. '
          'Current value: ${config.serverPublicKey}'
        );
      }

      // Build WireGuard configuration
      final wgConfig = _buildWireGuardConfig(config);
      _logger.d('Built WireGuard configuration');

      // Create and activate tunnel
      final tunnelName = 'ozzu-vpn';
      _currentTunnelName = tunnelName;
      _assignedIpAddress = config.address;

      _logger.d('Creating WireGuard tunnel: $tunnelName');
      await _wireguard.activate(wgConfig, tunnelName: tunnelName);

      _connectionStartTime = DateTime.now();
      _logger.d('WireGuard VPN connected successfully');

      _updateState(VPNConnectionState.connected);
      _headscaleService.updateConnectionStatus(ConnectionStatus.connected);
      _startStatsMonitoring();

      return true;
    } catch (e) {
      _logger.e('Failed to connect VPN: $e');
      _updateState(VPNConnectionState.error);
      _headscaleService.updateConnectionStatus(ConnectionStatus.error);
      rethrow; // Re-throw so UI can handle specific errors
    }
  }

  /// Build WireGuard configuration from Headscale response
  String _buildWireGuardConfig(WireGuardConfig config) {
    return '''[Interface]
PrivateKey = ${config.privateKey}
Address = ${config.address}
DNS = ${config.dns}

[Peer]
PublicKey = ${config.serverPublicKey}
Endpoint = ${config.serverEndpoint}
AllowedIPs = ${config.allowedIPs}
PersistentKeepalive = ${config.persistentKeepalive}
''';
  }

  /// Disconnect from VPN
  Future<bool> disconnect() async {
    if (_currentState == VPNConnectionState.disconnected) {
      _logger.w('Already disconnected');
      return true;
    }

    try {
      _logger.d('Disconnecting VPN');
      _updateState(VPNConnectionState.disconnecting);

      // Deactivate WireGuard tunnel
      if (_currentTunnelName != null) {
        await _wireguard.deactivate(tunnelName: _currentTunnelName!);
        _logger.d('WireGuard tunnel deactivated');
      }

      _connectionStartTime = null;
      _assignedIpAddress = null;
      _currentTunnelName = null;
      _currentStats = null;

      _stopStatsMonitoring();
      _updateState(VPNConnectionState.disconnected);
      _headscaleService.updateConnectionStatus(ConnectionStatus.disconnected);

      _logger.d('VPN disconnected successfully');
      return true;
    } catch (e) {
      _logger.e('Failed to disconnect VPN: $e');
      _updateState(VPNConnectionState.error);
      return false;
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
      if (_currentTunnelName == null) return;

      final stats = await _wireguard.tunnelGetStats(tunnelName: _currentTunnelName!);

      if (stats != null) {
        // Parse WireGuard stats
        // The stats format depends on wireguard_flutter implementation
        // This is a placeholder - adjust based on actual API
        _currentStats = VPNStats(
          bytesReceived: stats.totalRx ?? 0,
          bytesSent: stats.totalTx ?? 0,
          lastHandshake: stats.lastHandshakeTime,
        );
      }
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
