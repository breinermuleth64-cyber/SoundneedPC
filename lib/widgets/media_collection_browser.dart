import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/track.dart';
import '../services/artist_song_discovery_service.dart';
import '../services/artist_catalog_service.dart';
import '../services/home_discovery_service.dart';
import '../services/listening_history_service.dart';
import '../services/playlist_library_service.dart';
import 'ambient_album_background.dart';
import 'collection_hero.dart';

typedef PlayCollectionTracks = Future<void> Function(
  List<Track> tracks,
  int startAt,
  bool shuffle,
);
typedef PlayChartTrack = Future<void> Function(
  HomeChartTrack track,
  List<HomeChartTrack> queue,
);
typedef SaveChartTrack = Future<void> Function(HomeChartTrack track);

class MediaCollectionBrowser extends StatefulWidget {
  const MediaCollectionBrowser({
    required this.tracks,
    required this.showArtists,
    required this.compact,
    required this.accentColor,
    required this.secondaryAccent,
    required this.onPlayTracks,
    required this.currentTrackPath,
    required this.isPlaying,
    required this.favoritePaths,
    required this.onToggleFavorite,
    required this.onAddToPlaylist,
    this.featuredArtists = const [],
    this.worldArtists = const [],
    this.trendingTracks = const [],
    this.preferredArtists = const [],
    this.recentlyHeardTrackKeys = const {},
    this.trackPlayCounts = const {},
    this.onPlayArtistStation,
    this.onPlayChartTrack,
    this.onAddChartToPlaylist,
    this.onToggleChartFavorite,
    this.onPlayArtistSong,
    super.key,
  });

  final List<Track> tracks;
  final bool showArtists;
  final bool compact;
  final Color accentColor;
  final Color secondaryAccent;
  final PlayCollectionTracks onPlayTracks;
  final String? currentTrackPath;
  final bool isPlaying;
  final Set<String> favoritePaths;
  final ValueChanged<Track> onToggleFavorite;
  final ValueChanged<Track> onAddToPlaylist;
  final List<String> featuredArtists;
  final List<HomeChartArtist> worldArtists;
  final List<HomeChartTrack> trendingTracks;
  final List<String> preferredArtists;
  final Set<String> recentlyHeardTrackKeys;
  final Map<String, int> trackPlayCounts;
  final ValueChanged<String>? onPlayArtistStation;
  final PlayChartTrack? onPlayChartTrack;
  final SaveChartTrack? onAddChartToPlaylist;
  final SaveChartTrack? onToggleChartFavorite;
  final Future<void> Function(ArtistSongResult, List<ArtistSongResult>)?
  onPlayArtistSong;

  @override
  State<MediaCollectionBrowser> createState() => _MediaCollectionBrowserState();
}

class _MediaCollectionBrowserState extends State<MediaCollectionBrowser> {
  Color get _cyan => widget.accentColor;
  Color get _secondary => widget.secondaryAccent;
  static const _surface = Color(0xFF151522);
  static const _raised = Color(0xFF1D1D2B);
  static const _muted = Color(0xFF9292A5);

  String _query = '';
  String? _selectedKey;
  String? _selectedName;
  String? _returnArtistKey;
  String? _returnArtistName;
  bool _showingArtistAlbum = false;
  Timer? _artistSearchDebounce;
  int _artistSearchRequest = 0;
  bool _searchingArtists = false;
  List<ArtistCatalogEntry> _artistSearchResults = [];
  String? _artistSearchError;
  final _searchController = TextEditingController();
  List<ArtistSongResult> _artistSongResults = [];
  bool _loadingArtistSongs = false;
  String? _artistSongsError;
  int _artistSongRequest = 0;
  final Map<String, Future<ArtistCatalogEntry?>> _portraitFutures = {};

  bool get _isArtists => widget.showArtists;

  @override
  void dispose() {
    _artistSearchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() => _query = value);
    _artistSearchDebounce?.cancel();
    final query = value.trim();
    if (!_isArtists || query.isEmpty) {
      _artistSearchRequest++;
      setState(() {
        _artistSearchResults = [];
        _searchingArtists = false;
        _artistSearchError = null;
      });
      return;
    }

