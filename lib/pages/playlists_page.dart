import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/track.dart';
import '../widgets/library_content.dart';
import '../widgets/middle_content_panel.dart';

typedef PlayPlaylistTracks = Future<void> Function(List<Track>, int, bool);
typedef AddTracksToPlaylist = Future<void> Function(String, List<Track>);
typedef RemovePlaylistTrack = void Function(String, Track);
const _cyan = Color(0xFF83E8FF),
    _panel = Color(0xFF151522),
    _raised = Color(0xFF1D1D2B),
    _muted = Color(0xFF9292A5),
    _like = Color(0xFFFF5378);

class PlaylistsPage extends StatefulWidget {
  const PlaylistsPage({
    super.key,
    required this.config,
    required this.tracks,
    required this.playlists,
    required this.favoritePaths,
    required this.currentTrackPath,
    required this.isPlaying,
    required this.onPlayTracks,
    required this.onToggleFavorite,
    required this.onAddTracksToPlaylist,
    required this.onRemoveTrack,
  });
  final LibraryPageConfig config;
  final List<Track> tracks;
  final Map<String, List<String>> playlists;
  final Set<String> favoritePaths;
  final String? currentTrackPath;
  final bool isPlaying;
  final PlayPlaylistTracks onPlayTracks;
  final ValueChanged<Track> onToggleFavorite;
  final AddTracksToPlaylist onAddTracksToPlaylist;
  final RemovePlaylistTrack onRemoveTrack;
  @override
  State<PlaylistsPage> createState() => _PlaylistsPageState();
}

class _PlaylistsPageState extends State<PlaylistsPage> {
  bool _showLiked = false;
  String _query = '', _sort = 'added';
  final _search = TextEditingController();
  bool get _showPlaylist =>
      widget.config.playlistView != null &&
      widget.playlists.containsKey(widget.config.playlistView);
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MiddleContentPanel(
    section: 'Playlists',
    config: widget.config,
    showHeader: false,
    body: _showPlaylist || _showLiked ? _detail() : _library(),
  );

