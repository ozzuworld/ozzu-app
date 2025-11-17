import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/jellyseerr_service.dart';

class ContentDetailsScreen extends StatefulWidget {
  final int tmdbId;
  final String mediaType; // 'movie' or 'tv'
  final String title;
  final String? posterPath;

  const ContentDetailsScreen({
    super.key,
    required this.tmdbId,
    required this.mediaType,
    required this.title,
    this.posterPath,
  });

  @override
  State<ContentDetailsScreen> createState() => _ContentDetailsScreenState();
}

class _ContentDetailsScreenState extends State<ContentDetailsScreen> {
  final JellyseerrService _jellyseerrService = JellyseerrService();
  Map<String, dynamic>? _details;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    setState(() => _isLoading = true);

    final details = widget.mediaType == 'movie'
        ? await _jellyseerrService.getMovieDetails(widget.tmdbId)
        : await _jellyseerrService.getTVDetails(widget.tmdbId);

    if (mounted) {
      setState(() {
        _details = details;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _details == null
              ? _buildErrorState()
              : _buildContent(),
    );
  }

  Widget _buildErrorState() {
    return Center(
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
            'Failed to load details',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Go Back'),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final backdropPath = _details!['backdropPath'];
    final posterPath = _details!['posterPath'] ?? widget.posterPath;
    final title = _details!['title'] ?? _details!['name'] ?? widget.title;
    final overview = _details!['overview'] ?? '';
    final releaseDate = _details!['releaseDate'] ?? _details!['firstAirDate'] ?? '';
    final voteAverage = _details!['voteAverage'] ?? 0.0;
    final runtime = _details!['runtime'];
    final genres = _details!['genres'] as List? ?? [];
    final credits = _details!['credits'];

    return CustomScrollView(
      slivers: [
        // Backdrop with gradient
        SliverAppBar(
          expandedHeight: 300,
          pinned: true,
          backgroundColor: Colors.black,
          leading: IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.arrow_back, color: Colors.white),
            ),
            onPressed: () => Navigator.pop(context),
          ),
          flexibleSpace: FlexibleSpaceBar(
            background: Stack(
              fit: StackFit.expand,
              children: [
                if (backdropPath != null)
                  CachedNetworkImage(
                    imageUrl: _jellyseerrService.getImageUrl(backdropPath, size: 'original'),
                    fit: BoxFit.cover,
                    errorWidget: (context, url, error) => Container(
                      color: Colors.grey[900],
                    ),
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
              ],
            ),
          ),
        ),

        // Content
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Poster and basic info row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Poster with Hero animation
                    if (posterPath != null)
                      Hero(
                        tag: 'content_jellyseerr_${widget.tmdbId}',
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CachedNetworkImage(
                            imageUrl: _jellyseerrService.getImageUrl(posterPath),
                            width: 120,
                            height: 180,
                            fit: BoxFit.cover,
                            errorWidget: (context, url, error) => Container(
                              width: 120,
                              height: 180,
                              color: Colors.grey[900],
                              child: const Icon(Icons.movie, color: Colors.white24),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(width: 16),

                    // Title and metadata
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Rating
                          Row(
                            children: [
                              const Icon(Icons.star, color: Colors.amber, size: 20),
                              const SizedBox(width: 4),
                              Text(
                                voteAverage.toStringAsFixed(1),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '/10',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // Release date and runtime
                          if (releaseDate.isNotEmpty)
                            Text(
                              releaseDate.substring(0, 4),
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 14,
                              ),
                            ),
                          if (runtime != null)
                            Text(
                              '${runtime}min',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 14,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Genres
                if (genres.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: genres.map<Widget>((genre) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withOpacity(0.2)),
                        ),
                        child: Text(
                          genre['name'],
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 12,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                const SizedBox(height: 24),

                // Request button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Request submitted!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    },
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('Request'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Overview section
                const Text(
                  'Overview',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  overview,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),

                // Cast section
                if (credits != null && credits['cast'] != null && credits['cast'].isNotEmpty) ...[
                  const Text(
                    'Cast',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 180,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: (credits['cast'] as List).length.clamp(0, 10),
                      itemBuilder: (context, index) {
                        final cast = credits['cast'][index];
                        final profilePath = cast['profilePath'];
                        final name = cast['name'];
                        final character = cast['character'];

                        return Container(
                          width: 120,
                          margin: const EdgeInsets.only(right: 12),
                          child: Column(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: profilePath != null
                                    ? CachedNetworkImage(
                                        imageUrl: _jellyseerrService.getImageUrl(profilePath),
                                        width: 120,
                                        height: 120,
                                        fit: BoxFit.cover,
                                        errorWidget: (context, url, error) => Container(
                                          width: 120,
                                          height: 120,
                                          color: Colors.grey[900],
                                          child: const Icon(Icons.person, color: Colors.white24),
                                        ),
                                      )
                                    : Container(
                                        width: 120,
                                        height: 120,
                                        color: Colors.grey[900],
                                        child: const Icon(Icons.person, color: Colors.white24),
                                      ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                              ),
                              Text(
                                character,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: 11,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
