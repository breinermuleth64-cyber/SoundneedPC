import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

class HomeChartTrack {
  const HomeChartTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.artworkUrl,
    required this.rank,
  });

  final String id;
  final String title;
  final String artist;
  final String artworkUrl;
  final int rank;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'artworkUrl': artworkUrl,
    'rank': rank,
  };

  factory HomeChartTrack.fromJson(
    Map<String, dynamic> json,
    int fallbackRank,
  ) => HomeChartTrack(
    id: json['id']?.toString() ?? '',
    title: json['title']?.toString() ?? '',
    artist: json['artist']?.toString() ?? '',
    artworkUrl: json['artworkUrl']?.toString() ?? '',
    rank: (json['rank'] as num?)?.toInt() ?? fallbackRank,
  );
}

class HomeChartArtist {
  const HomeChartArtist({
    required this.name,
    required this.artworkUrl,
    required this.rank,
    required this.songs,
    required this.snapshotDays,
  });

  final String name;
  final String artworkUrl;
  final int rank;
  final List<HomeChartTrack> songs;
  final int snapshotDays;
}

class HomeChartsService {
  HomeChartsService._();

  static final HomeChartsService instance = HomeChartsService._();
  static const _colombiaKey = 'soundneed_pc_home_colombia_chart_v1';
  static const _worldKey = 'soundneed_pc_home_world_chart_v1';
  static const _worldSnapshotKey = 'soundneed_pc_world_artist_snapshots_v1';
  static const _cacheAge = Duration(minutes: 45);
  static const _worldMarkets = [
    'us',
    'gb',
    'mx',
    'br',
    'ca',
    'au',
    'es',
    'de',
    'fr',
    'jp',
    'kr',
    'in',
  ];

  Future<List<HomeChartTrack>> loadColombia({bool refresh = false}) =>
      _loadChart(
        key: _colombiaKey,
        refresh: refresh,
        fetch: () => _fetchMarket('co'),
      );

  Future<List<HomeChartTrack>> loadWorld({bool refresh = false}) =>
      _loadChart(key: _worldKey, refresh: refresh, fetch: _fetchWorld);

