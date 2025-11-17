import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';

/// Service for managing Tailscale VPN connections with Headscale
/// Uses native Tailscale SDK through platform channels
class TailscaleVpnService {
  static final TailscaleVpnService _instance = TailscaleVpnService._internal();
  factory TailscaleVpnService() => _instance;
  TailscaleVpnService._internal();

  final _logger = Logger();
  static const _platform = MethodChannel('com.example.livekitvoiceapp/tailscale');

  // Connection state
  final _connectionStateController = StreamController<TailscaleConnectionState>.broadcast();
  Stream<TailscaleConnectionState> get connectionStateStream => _connectionStateController.stream;

  TailscaleConnectionState _currentState = TailscaleConnectionState.disconnected;
  TailscaleConnectionState get currentState => _currentState;

  String? _ipAddress;
  String? get ipAddress => _ipAddress;

  /// Connect to VPN using Tailscale with Headscale server
  ///
  /// Parameters:
  /// - [loginServer]: The Headscale server URL (e.g., "https://headscale.ozzu.world")
  /// - [authKey]: Pre-authentication key from Headscale
  Future<bool> connect(String loginServer, String authKey) async {
    if (_currentState == TailscaleConnectionState.connected ||
        _currentState == TailscaleConnectionState.connecting) {
      _logger.w('Already connected or connecting');
      return false;
    }

    _updateState(TailscaleConnectionState.connecting);

    try {
      _logger.d('Connecting to Tailscale with Headscale server: $loginServer');

      if (Platform.isAndroid) {
        final result = await _platform.invokeMethod('connect', {
          'loginServer': loginServer,
          'authKey': authKey,
        });

        _logger.d('Tailscale connection initiated: $result');

        // Note: The actual connection happens in the Tailscale app/SDK
        // We mark as connected here, but the SDK will handle the actual VPN
        _updateState(TailscaleConnectionState.connected);

        return true;
      } else if (Platform.isIOS) {
        // iOS implementation will be similar
        final result = await _platform.invokeMethod('connect', {
          'loginServer': loginServer,
          'authKey': authKey,
        });

        _logger.d('Tailscale connection initiated: $result');
        _updateState(TailscaleConnectionState.connected);

        return true;
      }

      return false;
    } on PlatformException catch (e) {
      _logger.e('Failed to connect: ${e.code} - ${e.message}');
      _updateState(TailscaleConnectionState.error);
      rethrow;
    } catch (e) {
      _logger.e('Unexpected error during connection: $e');
      _updateState(TailscaleConnectionState.error);
      rethrow;
    }
  }

  /// Disconnect from VPN
  Future<bool> disconnect() async {
    if (_currentState == TailscaleConnectionState.disconnected) {
      _logger.w('Already disconnected');
      return true;
    }

    _updateState(TailscaleConnectionState.disconnecting);

    try {
      _logger.d('Disconnecting from Tailscale');

      final result = await _platform.invokeMethod('disconnect');
      _logger.d('Disconnection result: $result');

      _ipAddress = null;
      _updateState(TailscaleConnectionState.disconnected);

      return true;
    } on PlatformException catch (e) {
      _logger.e('Failed to disconnect: ${e.code} - ${e.message}');
      _updateState(TailscaleConnectionState.error);
      return false;
    } catch (e) {
      _logger.e('Unexpected error during disconnection: $e');
      _updateState(TailscaleConnectionState.error);
      return false;
    }
  }

  /// Get current VPN status
  Future<Map<String, dynamic>?> getStatus() async {
    try {
      final result = await _platform.invokeMethod('getStatus');

      if (result is Map) {
        final status = Map<String, dynamic>.from(result);

        // Update local state based on status
        if (status['connected'] == true) {
          _ipAddress = status['ipAddress'];
          _updateState(TailscaleConnectionState.connected);
        } else {
          _updateState(TailscaleConnectionState.disconnected);
        }

        return status;
      }

      return null;
    } on PlatformException catch (e) {
      _logger.e('Failed to get status: ${e.code} - ${e.message}');
      return null;
    } catch (e) {
      _logger.e('Unexpected error getting status: $e');
      return null;
    }
  }

  void _updateState(TailscaleConnectionState newState) {
    if (_currentState != newState) {
      _logger.d('Tailscale state updated: $newState');
      _currentState = newState;
      _connectionStateController.add(newState);
    }
  }

  void dispose() {
    _connectionStateController.close();
  }
}

/// Connection states for Tailscale VPN
enum TailscaleConnectionState {
  disconnected,
  connecting,
  connected,
  disconnecting,
  error,
}
