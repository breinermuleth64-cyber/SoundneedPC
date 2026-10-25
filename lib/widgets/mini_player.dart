import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class MiniPlayer extends StatefulWidget {
  const MiniPlayer({
    required this.compact,
    required this.hasTrack,
    required this.title,
    required this.artist,
    required this.cover,
    this.artworkProvider,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.playingStream,
    required this.initialPlaying,
    required this.loading,
    required this.onTogglePlayback,
    required this.shuffleEnabled,
    required this.onToggleShuffle,
    required this.loopEnabled,
    required this.onToggleLoop,
    required this.onPrevious,
    required this.onNext,
    required this.position,
    required this.duration,
    required this.positionLabel,
    required this.durationLabel,
    required this.onSeek,
    required this.volume,
    required this.onVolumeChanged,
    required this.queueOpen,
    required this.onToggleQueue,
    required this.windowMaximized,
    required this.onToggleWindowSize,
    required this.panelColor,
    required this.accentColor,
    required this.mutedColor,
    super.key,
  });

  final bool compact;
  final bool hasTrack;
  final String title;
  final String artist;
  final Widget cover;
  final ImageProvider? artworkProvider;
  final bool isFavorite;
  final VoidCallback? onToggleFavorite;
  final Stream<bool> playingStream;
  final bool initialPlaying;
  final bool loading;
  final ValueChanged<bool> onTogglePlayback;
  final bool shuffleEnabled;
  final VoidCallback? onToggleShuffle;
  final bool loopEnabled;
  final VoidCallback onToggleLoop;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final Duration position;
  final Duration? duration;
  final String positionLabel;
  final String durationLabel;
  final ValueChanged<Duration>? onSeek;
  final double volume;
  final ValueChanged<double> onVolumeChanged;
  final bool queueOpen;
  final VoidCallback onToggleQueue;
  final bool windowMaximized;
  final VoidCallback onToggleWindowSize;
  final Color panelColor;
  final Color accentColor;
  final Color mutedColor;

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  Color? _artworkColor;
  Color? _artworkSecondaryColor;
  Color? _artworkDarkColor;
  int _artworkRequestId = 0;

  static const Color _controlColor = Color(0xFFCACAD4);
  static const Color _iconColor = Color(0xFFD7D7E0);

  void _showUnavailable(BuildContext context, String feature) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF151522),
        title: Text('$feature no disponible'),
        content: Text('$feature todavía no está implementado en SoundNeed PC.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _readArtworkColor();
  }

  @override
  void didUpdateWidget(covariant MiniPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.artworkProvider != widget.artworkProvider) {
      _readArtworkColor();
    }
  }

  Future<void> _readArtworkColor() async {
    final requestId = ++_artworkRequestId;
    final provider = widget.artworkProvider;

    if (provider == null) {
      if (_artworkColor != null && mounted) {
        setState(() {
          _artworkColor = null;
          _artworkSecondaryColor = null;
          _artworkDarkColor = null;
        });
      }
      return;
    }

    try {
      final image = await _resolveArtwork(provider);
      final colors = await _extractArtworkTheme(image);

      if (mounted && requestId == _artworkRequestId) {
        setState(() {
          _artworkColor = colors.primary;
          _artworkSecondaryColor = colors.secondary;
          _artworkDarkColor = colors.dark;
        });
      }
    } catch (_) {
      if (mounted && requestId == _artworkRequestId) {
        setState(() {
          _artworkColor = null;
          _artworkSecondaryColor = null;
          _artworkDarkColor = null;
        });
      }
    }
  }

  Future<ui.Image> _resolveArtwork(ImageProvider provider) {
    final completer = Completer<ui.Image>();
    final stream = provider.resolve(const ImageConfiguration());
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        completer.complete(info.image);
      },
      onError: (Object error, StackTrace? stackTrace) {
        stream.removeListener(listener);
        completer.completeError(error, stackTrace);
      },
    );
    stream.addListener(listener);
    return completer.future;
  }

  Future<_ArtworkTheme> _extractArtworkTheme(ui.Image image) async {
    const sampleSize = 24;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      const Rect.fromLTWH(0, 0, 24, 24),
      Paint(),
    );
    final picture = recorder.endRecording();
    final thumbnail = await picture.toImage(sampleSize, sampleSize);
    picture.dispose();
    final data = await thumbnail.toByteData(format: ui.ImageByteFormat.rawRgba);
    thumbnail.dispose();

    if (data == null || data.lengthInBytes < 4) {
      return _ArtworkTheme.fallback(widget.accentColor, widget.panelColor);
    }

    final samples = <_ColorSample>[];
    for (var offset = 0; offset + 3 < data.lengthInBytes; offset += 4) {
      final alpha = data.getUint8(offset + 3);
      if (alpha < 180) continue;

      final color = Color.fromARGB(
        255,
        data.getUint8(offset),
        data.getUint8(offset + 1),
        data.getUint8(offset + 2),
      );
      final hsl = HSLColor.fromColor(color);
      if (hsl.lightness < .08) continue;
      if (hsl.saturation < .10 && hsl.lightness > .20 && hsl.lightness < .85) {
        continue;
      }

      final saturationScore = hsl.saturation.clamp(0.0, 1.0).toDouble();
      final lightnessScore =
          1 - ((hsl.lightness - .52).abs() / .52)
              .clamp(0.0, 1.0)
              .toDouble();
      samples.add(
        _ColorSample(color, saturationScore * .65 + lightnessScore * .35),
      );
    }

    if (samples.isEmpty) {
      return _ArtworkTheme.fallback(widget.accentColor, widget.panelColor);
    }

    samples.sort((a, b) => b.score.compareTo(a.score));
    final primary = _prepareThemeColor(samples.first.color);
    var secondary = primary;
    for (final sample in samples.skip(1)) {
      final candidate = _prepareThemeColor(sample.color);
      if (_colorDistance(primary, candidate) > .18) {
        secondary = candidate;
        break;
      }
    }
    if (secondary == primary) {
      final hsl = HSLColor.fromColor(primary);
      secondary = hsl
          .withLightness((hsl.lightness + .12).clamp(0.0, 1.0).toDouble())
          .toColor();
    }

    final darkHsl = HSLColor.fromColor(primary);
    final dark = darkHsl
        .withLightness(.07)
        .withSaturation(
          (darkHsl.saturation * .75).clamp(0.0, 1.0).toDouble(),
        )
        .toColor();
    return _ArtworkTheme(primary, secondary, dark);
  }

  Color _prepareThemeColor(Color color) {
    final hsl = HSLColor.fromColor(color);
    final saturation = hsl.saturation.clamp(.35, .90).toDouble();
    final lightness = hsl.lightness < .30
        ? .48
        : hsl.lightness > .78
        ? .62
        : hsl.lightness;
    return hsl.withSaturation(saturation).withLightness(lightness).toColor();
  }

  double _colorDistance(Color a, Color b) {
    final ahsl = HSLColor.fromColor(a);
    final bhsl = HSLColor.fromColor(b);
    final hueDistance = (ahsl.hue - bhsl.hue).abs() / 360;
    return hueDistance * .5 +
        (ahsl.saturation - bhsl.saturation).abs() * .3 +
        (ahsl.lightness - bhsl.lightness).abs() * .2;
  }

  Widget _iconButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
    required Color color,
    double iconSize = 20,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
      padding: EdgeInsets.zero,
      splashRadius: 19,
      icon: Icon(icon, size: iconSize, color: color),
    );
  }

  Widget _buildPlaybackControls({
    required double availableWidth,
    required bool hasTrack,
    required bool loading,
    required Color accentColor,
    required Color playButtonColor,
    required bool shuffleEnabled,
    required bool loopEnabled,
  }) {
    final showShuffle = availableWidth >= 270 && widget.onToggleShuffle != null;
    final showLoop = availableWidth >= 220;

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Keep the play/pause button centered when the available width is
        // enough for loop but not for shuffle.
        if (showLoop && !showShuffle) const SizedBox(width: 43),
        if (showShuffle)
          _iconButton(
            tooltip: shuffleEnabled
                ? 'Desactivar aleatorio'
                : 'Reproducción aleatoria',
            icon: CupertinoIcons.shuffle,
            onPressed: widget.onToggleShuffle,
            color: shuffleEnabled ? accentColor : _iconColor,
            iconSize: 20,
          ),
        if (showShuffle) const SizedBox(width: 5),
        _iconButton(
          tooltip: 'Anterior',
          icon: CupertinoIcons.backward_end,
          onPressed: widget.onPrevious,
          color: _iconColor,
          iconSize: 24,
        ),
        const SizedBox(width: 5),
        StreamBuilder<bool>(
          stream: widget.playingStream,
          initialData: widget.initialPlaying,
          builder: (context, snapshot) {
            final playing = snapshot.data ?? false;

            return SizedBox(
              width: 36,
              height: 36,
              child: Material(
                color: playButtonColor,
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: () => widget.onTogglePlayback(playing),
                  customBorder: const CircleBorder(),
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: Center(
                      child: loading
                          ? const SizedBox(
                              width: 17,
                              height: 17,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF0B0B12),
                              ),
                            )
                          : Icon(
                              !hasTrack
                                  ? CupertinoIcons.add
                                  : playing
                                  ? CupertinoIcons.pause_fill
                                  : Icons.play_arrow_rounded,
                              color: hasTrack
                                  ? const Color(0xFF0B0B12)
                                  : widget.accentColor,
                              size: 24,
                            ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(width: 5),
        _iconButton(
          tooltip: 'Siguiente',
          icon: CupertinoIcons.forward_end,
          onPressed: widget.onNext,
          color: _iconColor,
          iconSize: 24,
        ),
        if (showLoop) const SizedBox(width: 5),
        if (showLoop)
          _iconButton(
            tooltip: loopEnabled ? 'Desactivar bucle' : 'Activar bucle',
            icon: CupertinoIcons.repeat,
            onPressed: widget.onToggleLoop,
            color: loopEnabled ? accentColor : _iconColor,
            iconSize: 20,
          ),
      ],
    );
  }

  Widget _buildProgressBar(Color mutedColor, Color accentColor) {
    final duration = widget.duration;
    final position = widget.position;

    final progress = duration == null || duration.inMilliseconds <= 0
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 30,
          child: Text(
            widget.positionLabel,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: mutedColor,
              fontSize: 9,
              fontFeatures: const [],
              height: 1.0,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ProgressTrack(
            progress: progress,
            accentColor: accentColor,
            onSeek: widget.onSeek == null || duration == null
                ? null
                : (value) {
                    widget.onSeek!(
                      Duration(
                        milliseconds: (duration.inMilliseconds * value).round(),
                      ),
                    );
                  },
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 30,
          child: Text(
            widget.durationLabel,
            textAlign: TextAlign.left,
            style: TextStyle(
              color: mutedColor,
              fontSize: 9,
              height: 1.0,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRightControls({
    required bool narrowWindow,
    required bool compact,
    required Color accentColor,
    required Color mutedColor,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (!narrowWindow) ...[
          _iconButton(
            tooltip: 'Letras',
            icon: Icons.lyrics_outlined,
            onPressed: () => _showUnavailable(context, 'Letras'),
            color: _controlColor,
            iconSize: 20,
          ),
          const SizedBox(width: 5),
        ],
        _iconButton(
          tooltip: widget.queueOpen ? 'Ocultar cola' : 'Ver cola',
          icon: Icons.queue_music,
          onPressed: widget.onToggleQueue,
          color: widget.queueOpen ? accentColor : _controlColor,
          iconSize: 21,
        ),
        const SizedBox(width: 5),
        _iconButton(
          tooltip: 'Dispositivo de reproducción',
          icon: Icons.devices,
          onPressed: () => _showUnavailable(context, 'Dispositivos'),
          color: const Color(0xFFE2E2EA),
          iconSize: 21,
        ),
        if (!compact && !narrowWindow) ...[
          const SizedBox(width: 5),
          Icon(Icons.volume_up_outlined, size: 20, color: _controlColor),
          SizedBox(
            width: 90,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                activeTrackColor: accentColor,
                inactiveTrackColor: Colors.white.withValues(alpha: .17),
                thumbColor: accentColor,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Overlay.wrap(
                alwaysSizeToContent: true,
                clipBehavior: Clip.none,
                child: Slider(
                  value: widget.volume,
                  onChanged: widget.onVolumeChanged,
                ),
              ),
            ),
          ),
        ],
        if (!narrowWindow) ...[
          const SizedBox(width: 5),
          _iconButton(
            tooltip: widget.windowMaximized
                ? 'Restaurar ventana'
                : 'Maximizar ventana',
            icon: widget.windowMaximized
                ? CupertinoIcons.fullscreen_exit
                : CupertinoIcons.fullscreen,
            onPressed: widget.onToggleWindowSize,
            color: _controlColor,
            iconSize: 20,
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final narrowWindow = MediaQuery.sizeOf(context).width < 700;
    final compact = widget.compact;
    final hasTrack = widget.hasTrack;
    final mutedColor = widget.mutedColor;
    final panelColor = widget.panelColor;

    final accentColor = hasTrack
        ? _artworkColor ?? widget.accentColor
        : const Color(0xFF747484);

    final playButtonColor = hasTrack ? accentColor : const Color(0xFF292936);

    final darkArtworkColor = _artworkDarkColor ?? panelColor;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      height: compact ? 66 : 78,
      padding: EdgeInsets.symmetric(horizontal: compact ? 7 : 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accentColor.withValues(alpha: hasTrack ? .10 : .035),
            darkArtworkColor.withValues(alpha: hasTrack ? .18 : .035),
            (_artworkSecondaryColor ?? accentColor).withValues(
              alpha: hasTrack ? .07 : .025,
            ),
          ],
          stops: const [0, .48, 1],
        ),
        border: Border.all(
          color: accentColor.withValues(alpha: hasTrack ? .16 : .07),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: hasTrack ? .08 : .02),
            blurRadius: 30,
            spreadRadius: -5,
            offset: const Offset(0, 9),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: .25),
            blurRadius: 20,
            spreadRadius: -5,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: narrowWindow ? 100 : (compact ? 180 : 300),
            child: Row(
              children: [
                SizedBox(
                  width: compact ? 38 : 50,
                  height: compact ? 38 : 50,
                  child: widget.cover,
                ),
                SizedBox(width: compact ? 7 : 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: compact ? 10 : 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: mutedColor,
                          fontSize: compact ? 8 : 10,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.onToggleFavorite != null)
                  _iconButton(
                    tooltip: 'Favorito',
                    icon: widget.isFavorite
                        ? CupertinoIcons.heart_fill
                        : CupertinoIcons.heart,
                    onPressed: widget.onToggleFavorite,
                    color: widget.isFavorite ? accentColor : mutedColor,
                    iconSize: 17,
                  ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  fit: StackFit.expand,
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      bottom: 12,
                      child: Center(
                        child: _buildPlaybackControls(
                          availableWidth: constraints.maxWidth,
                          hasTrack: hasTrack,
                          loading: widget.loading,
                          accentColor: accentColor,
                          playButtonColor: playButtonColor,
                          shuffleEnabled: widget.shuffleEnabled,
                          loopEnabled: widget.loopEnabled,
                        ),
                      ),
                    ),
                    if (!compact &&
                        !narrowWindow &&
                        constraints.maxWidth >= 360)
                      Positioned(
                        left: constraints.maxWidth * .10,
                        right: constraints.maxWidth * .10,
                        bottom: 6,
                        child: _buildProgressBar(mutedColor, accentColor),
                      ),
                  ],
                );
              },
            ),
          ),
          SizedBox(
            width: narrowWindow ? 100 : (compact ? 180 : 300),
            child: _buildRightControls(
              narrowWindow: narrowWindow,
              compact: compact,
              accentColor: accentColor,
              mutedColor: mutedColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressTrack extends StatefulWidget {
  const _ProgressTrack({
    required this.progress,
    required this.accentColor,
    required this.onSeek,
  });

  final double progress;
  final Color accentColor;
  final ValueChanged<double>? onSeek;

  @override
  State<_ProgressTrack> createState() => _ProgressTrackState();
}

class _ProgressTrackState extends State<_ProgressTrack> {
  bool _isHovered = false;

  void update(Offset localPosition, double width) {
    if (widget.onSeek == null || width <= 0) return;

    widget.onSeek!((localPosition.dx / width).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: widget.onSeek == null
                ? null
                : (details) =>
                      update(details.localPosition, constraints.maxWidth),
            onHorizontalDragUpdate: widget.onSeek == null
                ? null
                : (details) =>
                      update(details.localPosition, constraints.maxWidth),
            child: SizedBox(
              height: 12,
              child: CustomPaint(
                painter: _ProgressTrackPainter(
                  widget.progress,
                  _isHovered,
                  widget.accentColor,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ProgressTrackPainter extends CustomPainter {
  const _ProgressTrackPainter(this.progress, this.isHovered, this.accentColor);

  final double progress;
  final bool isHovered;
  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;

    final track = Paint()
      ..color = Colors.white.withValues(alpha: .5)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    final active = Paint()
      ..color = isHovered ? accentColor : Colors.white
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), track);

    final activeX = size.width * progress.clamp(0.0, 1.0);

    canvas.drawLine(Offset(0, centerY), Offset(activeX, centerY), active);

    // Only show thumb when hovered
    if (isHovered) {
      canvas.drawCircle(
        Offset(activeX, centerY),
        5,
        active..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ProgressTrackPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isHovered != isHovered ||
        oldDelegate.accentColor != accentColor;
  }
}

class _ArtworkTheme {
  const _ArtworkTheme(this.primary, this.secondary, this.dark);

  factory _ArtworkTheme.fallback(Color accent, Color panel) =>
      _ArtworkTheme(accent, accent.withValues(alpha: .75), panel);

  final Color primary;
  final Color secondary;
  final Color dark;
}

class _ColorSample {
  const _ColorSample(this.color, this.score);

  final Color color;
  final double score;
}
