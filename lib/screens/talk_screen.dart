import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:permission_handler/permission_handler.dart';
import '../services/keycloak_service.dart';

class TalkScreen extends StatefulWidget {
  const TalkScreen({super.key});

  @override
  State<TalkScreen> createState() => _TalkScreenState();
}

class _TalkScreenState extends State<TalkScreen> with SingleTickerProviderStateMixin {
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

  // Participants
  List<Participant> _participants = [];

  // LiveKit server configuration
  final String _livekitUrl = 'wss://livekit.ozzu.world';
  final String _apiUrl = 'https://api.ozzu.world';

  EventsListener<RoomEvent>? _roomListener;

  // Animation
  late AnimationController _controlsAnimationController;

  @override
  void initState() {
    super.initState();
    _loadAvailableRooms();
    _controlsAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _roomListener?.dispose();
    _controlsAnimationController.dispose();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF1a1a2e),
              const Color(0xFF16213e),
              const Color(0xFF0f3460).withOpacity(0.9),
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
            color: Colors.white.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
        ),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(
        _isConnected ? (_currentRoomName ?? 'Talk') : 'Talk',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
      centerTitle: false,
      actions: [
        if (_isConnected)
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.2),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.red.withOpacity(0.5), width: 1),
                ),
                child: const Icon(Icons.call_end, color: Colors.red, size: 20),
              ),
              onPressed: _disconnectFromRoom,
            ),
          ),
      ],
    );
  }

  // Room selection view
  Widget _buildRoomSelectionView() {
    return SafeArea(
      child: Column(
        children: [
          const SizedBox(height: 16),

          // Search bar with enhanced glass effect
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withOpacity(0.15),
                        Colors.white.withOpacity(0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    decoration: InputDecoration(
                      hintText: 'Search or create a room...',
                      hintStyle: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 15,
                      ),
                      prefixIcon: Container(
                        margin: const EdgeInsets.all(12),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.search, color: Colors.blue.shade300, size: 20),
                      ),
                      suffixIcon: IconButton(
                        icon: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.arrow_forward, color: Colors.blue.shade300, size: 20),
                        ),
                        onPressed: () {
                          if (_searchController.text.isNotEmpty) {
                            _joinRoom(_searchController.text.trim());
                          }
                        },
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
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

          const SizedBox(height: 28),

          // Section header with glass background
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Public Rooms',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.95),
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.2),
                          width: 1,
                        ),
                      ),
                      child: IconButton(
                        icon: Icon(Icons.refresh, color: Colors.white.withOpacity(0.9), size: 22),
                        onPressed: _loadAvailableRooms,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Available rooms list
          Expanded(
            child: _isLoadingRooms
                ? Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.2),
                              width: 1,
                            ),
                          ),
                          child: const CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                      ),
                    ),
                  )
                : _availableRooms.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        itemCount: _availableRooms.length,
                        itemBuilder: (context, index) {
                          final room = _availableRooms[index];
                          return _buildRoomCard(room, index);
                        },
                      ),
          ),

          // Connecting indicator
          if (_isConnecting) _buildConnectingIndicator(),
        ],
      ),
    );
  }

  // Empty state with glass design
  Widget _buildEmptyState() {
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            margin: const EdgeInsets.all(20),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withOpacity(0.1),
                  Colors.white.withOpacity(0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withOpacity(0.2),
                width: 1.5,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.meeting_room,
                    size: 48,
                    color: Colors.blue.shade300,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'No Public Rooms',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Be the first to create a room\nSearch above to get started',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
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
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.15),
                Colors.white.withOpacity(0.05),
              ],
            ),
            border: Border(
              top: BorderSide(
                color: Colors.white.withOpacity(0.3),
                width: 1.5,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                  strokeWidth: 2.5,
                ),
              ),
              const SizedBox(width: 16),
              Text(
                'Joining room...',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Enhanced room card widget
  Widget _buildRoomCard(RoomInfo room, int index) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withOpacity(0.15),
                  Colors.white.withOpacity(0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withOpacity(0.3),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                splashColor: Colors.white.withOpacity(0.1),
                highlightColor: Colors.white.withOpacity(0.05),
                onTap: () => _joinRoom(room.name),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      // Room icon with gradient
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.blue.withOpacity(0.4),
                              Colors.purple.withOpacity(0.4),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blue.withOpacity(0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.groups_rounded,
                          color: Colors.white.withOpacity(0.95),
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              room.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.3,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.person,
                                        size: 14,
                                        color: Colors.white.withOpacity(0.7),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${room.numParticipants}',
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.8),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade400,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.green.withOpacity(0.5),
                                        blurRadius: 6,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Active',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.6),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        color: Colors.white.withOpacity(0.5),
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Room view (when connected)
  Widget _buildRoomView() {
    return SafeArea(
      child: Stack(
        children: [
          // Participants grid
          Column(
            children: [
              // Room info banner with glass effect
              ClipRRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white.withOpacity(0.12),
                          Colors.white.withOpacity(0.05),
                        ],
                      ),
                      border: Border(
                        bottom: BorderSide(
                          color: Colors.white.withOpacity(0.2),
                          width: 1,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.meeting_room_rounded,
                            color: Colors.blue.shade300,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _currentRoomName ?? 'Unknown Room',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.3,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${_participants.length} participant${_participants.length != 1 ? 's' : ''}',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.6),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
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

              // Participants grid
              Expanded(
                child: _participants.isEmpty
                    ? _buildWaitingState()
                    : _buildParticipantGrid(),
              ),
            ],
          ),

          // Floating glass controls at bottom
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: _buildFloatingControls(),
          ),
        ],
      ),
    );
  }

  // Waiting state
  Widget _buildWaitingState() {
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            margin: const EdgeInsets.all(20),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withOpacity(0.1),
                  Colors.white.withOpacity(0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withOpacity(0.2),
                width: 1.5,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                    strokeWidth: 3,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Waiting for participants...',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Participant grid layout
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
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 110),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: participantCount == 1 ? 0.75 : 1.0,
      ),
      itemCount: participantCount,
      itemBuilder: (context, index) {
        return _buildParticipantTile(_participants[index]);
      },
    );
  }

  // Enhanced participant tile
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
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.grey.shade900,
                      Colors.grey.shade800,
                    ],
                  ),
                ),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.person,
                      size: 48,
                      color: Colors.white.withOpacity(0.4),
                    ),
                  ),
                ),
              ),

            // Glass overlay for speaking indicator
            if (isSpeaking)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.green.shade400,
                      width: 4,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.green.withOpacity(0.5),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              ),

            // Border overlay
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isLocal
                        ? Colors.blue.withOpacity(0.6)
                        : Colors.white.withOpacity(0.3),
                    width: isLocal ? 3 : 2,
                  ),
                ),
              ),
            ),

            // Identity label with enhanced glass effect
            Positioned(
              bottom: 12,
              left: 12,
              right: 12,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.black.withOpacity(0.6),
                          Colors.black.withOpacity(0.4),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isLocal) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.blue.withOpacity(0.6),
                                  Colors.purple.withOpacity(0.6),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'You',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        if (isSpeaking) ...[
                          Icon(
                            Icons.graphic_eq_rounded,
                            color: Colors.green.shade400,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Flexible(
                          child: Text(
                            identity,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
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

  // Floating glass controls
  Widget _buildFloatingControls() {
    return FadeTransition(
      opacity: _controlsAnimationController,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: _controlsAnimationController,
          curve: Curves.easeOut,
        )),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withOpacity(0.2),
                    Colors.white.withOpacity(0.1),
                  ],
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.white.withOpacity(0.4),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Microphone
                  _buildGlassControlButton(
                    icon: _isMicEnabled ? Icons.mic_rounded : Icons.mic_off_rounded,
                    label: _isMicEnabled ? 'Mic On' : 'Mic Off',
                    isActive: _isMicEnabled,
                    activeColor: Colors.blue,
                    onPressed: _toggleMicrophone,
                  ),

                  // Camera
                  _buildGlassControlButton(
                    icon: _isCameraEnabled ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                    label: _isCameraEnabled ? 'Cam On' : 'Cam Off',
                    isActive: _isCameraEnabled,
                    activeColor: Colors.green,
                    onPressed: _toggleCamera,
                  ),

                  // Leave
                  _buildGlassControlButton(
                    icon: Icons.call_end_rounded,
                    label: 'Leave',
                    isActive: false,
                    isDestructive: true,
                    activeColor: Colors.red,
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

  // Glass control button
  Widget _buildGlassControlButton({
    required IconData icon,
    required String label,
    required bool isActive,
    bool isDestructive = false,
    required Color activeColor,
    required VoidCallback onPressed,
  }) {
    final displayColor = isDestructive
        ? Colors.red
        : isActive
            ? activeColor
            : Colors.white;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                gradient: isActive || isDestructive
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          displayColor.withOpacity(0.3),
                          displayColor.withOpacity(0.2),
                        ],
                      )
                    : LinearGradient(
                        colors: [
                          Colors.white.withOpacity(0.15),
                          Colors.white.withOpacity(0.05),
                        ],
                      ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: displayColor.withOpacity(0.6),
                  width: 2,
                ),
                boxShadow: isActive || isDestructive
                    ? [
                        BoxShadow(
                          color: displayColor.withOpacity(0.3),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        ),
                      ]
                    : [],
              ),
              child: Icon(
                icon,
                color: displayColor.withOpacity(0.95),
                size: 28,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.9),
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      ],
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
