import 'dart:math' as math;

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'artist_catalog_service.dart';
import 'listening_history_service.dart';

class ExploreRecommendation {
  const ExploreRecommendation({
    required this.id,
    required this.title,
    required this.artist,
    required this.artworkUrl,
    required this.seedArtist,
    this.videoId,
    required this.score,
    required this.reason,
  });

  final String id;
  final String title;
  final String artist;
  final String artworkUrl;
  final String seedArtist;
  final String? videoId;
  final double score;
  final String reason;
}

class ExploreDiscoveryFeed {
  const ExploreDiscoveryFeed({required this.recommendations, required this.seeds});

  final List<ExploreRecommendation> recommendations;
  final List<String> seeds;
}

/// Finds related online artists from listening history and ranks their catalog.
class ExploreDiscoveryService {
  ExploreDiscoveryService._();

  static final instance = ExploreDiscoveryService._();

  Future<ExploreDiscoveryFeed> discover({
    required ListeningHistoryProfile history,
    required YoutubeExplode youtube,
    bool refresh = false,
    int limit = 12,
  }) async {
    final seeds = <String>[];
    final seedKeys = <String>{};
    for (final artist in history.preferredArtists) {
      final value = artist.trim();
      if (value.isEmpty || !seedKeys.add(_normalize(value))) continue;
      seeds.add(value);
      if (seeds.length == 3) break;
    }
    if (seeds.isEmpty) {
      return const ExploreDiscoveryFeed(recommendations: [], seeds: []);
    }

    final catalog = ArtistCatalogService.instance;
    final relatedBySeed = await Future.wait(
      seeds.map((seed) async => (
        seed: seed,
        artists: (await catalog.relatedArtists(
          seed,
          forceRefresh: refresh,
        )).take(4).toList(),
      )),
    );
    final related = <(String, ArtistCatalogEntry)>[];
    final seenArtists = <String>{...seeds.map(_normalize)};
    for (final group in relatedBySeed) {
      for (final artist in group.artists) {
        if (seenArtists.add(_normalize(artist.name))) {
          related.add((group.seed, artist));
        }
      }
    }
    final primaryArtists = await Future.wait(
      relatedBySeed
          .where((group) => group.artists.isEmpty)
          .map((group) async => (group.seed, await catalog.lookup(group.seed))),
    );
    for (final entry in primaryArtists) {
      final artist = entry.$2;
      if (artist != null && artist.id.isNotEmpty) {
        related.add((entry.$1, artist));
      }
    }
    final groups = await Future.wait(
      related.map((item) async => (
        seed: item.$1,
        artist: item.$2,
        tracks: await catalog.tracksForArtist(
          item.$2,
          limit: 12,
          forceRefresh: refresh,
        ),
      )),
    );

    final heard = <String>{
      ...history.trackPlayCounts.keys,
      ...history.recentTrackKeys,
    };
    final heardTitles = heard
        .map((key) => key.split('|').first)
        .where((title) => title.isNotEmpty)
        .toSet();
    final candidates = <_ScoredRecommendation>[];
    final seenTracks = <String>{};
    var insertionOrder = 0;
    for (final group in groups) {
      for (final track in group.tracks) {
        final key = listeningTrackKey(track.title, track.artist);
        if (heard.contains(key) ||
            heardTitles.contains(_normalize(track.title)) ||
            !seenTracks.add(key)) {
          continue;
        }
        final seedIndex = seeds.indexWhere(
          (seed) => _normalize(seed) == _normalize(group.seed),
        );
        final affinity = (100 - seedIndex.clamp(0, 4) * 12).toDouble();
        final historySignal = (100 - seedIndex.clamp(0, 4) * 15).toDouble();
        const novelty = 100.0;
        final popularity = _popularity(group.artist.fanCount);
        const diversity = 100.0;
        final metadata = track.title.isNotEmpty &&
                track.artist.isNotEmpty &&
                track.artworkUrl.startsWith('https://')
            ? 100.0
            : 55.0;
        final score = .30 * affinity +
            .20 * historySignal +
            .15 * novelty +
            .15 * popularity +
            .10 * diversity +
            .10 * metadata;
        candidates.add(
          _ScoredRecommendation(
            ExploreRecommendation(
              id: track.id,
              title: track.title,
              artist: track.artist,
              artworkUrl: track.artworkUrl,
              seedArtist: group.seed,
              score: score,
              reason: _normalize(track.artist) == _normalize(group.seed)
                  ? 'Más canciones de ${group.seed}'
                  : 'Relacionado con ${group.seed}',
            ),
            insertionOrder++,
          ),
        );
      }
    }

    if (candidates.length < limit) {
      final fallback = await _searchOnlineRelated(
        youtube: youtube,
        seeds: seeds,
        history: history,
        excludedTitles: seenTracks,
        firstOrder: insertionOrder,
      );
      candidates.addAll(fallback);
    }

    final selected = <ExploreRecommendation>[];
    final artistCounts = <String, int>{};
    final remaining = List<_ScoredRecommendation>.of(candidates);
    while (remaining.isNotEmpty && selected.length < limit) {
      remaining.sort((a, b) {
        final adjustedA = a.value.score -
            (artistCounts[_normalize(a.value.artist)] ?? 0) * 18;
        final adjustedB = b.value.score -
            (artistCounts[_normalize(b.value.artist)] ?? 0) * 18;
        final order = adjustedB.compareTo(adjustedA);
        return order == 0 ? a.order.compareTo(b.order) : order;
      });
      final next = remaining.removeAt(0).value;
      selected.add(next);
      final key = _normalize(next.artist);
      artistCounts.update(key, (count) => count + 1, ifAbsent: () => 1);
    }
    return ExploreDiscoveryFeed(
      recommendations: List.unmodifiable(selected),
      seeds: List.unmodifiable(seeds),
    );
  }

