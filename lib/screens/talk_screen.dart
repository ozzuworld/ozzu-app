import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:permission_handler/permission_handler.dart';
import '../services/keycloak_service.dart';

enum TalkView { search, publicRooms }

class TalkScreen extends StatefulWidget {
  final TalkView initialView;
  final String? autoJoinRoom;

  const TalkScreen({
    super.key,
    this.initialView = TalkView.search,
    this.autoJoinRoom,
  });

  @override
  State<TalkScreen> createState() => _TalkScreenState();
}

class _TalkScreenState extends State<TalkScreen> with TickerProviderStateMixin {
  final AuthService _authService = AuthService();
  final TextEditingController _searchController = TextEditingController();

  // LiveKit connection
  Room? _room;
  bool _isConnected = false;
  bool _isConnecting = false;
  bool _isMicEnabled = false;
  bool _isCameraEnabled = false;

  // Room discovery
  List<RoomInfo> _availableRooms = [];
  bool _isLoadingRooms = false;
  String? _currentRoomName;
  bool _showPublicRooms = false; // Collapsible public rooms

  // Participants
  List<Participant> _participants = [];

  // LiveKit server configuration
  final String _livekitUrl = 'wss://livekit.ozzu.world';
  final String _apiUrl = 'https://api.ozzu.world';

  EventsListener<RoomEvent>? _roomListener;

  // Animations
  late AnimationController _controlsAnimationController;
  late AnimationController _roomsAnimationController;
  late AnimationController _physicsAnimationController;

  // Physics-based particle positions
  final Map<String, ParticlePhysics> _particlePhysics = {};

  @override
  void initState() {
    super.initState();
    // Auto-expand public rooms if that's the initial view
    if (widget.initialView == TalkView.publicRooms) {
      _showPublicRooms = true;
      _loadAvailableRooms();
    }
    _controlsAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _roomsAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _physicsAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(days: 365), // Runs forever
    )..addListener(_updatePhysics);

