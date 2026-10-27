import 'package:flutter/material.dart';

import '../widgets/library_content.dart';
import '../widgets/middle_content_panel.dart';
import '../widgets/online_search_results.dart';
import '../services/home_discovery_service.dart';
import '../widgets/home_podcast_section.dart';

class HomeOnlineSection {
  const HomeOnlineSection({
    required this.title,
    required this.subtitle,
    required this.results,
    required this.loading,
    required this.error,
    required this.onRefresh,
    required this.onPlay,
    this.ranked = false,
  });

  final String title;
  final String subtitle;
  final List<OnlineSearchResult> results;
  final bool loading;
  final String? error;
  final VoidCallback onRefresh;
  final ValueChanged<int> onPlay;
  final bool ranked;
}

class HomePage extends StatelessWidget {
  const HomePage({
    required this.config,
    required this.colombiaChart,
    required this.worldChart,
    required this.discoverMusic,
    required this.onPlayPodcast,
    this.topTrack,
    this.onPlayTopTrack,
    required this.playingVideoId,
    required this.isPlaying,
    required this.loadingVideoId,
    required this.continueTitle,
    required this.continueArtist,
    required this.onContinue,
    required this.stationArtists,
    required this.onSurpriseMix,
    required this.onPlayStation,
    required this.onNavigate,
    super.key,
  });

  final LibraryPageConfig config;
  final HomeOnlineSection colombiaChart;
  final HomeOnlineSection worldChart;
  final HomeOnlineSection discoverMusic;
  final ValueChanged<HomePodcastPlayRequest> onPlayPodcast;
  final OnlineSearchResult? topTrack;
  final VoidCallback? onPlayTopTrack;
  final String? playingVideoId;
  final bool isPlaying;
  final String? loadingVideoId;
  final String? continueTitle;
  final String? continueArtist;
  final VoidCallback? onContinue;
  final List<String> stationArtists;
  final VoidCallback onSurpriseMix;
  final ValueChanged<String> onPlayStation;
  final ValueChanged<String> onNavigate;

  static const Color _accent = Color(0xFFF4F3EF);
  static const Color _muted = Color(0xFF969696);
  static const Color _surface = Color(0xFF191919);