  Future<List<HomeChartArtist>> rankWorldArtists(
    List<HomeChartTrack> currentChart,
  ) async {
    if (currentChart.isEmpty) return const [];
    final preferences = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(days: 30));
    final snapshots = <Map<String, dynamic>>[];
    final raw = preferences.getString(_worldSnapshotKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as List? ?? const [];
        snapshots.addAll(
          decoded.whereType<Map>().map(Map<String, dynamic>.from).where((item) {
            final date = DateTime.tryParse(item['date']?.toString() ?? '');
            return date != null && !date.isBefore(cutoff);
          }),
        );
      } catch (_) {
        snapshots.clear();
      }
    }
    final today = _dayKey(now);
    snapshots.removeWhere((item) => item['date'] == today);
    snapshots.add({
      'date': today,
      'tracks': currentChart.take(100).map((track) => track.toJson()).toList(),
    });
    await preferences.setString(_worldSnapshotKey, jsonEncode(snapshots));

    final artistScores = <String, int>{};
    final artistNames = <String, String>{};
    final artistSongs = <String, Map<String, _RankedWorldSong>>{};
    for (final snapshot in snapshots) {
      for (final value
          in (snapshot['tracks'] as List? ?? const []).whereType<Map>()) {
        final track = HomeChartTrack.fromJson(
          Map<String, dynamic>.from(value),
          0,
        );
        if (track.title.isEmpty || track.artist.isEmpty || track.rank < 1) {
          continue;
        }
        final artistKey = _normalizeChartValue(track.artist);
        final songKey = _normalizeChartValue(track.title);
        if (artistKey.isEmpty || songKey.isEmpty) continue;
        final points = 101 - track.rank.clamp(1, 100);
        artistScores.update(
          artistKey,
          (score) => score + points,
          ifAbsent: () => points,
        );
        artistNames.putIfAbsent(artistKey, () => track.artist);
        final songs = artistSongs.putIfAbsent(artistKey, () => {});
        final previous = songs[songKey];
        if (previous == null) {
          songs[songKey] = _RankedWorldSong(track, points);
        } else {
          previous.points += points;
        }
      }
    }

    final keys = artistScores.keys.toList()
      ..sort((a, b) => artistScores[b]!.compareTo(artistScores[a]!));
    return List.unmodifiable([
      for (var artistIndex = 0; artistIndex < keys.length; artistIndex++)
        _buildRankedArtist(
          keys[artistIndex],
          artistIndex + 1,
          artistNames,
          artistSongs,
          snapshots.length,
        ),
    ]);
  }

  HomeChartArtist _buildRankedArtist(
    String key,
    int rank,
    Map<String, String> names,
    Map<String, Map<String, _RankedWorldSong>> songsByArtist,
    int snapshotDays,
  ) {
    final songs = songsByArtist[key]!.values.toList()
      ..sort((a, b) => b.points.compareTo(a.points));
    final tracks = [
      for (var index = 0; index < songs.length && index < 10; index++)
        HomeChartTrack(
          id: songs[index].track.id,
          title: songs[index].track.title,
          artist: songs[index].track.artist,
          artworkUrl: songs[index].track.artworkUrl,
          rank: index + 1,
        ),
    ];
    return HomeChartArtist(
      name: names[key]!,
      artworkUrl: tracks.isEmpty ? '' : tracks.first.artworkUrl,
      rank: rank,
      songs: List.unmodifiable(tracks),
      snapshotDays: snapshotDays,
    );
  }

  String _dayKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  String _normalizeChartValue(String value) => value
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

  Future<List<HomeChartTrack>> _loadChart({
    required String key,
    required bool refresh,
    required Future<List<HomeChartTrack>> Function() fetch,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final cached = _readCache(preferences.getString(key));
    final cachedAt = _cacheTime(preferences.getString(key));
    if (!refresh &&
        cached.isNotEmpty &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _cacheAge) {
      return cached;
    }
    try {
      final tracks = await fetch();
      if (tracks.isNotEmpty) {
        await preferences.setString(
          key,
          jsonEncode({
            'savedAt': DateTime.now().toIso8601String(),
            'tracks': tracks.map((track) => track.toJson()).toList(),
          }),
        );
        return tracks;
      }
    } catch (_) {
      // Keep the last chart available when the network is unavailable.
    }
    return cached;
  }

  List<HomeChartTrack> _readCache(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final saved = jsonDecode(raw) as Map<String, dynamic>;
      return (saved['tracks'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (item) =>
                HomeChartTrack.fromJson(Map<String, dynamic>.from(item), 0),
          )
          .where((track) => track.title.isNotEmpty && track.artist.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  DateTime? _cacheTime(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return DateTime.tryParse(
        (jsonDecode(raw) as Map<String, dynamic>)['savedAt']?.toString() ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<HomeChartTrack>> _fetchMarket(String market) async {
    final uri = Uri.https(
      'rss.applemarketingtools.com',
      '/api/v2/$market/music/most-played/50/songs.json',
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) return const [];
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final feed = decoded['feed'] as Map<String, dynamic>?;
    final results = feed?['results'] as List? ?? const [];
    final tracks = <HomeChartTrack>[];
    for (var index = 0; index < results.length; index++) {
      final item = results[index];
      if (item is! Map) continue;
      final attributes = item['attributes'] is Map
          ? Map<String, dynamic>.from(item['attributes'] as Map)
          : Map<String, dynamic>.from(item);
      final title = (attributes['name'] ?? attributes['trackName'] ?? '')
          .toString()
          .trim();
      final artist = (attributes['artistName'] ?? '').toString().trim();
      if (title.isEmpty || artist.isEmpty) continue;
      tracks.add(
        HomeChartTrack(
          id: (item['id'] ?? attributes['trackId'] ?? '$market-$index')
              .toString(),
          title: title,
          artist: artist,
          artworkUrl:
              (attributes['artworkUrl100'] ?? attributes['artworkUrl60'] ?? '')
                  .toString()
                  .replaceAll('100x100', '600x600'),
          rank: index + 1,
        ),
      );
    }
    return tracks;
  }

  Future<List<HomeChartTrack>> _fetchWorld() async {
    final charts = await Future.wait(
      _worldMarkets.map((market) async {
        try {
          return await _fetchMarket(market);
        } catch (_) {
          return const <HomeChartTrack>[];
        }
      }),
    );
    final points = <String, int>{};
    final tracks = <String, HomeChartTrack>{};
    for (final chart in charts) {
      for (final track in chart) {
        final key =
            '${track.title.toLowerCase()}|${track.artist.toLowerCase()}';
        points.update(
          key,
          (value) => value + (51 - track.rank),
          ifAbsent: () => 51 - track.rank,
        );
        tracks.putIfAbsent(key, () => track);
      }
    }
    final ranked = points.keys.toList()
      ..sort((a, b) => points[b]!.compareTo(points[a]!));
    return [
      for (var index = 0; index < ranked.length; index++)
        HomeChartTrack(
          id: tracks[ranked[index]]!.id,
          title: tracks[ranked[index]]!.title,
          artist: tracks[ranked[index]]!.artist,
          artworkUrl: tracks[ranked[index]]!.artworkUrl,
          rank: index + 1,
        ),
    ];
  }
}

class HomePodcastShow {
  const HomePodcastShow({
    required this.id,
    required this.title,
    required this.author,
    required this.artworkUrl,
    required this.feedUrl,
  });

  final String id;
  final String title;
  final String author;
  final String artworkUrl;
  final String feedUrl;
}

class HomePodcastEpisode {
  const HomePodcastEpisode({
    required this.id,
    required this.title,
    required this.showTitle,
    required this.audioUrl,
    required this.artworkUrl,
    required this.durationSeconds,
  });

  final String id;
  final String title;
  final String showTitle;
  final String audioUrl;
  final String artworkUrl;
  final int durationSeconds;
}

class HomePodcastPlayRequest {
  const HomePodcastPlayRequest({required this.episodes, required this.index});

  final List<HomePodcastEpisode> episodes;
  final int index;
}

class HomePodcastService {
  HomePodcastService._();

  static final HomePodcastService instance = HomePodcastService._();
  static const _cacheKey = 'soundneed_pc_home_podcasts_v1';
  static const _cacheAge = Duration(minutes: 45);
  final http.Client _client = http.Client();

  Future<List<HomePodcastShow>> recommendedShows({bool refresh = false}) async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_cacheKey);
    List<HomePodcastShow> cached = const [];
    DateTime? savedAt;
    if (raw != null) {
      try {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        savedAt = DateTime.tryParse(data['savedAt']?.toString() ?? '');
        cached = (data['shows'] as List? ?? const [])
            .whereType<Map>()
            .map((item) {
              final show = Map<String, dynamic>.from(item);
              return HomePodcastShow(
                id: show['id']?.toString() ?? '',
                title: show['title']?.toString() ?? '',
                author: show['author']?.toString() ?? '',
                artworkUrl: show['artworkUrl']?.toString() ?? '',
                feedUrl: show['feedUrl']?.toString() ?? '',
              );
            })
            .where((show) => show.title.isNotEmpty && show.feedUrl.isNotEmpty)
            .toList(growable: false);
      } catch (_) {
        cached = const [];
      }
    }
    if (!refresh &&
        cached.isNotEmpty &&
        savedAt != null &&
        DateTime.now().difference(savedAt) < _cacheAge) {
      return cached;
    }
    try {
      final uri = Uri.https('itunes.apple.com', '/search', {
        'term': 'podcast Colombia español',
        'media': 'podcast',
        'entity': 'podcast',
        'country': 'CO',
        'limit': '12',
      });
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return cached;
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final seen = <String>{};
      final shows = (json['results'] as List? ?? const [])
          .whereType<Map>()
          .map((item) {
            final data = Map<String, dynamic>.from(item);
            return HomePodcastShow(
              id: (data['collectionId'] ?? '').toString(),
              title: (data['collectionName'] ?? '').toString().trim(),
              author: (data['artistName'] ?? '').toString().trim(),
              artworkUrl: (data['artworkUrl600'] ?? data['artworkUrl100'] ?? '')
                  .toString()
                  .replaceAll('100x100', '600x600'),
              feedUrl: (data['feedUrl'] ?? '').toString(),
            );
          })
          .where(
            (show) =>
                show.title.isNotEmpty &&
                (show.feedUrl.startsWith('https://') ||
                    show.feedUrl.startsWith('http://')) &&
                seen.add(show.id),
          )
          .toList(growable: false);
      if (shows.isNotEmpty) {
        await preferences.setString(
          _cacheKey,
          jsonEncode({
            'savedAt': DateTime.now().toIso8601String(),
            'shows': [
              for (final show in shows)
                {
                  'id': show.id,
                  'title': show.title,
                  'author': show.author,
                  'artworkUrl': show.artworkUrl,
                  'feedUrl': show.feedUrl,
                },
            ],
          }),
        );
        return shows;
      }
    } catch (_) {
      // Return the last successful recommendation list on network failures.
    }
    return cached;
  }

  Future<List<HomePodcastShow>> searchShows(String query) async {
    final term = query.trim();
    if (term.isEmpty) return const [];
    try {
      final uri = Uri.https('itunes.apple.com', '/search', {
        'term': term,
        'media': 'podcast',
        'entity': 'podcast',
        'country': 'CO',
        'limit': '20',
      });
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return const [];
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final seen = <String>{};
      return (json['results'] as List? ?? const [])
          .whereType<Map>()
          .map((item) {
            final data = Map<String, dynamic>.from(item);
            return HomePodcastShow(
              id: (data['collectionId'] ?? '').toString(),
              title: (data['collectionName'] ?? '').toString().trim(),
              author: (data['artistName'] ?? '').toString().trim(),
              artworkUrl: (data['artworkUrl600'] ?? data['artworkUrl100'] ?? '')
                  .toString()
                  .replaceAll('100x100', '600x600'),
              feedUrl: (data['feedUrl'] ?? '').toString(),
            );
          })
          .where(
            (show) =>
                show.title.isNotEmpty &&
                show.feedUrl.startsWith('https://') &&
                seen.add(show.id),
          )
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<List<HomePodcastEpisode>> latestEpisodes(
    HomePodcastShow show, {
    int limit = 8,
  }) async {
    final uri = Uri.tryParse(show.feedUrl);
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        !uri.hasAuthority) {
      return const [];
    }
    try {
      final response = await _client
          .get(
            uri,
            headers: const {
              'Accept': 'application/rss+xml, application/xml, text/xml',
              'User-Agent': 'SoundNeed Podcast Player',
            },
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const [];
      }
      final document = XmlDocument.parse(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
      final channel = document.descendantElements
          .where((element) => element.name.local == 'channel')
          .firstOrNull;
      if (channel == null) return const [];
      final artwork = channel.descendantElements
          .where((element) => element.name.local == 'image')
          .map((element) => element.getAttribute('href') ?? '')
          .firstWhere(
            (value) => value.startsWith('https://'),
            orElse: () => '',
          );
      final episodes = <HomePodcastEpisode>[];
      for (final item in channel.childElements.where(
        (element) => element.name.local == 'item',
      )) {
        final enclosure = item.childElements
            .where((element) => element.name.local == 'enclosure')
            .firstOrNull;
        final audioUrl = enclosure?.getAttribute('url')?.trim() ?? '';
        final title = _childText(item, 'title');
        if ((!audioUrl.startsWith('https://') &&
                !audioUrl.startsWith('http://')) ||
            title.isEmpty) {
          continue;
        }
        episodes.add(
          HomePodcastEpisode(
            id: '${show.id}:$audioUrl',
            title: title,
            showTitle: show.title,
            audioUrl: audioUrl,
            artworkUrl: artwork.isEmpty ? show.artworkUrl : artwork,
            durationSeconds: _parseDuration(_childText(item, 'duration')),
          ),
        );
        if (episodes.length >= limit) break;
      }
      return episodes;
    } catch (_) {
      return const [];
    }
  }

  String _childText(XmlElement parent, String localName) =>
      parent.childElements
          .where((element) => element.name.local == localName)
          .map((element) => element.innerText.trim())
          .firstOrNull ??
      '';

  int _parseDuration(String value) {
    final parts = value.trim().split(':').map(int.tryParse).toList();
    if (parts.isEmpty || parts.any((part) => part == null)) return 0;
    final numbers = parts.cast<int>();
    return switch (numbers.length) {
      3 => numbers[0] * 3600 + numbers[1] * 60 + numbers[2],
      2 => numbers[0] * 60 + numbers[1],
      1 => numbers[0],
      _ => 0,
    };
  }
}

class _RankedWorldSong {
  _RankedWorldSong(this.track, this.points);

  final HomeChartTrack track;
  int points;
}
