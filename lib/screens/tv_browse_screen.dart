import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../services/jellyfin_service.dart';
import '../services/jellyseerr_service.dart';
import 'tv_player_screen.dart';
import 'tv_show_details_screen.dart';
import 'content_details_screen.dart';

class TVBrowseScreen extends StatefulWidget {
  const TVBrowseScreen({super.key});

  @override
  State<TVBrowseScreen> createState() => _TVBrowseScreenState();
}

class _TVBrowseScreenState extends State<TVBrowseScreen> {
  final JellyfinService _jellyfinService = JellyfinService();
  final JellyseerrService _jellyseerrService = JellyseerrService();

  bool _isLoading = true;
  String? _errorMessage;
  List<dynamic> _continueWatching = [];
  List<dynamic> _recentlyAdded = [];
  List<dynamic> _trendingMovies = [];
  List<dynamic> _trendingTV = [];
  List<dynamic> _popularMovies = [];
  List<dynamic> _movies = [];
  List<dynamic> _tvShows = [];

  // Search state
  bool _isSearching = false;
  String _searchQuery = '';
  List<dynamic> _searchResults = [];
  bool _isSearchLoading = false;

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
      // Authenticate with both services
      final jellyfinAuth = await _jellyfinService.authenticate('hadmin', 'Pokemon123!');

      if (!jellyfinAuth) {
        setState(() {
          _errorMessage = 'Failed to authenticate with Jellyfin';
          _isLoading = false;
        });
        return;
      }

      // On web, skip Jellyseerr due to CORS issues
      if (!kIsWeb) {
        await _jellyseerrService.login('hadmin', 'Pokemon123!');
      }

      // Load content from Jellyfin
      await _loadJellyfinContent();