  double _popularity(int? fans) {
    if (fans == null || fans <= 0) return 20;
    return (math.log(fans + 1) / math.log(100000001) * 100)
        .clamp(0.0, 100.0)
        .toDouble();
  }

  Future<List<_ScoredRecommendation>> _searchOnlineRelated({
    required YoutubeExplode youtube,
    required List<String> seeds,
    required ListeningHistoryProfile history,
    required Set<String> excludedTitles,
    required int firstOrder,
  }) async {
    final heardTitles = <String>{
      ...history.trackPlayCounts.keys.map((key) => key.split('|').first),
      ...history.recentTrackKeys.map((key) => key.split('|').first),
    };
    final candidates = <_ScoredRecommendation>[];
    final seenTitles = <String>{...heardTitles};
    for (final key in excludedTitles) {
      seenTitles.add(key.split('|').first);
    }
    final seenVideoIds = <String>{};
    var order = firstOrder;

    for (var pass = 0; pass < 2 && candidates.length < 12; pass++) {
      final results = await Future.wait([
        for (final seed in seeds)
          () async {
            final query = pass == 0
                ? '$seed canciones similares'
                : 'artistas parecidos a $seed canciones';
            try {
              return await youtube.search
                  .search(query)
                  .timeout(const Duration(seconds: 12));
            } catch (_) {
              return null;
            }
          }(),
      ]);
      for (var seedIndex = 0; seedIndex < results.length; seedIndex++) {
        final videos = results[seedIndex];
        if (videos == null) continue;
        final seed = seeds[seedIndex];
        for (final video in videos.take(18)) {
          final title = video.title.trim();
          final artist = video.author.trim();
          final id = video.id.value;
          final titleKey = _normalize(title);
          if (title.isEmpty ||
              artist.isEmpty ||
              id.isEmpty ||
              !seenVideoIds.add(id) ||
              !seenTitles.add(titleKey) ||
              _normalize(artist) == _normalize(seed)) {
            continue;
          }
          final duration = video.duration?.inSeconds ?? 0;
          if (duration > 0 && duration < 50) continue;
          final metadata = video.thumbnails.highResUrl.isNotEmpty
              ? 90.0
              : 70.0;
          final affinity = (82 - seedIndex * 9).toDouble();
          final historySignal = (78 - seedIndex * 8).toDouble();
          const novelty = 100.0;
          const popularity = 20.0;
          const diversity = 85.0;
          final score = .30 * affinity +
              .20 * historySignal +
              .15 * novelty +
              .15 * popularity +
              .10 * diversity +
              .10 * metadata;
          candidates.add(
            _ScoredRecommendation(
              ExploreRecommendation(
                id: id,
                videoId: id,
                title: title,
                artist: artist,
                artworkUrl: video.thumbnails.highResUrl,
                seedArtist: seed,
                score: score,
                reason: 'Descubierto desde tu búsqueda de $seed',
              ),
              order++,
            ),
          );
          if (candidates.length >= 18) break;
        }
      }
    }
    if (candidates.isEmpty) {
      final results = await Future.wait([
        for (final seed in seeds)
          () async {
            try {
              return await youtube.search
                  .search('$seed canciones')
                  .timeout(const Duration(seconds: 12));
            } catch (_) {
              return null;
            }
          }(),
      ]);
      for (var seedIndex = 0; seedIndex < results.length; seedIndex++) {
        final videos = results[seedIndex];
        if (videos == null) continue;
        final seed = seeds[seedIndex];
        for (final video in videos.take(18)) {
          final title = video.title.trim();
          final artist = video.author.trim();
          final id = video.id.value;
          final titleKey = _normalize(title);
          if (title.isEmpty ||
              artist.isEmpty ||
              id.isEmpty ||
              !seenVideoIds.add(id) ||
              !seenTitles.add(titleKey)) {
            continue;
          }
          final duration = video.duration?.inSeconds ?? 0;
          if (duration > 0 && duration < 50) continue;
          candidates.add(
            _ScoredRecommendation(
              ExploreRecommendation(
                id: id,
                videoId: id,
                title: title,
                artist: artist,
                artworkUrl: video.thumbnails.highResUrl,
                seedArtist: seed,
                score: 62 - seedIndex * 8,
                reason: 'Más música basada en tu búsqueda de $seed',
              ),
              order++,
            ),
          );
          if (candidates.length >= 12) break;
        }
      }
    }
    return candidates;
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

class _ScoredRecommendation {
  const _ScoredRecommendation(this.value, this.order);
  final ExploreRecommendation value;
  final int order;
}
