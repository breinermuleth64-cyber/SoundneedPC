import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals, ValueListenable;
import 'package:flutter/material.dart';

import '../models/track.dart';
import '../services/explore_discovery_service.dart';
import '../widgets/library_content.dart';
import '../widgets/middle_content_panel.dart';

class ExplorePage extends StatelessWidget {
  const ExplorePage({
    required this.config,
    required this.track,
    required this.onlineArtwork,
    required this.spectrum,
    required this.onPrevious,
    required this.onNext,
    required this.onBackToDiscoveries,
    required this.recommendations,
    required this.recommendationsLoading,
    required this.onPlayRecommendation,
    required this.canGoPrevious,
    required this.canGoNext,
    super.key,
  });

  final LibraryPageConfig config;
  final Track? track;
  final String? onlineArtwork;
  final ValueListenable<List<double>> spectrum;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onBackToDiscoveries;
  final List<ExploreRecommendation> recommendations;
  final bool recommendationsLoading;
  final ValueChanged<ExploreRecommendation> onPlayRecommendation;
  final bool canGoPrevious;
  final bool canGoNext;

  static const _cyan = Color(0xFF83E8FF);

  @override
  Widget build(BuildContext context) => MiddleContentPanel(
    section: 'Explorar',
    config: config,
    showHeader: false,
    body: LayoutBuilder(
      builder: (context, constraints) {
        final artwork = track?.coverPath;
        final remoteArtwork = onlineArtwork;
        final ImageProvider<Object>? artworkProvider =
            artwork != null && artwork.isNotEmpty
            ? FileImage(File(artwork))
            : remoteArtwork != null && remoteArtwork.isNotEmpty
            ? NetworkImage(remoteArtwork)
            : null;

        final coverSize = (constraints.maxWidth - 224)
            .clamp(72.0, 300.0)
            .toDouble();

        const spectrumMargin = 52.0;
        const arrowSpacing = 12.0;

        final visualizerSize = coverSize + spectrumMargin * 2;
        const arrowHeight = 108.0;

        return Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'PARA TI, AL AZAR',
                        style: TextStyle(
                          color: _cyan,
                          fontSize: 11,
                          letterSpacing: 2.2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: onBackToDiscoveries,
                        icon: const Icon(Icons.arrow_back_rounded, size: 17),
                        label: const Text('Descubrimientos'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white70,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: constraints.maxWidth,
                  height: math.max(visualizerSize, arrowHeight).toDouble(),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Center(
                        child: RepaintBoundary(
                          child: ValueListenableBuilder<List<double>>(
                            valueListenable: spectrum,
                            builder: (context, spectrumValues, _) =>
                                _ReactiveAlbumCover(
                                  size: coverSize,
                                  spectrumMargin: spectrumMargin,
                                  spectrum: spectrumValues,
                                  artworkProvider: artworkProvider,
                                  placeholder: _coverPlaceholder(coverSize),
                                ),
                              ),
                        ),
                      ),
                      Positioned(
                        left:
                            constraints.maxWidth / 2 +
                            coverSize / 2 +
                            spectrumMargin +
                            arrowSpacing,
                        top: (visualizerSize - arrowHeight) / 2,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _ArrowButton(
                              icon: Icons.keyboard_arrow_up_rounded,
                              tooltip: 'Canción anterior',
                              enabled: canGoPrevious,
                              onPressed: onPrevious,
                            ),
                            const SizedBox(height: arrowSpacing),
                            _ArrowButton(
                              icon: Icons.keyboard_arrow_down_rounded,
                              tooltip: 'Siguiente canción',
                              enabled: canGoNext,
                              onPressed: onNext,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: constraints.maxWidth,
                  child: _ExploreRecommendations(
                    recommendations: recommendations,
                    loading: recommendationsLoading,
                    onPlay: onPlayRecommendation,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );

  static Widget _coverPlaceholder(double size) => Container(
    color: const Color(0xFF111722),
    alignment: Alignment.center,
    child: Icon(Icons.music_note_rounded, color: _cyan, size: size * .3),
  );
}

class _ExploreRecommendations extends StatelessWidget {
  const _ExploreRecommendations({
    required this.recommendations,
    required this.loading,
    required this.onPlay,
  });

  final List<ExploreRecommendation> recommendations;
  final bool loading;
  final ValueChanged<ExploreRecommendation> onPlay;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SIGUE DESCUBRIENDO',
              style: TextStyle(
                color: Color(0xFF83E8FF),
                fontSize: 10,
                letterSpacing: 2,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Del artista, colaboraciones y artistas relacionados',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      if (loading && recommendations.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 26, vertical: 16),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF83E8FF),
                ),
              ),
              SizedBox(width: 10),
              Text(
                'Buscando canciones para ti…',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
          ),
        )
      else if (recommendations.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 26, vertical: 16),
          child: Text(
            'Aún no encontramos canciones relacionadas. Sigue escuchando y vuelve a intentarlo.',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
        )
      else
        SizedBox(
          height: 190,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 26),
            scrollDirection: Axis.horizontal,
            itemCount: recommendations.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final item = recommendations[index];
              return SizedBox(
                width: 142,
                child: InkWell(
                  onTap: () => onPlay(item),
                  borderRadius: BorderRadius.circular(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            width: 142,
                            child: item.artworkUrl.isEmpty
                                ? _recommendationPlaceholder()
                                : Image.network(
                                    item.artworkUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) =>
                                        _recommendationPlaceholder(),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        item.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
    ],
  );

  Widget _recommendationPlaceholder() => Container(
    color: const Color(0xFF20232B),
    alignment: Alignment.center,
    child: const Icon(Icons.music_note_rounded, color: Colors.white54),
  );
}

class _ReactiveAlbumCover extends StatefulWidget {
  const _ReactiveAlbumCover({
    required this.size,
    required this.spectrumMargin,
    required this.spectrum,
    required this.artworkProvider,
    required this.placeholder,
  });

  final double size;
  final double spectrumMargin;
  final List<double> spectrum;
  final ImageProvider<Object>? artworkProvider;
  final Widget placeholder;

  @override
  State<_ReactiveAlbumCover> createState() => _ReactiveAlbumCoverState();
}

class _ReactiveAlbumCoverState extends State<_ReactiveAlbumCover> {
  ImageStream? _imageStream;
  ImageStreamListener? _imageListener;
  Color? _coverAccent;
  bool _extractingAccent = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveArtwork();
  }

  @override
  void didUpdateWidget(covariant _ReactiveAlbumCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.artworkProvider != widget.artworkProvider) {
      _coverAccent = null;
      _extractingAccent = false;
      _resolveArtwork();
    }
  }

  void _resolveArtwork() {
    final provider = widget.artworkProvider;
    if (provider == null) return;
    final stream = provider.resolve(createLocalImageConfiguration(context));
    if (_imageStream?.key == stream.key) return;
    if (_imageStream != null && _imageListener != null) {
      _imageStream!.removeListener(_imageListener!);
    }
    _imageStream = stream;
    _imageListener = ImageStreamListener((info, _) {
      if (_coverAccent == null && !_extractingAccent) {
        _extractingAccent = true;
        _extractAccent(info.image);
      }
    });
    stream.addListener(_imageListener!);
  }

  Future<void> _extractAccent(ui.Image image) async {
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (!mounted || data == null) return;
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final strideX = math.max(1, image.width ~/ 28).toInt();
      final strideY = math.max(1, image.height ~/ 28).toInt();
      var red = 0.0;
      var green = 0.0;
      var blue = 0.0;
      var totalWeight = 0.0;
      for (var y = 0; y < image.height; y += strideY) {
        for (var x = 0; x < image.width; x += strideX) {
          final offset = (y * image.width + x) * 4;
          if (offset + 3 >= bytes.length || bytes[offset + 3] < 180) continue;
          final r = bytes[offset];
          final g = bytes[offset + 1];
          final b = bytes[offset + 2];
          final hsl = HSLColor.fromColor(Color.fromARGB(255, r, g, b));
          if (hsl.saturation < .14 ||
              hsl.lightness < .12 ||
              hsl.lightness > .9) {
            continue;
          }
          final weight = hsl.saturation * (1 - (hsl.lightness - .56).abs());
          red += r * weight;
          green += g * weight;
          blue += b * weight;
          totalWeight += weight;
        }
      }
      if (totalWeight <= 0) return;
      setState(() {
        _coverAccent = Color.fromARGB(
          255,
          (red / totalWeight).round().clamp(0, 255).toInt(),
          (green / totalWeight).round().clamp(0, 255).toInt(),
          (blue / totalWeight).round().clamp(0, 255).toInt(),
        );
      });
    } catch (_) {
      // Keep the app theme color if the cover cannot be sampled.
    } finally {
      _extractingAccent = false;
    }
  }

  @override
  void dispose() {
    if (_imageStream != null && _imageListener != null) {
      _imageStream!.removeListener(_imageListener!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = _coverAccent ?? Theme.of(context).colorScheme.primary;
    final artwork = widget.artworkProvider == null
        ? widget.placeholder
        : Image(
            image: widget.artworkProvider!,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => widget.placeholder,
          );
    return TweenAnimationBuilder<List<double>>(
      tween: _SpectrumTween(
        begin: List<double>.filled(widget.spectrum.length, 0.0),
        end: widget.spectrum,
      ),
      duration: const Duration(milliseconds: 65),
      curve: Curves.easeOutCubic,
      builder: (context, animatedSpectrum, _) {
        return SizedBox(
          width: widget.size + widget.spectrumMargin * 2,
          height: widget.size + widget.spectrumMargin * 2,
          child: CustomPaint(
            painter: _LiquidBlobPainter(animatedSpectrum, accentColor),
            child: Center(
              child: Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: accentColor.withValues(alpha: .82),
                    width: 1.25,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black54,
                      blurRadius: 28,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: ClipOval(child: artwork),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LiquidBlobPainter extends CustomPainter {
  const _LiquidBlobPainter(this.spectrum, this.accentColor);

  final List<double> spectrum;
  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.shortestSide / 2 - 52.0;

    if (baseRadius <= 0) return;

    final safeSpectrum = spectrum
        .where((value) => value.isFinite)
        .map((value) => value.clamp(0.0, 1.0).toDouble())
        .toList(growable: false);

    final level = _averageLevel(safeSpectrum);
    final peak = _peakLevel(safeSpectrum);
    final deepAccent = Color.lerp(accentColor, Colors.black, .78)!;
    final darkAccent = Color.lerp(accentColor, Colors.black, .36)!;
    final lightAccent = Color.lerp(accentColor, Colors.white, .24)!;

    // The organic edge is continuous, not a collection of visible bars.
    const pointCount = 144;
    final radii = List<double>.generate(pointCount, (index) {
      final angle = index / pointCount * math.pi * 2 - math.pi / 2;
      final audio = _sampleSpectrum(safeSpectrum, index / pointCount);

      final previous = _sampleSpectrum(safeSpectrum, (index - 1) / pointCount);
      final next = _sampleSpectrum(safeSpectrum, (index + 1) / pointCount);

      // Smooth neighboring frequencies without flattening the reaction.
      final smooth = audio * .60 + previous * .20 + next * .20;

      // Low-amplitude movement remains visible when the song is quiet.
      final organicShape =
          math.sin(angle * 3 + .7) * .035 +
          math.sin(angle * 5 - 1.3) * .022 +
          math.sin(angle * 7 + 2.0) * .012;

      final audioDisplacement = smooth * 43.0;
      final quietMovement = level * 5.0;

      return baseRadius +
          7.0 +
          quietMovement +
          audioDisplacement +
          organicShape * 14.0;
    }, growable: false);

    final blobPath = _buildSmoothBlob(center, radii);

    final bounds = Rect.fromCircle(center: center, radius: baseRadius + 58);

    // Layer 1: broad, diffuse atmospheric glow.
    canvas.drawPath(
      blobPath,
      Paint()
        ..style = PaintingStyle.fill
        ..color = accentColor.withValues(alpha: .34 + peak * .20)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30),
    );

    // Layer 2: a deep shade of the current theme color.
    canvas.drawPath(
      blobPath,
      Paint()
        ..style = PaintingStyle.fill
        ..shader = ui.Gradient.radial(
          center,
          baseRadius + 60,
          [
            deepAccent.withValues(alpha: .12),
            darkAccent.withValues(alpha: .64),
            accentColor.withValues(alpha: .82),
            darkAccent.withValues(alpha: .12),
          ],
          const [0.0, .53, .79, 1.0],
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // Layer 3: the actual liquid mass.
    canvas.drawPath(
      blobPath,
      Paint()
        ..style = PaintingStyle.fill
        ..shader = ui.Gradient.radial(
          center,
          bounds.width * .49,
          [
            deepAccent.withValues(alpha: .08),
            darkAccent.withValues(alpha: .78),
            accentColor.withValues(alpha: .94),
            lightAccent.withValues(alpha: .96),
            darkAccent.withValues(alpha: .72),
          ],
          const [0.0, .43, .66, .82, 1.0],
        ),
    );

    // Layer 4: soft highlights in the current theme color.
    canvas.drawPath(
      blobPath,
      Paint()
        ..style = PaintingStyle.fill
        ..color = accentColor.withValues(alpha: .20 + peak * .20)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );

    // Small points of light give the effect depth without creating bars.
    _drawParticles(
      canvas,
      center,
      baseRadius,
      level,
      peak,
      accentColor,
      lightAccent,
    );
  }

  double _sampleSpectrum(List<double> values, double position) {
    if (values.isEmpty) return 0.0;
    if (values.length == 1) return values.first;

    final normalized = position - position.floorToDouble();
    final scaled = normalized * values.length;
    final index = scaled.floor() % values.length;
    final next = (index + 1) % values.length;
    final fraction = scaled - scaled.floor();

    return values[index] * (1 - fraction) + values[next] * fraction;
  }

  double _averageLevel(List<double> values) {
    if (values.isEmpty) return 0.0;

    var total = 0.0;
    for (final value in values) {
      total += value;
    }

    return (total / values.length).clamp(0.0, 1.0).toDouble();
  }

  double _peakLevel(List<double> values) {
    var peak = 0.0;

    for (final value in values) {
      if (value > peak) peak = value;
    }

    return peak.clamp(0.0, 1.0).toDouble();
  }

  Path _buildSmoothBlob(Offset center, List<double> radii) {
    final count = radii.length;
    final points = List<Offset>.generate(count, (index) {
      final angle = index / count * math.pi * 2 - math.pi / 2;

      return Offset(
        center.dx + math.cos(angle) * radii[index],
        center.dy + math.sin(angle) * radii[index],
      );
    }, growable: false);

    // Midpoints and quadratic curves create a continuous, liquid contour.
    final path = Path();
    final firstMid = Offset(
      (points[0].dx + points[1].dx) / 2,
      (points[0].dy + points[1].dy) / 2,
    );

    path.moveTo(firstMid.dx, firstMid.dy);

    for (var index = 1; index < count; index++) {
      final current = points[index];
      final next = points[(index + 1) % count];
      final midpoint = Offset(
        (current.dx + next.dx) / 2,
        (current.dy + next.dy) / 2,
      );

      path.quadraticBezierTo(current.dx, current.dy, midpoint.dx, midpoint.dy);
    }

    path.close();
    return path;
  }

  void _drawParticles(
    Canvas canvas,
    Offset center,
    double baseRadius,
    double level,
    double peak,
    Color accentColor,
    Color lightAccent,
  ) {
    const count = 42;

    for (var index = 0; index < count; index++) {
      // Fixed positions prevent particles from randomly flickering.
      final angle = index * 2.399963229728653;
      final variation = ((index * 37) % 101) / 100.0;
      final radius = baseRadius + 29 + variation * 24 + level * 5;

      final position = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );

      final particleSize = .45 + variation * 1.35;
      final alpha = (.12 + variation * .38 + peak * .30)
          .clamp(0.0, .8)
          .toDouble();

      canvas.drawCircle(
        position,
        particleSize,
        Paint()
          ..color = (index.isEven ? accentColor : lightAccent).withValues(
            alpha: alpha,
          ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LiquidBlobPainter oldDelegate) =>
      !listEquals(oldDelegate.spectrum, spectrum) ||
      oldDelegate.accentColor != accentColor;
}

class _SpectrumTween extends Tween<List<double>> {
  _SpectrumTween({required super.begin, required super.end});

  @override
  List<double> lerp(double t) {
    final start = begin ?? const <double>[];
    final finish = end ?? const <double>[];

    if (finish.isEmpty) return const <double>[];
    if (start.isEmpty) {
      return List<double>.filled(finish.length, 0.0);
    }

    return List<double>.generate(finish.length, (index) {
      final startValue = start[index % start.length];
      final endValue = finish[index];

      return startValue + (endValue - startValue) * t;
    }, growable: false);
  }
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: enabled
          ? const Color(0xFF17171D)
          : const Color(0xFF17171D).withValues(alpha: .45),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: enabled ? onPressed : null,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(
            icon,
            color: enabled ? Colors.white : Colors.white38,
            size: 28,
          ),
        ),
      ),
    ),
  );
}
