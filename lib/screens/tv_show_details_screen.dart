import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../services/jellyfin_service.dart';
import 'tv_player_screen.dart';

class TVShowDetailsScreen extends StatefulWidget {
  final String seriesId;
  final String seriesName;

  const TVShowDetailsScreen({
    super.key,
    required this.seriesId,
    required this.seriesName,
  });

  @override
  State<TVShowDetailsScreen> createState() => _TVShowDetailsScreenState();
}

class _TVShowDetailsScreenState extends State<TVShowDetailsScreen> {
  final JellyfinService _jellyfinService = JellyfinService();
  List<dynamic> _seasons = [];
  Map<String, List<dynamic>> _episodesBySeason = {};
  bool _isLoading = true;
  String? _selectedSeasonId;

  @override
  void initState() {
    super.initState();
    _loadSeasons();
  }

  Future<void> _loadSeasons() async {
    setState(() => _isLoading = true);
    final seasons = await _jellyfinService.getSeasons(widget.seriesId);
    setState(() {
      _seasons = seasons;
      _isLoading = false;
      // Auto-select first season
      if (_seasons.isNotEmpty) {
        _selectedSeasonId = _seasons[0]['Id'];
        _loadEpisodes(_selectedSeasonId!);
      }
    });
  }

  Future<void> _loadEpisodes(String seasonId) async {
    if (_episodesBySeason.containsKey(seasonId)) {
      return; // Already loaded
    }

    final episodes = await _jellyfinService.getEpisodes(widget.seriesId, seasonId);
    setState(() {
      _episodesBySeason[seasonId] = episodes;
    });
  }

  void _playEpisode(dynamic episode) {
    final episodeId = episode['Id'];
    final episodeTitle = episode['Name'];
    final seasonNum = episode['ParentIndexNumber'];
    final episodeNum = episode['IndexNumber'];
    final fullTitle = 'S${seasonNum}E${episodeNum} - $episodeTitle';

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TVPlayerScreen(
          itemId: episodeId,
          title: fullTitle,
          seriesId: widget.seriesId,
          seriesName: widget.seriesName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          widget.seriesName,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Season selector
                if (_seasons.isNotEmpty)
                  Container(
                    height: 60,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _seasons.length,
                      itemBuilder: (context, index) {
                        final season = _seasons[index];
                        final seasonId = season['Id'];
                        final seasonName = season['Name'] ?? 'Season ${season['IndexNumber']}';
                        final isSelected = seasonId == _selectedSeasonId;

                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedSeasonId = seasonId;
                            });
                            _loadEpisodes(seasonId);
                          },
                          child: Container(
                            margin: const EdgeInsets.only(right: 12),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.white.withOpacity(0.2)
                                  : Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSelected
                                    ? Colors.white
                                    : Colors.white.withOpacity(0.2),
                              ),
                            ),
                            child: Center(
                              child: Text(
                                seasonName,
                                style: TextStyle(
                                  color: isSelected ? Colors.white : Colors.white.withOpacity(0.6),
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 20),

                // Episodes list
                Expanded(
                  child: _selectedSeasonId == null
                      ? const Center(
                          child: Text(
                            'No seasons available',
                            style: TextStyle(color: Colors.white),
                          ),
                        )
                      : _buildEpisodesList(_selectedSeasonId!),
                ),
              ],
            ),
    );
  }

  Widget _buildEpisodesList(String seasonId) {
    final episodes = _episodesBySeason[seasonId];

    if (episodes == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (episodes.isEmpty) {
      return const Center(
        child: Text(
          'No episodes available',
          style: TextStyle(color: Colors.white),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: episodes.length,
      itemBuilder: (context, index) {
        final episode = episodes[index];
        final episodeNum = episode['IndexNumber'];
        final episodeName = episode['Name'];
        final overview = episode['Overview'] ?? '';
        final imageId = episode['Id'];
        final hasImage = episode['ImageTags']?['Primary'] != null;

        return GestureDetector(
          onTap: () => _playEpisode(episode),
          child: Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Episode thumbnail
                ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    bottomLeft: Radius.circular(12),
                  ),
                  child: hasImage
                      ? CachedNetworkImage(
                          imageUrl: _jellyfinService.getImageUrl(imageId),
                          width: 150,
                          height: 90,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Shimmer.fromColors(
                            baseColor: Colors.grey[900]!,
                            highlightColor: Colors.grey[800]!,
                            child: Container(
                              color: Colors.grey[900],
                            ),
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: Colors.grey[900],
                            child: const Icon(Icons.movie, color: Colors.white24),
                          ),
                        )
                      : Container(
                          width: 150,
                          height: 90,
                          color: Colors.grey[900],
                          child: const Icon(Icons.movie, color: Colors.white24),
                        ),
                ),
                // Episode info
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$episodeNum. $episodeName',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (overview.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            overview,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.6),
                              fontSize: 13,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                // Play icon
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Icon(
                    Icons.play_circle_outline,
                    color: Colors.white.withOpacity(0.8),
                    size: 32,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
