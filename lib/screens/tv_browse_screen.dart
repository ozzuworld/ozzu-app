import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/jellyfin_service.dart';
import '../services/jellyseerr_service.dart';
import '../services/favorites_service.dart';
import '../services/downloads_service.dart';
import 'tv_player_screen.dart';
import 'tv_show_details_screen.dart';
import 'content_details_screen.dart';
import 'settings_screen.dart';

class TVBrowseScreen extends StatefulWidget {
  final bool startWithSearch;
  final bool showBackButton;

  const TVBrowseScreen({
    super.key,
    this.startWithSearch = false,
    this.showBackButton = false,
  });

  @override
  State<TVBrowseScreen> createState() => _TVBrowseScreenState();
}

class _TVBrowseScreenState extends State<TVBrowseScreen> {
  final JellyfinService _jellyfinService = JellyfinService();
  final JellyseerrService _jellyseerrService = JellyseerrService();
  final FavoritesService _favoritesService = FavoritesService();
  final DownloadsService _downloadsService = DownloadsService();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  static const String _searchHistoryKey = 'search_history';

  bool _isLoading = true;
  String? _errorMessage;
  List<dynamic> _continueWatching = [];
  List<dynamic> _recentlyAdded = [];
  List<dynamic> _trendingMovies = [];
  List<dynamic> _trendingTV = [];
  List<dynamic> _popularMovies = [];
  List<dynamic> _movies = [];
  List<dynamic> _tvShows = [];
  List<Map<String, dynamic>> _favorites = [];
  List<Map<String, dynamic>> _downloads = [];

  // Search state
  bool _isSearching = false;
  String _searchQuery = '';
  List<dynamic> _searchResults = [];
  bool _isSearchLoading = false;
  List<String> _searchHistory = [];

  // View mode state
  String _viewMode = 'row'; // 'row' or 'grid'
  String? _selectedGenre; // null means 'All'

