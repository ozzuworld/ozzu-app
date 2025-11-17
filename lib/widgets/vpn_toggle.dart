import 'package:flutter/material.dart';
import 'dart:async';
import '../services/vpn_manager.dart';
import '../services/headscale_service.dart';
import 'package:logger/logger.dart';

/// VPN Toggle Widget
/// Provides a toggle switch to connect/disconnect from VPN with seamless OIDC SSO
class VPNToggle extends StatefulWidget {
  const VPNToggle({super.key});

  @override
  State<VPNToggle> createState() => _VPNToggleState();
}

class _VPNToggleState extends State<VPNToggle> {
  final VPNManager _vpnManager = VPNManager();
  final HeadscaleService _headscaleService = HeadscaleService();
  final Logger _logger = Logger();

  VPNConnectionState _connectionState = VPNConnectionState.disconnected;
  String? _vpnIP;
  Duration? _connectionDuration;
  Timer? _updateTimer;
  bool _tailscaleInstalled = false;

  StreamSubscription<VPNConnectionState>? _connectionSubscription;

  @override
  void initState() {
    super.initState();
    _initializeVPN();
  }

  Future<void> _initializeVPN() async {
    await _vpnManager.initialize();
    await _headscaleService.initialize();

    // Check if Tailscale is installed
    final installed = await _headscaleService.isTailscaleInstalled();
    setState(() {
      _tailscaleInstalled = installed;
    });

    // Listen to connection state changes
    _connectionSubscription = _vpnManager.connectionStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _connectionState = state;
          _vpnIP = _vpnManager.assignedIpAddress;
        });
      }
    });

    // Get initial state
    setState(() {
      _connectionState = _vpnManager.currentState;
      _vpnIP = _vpnManager.assignedIpAddress;
    });

    // Start periodic updates for connection duration
    if (_connectionState == VPNConnectionState.connected) {
      _startDurationUpdates();
    }
  }

  void _startDurationUpdates() {
    _updateTimer?.cancel();
    _updateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted && _connectionState == VPNConnectionState.connected) {
        setState(() {
          _connectionDuration = _vpnManager.connectionDuration;
        });
      }
    });
  }

  void _stopDurationUpdates() {
    _updateTimer?.cancel();
    _updateTimer = null;
  }

  Future<void> _handleToggle(bool value) async {
    if (value) {
      // Check if Tailscale is installed first
      if (!_tailscaleInstalled) {
        _showTailscaleInstallDialog();
        return;
      }

      // Connect to VPN (launches Tailscale)
      try {
        final success = await _vpnManager.connect();

        if (success) {
          _startDurationUpdates();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Tailscale launched! Complete setup in the Tailscale app.'),
                backgroundColor: Colors.blue,
                duration: Duration(seconds: 4),
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Failed to launch Tailscale. Please try again.'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 3),
              ),
            );
          }
        }
      } catch (e) {
        _logger.e('VPN connection error: $e');
        if (mounted) {
          final errorMsg = e.toString().contains('Tailscale app required')
              ? 'Tailscale app not installed'
              : 'Error: $e';

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMsg),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
              action: e.toString().contains('Tailscale app required')
                  ? SnackBarAction(
                      label: 'Install',
                      onPressed: () async {
                        await _headscaleService.openTailscaleInstallPage();
                      },
                    )
                  : null,
            ),
          );
        }
      }
    } else {
      // Note: We can't disconnect Tailscale from our app
      // User needs to do it in the Tailscale app
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Open Tailscale app to disconnect'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _showTailscaleInstallDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tailscale Required'),
        content: const Text(
          'Tailscale app is required for VPN connection. '
          'Would you like to install it from the app store?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _headscaleService.openTailscaleInstallPage();
              // Recheck after user might have installed
              await Future.delayed(const Duration(seconds: 2));
              final installed = await _headscaleService.isTailscaleInstalled();
              if (mounted) {
                setState(() {
                  _tailscaleInstalled = installed;
                });
              }
            },
            child: const Text('Install'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = _connectionState == VPNConnectionState.connected;
    final isConnecting = _connectionState == VPNConnectionState.connecting;
    final isDisconnecting = _connectionState == VPNConnectionState.disconnecting;
    final hasError = _connectionState == VPNConnectionState.error;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isConnected
              ? Colors.green.withOpacity(0.3)
              : hasError
                  ? Colors.red.withOpacity(0.3)
                  : Colors.white.withOpacity(0.1),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row with title and toggle
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.vpn_lock,
                          color: isConnected ? Colors.green : Colors.white.withOpacity(0.7),
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'VPN Connection',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    if (isConnected && _vpnIP != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'IP: $_vpnIP',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 12,
                        ),
                      ),
                    ],
                    if (isConnected && _connectionDuration != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Connected: ${_formatDuration(_connectionDuration!)}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (isConnecting || isDisconnecting)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                  ),
                )
              else
                Switch(
                  value: isConnected,
                  onChanged: (value) => _handleToggle(value),
                  activeColor: Colors.green,
                  activeTrackColor: Colors.green.withOpacity(0.5),
                  inactiveThumbColor: Colors.grey,
                  inactiveTrackColor: Colors.grey.withOpacity(0.3),
                ),
            ],
          ),

          // Status badge
          if (isConnected || hasError) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isConnected ? Colors.green : Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  isConnected ? 'Connected' : 'Connection Error',
                  style: TextStyle(
                    color: isConnected ? Colors.green : Colors.red,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],

          // Info text
          if (!isConnected && !isConnecting && !hasError) ...[
            const SizedBox(height: 12),
            Text(
              'Connect to Ozzu VPN for secure access to private resources',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }
}
