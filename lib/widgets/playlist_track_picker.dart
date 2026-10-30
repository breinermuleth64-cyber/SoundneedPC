import 'dart:io';

import 'package:flutter/material.dart';

import '../models/track.dart';
import '../services/playlist_search_service.dart';
import '../services/online_search_service.dart';
import '../services/playlist_library_service.dart';

const _pickerCyan = Color(0xFF83E8FF);
const _pickerPanel = Color(0xFF151522);
const _pickerRaised = Color(0xFF1D1D2B);
const _pickerMuted = Color(0xFF9292A5);

class PlaylistTrackPicker extends StatefulWidget {
  const PlaylistTrackPicker({
    required this.playlistName,
    required this.tracks,
    required this.alreadyIncludedPaths,
    super.key,
  });

  final String playlistName;
  final List<Track> tracks;
  final Set<String> alreadyIncludedPaths;

  @override
  State<PlaylistTrackPicker> createState() => _PlaylistTrackPickerState();
}

class _PlaylistTrackPickerState extends State<PlaylistTrackPicker> {
  final _search = TextEditingController();
  final _selected = <String>{};
  String _query = '';
  bool _showOnline = false;
  List<OnlineSearchResult> _onlineResults = [];
  bool _onlineSearching = false;
  String? _onlineError;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Track> get _candidates => widget.tracks
      .where((track) => !widget.alreadyIncludedPaths.contains(track.path))
      .toList(growable: false);

  List<Track> get _visible =>
      PlaylistSearchService.filterTracks(_candidates, _query);