  final List<String> _genres = [
    'All',
    'Action',
    'Comedy',
    'Drama',
    'Horror',
    'Sci-Fi',
    'Romance',
    'Thriller',
    'Documentary',
    'Animation',
    'Fantasy',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.startWithSearch) {
      _isSearching = true;
    }
    _loadSearchHistory();
    _initialize();
  }

  Future<void> _loadSearchHistory() async {
    final historyJson = await _storage.read(key: _searchHistoryKey);
    if (historyJson != null) {
      final List<dynamic> decoded = json.decode(historyJson);
      setState(() {
        _searchHistory = decoded.map((e) => e.toString()).toList();
      });
    }
  }

  Future<void> _saveSearchHistory() async {
    await _storage.write(
      key: _searchHistoryKey,
      value: json.encode(_searchHistory),
    );
  }

  Future<void> _addToSearchHistory(String query) async {
    if (query.trim().isEmpty) return;

    // Remove if already exists
    _searchHistory.remove(query);
    // Add to front
    _searchHistory.insert(0, query);
    // Keep only last 10 searches
    if (_searchHistory.length > 10) {
      _searchHistory = _searchHistory.sublist(0, 10);
    }
    await _saveSearchHistory();
  }

  Future<void> _clearSearchHistory() async {
    setState(() {
      _searchHistory.clear();
    });
    await _saveSearchHistory();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Search history cleared'),
          backgroundColor: Colors.grey[800],
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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

      // Load favorites and downloads
      await _favoritesService.loadFavorites();
      await _downloadsService.loadDownloads();
      setState(() {
        _favorites = _favoritesService.getFavorites();
        _downloads = _downloadsService.getCompletedDownloads();
        _isLoading = false;
      });
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

  Future<void> _performSearch(String query, {bool saveToHistory = false}) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearchLoading = false;
      });
      return;
    }

    setState(() => _isSearchLoading = true);

    try {
      // Add to search history only when explicitly requested (on submit)
      if (saveToHistory) {
        await _addToSearchHistory(query);
      }

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
            : widget.showBackButton
                ? IconButton(
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
                  )
                : null,
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
                  _performSearch(value); // Live search without saving
                },
                onSubmitted: (value) {
                  _performSearch(value, saveToHistory: true); // Save to history on submit
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
          if (!_isSearching && !widget.startWithSearch)
            IconButton(
              icon: Icon(
                _viewMode == 'row' ? Icons.grid_view : Icons.view_carousel,
                color: Colors.white,
              ),
              onPressed: () {
                final newMode = _viewMode == 'row' ? 'grid' : 'row';
                setState(() {
                  _viewMode = newMode;
                });

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Switched to ${newMode == 'grid' ? 'Grid' : 'Row'} view'),
                    backgroundColor: Colors.grey[800],
                    duration: const Duration(seconds: 1),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
          if (!_isSearching && !widget.startWithSearch)
            IconButton(
              icon: const Icon(Icons.search, color: Colors.white),
              onPressed: () {
                setState(() => _isSearching = true);
              },
            ),
          if (!_isSearching && widget.showBackButton)
            IconButton(
              icon: const Icon(Icons.settings, color: Colors.white),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SettingsScreen(),
                  ),
                );
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
                  : Column(
                      children: [
                        if (!widget.startWithSearch) _buildGenreFilter(),
                        Expanded(child: _buildContentBody()),
                      ],
                    ),
    );
  }

  Widget _buildGenreFilter() {
    return Container(
      height: 60,
      margin: const EdgeInsets.only(top: 100), // Account for transparent AppBar
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: _genres.length,
        itemBuilder: (context, index) {
          final genre = _genres[index];
          final isSelected = _selectedGenre == null && genre == 'All' ||
              _selectedGenre == genre;

          return Container(
            margin: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(genre),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  if (genre == 'All') {
                    _selectedGenre = null;
                  } else {
                    _selectedGenre = selected ? genre : null;
                  }
                });
              },
              backgroundColor: Colors.white.withOpacity(0.1),
              selectedColor: Colors.blueAccent,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : Colors.white.withOpacity(0.7),
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              checkmarkColor: Colors.white,
              side: BorderSide(
                color: isSelected
                    ? Colors.blueAccent
                    : Colors.white.withOpacity(0.2),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLoadingState() {
    return ListView(
      children: [
        const SizedBox(height: 100), // Padding for transparent AppBar

        // Featured section skeleton
        Shimmer.fromColors(
          baseColor: Colors.grey[900]!,
          highlightColor: Colors.grey[800]!,
          child: Container(
            height: 500,
            margin: const EdgeInsets.symmetric(horizontal: 0),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(0),
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Content rows skeleton
        ...List.generate(5, (rowIndex) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Section title skeleton
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Shimmer.fromColors(
                  baseColor: Colors.grey[900]!,
                  highlightColor: Colors.grey[800]!,
                  child: Container(
                    width: 150,
                    height: 20,
                    decoration: BoxDecoration(
                      color: Colors.grey[900],
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
              // Content cards skeleton
              SizedBox(
                height: 180,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: 8,
                  itemBuilder: (context, index) {
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
                                color: Colors.white.withOpacity(0.05),
                                size: 40,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
            ],
          );
        }),
      ],
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
      child: _viewMode == 'grid' ? _buildGridView() : _buildRowView(),
    );
  }

  bool _itemMatchesGenre(dynamic item) {
    if (_selectedGenre == null) return true;

    final genres = item['Genres'] ?? item['genres'] ?? [];
    if (genres is List) {
      for (var genre in genres) {
        final genreName = genre is String ? genre : genre['name'] ?? genre['Name'] ?? '';
        if (genreName.toString().toLowerCase().contains(_selectedGenre!.toLowerCase())) {
          return true;
        }
      }
    }
    return false;
  }

  Widget _buildRowView() {
    return ListView(
      children: [
        // No extra padding here since genre filter already provides it

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

        // My Favorites category
        if (_favorites.isNotEmpty) ...[
          _buildContentRow(
            'My Favorites',
            _favorites,
            isJellyfin: _favorites.first.containsKey('Id'),
          ),
          const SizedBox(height: 20),
        ],

        // Downloaded content category
        if (_downloads.isNotEmpty) ...[
          _buildDownloadsRow(),
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
        const SizedBox(height: 20),

        // Sorted content rows
        _buildMixedContentRow(
          'A-Z',
          _getSortedContent('alphabetical'),
        ),
        const SizedBox(height: 20),

        _buildMixedContentRow(
          'Top Rated',
          _getSortedContent('rating'),
        ),

        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildMixedContentRow(String title, List<dynamic> items) {
    if (items.isEmpty) return const SizedBox.shrink();

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
              // Determine if it's Jellyfin or Jellyseerr based on the presence of 'Id' field
              final isJellyfin = item['Id'] != null;
              return _buildContentCard(item, isJellyfin);
            },
          ),
        ),
      ],
    );
  }

  List<dynamic> _getSortedContent(String sortType) {
    // Combine all content
    final allContent = <dynamic>[
      ..._continueWatching,
      ..._favorites,
      ..._recentlyAdded,
      ..._trendingMovies,
      ..._trendingTV,
      ..._popularMovies,
      ..._movies,
      ..._tvShows,
    ];

    // Apply sorting
    if (sortType == 'alphabetical') {
      allContent.sort((a, b) {
        final aTitle = a['Name'] ?? a['title'] ?? a['name'] ?? '';
        final bTitle = b['Name'] ?? b['title'] ?? b['name'] ?? '';
        return aTitle.toString().toLowerCase().compareTo(bTitle.toString().toLowerCase());
      });
    } else if (sortType == 'rating') {
      allContent.sort((a, b) {
        final aRating = (a['CommunityRating'] ?? a['vote_average'] ?? 0.0) as num;
        final bRating = (b['CommunityRating'] ?? b['vote_average'] ?? 0.0) as num;
        return bRating.compareTo(aRating);
      });
    }

    return allContent;
  }

  Widget _buildGridView() {
    // Combine all content into a single list
    final allContent = <Map<String, dynamic>>[];

    // Add all items with their category info, applying genre filter
    for (var item in _continueWatching) {
      if (_itemMatchesGenre(item)) {
        allContent.add({'item': item, 'isJellyfin': true, 'showProgress': true});
      }
    }
    for (var item in _favorites) {
      if (_itemMatchesGenre(item)) {
        allContent.add({'item': item, 'isJellyfin': item.containsKey('Id')});
      }
    }
    for (var item in _recentlyAdded) {
      if (_itemMatchesGenre(item)) {
        allContent.add({'item': item, 'isJellyfin': true});
      }
    }
    for (var item in _trendingMovies) {
      if (_itemMatchesGenre(item)) {
        allContent.add({'item': item, 'isJellyfin': false});
      }
    }
    for (var item in _trendingTV) {
      if (_itemMatchesGenre(item)) {
        allContent.add({'item': item, 'isJellyfin': false});
      }
    }
    for (var item in _popularMovies) {
      if (_itemMatchesGenre(item)) {
        allContent.add({'item': item, 'isJellyfin': false});
      }
    }
    for (var item in _movies) {
      if (_itemMatchesGenre(item)) {
        allContent.add({'item': item, 'isJellyfin': true});
      }
    }
    for (var item in _tvShows) {
      if (_itemMatchesGenre(item)) {
        allContent.add({'item': item, 'isJellyfin': true});
      }
    }

    return CustomScrollView(
      slivers: [
        // No top padding needed since genre filter handles it
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 0.67,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final contentData = allContent[index];
                final item = contentData['item'];
                final isJellyfin = contentData['isJellyfin'] as bool;
                final showProgress = contentData['showProgress'] as bool? ?? false;

                return _buildContentCard(item, isJellyfin, showProgress: showProgress);
              },
              childCount: allContent.length,
            ),
          ),
        ),
        const SliverToBoxAdapter(
          child: SizedBox(height: 40), // Bottom padding
        ),
      ],
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

  Widget _buildDownloadsRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.download, color: Colors.blueAccent, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Downloaded',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_downloads.length}',
                  style: const TextStyle(
                    color: Colors.blueAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 180,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _downloads.length,
            itemBuilder: (context, index) {
              final download = _downloads[index];
              final metadata = download['metadata'] ?? {};

              return Container(
                width: 120,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        color: Colors.grey[900],
                        child: const Center(
                          child: Icon(Icons.download_done, color: Colors.blueAccent, size: 48),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withOpacity(0.9),
                              Colors.transparent,
                            ],
                          ),
                        ),
                        child: Text(
                          download['title'] ?? 'Downloaded',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
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
    return Container(
      height: 180,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          style: BorderStyle.solid,
          width: 1,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 48,
              color: Colors.white.withOpacity(0.3),
            ),
            const SizedBox(height: 12),
            Text(
              'No content available',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
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

  String _formatTimeRemaining(int totalMinutes, double progressPercent) {
    final remainingMinutes = (totalMinutes * (1 - progressPercent)).round();
    if (remainingMinutes < 60) {
      return '${remainingMinutes}m left';
    } else {
      final hours = remainingMinutes ~/ 60;
      final minutes = remainingMinutes % 60;
      return '${hours}h ${minutes}m left';
    }
  }

  Widget _buildContentCard(dynamic item, bool isJellyfin, {bool showProgress = false}) {
    final imageUrl = isJellyfin
        ? _jellyfinService.getImageUrl(item['Id'])
        : _jellyseerrService.getImageUrl(item['posterPath']);

    // Get progress percentage if available
    double? progressPercent;
    String? timeRemaining;
    if (showProgress && item['UserData'] != null) {
      progressPercent = (item['UserData']['PlayedPercentage'] ?? 0.0).toDouble() / 100.0;

      // Calculate time remaining
      final runTimeTicks = item['RunTimeTicks'];
      if (runTimeTicks != null && progressPercent != null && progressPercent > 0) {
        final totalMinutes = (runTimeTicks / 600000000).round(); // Convert ticks to minutes
        timeRemaining = _formatTimeRemaining(totalMinutes, progressPercent);
      }
    }

    // Create unique hero tag
    final heroTag = isJellyfin
        ? 'content_${item['Id']}'
        : 'content_jellyseerr_${item['id']}';

    return GestureDetector(
      onTap: () => isJellyfin ? _playItem(item) : _showDetails(item, isJellyfin),
      child: Hero(
        tag: heroTag,
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
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withOpacity(0.8),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    padding: const EdgeInsets.all(6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Time remaining text
                        if (timeRemaining != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              timeRemaining,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        // Progress bar
                        Container(
                          height: 3,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: progressPercent,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.blueAccent,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
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

  Widget _buildRecentSearches() {
    if (_searchHistory.isEmpty) {
      return Center(
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
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent Searches',
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            TextButton.icon(
              onPressed: _clearSearchHistory,
              icon: Icon(
                Icons.clear_all,
                color: Colors.white.withOpacity(0.7),
                size: 18,
              ),
              label: Text(
                'Clear',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ..._searchHistory.map((query) {
          return ListTile(
            leading: Icon(
              Icons.history,
              color: Colors.white.withOpacity(0.5),
            ),
            title: Text(
              query,
              style: const TextStyle(color: Colors.white),
            ),
            trailing: IconButton(
              icon: Icon(
                Icons.arrow_outward,
                color: Colors.white.withOpacity(0.5),
                size: 20,
              ),
              onPressed: () {
                setState(() {
                  _searchQuery = query;
                });
                _performSearch(query, saveToHistory: true); // Re-save to bump to top
              },
            ),
            onTap: () {
              setState(() {
                _searchQuery = query;
              });
              _performSearch(query, saveToHistory: true); // Re-save to bump to top
            },
          );
        }).toList(),
      ],
    );
  }

  Widget _buildSearchBody() {
    return Container(
      padding: const EdgeInsets.only(top: 100),
      child: _isSearchLoading
          ? const Center(child: CircularProgressIndicator())
          : _searchQuery.trim().isEmpty
              ? _buildRecentSearches()
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
