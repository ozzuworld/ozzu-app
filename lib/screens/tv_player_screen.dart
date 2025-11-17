import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../services/jellyfin_service.dart';

class TVPlayerScreen extends StatefulWidget {
  final String itemId;
  final String title;
  final String? seriesId;
  final String? seriesName;

  const TVPlayerScreen({
    super.key,
    required this.itemId,
    required this.title,
    this.seriesId,
    this.seriesName,
  });

  @override
  State<TVPlayerScreen> createState() => _TVPlayerScreenState();
}

class _TVPlayerScreenState extends State<TVPlayerScreen> {
  final JellyfinService _jellyfinService = JellyfinService();
  VideoPlayerController? _controller;
  bool _isLoading = true;
  bool _showControls = true;
  Timer? _hideControlsTimer;
  Timer? _progressReportTimer;
  int? _savedPositionTicks;

  // Auto-play next episode state
  bool _showNextEpisodeCountdown = false;
  int _countdownSeconds = 10;
  Timer? _countdownTimer;
  Map<String, dynamic>? _nextEpisode;

  // Skip indicator state
  bool _showSkipLeft = false;
  bool _showSkipRight = false;
  Timer? _skipIndicatorTimer;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
    _setLandscapeOrientation();
  }

  void _setLandscapeOrientation() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  Future<void> _initializePlayer() async {
    // Get item details to check for saved playback position
    final itemDetails = await _jellyfinService.getItemDetails(widget.itemId);
    if (itemDetails != null && itemDetails['UserData'] != null) {
      _savedPositionTicks = itemDetails['UserData']['PlaybackPositionTicks'] ?? 0;
      debugPrint('▶️ Found saved position: ${_savedPositionTicks! ~/ 10000000}s');
    }

    final streamUrl = _jellyfinService.getStreamUrl(widget.itemId);

    _controller = VideoPlayerController.networkUrl(
      Uri.parse(streamUrl),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
    );

    try {
      await _controller!.initialize();

      // Resume from saved position if it exists (and it's not at the end)
      if (_savedPositionTicks != null && _savedPositionTicks! > 0) {
        final savedSeconds = _savedPositionTicks! ~/ 10000000;
        final duration = _controller!.value.duration.inSeconds;

        // Only resume if we're not within the last 5% of the video
        if (savedSeconds < duration * 0.95) {
          await _controller!.seekTo(Duration(seconds: savedSeconds));
          debugPrint('▶️ Resumed from ${savedSeconds}s');
        }
      }

      await _controller!.play();
      setState(() => _isLoading = false);
      _startHideControlsTimer();

      // Report playback started
      _jellyfinService.reportPlaybackStart(
        widget.itemId,
        positionTicks: _savedPositionTicks ?? 0,
      );

      // Start periodic progress reporting (every 10 seconds)
      _startProgressReporting();

      _controller!.addListener(() {
        if (mounted) {
          setState(() {});

          // Check if video ended
          if (_controller!.value.position >= _controller!.value.duration) {
            _onVideoEnded();
          }
        }
      });
    } catch (e) {
      debugPrint('Error initializing video player: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading video: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _startProgressReporting() {
    _progressReportTimer?.cancel();
    _progressReportTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (_controller != null && _controller!.value.isInitialized) {
        final positionTicks = _controller!.value.position.inMilliseconds * 10000;
        final isPaused = !_controller!.value.isPlaying;
        _jellyfinService.reportPlaybackProgress(
          widget.itemId,
          positionTicks,
          isPaused,
        );
      }
    });
  }

  Future<void> _onVideoEnded() async {
    debugPrint('▶️ Video ended');

    // Report playback stopped
    if (_controller != null && _controller!.value.isInitialized) {
      final positionTicks = _controller!.value.position.inMilliseconds * 10000;
      await _jellyfinService.reportPlaybackStopped(widget.itemId, positionTicks);
    }

    // Check for next episode if this is a TV show
    if (widget.seriesId != null) {
      await _fetchAndShowNextEpisode();
    } else {
      // For movies, just exit
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  Future<void> _fetchAndShowNextEpisode() async {
    // Fetch next episode
    _nextEpisode = await _jellyfinService.getNextUp(widget.seriesId!);

    if (_nextEpisode != null && mounted) {
      // Show countdown overlay
      setState(() {
        _showNextEpisodeCountdown = true;
        _countdownSeconds = 10;
      });

      // Start countdown timer
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_countdownSeconds > 0) {
          setState(() => _countdownSeconds--);
        } else {
          timer.cancel();
          _playNextEpisode();
        }
      });
    } else {
      // No next episode, exit
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  void _playNextEpisode() {
    if (_nextEpisode != null && mounted) {
      final episodeId = _nextEpisode!['Id'];
      final seasonNum = _nextEpisode!['ParentIndexNumber'];
      final episodeNum = _nextEpisode!['IndexNumber'];
      final episodeName = _nextEpisode!['Name'];
      final fullTitle = 'S${seasonNum}E${episodeNum} - $episodeName';

      // Navigate to next episode
      Navigator.pushReplacement(
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
  }

  void _cancelNextEpisode() {
    _countdownTimer?.cancel();
    setState(() {
      _showNextEpisodeCountdown = false;
    });
    Navigator.pop(context);
  }

  Future<void> _reportStopAndExit() async {
    if (_controller != null && _controller!.value.isInitialized) {
      final positionTicks = _controller!.value.position.inMilliseconds * 10000;
      await _jellyfinService.reportPlaybackStopped(widget.itemId, positionTicks);
    }
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _startHideControlsTimer();
    } else {
      _hideControlsTimer?.cancel();
    }
  }

  void _showSkipIndicator(bool isLeft) {
    _skipIndicatorTimer?.cancel();
    setState(() {
      if (isLeft) {
        _showSkipLeft = true;
        _showSkipRight = false;
      } else {
        _showSkipRight = true;
        _showSkipLeft = false;
      }
    });

    _skipIndicatorTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() {
          _showSkipLeft = false;
          _showSkipRight = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _progressReportTimer?.cancel();
    _countdownTimer?.cancel();
    _skipIndicatorTimer?.cancel();

    // Report playback stopped before disposing
    if (_controller != null && _controller!.value.isInitialized) {
      final positionTicks = _controller!.value.position.inMilliseconds * 10000;
      _jellyfinService.reportPlaybackStopped(widget.itemId, positionTicks);
    }

    _controller?.dispose();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Double tap to skip areas
          Row(
            children: [
              // Left side - double tap to rewind 10s
              Expanded(
                child: GestureDetector(
                  onDoubleTap: () {
                    if (_controller != null && _controller!.value.isInitialized) {
                      final position = _controller!.value.position;
                      _controller!.seekTo(position - const Duration(seconds: 10));
                      _showSkipIndicator(true);
                    }
                  },
                  onTap: _toggleControls,
                  child: Container(color: Colors.transparent),
                ),
              ),
              // Right side - double tap to forward 10s
              Expanded(
                child: GestureDetector(
                  onDoubleTap: () {
                    if (_controller != null && _controller!.value.isInitialized) {
                      final position = _controller!.value.position;
                      _controller!.seekTo(position + const Duration(seconds: 10));
                      _showSkipIndicator(false);
                    }
                  },
                  onTap: _toggleControls,
                  child: Container(color: Colors.transparent),
                ),
              ),
            ],
          ),

          Stack(
            fit: StackFit.expand,
            children: [
            // Video player
            if (_controller != null && _controller!.value.isInitialized)
              Center(
                child: AspectRatio(
                  aspectRatio: _controller!.value.aspectRatio,
                  child: VideoPlayer(_controller!),
                ),
              ),

            // Loading indicator
            if (_isLoading)
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),

            // Controls overlay
            if (_showControls && !_isLoading)
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.7),
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black.withOpacity(0.7),
                    ],
                    stops: const [0.0, 0.3, 0.7, 1.0],
                  ),
                ),
              ),

            // Top bar with title and close button
            if (_showControls && !_isLoading)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Center play/pause button
            if (_showControls && !_isLoading && _controller != null)
              Center(
                child: IconButton(
                  icon: Icon(
                    _controller!.value.isPlaying ? Icons.pause : Icons.play_arrow,
                    size: 64,
                    color: Colors.white,
                  ),
                  onPressed: () {
                    setState(() {
                      if (_controller!.value.isPlaying) {
                        _controller!.pause();
                      } else {
                        _controller!.play();
                        _startHideControlsTimer();
                      }
                    });
                  },
                ),
              ),

            // Bottom controls
            if (_showControls && !_isLoading && _controller != null)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Progress bar
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Text(
                              _formatDuration(_controller!.value.position),
                              style: const TextStyle(color: Colors.white, fontSize: 12),
                            ),
                            Expanded(
                              child: Slider(
                                value: _controller!.value.position.inSeconds.toDouble(),
                                max: _controller!.value.duration.inSeconds.toDouble(),
                                onChanged: (value) {
                                  _controller!.seekTo(Duration(seconds: value.toInt()));
                                  _startHideControlsTimer();
                                },
                                activeColor: Colors.blueAccent,
                                inactiveColor: Colors.white24,
                              ),
                            ),
                            Text(
                              _formatDuration(_controller!.value.duration),
                              style: const TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          ],
                        ),
                      ),

                      // Additional controls
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            // Rewind 10s
                            IconButton(
                              icon: const Icon(Icons.replay_10, color: Colors.white),
                              onPressed: () {
                                final position = _controller!.value.position;
                                _controller!.seekTo(position - const Duration(seconds: 10));
                                _startHideControlsTimer();
                              },
                            ),

                            // Play/Pause
                            IconButton(
                              icon: Icon(
                                _controller!.value.isPlaying ? Icons.pause : Icons.play_arrow,
                                color: Colors.white,
                                size: 32,
                              ),
                              onPressed: () {
                                setState(() {
                                  if (_controller!.value.isPlaying) {
                                    _controller!.pause();
                                  } else {
                                    _controller!.play();
                                    _startHideControlsTimer();
                                  }
                                });
                              },
                            ),

                            // Forward 10s
                            IconButton(
                              icon: const Icon(Icons.forward_10, color: Colors.white),
                              onPressed: () {
                                final position = _controller!.value.position;
                                _controller!.seekTo(position + const Duration(seconds: 10));
                                _startHideControlsTimer();
                              },
                            ),

                            // Fullscreen toggle (already in fullscreen, so this could be settings)
                            IconButton(
                              icon: const Icon(Icons.settings, color: Colors.white),
                              onPressed: () {
                                // Could show quality settings, subtitles, etc.
                                _startHideControlsTimer();
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Skip indicators (double-tap feedback)
            if (_showSkipLeft || _showSkipRight)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _showSkipLeft ? Icons.replay_10 : Icons.forward_10,
                    color: Colors.white,
                    size: 48,
                  ),
                ),
              ),

            // Next episode countdown overlay
            if (_showNextEpisodeCountdown && _nextEpisode != null)
              Container(
                color: Colors.black.withOpacity(0.8),
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 400),
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.skip_next,
                          color: Colors.blueAccent,
                          size: 48,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Up Next',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _nextEpisode!['Name'] ?? 'Unknown',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 16,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Playing in $_countdownSeconds seconds',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            OutlinedButton(
                              onPressed: _cancelNextEpisode,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Colors.white),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 12,
                                ),
                              ),
                              child: const Text('Cancel'),
                            ),
                            ElevatedButton(
                              onPressed: _playNextEpisode,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blueAccent,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 12,
                                ),
                              ),
                              child: const Text('Play Now'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }
}