  @override
  Widget build(BuildContext context) {
    return MiddleContentPanel(
      section: 'Inicio',
      config: config,
      showHeader: false,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 700;
          final gap = compact ? 24.0 : 32.0;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _welcome(compact),
              SizedBox(height: compact ? 18 : 24),
              _selectionOfDay(compact),
              SizedBox(height: compact ? 20 : 26),
              _musicSection(
                discoverMusic,
                eyebrow: 'PRIMERA FILA · PARA TI',
                compact: compact,
                featured: true,
              ),
              const SizedBox(height: 14),
              _quickActions(),
              SizedBox(height: gap),
              _musicSection(
                colombiaChart,
                eyebrow: 'SONIDO LOCAL',
                compact: compact,
              ),
              SizedBox(height: gap),
              _musicSection(
                worldChart,
                eyebrow: 'ALREDEDOR DEL MUNDO',
                compact: compact,
              ),
              SizedBox(height: gap),
              HomePodcastSection(onPlay: onPlayPodcast),
              if (stationArtists.isNotEmpty) ...[
                SizedBox(height: gap),
                _stationsSection(),
              ],
              if (config.trackCount > 0) ...[
                SizedBox(height: gap),
                _sectionHeading(
                  eyebrow: 'TU COLECCIÓN',
                  title: 'Tu biblioteca',
                  subtitle: '${config.trackCount} canciones listas para sonar',
                ),
                const SizedBox(height: 18),
              ],
              config.body,
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  Widget _welcome(bool compact) {
    final now = DateTime.now();
    final greeting = now.hour < 12
        ? 'Buenos días'
        : now.hour < 19
        ? 'Buenas tardes'
        : 'Buenas noches';
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 620),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 13 * (1 - value)),
          child: child,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$greeting${compact ? '' : '.'}',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 31 : 38,
                    height: 1.05,
                    letterSpacing: -1.4,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _searchAction(),
        ],
      ),
    );
  }

  Widget _searchAction() {
    return Tooltip(
      message: 'Buscar música',
      child: Material(
        color: Colors.white.withValues(alpha: .045),
        shape: const CircleBorder(),
        child: InkWell(
          onTap: () => onNavigate('Buscar'),
          customBorder: const CircleBorder(),
          child: const SizedBox(
            width: 40,
            height: 40,
            child: Icon(Icons.search_rounded, color: Colors.white, size: 18),
          ),
        ),
      ),
    );
  }

  HomeOnlineSection get _dailySelectionSource =>
      discoverMusic.results.isNotEmpty ||
          discoverMusic.loading ||
          discoverMusic.error != null
      ? discoverMusic
      : colombiaChart;

  Widget _selectionOfDay(bool compact) {
    final source = _dailySelectionSource;
    final result =
        topTrack ?? (source.results.isNotEmpty ? source.results.first : null);
    final selected = result?.videoId == playingVideoId;
    final loading = result != null && result.videoId == loadingVideoId;

    return LayoutBuilder(
      builder: (context, constraints) {
        final artWidth = compact
            ? constraints.maxWidth < 360
                  ? 110.0
                  : constraints.maxWidth < 520
                  ? 145.0
                  : 172.0
            : 224.0;
        final artHeight = artWidth;

        return Container(
          padding: EdgeInsets.all(compact ? 15 : 22),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.white.withValues(alpha: .07)),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF222222), Color(0xFF191919), Color(0xFF161616)],
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 24,
                offset: Offset(0, 11),
              ),
            ],
          ),
          child: Row(
            children: [
              SizedBox(
                width: artWidth,
                height: artHeight,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(19),
                      child: result == null
                          ? _artFallback(loading: source.loading)
                          : Image.network(
                              result.thumbnail,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  _artFallback(),
                            ),
                    ),
                    if (result != null)
                      const Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color(0x08000000),
                                Color(0x00000000),
                                Color(0x48000000),
                              ],
                            ),
                          ),
                        ),
                      ),
                    if (selected && topTrack == null)
                      Positioned(left: 7, top: 7, child: _playingBadge()),
                    if (topTrack?.rank != null)
                      Positioned(
                        left: 7,
                        top: 7,
                        child: _rankBadge(topTrack!.rank!),
                      ),
                    if (result != null)
                      Positioned(
                        right: 7,
                        bottom: 7,
                        child: Material(
                          color: _accent,
                          shape: const CircleBorder(),
                          child: InkWell(
                            onTap: loading
                                ? null
                                : topTrack != null
                                ? onPlayTopTrack
                                : () => source.onPlay(0),
                            customBorder: const CircleBorder(),
                            child: SizedBox(
                              width: compact ? 36 : 42,
                              height: compact ? 36 : 42,
                              child: Center(
                                child: loading
                                    ? const SizedBox(
                                        width: 13,
                                        height: 13,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Color(0xFF171717),
                                        ),
                                      )
                                    : Icon(
                                        selected && isPlaying
                                            ? Icons.equalizer_rounded
                                            : Icons.play_arrow_rounded,
                                        color: const Color(0xFF171717),
                                        size: compact ? 23 : 27,
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(width: compact ? 15 : 26),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 5,
                          height: 5,
                          decoration: const BoxDecoration(
                            color: _accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          'SELECCIÓN DE HOY',
                          style: TextStyle(
                            color: _muted,
                            fontSize: compact ? 9 : 10,
                            letterSpacing: 1.25,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: compact ? 11 : 15),
                    Text(
                      result?.title ?? 'Una canción para tu momento.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: compact ? 18 : 27,
                        height: 1.1,
                        letterSpacing: -.7,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: compact ? 7 : 9),
                    Text(
                      result?.artist ??
                          (source.loading
                              ? 'Preparando tu recomendación…'
                              : source.error ??
                                    'Una recomendación para empezar el día.'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _muted,
                        fontSize: compact ? 11 : 13,
                      ),
                    ),
                    SizedBox(height: compact ? 13 : 18),
                    if (result != null && result.durationSeconds > 0)
                      Row(
                        children: [
                          Text(
                            _durationLabel(result.durationSeconds),
                            style: const TextStyle(
                              color: Color(0xFFB8B8B8),
                              fontSize: 9,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      )
                    else if (!source.loading)
                      TextButton.icon(
                        onPressed: source.onRefresh,
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          foregroundColor: _accent,
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.refresh_rounded, size: 15),
                        label: const Text(
                          'Actualizar selección',
                          style: TextStyle(fontSize: 9),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _durationLabel(int seconds) {
    if (seconds <= 0) return 'Duración no disponible';
    final minutes = seconds ~/ 60;
    final remainder = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$remainder min';
  }

  Widget _quickActions() {
    final actions = <Widget>[
      if (onContinue != null)
        _quickAction(
          icon: Icons.history_rounded,
          eyebrow: '',
          title: continueTitle ?? 'Seguir escuchando',
          subtitle: continueArtist ?? '',
          trailing: Icons.arrow_forward_rounded,
          onTap: onContinue!,
        ),
      _quickAction(
        icon: Icons.shuffle_rounded,
        eyebrow: '',
        title: 'Mezcla sorpresa',
        subtitle: '',
        trailing: Icons.auto_awesome_rounded,
        onTap: onSurpriseMix,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 540 && actions.length > 1) {
          return Column(
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(height: 11),
                SizedBox(width: double.infinity, child: actions[i]),
              ],
            ],
          );
        }
        return Row(
          children: [
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(child: actions[i]),
            ],
          ],
        );
      },
    );
  }

  Widget _quickAction({
    required IconData icon,
    required String eyebrow,
    required String title,
    required String subtitle,
    required IconData trailing,
    required VoidCallback onTap,
  }) {
    return Material(
      color: _surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          constraints: const BoxConstraints(minHeight: 68),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: .055)),
          ),
          child: Row(
            children: [
              Container(
                width: 43,
                height: 43,
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: _accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle.trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _muted, fontSize: 9),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(trailing, color: const Color(0xFF777777), size: 17),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeading({
    required String eyebrow,
    required String title,
    required String subtitle,
    VoidCallback? onRefresh,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              letterSpacing: -.65,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (onRefresh != null)
          Material(
            color: Colors.white.withValues(alpha: .045),
            shape: const CircleBorder(),
            child: IconButton(
              tooltip: 'Actualizar',
              onPressed: onRefresh,
              visualDensity: VisualDensity.compact,
              icon: const Icon(
                Icons.refresh_rounded,
                color: Color(0xFFB8B8B8),
                size: 17,
              ),
            ),
          ),
      ],
    );
  }

  Widget _musicSection(
    HomeOnlineSection section, {
    required String eyebrow,
    required bool compact,
    bool featured = false,
  }) {
    final coverSize = _coverSize(compact, featured);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeading(
          eyebrow: eyebrow,
          title: section.title,
          subtitle: section.subtitle,
          onRefresh: section.onRefresh,
        ),
        const SizedBox(height: 12),
        if (section.loading)
          _loadingRail(compact: compact, featured: featured)
        else if (section.error != null)
          _emptyState(
            message: section.error!,
            action: 'Intentar de nuevo',
            onTap: section.onRefresh,
          )
        else if (section.results.isEmpty)
          _emptyState(
            message: 'Aún no hay recomendaciones en esta sección.',
            action: 'Actualizar',
            onTap: section.onRefresh,
          )
        else
          SizedBox(
            height: coverSize * .78 + 76,
            child: ListView.separated(
              primary: false,
              scrollDirection: Axis.horizontal,
              itemCount: section.results.length,
              separatorBuilder: (context, index) =>
                  SizedBox(width: compact ? 13 : 17),
              itemBuilder: (context, index) => _musicCard(
                section,
                index,
                compact: compact,
                featured: featured,
              ),
            ),
          ),
      ],
    );
  }

  Widget _musicCard(
    HomeOnlineSection section,
    int index, {
    required bool compact,
    required bool featured,
  }) {
    final result = section.results[index];
    final selected = result.videoId == playingVideoId;
    final loading = result.videoId == loadingVideoId;
    final size = _coverSize(compact, featured);
    final coverHeight = size * .78;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: .94, end: 1),
      duration: Duration(milliseconds: 360 + (index % 5) * 55),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 10 * (1 - value)),
          child: child,
        ),
      ),
      child: SizedBox(
        width: size,
        child: Material(
          color: _surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(19),
            side: BorderSide(color: Colors.white.withValues(alpha: .07)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: loading ? null : () => section.onPlay(index),
            borderRadius: BorderRadius.circular(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: size,
                  height: coverHeight,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: selected
                                ? _accent.withValues(alpha: .65)
                                : Colors.white.withValues(alpha: .075),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: selected
                                  ? _accent.withValues(alpha: .11)
                                  : const Color(0x25000000),
                              blurRadius: selected ? 20 : 13,
                              offset: const Offset(0, 7),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(17),
                          child: Image.network(
                            result.thumbnail,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                _artFallback(),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              gradient: const LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Color(0x16000000),
                                  Color(0x00000000),
                                  Color(0x52000000),
                                ],
                                stops: [0, .48, 1],
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (section.ranked && result.rank != null)
                        Positioned(
                          top: 9,
                          left: 9,
                          child: _rankBadge(result.rank!),
                        ),
                      if (selected && !section.ranked)
                        Positioned(top: 9, left: 9, child: _playingBadge()),
                      if (result.durationSeconds > 0)
                        Positioned(
                          left: 10,
                          bottom: 10,
                          child: _durationBadge(result.durationSeconds),
                        ),
                      Positioned(
                        right: 10,
                        bottom: 10,
                        child: Container(
                          width: 37,
                          height: 37,
                          decoration: const BoxDecoration(
                            color: _accent,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Color(0x44000000),
                                blurRadius: 12,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Center(
                            child: loading
                                ? const SizedBox(
                                    width: 15,
                                    height: 15,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFF171717),
                                    ),
                                  )
                                : Icon(
                                    selected && isPlaying
                                        ? Icons.equalizer_rounded
                                        : Icons.play_arrow_rounded,
                                    color: const Color(0xFF171717),
                                    size: 22,
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(11, 9, 11, 11),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          height: 1.3,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        result.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _muted, fontSize: 9),
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
  }

  Widget _playingBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xE9141414),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: .12)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.graphic_eq_rounded, color: _accent, size: 11),
          SizedBox(width: 5),
          Text(
            'SONANDO',
            style: TextStyle(
              color: Colors.white,
              fontSize: 7,
              fontWeight: FontWeight.w800,
              letterSpacing: .65,
            ),
          ),
        ],
      ),
    );
  }

  Widget _rankBadge(int rank) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: .72),
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: Colors.white.withValues(alpha: .16)),
    ),
    child: Text(
      '#${rank.toString().padLeft(2, '0')}',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 10,
        fontWeight: FontWeight.w800,
        height: 1,
      ),
    ),
  );

  Widget _durationBadge(int seconds) {
    final minutes = seconds ~/ 60;
    final remainder = (seconds % 60).toString().padLeft(2, '0');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xDD151515),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: Colors.white.withValues(alpha: .10)),
      ),
      child: Text(
        '$minutes:$remainder',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 8,
          fontWeight: FontWeight.w700,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }

  double _coverSize(bool compact, bool featured) => compact
      ? 154
      : featured
      ? 210
      : 178;

  Widget _loadingRail({required bool compact, required bool featured}) {
    final size = _coverSize(compact, featured);
    final coverHeight = size * .78;
    return SizedBox(
      height: coverHeight + 76,
      child: ListView.separated(
        primary: false,
        scrollDirection: Axis.horizontal,
        itemCount: 4,
        separatorBuilder: (context, index) => const SizedBox(width: 15),
        itemBuilder: (context, index) => SizedBox(
          width: size,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: size,
                height: coverHeight,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF292929), Color(0xFF1B1B1B)],
                  ),
                ),
                child: const Icon(
                  Icons.graphic_eq_rounded,
                  color: Color(0xFF676767),
                  size: 26,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                height: 9,
                width: size * .72,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .07),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: 7),
              Container(
                height: 7,
                width: size * .46,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .04),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState({
    required String message,
    required String action,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 15, 12, 15),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: .055)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.music_note_rounded,
              color: _accent,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: _muted, fontSize: 10),
            ),
          ),
          TextButton(
            onPressed: onTap,
            child: Text(
              action,
              style: const TextStyle(color: _accent, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stationsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeading(
          eyebrow: 'EMPIEZA POR UN ARTISTA',
          title: 'Estaciones',
          subtitle: '',
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 9,
          runSpacing: 9,
          children: stationArtists
              .map((artist) {
                return Material(
                  color: _surface,
                  borderRadius: BorderRadius.circular(30),
                  child: InkWell(
                    onTap: () => onPlayStation(artist),
                    borderRadius: BorderRadius.circular(30),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.radio_rounded,
                            color: _accent,
                            size: 15,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            artist,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 7),
                          const Icon(
                            Icons.arrow_outward_rounded,
                            color: _muted,
                            size: 12,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              })
              .toList(growable: false),
        ),
      ],
    );
  }

  Widget _artFallback({bool loading = false}) {
    return Container(
      color: const Color(0xFF242424),
      child: Center(
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: _accent,
                  strokeWidth: 2,
                ),
              )
            : const Icon(Icons.music_note_rounded, color: _accent, size: 34),
      ),
    );
  }
}
