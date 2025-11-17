import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:livekit_client/livekit_client.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import '../services/keycloak_service.dart';
import 'login_screen.dart';
import 'main_navigation_screen.dart';
import 'music_browse_screen.dart';
import 'talk_screen.dart';

class VoiceCallScreen extends StatefulWidget {
  final bool startUnmuted;
  const VoiceCallScreen({super.key, this.startUnmuted = false});

  @override
  State<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends State<VoiceCallScreen>
    with TickerProviderStateMixin {
  final AuthService _authService = AuthService();
  bool _showMenu = false;
  bool _showMediaMenu = false;
  bool _showTalkMenu = false;
  bool _showTalkSearchMenu = false;
  bool _showTalkPublicRoomsMenu = false;
  final TextEditingController _talkSearchController = TextEditingController();

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
  EventsListener<RoomEvent>? _roomListener;

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
    _roomListener?.dispose();
    _talkSearchController.dispose();
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
      // Dispose old listener if exists
      _roomListener?.dispose();
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
    if (_roomListener == null) return;

    _roomListener!
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
                      opacity: (isConnected && isJuneSpeaking) ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
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

              // Minimalist menu overlay
              if (_showMenu)
                GestureDetector(
                  onTap: () => setState(() => _showMenu = false),
                  child: Container(
                    color: Colors.black.withOpacity(0.3),
                  ),
                ),

              // Compact glass menu
              AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                top: 16,
                left: _showMenu ? 16 : -250,
                child: _buildGlassMenu(),
              ),

