import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/track.dart';

/// Owns playlist persistence and mutations for the Windows library.
///
/// The `playlists.v1` shape stays compatible with existing installations:
/// each playlist name maps to an ordered list of local paths or encoded online
/// tracks.
class PlaylistLibraryService {
  PlaylistLibraryService._();

  static final instance = PlaylistLibraryService._();
  static const storageKey = 'playlists.v1';
  static const onlineTrackPrefix = 'soundneed-online:';

  static String encodeOnlineTrack(Track track, String videoId) {
    final payload = jsonEncode({
      'id': videoId,
      'title': track.title,
      'artist': track.artist,
      'thumbnail': track.coverPath ?? '',
      'durationSeconds': ((track.durationMs ?? 0) / 1000).round(),
    });
    return '$onlineTrackPrefix${base64Url.encode(utf8.encode(payload))}';
  }

  static Track? decodeOnlineTrack(String key) {
    if (!key.startsWith(onlineTrackPrefix)) return null;
    try {
      final payload = jsonDecode(utf8.decode(base64Url.decode(
        base64Url.normalize(key.substring(onlineTrackPrefix.length)),
      ))) as Map<String, dynamic>;
      final thumbnail = payload['thumbnail'] as String? ?? '';
      return Track(
        path: key,
        title: payload['title'] as String? ?? '',
        artist: payload['artist'] as String? ?? '',
        coverPath: thumbnail,
        durationMs: ((payload['durationSeconds'] as num?)?.toInt() ?? 0) * 1000,
      );
    } catch (_) {
      return null;
    }
  }

  static String? onlineVideoId(String key) {
    if (!key.startsWith(onlineTrackPrefix)) return null;
    try {
      final payload = jsonDecode(utf8.decode(base64Url.decode(
        base64Url.normalize(key.substring(onlineTrackPrefix.length)),
      ))) as Map<String, dynamic>;
      return payload['id'] as String?;
    } catch (_) {
      return null;
    }
  }

  final Map<String, List<String>> _playlists = {};

  Map<String, List<String>> get playlists => Map.unmodifiable({
    for (final entry in _playlists.entries)
      entry.key: List<String>.unmodifiable(entry.value),
  });

  void restore(String? raw) {
    _playlists.clear();
    if (raw == null || raw.isEmpty) return;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      for (final entry in decoded.entries) {
        final name = entry.key.toString().trim();
        final savedPaths = entry.value;
        if (name.isEmpty || savedPaths is! List) continue;
        final paths = <String>[];
        final seen = <String>{};
        for (final value in savedPaths) {
          if (value is! String) continue;
          final path = value.trim();
          if (path.isNotEmpty && seen.add(path)) paths.add(path);
        }
        _playlists[name] = paths;
      }
    } catch (_) {
      // Keep a damaged preference isolated instead of preventing library load.
    }
  }

  Future<bool> create(String requestedName) async {
    final name = requestedName.trim();
    if (name.isEmpty || _containsName(name)) return false;
    _playlists[name] = [];
    await save();
    return true;
  }

  Future<bool> rename(String currentName, String requestedName) async {
    final name = requestedName.trim();
    if (name.isEmpty || !_playlists.containsKey(currentName)) return false;
    if (name != currentName && _containsName(name, excluding: currentName)) {
      return false;
    }
    if (name == currentName) return true;

    final renamed = <String, List<String>>{};
    for (final entry in _playlists.entries) {
      renamed[entry.key == currentName ? name : entry.key] = entry.value;
    }
    _playlists
      ..clear()
      ..addAll(renamed);
    await save();
    return true;
  }

  Future<void> delete(String name) async {
    if (_playlists.remove(name) != null) await save();
  }

  Future<int> addTracks(String name, Iterable<String> paths) async {
    final playlist = _playlists[name];
    if (playlist == null) return 0;
    final seen = playlist.toSet();
    var added = 0;
    for (final path in paths) {
      final cleanPath = path.trim();
      if (cleanPath.isEmpty || !seen.add(cleanPath)) continue;
      playlist.add(cleanPath);
      added++;
    }
    if (added > 0) await save();
    return added;
  }

  Future<void> removeTrack(String name, String path) async {
    final playlist = _playlists[name];
    if (playlist == null) return;
    final oldLength = playlist.length;
    playlist.removeWhere((item) => item == path);
    if (playlist.length != oldLength) await save();
  }

  Future<void> removeMissingTracks(Set<String> paths) async {
    if (paths.isEmpty) return;
    var changed = false;
    for (final playlist in _playlists.values) {
      final oldLength = playlist.length;
      playlist.removeWhere(paths.contains);
      changed = changed || playlist.length != oldLength;
    }
    if (changed) await save();
  }

  Future<void> save() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(storageKey, jsonEncode(_playlists));
  }

  bool _containsName(String name, {String? excluding}) => _playlists.keys.any(
    (existing) =>
        existing != excluding && existing.toLowerCase() == name.toLowerCase(),
  );
}
