import 'dart:convert';

import 'package:http/http.dart' as http;

class ArtistCatalogEntry {
  const ArtistCatalogEntry({
    required this.name,
    required this.pictureUrl,
    this.fanCount,
  });

  final String name;
  final String pictureUrl;
  final int? fanCount;
}

class ArtistCatalogService {
  ArtistCatalogService._();

  static final instance = ArtistCatalogService._();
  static const _cacheAge = Duration(hours: 6);

  final Map<String, _CachedArtist> _artists = {};
  final Map<String, Future<ArtistCatalogEntry?>> _pending = {};
  final Map<String, _CachedArtistList> _searches = {};
  final Map<String, Future<List<ArtistCatalogEntry>>> _searchPending = {};
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
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
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
