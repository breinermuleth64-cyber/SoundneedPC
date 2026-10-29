import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ListeningHistoryProfile {
  const ListeningHistoryProfile({
    required this.preferredArtists,
    required this.searchedArtists,
    required this.recentTrackKeys,
    required this.trackPlayCounts,
  });

  final List<String> preferredArtists;
  final List<String> searchedArtists;
  final Set<String> recentTrackKeys;
  final Map<String, int> trackPlayCounts;
}

class ListeningHistoryService {
  ListeningHistoryService._();

  static final instance = ListeningHistoryService._();
  static const _storageKey = 'soundneed_pc_listening_history_v1';
  static const _searchStorageKey = 'soundneed_pc_music_search_history_v1';
  static const _historyWindow = Duration(days: 90);
  static const _recentWindow = Duration(days: 7);
  static const _maxRecords = 250;

  Future<ListeningHistoryProfile> load() async {
    final preferences = await SharedPreferences.getInstance();
    return _profile(
      _read(preferences.getString(_storageKey)),
      _readSearches(preferences.getString(_searchStorageKey)),
    );
  }

  Future<ListeningHistoryProfile> recordSearch({
    required String query,
    required Iterable<String> resultArtists,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final searches = _readSearches(
      preferences.getString(_searchStorageKey),
    )..removeWhere((entry) => now.difference(entry.searchedAt).inDays > 90);
    final candidates = <String>{
      ...resultArtists.map((artist) => artist.trim()).where((artist) => artist.isNotEmpty),
    };
    if (candidates.isEmpty && query.trim().isNotEmpty) {
      candidates.add(query.trim());
    }
    for (final artist in candidates.toList().reversed) {
      final key = _normalize(artist);
      final repeatedRecently = searches.any(
        (entry) =>
            _normalize(entry.artist) == key &&
            now.difference(entry.searchedAt) < const Duration(hours: 12),
      );
      if (!repeatedRecently) searches.insert(0, _SearchEntry(artist, now));
    }
    if (searches.length > 120) searches.removeRange(120, searches.length);
    await preferences.setString(
      _searchStorageKey,
      jsonEncode(searches.map((entry) => entry.toJson()).toList()),
    );
    return _profile(
      _read(preferences.getString(_storageKey)),
      searches,
    );
  }

  Future<ListeningHistoryProfile> record({
    required String title,
    required String artist,
  }) async {
    final cleanTitle = title.trim();
    final cleanArtist = artist.trim();
    if (cleanTitle.isEmpty || cleanArtist.isEmpty) return load();

    final preferences = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final cutoff = now.subtract(_historyWindow);
    final records = _read(preferences.getString(_storageKey))
      ..removeWhere((entry) => entry.playedAt.isBefore(cutoff));
    final key = _trackKey(cleanTitle, cleanArtist);
    final justPlayed = records.any(
      (entry) =>
          _trackKey(entry.title, entry.artist) == key &&
          now.difference(entry.playedAt) < const Duration(minutes: 1),
    );
    if (!justPlayed) {
      records.insert(0, _ListeningEntry(cleanTitle, cleanArtist, now));
    }
    if (records.length > _maxRecords) {
      records.removeRange(_maxRecords, records.length);
    }
    await preferences.setString(
      _storageKey,
      jsonEncode(records.map((entry) => entry.toJson()).toList()),
    );
    return _profile(
      records,
      _readSearches(preferences.getString(_searchStorageKey)),
    );
  }

  List<_ListeningEntry> _read(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final values = jsonDecode(raw) as List? ?? const [];
      final cutoff = DateTime.now().subtract(_historyWindow);
      return values
          .whereType<Map>()
          .map(
            (value) =>
                _ListeningEntry.fromJson(Map<String, dynamic>.from(value)),
          )
          .where(
            (entry) =>
                entry.title.isNotEmpty &&
                entry.artist.isNotEmpty &&
                !entry.playedAt.isBefore(cutoff),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  ListeningHistoryProfile _profile(
    List<_ListeningEntry> records,
    List<_SearchEntry> searches,
  ) {
    final cutoff = DateTime.now().subtract(_recentWindow);
    final scores = <String, int>{};
    final names = <String, String>{};
    final recentTrackKeys = <String>{};
    final trackScores = <String, int>{};
    for (final entry in records) {
      final artistKey = _normalize(entry.artist);
      if (artistKey.isEmpty) continue;
      names.putIfAbsent(artistKey, () => entry.artist);
      scores.update(artistKey, (score) => score + 1, ifAbsent: () => 1);
      final trackKey = _trackKey(entry.title, entry.artist);
      trackScores.update(trackKey, (score) => score + 1, ifAbsent: () => 1);
      if (!entry.playedAt.isBefore(cutoff)) {
        recentTrackKeys.add(trackKey);
      }
    }
    final artists = scores.keys.toList()
      ..sort((a, b) => scores[b]!.compareTo(scores[a]!));
    final rankedTrackKeys = trackScores.keys.toList()
      ..sort((a, b) => trackScores[b]!.compareTo(trackScores[a]!));
    final searchedNames = <String, String>{};
    for (final entry in searches) {
      searchedNames.putIfAbsent(_normalize(entry.artist), () => entry.artist);
    }
    return ListeningHistoryProfile(
      preferredArtists: List.unmodifiable(artists.map((key) => names[key]!)),
      searchedArtists: List.unmodifiable(searchedNames.values),
      recentTrackKeys: Set.unmodifiable(recentTrackKeys),
      trackPlayCounts: Map.unmodifiable({
        for (final key in rankedTrackKeys) key: trackScores[key]!,
      }),
    );
  }

  List<_SearchEntry> _readSearches(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final values = jsonDecode(raw) as List? ?? const [];
      final cutoff = DateTime.now().subtract(const Duration(days: 90));
      return values
          .whereType<Map>()
          .map(
            (value) => _SearchEntry.fromJson(Map<String, dynamic>.from(value)),
          )
          .where(
            (entry) =>
                entry.artist.isNotEmpty && !entry.searchedAt.isBefore(cutoff),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  String _trackKey(String title, String artist) =>
      '${_normalize(title)}|${_normalize(artist)}';

  String _normalize(String value) => value
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
}

class _SearchEntry {
  const _SearchEntry(this.artist, this.searchedAt);

  final String artist;
  final DateTime searchedAt;

  Map<String, Object?> toJson() => {
    'artist': artist,
    'searchedAt': searchedAt.toIso8601String(),
  };

  factory _SearchEntry.fromJson(Map<String, dynamic> json) => _SearchEntry(
    json['artist']?.toString() ?? '',
    DateTime.tryParse(json['searchedAt']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );
}

String listeningTrackKey(String title, String artist) {
  String normalize(String value) => value
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
  return '${normalize(title)}|${normalize(artist)}';
}

class _ListeningEntry {
  const _ListeningEntry(this.title, this.artist, this.playedAt);

  final String title;
  final String artist;
  final DateTime playedAt;

  Map<String, Object?> toJson() => {
    'title': title,
    'artist': artist,
    'playedAt': playedAt.toIso8601String(),
  };

  factory _ListeningEntry.fromJson(Map<String, dynamic> json) =>
      _ListeningEntry(
        json['title']?.toString() ?? '',
        json['artist']?.toString() ?? '',
        DateTime.tryParse(json['playedAt']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}
