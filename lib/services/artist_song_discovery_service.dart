import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class ArtistSongResult {
  const ArtistSongResult({
    required this.videoId,
    required this.title,
    required this.artist,
    required this.artworkUrl,
    required this.durationSeconds,
  });

  final String videoId;
  final String title;
  final String artist;
  final String artworkUrl;
  final int durationSeconds;
}

/// Searches a single artist's catalog and keeps a short cache so opening the
/// same profile does not repeat network requests.
class ArtistSongDiscoveryService {
  ArtistSongDiscoveryService._();

  static final instance = ArtistSongDiscoveryService._();
  static const _cacheDuration = Duration(minutes: 30);
  final YoutubeExplode _youtube = YoutubeExplode();
  final Map<String, _CachedArtistSongs> _cache = {};
  final Map<String, Future<List<ArtistSongResult>>> _pending = {};

  Future<List<ArtistSongResult>> search(
    String artist, {
    bool forceRefresh = false,
  }) {
    final query = artist.trim();
    if (query.isEmpty) return Future.value(const []);
    final key = _normalize(query);
    final cached = _cache[key];
    if (!forceRefresh &&
        cached != null &&
        DateTime.now().difference(cached.savedAt) < _cacheDuration) {
      return Future.value(cached.songs);
    }
    return _pending.putIfAbsent(key, () => _fetch(query, key));
  }

  Future<List<ArtistSongResult>> _fetch(String artist, String key) async {
    try {
      final seen = <String>{};
      final songs = <ArtistSongResult>[];
      for (final query in ['$artist canciones', '$artist songs']) {
        try {
          final results = await _youtube.search
              .search(query)
              .timeout(const Duration(seconds: 12));
          for (final video in results) {
            final id = video.id.value;
            final title = video.title.trim();
            if (id.isEmpty || title.isEmpty || !seen.add(id)) continue;
            songs.add(
              ArtistSongResult(
                videoId: id,
                title: title,
                artist: video.author.trim().isEmpty
                    ? artist
                    : video.author.trim(),
                artworkUrl: video.thumbnails.highResUrl,
                durationSeconds: video.duration?.inSeconds ?? 0,
              ),
            );
            if (songs.length >= 15) break;
          }
          if (songs.length >= 10) break;
        } catch (_) {
          // Keep the other query as a fallback when one search request fails.
        }
      }
      final result = List<ArtistSongResult>.unmodifiable(songs);
      _cache[key] = _CachedArtistSongs(result, DateTime.now());
      return result;
    } finally {
      _pending.remove(key);
    }
  }

  String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9áéíóúüñ]+'), ' ').trim();
}

class _CachedArtistSongs {
  const _CachedArtistSongs(this.songs, this.savedAt);

  final List<ArtistSongResult> songs;
  final DateTime savedAt;
}
