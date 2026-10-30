import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

/// Records user interactions with explore recommendations to improve future suggestions.
class ExploreFeedbackService {
  ExploreFeedbackService._();

  static final instance = ExploreFeedbackService._();
  static const _storageKey = 'soundneed_explore_feedback_v1';
  static const _maxRecords = 500;

  final Map<String, _FeedbackRecord> _records = {};
  bool _loaded = false;

  @visibleForTesting
  void resetForTesting() {
    _records.clear();
    _loaded = false;
  }

  Future<void> initialize() => _load();

  Future<void> _load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      _loaded = true;
      return;
    }
    try {
      final values = jsonDecode(raw) as List? ?? const [];
      for (final value in values) {
        if (value is! Map) continue;
        final record = _FeedbackRecord.fromJson(Map<String, dynamic>.from(value));
        _records[record.trackKey] = record;
      }
    } catch (_) {
      // Corrupt data, start fresh
    }
    _loaded = true;
  }

  Future<void> recordInteraction({
    required String title,
    required String artist,
    required FeedbackType type,
    Duration? listenDuration,
  }) async {
    await _load();
    final trackKey = _trackKey(title, artist);
    final existing = _records[trackKey];
    final now = DateTime.now();

    final updated = _FeedbackRecord(
      trackKey: trackKey,
      title: title,
      artist: artist,
      clickCount: (existing?.clickCount ?? 0) + (type == FeedbackType.click ? 1 : 0),
      skipCount: (existing?.skipCount ?? 0) + (type == FeedbackType.skip ? 1 : 0),
      likeCount: (existing?.likeCount ?? 0) + (type == FeedbackType.like ? 1 : 0),
      addToPlaylistCount:
          (existing?.addToPlaylistCount ?? 0) + (type == FeedbackType.addToPlaylist ? 1 : 0),
      completeCount: (existing?.completeCount ?? 0) + (type == FeedbackType.complete ? 1 : 0),
      totalListenSeconds: (existing?.totalListenSeconds ?? 0) + (listenDuration?.inSeconds ?? 0),
      lastInteraction: now,
      firstSeen: existing?.firstSeen ?? now,
    );

    _records[trackKey] = updated;
    await _save();
  }

  double getAffinityScore(String title, String artist) {
    final trackKey = _trackKey(title, artist);
    final record = _records[trackKey];
    if (record == null) return 0.0;

    // Positive signals
    final positiveScore =
        (record.likeCount * 10.0) +
        (record.addToPlaylistCount * 8.0) +
        (record.completeCount * 5.0) +
        (record.clickCount * 1.0);

    // Negative signals
    final negativeScore = record.skipCount * 3.0;

    // Listen duration factor (bonus for substantial listens)
    final durationBonus = record.totalListenSeconds > 30 ? 2.0 : 0.0;

    // Recency decay (older interactions have less weight)
    final daysSinceLast = DateTime.now().difference(record.lastInteraction).inDays;
    final recencyFactor = (1.0 / (1.0 + daysSinceLast * 0.1)).clamp(0.1, 1.0);

    final rawScore = (positiveScore - negativeScore + durationBonus) * recencyFactor;
    return rawScore.clamp(0.0, 100.0);
  }

  /// A bounded, per-artist signal derived only from explicit user actions.
  /// Averaging by track prevents a single frequently clicked song from
  /// overwhelming the user's listening-history preference.
  double getArtistAffinityScore(String artist) {
    final artistKey = _normalize(artist);
    final matching = _records.values
        .where((record) => _normalize(record.artist) == artistKey)
        .toList(growable: false);
    if (matching.isEmpty) return 0;
    final now = DateTime.now();
    final average = matching
            .map((record) {
              final positive =
                  record.likeCount * 10.0 +
                  record.addToPlaylistCount * 8.0 +
                  record.completeCount * 5.0;
              final negative = record.skipCount * 3.0;
              final recency =
                  1.0 /
                  (1.0 +
                      now.difference(record.lastInteraction).inDays * 0.1);
              return (positive - negative) * recency;
            })
            .fold<double>(0, (sum, value) => sum + value) /
        matching.length;
    return average.clamp(-30.0, 30.0);
  }

  bool shouldShowAgain(String title, String artist) {
    final trackKey = _trackKey(title, artist);
    final record = _records[trackKey];
    if (record == null) return true;

    // If user skipped multiple times, don't show again
    if (record.skipCount >= 3) return false;

    // If shown recently and user didn't interact positively, deprioritize
    final daysSinceLast = DateTime.now().difference(record.lastInteraction).inDays;
    if (daysSinceLast < 1 && record.clickCount == 0 && record.likeCount == 0) {
      return false;
    }

    return true;
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final values = _records.values.toList();
    if (values.length > _maxRecords) {
      // Keep most recent
      values.sort((a, b) => b.lastInteraction.compareTo(a.lastInteraction));
      values.removeRange(_maxRecords, values.length);
    }
    await prefs.setString(
      _storageKey,
      jsonEncode(values.map((r) => r.toJson()).toList()),
    );
  }

  String _trackKey(String title, String artist) {
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

enum FeedbackType {
  click,
  skip,
  like,
  addToPlaylist,
  complete,
}

class _FeedbackRecord {
  const _FeedbackRecord({
    required this.trackKey,
    required this.title,
    required this.artist,
    required this.clickCount,
    required this.skipCount,
    required this.likeCount,
    required this.addToPlaylistCount,
    required this.completeCount,
    required this.totalListenSeconds,
    required this.lastInteraction,
    required this.firstSeen,
  });

  final String trackKey;
  final String title;
  final String artist;
  final int clickCount;
  final int skipCount;
  final int likeCount;
  final int addToPlaylistCount;
  final int completeCount;
  final int totalListenSeconds;
  final DateTime lastInteraction;
  final DateTime firstSeen;

  Map<String, Object?> toJson() => {
    'trackKey': trackKey,
    'title': title,
    'artist': artist,
    'clickCount': clickCount,
    'skipCount': skipCount,
    'likeCount': likeCount,
    'addToPlaylistCount': addToPlaylistCount,
    'completeCount': completeCount,
    'totalListenSeconds': totalListenSeconds,
    'lastInteraction': lastInteraction.toIso8601String(),
    'firstSeen': firstSeen.toIso8601String(),
  };

  factory _FeedbackRecord.fromJson(Map<String, dynamic> json) => _FeedbackRecord(
    trackKey: json['trackKey']?.toString() ?? '',
    title: json['title']?.toString() ?? '',
    artist: json['artist']?.toString() ?? '',
    clickCount: json['clickCount'] as int? ?? 0,
    skipCount: json['skipCount'] as int? ?? 0,
    likeCount: json['likeCount'] as int? ?? 0,
    addToPlaylistCount: json['addToPlaylistCount'] as int? ?? 0,
    completeCount: json['completeCount'] as int? ?? 0,
    totalListenSeconds: json['totalListenSeconds'] as int? ?? 0,
    lastInteraction:
        DateTime.tryParse(json['lastInteraction']?.toString() ?? '') ?? DateTime.now(),
    firstSeen:
        DateTime.tryParse(json['firstSeen']?.toString() ?? '') ?? DateTime.now(),
  );
}
