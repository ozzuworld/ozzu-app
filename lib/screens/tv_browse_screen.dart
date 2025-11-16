import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../services/jellyfin_service.dart';
import '../services/jellyseerr_service.dart';
import 'tv_player_screen.dart';

class TVBrowseScreen extends StatefulWidget {
  const TVBrowseScreen({super.key});

  @override
  State<TVBrowseScreen> createState() => _TVBrowseScreenState();
}

class _TVBrowseScreenState extends State<TVBrowseScreen> {
  final JellyfinService _jellyfinService = JellyfinService();
  final JellyseerrService _jellyseerrService = JellyseerrService();

  bool _isLoading = true;
  List<dynamic> _recentlyAdded = [];
  List<dynamic> _trendingMovies = [];
  List<dynamic> _trendingTV = [];
  List<dynamic> _popularMovies = [];
  List<dynamic> _movies = [];
  List<dynamic> _tvShows = [];

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    setState(() => _isLoading = true);

    // Authenticate with both services
    await _jellyfinService.authenticate('hadmin', 'Pokemon123!');
    await _jellyseerrService.login('hadmin', 'Pokemon123!');

    // Load content from both services
    await Future.wait([
      _loadJellyfinContent(),
      _loadJellyseerrContent(),
    ]);

    setState(() => _isLoading = false);
  }

  Future<void> _loadJellyfinContent() async {
    final results = await Future.wait([
      _jellyfinService.getRecentlyAdded(),
      _jellyfinService.getMovies(),
      _jellyfinService.getTVShows(),
    ]);

    setState(() {
      _recentlyAdded = results[0];
      _movies = results[1];
      _tvShows = results[2];
    });
  }

  Future<void> _loadJellyseerrContent() async {
    final results = await Future.wait([
      _jellyseerrService.getTrendingMovies(),
      _jellyseerrService.getTrendingTV(),
      _jellyseerrService.getPopularMovies(),
    ]);

    setState(() {
      _trendingMovies = results[0];
      _trendingTV = results[1];
      _popularMovies = results[2];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.2)),
            ),
            child: const Icon(Icons.arrow_back, color: Colors.white),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'OZZU TV',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
      ),
      body: _isLoading
          ? _buildLoadingState()
          : RefreshIndicator(
              onRefresh: _initialize,
              backgroundColor: Colors.black.withOpacity(0.8),
              color: Colors.white,
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  // Featured/Hero section
                  if (_recentlyAdded.isNotEmpty)
                    _buildFeaturedSection(_recentlyAdded.first),

                  const SizedBox(height: 20),

                  // Recently Added
                  if (_recentlyAdded.isNotEmpty)
                    _buildContentRow(
                      'Recently Added',
                      _recentlyAdded,
                      isJellyfin: true,
                    ),

                  // Trending Movies
                  if (_trendingMovies.isNotEmpty)
                    _buildContentRow(
                      'Trending Movies',
                      _trendingMovies,
                      isJellyfin: false,
                    ),

                  // Trending TV Shows
                  if (_trendingTV.isNotEmpty)
                    _buildContentRow(
                      'Trending TV Shows',
                      _trendingTV,
                      isJellyfin: false,
                    ),

                  // Popular Movies
                  if (_popularMovies.isNotEmpty)
                    _buildContentRow(
                      'Popular Movies',
                      _popularMovies,
                      isJellyfin: false,
                    ),

                  // All Movies
                  if (_movies.isNotEmpty)
                    _buildContentRow(
                      'Movies',
                      _movies,
                      isJellyfin: true,
                    ),

                  // All TV Shows
                  if (_tvShows.isNotEmpty)
                    _buildContentRow(
                      'TV Shows',
                      _tvShows,
                      isJellyfin: true,
                    ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: Colors.blueAccent),
          const SizedBox(height: 20),
          Text(
            'Loading content...',
            style: TextStyle(color: Colors.white.withOpacity(0.7)),
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturedSection(dynamic item) {
    final isJellyfin = item['Id'] != null;
    final imageUrl = isJellyfin
        ? _jellyfinService.getImageUrl(item['Id'], type: 'Backdrop')
        : _jellyseerrService.getImageUrl(item['backdropPath'], size: 'original');

    final title = isJellyfin ? item['Name'] : (item['title'] ?? item['name']);
    final overview = item['Overview'] ?? item['overview'] ?? 'No description available';

    return Container(
      height: 500,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background image
          CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.cover,
            placeholder: (context, url) => Container(color: Colors.grey[900]),
            errorWidget: (context, url, error) => Container(color: Colors.grey[900]),
          ),

          // Gradient overlay
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withOpacity(0.7),
                  Colors.black,
                ],
                stops: const [0.0, 0.7, 1.0],
              ),
            ),
          ),

          // Content
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                Text(
                  overview,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 14,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    if (isJellyfin)
                      ElevatedButton.icon(
                        onPressed: () => _playItem(item),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Play'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                      ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: () => _showDetails(item, isJellyfin),
                      icon: const Icon(Icons.info_outline),
                      label: const Text('More Info'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContentRow(String title, List<dynamic> items, {required bool isJellyfin}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        SizedBox(
          height: 180,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return _buildContentCard(item, isJellyfin);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildContentCard(dynamic item, bool isJellyfin) {
    final imageUrl = isJellyfin
        ? _jellyfinService.getImageUrl(item['Id'])
        : _jellyseerrService.getImageUrl(item['posterPath']);

    return GestureDetector(
      onTap: () => isJellyfin ? _playItem(item) : _showDetails(item, isJellyfin),
      child: Container(
        width: 120,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.cover,
            placeholder: (context, url) => Shimmer.fromColors(
              baseColor: Colors.grey[900]!,
              highlightColor: Colors.grey[800]!,
              child: Container(color: Colors.grey[900]),
            ),
            errorWidget: (context, url, error) => Container(
              color: Colors.grey[900],
              child: const Icon(Icons.movie, color: Colors.white24),
            ),
          ),
        ),
      ),
    );
  }

  void _playItem(dynamic item) {
    final itemId = item['Id'];
    final title = item['Name'];

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TVPlayerScreen(
          itemId: itemId,
          title: title,
        ),
      ),
    );
  }

  void _showDetails(dynamic item, bool isJellyfin) {
    final title = isJellyfin ? item['Name'] : (item['title'] ?? item['name']);
    final overview = item['Overview'] ?? item['overview'] ?? 'No description available';
    final imageUrl = isJellyfin
        ? _jellyfinService.getImageUrl(item['Id'], type: 'Backdrop')
        : _jellyseerrService.getImageUrl(item['backdropPath'], size: 'w500');

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.8),
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AlertDialog(
          backgroundColor: Colors.black.withOpacity(0.9),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.white.withOpacity(0.2)),
          ),
          contentPadding: EdgeInsets.zero,
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Backdrop image
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorWidget: (context, url, error) => Container(
                      height: 200,
                      color: Colors.grey[900],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        overview,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 14,
                        ),
                      ),
                      if (isJellyfin) ...[
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              _playItem(item);
                            },
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('Play Now'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueAccent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}
