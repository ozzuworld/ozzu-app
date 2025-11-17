import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';

class MusicBrowseScreen extends StatefulWidget {
  const MusicBrowseScreen({super.key});

  @override
  State<MusicBrowseScreen> createState() => _MusicBrowseScreenState();
}

class _MusicBrowseScreenState extends State<MusicBrowseScreen> {
  bool _isLoading = true;
  String? _errorMessage;

  // Mock data - will be replaced with actual Jellyfin music library data
  List<dynamic> _recentlyPlayed = [];
  List<dynamic> _playlists = [];
  List<dynamic> _albums = [];
  List<dynamic> _artists = [];
  List<dynamic> _popularTracks = [];

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // TODO: Replace with actual Jellyfin music API calls
      await Future.delayed(const Duration(seconds: 1)); // Simulate loading

      // For now, using mock data to demonstrate UI
      setState(() {
        _recentlyPlayed = _getMockData(5);
        _playlists = _getMockData(6);
        _albums = _getMockData(8);
        _artists = _getMockData(6);
        _popularTracks = _getMockData(10);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load music library: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  List<dynamic> _getMockData(int count) {
    return List.generate(count, (index) => {
      'id': 'mock_$index',
      'title': 'Item ${index + 1}',
      'subtitle': 'Description ${index + 1}',
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return _buildLoadingState();
    }

    if (_errorMessage != null) {
      return _buildErrorState();
    }

    return RefreshIndicator(
      onRefresh: _initialize,
      color: Colors.blueAccent,
      backgroundColor: Colors.grey[900],
      child: ListView(
        padding: const EdgeInsets.only(bottom: 100),
        children: [
          const SizedBox(height: 20),

          // Greeting section
          _buildGreetingSection(),
          const SizedBox(height: 30),

          // Recently Played
          if (_recentlyPlayed.isNotEmpty) ...[
            _buildSectionTitle('Recently Played'),
            const SizedBox(height: 15),
            _buildHorizontalList(_recentlyPlayed, _buildSquareCard),
            const SizedBox(height: 30),
          ],

          // Your Playlists
          if (_playlists.isNotEmpty) ...[
            _buildSectionTitle('Your Playlists'),
            const SizedBox(height: 15),
            _buildHorizontalList(_playlists, _buildSquareCard),
            const SizedBox(height: 30),
          ],

          // Albums
          if (_albums.isNotEmpty) ...[
            _buildSectionTitle('Albums'),
            const SizedBox(height: 15),
            _buildHorizontalList(_albums, _buildSquareCard),
            const SizedBox(height: 30),
          ],

          // Artists
          if (_artists.isNotEmpty) ...[
            _buildSectionTitle('Artists'),
            const SizedBox(height: 15),
            _buildHorizontalList(_artists, _buildArtistCard),
            const SizedBox(height: 30),
          ],

          // Popular Tracks
          if (_popularTracks.isNotEmpty) ...[
            _buildSectionTitle('Popular on Ozzu'),
            const SizedBox(height: 15),
            _buildTracksList(_popularTracks),
            const SizedBox(height: 30),
          ],
        ],
      ),
    );
  }

  Widget _buildGreetingSection() {
    final hour = DateTime.now().hour;
    String greeting = 'Good Morning';
    if (hour >= 12 && hour < 17) {
      greeting = 'Good Afternoon';
    } else if (hour >= 17) {
      greeting = 'Good Evening';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        greeting,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 28,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          TextButton(
            onPressed: () {
              // TODO: Navigate to full section view
            },
            child: Text(
              'See all',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHorizontalList(
    List<dynamic> items,
    Widget Function(dynamic item) cardBuilder,
  ) {
    return SizedBox(
      height: 200,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: EdgeInsets.only(
              right: index < items.length - 1 ? 16 : 0,
            ),
            child: cardBuilder(items[index]),
          );
        },
      ),
    );
  }

  Widget _buildSquareCard(dynamic item) {
    return GestureDetector(
      onTap: () {
        // TODO: Navigate to item details/player
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Tapped: ${item['title']}'),
            backgroundColor: Colors.blueAccent,
            duration: const Duration(seconds: 1),
          ),
        );
      },
      child: SizedBox(
        width: 160,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Album/Playlist cover
            Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _buildPlaceholderImage(),
              ),
            ),
            const SizedBox(height: 8),
            // Title
            Text(
              item['title'] ?? 'Unknown',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            // Subtitle
            Text(
              item['subtitle'] ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArtistCard(dynamic item) {
    return GestureDetector(
      onTap: () {
        // TODO: Navigate to artist details
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Tapped: ${item['title']}'),
            backgroundColor: Colors.blueAccent,
            duration: const Duration(seconds: 1),
          ),
        );
      },
      child: SizedBox(
        width: 160,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Artist image (circular)
            Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                color: Colors.grey[800],
                shape: BoxShape.circle,
              ),
              child: ClipOval(
                child: _buildPlaceholderImage(),
              ),
            ),
            const SizedBox(height: 8),
            // Artist name
            Text(
              item['title'] ?? 'Unknown Artist',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTracksList(List<dynamic> tracks) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: tracks.asMap().entries.map((entry) {
          final index = entry.key;
          final track = entry.value;
          return _buildTrackItem(track, index + 1);
        }).toList(),
      ),
    );
  }

  Widget _buildTrackItem(dynamic track, int number) {
    return GestureDetector(
      onTap: () {
        // TODO: Play track
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Playing: ${track['title']}'),
            backgroundColor: Colors.blueAccent,
            duration: const Duration(seconds: 1),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            // Track number
            SizedBox(
              width: 30,
              child: Text(
                '$number',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Album art
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(4),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: _buildPlaceholderImage(),
              ),
            ),
            const SizedBox(width: 12),
            // Track info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track['title'] ?? 'Unknown Track',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track['subtitle'] ?? 'Unknown Artist',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            // More options button
            IconButton(
              icon: Icon(
                Icons.more_vert,
                color: Colors.white.withOpacity(0.6),
              ),
              onPressed: () {
                // TODO: Show track options menu
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholderImage() {
    return Container(
      color: Colors.grey[800],
      child: Icon(
        Icons.music_note,
        color: Colors.white.withOpacity(0.3),
        size: 40,
      ),
    );
  }

  Widget _buildLoadingState() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      children: [
        // Greeting shimmer
        Shimmer.fromColors(
          baseColor: Colors.grey[800]!,
          highlightColor: Colors.grey[700]!,
          child: Container(
            width: 200,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.grey[800],
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        const SizedBox(height: 30),

        // Section shimmers
        ...List.generate(3, (index) => _buildSectionShimmer()),
      ],
    );
  }

  Widget _buildSectionShimmer() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section title shimmer
        Shimmer.fromColors(
          baseColor: Colors.grey[800]!,
          highlightColor: Colors.grey[700]!,
          child: Container(
            width: 150,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.grey[800],
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        const SizedBox(height: 15),
        // Cards shimmer
        SizedBox(
          height: 200,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: 5,
            itemBuilder: (context, index) {
              return Padding(
                padding: EdgeInsets.only(right: index < 4 ? 16 : 0),
                child: Shimmer.fromColors(
                  baseColor: Colors.grey[800]!,
                  highlightColor: Colors.grey[700]!,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 160,
                        height: 160,
                        decoration: BoxDecoration(
                          color: Colors.grey[800],
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 120,
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.grey[800],
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 30),
      ],
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.white.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'An error occurred',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _initialize,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 12,
                ),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
