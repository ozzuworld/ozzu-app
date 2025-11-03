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
      throw Exception('HTTP ${"${response.statusCode}"}: ${"${response.body}"}');
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
        debugPrint('👋 Participant joined: ${"${event.participant.identity}"}');
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

      debugPrint('🎤 Found June-TTS participant: ${"${participant.identity}"}');
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
        backgroundColor: Colors.black,
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

              // Corner icons  
              Positioned(
                top: 16,
                right: 16,
                child: GestureDetector(
                  onTap: _logout,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: const Icon(Icons.logout, color: Colors.white38, size: 18),
                  ),
                ),
              ),

              Positioned(
                right: 20,
                bottom: 28,
                child: Row(
                  children: [
                    _StatusDot(
                      tooltip: isConnected ? 'Connected' : (isConnecting ? 'Connecting...' : 'Disconnected'),
                      color: isConnected ? Colors.greenAccent : (isConnecting ? Colors.orangeAccent : Colors.redAccent),
                      icon: Icons.wifi,
                    ),
                    const SizedBox(width: 10),
                    _StatusDot(
                      tooltip: isMuted ? 'Mic off' : 'Mic on',
                      color: isMuted ? Colors.red.shade300 : Colors.blue.shade300,
                      icon: isMuted ? Icons.mic_off : Icons.mic,
                    ),
                    const SizedBox(width: 10),
                    // NEW: June speaking indicator
                    _StatusDot(
                      tooltip: isJuneSpeaking ? 'June is speaking' : 'June is silent',
                      color: isJuneSpeaking ? Colors.blue.shade300 : Colors.grey.shade600,
                      icon: Icons.record_voice_over,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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

class _StatusDot extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String tooltip;
  const _StatusDot({required this.color, required this.icon, required this.tooltip});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(icon, color: Colors.white60, size: 18),
            Positioned(
              right: 8,
              top: 8,
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}