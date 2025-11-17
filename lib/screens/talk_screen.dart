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

class _TalkScreenState extends State<TalkScreen> {
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

  @override
  void initState() {
    super.initState();
    _loadAvailableRooms();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _roomListener?.dispose();
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
            backgroundColor: Colors.red,
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
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Talk',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          if (_isConnected)
            IconButton(
              icon: const Icon(Icons.call_end, color: Colors.red),
              onPressed: _disconnectFromRoom,
            ),
        ],
      ),
      body: _isConnected ? _buildRoomView() : _buildRoomSelectionView(),
    );
  }

  // Room selection view
  Widget _buildRoomSelectionView() {
    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search for a room...',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                    prefixIcon: Icon(Icons.search, color: Colors.white.withOpacity(0.7)),
                    suffixIcon: IconButton(
                      icon: Icon(Icons.arrow_forward, color: Colors.white.withOpacity(0.7)),
                      onPressed: () {
                        if (_searchController.text.isNotEmpty) {
                          _joinRoom(_searchController.text.trim());
                        }
                      },
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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

        // Refresh button
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Public Rooms',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: Icon(Icons.refresh, color: Colors.white.withOpacity(0.7)),
                onPressed: _loadAvailableRooms,
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // Available rooms list
        Expanded(
          child: _isLoadingRooms
              ? Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white.withOpacity(0.7)),
                  ),
                )
              : _availableRooms.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.meeting_room, size: 64, color: Colors.white.withOpacity(0.3)),
                          const SizedBox(height: 16),
                          Text(
                            'No public rooms available',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Create a new room by searching',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.3),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _availableRooms.length,
                      itemBuilder: (context, index) {
                        final room = _availableRooms[index];
                        return _buildRoomCard(room);
                      },
                    ),
        ),

        // Connecting indicator
        if (_isConnecting)
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white.withOpacity(0.7)),
                ),
                const SizedBox(width: 16),
                Text(
                  'Joining room...',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // Room card widget
  Widget _buildRoomCard(RoomInfo room) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withOpacity(0.2),
                width: 1,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _joinRoom(room.name),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.groups,
                          color: Colors.white.withOpacity(0.9),
                          size: 24,
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
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.person,
                                  size: 14,
                                  color: Colors.white.withOpacity(0.6),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${room.numParticipants} participant${room.numParticipants != 1 ? 's' : ''}',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.6),
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_ios,
                        color: Colors.white.withOpacity(0.4),
                        size: 16,
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
    return Column(
      children: [
        // Room info banner
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withOpacity(0.1),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.meeting_room, color: Colors.white.withOpacity(0.7), size: 20),
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
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_participants.length} participant${_participants.length != 1 ? 's' : ''}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Participants grid
        Expanded(
          child: _participants.isEmpty
              ? Center(
                  child: Text(
                    'Waiting for participants...',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 16,
                    ),
                  ),
                )
              : _buildParticipantGrid(),
        ),

        // Controls
        _buildControls(),
      ],
    );
  }

  // Participant grid layout
  Widget _buildParticipantGrid() {
    final participantCount = _participants.length;

    // Calculate grid dimensions
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
      padding: const EdgeInsets.all(8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.0,
      ),
      itemCount: participantCount,
      itemBuilder: (context, index) {
        return _buildParticipantTile(_participants[index]);
      },
    );
  }

  // Participant tile
  Widget _buildParticipantTile(Participant participant) {
    final isLocal = participant == _room?.localParticipant;
    final identity = participant.identity ?? 'Unknown';

    // Find video track
    VideoTrack? videoTrack;
    for (final pub in participant.videoTrackPublications) {
      if (pub.subscribed && pub.track != null) {
        videoTrack = pub.track as VideoTrack;
        break;
      }
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isLocal ? Colors.blue.withOpacity(0.5) : Colors.white.withOpacity(0.2),
            width: 2,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Video or placeholder
            if (videoTrack != null)
              VideoTrackRenderer(videoTrack)
            else
              Container(
                color: Colors.grey.shade900,
                child: Center(
                  child: Icon(
                    Icons.person,
                    size: 48,
                    color: Colors.white.withOpacity(0.3),
                  ),
                ),
              ),

            // Identity label
            Positioned(
              bottom: 8,
              left: 8,
              right: 8,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isLocal)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'You',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        if (isLocal) const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            identity,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Speaking indicator
            if (participant.isSpeaking)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.green,
                      width: 3,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Controls widget
  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.8),
        border: Border(
          top: BorderSide(
            color: Colors.white.withOpacity(0.1),
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Microphone toggle
          _buildControlButton(
            icon: _isMicEnabled ? Icons.mic : Icons.mic_off,
            label: 'Mic',
            isActive: _isMicEnabled,
            onPressed: _toggleMicrophone,
          ),

          // Camera toggle
          _buildControlButton(
            icon: _isCameraEnabled ? Icons.videocam : Icons.videocam_off,
            label: 'Camera',
            isActive: _isCameraEnabled,
            onPressed: _toggleCamera,
          ),

          // Leave button
          _buildControlButton(
            icon: Icons.call_end,
            label: 'Leave',
            isActive: false,
            isDestructive: true,
            onPressed: _disconnectFromRoom,
          ),
        ],
      ),
    );
  }

  // Control button
  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required bool isActive,
    bool isDestructive = false,
    required VoidCallback onPressed,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(32),
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: isDestructive
                    ? Colors.red.withOpacity(0.2)
                    : isActive
                        ? Colors.blue.withOpacity(0.3)
                        : Colors.white.withOpacity(0.1),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDestructive
                      ? Colors.red
                      : isActive
                          ? Colors.blue
                          : Colors.white.withOpacity(0.3),
                  width: 2,
                ),
              ),
              child: Icon(
                icon,
                color: isDestructive
                    ? Colors.red
                    : isActive
                        ? Colors.blue
                        : Colors.white.withOpacity(0.7),
                size: 28,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 12,
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