  Future<void> _searchOnline(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _onlineResults = [];
        _onlineError = null;
      });
      return;
    }
    setState(() {
      _onlineSearching = true;
      _onlineError = null;
    });
    final results = await OnlineSearchService.instance.search(query);
    if (!mounted) return;
    setState(() {
      _onlineResults = results;
      _onlineSearching = false;
      _onlineError = results.isEmpty
          ? 'No encontramos resultados. Prueba con otra búsqueda.'
          : null;
    });
  }

  void _toggleVisible() {
    final visiblePaths = _visible.map((track) => track.path).toSet();
    final allSelected =
        visiblePaths.isNotEmpty && visiblePaths.every(_selected.contains);
    setState(() {
      if (allSelected) {
        _selected.removeAll(visiblePaths);
      } else {
        _selected.addAll(visiblePaths);
      }
    });
  }

  Widget _cover(Track track) {
    final path = track.coverPath;
    if (path == null || path.isEmpty) return _placeholder();
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => _placeholder(),
    );
  }

  Widget _placeholder() => const ColoredBox(
    color: _pickerRaised,
    child: Center(
      child: Icon(Icons.music_note_rounded, color: _pickerMuted, size: 19),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final candidates = _candidates;
    final visible = _visible;
    return AlertDialog(
      backgroundColor: _pickerPanel,
      titlePadding: const EdgeInsets.fromLTRB(22, 20, 18, 8),
      contentPadding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
      title: Row(
        children: [
          const Icon(Icons.playlist_add_rounded, color: _pickerCyan),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Agregar a ${widget.playlistName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  _showOnline
                      ? 'Buscar música online'
                      : '${candidates.length} canciones disponibles',
                  style: const TextStyle(color: _pickerMuted, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 560,
        height: 470,
        child: Column(
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Text('Biblioteca'),
                  icon: Icon(Icons.library_music_rounded),
                ),
                ButtonSegment(
                  value: true,
                  label: Text('Online'),
                  icon: Icon(Icons.cloud_rounded),
                ),
              ],
              selected: {_showOnline},
              onSelectionChanged: (Set<bool> selected) {
                setState(() {
                  _showOnline = selected.first;
                  _query = '';
                  _search.clear();
                  _onlineResults = [];
                  _onlineError = null;
                });
              },
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return _pickerCyan;
                  }
                  return _pickerRaised;
                }),
                foregroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return const Color(0xFF11111A);
                  }
                  return Colors.white;
                }),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _search,
              autofocus: true,
              onChanged: (value) {
                setState(() => _query = value);
                if (_showOnline) {
                  _searchOnline(value);
                }
              },
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: _showOnline
                    ? 'Buscar en YouTube'
                    : 'Buscar por canción, artista o álbum',
                hintStyle: const TextStyle(color: _pickerMuted, fontSize: 12),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: _pickerCyan,
                ),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpiar búsqueda',
                        onPressed: () {
                          _search.clear();
                          setState(() {
                            _query = '';
                            if (_showOnline) {
                              _onlineResults = [];
                              _onlineError = null;
                            }
                          });
                        },
                        icon: const Icon(
                          Icons.close_rounded,
                          color: _pickerMuted,
                        ),
                      ),
                filled: true,
                fillColor: _pickerRaised,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: const BorderSide(color: _pickerCyan),
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (!_showOnline)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: visible.isEmpty ? null : _toggleVisible,
                  icon: Icon(
                    visible.isNotEmpty &&
                            visible.every(
                              (track) => _selected.contains(track.path),
                            )
                        ? Icons.deselect_rounded
                        : Icons.library_add_check_rounded,
                    size: 17,
                  ),
                  label: Text(
                    visible.isNotEmpty &&
                            visible.every(
                              (track) => _selected.contains(track.path),
                            )
                        ? 'Quitar selección visible'
                        : 'Seleccionar visibles',
                  ),
                ),
              ),
            const SizedBox(height: 4),
            Expanded(
              child: _showOnline
                  ? _buildOnlineList()
                  : _buildLibraryList(candidates, visible),
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
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.pop(
                  context,
                  _showOnline
                      ? _buildSelectedOnlineTracks()
                      : _candidates
                          .where((track) => _selected.contains(track.path))
                          .toList(growable: false),
                ),
          icon: const Icon(Icons.playlist_add_rounded),
          label: Text('Agregar ${_selected.length}'),
        ),
      ],
    );
  }

  Widget _buildLibraryList(List<Track> candidates, List<Track> visible) {
    return visible.isEmpty
        ? Center(
            child: Text(
              candidates.isEmpty
                  ? 'Ya agregaste toda tu música a esta playlist.'
                  : 'No encontramos canciones. Prueba otra búsqueda.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _pickerMuted),
            ),
          )
        : ListView.separated(
            itemCount: visible.length,
            separatorBuilder: (_, _) =>
                const Divider(height: 1, color: Color(0xFF2B2B3B)),
            itemBuilder: (context, index) {
              final track = visible[index];
              final selected = _selected.contains(track.path);
              return CheckboxListTile(
                value: selected,
                activeColor: _pickerCyan,
                checkColor: const Color(0xFF11111A),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 4,
                ),
                secondary: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 42,
                    height: 42,
                    child: _cover(track),
                  ),
                ),
                title: Text(
                  track.title.isEmpty ? 'Canción sin título' : track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  track.album.isEmpty
                      ? track.artist
                      : '${track.artist} · ${track.album}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _pickerMuted,
                    fontSize: 11,
                  ),
                ),
                onChanged: (value) => setState(() {
                  if (value == true) {
                    _selected.add(track.path);
                  } else {
                    _selected.remove(track.path);
                  }
                }),
              );
            },
          );
  }

  Widget _buildOnlineList() {
    if (_onlineSearching) {
      return const Center(
        child: CircularProgressIndicator(color: _pickerCyan),
      );
    }
    if (_onlineError != null) {
      return Center(
        child: Text(
          _onlineError!,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _pickerMuted),
        ),
      );
    }
    if (_onlineResults.isEmpty && _query.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_rounded, color: _pickerCyan, size: 48),
            const SizedBox(height: 12),
            const Text(
              'Busca música online',
              style: TextStyle(color: _pickerMuted),
            ),
          ],
        ),
      );
    }
    if (_onlineResults.isEmpty) {
      return const Center(
        child: Text(
          'No encontramos resultados. Prueba con otra búsqueda.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _pickerMuted),
        ),
      );
    }
    return ListView.separated(
      itemCount: _onlineResults.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, color: Color(0xFF2B2B3B)),
      itemBuilder: (context, index) {
        final result = _onlineResults[index];
        final selected = _selected.contains(result.videoId);
        return CheckboxListTile(
          value: selected,
          activeColor: _pickerCyan,
          checkColor: const Color(0xFF11111A),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 4,
          ),
          secondary: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 42,
              height: 42,
              child: _onlineCover(result),
            ),
          ),
          title: Text(
            result.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            result.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _pickerMuted,
              fontSize: 11,
            ),
          ),
          onChanged: (value) => setState(() {
            if (value == true) {
              _selected.add(result.videoId);
            } else {
              _selected.remove(result.videoId);
            }
          }),
        );
      },
    );
  }

  Widget _onlineCover(OnlineSearchResult result) {
    return Image.network(
      result.thumbnail,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => _placeholder(),
    );
  }

  List<Track> _buildSelectedOnlineTracks() {
    return _onlineResults
        .where((result) => _selected.contains(result.videoId))
        .map((result) {
      final metadata = Track(
        path: '',
        title: result.title,
        artist: result.artist,
        coverPath: result.thumbnail,
        durationMs: result.durationSeconds * 1000,
      );
      return Track(
        path: PlaylistLibraryService.encodeOnlineTrack(metadata, result.videoId),
        title: metadata.title,
        artist: metadata.artist,
        coverPath: metadata.coverPath,
        durationMs: metadata.durationMs,
      );
    }).toList();
  }
}