    final request = ++_artistSearchRequest;
    setState(() => _searchingArtists = true);
    _artistSearchDebounce = Timer(const Duration(milliseconds: 450), () async {
      try {
        final results = await ArtistCatalogService.instance.searchArtists(
          query,
          limit: 20,
        );
        if (!mounted || request != _artistSearchRequest) return;
        setState(() {
          _artistSearchResults = results;
          _searchingArtists = false;
          _artistSearchError = null;
        });
      } catch (_) {
        if (!mounted || request != _artistSearchRequest) return;
        setState(() {
          _artistSearchResults = [];
          _searchingArtists = false;
          _artistSearchError =
              'No se pudo buscar. Revisa tu conexión e inténtalo de nuevo.';
        });
      }
    });
  }

  Future<ArtistCatalogEntry?> _artistPortraitFuture(String artist) =>
      _portraitFutures.putIfAbsent(
        _normalize(artist),
        () => ArtistCatalogService.instance.lookup(artist),
      );
  String _clean(String value, String fallback) {
    final result = value.trim();
    return result.isEmpty || result == '<unknown>' ? fallback : result;
  }

  String _normalize(String value) => value.trim().toLowerCase();

  Track? _first(List<Track> tracks) => tracks.isEmpty ? null : tracks.first;

  List<_MediaGroup> _groups() {
    final buckets = <String, List<Track>>{};
    final titles = <String, String>{};
    final subtitles = <String, String>{};
    for (final track in widget.tracks) {
      final artist = _clean(track.artist, 'Artista desconocido');
      final album = _clean(track.album, 'Álbum sin nombre');
      final key = _isArtists
          ? 'artist:${_normalize(artist)}'
          : 'album:${_normalize(album)}|${_normalize(artist)}';
      buckets.putIfAbsent(key, () => <Track>[]).add(track);
      titles.putIfAbsent(key, () => _isArtists ? artist : album);
      subtitles.putIfAbsent(key, () => _isArtists ? '' : artist);
    }
    final result =
        buckets.entries.map((entry) {
          final songs = List<Track>.of(entry.value)
            ..sort(
              (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
            );
          return _MediaGroup(
            key: entry.key,
            title: titles[entry.key]!,
            subtitle: subtitles[entry.key]!,
            tracks: songs,
          );
        }).toList()..sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups();
    if (_selectedKey != null) {
      if (_showingArtistAlbum) {
        final albums = _allAlbumGroups().where(
          (group) => group.key == _selectedKey,
        );
        if (albums.isNotEmpty) return _albumDetail(albums.first);
      }
      final matches = groups.where((group) => group.key == _selectedKey);
      if (matches.isNotEmpty) return _detail(matches.first);
      if (_isArtists && _selectedName != null) {
        return _artistDetail(
          _MediaGroup(
            key: _selectedKey!,
            title: _selectedName!,
            subtitle: '',
            tracks: const [],
          ),
        );
      }
      _selectedKey = null;
      _selectedName = null;
    }

    final query = _query.trim().toLowerCase();
    final visible = query.isEmpty
        ? groups
        : groups
              .where(
                (group) =>
                    group.title.toLowerCase().contains(query) ||
                    group.subtitle.toLowerCase().contains(query),
              )
              .toList(growable: false);
    final featured = _isArtists
        ? widget.featuredArtists
              .where((name) => name.trim().isNotEmpty)
              .where(
                (name) => query.isEmpty || name.toLowerCase().contains(query),
              )
              .toSet()
              .take(12)
              .toList(growable: false)
        : const <String>[];
    final personalArtists = _isArtists
        ? widget.preferredArtists
              .where((name) => name.trim().isNotEmpty)
              .where(
                (name) => query.isEmpty || name.toLowerCase().contains(query),
              )
              .toList(growable: false)
        : const <String>[];
    final discovery = _discoverySelection();

    if (widget.tracks.isEmpty &&
        (!_isArtists || (featured.isEmpty && personalArtists.isEmpty))) {
      return _emptyLibrary();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CollectionHero(
          eyebrow: _isArtists ? 'DESCUBRE Y EXPLORA' : 'TU COLECCIÓN',
          title: _isArtists ? 'Artistas' : 'Álbumes',
          description: _isArtists
              ? 'Perfiles, novedades y canciones de tu biblioteca.'
              : 'Portadas y canciones organizadas por artista.',
          icon: _isArtists ? Icons.mic_rounded : Icons.album_rounded,
          count: groups.length,
          countLabel: _isArtists ? 'artistas' : 'álbumes',
          compact: widget.compact,
          accent: widget.accentColor,
          secondaryAccent: widget.secondaryAccent,
        ),
        const SizedBox(height: 20),
        _searchField(),
        const SizedBox(height: 24),
        if (_isArtists && query.isNotEmpty) ...[
          _heading(
            'Artistas encontrados',
            'Catálogo de artistas',
            _artistSearchResults.length,
          ),
          const SizedBox(height: 12),
          if (_searchingArtists)
            LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: _surface,
              valueColor: AlwaysStoppedAnimation<Color>(_cyan),
            )
          else if (_artistSearchResults.isEmpty)
            _message(
              Icons.person_search_rounded,
              _artistSearchError ?? 'No encontramos artistas con ese nombre',
              'Prueba con otro nombre. También puedes explorar los artistas de tu biblioteca.',
            )
          else
            ..._artistSearchResults.map(_searchedArtistTile),
          const SizedBox(height: 22),
        ],
        if (_isArtists && query.isEmpty && featured.isNotEmpty) ...[
          if (widget.worldArtists.isNotEmpty) ...[
            _artistSpotlight(widget.worldArtists.first),
            const SizedBox(height: 22),
          ],
          _heading(
            'Artistas más escuchados',
            widget.worldArtists.isEmpty
                ? 'Tendencias del Top mundial'
                : 'Tendencia global · ${widget.worldArtists.first.snapshotDays}/30 días registrados',
            featured.length,
          ),
          const SizedBox(height: 13),
          SizedBox(
            height: widget.compact ? 146 : 158,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: featured.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) => _featuredArtist(featured[index]),
            ),
          ),
          if (discovery.tracks.isNotEmpty) ...[
            const SizedBox(height: 24),
            _heading(
              'Descubre en SoundNeed',
              discovery.personalized
                  ? 'Según tus artistas más escuchados'
                  : 'De artistas destacados en SoundNeed',
              discovery.tracks.length,
            ),
            const SizedBox(height: 10),
            ...discovery.tracks.map(
              (track) => _chartTrackRow(track, discovery.tracks),
            ),
          ],
          const SizedBox(height: 26),
        ],
        if (_isArtists && query.isEmpty && personalArtists.isNotEmpty) ...[
          _heading(
            'Tus artistas más escuchados',
            'Según tu actividad reciente',
            personalArtists.length,
          ),
          const SizedBox(height: 13),
          SizedBox(
            height: widget.compact ? 150 : 162,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: personalArtists.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) =>
                  _personalArtist(personalArtists[index], index),
            ),
          ),
          const SizedBox(height: 22),
        ],
        _heading(
          _isArtists ? 'Artistas de tu biblioteca' : 'Álbumes de tu biblioteca',
          _isArtists
              ? 'Explora y reproduce tu colección por artista'
              : 'Organizados por álbum y artista',
          visible.length,
        ),
        const SizedBox(height: 15),
        if (visible.isEmpty && groups.isEmpty && query.isEmpty)
          _emptyLibrary()
        else if (visible.isEmpty)
          _noMatches()
        else if (_isArtists)
          _artistGrid(visible)
        else
          _albumGrid(visible),
      ],
    );
  }

  Widget _searchField() => TextField(
    controller: _searchController,
    onChanged: _onSearchChanged,
    style: TextStyle(color: Colors.white, fontSize: 14),
    decoration: InputDecoration(
      hintText: _isArtists ? 'Buscar artista en tu biblioteca' : 'Buscar álbum',
      hintStyle: TextStyle(color: _muted, fontSize: 13),
      prefixIcon: Icon(Icons.search_rounded, color: _cyan, size: 21),
      suffixIcon: _query.isEmpty
          ? null
          : IconButton(
              tooltip: 'Limpiar búsqueda',
              onPressed: () {
                _searchController.clear();
                _onSearchChanged('');
              },
              icon: Icon(Icons.close_rounded, color: _muted, size: 18),
            ),
      filled: true,
      fillColor: _surface,
      contentPadding: const EdgeInsets.symmetric(vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(color: Color(0xFF2B2B3B)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(color: Color(0xFF2B2B3B)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(color: _cyan, width: 1.2),
      ),
    ),
  );

  Widget _heading(String title, String subtitle, int count) => Row(
    children: [
      Container(
        width: 3,
        height: 34,
        decoration: BoxDecoration(
          color: _cyan,
          borderRadius: BorderRadius.circular(6),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -.25,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: _muted, fontSize: 11),
            ),
          ],
        ),
      ),
      const SizedBox(width: 10),
      Container(
        constraints: const BoxConstraints(minWidth: 34, minHeight: 28),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              _cyan.withValues(alpha: .2),
              _secondary.withValues(alpha: .09),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _secondary.withValues(alpha: .34)),
          boxShadow: [
            BoxShadow(
              color: _secondary.withValues(alpha: .09),
              blurRadius: 10,
              spreadRadius: -2,
            ),
          ],
        ),
        child: Text(
          '$count',
          style: TextStyle(
            color: _cyan,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    ],
  );

  Widget _featuredArtist(String artist) {
    final sample = _first(_artistGroupByName(artist)?.tracks ?? const []);
    final rank = widget.worldArtists.indexWhere(
      (entry) => _normalizeChartText(entry.name) == _normalizeChartText(artist),
    );
    return SizedBox(
      width: widget.compact ? 132 : 148,
      child: Material(
        color: _raised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(19),
          side: BorderSide(color: _cyan.withValues(alpha: .16)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openArtist(artist),
          hoverColor: _cyan.withValues(alpha: .07),
          splashColor: _secondary.withValues(alpha: .12),
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _cyan.withValues(alpha: .085),
                  _raised,
                  _secondary.withValues(alpha: .035),
                ],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: _cyan.withValues(alpha: .52)),
                      boxShadow: [
                        BoxShadow(
                          color: _cyan.withValues(alpha: .14),
                          blurRadius: 13,
                          spreadRadius: -4,
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: SizedBox(
                        width: 68,
                        height: 68,
                        child: _artistPortrait(artist, sample),
                      ),
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _cyan.withValues(alpha: .10),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _cyan.withValues(alpha: .19)),
                    ),
                    child: Text(
                      rank < 0 ? 'En tendencia' : 'N.º ${rank + 1}',
                      style: TextStyle(
                        color: _cyan,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _personalArtist(String artist, int rank) {
    final tracks = _artistGroupByName(artist)?.tracks ?? const <Track>[];
    final plays = tracks.fold<int>(
      0,
      (total, track) =>
          total +
          (widget.trackPlayCounts[listeningTrackKey(
                track.title,
                track.artist,
              )] ??
              0),
    );
    return SizedBox(
      width: 190,
      child: Material(
        color: _raised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(19),
          side: BorderSide(color: _cyan.withValues(alpha: .13)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openArtist(artist),
          hoverColor: _cyan.withValues(alpha: .06),
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_cyan.withValues(alpha: .07), _raised],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: _cyan.withValues(alpha: .42)),
                    ),
                    child: ClipOval(
                      child: SizedBox(
                        width: 62,
                        height: 62,
                        child: _artistPortrait(
                          artist,
                          tracks.isEmpty ? null : tracks.first,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'TU ROTACIÓN · N.º ${rank + 1}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _cyan,
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .7,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          plays > 0
                              ? '$plays reproducciones'
                              : '${tracks.length} canciones guardadas',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: _muted, fontSize: 9),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right_rounded, color: _cyan, size: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _normalizeChartText(String value) => value
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ü', 'u')
      .replaceAll('ñ', 'n')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();

  Widget _artistSpotlight(HomeChartArtist artist) {
    final sample = _first(_artistGroupByName(artist.name)?.tracks ?? const []);
    final topSong = artist.songs.isEmpty ? null : artist.songs.first;
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = widget.compact || constraints.maxWidth < 650;
        final portraitSize = narrow ? 82.0 : 118.0;
        final identity = Row(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: .22),
                border: Border.all(color: _cyan.withValues(alpha: .6)),
                boxShadow: [
                  BoxShadow(
                    color: _cyan.withValues(alpha: .18),
                    blurRadius: 22,
                    spreadRadius: -5,
                  ),
                ],
              ),
              child: ClipOval(
                child: SizedBox(
                  width: portraitSize,
                  height: portraitSize,
                  child: _artistPortrait(artist.name, sample),
                ),
              ),
            ),
            SizedBox(width: narrow ? 13 : 19),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: _cyan.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _cyan.withValues(alpha: .28)),
                    ),
                    child: Text(
                      'ARTISTA DESTACADO  ·  N.º ${artist.rank}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _cyan,
                        fontSize: 9,
                        letterSpacing: .65,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    artist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: narrow ? 20 : 25,
                      height: 1.05,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -.55,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    topSong == null
                        ? '${artist.songs.length} canciones · ${artist.snapshotDays}/30 días'
                        : 'Más escuchada: ${topSong.title}  ·  ${artist.snapshotDays}/30 días',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white70, fontSize: 10.5),
                  ),
                ],
              ),
            ),
          ],
        );
        final actions = Wrap(
          spacing: 8,
          runSpacing: 7,
          children: [
            _heroButton(
              Icons.person_search_rounded,
              'Ver artista',
              () => _openArtist(artist.name),
            ),
            if (topSong != null && widget.onPlayChartTrack != null)
              _heroButton(
                Icons.play_arrow_rounded,
                'Escuchar top',
                () => widget.onPlayChartTrack!(topSong, artist.songs),
              ),
          ],
        );

        return Material(
          color: _surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(23),
            side: BorderSide(color: _cyan.withValues(alpha: .27)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _openArtist(artist.name),
            hoverColor: _cyan.withValues(alpha: .035),
            child: SizedBox(
              height: narrow ? 226 : 202,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (artist.artworkUrl.isNotEmpty)
                    Image.network(
                      artist.artworkUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          const ColoredBox(color: _surface),
                    )
                  else
                    const ColoredBox(color: _surface),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        stops: [0, .44, 1],
                        colors: [
                          Color(0xF20C0C15),
                          Color(0xD50C0C15),
                          Color(0x45101018),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    right: -64,
                    top: -116,
                    child: Container(
                      width: 240,
                      height: 240,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _secondary.withValues(alpha: .1),
                          width: 28,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.all(narrow ? 15 : 20),
                    child: narrow
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              identity,
                              const Spacer(),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: actions,
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(flex: 3, child: identity),
                              const SizedBox(width: 18),
                              Flexible(
                                flex: 2,
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: actions,
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
      },
    );
  }

  ({List<HomeChartTrack> tracks, bool personalized}) _discoverySelection() {
    final candidates = <HomeChartTrack>[
      for (final artist in widget.worldArtists) ...artist.songs,
      ...widget.trendingTracks,
    ];
    final selected = <HomeChartTrack>[];
    final selectedKeys = <String>{};
    var personalizedCount = 0;

    String keyFor(HomeChartTrack track) =>
        '${_normalizeChartText(track.title)}|'
        '${_normalizeChartText(track.artist)}';

    void add(HomeChartTrack track, {required bool avoidRecentlyHeard}) {
      final key = keyFor(track);
      if (key.startsWith('|') || selectedKeys.contains(key)) return;
      if (avoidRecentlyHeard && widget.recentlyHeardTrackKeys.contains(key)) {
        return;
      }
      selectedKeys.add(key);
      selected.add(track);
    }

    for (final artist in widget.preferredArtists) {
      final artistKey = _normalizeChartText(artist);
      for (final track in candidates) {
        if (_normalizeChartText(track.artist) != artistKey) continue;
        final before = selected.length;
        add(track, avoidRecentlyHeard: true);
        if (selected.length > before) personalizedCount++;
        if (selected.length >= 8) break;
      }
      if (selected.length >= 8) break;
    }

    for (final artist in widget.worldArtists) {
      for (final track in artist.songs) {
        add(track, avoidRecentlyHeard: true);
        if (selected.length >= 8) break;
      }
      if (selected.length >= 8) break;
    }
    for (final track in widget.trendingTracks) {
      add(track, avoidRecentlyHeard: true);
      if (selected.length >= 8) break;
    }
    if (selected.isEmpty) {
      for (final track in candidates) {
        add(track, avoidRecentlyHeard: false);
        if (selected.length >= 8) break;
      }
    }

    return (
      tracks: List.unmodifiable(selected),
      personalized: personalizedCount > 0,
    );
  }

  List<HomeChartTrack> _popularSongsForArtist(String artist) {
    final key = _normalizeChartText(artist);
    for (final entry in widget.worldArtists) {
      if (_normalizeChartText(entry.name) == key) return entry.songs;
    }
    return widget.trendingTracks
        .where((track) => _normalizeChartText(track.artist) == key)
        .take(10)
        .toList(growable: false);
  }

  bool _isChartTrackFavorite(HomeChartTrack track) {
    final title = _normalizeChartText(track.title);
    final artist = _normalizeChartText(track.artist);
    for (final key in widget.favoritePaths) {
      final saved = PlaylistLibraryService.decodeOnlineTrack(key);
      if (saved != null &&
          _normalizeChartText(saved.title) == title &&
          _normalizeChartText(saved.artist) == artist) {
        return true;
      }
    }
    return false;
  }

  Widget _chartTrackRow(HomeChartTrack track, List<HomeChartTrack> queue) {
    final favorite = _isChartTrackFavorite(track);
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Material(
        color: _raised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(17),
          side: BorderSide(color: _cyan.withValues(alpha: .09)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(17),
          onTap: widget.onPlayChartTrack == null
              ? null
              : () => widget.onPlayChartTrack!(track, queue),
          hoverColor: _cyan.withValues(alpha: .04),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        _cyan.withValues(alpha: .17),
                        _secondary.withValues(alpha: .08),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _cyan.withValues(alpha: .15)),
                  ),
                  child: Text(
                    '#${track.rank.toString().padLeft(2, '0')}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _cyan,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 11),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 50,
                    height: 50,
                    child: track.artworkUrl.isEmpty
                        ? _coverPlaceholder(Icons.music_note_rounded)
                        : Image.network(
                            track.artworkUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                _coverPlaceholder(Icons.music_note_rounded),
                          ),
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: _muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: favorite
                      ? 'Quitar de Me gusta'
                      : 'Guardar en Me gusta',
                  onPressed: widget.onToggleChartFavorite == null
                      ? null
                      : () => unawaited(widget.onToggleChartFavorite!(track)),
                  icon: Icon(
                    favorite
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: favorite ? const Color(0xFFFF6B87) : _muted,
                    size: 19,
                  ),
                ),
                IconButton(
                  tooltip: 'Agregar a playlist',
                  onPressed: widget.onAddChartToPlaylist == null
                      ? null
                      : () => unawaited(widget.onAddChartToPlaylist!(track)),
                  icon: Icon(
                    Icons.playlist_add_rounded,
                    color: _cyan,
                    size: 21,
                  ),
                ),
                IconButton(
                  tooltip: 'Reproducir canción',
                  onPressed: widget.onPlayChartTrack == null
                      ? null
                      : () => widget.onPlayChartTrack!(track, queue),
                  icon: Icon(
                    Icons.play_circle_fill_rounded,
                    color: _cyan,
                    size: 27,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _searchedArtistTile(ArtistCatalogEntry artist) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: _raised,
      borderRadius: BorderRadius.circular(14),
      child: ListTile(
        leading: ClipOval(
          child: SizedBox(
            width: 48,
            height: 48,
            child: Image.network(
              artist.pictureUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  _coverPlaceholder(Icons.person_rounded),
            ),
          ),
        ),
        title: Text(
          artist.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          artist.fanCount == null
              ? 'Abrir perfil del artista'
              : '${artist.fanCount} seguidores en Deezer',
          style: TextStyle(color: _muted, fontSize: 11),
        ),
        trailing: Icon(Icons.chevron_right_rounded, color: _cyan),
        onTap: () => _openArtist(artist.name),
      ),
    ),
  );

  Widget _artistPortrait(String name, Track? fallback) =>
      FutureBuilder<ArtistCatalogEntry?>(
        future: _artistPortraitFuture(name),
        builder: (context, snapshot) {
          final portrait = snapshot.data;
          if (portrait == null) {
            return _cover(fallback, icon: Icons.person_rounded);
          }
          return Image.network(
            portrait.pictureUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) =>
                _cover(fallback, icon: Icons.person_rounded),
            loadingBuilder: (context, child, progress) => progress == null
                ? child
                : _cover(fallback, icon: Icons.person_rounded),
          );
        },
      );
  Widget _artistGrid(List<_MediaGroup> groups) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = widget.compact || constraints.maxWidth < 680;
      final columns = compact ? 2 : (constraints.maxWidth > 1050 ? 4 : 3);
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: groups.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: compact ? 1.18 : 1.35,
        ),
        itemBuilder: (context, index) =>
            _artistCard(groups[index], _first(groups[index].tracks)),
      );
    },
  );

  Widget _artistCard(_MediaGroup group, Track? sample) {
    final portraitSize = widget.compact ? 54.0 : 66.0;
    final radius = BorderRadius.circular(20);
    return Material(
      color: _raised,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: _cyan.withValues(alpha: .14)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openArtist(group.title),
        hoverColor: _cyan.withValues(alpha: .045),
        splashColor: _cyan.withValues(alpha: .10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: portraitSize + 6,
                height: portraitSize + 6,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _cyan.withValues(alpha: .32)),
                  color: _cyan.withValues(alpha: .08),
                ),
                child: ClipOval(child: _artistPortrait(group.title, sample)),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        height: 1.15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.15,
                      ),
                    ),
                    const SizedBox(height: 7),
                    _trackCount(group.tracks.length),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .045),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .07),
                  ),
                ),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  color: _cyan,
                  size: 18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _albumGrid(List<_MediaGroup> groups) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = widget.compact || constraints.maxWidth < 680;
      final columns = compact ? 2 : (constraints.maxWidth > 1120 ? 4 : 3);
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: groups.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 13,
          mainAxisSpacing: 14,
          childAspectRatio: compact ? .79 : .84,
        ),
        itemBuilder: (context, index) => _albumCard(groups[index]),
      );
    },
  );

  Widget _albumCard(_MediaGroup group, {VoidCallback? onTap}) {
    final sample = _first(group.tracks);
    return Material(
      color: _raised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(19),
        side: BorderSide(color: _cyan.withValues(alpha: .13)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap ?? () => _select(group),
        hoverColor: _cyan.withValues(alpha: .045),
        splashColor: _cyan.withValues(alpha: .1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _cover(sample, icon: Icons.album_rounded),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      height: 60,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0xD9000000)],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: _roundAction(
                      icon: Icons.play_arrow_rounded,
                      onPressed: () =>
                          widget.onPlayTracks(group.tracks, 0, false),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    group.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: _muted, fontSize: 11),
                  ),
                  const SizedBox(height: 4),
                  _trackCount(group.tracks.length),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detail(_MediaGroup group) =>
      _isArtists ? _artistDetail(group) : _albumDetail(group);

  Widget _artistDetail(_MediaGroup group) {
    final albums = _groupsForArtist(group.title);
    final hasTracks = group.tracks.isNotEmpty;
    final orderedTracks = [...group.tracks]
      ..sort((a, b) {
        final aPlays =
            widget.trackPlayCounts[listeningTrackKey(a.title, a.artist)] ?? 0;
        final bPlays =
            widget.trackPlayCounts[listeningTrackKey(b.title, b.artist)] ?? 0;
        final byPlays = bPlays.compareTo(aPlays);
        return byPlays != 0
            ? byPlays
            : a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _detailBack(
          group.title,
          'PERFIL DEL ARTISTA',
          onRefresh: _loadingArtistSongs
              ? null
              : () => unawaited(
                  _loadArtistSongs(group.title, forceRefresh: true),
                ),
        ),
        const SizedBox(height: 14),
        _hero(
          title: group.title,
          subtitle: hasTracks
              ? '${_trackText(group.tracks.length)} en tu biblioteca'
              : 'Explora este artista en SoundNeed',
          sample: _first(group.tracks),
          icon: Icons.person_rounded,
          artistPortraitName: group.title,
          actions: [
            _heroButton(
              Icons.play_arrow_rounded,
              'Reproducir',
              hasTracks
                  ? () => widget.onPlayTracks(group.tracks, 0, false)
                  : null,
            ),
            _heroButton(
              Icons.shuffle_rounded,
              'Aleatorio',
              hasTracks
                  ? () => widget.onPlayTracks(group.tracks, 0, true)
                  : null,
            ),
            if (widget.onPlayArtistStation != null)
              _heroButton(
                Icons.graphic_eq_rounded,
                'Radio del artista',
                () => widget.onPlayArtistStation!(group.title),
              ),
          ],
        ),
        if (_popularSongsForArtist(group.title).isNotEmpty) ...[
          const SizedBox(height: 23),
          _heading(
            'Más escuchadas en 30 días',
            widget.worldArtists.isEmpty
                ? 'Canciones del Top mundial actual'
                : 'Tendencia global · ${widget.worldArtists.first.snapshotDays}/30 días registrados',
            _popularSongsForArtist(group.title).length,
          ),
          const SizedBox(height: 10),
          ..._popularSongsForArtist(group.title).indexed.map(
            (entry) =>
                _chartTrackRow(entry.$2, _popularSongsForArtist(group.title)),
          ),
        ] else if (_isArtists && widget.trendingTracks.isNotEmpty) ...[
          const SizedBox(height: 23),
          _message(
            Icons.trending_up_rounded,
            'Todavía no hay temas en tendencia de ${group.title}',
            'Puedes escuchar su radio o disfrutar las canciones de tu biblioteca.',
          ),
        ],
        const SizedBox(height: 23),
        _heading(
          'Descubre en SoundNeed',
          'Canciones de ${group.title}',
          _artistSongResults.length,
        ),
        const SizedBox(height: 10),
        if (_loadingArtistSongs)
          LinearProgressIndicator(
            minHeight: 2,
            backgroundColor: _surface,
            valueColor: AlwaysStoppedAnimation<Color>(_cyan),
          )
        else if (_artistSongResults.isNotEmpty)
          ..._artistSongResults.indexed.map(
            (entry) => _artistSongRow(entry.$2, entry.$1, _artistSongResults),
          )
        else
          _message(
            Icons.search_rounded,
            _artistSongsError ?? 'Desliza para volver a buscar canciones.',
            'Prueba de nuevo con una conexión a internet.',
          ),
        if (albums.isNotEmpty) ...[
          const SizedBox(height: 24),
          _heading(
            'Álbumes de ${group.title}',
            'De tu biblioteca',
            albums.length,
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 205,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: albums.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) => SizedBox(
                width: 145,
                child: _albumCard(
                  albums[index],
                  onTap: () => _selectArtistAlbum(albums[index], group.title),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 23),
        _heading(
          'De tu biblioteca',
          'Canciones guardadas',
          group.tracks.length,
        ),
        const SizedBox(height: 10),
        if (!hasTracks)
          _emptyArtist(group.title)
        else
          ...orderedTracks.indexed.map(
            (entry) => _trackRow(orderedTracks, entry.$2, entry.$1),
          ),
      ],
    );
  }

  Track _savedArtistSong(ArtistSongResult song) {
    final metadata = Track(
      path: '',
      title: song.title,
      artist: song.artist,
      coverPath: song.artworkUrl,
      durationMs: song.durationSeconds * 1000,
    );
    return Track(
      path: PlaylistLibraryService.encodeOnlineTrack(metadata, song.videoId),
      title: metadata.title,
      artist: metadata.artist,
      coverPath: metadata.coverPath,
      durationMs: metadata.durationMs,
    );
  }

  Widget _artistSongRow(
    ArtistSongResult song,
    int index,
    List<ArtistSongResult> queue,
  ) {
    final play = widget.onPlayArtistSong;
    final savedTrack = _savedArtistSong(song);
    final favorite = widget.favoritePaths.contains(savedTrack.path);
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Material(
        color: _surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(17),
          side: BorderSide(color: _cyan.withValues(alpha: .08)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: play == null ? null : () => unawaited(play(song, queue)),
          hoverColor: _cyan.withValues(alpha: .04),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _cyan.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text(
                    '${index + 1}'.padLeft(2, '0'),
                    style: TextStyle(
                      color: _cyan,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 11),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    song.artworkUrl,
                    width: 50,
                    height: 50,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        _coverPlaceholder(Icons.music_note_rounded),
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: _muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: favorite
                      ? 'Quitar de Me gusta'
                      : 'Guardar en Me gusta',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => widget.onToggleFavorite(savedTrack),
                  icon: Icon(
                    favorite
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: favorite ? const Color(0xFFFF6B87) : _muted,
                    size: 19,
                  ),
                ),
                IconButton(
                  tooltip: 'Agregar a playlist',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => widget.onAddToPlaylist(savedTrack),
                  icon: Icon(
                    Icons.playlist_add_rounded,
                    color: _cyan,
                    size: 21,
                  ),
                ),
                IconButton(
                  tooltip: 'Reproducir canción',
                  visualDensity: VisualDensity.compact,
                  onPressed: play == null
                      ? null
                      : () => unawaited(play(song, queue)),
                  icon: Icon(
                    Icons.play_circle_fill_rounded,
                    color: _cyan,
                    size: 27,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _albumDetail(_MediaGroup group) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _detailBack(group.title, 'ÁLBUM DE TU BIBLIOTECA'),
      const SizedBox(height: 14),
      _hero(
        title: group.title,
        subtitle: '${group.subtitle}  ·  ${_trackText(group.tracks.length)}',
        sample: _first(group.tracks),
        icon: Icons.album_rounded,
        actions: [
          _heroButton(
            Icons.play_arrow_rounded,
            'Reproducir álbum',
            group.tracks.isEmpty
                ? null
                : () => widget.onPlayTracks(group.tracks, 0, false),
          ),
          _heroButton(
            Icons.shuffle_rounded,
            'Aleatorio',
            group.tracks.isEmpty
                ? null
                : () => widget.onPlayTracks(group.tracks, 0, true),
          ),
        ],
      ),
      const SizedBox(height: 23),
      _heading(
        'Canciones del álbum',
        'Reproducción en orden',
        group.tracks.length,
      ),
      const SizedBox(height: 10),
      ...group.tracks.indexed.map(
        (entry) => _trackRow(group.tracks, entry.$2, entry.$1),
      ),
    ],
  );

  Widget _detailBack(String title, String eyebrow, {VoidCallback? onRefresh}) =>
      Row(
        children: [
          IconButton(
            tooltip: 'Volver a la colección',
            onPressed: () => setState(() {
              if (_showingArtistAlbum) {
                _selectedKey = _returnArtistKey;
                _selectedName = _returnArtistName;
                _showingArtistAlbum = false;
              } else {
                _selectedKey = null;
                _selectedName = null;
              }
            }),
            icon: Icon(Icons.arrow_back_rounded, color: _cyan),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eyebrow,
                  style: TextStyle(
                    color: _cyan,
                    fontSize: 9,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (onRefresh != null)
            IconButton(
              tooltip: 'Actualizar',
              onPressed: onRefresh,
              icon: Icon(Icons.refresh_rounded, color: _cyan),
            ),
        ],
      );

  Widget _hero({
    required String title,
    required String subtitle,
    required Track? sample,
    required IconData icon,
    required List<Widget> actions,
    String? artistPortraitName,
  }) {
    final size = widget.compact ? 100.0 : 155.0;
    final portraitFuture = artistPortraitName == null
        ? null
        : _artistPortraitFuture(artistPortraitName);
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: SizedBox(
        height: widget.compact ? 220 : 244,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (portraitFuture == null)
              AmbientAlbumBackground(artwork: _imageProvider(sample))
            else
              FutureBuilder<ArtistCatalogEntry?>(
                future: portraitFuture,
                builder: (context, snapshot) {
                  final url = snapshot.data?.pictureUrl;
                  final artwork = url == null
                      ? _imageProvider(sample)
                      : NetworkImage(url);
                  return AmbientAlbumBackground(artwork: artwork);
                },
              ),
            Container(color: const Color(0x660B0B12)),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(17),
                    child: SizedBox(
                      width: size,
                      height: size,
                      child: artistPortraitName == null
                          ? _cover(sample, icon: icon)
                          : _artistPortrait(artistPortraitName, sample),
                    ),
                  ),
                  SizedBox(width: widget.compact ? 15 : 23),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: widget.compact ? 21 : 27,
                            height: 1.05,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -.6,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        const SizedBox(height: 13),
                        Wrap(spacing: 8, runSpacing: 8, children: actions),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroButton(IconData icon, String label, VoidCallback? onPressed) {
    final primary =
        onPressed != null &&
        (icon == Icons.play_arrow_rounded || label == 'Escuchar');
    final foreground = onPressed == null
        ? Colors.white38
        : primary
        ? const Color(0xFF071219)
        : _cyan;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onPressed,
        child: Ink(
          decoration: BoxDecoration(
            gradient: primary
                ? LinearGradient(
                    colors: [Color(0xFFB6F5FF), _cyan, Color(0xFF56C9E6)],
                  )
                : LinearGradient(
                    colors: [Color(0xE8232534), Color(0xD8171825)],
                  ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: primary
                  ? Colors.white.withValues(alpha: .34)
                  : _cyan.withValues(alpha: onPressed == null ? .1 : .32),
            ),
            boxShadow: primary
                ? [
                    BoxShadow(
                      color: _cyan.withValues(alpha: .22),
                      blurRadius: 14,
                      spreadRadius: -3,
                    ),
                  ]
                : const [],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(7, 6, 15, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 29,
                  height: 29,
                  decoration: BoxDecoration(
                    color: primary
                        ? Colors.black.withValues(alpha: .1)
                        : _cyan.withValues(
                            alpha: onPressed == null ? .06 : .12,
                          ),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 17, color: foreground),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .05,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _trackRow(List<Track> queue, Track track, int index) {
    final active = widget.currentTrackPath == track.path;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Material(
        color: active ? _cyan.withValues(alpha: .12) : _surface,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: () => widget.onPlayTracks(queue, index, false),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 36,
                  child: Center(
                    child: active && widget.isPlaying
                        ? Icon(Icons.equalizer_rounded, color: _cyan, size: 18)
                        : Text(
                            (index + 1).toString().padLeft(2, '0'),
                            style: TextStyle(color: _muted, fontSize: 10),
                          ),
                  ),
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: SizedBox(width: 42, height: 42, child: _cover(track)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: active ? _cyan : Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${track.artist}  ·  ${track.album.isEmpty ? "Archivo local" : track.album}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: _muted, fontSize: 10),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Reproducir',
                  onPressed: () => widget.onPlayTracks(queue, index, false),
                  icon: Icon(Icons.play_circle_outline_rounded, color: _cyan),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Más opciones',
                  icon: Icon(Icons.more_horiz_rounded, color: _muted),
                  onSelected: (value) {
                    if (value == 'favorite') widget.onToggleFavorite(track);
                    if (value == 'playlist') widget.onAddToPlaylist(track);
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'favorite',
                      child: Text(
                        widget.favoritePaths.contains(track.path)
                            ? 'Quitar de favoritos'
                            : 'Añadir a favoritos',
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'playlist',
                      child: Text('Añadir a playlist'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cover(Track? track, {IconData icon = Icons.music_note_rounded}) {
    final provider = _imageProvider(track);
    if (provider == null) return _coverPlaceholder(icon);
    return Image(
      image: provider,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => _coverPlaceholder(icon),
    );
  }

  ImageProvider<Object>? _imageProvider(Track? track) {
    final path = track?.coverPath;
    if (path == null || path.isEmpty) return null;
    return FileImage(File(path));
  }

  Widget _coverPlaceholder(IconData icon) => ColoredBox(
    color: const Color(0xFF252536),
    child: Center(child: Icon(icon, color: _cyan, size: 30)),
  );

  Widget _roundAction({
    required IconData icon,
    required VoidCallback onPressed,
  }) => Material(
    color: Colors.white,
    shape: const CircleBorder(),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onPressed,
      child: SizedBox(
        width: 38,
        height: 38,
        child: Icon(icon, color: const Color(0xFF11111A), size: 23),
      ),
    ),
  );

  Widget _emptyLibrary() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      CollectionHero(
        eyebrow: _isArtists ? 'DESCUBRE Y EXPLORA' : 'TU COLECCIÓN',
        title: _isArtists ? 'Artistas' : 'Álbumes',
        description: _isArtists
            ? 'Perfiles y canciones vinculados a tu biblioteca.'
            : 'Organiza tu música local por álbum y artista.',
        icon: _isArtists ? Icons.mic_rounded : Icons.album_rounded,
        count: 0,
        countLabel: _isArtists ? 'artistas' : 'álbumes',
        compact: widget.compact,
      ),
      const SizedBox(height: 22),
      _message(
        Icons.library_music_outlined,
        _isArtists
            ? 'Tus artistas aparecerán aquí'
            : 'Tus álbumes aparecerán aquí',
        'Agrega música a tu biblioteca para organizarla por ${_isArtists ? "artista." : "álbum."}',
      ),
    ],
  );

  Widget _emptyArtist(String name) => _message(
    Icons.graphic_eq_rounded,
    'Aún no tienes canciones de $name',
    'Puedes escuchar una estación relacionada con este artista.',
    buttonLabel: 'Iniciar radio del artista',
    onPressed: widget.onPlayArtistStation == null
        ? null
        : () => widget.onPlayArtistStation!(name),
  );

  Widget _noMatches() => _message(
    Icons.search_off_rounded,
    'No encontramos coincidencias',
    'Prueba con otro nombre o borra la búsqueda.',
  );

  Widget _message(
    IconData icon,
    String title,
    String subtitle, {
    String? buttonLabel,
    VoidCallback? onPressed,
  }) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: _surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFF29293A)),
    ),
    child: Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: _cyan.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: _cyan),
        ),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 5),
              Text(
                subtitle,
                style: TextStyle(color: _muted, fontSize: 11, height: 1.35),
              ),
              if (buttonLabel != null) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: onPressed,
                  icon: Icon(Icons.graphic_eq_rounded, size: 16),
                  label: Text(buttonLabel),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );

  List<_MediaGroup> _allAlbumGroups() {
    final buckets = <String, List<Track>>{};
    final names = <String, String>{};
    final artists = <String, String>{};
    for (final track in widget.tracks) {
      final artist = _clean(track.artist, 'Artista desconocido');
      final album = _clean(track.album, 'Álbum sin nombre');
      final key = 'album:${_normalize(album)}|${_normalize(artist)}';
      buckets.putIfAbsent(key, () => <Track>[]).add(track);
      names.putIfAbsent(key, () => album);
      artists.putIfAbsent(key, () => artist);
    }
    return buckets.entries.map((entry) {
        final songs = List<Track>.of(entry.value)
          ..sort(
            (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
          );
        return _MediaGroup(
          key: entry.key,
          title: names[entry.key]!,
          subtitle: artists[entry.key]!,
          tracks: songs,
        );
      }).toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  }

  List<_MediaGroup> _groupsForArtist(String artist) => _allAlbumGroups()
      .where((group) => _normalize(group.subtitle) == _normalize(artist))
      .toList(growable: false);
  _MediaGroup? _artistGroupByName(String artist) {
    for (final group in _groups()) {
      if (group.key.startsWith('artist:') &&
          _normalize(group.title) == _normalize(artist)) {
        return group;
      }
    }
    return null;
  }

  void _openArtist(String name) {
    final group = _artistGroupByName(name);
    setState(() {
      _selectedKey = group?.key ?? 'artist:${_normalize(name)}';
      _selectedName = group?.title ?? name;
      _artistSongResults = [];
      _artistSongsError = null;
    });
    unawaited(_loadArtistSongs(group?.title ?? name));
  }

  Future<void> _loadArtistSongs(
    String artist, {
    bool forceRefresh = false,
  }) async {
    final request = ++_artistSongRequest;
    setState(() {
      _loadingArtistSongs = true;
      _artistSongsError = null;
    });
    try {
      final songs = await ArtistSongDiscoveryService.instance.search(
        artist,
        forceRefresh: forceRefresh,
      );
      if (!mounted ||
          request != _artistSongRequest ||
          _selectedName?.toLowerCase() != artist.toLowerCase()) {
        return;
      }
      setState(() {
        _artistSongResults = songs;
        _loadingArtistSongs = false;
        _artistSongsError = songs.isEmpty
            ? 'No encontramos canciones para este artista.'
            : null;
      });
    } catch (_) {
      if (!mounted ||
          request != _artistSongRequest ||
          _selectedName?.toLowerCase() != artist.toLowerCase()) {
        return;
      }
      setState(() {
        _artistSongResults = [];
        _loadingArtistSongs = false;
        _artistSongsError = 'No se pudo cargar su música. Intenta de nuevo.';
      });
    }
  }

  void _select(_MediaGroup group) {
    setState(() {
      _selectedKey = group.key;
      _selectedName = group.title;
      _showingArtistAlbum = false;
    });
  }

  void _selectArtistAlbum(_MediaGroup group, String artist) {
    setState(() {
      _returnArtistKey = 'artist:${_normalize(artist)}';
      _returnArtistName = artist;
      _selectedKey = group.key;
      _selectedName = group.title;
      _showingArtistAlbum = true;
    });
  }

  String _trackText(int count) =>
      count.toString() + (count == 1 ? ' canción' : ' canciones');

  Widget _trackCount(int count) =>
      Text(_trackText(count), style: TextStyle(color: _muted, fontSize: 10));
}

class _MediaGroup {
  const _MediaGroup({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.tracks,
  });

  final String key;
  final String title;
  final String subtitle;
  final List<Track> tracks;
}
