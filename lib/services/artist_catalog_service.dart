import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ArtistCatalogEntry {
  const ArtistCatalogEntry({
    this.id = '',
    required this.name,
    required this.pictureUrl,
    this.fanCount,
  });

  final String id;
  final String name;
  final String pictureUrl;
  final int? fanCount;
}

class ArtistCatalogTrack {
  const ArtistCatalogTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.artworkUrl,
  });

  final String id;
  final String title;
  final String artist;
  final String artworkUrl;
}

class ArtistCatalogService {
  ArtistCatalogService._();

  static final instance = ArtistCatalogService._();
  static const _cacheAge = Duration(hours: 6);

  @visibleForTesting
  String normalizeArtistNameForTesting(String value) => _normalize(value);

  final Map<String, _CachedArtist> _artists = {};
  final Map<String, Future<ArtistCatalogEntry?>> _pending = {};
  final Map<String, _CachedArtistList> _searches = {};
  final Map<String, Future<List<ArtistCatalogEntry>>> _searchPending = {};
  final Map<String, _CachedArtistList> _related = {};
  final Map<String, Future<List<ArtistCatalogEntry>>> _relatedPending = {};
  final Map<String, _CachedCatalogTracks> _artistTracks = {};
  final Map<String, Future<List<ArtistCatalogTrack>>> _artistTrackPending = {};
  final http.Client _client = http.Client();

  Future<ArtistCatalogEntry?> lookup(String name) {
    final query = name.trim();
    if (query.isEmpty) return Future.value(null);
    final key = _normalize(query);
    final cached = _artists[key];
    if (cached != null &&
        DateTime.now().difference(cached.savedAt) < _cacheAge) {
      return Future.value(cached.entry);
    }
    return _pending.putIfAbsent(key, () => _fetchExact(query, key));
  }

  Future<List<ArtistCatalogEntry>> searchArtists(
    String query, {
    int limit = 12,
  }) {
    final value = query.trim();
    if (value.isEmpty) return Future.value(const []);
    final key = _normalize(value);
    final cached = _searches[key];
    if (cached != null &&
        DateTime.now().difference(cached.savedAt) < _cacheAge) {
      return Future.value(cached.entries.take(limit).toList(growable: false));
    }
    return _searchPending.putIfAbsent(key, () => _search(value, key, limit));
  }

  Future<List<ArtistCatalogEntry>> relatedArtists(
    String artist, {
    bool forceRefresh = false,
  }) {
    final query = artist.trim();
    if (query.isEmpty) return Future.value(const []);
    final key = _normalize(query);
    final cached = _related[key];
    if (!forceRefresh &&
        cached != null &&
        DateTime.now().difference(cached.savedAt) < _cacheAge) {
      return Future.value(cached.entries);
    }
    return _relatedPending.putIfAbsent(key, () => _fetchRelated(query, key));
  }

  Future<List<ArtistCatalogTrack>> tracksForArtist(
    ArtistCatalogEntry artist, {
    int limit = 20,
    bool forceRefresh = false,
  }) {
    if (artist.id.isEmpty) return Future.value(const []);
    final key = artist.id;
    final cached = _artistTracks[key];
    if (!forceRefresh &&
        cached != null &&
        DateTime.now().difference(cached.savedAt) < _cacheAge) {
      return Future.value(cached.tracks.take(limit).toList(growable: false));
    }
    return _artistTrackPending.putIfAbsent(
      key,
      () => _fetchArtistTracks(artist, key, limit),
    );
  }