  Widget _library() {
    final liked = _likedSongs();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _libraryHero(widget.playlists.length + 1),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (context, box) {
            final columns = box.maxWidth >= 1060
                ? 4
                : box.maxWidth >= 690
                ? 3
                : 2;
            final gap = 18.0,
                width = (box.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: 22,
              children: [
                SizedBox(
                  width: width,
                  child: _playlistCard(
                    title: 'Me gusta',
                    subtitle: _count(liked.length),
                    songs: liked,
                    liked: true,
                    onTap: () => setState(() {
                      _showLiked = true;
                      _query = '';
                    }),
                    onPlay: liked.isEmpty
                        ? null
                        : () => widget.onPlayTracks(liked, 0, false),
                  ),
                ),
                ...widget.playlists.entries.map((entry) {
                  final songs = _songs(entry.key);
                  return SizedBox(
                    width: width,
                    child: _playlistCard(
                      title: entry.key,
                      subtitle: _count(songs.length),
                      songs: songs,
                      onTap: () => widget.config.onOpenPlaylist(entry.key),
                      onPlay: songs.isEmpty
                          ? null
                          : () => widget.onPlayTracks(songs, 0, false),
                      menu: PopupMenuButton<String>(
                        tooltip: 'Opciones de ${entry.key}',
                        onSelected: (action) =>
                            _playlistAction(action, entry.key),
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'rename',
                            child: Text('Cambiar nombre'),
                          ),
                          PopupMenuItem(
                            value: 'share',
                            child: Text('Compartir lista'),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text('Eliminar playlist'),
                          ),
                        ],
                        child: _moreButton,
                      ),
                    ),
                  );
                }),
              ],
            );
          },
        ),
        if (widget.playlists.isEmpty) ...[
          const SizedBox(height: 22),
          _empty(
            'Tu próxima playlist empieza aquí',
            'Crea una lista y organiza tus canciones por momento o estilo.',
            action: 'Crear playlist',
            onAction: widget.config.onCreatePlaylist,
          ),
        ],
        const SizedBox(height: 24),
        _surpriseMix(),
      ],
    );
  }

  Widget _libraryHero(int total) => Container(
    padding: const EdgeInsets.all(23),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF17424D), Color(0xFF18202D), Color(0xFF171722)],
      ),
      borderRadius: BorderRadius.circular(23),
      border: Border.all(color: _cyan.withValues(alpha: .26)),
      boxShadow: [
        BoxShadow(
          color: _cyan.withValues(alpha: .07),
          blurRadius: 26,
          spreadRadius: -8,
        ),
      ],
    ),
    child: Row(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: _cyan.withValues(alpha: .13),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _cyan.withValues(alpha: .2)),
          ),
          child: const Icon(Icons.queue_music_rounded, color: _cyan, size: 32),
        ),
        const SizedBox(width: 17),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'TU MÚSICA',
                style: TextStyle(
                  color: _cyan,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.8,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Tus playlists',
                style: TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$total colecciones listas para sonar',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Tooltip(
          message: 'Crear playlist',
          child: Material(
            color: Colors.white,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: widget.config.onCreatePlaylist,
              child: const SizedBox(
                width: 52,
                height: 52,
                child: Icon(
                  Icons.add_rounded,
                  color: Color(0xFF10131A),
                  size: 30,
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _playlistCard({
    required String title,
    required String subtitle,
    required List<Track> songs,
    required VoidCallback onTap,
    required VoidCallback? onPlay,
    bool liked = false,
    Widget? menu,
  }) {
    final accent = liked ? _like : _cyan;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: _raised,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _mosaic(songs, liked: liked),
                  if (menu != null) Positioned(top: 8, right: 8, child: menu),
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: Material(
                      color: Colors.white,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: onPlay,
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: Icon(
                            Icons.play_arrow_rounded,
                            color: onPlay == null ? _muted : accent,
                            size: 29,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: _muted, fontSize: 11),
        ),
      ],
    );
  }

  Widget _mosaic(List<Track> songs, {required bool liked}) {
    if (songs.isEmpty) {
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: liked
                ? const [
                    Color(0xFF7E293F),
                    Color(0xFF251A2B),
                    Color(0xFF181823),
                  ]
                : [_cyan, Color(0xFF20202E), Color(0xFF151522)],
          ),
        ),
        child: Center(
          child: Icon(
            liked ? Icons.favorite_rounded : Icons.queue_music_rounded,
            color: Colors.white,
            size: 58,
          ),
        ),
      );
    }
    return Column(
      children: [
        for (var row = 0; row < 2; row++)
          Expanded(
            child: Row(
              children: [
                for (var col = 0; col < 2; col++)
                  Expanded(child: _mosaicTile(songs, row * 2 + col)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _mosaicTile(List<Track> songs, int i) {
    if (i >= songs.length) {
      return const ColoredBox(
        color: Color(0xFF252532),
        child: Center(
          child: Icon(
            Icons.music_note_rounded,
            color: Colors.white24,
            size: 24,
          ),
        ),
      );
    }
    final path = songs[i].coverPath;
    if (path == null || path.isEmpty) return _placeholder();
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => _placeholder(),
    );
  }

  Widget _placeholder() => const ColoredBox(
    color: Color(0xFF292936),
    child: Center(
      child: Icon(Icons.music_note_rounded, color: _cyan, size: 28),
    ),
  );
  Widget _surpriseMix() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 17),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF253D45), Color(0xFF202131)],
      ),
      borderRadius: BorderRadius.circular(19),
      border: Border.all(color: _cyan.withValues(alpha: .19)),
    ),
    child: Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: _cyan.withValues(alpha: .13),
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Icon(Icons.shuffle_rounded, color: _cyan),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Mezcla sorpresa',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 4),
              Text(
                'Una combinación para descubrir tu música',
                style: TextStyle(color: _muted, fontSize: 11),
              ),
            ],
          ),
        ),
        IconButton.filled(
          tooltip: 'Reproducir mezcla sorpresa',
          onPressed: widget.tracks.isEmpty
              ? null
              : () => widget.onPlayTracks(widget.tracks, 0, true),
          style: IconButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF11111A),
          ),
          icon: const Icon(Icons.play_arrow_rounded),
        ),
      ],
    ),
  );

  Widget _detail() {
    final playlist = _showPlaylist ? widget.config.playlistView : null;
    final liked = !_showPlaylist && _showLiked;
    final title = liked ? 'Me gusta' : playlist!;
    final songs = liked ? _likedSongs() : _songs(playlist);
    final accent = liked ? _like : _cyan;
    final duration = songs.fold<int>(
      0,
      (sum, track) => sum + (track.durationMs ?? 0),
    );
    final visible = [...songs];
    if (_sort == 'title') {
      visible.sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );
    }
    if (_sort == 'artist') {
      visible.sort(
        (a, b) => a.artist.toLowerCase().compareTo(b.artist.toLowerCase()),
      );
    }
    final filtered = _query.isEmpty
        ? visible
        : visible
              .where(
                (track) =>
                    track.title.toLowerCase().contains(_query.toLowerCase()) ||
                    track.artist.toLowerCase().contains(_query.toLowerCase()) ||
                    track.album.toLowerCase().contains(_query.toLowerCase()),
              )
              .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _back(title),
        const SizedBox(height: 14),
        _detailHero(title, songs, duration, accent, liked ? null : playlist),
        const SizedBox(height: 17),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              if (!liked)
                _option(
                  Icons.edit_note_rounded,
                  'Editar',
                  accent,
                  () => widget.config.onRenamePlaylist(playlist!),
                ),
              if (!liked) const SizedBox(width: 8),
              _option(
                Icons.share_outlined,
                'Compartir',
                accent,
                () => _share(title, songs),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                tooltip: 'Ordenar canciones',
                onSelected: (value) => setState(() => _sort = value),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'added', child: Text('Orden original')),
                  PopupMenuItem(value: 'title', child: Text('Por título')),
                  PopupMenuItem(value: 'artist', child: Text('Por artista')),
                ],
                child: _option(
                  Icons.sort_rounded,
                  _sort == 'title'
                      ? 'Por título'
                      : _sort == 'artist'
                      ? 'Por artista'
                      : 'Orden original',
                  accent,
                ),
              ),
              if (!liked) ...[
                const SizedBox(width: 8),
                _option(
                  Icons.delete_outline_rounded,
                  'Eliminar',
                  const Color(0xFFFF7888),
                  () => _confirmDelete(playlist!),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _search,
          onChanged: (value) => setState(() => _query = value.trim()),
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Buscar en $title',
            hintStyle: const TextStyle(color: _muted, fontSize: 12),
            prefixIcon: const Icon(Icons.search_rounded, color: _cyan),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    onPressed: () {
                      _search.clear();
                      setState(() => _query = '');
                    },
                    icon: const Icon(Icons.close_rounded, color: _muted),
                  ),
            filled: true,
            fillColor: _panel,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: accent.withValues(alpha: .65)),
            ),
          ),
        ),
        const SizedBox(height: 14),
        if (filtered.isEmpty)
          _empty(
            _query.isNotEmpty
                ? 'No encontramos canciones'
                : liked
                ? 'Tu colección empieza aquí'
                : 'Esta playlist está vacía',
            _query.isNotEmpty
                ? 'Prueba con otro título o artista.'
                : liked
                ? 'Las canciones que marques con Me gusta aparecerán aquí.'
                : 'Agrega canciones desde tu biblioteca.',
            action: !liked ? 'Agregar canciones' : null,
            onAction: !liked ? () => _addSongs(playlist!) : null,
          )
        else
          ...filtered.map((track) {
            final index = songs.indexOf(track);
            return _songRow(
              track,
              index < 0 ? 0 : index,
              songs,
              playlist,
              liked,
              accent,
            );
          }),
      ],
    );
  }

  Widget _detailHero(
    String title,
    List<Track> songs,
    int duration,
    Color accent,
    String? playlist,
  ) => LayoutBuilder(
    builder: (context, box) {
      final compact = box.maxWidth < 670, size = compact ? 160.0 : 198.0;
      final cover = SizedBox(
        width: size,
        height: size,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: _mosaic(songs, liked: title == 'Me gusta'),
        ),
      );
      final description = Column(
        crossAxisAlignment: compact
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title == 'Me gusta' ? 'TU COLECCIÓN' : 'PLAYLIST',
            style: TextStyle(
              color: accent,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.7,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: compact ? TextAlign.center : TextAlign.left,
            style: TextStyle(
              fontSize: compact ? 27 : 34,
              height: 1.05,
              fontWeight: FontWeight.w900,
              letterSpacing: -.7,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${songs.length} ${songs.length == 1 ? 'canción' : 'canciones'} · ${_duration(duration)}',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: compact ? WrapAlignment.center : WrapAlignment.start,
            spacing: 9,
            runSpacing: 9,
            children: [
              if (playlist != null)
                _action(
                  Icons.add_rounded,
                  'Agregar',
                  accent,
                  () => _addSongs(playlist),
                ),
              _action(
                Icons.play_arrow_rounded,
                'Reproducir',
                accent,
                songs.isEmpty
                    ? null
                    : () => widget.onPlayTracks(songs, 0, false),
                primary: true,
              ),
              _roundAction(
                Icons.shuffle_rounded,
                'Aleatorio',
                accent,
                songs.isEmpty
                    ? null
                    : () => widget.onPlayTracks(songs, 0, true),
              ),
              _roundAction(
                Icons.share_outlined,
                'Compartir',
                accent,
                () => _share(title, songs),
              ),
            ],
          ),
        ],
      );
      return Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accent.withValues(alpha: .2),
              const Color(0xFF1B1D29),
              const Color(0xFF151520),
            ],
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: accent.withValues(alpha: .23)),
        ),
        child: compact
            ? Column(children: [cover, const SizedBox(height: 16), description])
            : Row(
                children: [
                  cover,
                  const SizedBox(width: 22),
                  Expanded(child: description),
                ],
              ),
      );
    },
  );

  Widget _back(String title) => Row(
    children: [
      IconButton(
        tooltip: 'Volver a tus playlists',
        onPressed: () {
          if (_showLiked) {
            setState(() {
              _showLiked = false;
              _query = '';
              _search.clear();
            });
          } else {
            widget.config.onOpenPlaylist('Playlists');
          }
        },
        icon: const Icon(Icons.arrow_back_rounded, color: _cyan),
      ),
      const SizedBox(width: 5),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'TU COLECCIÓN',
              style: TextStyle(
                color: _cyan,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
      if (!_showLiked)
        PopupMenuButton<String>(
          tooltip: 'Opciones de playlist',
          onSelected: (action) => _playlistAction(action, title),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'rename', child: Text('Cambiar nombre')),
            PopupMenuItem(value: 'share', child: Text('Compartir lista')),
            PopupMenuItem(value: 'delete', child: Text('Eliminar playlist')),
          ],
          icon: const Icon(Icons.more_horiz_rounded, color: Colors.white70),
        ),
    ],
  );

  Widget _songRow(
    Track track,
    int index,
    List<Track> queue,
    String? playlist,
    bool liked,
    Color accent,
  ) {
    final active = widget.currentTrackPath == track.path;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: active ? accent.withValues(alpha: .11) : _raised,
        borderRadius: BorderRadius.circular(15),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => widget.onPlayTracks(queue, index, false),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 31,
                  child: Center(
                    child: active && widget.isPlaying
                        ? Icon(Icons.equalizer_rounded, color: accent, size: 18)
                        : Text(
                            '${index + 1}'.padLeft(2, '0'),
                            style: const TextStyle(color: _muted, fontSize: 10),
                          ),
                  ),
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(width: 45, height: 45, child: _cover(track)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title.isEmpty
                            ? track.path.split(Platform.pathSeparator).last
                            : track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: active ? accent : Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${track.artist}${track.album.isEmpty ? '' : ' · ${track.album}'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _muted, fontSize: 10),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Reproducir',
                  onPressed: () => widget.onPlayTracks(queue, index, false),
                  icon: Icon(Icons.play_circle_outline_rounded, color: accent),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Opciones de canción',
                  onSelected: (value) {
                    if (value == 'favorite') widget.onToggleFavorite(track);
                    if (value == 'remove') {
                      if (liked) {
                        widget.onToggleFavorite(track);
                      } else if (playlist != null) {
                        widget.onRemoveTrack(playlist, track);
                      }
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'favorite',
                      child: Text(
                        widget.favoritePaths.contains(track.path)
                            ? 'Quitar de Me gusta'
                            : 'Agregar a Me gusta',
                      ),
                    ),
                    PopupMenuItem(
                      value: 'remove',
                      child: Text(
                        liked ? 'Quitar de Me gusta' : 'Quitar de playlist',
                      ),
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

  Widget _action(
    IconData icon,
    String label,
    Color accent,
    VoidCallback? onTap, {
    bool primary = false,
  }) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: Ink(
        decoration: BoxDecoration(
          gradient: primary
              ? const LinearGradient(
                  colors: [Color(0xFFB6F5FF), _cyan, Color(0xFF56C9E6)],
                )
              : null,
          color: primary ? null : const Color(0xAA1D1D2B),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: primary ? Colors.white38 : accent.withValues(alpha: .3),
          ),
          boxShadow: primary
              ? [BoxShadow(color: accent.withValues(alpha: .2), blurRadius: 12)]
              : const [],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: primary ? Colors.black : accent),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  color: primary ? Colors.black : Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  Widget _roundAction(
    IconData icon,
    String label,
    Color accent,
    VoidCallback? onTap,
  ) => Tooltip(
    message: label,
    child: Material(
      color: _panel,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 43,
          height: 43,
          child: Icon(icon, color: accent, size: 19),
        ),
      ),
    ),
  );
  Widget _option(
    IconData icon,
    String label,
    Color accent, [
    VoidCallback? onTap,
  ]) => Material(
    color: accent.withValues(alpha: .08),
    borderRadius: BorderRadius.circular(24),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: accent.withValues(alpha: .24)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: accent),
            const SizedBox(width: 7),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    ),
  );
  Widget get _moreButton => Material(
    color: const Color(0xCC151522),
    shape: const CircleBorder(),
    child: const SizedBox(
      width: 34,
      height: 34,
      child: Icon(Icons.more_horiz_rounded, color: Colors.white, size: 19),
    ),
  );

  Widget _empty(
    String title,
    String message, {
    String? action,
    VoidCallback? onAction,
  }) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: _panel,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Colors.white.withValues(alpha: .06)),
    ),
    child: Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: _cyan.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Icon(Icons.queue_music_rounded, color: _cyan),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                message,
                style: const TextStyle(
                  color: _muted,
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
              if (action != null && onAction != null)
                TextButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: Text(action),
                ),
            ],
          ),
        ),
      ],
    ),
  );
  Widget _cover(Track track) {
    final path = track.coverPath;
    if (path == null || path.isEmpty) return _placeholder();
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => _placeholder(),
    );
  }

  List<Track> _likedSongs() => widget.tracks
      .where((track) => widget.favoritePaths.contains(track.path))
      .toList(growable: false);
  List<Track> _songs(String? name) {
    if (name == null) return const [];
    final byPath = {for (final track in widget.tracks) track.path: track};
    return (widget.playlists[name] ?? const <String>[])
        .map((path) => byPath[path])
        .whereType<Track>()
        .toList(growable: false);
  }

  String _count(int count) =>
      'Playlist · $count ${count == 1 ? 'canción' : 'canciones'}';
  String _duration(int ms) {
    final seconds = (ms / 1000).round(),
        hours = seconds ~/ 3600,
        minutes = (seconds % 3600) ~/ 60,
        remainder = seconds % 60;
    return hours > 0
        ? '$hours h ${minutes.toString().padLeft(2, '0')} min'
        : '$minutes:${remainder.toString().padLeft(2, '0')} min';
  }

  Future<void> _playlistAction(String action, String name) async {
    if (action == 'rename') {
      widget.config.onRenamePlaylist(name);
    } else if (action == 'share') {
      await _share(name, _songs(name));
    } else if (action == 'delete') {
      await _confirmDelete(name);
    }
  }

  Future<void> _confirmDelete(String name) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _panel,
        title: const Text('Eliminar playlist'),
        content: Text(
          'Se eliminará "$name". Las canciones seguirán en tu biblioteca.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB9505C),
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (result == true && mounted) widget.config.onDeletePlaylist(name);
  }

  Future<void> _share(String title, List<Track> songs) async {
    final text = StringBuffer('SoundNeed · $title\n');
    for (var i = 0; i < songs.length; i++) {
      text.writeln('${i + 1}. ${songs[i].title} — ${songs[i].artist}');
    }
    await Clipboard.setData(ClipboardData(text: text.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lista copiada para compartir.')),
      );
    }
  }

  Future<void> _addSongs(String playlist) async {
    final already = (widget.playlists[playlist] ?? const <String>[]).toSet();
    final candidates = widget.tracks
        .where((track) => !already.contains(track.path))
        .toList(growable: false);
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay más canciones en tu biblioteca para agregar.'),
        ),
      );
      return;
    }
    final selected = <String>{};
    var query = '';
    final chosen = await showDialog<List<Track>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) {
          final visible = candidates
              .where(
                (track) =>
                    track.title.toLowerCase().contains(query.toLowerCase()) ||
                    track.artist.toLowerCase().contains(query.toLowerCase()) ||
                    track.album.toLowerCase().contains(query.toLowerCase()),
              )
              .toList(growable: false);
          return AlertDialog(
            backgroundColor: _panel,
            title: Text('Agregar a $playlist'),
            content: SizedBox(
              width: 520,
              height: 460,
              child: Column(
                children: [
                  TextField(
                    autofocus: true,
                    onChanged: (value) => update(() => query = value.trim()),
                    decoration: InputDecoration(
                      hintText: 'Buscar en tu biblioteca',
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: _cyan,
                      ),
                      filled: true,
                      fillColor: _raised,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.builder(
                      itemCount: visible.length,
                      itemBuilder: (context, i) {
                        final track = visible[i],
                            checked = selected.contains(visible[i].path);
                        return CheckboxListTile(
                          value: checked,
                          activeColor: _cyan,
                          checkColor: const Color(0xFF11111A),
                          secondary: ClipRRect(
                            borderRadius: BorderRadius.circular(7),
                            child: SizedBox(
                              width: 42,
                              height: 42,
                              child: _cover(track),
                            ),
                          ),
                          title: Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: _muted, fontSize: 11),
                          ),
                          onChanged: (value) => update(() {
                            if (value == true) {
                              selected.add(track.path);
                            } else {
                              selected.remove(track.path);
                            }
                          }),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                onPressed: selected.isEmpty
                    ? null
                    : () => Navigator.pop(
                        context,
                        candidates
                            .where((track) => selected.contains(track.path))
                            .toList(),
                      ),
                icon: const Icon(Icons.playlist_add_rounded),
                label: Text('Agregar ${selected.length}'),
              ),
            ],
          );
        },
      ),
    );
    if (chosen != null && chosen.isNotEmpty) {
      await widget.onAddTracksToPlaylist(playlist, chosen);
    }
  }
}
