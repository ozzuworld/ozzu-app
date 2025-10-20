import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:math';
import '../services/keycloak_service.dart';
import 'login_screen.dart';

class VoiceCallScreen extends StatefulWidget {
  @override
  _VoiceCallScreenState createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends State<VoiceCallScreen>
    with TickerProviderStateMixin {
  final AuthService _authService = AuthService();
  Room? room;
  bool isConnected = false;
  bool isMuted = true;
  bool isConnecting = false;
  List<RemoteParticipant> remoteParticipants = [];
  String statusMessage = 'Initializing...';
  
  final String websocketUrl = 'wss://livekit.ozzu.world';
  final String tokenUrl = 'https://api.ozzu.world/api/livekit/token';  // Fixed: Added /api prefix
  
  // Fixed room name and participant name as per requirements
  final String roomName = 'ozzu-main';
  final String participantName = 'ozzu-app';
  
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _glowController;
  late Animation<double> _glowAnimation;
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    
    _pulseController = AnimationController(
      duration: Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(
      begin: 0.8,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
    
    _glowController = AnimationController(
      duration: Duration(seconds: 2),
      vsync: this,
    )..repeat();
    
    _glowAnimation = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _glowController,
      curve: Curves.easeInOut,
    ));
    
    _scaleController = AnimationController(
      duration: Duration(milliseconds: 200),
      vsync: this,
    );
    
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(
      parent: _scaleController,
      curve: Curves.easeInOut,
    ));
    
