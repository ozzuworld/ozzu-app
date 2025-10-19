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

class _VoiceCallScreenState extends State<VoiceCallScreen> {
  final AuthService _authService = AuthService();
  Room? room;
  bool isConnected = false;
  bool isMuted = true;
  bool isConnecting = false;
  List<RemoteParticipant> remoteParticipants = [];
  String statusMessage = 'Not Connected';
  
  final String websocketUrl = 'wss://livekit.ozzu.world';
  final String tokenUrl = 'https://api.ozzu.world/livekit/token';
  
  final String defaultRoomName = 'voice-room';
  
  // Use authenticated user info for participant name
  String get authenticatedParticipantName {
    final userInfo = _authService.userInfo;
    if (userInfo != null) {
      // Try to get username from various Keycloak fields
      String? username = userInfo['preferred_username'] ?? 
                        userInfo['username'] ?? 
                        userInfo['given_name'] ??
                        userInfo['name'];
      
      if (username != null && username.isNotEmpty) {
        // Clean username for LiveKit (alphanumeric + dash/underscore only)
        username = username.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
        return username.length > 2 ? username : 'user_${username}';
      }
    }
    
    // Fallback to random if no user info
    final rand = Random();
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final suffix = List.generate(8, (_) => chars[rand.nextInt(chars.length)]).join();
    return 'flutter-$suffix';
  }
  
  @override
  Widget build(BuildContext context) {
    final userInfo = _authService.userInfo;
    
    return Scaffold(
      appBar: AppBar(
        title: Text('LiveKit Voice Call'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        elevation: 2,
        actions: [
          // User profile button
          PopupMenuButton<String>(
            icon: CircleAvatar(
              backgroundColor: Colors.blue[700],
              child: Text(
                _authService.displayName.substring(0, 1).toUpperCase(),
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            itemBuilder: (context) => [
              PopupMenuItem(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _authService.displayName,
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      _authService.userEmail,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
                enabled: false,
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, size: 18),
                    SizedBox(width: 8),
                    Text('Sign Out'),
                  ],
                ),
              ),
            ],
            onSelected: (value) {
              if (value == 'logout') {
                _logout();
              }
            },
          ),
        ],
      ),
      body: Container(
        padding: EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // User Welcome Card
            Card(
              elevation: 2,
              color: Colors.blue[50],
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.blue[700],
                      child: Text(
                        _authService.displayName.substring(0, 1).toUpperCase(),
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Welcome, ${_authService.displayName}!',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            _authService.userEmail,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            SizedBox(height: 32),
            
            // Connection Status Card
            Card(
              elevation: 4,
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(
                      isConnected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      size: 48,
                      color: isConnected ? Colors.green : Colors.red,
                    ),
                    SizedBox(height: 10),
                    Text(
                      statusMessage,
                      style: TextStyle(
                        fontSize: 18,
                        color: isConnected ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 10),
                    Text(
                      'Remote Participants: ${remoteParticipants.length}',
                      style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ),
            
            SizedBox(height: 32),
            
            // Connection Controls
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: (isConnected || isConnecting) ? null : connectToRoom,
                    icon: isConnecting 
                        ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(Icons.phone),
                    label: Text(isConnecting ? 'Connecting...' : 'Connect'),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: isConnected ? disconnectFromRoom : null,
                    icon: Icon(Icons.phone_disabled),
                    label: Text('Disconnect'),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            
            SizedBox(height: 20),
            
            // Mute/Unmute Button
            Container(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isConnected ? toggleMute : null,
                icon: Icon(isMuted ? Icons.mic_off : Icons.mic),
                label: Text(isMuted ? 'Unmute Microphone' : 'Mute Microphone'),
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: isMuted ? Colors.orange : Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            
            SizedBox(height: 32),
            
            // Server Configuration Info
            Card(
              color: Colors.grey[50],
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Connection Details:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    SizedBox(height: 8),
                    Text('WebSocket: $websocketUrl'),
                    Text('Token API: $tokenUrl'),
                    Text('Room: $defaultRoomName'),
                    Text('Participant: ${authenticatedParticipantName}'),
                  ],
                ),
              ),
            ),
          ],
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
          'User-Agent': 'Flutter-LiveKit-App/1.0',
        },
        body: json.encode({
          'roomName': defaultRoomName,
          'participantName': authenticatedParticipantName,
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
    setState(() { isConnecting = true; statusMessage = 'Initializing connection...'; });
    try {
      final token = await getToken();
      setState(() { statusMessage = 'Connecting to LiveKit server...'; });
      room = Room(roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true));
      room!.addListener(_onRoomUpdate);
      await room!.connect(websocketUrl, token);
      await room!.localParticipant?.setMicrophoneEnabled(false);
      setState(() { 
        isConnected = true; 
        isConnecting = false; 
        statusMessage = 'Connected to LiveKit room'; 
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Successfully connected to voice room'), backgroundColor: Colors.green, duration: Duration(seconds: 2))
        );
      }
    } catch (error) {
      setState(() { isConnected = false; isConnecting = false; statusMessage = 'Connection failed'; });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to connect: ${error.toString()}'), backgroundColor: Colors.red, duration: Duration(seconds: 4))
        );
      }
    }
  }

  Future<void> disconnectFromRoom() async {
    try {
      setState(() { statusMessage = 'Disconnecting...'; });
      await room?.disconnect();
      room?.removeListener(_onRoomUpdate);
      setState(() { isConnected = false; remoteParticipants.clear(); isMuted = true; statusMessage = 'Disconnected'; });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Disconnected from voice room'), backgroundColor: Colors.grey, duration: Duration(seconds: 2))
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
            SnackBar(content: Text(isMuted ? 'Microphone muted' : 'Microphone unmuted'), duration: Duration(seconds: 1))
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
      setState(() { remoteParticipants = room?.remoteParticipants.values.toList() ?? []; });
    }
  }

  @override
  void dispose() {
    disconnectFromRoom();
    super.dispose();
  }
}