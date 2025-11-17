import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../services/jellyfin_service.dart';

class TVPlayerScreen extends StatefulWidget {
  final String itemId;
  final String title;

  const TVPlayerScreen({
    super.key,
    required this.itemId,
    required this.title,
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

  void _onVideoEnded() {
    debugPrint('▶️ Video ended');
    _reportStopAndExit();
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

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _progressReportTimer?.cancel();

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
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
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
          ],
        ),
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