    // Animate public rooms if needed
    if (_showPublicRooms) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _roomsAnimationController.forward();
      });
    }

    // Auto-join room if specified
    if (widget.autoJoinRoom != null && widget.autoJoinRoom!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _joinRoom(widget.autoJoinRoom!);
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _roomListener?.dispose();
    _controlsAnimationController.dispose();
    _roomsAnimationController.dispose();
    _physicsAnimationController.dispose();
    _disconnectFromRoom();
    super.dispose();
  }

  // Load available public rooms
  Future<void> _loadAvailableRooms() async {
    setState(() => _isLoadingRooms = true);

    try {
      final accessToken = await _authService.getAccessToken();
      final response = await http.post(
        Uri.parse('$_apiUrl/rooms/list'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          if (accessToken != null) 'Authorization': 'Bearer $accessToken',
        },
        body: json.encode({}),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map<String, dynamic> && data['rooms'] != null) {
          final rooms = (data['rooms'] as List)
              .map((room) => RoomInfo.fromJson(room))
              .toList();

          setState(() {
            _availableRooms = rooms;
            _isLoadingRooms = false;
          });
        }
      } else {
        debugPrint('Failed to load rooms: ${response.statusCode}');
        setState(() => _isLoadingRooms = false);
      }
    } catch (e) {
      debugPrint('Error loading rooms: $e');
      setState(() => _isLoadingRooms = false);
    }
  }

  // Get token for joining a room
  Future<String> _getToken(String roomName, String participantName) async {
    final accessToken = await _authService.getAccessToken();
    final response = await http.post(
      Uri.parse('$_apiUrl/token'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (accessToken != null) 'Authorization': 'Bearer $accessToken',
      },
      body: json.encode({
        'roomName': roomName,
        'participantName': participantName,
      }),
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data is Map<String, dynamic> && data['token'] != null) {
        return data['token'];
      }
      throw Exception('Token field not found in response');
    } else {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
  }

  // Join a LiveKit room
  Future<void> _joinRoom(String roomName) async {
    setState(() {
      _isConnecting = true;
      _currentRoomName = roomName;
    });

    try {
      // Request permissions
      final micStatus = await Permission.microphone.request();
      final cameraStatus = await Permission.camera.request();

      debugPrint('Microphone permission: $micStatus');
      debugPrint('Camera permission: $cameraStatus');

      // Get token
      final token = await _getToken(roomName, 'user-${DateTime.now().millisecondsSinceEpoch}');

      // Create room
      _room = Room(
        roomOptions: const RoomOptions(
          adaptiveStream: true,
          dynacast: true,
        ),
      );

      // Set up event listeners
      _roomListener?.dispose();
      _roomListener = _room!.createListener();
      _setupRoomEventListeners();

      // Connect to room
      await _room!.connect(
        _livekitUrl,
        token,
        connectOptions: const ConnectOptions(autoSubscribe: true),
      );

      setState(() {
        _isConnected = true;
        _isConnecting = false;
        _updateParticipants();
      });

      _controlsAnimationController.forward();
      debugPrint('Successfully joined room: $roomName');
    } catch (e) {
      debugPrint('Error joining room: $e');
      setState(() {
        _isConnected = false;
        _isConnecting = false;
        _currentRoomName = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to join room: $e'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  // Set up room event listeners
  void _setupRoomEventListeners() {
    if (_roomListener == null) return;

    _roomListener!
      ..on<ParticipantConnectedEvent>((event) {
        debugPrint('Participant joined: ${event.participant.identity}');
        setState(() => _updateParticipants());
      })
      ..on<ParticipantDisconnectedEvent>((event) {
        debugPrint('Participant left: ${event.participant.identity}');
        setState(() => _updateParticipants());
      })
      ..on<TrackPublishedEvent>((event) {
        debugPrint('Track published: ${event.publication.sid}');
        setState(() => _updateParticipants());
      })
      ..on<TrackUnpublishedEvent>((event) {
        debugPrint('Track unpublished: ${event.publication.sid}');
        setState(() => _updateParticipants());
      });
  }

  // Update participants list
  void _updateParticipants() {
    if (_room == null) return;

    _participants = [
      if (_room!.localParticipant != null) _room!.localParticipant!,
      ..._room!.remoteParticipants.values,
    ];

    // Initialize physics for new participants
    _initializeParticlePhysics();

    // Start physics animation if we have participants
    if (_participants.isNotEmpty && !_physicsAnimationController.isAnimating) {
      _physicsAnimationController.repeat();
    }
  }

  // Initialize physics simulation for all particles
  void _initializeParticlePhysics() {
    // Remove physics for participants who left
    _particlePhysics.removeWhere((id, _) =>
      !_participants.any((p) => p.identity == id));

    // Add physics for new participants
    for (int i = 0; i < _participants.length; i++) {
      final participant = _participants[i];
      final id = participant.identity ?? 'unknown-$i';

      if (!_particlePhysics.containsKey(id)) {
        // Calculate ideal orbital position
        final angle = (2 * math.pi * i / _participants.length) - (math.pi / 2);

        _particlePhysics[id] = ParticlePhysics(
          targetAngle: angle,
          currentAngle: angle + (math.Random().nextDouble() - 0.5) * 0.3,
          currentRadius: 0.32 + (math.Random().nextDouble() - 0.5) * 0.05,
          currentDepth: 0.5 + (math.Random().nextDouble() - 0.5) * 0.3, // Random depth 0.35-0.65
          velocityAngle: (math.Random().nextDouble() - 0.5) * 0.02,
          velocityRadius: (math.Random().nextDouble() - 0.5) * 0.01,
          velocityDepth: (math.Random().nextDouble() - 0.5) * 0.005,
        );
      } else {
        // Update target angle for existing participants
        final angle = (2 * math.pi * i / _participants.length) - (math.pi / 2);
        _particlePhysics[id]!.targetAngle = angle;
      }
    }
  }

  // Update physics simulation every frame with 3D depth
  void _updatePhysics() {
    if (_participants.isEmpty) return;

    const dt = 0.016; // ~60fps
    const repulsionStrength = 0.008;
    const springStrength = 0.05;
    const depthSpringStrength = 0.03;
    const damping = 0.92;
    const minDistance = 0.15;

    // Update each particle
    for (int i = 0; i < _participants.length; i++) {
      final participant = _participants[i];
      final id = participant.identity ?? 'unknown-$i';
      final physics = _particlePhysics[id];
      if (physics == null) continue;

      double forceAngle = 0;
      double forceRadius = 0;
      double forceDepth = 0;

      // Spring force toward target orbital position
      final angleDiff = _normalizeAngle(physics.targetAngle - physics.currentAngle);
      forceAngle += angleDiff * springStrength;

      final radiusDiff = 0.32 - physics.currentRadius;
      forceRadius += radiusDiff * springStrength;

      // Spring force toward mid-depth (0.5)
      final depthDiff = 0.5 - physics.currentDepth;
      forceDepth += depthDiff * depthSpringStrength;

      // Repulsion from other participants (3D distance)
      for (int j = 0; j < _participants.length; j++) {
        if (i == j) continue;

        final otherParticipant = _participants[j];
        final otherId = otherParticipant.identity ?? 'unknown-$j';
        final otherPhysics = _particlePhysics[otherId];
        if (otherPhysics == null) continue;

        // Calculate 3D distance between particles
        final dx = physics.currentRadius * math.cos(physics.currentAngle) -
                   otherPhysics.currentRadius * math.cos(otherPhysics.currentAngle);
        final dy = physics.currentRadius * math.sin(physics.currentAngle) -
                   otherPhysics.currentRadius * math.sin(otherPhysics.currentAngle);
        final dz = (physics.currentDepth - otherPhysics.currentDepth) * 0.3; // Scale depth
        final distance = math.sqrt(dx * dx + dy * dy + dz * dz);

        if (distance < minDistance && distance > 0.001) {
          // Apply repulsion force in 3D
          final repulsion = repulsionStrength * (minDistance - distance) / distance;
          final repulsionAngle = math.atan2(dy, dx);

          forceAngle += repulsion * math.sin(repulsionAngle - physics.currentAngle);
          forceRadius += repulsion * math.cos(repulsionAngle - physics.currentAngle);
          forceDepth += repulsion * dz;
        }
      }

      // Add gentle random drift for organic feel (3D)
      forceAngle += (math.Random().nextDouble() - 0.5) * 0.001;
      forceRadius += (math.Random().nextDouble() - 0.5) * 0.0005;
      forceDepth += (math.Random().nextDouble() - 0.5) * 0.0003;

      // Update velocities
      physics.velocityAngle += forceAngle * dt;
      physics.velocityRadius += forceRadius * dt;
      physics.velocityDepth += forceDepth * dt;

      // Apply damping
      physics.velocityAngle *= damping;
      physics.velocityRadius *= damping;
      physics.velocityDepth *= damping;

      // Update positions
      physics.currentAngle += physics.velocityAngle;
      physics.currentRadius += physics.velocityRadius;
      physics.currentDepth += physics.velocityDepth;

      // Clamp to reasonable bounds
      physics.currentRadius = physics.currentRadius.clamp(0.25, 0.4);
      physics.currentDepth = physics.currentDepth.clamp(0.2, 0.8); // Keep depth varied

      // Normalize angle
      physics.currentAngle = _normalizeAngle(physics.currentAngle);
    }

    // Trigger rebuild
    if (mounted) {
      setState(() {});
    }
  }

  // Normalize angle to -π to π range
  double _normalizeAngle(double angle) {
    while (angle > math.pi) angle -= 2 * math.pi;
    while (angle < -math.pi) angle += 2 * math.pi;
    return angle;
  }

  // Disconnect from room
  Future<void> _disconnectFromRoom() async {
    await _room?.disconnect();
    _roomListener?.dispose();

    // Stop physics animation
    _physicsAnimationController.stop();
    _particlePhysics.clear();

    setState(() {
      _room = null;
      _isConnected = false;
      _currentRoomName = null;
      _participants = [];
      _isMicEnabled = false;
      _isCameraEnabled = false;
    });

    _controlsAnimationController.reverse();
  }

  // Toggle microphone
  Future<void> _toggleMicrophone() async {
    if (_room?.localParticipant == null) return;

    try {
      await _room!.localParticipant!.setMicrophoneEnabled(!_isMicEnabled);
      setState(() => _isMicEnabled = !_isMicEnabled);
    } catch (e) {
      debugPrint('Error toggling microphone: $e');
    }
  }

  // Toggle camera
  Future<void> _toggleCamera() async {
    if (_room?.localParticipant == null) return;

    try {
      await _room!.localParticipant!.setCameraEnabled(!_isCameraEnabled);
      setState(() => _isCameraEnabled = !_isCameraEnabled);
    } catch (e) {
      debugPrint('Error toggling camera: $e');
    }
  }

  // Toggle public rooms
  void _togglePublicRooms() {
    setState(() {
      _showPublicRooms = !_showPublicRooms;
    });

    if (_showPublicRooms) {
      _roomsAnimationController.forward();
      _loadAvailableRooms();
    } else {
      _roomsAnimationController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000), // Pure black
      extendBodyBehindAppBar: true,
      appBar: _isConnected ? null : _buildAppBar(),
      body: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF000000), // Pure black, no gradient
        ),
        child: _isConnected ? _buildRoomView() : _buildRoomSelectionView(),
      ),
    );
  }

  // App bar
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.arrow_back, color: Colors.white, size: 18),
        ),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(
        'Talk',
        style: TextStyle(
          color: Colors.white.withOpacity(0.95),
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
      centerTitle: false,
    );
  }

  // Room selection view
  Widget _buildRoomSelectionView() {
    return SafeArea(
      child: Column(
        children: [
          const SizedBox(height: 24),

          // Minimalist glass search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withOpacity(0.08),
                        Colors.white.withOpacity(0.02),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.15),
                      width: 1,
                    ),
                  ),
                  child: TextField(
                    controller: _searchController,
                    style: TextStyle(color: Colors.white.withOpacity(0.95), fontSize: 15),
                    decoration: InputDecoration(
                      hintText: 'Enter room name...',
                      hintStyle: TextStyle(
                        color: Colors.white.withOpacity(0.3),
                        fontSize: 15,
                      ),
                      prefixIcon: Padding(
                        padding: const EdgeInsets.all(14.0),
                        child: Icon(Icons.search, color: Colors.white.withOpacity(0.4), size: 22),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(Icons.arrow_circle_right, color: Colors.white.withOpacity(0.5), size: 28),
                        onPressed: () {
                          if (_searchController.text.isNotEmpty) {
                            _joinRoom(_searchController.text.trim());
                          }
                        },
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    ),
                    onSubmitted: (value) {
                      if (value.isNotEmpty) {
                        _joinRoom(value.trim());
                      }
                    },
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 32),

          // Public Rooms collapsible button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _togglePublicRooms,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withOpacity(0.08),
                            Colors.white.withOpacity(0.02),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.15),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.blue.withOpacity(0.3),
                                  Colors.purple.withOpacity(0.3),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.groups_rounded,
                              color: Colors.white.withOpacity(0.9),
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              'Public Rooms',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                          if (_availableRooms.isNotEmpty && !_isLoadingRooms)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${_availableRooms.length}',
                                style: TextStyle(
                                  color: Colors.blue.shade300,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          const SizedBox(width: 8),
                          AnimatedRotation(
                            turns: _showPublicRooms ? 0.5 : 0,
                            duration: const Duration(milliseconds: 300),
                            child: Icon(
                              Icons.expand_more,
                              color: Colors.white.withOpacity(0.5),
                              size: 24,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Expandable rooms list
          Expanded(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeInOut,
              child: _showPublicRooms
                  ? _isLoadingRooms
                      ? _buildLoadingState()
                      : _availableRooms.isEmpty
                          ? _buildEmptyState()
                          : _buildRoomsList()
                  : const SizedBox.shrink(),
            ),
          ),

          // Connecting indicator
          if (_isConnecting) _buildConnectingIndicator(),
        ],
      ),
    );
  }

  // Loading state
  Widget _buildLoadingState() {
    return Center(
      child: CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation<Color>(Colors.white.withOpacity(0.5)),
        strokeWidth: 2,
      ),
    );
  }

  // Empty state
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.meeting_room_outlined,
            size: 48,
            color: Colors.white.withOpacity(0.2),
          ),
          const SizedBox(height: 16),
          Text(
            'No rooms available',
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  // Rooms list
  Widget _buildRoomsList() {
    return FadeTransition(
      opacity: _roomsAnimationController,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        itemCount: _availableRooms.length,
        itemBuilder: (context, index) {
          final room = _availableRooms[index];
          return _buildRoomCard(room);
        },
      ),
    );
  }

  // Connecting indicator
  Widget _buildConnectingIndicator() {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            border: Border(
              top: BorderSide(
                color: Colors.white.withOpacity(0.1),
                width: 1,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white.withOpacity(0.7)),
                  strokeWidth: 2,
                ),
              ),
              const SizedBox(width: 16),
              Text(
                'Joining room...',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Minimalist room card
  Widget _buildRoomCard(RoomInfo room) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _joinRoom(room.name),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withOpacity(0.06),
                      Colors.white.withOpacity(0.02),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.1),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.meeting_room_outlined,
                      color: Colors.white.withOpacity(0.6),
                      size: 20,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        room.name,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.person_outline,
                            size: 14,
                            color: Colors.white.withOpacity(0.6),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${room.numParticipants}',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Room view (when connected) - Gaming-style radial network
  Widget _buildRoomView() {
    return SafeArea(
      child: Stack(
        children: [
          // Radial participant network with floating effect
          Positioned.fill(
            child: _participants.isEmpty
                ? _buildWaitingState()
                : _buildParticipantGrid(),
          ),

          // Minimalist floating controls at bottom
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: _buildFloatingControls(),
          ),

          // Minimalist back button top left
          Positioned(
            top: 16,
            left: 16,
            child: _buildBackButton(),
          ),
        ],
      ),
    );
  }

  // Minimalist back button
  Widget _buildBackButton() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _disconnectFromRoom,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withOpacity(0.1),
                  width: 1,
                ),
              ),
              child: Icon(
                Icons.arrow_back,
                color: Colors.white.withOpacity(0.8),
                size: 20,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Waiting state
  Widget _buildWaitingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white.withOpacity(0.5)),
              strokeWidth: 2,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Waiting for participants...',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  // Gaming-style radial network layout - participants orbit around room center
  Widget _buildParticipantGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final centerX = constraints.maxWidth / 2;
        final centerY = constraints.maxHeight / 2;
        final participantCount = _participants.length;

        // Size of participant hexagons (40% bigger than original 100px)
        const participantSize = 140.0;

        // Radius for participant orbit - scales with screen size
        final baseRadius = math.min(constraints.maxWidth, constraints.maxHeight) * 0.32;

        // Sort participant indices by depth (far to near) for proper 3D layering
        final sortedIndices = List.generate(participantCount, (i) => i);
        sortedIndices.sort((a, b) {
          final idA = _participants[a].identity ?? 'unknown-$a';
          final idB = _participants[b].identity ?? 'unknown-$b';
          final depthA = _particlePhysics[idA]?.currentDepth ?? 0.5;
          final depthB = _particlePhysics[idB]?.currentDepth ?? 0.5;
          return depthA.compareTo(depthB); // Far nodes first (behind)
        });

        return Stack(
          children: [
            // Participant nodes sorted by depth (far to near)
            for (final i in sortedIndices)
              _buildFloatingParticipant(
                participant: _participants[i],
                index: i,
                centerX: centerX,
                centerY: centerY,
                screenSize: math.min(constraints.maxWidth, constraints.maxHeight),
                size: participantSize,
              ),
          ],
        );
      },
    );
  }


  // Floating participant with 3D perspective transform
  Widget _buildFloatingParticipant({
    required Participant participant,
    required int index,
    required double centerX,
    required double centerY,
    required double screenSize,
    required double size,
  }) {
    final id = participant.identity ?? 'unknown-$index';
    final physics = _particlePhysics[id];

    // If physics not initialized yet, use default position
    final angle = physics?.currentAngle ?? ((2 * math.pi * index / _participants.length) - (math.pi / 2));
    final radius = (physics?.currentRadius ?? 0.32) * screenSize;
    final depth = physics?.currentDepth ?? 0.5;

    final x = centerX + radius * math.cos(angle) - (size / 2);
    final y = centerY + radius * math.sin(angle) - (size / 2);

    // Calculate position relative to center for billboard rotation
    final relX = x + (size / 2) - centerX;
    final relY = y + (size / 2) - centerY;

    // DRAMATIC depth-based scale (closer = MUCH larger)
    final depthScale = 0.6 + (depth * 0.8); // Range: 0.6 to 1.4 (dramatic!)

    // Depth-based opacity (far = dimmer, creates atmospheric depth)
    final depthOpacity = 0.7 + (depth * 0.3); // Range: 0.7 to 1.0

    // Depth-based blur (far = blurrier, simulates depth of field)
    final depthBlur = (1.0 - depth) * 3.0; // Range: 0 to 3.0 (close = sharp, far = blurred)

    // Billboard rotation based on position (always facing viewer)
    final rotateY = (relX / screenSize) * 0.2; // Max ±0.2 radians
    final rotateX = -(relY / screenSize) * 0.2;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 16), // Smooth 60fps interpolation
      curve: Curves.linear,
      left: x,
      top: y,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: Duration(milliseconds: 400 + (index * 100)),
        curve: Curves.elasticOut,
        builder: (context, entranceValue, child) {
          return Transform(
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.004) // STRONGER perspective for dramatic depth!
              ..rotateX(rotateX * entranceValue)
              ..rotateY(rotateY * entranceValue)
              ..scale(depthScale * entranceValue),
            alignment: Alignment.center,
            child: Opacity(
              opacity: entranceValue * depthOpacity, // Depth-aware opacity
              child: depthBlur > 0.5
                  ? ImageFiltered(
                      imageFilter: ImageFilter.blur(
                        sigmaX: depthBlur,
                        sigmaY: depthBlur,
                      ),
                      child: child,
                    )
                  : child,
            ),
          );
        },
        child: _buildSmallParticipantSquare(participant, size, depth),
      ),
    );
  }

  // Gaming-style hexagon participant tile with 3D depth
  Widget _buildSmallParticipantSquare(Participant participant, double size, double depth) {
    final isLocal = participant == _room?.localParticipant;
    final identity = participant.identity ?? 'Unknown';
    final isSpeaking = participant.isSpeaking;

    // Find video track
    VideoTrack? videoTrack;
    for (final pub in participant.videoTrackPublications) {
      if (pub.subscribed && pub.track != null) {
        videoTrack = pub.track as VideoTrack;
        break;
      }
    }

    // DRAMATIC depth-based shadow intensity (closer = MUCH stronger shadow)
    final shadowOpacity = 0.15 + (depth * 0.6); // Range: 0.15 to 0.75
    final shadowBlur = 10.0 + (depth * 40.0); // Range: 10 to 50
    final shadowSpread = depth * 8.0; // Range: 0 to 8
    final shadowOffset = depth * 12.0; // Range: 0 to 12

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        boxShadow: [
          // Main depth shadow (creates 3D floating effect)
          BoxShadow(
            color: Colors.black.withOpacity(shadowOpacity),
            blurRadius: shadowBlur,
            spreadRadius: shadowSpread,
            offset: Offset(0, shadowOffset),
          ),
          // Ambient shadow (softer, larger)
          BoxShadow(
            color: Colors.black.withOpacity(shadowOpacity * 0.4),
            blurRadius: shadowBlur * 1.5,
            spreadRadius: shadowSpread * 0.5,
            offset: Offset(0, shadowOffset * 0.5),
          ),
          // Colored glow shadow (depth-aware)
          BoxShadow(
            color: isLocal
                ? Colors.blue.withOpacity(0.5 * depth)
                : isSpeaking
                    ? Colors.green.withOpacity(0.6 * depth)
                    : Colors.white.withOpacity(0.25 * depth),
            blurRadius: isSpeaking ? 35 : 25,
            spreadRadius: isSpeaking ? 4 : 2,
          ),
        ],
      ),
      child: ClipPath(
        clipper: HexagonClipper(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Video or placeholder fitted to hexagon
            if (videoTrack != null)
              FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: size,
                  height: size,
                  child: VideoTrackRenderer(videoTrack),
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF000000),
                  gradient: LinearGradient(
                    colors: [
                      Colors.grey.shade900,
                      Colors.black,
                    ],
                  ),
                ),
                child: Center(
                  child: Icon(
                    Icons.person_outline,
                    size: 45,
                    color: Colors.white.withOpacity(0.3),
                  ),
                ),
              ),

            // Hexagon border glow using CustomPaint
            CustomPaint(
              painter: HexagonBorderPainter(
                borderColor: isLocal
                    ? Colors.blue.withOpacity(0.6)
                    : isSpeaking
                        ? Colors.green.withOpacity(0.8)
                        : Colors.white.withOpacity(0.2),
                borderWidth: isSpeaking ? 3 : 2,
              ),
            ),

            // Name label overlay (bottom)
            Positioned(
              bottom: 8,
              left: 0,
              right: 0,
              child: Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isLocal)
                            Container(
                              width: 4,
                              height: 4,
                              margin: const EdgeInsets.only(right: 4),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade400,
                                shape: BoxShape.circle,
                              ),
                            ),
                          if (isSpeaking)
                            Icon(
                              Icons.graphic_eq,
                              color: Colors.green.shade400,
                              size: 11,
                            ),
                          if (isSpeaking) const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              identity.length > 10 ? '${identity.substring(0, 10)}...' : identity,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.3,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
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


  // Ultra minimalist floating controls
  Widget _buildFloatingControls() {
    return FadeTransition(
      opacity: _controlsAnimationController,
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: Colors.white.withOpacity(0.15),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Microphone
                  _buildMinimalControlButton(
                    icon: _isMicEnabled ? Icons.mic : Icons.mic_off,
                    isActive: _isMicEnabled,
                    activeColor: Colors.blue,
                    onPressed: _toggleMicrophone,
                  ),

                  const SizedBox(width: 12),

                  // Camera
                  _buildMinimalControlButton(
                    icon: _isCameraEnabled ? Icons.videocam : Icons.videocam_off,
                    isActive: _isCameraEnabled,
                    activeColor: Colors.green,
                    onPressed: _toggleCamera,
                  ),

                  const SizedBox(width: 12),

                  // Leave (destructive)
                  _buildMinimalControlButton(
                    icon: Icons.call_end,
                    isActive: true,
                    activeColor: Colors.red,
                    isDestructive: true,
                    onPressed: _disconnectFromRoom,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Minimal control button - medium sized icons
  Widget _buildMinimalControlButton({
    required IconData icon,
    required bool isActive,
    required Color activeColor,
    bool isDestructive = false,
    required VoidCallback onPressed,
  }) {
    final displayColor = isDestructive
        ? Colors.red
        : isActive
            ? activeColor
            : Colors.white;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: (isActive || isDestructive)
                ? displayColor.withOpacity(0.15)
                : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: displayColor.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Icon(
            icon,
            color: displayColor.withOpacity(0.9),
            size: 24, // Medium icon size
          ),
        ),
      ),
    );
  }
}

