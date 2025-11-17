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
  }

  // Disconnect from room
  Future<void> _disconnectFromRoom() async {
    await _room?.disconnect();
    _roomListener?.dispose();

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
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: _isConnected ? null : _buildAppBar(),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF0a0a0f),
              const Color(0xFF1a1a2e).withOpacity(0.8),
              const Color(0xFF16213e).withOpacity(0.6),
            ],
          ),
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

  // Room view (when connected) - Ultra minimalist floating design
  Widget _buildRoomView() {
    return SafeArea(
      child: Stack(
        children: [
          // Participants grid with floating effect
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

          // Room name floating top center
          Positioned(
            top: 16,
            left: 0,
            right: 0,
            child: _buildRoomNameBadge(),
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

  // Floating room name badge
  Widget _buildRoomNameBadge() {
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.3),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withOpacity(0.1),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.circle,
                  size: 8,
                  color: Colors.green.shade400,
                ),
                const SizedBox(width: 8),
                Text(
                  _currentRoomName ?? 'Room',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '• ${_participants.length}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 12,
                  ),
                ),
              ],
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

  // Participant grid layout with floating effect
  Widget _buildParticipantGrid() {
    final participantCount = _participants.length;

    // Calculate grid dimensions based on participant count
    int columns = 1;
    if (participantCount == 2) {
      columns = 2;
    } else if (participantCount <= 4) {
      columns = 2;
    } else if (participantCount <= 9) {
      columns = 3;
    } else {
      columns = 4;
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 60, 20, 120),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: participantCount == 1 ? 0.7 : 0.9,
      ),
      itemCount: participantCount,
      itemBuilder: (context, index) {
        return _buildParticipantTile(_participants[index]);
      },
    );
  }

  // Floating participant tile
  Widget _buildParticipantTile(Participant participant) {
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

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Video or placeholder
            if (videoTrack != null)
              VideoTrackRenderer(videoTrack)
            else
              Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.4),
                ),
                child: Center(
                  child: Icon(
                    Icons.person_outline,
                    size: 40,
                    color: Colors.white.withOpacity(0.3),
                  ),
                ),
              ),

            // Speaking indicator glow
            if (isSpeaking)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.green.shade400,
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.green.shade400.withOpacity(0.6),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              ),

            // Minimal border overlay
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isLocal
                        ? Colors.blue.withOpacity(0.4)
                        : Colors.white.withOpacity(0.15),
                    width: 1.5,
                  ),
                ),
              ),
            ),

            // Minimal identity label
            Positioned(
              bottom: 10,
              left: 10,
              right: 10,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.1),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isLocal) ...[
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: Colors.blue.shade400,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        if (isSpeaking) ...[
                          Icon(
                            Icons.graphic_eq,
                            color: Colors.green.shade400,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Flexible(
                          child: Text(
                            identity,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
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
