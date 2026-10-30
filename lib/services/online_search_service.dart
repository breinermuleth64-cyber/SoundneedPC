import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class OnlineSearchResult {
  const OnlineSearchResult({
    required this.videoId,
    required this.title,
    required this.artist,
    required this.thumbnail,
    required this.durationSeconds,
  });

  final String videoId;
  final String title;
  final String artist;
  final String thumbnail;
  final int durationSeconds;
}

class OnlineSearchService {
  OnlineSearchService._();
  static final instance = OnlineSearchService._();
  static const _cacheDuration = Duration(minutes: 10);
  final _youtube = YoutubeExplode();
  final Map<String, _CachedOnlineSearch> _cache = {};
  final Map<String, Future<List<OnlineSearchResult>>> _pending = {};

  static OnlineSearchResult? bestTrackMatch({
    required Iterable<OnlineSearchResult> candidates,
    required String title,
    required String artist,
  }) {
    final requestedTitle = _matchTokens(title);
    final requestedArtist = _matchTokens(artist);
    if (requestedTitle.isEmpty) return null;
    OnlineSearchResult? best;
    var bestScore = -1.0;
    for (final candidate in candidates) {
      if (!RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(candidate.videoId) ||
          candidate.title.trim().isEmpty) {
        continue;
      }
      if (candidate.durationSeconds > 0 &&
          (candidate.durationSeconds < 45 ||
              candidate.durationSeconds > 1200)) {
        continue;
      }
      final candidateTitle = _matchTokens(candidate.title);
      final candidateArtist = _matchTokens(candidate.artist);
      final titleOverlap =
          requestedTitle.intersection(candidateTitle).length /
          requestedTitle.length;
      final artistOverlap =
          requestedArtist.isEmpty
              ? 0.0
              : requestedArtist.intersection(candidateArtist).length /
                    requestedArtist.length;
      final titleContainsArtist =
          requestedArtist.isNotEmpty &&
          candidateTitle.containsAll(requestedArtist);
      final strongTitleMatch =
          requestedTitle.length > 1 && titleOverlap >= 0.85;
      // Official uploads often expose a label or channel as the author, so
      // accept a very strong title match even when the artist field differs.
      if (titleOverlap < 0.55 ||
          (requestedArtist.isNotEmpty &&
              artistOverlap < 0.35 &&
              !titleContainsArtist &&
              !strongTitleMatch)) {
        continue;
      }
      final score =
          titleOverlap * 4 +
          artistOverlap * 2 +
          (candidate.durationSeconds >= 60 ? 0.25 : 0);
      if (score > bestScore) {
        best = candidate;
        bestScore = score;
      }
    }
    return best;
  }

  static Set<String> _matchTokens(String value) => value
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ü', 'u')
      .replaceAll('ñ', 'n')
      .replaceAll(
        RegExp(r'\b(topic|official|audio|video|lyrics?|vevo|visualizer|music)\b'),
        ' ',
      )
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .split(' ')
      .where((token) => token.length > 1)
      .toSet();

  Future<List<OnlineSearchResult>> search(String query) {
    final value = query.trim();
    if (value.isEmpty) return Future.value(const []);
    final key = value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final cached = _cache[key];
    if (cached != null &&
        DateTime.now().difference(cached.savedAt) < _cacheDuration) {
      return Future.value(cached.results);
    }
    return _pending.putIfAbsent(key, () => _fetch(value, key));
  }

  Future<List<OnlineSearchResult>> _fetch(String query, String key) async {
    try {
      final videos = await _youtube.search
          .search(query)
          .timeout(const Duration(seconds: 15));
      final results = videos
          .take(30)
          .map(
            (video) => OnlineSearchResult(
              videoId: video.id.value,
              title: video.title,
              artist: video.author,
              thumbnail: video.thumbnails.highResUrl,
              durationSeconds: video.duration?.inSeconds ?? 0,
            ),
          )
          .where(
            (track) =>
                RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(track.videoId) &&
                track.title.trim().isNotEmpty,
          )
          .toList(growable: false);
      _cache[key] = _CachedOnlineSearch(results, DateTime.now());
      if (_cache.length > 128) _cache.remove(_cache.keys.first);
      return results;
    } catch (_) {
      return [];
    } finally {
      _pending.remove(key);
    }
  }
}

class _CachedOnlineSearch {
  const _CachedOnlineSearch(this.results, this.savedAt);

  final List<OnlineSearchResult> results;
  final DateTime savedAt;
}