// Hexagon clipper for gaming-style tiles
class HexagonClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    final width = size.width;
    final height = size.height;

    // Create a regular hexagon (flat top)
    path.moveTo(width * 0.25, 0); // Top left
    path.lineTo(width * 0.75, 0); // Top right
    path.lineTo(width, height * 0.5); // Right
    path.lineTo(width * 0.75, height); // Bottom right
    path.lineTo(width * 0.25, height); // Bottom left
    path.lineTo(0, height * 0.5); // Left
    path.close();

    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

// Hexagon border painter
class HexagonBorderPainter extends CustomPainter {
  final Color borderColor;
  final double borderWidth;

  HexagonBorderPainter({
    required this.borderColor,
    required this.borderWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = borderColor
      ..strokeWidth = borderWidth
      ..style = PaintingStyle.stroke;

    final width = size.width;
    final height = size.height;

    final path = Path();
    path.moveTo(width * 0.25, 0);
    path.lineTo(width * 0.75, 0);
    path.lineTo(width, height * 0.5);
    path.lineTo(width * 0.75, height);
    path.lineTo(width * 0.25, height);
    path.lineTo(0, height * 0.5);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant HexagonBorderPainter oldDelegate) {
    return oldDelegate.borderColor != borderColor ||
        oldDelegate.borderWidth != borderWidth;
  }
}

// Particle physics data class with 3D depth
class ParticlePhysics {
  double targetAngle;      // Target orbital angle
  double currentAngle;     // Current angle position
  double currentRadius;    // Current radius (normalized 0-1)
  double currentDepth;     // Z-depth (0.0 = far, 1.0 = close)
  double velocityAngle;    // Angular velocity
  double velocityRadius;   // Radial velocity
  double velocityDepth;    // Z-axis velocity

  ParticlePhysics({
    required this.targetAngle,
    required this.currentAngle,
    required this.currentRadius,
    required this.currentDepth,
    required this.velocityAngle,
    required this.velocityRadius,
    required this.velocityDepth,
  });
}

// Room info model
class RoomInfo {
  final String sid;
  final String name;
  final int numParticipants;
  final int maxParticipants;
  final int creationTime;
  final String metadata;

  RoomInfo({
    required this.sid,
    required this.name,
    required this.numParticipants,
    required this.maxParticipants,
    required this.creationTime,
    required this.metadata,
  });

  factory RoomInfo.fromJson(Map<String, dynamic> json) {
    return RoomInfo(
      sid: json['sid'] ?? '',
      name: json['name'] ?? '',
      numParticipants: json['num_participants'] ?? 0,
      maxParticipants: json['max_participants'] ?? 0,
      creationTime: json['creation_time'] ?? 0,
      metadata: json['metadata'] ?? '',
    );
  }
}
