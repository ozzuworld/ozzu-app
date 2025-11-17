import 'dart:ui';
import 'package:flutter/material.dart';
import '../services/headscale_service.dart';
import '../services/vpn_manager.dart';

/// Security screen with VPN-style UI for headscale integration
class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> with TickerProviderStateMixin {
  final _headscaleService = HeadscaleService();
  final _vpnManager = VPNManager();

  VPNConnectionState _connectionState = VPNConnectionState.disconnected;
  List<HeadscaleNode> _nodes = [];
  bool _loadingNodes = false;
  late AnimationController _pulseController;
  late AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _setupAnimations();
    _listenToConnectionState();
  }

  void _setupAnimations() {
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
  }

  Future<void> _initializeServices() async {
    await _headscaleService.initialize();
    await _vpnManager.initialize();

    // No configuration needed - OIDC handles everything automatically

    setState(() {
      _connectionState = _vpnManager.currentState;
    });
  }

  void _listenToConnectionState() {
    _vpnManager.connectionStateStream.listen((state) {
      setState(() {
        _connectionState = state;
      });

      if (state == VPNConnectionState.connecting) {
        _rotationController.repeat();
      } else {
        _rotationController.stop();
      }
    });
  }

  Future<void> _loadNodes() async {
    // Only load nodes if we have API credentials (optional feature)
    // Most users won't need this with OIDC
    setState(() {
      _loadingNodes = true;
    });

    try {
      final nodes = await _headscaleService.getNodes();
      setState(() {
        _nodes = nodes;
        _loadingNodes = false;
      });
    } catch (e) {
      setState(() {
        _loadingNodes = false;
      });
      // Silently fail - not critical for VPN connection
    }
  }

  Future<void> _toggleConnection() async {
    if (_connectionState == VPNConnectionState.connecting ||
        _connectionState == VPNConnectionState.disconnecting) {
      return;
    }

    if (_connectionState == VPNConnectionState.connected) {
      await _vpnManager.disconnect();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Disconnected from VPN'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } else {
      try {
        final success = await _vpnManager.connect();

        if (success && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Connected to Ozzu VPN'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        } else if (!success && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to connect. Please try again.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          String errorMsg = 'Connection failed';

          if (e.toString().contains('Not authenticated')) {
            errorMsg = 'Please log in first';
          } else if (e.toString().contains('registration failed') ||
                     e.toString().contains('Device registration failed')) {
            errorMsg = 'Failed to register device. Please contact support.';
          } else if (e.toString().contains('500')) {
            errorMsg = 'Server error. Backend endpoint may not be implemented yet.';
          } else {
            errorMsg = 'Error: ${e.toString().replaceAll('Exception:', '').trim()}';
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMsg),
              backgroundColor: Colors.redAccent,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'VPN',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadNodes,
        backgroundColor: const Color(0xFF1E1E2E),
        color: Colors.cyanAccent,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const SizedBox(height: 20),
              _buildConnectionCard(),
              const SizedBox(height: 30),
              _buildConnectionInfo(),
              const SizedBox(height: 30),
              _buildDevicesList(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionCard() {
    final isConnected = _connectionState == VPNConnectionState.connected;
    final isConnecting = _connectionState == VPNConnectionState.connecting;

    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: Colors.white.withOpacity(0.1),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            children: [
              // Shield Icon
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  return Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _getStatusColor().withOpacity(0.1),
                      boxShadow: [
                        BoxShadow(
                          color: _getStatusColor().withOpacity(
                            isConnected ? 0.3 + (_pulseController.value * 0.3) : 0.1,
                          ),
                          blurRadius: 30,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                    child: RotationTransition(
                      turns: isConnecting ? _rotationController : const AlwaysStoppedAnimation(0),
                      child: Icon(
                        isConnected ? Icons.shield : Icons.shield_outlined,
                        size: 60,
                        color: _getStatusColor(),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 30),

              // Status Text
              Text(
                _getStatusText(),
                style: TextStyle(
                  color: _getStatusColor(),
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 10),

              // IP Address
              if (isConnected && _vpnManager.assignedIpAddress != null)
                Text(
                  _vpnManager.assignedIpAddress!,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 18,
                  ),
                ),
              const SizedBox(height: 30),

              // Toggle Button
              GestureDetector(
                onTap: _toggleConnection,
                child: Container(
                  width: 200,
                  height: 60,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isConnected
                          ? [Colors.redAccent, Colors.red.shade700]
                          : [Colors.cyanAccent, Colors.cyan.shade700],
                    ),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: (isConnected ? Colors.redAccent : Colors.cyanAccent)
                            .withOpacity(0.4),
                        blurRadius: 15,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Center(
                    child: isConnecting
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              strokeWidth: 3,
                            ),
                          )
                        : Text(
                            isConnected ? 'DISCONNECT' : 'CONNECT',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionInfo() {
    final isConnected = _connectionState == VPNConnectionState.connected;
    final duration = _vpnManager.connectionDuration;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withOpacity(0.1),
              width: 1,
            ),
          ),
          child: Column(
            children: [
              _buildInfoRow('Server', HeadscaleService.defaultServerUrl),
              const Divider(color: Colors.white12, height: 24),
              _buildInfoRow('Authentication', 'Keycloak SSO'),
              if (isConnected && duration != null) ...[
                const Divider(color: Colors.white12, height: 24),
                _buildInfoRow('Uptime', _formatDuration(duration)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontSize: 16,
          ),
        ),
        Flexible(
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildDevicesList() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withOpacity(0.1),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'My Devices (${_nodes.length})',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.refresh,
                        color: Colors.cyanAccent.withOpacity(0.8),
                      ),
                      onPressed: _loadingNodes ? null : _loadNodes,
                    ),
                  ],
                ),
              ),
              if (_loadingNodes)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.cyanAccent),
                    ),
                  ),
                )
              else if (_nodes.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Center(
                    child: Text(
                      'No devices found',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 16,
                      ),
                    ),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _nodes.length,
                  separatorBuilder: (context, index) => Divider(
                    color: Colors.white.withOpacity(0.1),
                    height: 1,
                  ),
                  itemBuilder: (context, index) {
                    final node = _nodes[index];
                    return ListTile(
                      leading: Text(
                        node.deviceIcon,
                        style: const TextStyle(fontSize: 24),
                      ),
                      title: Text(
                        node.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        node.primaryIp,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                        ),
                      ),
                      trailing: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: node.online ? Colors.greenAccent : Colors.grey,
                          shape: BoxShape.circle,
                          boxShadow: node.online
                              ? [
                                  BoxShadow(
                                    color: Colors.greenAccent.withOpacity(0.6),
                                    blurRadius: 6,
                                    spreadRadius: 1,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getStatusColor() {
    switch (_connectionState) {
      case VPNConnectionState.connected:
        return Colors.greenAccent;
      case VPNConnectionState.connecting:
        return Colors.blueAccent;
      case VPNConnectionState.disconnected:
        return Colors.orangeAccent;
      case VPNConnectionState.error:
        return Colors.redAccent;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText() {
    switch (_connectionState) {
      case VPNConnectionState.connected:
        return 'CONNECTED';
      case VPNConnectionState.connecting:
        return 'CONNECTING...';
      case VPNConnectionState.disconnected:
        return 'DISCONNECTED';
      case VPNConnectionState.error:
        return 'ERROR';
      default:
        return 'UNKNOWN';
    }
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }
}