      // Load Jellyseerr content (only on mobile)
      if (!kIsWeb) {
        await _loadJellyseerrContent();
      }

      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Error initializing TV browse: $e');
      setState(() {
        _errorMessage = 'Failed to load content. Please try again.';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadJellyfinContent() async {
    try {
      debugPrint('📺 Loading Jellyfin content...');
      final results = await Future.wait([
        _jellyfinService.getContinueWatching(),
        _jellyfinService.getRecentlyAdded(),
        _jellyfinService.getMovies(),
        _jellyfinService.getTVShows(),
      ]);

      debugPrint('📺 Jellyfin content loaded:');
      debugPrint('  - Continue Watching: ${results[0].length} items');
      debugPrint('  - Recently Added: ${results[1].length} items');
      debugPrint('  - Movies: ${results[2].length} items');
      debugPrint('  - TV Shows: ${results[3].length} items');

      if (mounted) {
        setState(() {
          _continueWatching = results[0];
          _recentlyAdded = results[1];
          _movies = results[2];
          _tvShows = results[3];
        });
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Error loading Jellyfin content: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearchLoading = false;
      });
      return;
    }

    setState(() => _isSearchLoading = true);

    try {
      final results = await Future.wait([
        _jellyfinService.search(query),
        if (!kIsWeb) _jellyseerrService.search(query) else Future.value(<dynamic>[]),
      ]);

      final jellyfinResults = results[0];
      final jellyseerrResults = results[1];

      // Combine results with markers for source
      final combined = [
        ...jellyfinResults.map((item) => {'source': 'jellyfin', 'data': item}),
        ...jellyseerrResults.map((item) => {'source': 'jellyseerr', 'data': item}),
      ];

      if (mounted) {
        setState(() {
          _searchResults = combined;
          _isSearchLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Error searching: $e');
      if (mounted) {
        setState(() => _isSearchLoading = false);
      }
    }
  }

  Future<void> _loadJellyseerrContent() async {
    try {
      debugPrint('🎬 Loading Jellyseerr content...');
      final results = await Future.wait([
        _jellyseerrService.getTrendingMovies(),
        _jellyseerrService.getTrendingTV(),
        _jellyseerrService.getPopularMovies(),
      ]);

      debugPrint('🎬 Jellyseerr content loaded:');
      debugPrint('  - Trending Movies: ${results[0].length} items');
      debugPrint('  - Trending TV: ${results[1].length} items');
      debugPrint('  - Popular Movies: ${results[2].length} items');

      if (mounted) {
        setState(() {
          _trendingMovies = results[0];
          _trendingTV = results[1];
          _popularMovies = results[2];
        });
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Error loading Jellyseerr content: $e');
      debugPrint('Stack trace: $stackTrace');
      // Non-fatal: Continue with Jellyfin content only
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: _isSearching
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () {
                  setState(() {
                    _isSearching = false;
                    _searchQuery = '';
                    _searchResults = [];
                  });
                },
              )
            : IconButton(
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
        title: _isSearching
            ? TextField(
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search movies & TV shows...',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                  border: InputBorder.none,
                ),
                onChanged: (value) {
                  setState(() => _searchQuery = value);
                  _performSearch(value);
                },
              )
            : const Text(
                'OZZU TV',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
        actions: [
          if (!_isSearching)
            IconButton(
              icon: const Icon(Icons.search, color: Colors.white),
              onPressed: () {
                setState(() => _isSearching = true);
              },
            ),
        ],
      ),
      body: _isSearching
          ? _buildSearchBody()
          : _isLoading
              ? _buildLoadingState()
              : _errorMessage != null
                  ? _buildErrorState()
                  : _buildContentBody(),
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

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            color: Colors.white.withOpacity(0.5),
            size: 64,
          ),
          const SizedBox(height: 20),
          Text(
            _errorMessage ?? 'An error occurred',
            style: TextStyle(color: Colors.white.withOpacity(0.7)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _initialize,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContentBody() {
    return RefreshIndicator(
      onRefresh: _initialize,
      color: Colors.blueAccent,
      child: ListView(
        children: [
          const SizedBox(height: 100), // Padding for transparent AppBar

          // Featured section (if we have any content)
          if (_recentlyAdded.isNotEmpty)
            _buildFeaturedSection(_recentlyAdded.first),

          const SizedBox(height: 20),

          // Continue Watching category (highest priority)
          if (_continueWatching.isNotEmpty) ...[
            _buildContentRow(
              'Continue Watching',
              _continueWatching,
              isJellyfin: true,
              showProgress: true,
            ),
            const SizedBox(height: 20),
          ],

          // Recently Added category
          _buildContentRow(
            'Recently Added',
            _recentlyAdded,
            isJellyfin: true,
          ),
          const SizedBox(height: 20),

          // Trending Movies category (from Jellyseerr)
          if (!kIsWeb)
            _buildContentRow(
              'Trending Movies',
              _trendingMovies,
              isJellyfin: false,
            ),
          if (!kIsWeb) const SizedBox(height: 20),

          // Trending TV category (from Jellyseerr)
          if (!kIsWeb)
            _buildContentRow(
              'Trending TV Shows',
              _trendingTV,
              isJellyfin: false,
            ),
          if (!kIsWeb) const SizedBox(height: 20),

          // Popular Movies category (from Jellyseerr)
          if (!kIsWeb)
            _buildContentRow(
              'Popular Movies',
              _popularMovies,
              isJellyfin: false,
            ),
          if (!kIsWeb) const SizedBox(height: 20),

          // Movies category (from Jellyfin)
          _buildContentRow(
            'Movies',
            _movies,
            isJellyfin: true,
          ),
          const SizedBox(height: 20),

          // TV Shows category (from Jellyfin)
          _buildContentRow(
            'TV Shows',
            _tvShows,
            isJellyfin: true,
          ),

          const SizedBox(height: 40),
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

  Widget _buildContentRow(String title, List<dynamic> items, {required bool isJellyfin, bool showProgress = false}) {
    // If empty, show placeholder cards to demonstrate the UI
    final displayItems = items.isEmpty ? List.filled(5, null) : items;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 10),
              if (items.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Empty',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 180,
          child: items.isEmpty
              ? _buildEmptyRow()
              : ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return _buildContentCard(item, isJellyfin, showProgress: showProgress);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyRow() {
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: 5, // Show 5 placeholder cards
      itemBuilder: (context, index) {
        return _buildPlaceholderCard();
      },
    );
  }

  Widget _buildPlaceholderCard() {
    return Container(
      width: 120,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Shimmer.fromColors(
          baseColor: Colors.grey[900]!,
          highlightColor: Colors.grey[800]!,
          child: Container(
            color: Colors.grey[900],
            child: Center(
              child: Icon(
                Icons.movie_outlined,
                color: Colors.white.withOpacity(0.1),
                size: 40,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContentCard(dynamic item, bool isJellyfin, {bool showProgress = false}) {
    final imageUrl = isJellyfin
        ? _jellyfinService.getImageUrl(item['Id'])
        : _jellyseerrService.getImageUrl(item['posterPath']);

    // Get progress percentage if available
    double? progressPercent;
    if (showProgress && item['UserData'] != null) {
      progressPercent = (item['UserData']['PlayedPercentage'] ?? 0.0).toDouble() / 100.0;
    }

    return GestureDetector(
      onTap: () => isJellyfin ? _playItem(item) : _showDetails(item, isJellyfin),
      child: Container(
        width: 120,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
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

              // Progress bar overlay
              if (showProgress && progressPercent != null && progressPercent > 0)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Progress bar
                      Container(
                        height: 3,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                        ),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: progressPercent,
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.blueAccent,
                            ),
                          ),
                        ),
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

  void _playItem(dynamic item) {
    final itemId = item['Id'];
    final title = item['Name'];
    final itemType = item['Type'];

    // Check if this is a TV Series - navigate to seasons/episodes screen
    if (itemType == 'Series') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => TVShowDetailsScreen(
            seriesId: itemId,
            seriesName: title,
          ),
        ),
      );
      return;
    }

    // For movies and episodes, play directly
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
    // For Jellyfin items, show simple dialog (can play directly)
    if (isJellyfin) {
      final title = item['Name'];
      final overview = item['Overview'] ?? 'No description available';
      final imageUrl = _jellyfinService.getImageUrl(item['Id'], type: 'Backdrop');

      showDialog(
        context: context,
        barrierColor: Colors.black.withOpacity(0.8),
        builder: (context) => BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 500),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.9),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.2)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
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
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(context),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: BorderSide(color: Colors.white.withOpacity(0.3)),
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                ),
                                child: const Text('Close'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      return;
    }

    // For Jellyseerr items, navigate to full details screen
    final tmdbId = item['id'];
    final mediaType = item['mediaType'];
    final title = item['title'] ?? item['name'];
    final posterPath = item['posterPath'];

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ContentDetailsScreen(
          tmdbId: tmdbId,
          mediaType: mediaType,
          title: title,
          posterPath: posterPath,
        ),
      ),
    );
  }

  Widget _buildSearchBody() {
    return Container(
      padding: const EdgeInsets.only(top: 100),
      child: _isSearchLoading
          ? const Center(child: CircularProgressIndicator())
          : _searchQuery.trim().isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.search,
                        size: 64,
                        color: Colors.white.withOpacity(0.3),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Search for movies & TV shows',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                )
              : _searchResults.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.search_off,
                            size: 64,
                            color: Colors.white.withOpacity(0.3),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No results found for "$_searchQuery"',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        childAspectRatio: 0.7,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: _searchResults.length,
                      itemBuilder: (context, index) {
                        final result = _searchResults[index];
                        final isJellyfin = result['source'] == 'jellyfin';
                        final item = result['data'];

                        return _buildContentCard(item, isJellyfin);
                      },
                    ),
    );
  }
}