              // Menu toggle button
              Positioned(
                top: 16,
                left: 16,
                child: GestureDetector(
                  onTap: () => setState(() => _showMenu = !_showMenu),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withOpacity(0.2),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Icon(
                      _showMenu ? Icons.close : Icons.menu,
                      color: Colors.white.withOpacity(0.9),
                      size: 22,
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

  Widget _buildGlassMenu() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: 220,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
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
            mainAxisSize: MainAxisSize.min,
            children: _showTalkSearchMenu
                ? _buildTalkSearchMenuItems()
                : _showTalkPublicRoomsMenu
                    ? _buildTalkPublicRoomsMenuItems()
                    : _showTalkMenu
                        ? _buildTalkMenuItems()
                        : _showMediaMenu
                            ? _buildMediaMenuItems()
                            : _buildMainMenuItems(),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildMainMenuItems() {
    return [
      // Talk (expandable)
      _buildGlassMenuItem(
        icon: Icons.groups,
        label: 'Talk',
        statusColor: Colors.blueAccent,
        onTap: () {
          setState(() => _showTalkMenu = true);
        },
      ),

      Divider(color: Colors.white.withOpacity(0.1), height: 1),

      // Media
      _buildGlassMenuItem(
        icon: Icons.movie,
        label: 'Media',
        statusColor: Colors.blueAccent,
        onTap: () {
          setState(() => _showMediaMenu = true);
        },
      ),

      Divider(color: Colors.white.withOpacity(0.1), height: 1),

      // Logout
      _buildGlassMenuItem(
        icon: Icons.logout,
        label: 'Logout',
        statusColor: Colors.redAccent,
        onTap: () {
          setState(() => _showMenu = false);
          _logout();
        },
      ),
    ];
  }

  List<Widget> _buildTalkMenuItems() {
    return [
      // Back button
      _buildGlassMenuItem(
        icon: Icons.arrow_back,
        label: 'Back',
        statusColor: Colors.white.withOpacity(0.5),
        onTap: () {
          setState(() => _showTalkMenu = false);
        },
      ),

      Divider(color: Colors.white.withOpacity(0.1), height: 1),

      // Search Room
      _buildGlassMenuItem(
        icon: Icons.search,
        label: 'Search Room',
        statusColor: Colors.blueAccent,
        onTap: () {
          setState(() => _showTalkSearchMenu = true);
        },
      ),

      Divider(color: Colors.white.withOpacity(0.1), height: 1),

      // Public Rooms
      _buildGlassMenuItem(
        icon: Icons.public,
        label: 'Public Rooms',
        statusColor: Colors.greenAccent,
        onTap: () {
          setState(() => _showTalkPublicRoomsMenu = true);
        },
      ),
    ];
  }

  List<Widget> _buildTalkSearchMenuItems() {
    return [
      // Back button
      _buildGlassMenuItem(
        icon: Icons.arrow_back,
        label: 'Back',
        statusColor: Colors.white.withOpacity(0.5),
        onTap: () {
          setState(() {
            _showTalkSearchMenu = false;
            _talkSearchController.clear();
          });
        },
      ),

      Divider(color: Colors.white.withOpacity(0.1), height: 1),

      // Search input
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withOpacity(0.15),
                  width: 1,
                ),
              ),
              child: TextField(
                controller: _talkSearchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Enter room name...',
                  hintStyle: TextStyle(
                    color: Colors.white.withOpacity(0.3),
                    fontSize: 15,
                  ),
                  prefixIcon: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Icon(Icons.meeting_room, color: Colors.white.withOpacity(0.5), size: 20),
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(Icons.arrow_circle_right, color: Colors.blue.withOpacity(0.7), size: 26),
                    onPressed: () {
                      if (_talkSearchController.text.isNotEmpty) {
                        _joinLivekitRoom(_talkSearchController.text.trim());
                      }
                    },
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                onSubmitted: (value) {
                  if (value.isNotEmpty) {
                    _joinLivekitRoom(value.trim());
                  }
                },
              ),
            ),
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildTalkPublicRoomsMenuItems() {
    // TODO: Load and display public rooms here
    return [
      // Back button
      _buildGlassMenuItem(
        icon: Icons.arrow_back,
        label: 'Back',
        statusColor: Colors.white.withOpacity(0.5),
        onTap: () {
          setState(() => _showTalkPublicRoomsMenu = false);
        },
      ),

      Divider(color: Colors.white.withOpacity(0.1), height: 1),

      // Placeholder for rooms list
      Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: Text(
            'Loading public rooms...',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 14,
            ),
          ),
        ),
      ),
    ];
  }

  // Join LiveKit room and navigate to TalkScreen
  void _joinLivekitRoom(String roomName) {
    setState(() {
      _showMenu = false;
      _showTalkMenu = false;
      _showTalkSearchMenu = false;
      _showTalkPublicRoomsMenu = false;
      _talkSearchController.clear();
    });

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TalkScreen(
          initialView: TalkView.search,
          autoJoinRoom: roomName,
        ),
      ),
    );
  }

  List<Widget> _buildMediaMenuItems() {
    return [
      // Back button
      _buildGlassMenuItem(
        icon: Icons.arrow_back,
        label: 'Back',
        statusColor: Colors.white.withOpacity(0.5),
        onTap: () {
          setState(() => _showMediaMenu = false);
        },
      ),

      Divider(color: Colors.white.withOpacity(0.1), height: 1),

      // TV
      _buildGlassMenuItem(
        icon: Icons.tv,
        label: 'TV',
        statusColor: Colors.blueAccent,
        onTap: () {
          setState(() {
            _showMenu = false;
            _showMediaMenu = false;
          });
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const MainNavigationScreen(initialTab: 0),
            ),
          );
        },
      ),

      Divider(color: Colors.white.withOpacity(0.1), height: 1),

      // Music
      _buildGlassMenuItem(
        icon: Icons.music_note,
        label: 'Music',
        statusColor: Colors.greenAccent,
        onTap: () {
          setState(() {
            _showMenu = false;
            _showMediaMenu = false;
          });
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => Scaffold(
                backgroundColor: Colors.black,
                appBar: AppBar(
                  backgroundColor: Colors.black,
                  elevation: 0,
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  title: const Text(
                    'Music',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                body: const MusicBrowseScreen(),
              ),
            ),
          );
        },
      ),
    ];
  }

  Widget _buildGlassMenuItem({
    required IconData icon,
    required String label,
    required Color statusColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: Colors.white.withOpacity(0.9), size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.95),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: statusColor.withOpacity(0.6),
                      blurRadius: 6,
                      spreadRadius: 1,
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

  void _showConnectionDetails() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: AlertDialog(
            backgroundColor: Colors.black.withOpacity(0.7),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(color: Colors.white.withOpacity(0.2), width: 1),
            ),
            title: Row(
              children: [
                Icon(Icons.wifi, color: Colors.white.withOpacity(0.9)),
                const SizedBox(width: 12),
                const Text(
                  'Connection',
                  style: TextStyle(color: Colors.white, fontSize: 20),
                ),
              ],
            ),
            content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Connection info
                _buildDetailRow(
                  icon: Icons.cloud,
                  label: 'Status',
                  value: isConnected
                      ? 'Connected'
                      : (isConnecting ? 'Connecting...' : 'Disconnected'),
                  color: isConnected
                      ? Colors.greenAccent
                      : (isConnecting ? Colors.orangeAccent : Colors.redAccent),
                ),
                const SizedBox(height: 12),
                _buildDetailRow(
                  icon: Icons.room,
                  label: 'Room',
                  value: roomName,
                  color: Colors.white60,
                ),
                const SizedBox(height: 12),
                _buildDetailRow(
                  icon: Icons.dns,
                  label: 'Server',
                  value: websocketUrl.replaceFirst('wss://', ''),
                  color: Colors.white60,
                ),
                const SizedBox(height: 12),
                _buildDetailRow(
                  icon: Icons.person,
                  label: 'Participant',
                  value: participantName,
                  color: Colors.white60,
                ),
                if (room != null) ...[
                  const SizedBox(height: 12),
                  _buildDetailRow(
                    icon: Icons.people,
                    label: 'Remote participants',
                    value: '${room!.remoteParticipants.length}',
                    color: Colors.white60,
                  ),
                ],

                const Divider(color: Colors.white24, height: 32),

                // Microphone control
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    isMuted ? Icons.mic_off : Icons.mic,
                    color: isMuted ? Colors.red.shade300 : Colors.blue.shade300,
                  ),
                  title: const Text(
                    'Microphone',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    isMuted ? 'Muted' : 'Active',
                    style: const TextStyle(color: Colors.white60),
                  ),
                  trailing: Switch(
                    value: !isMuted,
                    onChanged: (value) async {
                      await toggleMute();
                      setDialogState(() {}); // Update dialog state
                      setState(() {}); // Update main screen state
                    },
                    activeColor: Colors.blue.shade300,
                  ),
                ),

                const Divider(color: Colors.white24, height: 24),

                // June AI speaking status
                _buildDetailRow(
                  icon: Icons.record_voice_over,
                  label: 'June AI',
                  value: isJuneSpeaking ? 'Speaking...' : 'Silent',
                  color: isJuneSpeaking ? Colors.blue.shade300 : Colors.grey.shade600,
                ),
              ],
            ),
          ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.blueAccent,
                ),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
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