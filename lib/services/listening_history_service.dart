import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ListeningHistoryProfile {
  const ListeningHistoryProfile({
    required this.preferredArtists,
    required this.recentTrackKeys,
  });

  final List<String> preferredArtists;
  final Set<String> recentTrackKeys;
}

class ListeningHistoryService {
  ListeningHistoryService._();

  static final instance = ListeningHistoryService._();
  static const _storageKey = 'soundneed_pc_listening_history_v1';
  static const _historyWindow = Duration(days: 90);
  static const _recentWindow = Duration(days: 7);
  static const _maxRecords = 250;

  Future<ListeningHistoryProfile> load() async {
    final preferences = await SharedPreferences.getInstance();
    return _profile(_read(preferences.getString(_storageKey)));
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
    return _profile(records);
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

  ListeningHistoryProfile _profile(List<_ListeningEntry> records) {
    final cutoff = DateTime.now().subtract(_recentWindow);
    final scores = <String, int>{};
    final names = <String, String>{};
    final recentTrackKeys = <String>{};
    for (final entry in records) {
      final artistKey = _normalize(entry.artist);
      if (artistKey.isEmpty) continue;
      names.putIfAbsent(artistKey, () => entry.artist);
      scores.update(artistKey, (score) => score + 1, ifAbsent: () => 1);
      if (!entry.playedAt.isBefore(cutoff)) {
        recentTrackKeys.add(_trackKey(entry.title, entry.artist));
      }
    }
    final artists = scores.keys.toList()
      ..sort((a, b) => scores[b]!.compareTo(scores[a]!));
    return ListeningHistoryProfile(
      preferredArtists: List.unmodifiable(artists.map((key) => names[key]!)),
      recentTrackKeys: Set.unmodifiable(recentTrackKeys),
    );
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
