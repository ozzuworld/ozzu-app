import 'dart:async';
import 'dart:io';
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

  StreamSubscription<dynamic>? _stageSubscription;
  DateTime? _connectionStartTime;

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

      // Listen to VPN stage changes
      _stageSubscription = _wireguard.vpnStageSnapshot.listen((stage) {
        _handleStageChange(stage);
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
      final stage = await _wireguard.stage();
      _handleStageChange(stage);
    } catch (e) {
      _logger.d('Error checking VPN status: $e');
    }
  }

  /// Handle WireGuard stage changes
  void _handleStageChange(dynamic stage) {
    _logger.d('WireGuard stage changed: $stage');

    // Map WireGuard stages to our VPN states
    if (stage.toString().toLowerCase().contains('connected')) {
      _updateState(VPNConnectionState.connected);
      _headscaleService.updateConnectionStatus(ConnectionStatus.connected);
    } else if (stage.toString().toLowerCase().contains('connecting') ||
        stage.toString().toLowerCase().contains('preparing') ||
        stage.toString().toLowerCase().contains('authenticating')) {
      _updateState(VPNConnectionState.connecting);
      _headscaleService.updateConnectionStatus(ConnectionStatus.connecting);
    } else if (stage.toString().toLowerCase().contains('disconnecting') ||
        stage.toString().toLowerCase().contains('exiting')) {
      _updateState(VPNConnectionState.disconnecting);
    } else if (stage.toString().toLowerCase().contains('disconnected') ||
        stage.toString().toLowerCase().contains('noconnection')) {
      _updateState(VPNConnectionState.disconnected);
      _headscaleService.updateConnectionStatus(ConnectionStatus.disconnected);
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

      // Store assigned IP
      _assignedIpAddress = config.address;

      // Get server address from endpoint (remove port)
      final serverAddress = config.serverEndpoint.split(':')[0];

      // Get provider bundle identifier (application ID)
      final providerBundleIdentifier = Platform.isAndroid
          ? 'com.example.livekitvoiceapp'
          : 'com.example.livekitVoiceApp';

      _logger.d('Starting VPN with WireGuard');
      _logger.d('  Server: $serverAddress');
      _logger.d('  Provider: $providerBundleIdentifier');

      // Start VPN connection
      await _wireguard.startVpn(
        serverAddress: serverAddress,
        wgQuickConfig: wgConfig,
        providerBundleIdentifier: providerBundleIdentifier,
      );

      _connectionStartTime = DateTime.now();
      _logger.d('WireGuard VPN connection initiated successfully');

      // The actual connection state will be updated via the stream listener
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

      // Stop VPN connection
      await _wireguard.stopVpn();
      _logger.d('WireGuard VPN stopped');

      _connectionStartTime = null;
      _assignedIpAddress = null;
      _currentStats = null;

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
    _stageSubscription?.cancel();
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