    // Auto-connect to LiveKit immediately
    _autoConnect();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _glowController.dispose();
    _scaleController.dispose();
    disconnectFromRoom();
    super.dispose();
  }

  Future<void> _autoConnect() async {
    // Small delay to let the UI settle
    await Future.delayed(Duration(milliseconds: 500));
    await connectToRoom();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Column(
            children: [
              // Top header with OZZU branding and logout
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'OZZU',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 4,
                    ),
                  ),
                  GestureDetector(
                    onTap: _logout,
                    child: Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.2),
                        ),
                      ),
                      child: Icon(
                        Icons.logout,
                        color: Colors.white70,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
              
              // Spacer to center the main content
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Main glowing blue circle
                    GestureDetector(
                      onTapDown: (_) => _scaleController.forward(),
                      onTapUp: (_) {
                        _scaleController.reverse();
                        if (isConnected) {
                          toggleMute();
                        }
                      },
                      onTapCancel: () => _scaleController.reverse(),
                      child: AnimatedBuilder(
                        animation: _scaleAnimation,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _scaleAnimation.value,
                            child: AnimatedBuilder(
                              animation: _pulseAnimation,
                              builder: (context, child) {
                                return AnimatedBuilder(
                                  animation: _glowAnimation,
                                  builder: (context, child) {
                                    return Container(
                                      width: 280,
                                      height: 280,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.blue.withOpacity(0.2),
                                        boxShadow: [
                                          // Main glow
                                          BoxShadow(
                                            color: Colors.blue.withOpacity(
                                              0.4 * _glowAnimation.value * _pulseAnimation.value,
                                            ),
                                            blurRadius: 60,
                                            spreadRadius: 20,
                                          ),
                                          // Secondary glow
                                          BoxShadow(
                                            color: Colors.cyan.withOpacity(
                                              0.3 * _glowAnimation.value * _pulseAnimation.value,
                                            ),
                                            blurRadius: 100,
                                            spreadRadius: 30,
                                          ),
                                          // Inner glow
                                          BoxShadow(
                                            color: Colors.blue.withOpacity(
                                              0.6 * _pulseAnimation.value,
                                            ),
                                            blurRadius: 30,
                                            spreadRadius: -10,
                                          ),
                                        ],
                                      ),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.blue.withOpacity(0.8),
                                            width: 3,
                                          ),
                                        ),
                                        child: Center(
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                isConnected 
                                                    ? (isMuted ? Icons.mic_off : Icons.mic)
                                                    : Icons.power_settings_new,
                                                size: 60,
                                                color: Colors.white,
                                              ),
                                              SizedBox(height: 12),
                                              Text(
                                                isConnected
                                                    ? (isMuted ? 'Tap to Unmute' : 'Tap to Mute')
                                                    : (isConnecting ? 'Connecting...' : 'Disconnected'),
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                                textAlign: TextAlign.center,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ),
                    
                    SizedBox(height: 60),
                    
                    // Status message
                    Text(
                      statusMessage,
                      style: TextStyle(
                        fontSize: 20,
                        color: isConnected ? Colors.green : 
                               isConnecting ? Colors.orange : Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    
                    if (remoteParticipants.isNotEmpty) ...[
                      SizedBox(height: 20),
                      Text(
                        '${remoteParticipants.length} participant${remoteParticipants.length > 1 ? 's' : ''} connected',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.white60,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              
              // Bottom controls
              Column(
                children: [
                  if (!isConnected && !isConnecting)
                    Container(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: connectToRoom,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.withOpacity(0.8),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          'Reconnect',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  
                  if (isConnected) 
                    Container(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: disconnectFromRoom,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.withOpacity(0.8),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          'Disconnect',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  
                  SizedBox(height: 20),
                  
                  // Connection info
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.1),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: isConnected ? Colors.green : Colors.red,
                                shape: BoxShape.circle,
                              ),
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Room: $roomName',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: Colors.blue,
                                shape: BoxShape.circle,
                              ),
                            ),
                            SizedBox(width: 8),
                            Text(
                              'User: $participantName',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Future<String> getToken() async {
    try {
      setState(() { statusMessage = 'Getting authentication token...'; });
      
      // Get access token for API authentication
      final accessToken = await _authService.getAccessToken();
      
      final response = await http.post(
        Uri.parse(tokenUrl),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          if (accessToken != null) 'Authorization': 'Bearer $accessToken',
          'User-Agent': 'OZZU-App/1.0',
        },
        body: json.encode({
          'service_identity': participantName,  // Fixed: Use correct field name expected by backend
        }),
      ).timeout(Duration(seconds: 30));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map<String, dynamic> && data['token'] != null) {
          return data['token'];
        }
        throw Exception('Token field not found in response');
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      throw Exception('Could not get token: $e');
    }
  }

  Future<void> connectToRoom() async {
    setState(() { 
      isConnecting = true; 
      statusMessage = 'Initializing connection...'; 
    });
    
    try {
      final token = await getToken();
      setState(() { statusMessage = 'Connecting to OZZU voice...'; });
      
      room = Room(roomOptions: const RoomOptions(
        adaptiveStream: true, 
        dynacast: true
      ));
      
      room!.addListener(_onRoomUpdate);
      await room!.connect(websocketUrl, token);
      await room!.localParticipant?.setMicrophoneEnabled(false);
      
      setState(() { 
        isConnected = true; 
        isConnecting = false; 
        statusMessage = 'Connected to OZZU'; 
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connected to OZZU voice'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (error) {
      setState(() { 
        isConnected = false; 
        isConnecting = false; 
        statusMessage = 'Connection failed'; 
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to connect: ${error.toString()}'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> disconnectFromRoom() async {
    try {
      setState(() { statusMessage = 'Disconnecting...'; });
      await room?.disconnect();
      room?.removeListener(_onRoomUpdate);
      
      setState(() { 
        isConnected = false; 
        remoteParticipants.clear(); 
        isMuted = true; 
        statusMessage = 'Disconnected'; 
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Disconnected from OZZU'),
            backgroundColor: Colors.grey,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (error) {
      setState(() { statusMessage = 'Error during disconnect'; });
    }
  }

  Future<void> toggleMute() async {
    try {
      if (room?.localParticipant != null) {
        await room!.localParticipant!.setMicrophoneEnabled(isMuted);
        setState(() { isMuted = !isMuted; });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(isMuted ? 'Microphone muted' : 'Microphone unmuted'),
              duration: Duration(seconds: 1),
              backgroundColor: isMuted ? Colors.orange : Colors.green,
            ),
          );
        }
      }
    } catch (error) {
      // ignore
    }
  }

  Future<void> _logout() async {
    try {
      // Disconnect from voice room first
      if (isConnected) {
        await disconnectFromRoom();
      }
      
      // Logout from Keycloak
      await _authService.logout();
      
      // Navigate back to login screen
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => LoginScreen()),
        );
      }
    } catch (e) {
      print('Logout error: $e');
      // Force navigation anyway
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => LoginScreen()),
        );
      }
    }
  }

  void _onRoomUpdate() {
    if (mounted) {
      setState(() { 
        remoteParticipants = room?.remoteParticipants.values.toList() ?? [];
      });
    }
  }
}