  Future<List<ArtistCatalogEntry>> _fetchRelated(
    String query,
    String key,
  ) async {
    try {
      final matches = await searchArtists(query, limit: 8);
      ArtistCatalogEntry? artist;
      for (final match in matches) {
        if (_normalize(match.name) == key) {
          artist = match;
          break;
        }
      }
      // A fuzzy first search result can belong to a different artist. Never
      // build a relationship graph from it; an empty result is safer than
      // showing recommendations for the wrong seed.
      if (artist == null || artist.id.isEmpty) return const [];
      final response = await _client
          .get(
            Uri.https('api.deezer.com', '/artist/${artist.id}/related'),
            headers: const {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return const [];
      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['data'] is! List) return const [];
      final entries = (decoded['data'] as List)
          .map(_parse)
          .whereType<ArtistCatalogEntry>()
          .where((entry) => entry.id.isNotEmpty)
          .toList(growable: false);
      _related[key] = _CachedArtistList(entries, DateTime.now());
      return List.unmodifiable(entries);
    } catch (_) {
      return const [];
    } finally {
      _relatedPending.remove(key);
    }
  }

  Future<List<ArtistCatalogTrack>> _fetchArtistTracks(
    ArtistCatalogEntry artist,
    String key,
    int limit,
  ) async {
    try {
      final response = await _client
          .get(
            Uri.https('api.deezer.com', '/artist/$key/top', {
              'limit': '$limit',
            }),
            headers: const {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return const [];
      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['data'] is! List) return const [];
      final tracks = <ArtistCatalogTrack>[];
      for (final value in decoded['data'] as List) {
        if (value is! Map) continue;
        final title = value['title']?.toString().trim() ?? '';
        final id = value['id']?.toString() ?? '';
        final album = value['album'];
        final cover = album is Map
            ? (album['cover_xl'] ?? album['cover_big'] ?? album['cover_medium'])
                      ?.toString()
                      .trim() ??
                  ''
            : '';
        if (title.isEmpty || id.isEmpty) continue;
        tracks.add(
          ArtistCatalogTrack(
            id: id,
            title: title,
            artist: artist.name,
            artworkUrl: cover,
          ),
        );
      }
      _artistTracks[key] = _CachedCatalogTracks(tracks, DateTime.now());
      return List.unmodifiable(tracks);
    } catch (_) {
      return const [];
    } finally {
      _artistTrackPending.remove(key);
    }
  }

  Future<List<ArtistCatalogEntry>> _search(
    String query,
    String key,
    int limit,
  ) async {
    try {
      final response = await _client
          .get(
            Uri.https('api.deezer.com', '/search/artist', {'q': query}),
            headers: const {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return const [];
      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['data'] is! List) return const [];

      final entries = <ArtistCatalogEntry>[];
      final seen = <String>{};
      for (final value in decoded['data'] as List) {
        final entry = _parse(value);
        if (entry == null || !seen.add(_normalize(entry.name))) continue;
        entries.add(entry);
        _artists[_normalize(entry.name)] = _CachedArtist(entry, DateTime.now());
        if (entries.length >= limit) break;
      }
      _searches[key] = _CachedArtistList(entries, DateTime.now());
      return List.unmodifiable(entries);
    } catch (_) {
      return const [];
    } finally {
      _searchPending.remove(key);
    }
  }

  Future<ArtistCatalogEntry?> _fetchExact(String query, String key) async {
    try {
      final response = await _client
          .get(
            Uri.https('api.deezer.com', '/search/artist', {'q': query}),
            headers: const {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return _cacheNull(key);
      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['data'] is! List) return _cacheNull(key);
      for (final value in decoded['data'] as List) {
        final entry = _parse(value);
        if (entry == null || _normalize(entry.name) != key) continue;
        _artists[key] = _CachedArtist(entry, DateTime.now());
        return entry;
      }
      return _cacheNull(key);
    } catch (_) {
      return _cacheNull(key);
    } finally {
      _pending.remove(key);
    }
  }

  ArtistCatalogEntry? _parse(Object? value) {
    if (value is! Map) return null;
    final name = value['name']?.toString().trim() ?? '';
    final picture =
        (value['picture_xl'] ?? value['picture_big'] ?? value['picture_medium'])
            ?.toString()
            .trim();
    if (name.isEmpty || picture == null || !picture.startsWith('https://')) {
      return null;
    }
    final rawFans = value['nb_fan'];
    return ArtistCatalogEntry(
      id: value['id']?.toString() ?? '',
      name: name,
      pictureUrl: picture,
      fanCount: rawFans is num
          ? rawFans.toInt()
          : int.tryParse(rawFans.toString()),
    );
  }

  ArtistCatalogEntry? _cacheNull(String key) {
    _artists[key] = _CachedArtist(null, DateTime.now());
    return null;
  }

  String _normalize(String value) =>
      value
          .toLowerCase()
          .replaceAll('á', 'a')
          .replaceAll('à', 'a')
          .replaceAll('ä', 'a')
          .replaceAll('â', 'a')
          .replaceAll('é', 'e')
          .replaceAll('è', 'e')
          .replaceAll('ë', 'e')
          .replaceAll('ê', 'e')
          .replaceAll('í', 'i')
          .replaceAll('ì', 'i')
          .replaceAll('ï', 'i')
          .replaceAll('î', 'i')
          .replaceAll('ó', 'o')
          .replaceAll('ò', 'o')
          .replaceAll('ö', 'o')
          .replaceAll('ô', 'o')
          .replaceAll('ú', 'u')
          .replaceAll('ù', 'u')
          .replaceAll('ü', 'u')
          .replaceAll('û', 'u')
          .replaceAll('ñ', 'n')
          .replaceAll('ç', 'c')
          .replaceAll(RegExp(r'[^a-z0-9]'), '');
}

class _CachedArtist {
  const _CachedArtist(this.entry, this.savedAt);

  final ArtistCatalogEntry? entry;
  final DateTime savedAt;
}

class _CachedArtistList {
  const _CachedArtistList(this.entries, this.savedAt);

  final List<ArtistCatalogEntry> entries;
  final DateTime savedAt;
}

class _CachedCatalogTracks {
  const _CachedCatalogTracks(this.tracks, this.savedAt);

  final List<ArtistCatalogTrack> tracks;
  final DateTime savedAt;
}
