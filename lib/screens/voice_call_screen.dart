import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:livekit_client/livekit_client.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import '../services/keycloak_service.dart';
import 'login_screen.dart';

class VoiceCallScreen extends StatefulWidget {
  final bool startUnmuted;
  const VoiceCallScreen({super.key, this.startUnmuted = false});

  @override
  State<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends State<VoiceCallScreen>
    with TickerProviderStateMixin {
  final AuthService _authService = AuthService();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  Room? room;
  bool isConnected = false;
  bool isMuted = true;
  bool isConnecting = false;
  String statusMessage = '';

  // NEW: June-TTS speaking detection
  bool isJuneSpeaking = false;
  RemoteParticipant? juneParticipant;

  final String websocketUrl = 'wss://livekit.ozzu.world';
  final String tokenUrl = 'https://api.ozzu.world/token';
  final String roomName = 'ozzu-main';
  final String participantName = 'ozzu-app';

  late final AnimationController lottieCtrl;
  bool lottieLoaded = false;

  // NEW: Event listener for room events
  late final EventsListener<RoomEvent> _roomListener;

  @override
  void initState() {
    super.initState();
    isMuted = !widget.startUnmuted;
    lottieCtrl = AnimationController(vsync: this);
    _autoConnect();
  }

  @override
  void dispose() {
    lottieCtrl.dispose();
    _roomListener.dispose();
    disconnectFromRoom();
    super.dispose();
  }

  Future<void> _autoConnect() async {
    await Future.delayed(const Duration(milliseconds: 400));
    await connectToRoom();
  }

  Future<String> getToken() async {
    final accessToken = await _authService.getAccessToken();
    final response = await http
        .post(
          Uri.parse(tokenUrl),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            if (accessToken != null) 'Authorization': 'Bearer $accessToken',
          },
          body: json.encode({'roomName': roomName, 'participantName': participantName}),
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data is Map<String, dynamic> && data['token'] != null) return data['token'];
      throw Exception('Token field not found in response');
    } else {
      throw Exception('HTTP ${"${response.statusCode}"}: ${response.body}');
    }
  }

  Future<void> connectToRoom() async {
    setState(() => isConnecting = true);
    try {
      final micStatus = await Permission.microphone.request();
      debugPrint('🔒 Mic permission: $micStatus');
      final token = await getToken();

      room = Room(roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true));

      // NEW: Set up event listener using correct API
      _roomListener = room!.createListener();
      _setupRoomEventListeners();

      await room!.connect(
        websocketUrl,
        token,
        connectOptions: const ConnectOptions(autoSubscribe: true),
      );

      // Enable mic on connect
      await room!.localParticipant?.setMicrophoneEnabled(true);
      await Future.delayed(const Duration(milliseconds: 120));
      await room!.localParticipant?.setMicrophoneEnabled(true);

      setState(() {
        isConnected = true;
        isConnecting = false;
        isMuted = false;
      });

      _updateLottie();
      _scanForJuneParticipant();

    } catch (e) {
      debugPrint('❌ connect error: $e');
      setState(() {
        isConnected = false;
        isConnecting = false;
        isMuted = true;
      });
      _updateLottie();
    }
  }

  void _setupRoomEventListeners() {
    _roomListener
      ..on<ParticipantConnectedEvent>((event) {
        debugPrint('👋 Participant joined: ${event.participant.identity}');
        _checkIfJuneParticipant(event.participant);
      })
      ..on<ActiveSpeakersChangedEvent>((event) {
        final juneIsSpeaking = event.speakers.any((participant) => 
          participant == juneParticipant);

        if (juneIsSpeaking != isJuneSpeaking) {
          setState(() {
            isJuneSpeaking = juneIsSpeaking;
          });
          _updateLottie();
          debugPrint('🗣️ June speaking: $isJuneSpeaking');
        }
      });
  }

  void _checkIfJuneParticipant(RemoteParticipant participant) {
    final juneIdentities = ['june-tts', 'june_tts', 'June-TTS', 'June_TTS', 'tts', 'june'];

    if (juneIdentities.any((identity) => 
        participant.identity.toLowerCase().contains(identity.toLowerCase()))) {

      debugPrint('🎤 Found June-TTS participant: ${participant.identity}');
      juneParticipant = participant;

      participant.addListener(() {
        final wasSpeaking = isJuneSpeaking;
        final nowSpeaking = participant.isSpeaking;

        if (wasSpeaking != nowSpeaking) {
          setState(() {
            isJuneSpeaking = nowSpeaking;
          });
          _updateLottie();
          debugPrint('🗣️ June speaking state changed: $nowSpeaking');
        }
      });
    }
  }

  void _scanForJuneParticipant() {
    if (room == null) return;

    for (final participant in room!.remoteParticipants.values) {
      _checkIfJuneParticipant(participant);
    }
  }

  Future<void> disconnectFromRoom() async {
    await room?.disconnect();
    setState(() {
      isConnected = false;
      isMuted = true;
      isJuneSpeaking = false;
      juneParticipant = null;
    });
    _updateLottie();
  }

  Future<void> toggleMute() async {
    if (room?.localParticipant != null) {
      await room!.localParticipant!.setMicrophoneEnabled(isMuted);
      setState(() => isMuted = !isMuted);
    }
  }

  void _updateLottie() {
    if (!lottieLoaded) return;
    try {
      if (isConnected && isJuneSpeaking) {
        lottieCtrl..reset()..repeat();
        debugPrint('🎵 Animation visible & playing - June speaking');
      } else {
        lottieCtrl.stop();
        debugPrint('👻 Animation hidden - June silent');
      }
    } catch (e) {
      debugPrint('Lottie error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final safe = media.padding;
    final size = media.size;
    final safeWidth = size.width - safe.left - safe.right;
    final safeHeight = size.height - safe.top - safe.bottom;
    final minSide = math.min(safeWidth, safeHeight);

    final isTablet = media.size.shortestSide >= 600;
    final baseFraction = isTablet ? 0.806 : 0.65;
    final maxClamp = isTablet ? 1066.0 : 606.0;

    final lottieSize = (baseFraction * minSide).clamp(260.0, maxClamp);
    final glowSize = lottieSize + 80.0;

    return GestureDetector(
      onTap: isConnected ? toggleMute : null,
      onLongPress: () async {
        try {
          if (isConnected) {
            await disconnectFromRoom();
          } else {
            await connectToRoom();
          }
        } catch (e) {
          debugPrint('Long press error: $e');
        }
      },
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: Colors.black,
        drawer: _buildDrawer(),
        body: SafeArea(
          child: Stack(
            children: [
              // Centered content
              Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: glowSize,
                      height: glowSize,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [Color(0x3310B5FF), Colors.transparent],
                          stops: [0.0, 1.0],
                        ),
                      ),
                    ),
                    // MODIFIED: Use AnimatedOpacity to control visibility
                    AnimatedOpacity(
                      opacity: (isConnected && isJuneSpeaking) ? 1.0 : 0.0, // NEW: Invisible when not speaking
                      duration: const Duration(milliseconds: 200), // Smooth fade in/out
                      child: SizedBox(
                        width: lottieSize,
                        height: lottieSize,
                        child: Lottie.asset(
                          'assets/lottie/voice_button.json',
                          controller: lottieCtrl,
                          fit: BoxFit.contain,
                          onLoaded: (comp) {
                            try {
                              final duration = comp.duration;
                              lottieCtrl.duration = duration;
                              lottieLoaded = true;
                              _updateLottie();
                              debugPrint('✅ Lottie loaded: ${"${duration.inMilliseconds}ms"}');
                            } catch (e) {
                              debugPrint('❌ Lottie onLoaded error: $e');
                              lottieCtrl.duration = const Duration(seconds: 3);
                              lottieLoaded = true;
                              _updateLottie();
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Menu icon in top left
              Positioned(
                top: 16,
                left: 16,
                child: GestureDetector(
                  onTap: () => _scaffoldKey.currentState?.openDrawer(),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.15)),
                    ),
                    child: const Icon(Icons.menu, color: Colors.white70, size: 24),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFF1A1A1A),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.purple.withOpacity(0.3),
                    Colors.blue.withOpacity(0.3),
                  ],
                ),
              ),
              child: const Row(
                children: [
                  Icon(Icons.settings, color: Colors.white70, size: 28),
                  SizedBox(width: 12),
                  Text(
                    'Menu',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Connection Status
            _buildMenuTile(
              icon: Icons.wifi,
              title: 'Connection',
              subtitle: isConnected
                  ? 'Connected to room'
                  : (isConnecting ? 'Connecting...' : 'Disconnected'),
              statusColor: isConnected
                  ? Colors.greenAccent
                  : (isConnecting ? Colors.orangeAccent : Colors.redAccent),
              onTap: () {
                // Show detailed connection info
                _showConnectionDetails();
              },
            ),

            const Divider(color: Colors.white12, height: 1),

            // Microphone Status
            _buildMenuTile(
              icon: isMuted ? Icons.mic_off : Icons.mic,
              title: 'Microphone',
              subtitle: isMuted ? 'Muted' : 'Active',
              statusColor: isMuted ? Colors.red.shade300 : Colors.blue.shade300,
              onTap: toggleMute,
            ),

            const Divider(color: Colors.white12, height: 1),

            // June Speaking Status
            _buildMenuTile(
              icon: Icons.record_voice_over,
              title: 'June AI',
              subtitle: isJuneSpeaking ? 'Speaking...' : 'Silent',
              statusColor: isJuneSpeaking ? Colors.blue.shade300 : Colors.grey.shade600,
              onTap: null,
            ),

            const Divider(color: Colors.white12, height: 1),

            const Spacer(),

            // Logout button
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _logout,
                  icon: const Icon(Icons.logout),
                  label: const Text('Logout'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.withOpacity(0.2),
                    foregroundColor: Colors.redAccent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.redAccent.withOpacity(0.3)),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color statusColor,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white70),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: Colors.white60,
          fontSize: 14,
        ),
      ),
      trailing: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: statusColor,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: statusColor.withOpacity(0.5),
              blurRadius: 8,
              spreadRadius: 2,
            ),
          ],
        ),
      ),
      onTap: onTap,
    );
  }

  void _showConnectionDetails() {
    final details = '''
Status: ${isConnected ? 'Connected' : (isConnecting ? 'Connecting...' : 'Disconnected')}
Room: $roomName
Server: ${websocketUrl.replaceFirst('wss://', '')}
Participant: $participantName
${room != null ? 'Remote participants: ${room!.remoteParticipants.length}' : ''}
''';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.white70),
            SizedBox(width: 8),
            Text('Connection Details', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Text(
          details,
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    if (isConnected) await disconnectFromRoom();
    await _authService.logout();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }
}