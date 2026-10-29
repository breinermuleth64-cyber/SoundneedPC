import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';
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

class ExploreDiscoverySession {
  const ExploreDiscoverySession({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.items,
    this.sourceUnavailable = false,
  });

  final String id;
  final String title;
  final String subtitle;
  final List<ExploreRecommendation> items;
  final bool sourceUnavailable;
}

class ExploreDiscoveryFeed {
  const ExploreDiscoveryFeed({
    required this.recommendations,
    required this.seeds,
    this.sessions = const [],
  });

  final List<ExploreRecommendation> recommendations;
  final List<String> seeds;
  final List<ExploreDiscoverySession> sessions;
}

/// Finds related online artists from listening history and ranks their catalog.
class ExploreDiscoveryService {
  ExploreDiscoveryService._();

  static final instance = ExploreDiscoveryService._();
  static const _rotationStorageKey = 'soundneed_explore_rotation_v1';
  static const _recentStorageKey = 'soundneed_explore_recent_v1';
  int _rotation = 0;
  bool _stateLoaded = false;
  final List<String> _recentlyShown = [];

  static const _sessionDefinitions = <_SessionDefinition>[
    _SessionDefinition(
      'similar',
      'Suenan parecido',
      'Canciones cercanas a tus artistas favoritos.',
      'canciones similares a {artist}',
    ),
    _SessionDefinition(
      'connected',
      'Artistas conectados',
      'Artistas relacionados con lo que escuchas.',
      'artistas relacionados con {artist}',
    ),
    _SessionDefinition(
      'universe',
      'Del mismo universo',
      'Sonidos de escenas musicales cercanas.',
      'música del mismo estilo que {artist}',
    ),
    _SessionDefinition(
      'collaboration',
      'Si te gusta esta colaboración',
      'Búsqueda online de colaboraciones y artistas relacionados.',
      'colaboraciones de {artist} con otros artistas',
    ),
    _SessionDefinition(
      'same_sound',
      'El mismo sonido, otros artistas',
      'Otros nombres dentro de una escena musical parecida.',
      'artistas nuevos parecidos a {artist}',
    ),
    _SessionDefinition(
      'production',
      'Misma producción o productor',
      'Faltan créditos de producción verificables en las fuentes actuales.',
      '',
      available: false,
    ),
    _SessionDefinition(
      'more_like_this',
      'Más como esta',
      'Parte de una canción que ya escuchaste.',
      'canciones parecidas a {song} {artist}',
    ),
    _SessionDefinition(
      'unexpected',
      'La conexión inesperada',
      'Cruza dos artistas de tu historial.',
      'canciones que conectan {artist} y {other}',
    ),
    _SessionDefinition(
      'try_this',
      'Si te gusta esta, prueba esta otra',
      'Sugerencias online a partir de tus artistas preferidos.',
      'si te gusta {artist} escucha artistas similares',
    ),
    _SessionDefinition(
      'together',
      'Canciones que van juntas',
      'Música que combina con tus artistas habituales.',
      'canciones para escuchar después de {artist}',
    ),
    _SessionDefinition(
      'next_favorite',
      'Tu siguiente favorita',
      'Candidatas relacionadas con lo que escuchas más.',
      'artistas que te pueden gustar si escuchas {artist}',
    ),
    _SessionDefinition(
      'your_artists',
      'Más de tus artistas',
      'Canciones nuevas de artistas que ya escuchas.',
      'canciones de {artist}',
    ),
    _SessionDefinition(
      'old_sounds',
      'Vuelve a tus sonidos',
      'Recupera artistas que aparecen en tu historial.',
      'canciones de artistas que escuchabas como {artist}',
    ),
    _SessionDefinition(
      'less_known',
      'Tu lado menos conocido',
      'Explora alternativas menos conocidas de la escena.',
      'artistas menos conocidos similares a {artist}',
    ),
    _SessionDefinition(
      'favorites',
      'Basado en tus favoritos',
      'Usa artistas favoritos como punto de partida.',
      'música relacionada con {artist}',
    ),
    _SessionDefinition(
      'unknown_artists',
      'Artistas que todavía no conoces',
      'Artistas relacionados que no aparecen en tu historial.',
      'artistas nuevos para fans de {artist}',
    ),
    _SessionDefinition(
      'energy_up',
      'Para subir la energía',
      'Búsqueda de música animada relacionada con tus gustos.',
      'música movida y energética parecida a {artist}',
    ),
    _SessionDefinition(
      'slow_down',
      'Bajar revoluciones',
      'Búsqueda de sonidos tranquilos relacionados con tus gustos.',
      'música tranquila y relajada parecida a {artist}',
    ),
    _SessionDefinition(
      'mood',
      'Para ese ambiente',
      'Descubre música por ambiente y contexto.',
      'música romántica nostálgica para fans de {artist}',
    ),
    _SessionDefinition(
      'cross_genre',
      'Cruces de géneros',
      'Búsqueda de cruces entre escenas musicales.',
      'mezcla de géneros parecida a {artist} reggaeton pop trap',
    ),
    _SessionDefinition(
      'another_era',
      'De otra época',
      'Explora sonidos de otras épocas desde tus gustos.',
      'música clásica de otra época similar a {artist}',
    ),
    _SessionDefinition(
      'colombia_scene',
      'Escena colombiana',
      'Explora artistas colombianos relacionados; no es un ranking.',
      'artistas colombianos parecidos a {artist}',
    ),
    _SessionDefinition(
      'world_sounds',
      'Sonidos del mundo',
      'Abre una ruta hacia escenas de otros países.',
      'música de otros países relacionada con {artist}',
    ),
    _SessionDefinition(
      'emerging',
      'Antes de que sean tendencia',
      'Faltan datos temporales para medir qué artistas están creciendo.',
      '',
      available: false,
    ),
    _SessionDefinition(
      'viral',
      'Descubrimientos virales',
      'La fuente actual no aporta métricas verificables de viralidad.',
      '',
      available: false,
    ),
    _SessionDefinition(
      'classics',
      'Clásicos que encajan contigo',
      'Búsqueda de clásicos cercanos a tus preferencias.',
      'canciones clásicas similares a {artist}',
    ),
    _SessionDefinition(
      'chain',
      'Cadena de similitudes',
      'Sigue conexiones desde tus artistas hacia otros sonidos.',
      'artistas relacionados con los artistas similares a {artist}',
    ),
    _SessionDefinition(
      'bridge',
      'El puente musical',
      'Busca un puente entre dos artistas de tu historial.',
      'música que conecta {artist} con {other}',
    ),
    _SessionDefinition(
      'evolution',
      'Evolución de un artista',
      'Busca distintas etapas y sonidos de tus artistas.',
      'evolución musical diferentes épocas de {artist}',
    ),
    _SessionDefinition(
      'hidden',
      'Conexiones ocultas',
      'Investiga relaciones menos obvias entre artistas.',
      'conexiones musicales artistas relacionados con {artist} y {other}',
    ),
    _SessionDefinition(
      'endless',
      'Explora sin límites',
      'Una mezcla diversa de rutas conocidas y nuevas.',
      'descubre música nueva parecida a {artist}',
    ),
  ];

  Future<ExploreDiscoveryFeed> discover({
    required ListeningHistoryProfile history,
    required YoutubeExplode youtube,
    Iterable<String> favoriteArtists = const [],
    bool refresh = false,
    int limit = 12,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    if (!_stateLoaded) {
      _rotation = preferences.getInt(_rotationStorageKey) ?? 0;
      _recentlyShown.addAll(preferences.getStringList(_recentStorageKey) ?? []);
      _stateLoaded = true;
    }
    final favorites = favoriteArtists
        .map((artist) => artist.trim())
        .where((artist) => artist.isNotEmpty)
        .toList(growable: false);
    final seeds = <String>[];
    final seedKeys = <String>{};
    final recentCollaborationArtists = <String>[
      for (final track in history.recentTracks.take(12)) ...[
        if (!_isKnownNonMusicContent(track.title, track.artist)) ...[
          ..._splitArtistCredits(track.artist),
          ..._artistsFromTitle(track.title),
        ],
      ],
    ];
    final seedCandidates = <String>[
      ...recentCollaborationArtists,
      for (final artist in history.preferredArtists)
        ..._splitArtistCredits(artist),
      ...favorites,
    ];
    final knownArtistKeys = seedCandidates
        .map(_normalize)
        .where((artist) => artist.length > 1)
        .toSet();
    for (final artist in seedCandidates) {
      final value = artist.trim();
      if (value.isEmpty || !seedKeys.add(_normalize(value))) continue;
      seeds.add(value);
      if (seeds.length == 5) break;
    }
    if (seeds.isEmpty) {
      return const ExploreDiscoveryFeed(recommendations: [], seeds: []);
    }

    final catalog = ArtistCatalogService.instance;
    final relatedBySeed = await Future.wait(
      seeds.map(
        (seed) async => (
          seed: seed,
          artists: (await catalog.relatedArtists(
            seed,
            forceRefresh: refresh,
          )).take(5).toList(),
        ),
      ),
    );
    final related = <(String, ArtistCatalogEntry)>[];
    final seenArtists = <String>{...knownArtistKeys};
    for (final group in relatedBySeed) {
      for (final artist in group.artists) {
        if (!_splitArtistCredits(artist.name)
                .any((name) => knownArtistKeys.contains(_normalize(name))) &&
            seenArtists.add(_normalize(artist.name))) {
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
        if (!_splitArtistCredits(artist.name)
                .any((name) => knownArtistKeys.contains(_normalize(name))) &&
            seenArtists.add(_normalize(artist.name))) {
          related.add((entry.$1, artist));
        }
      }
    }
    final round = ++_rotation;
    await preferences.setInt(_rotationStorageKey, _rotation);
    final groups = await Future.wait(
      related.map(
        (item) async => (
          seed: item.$1,
          artist: item.$2,
          tracks: await catalog.tracksForArtist(
            item.$2,
            limit: 50,
            forceRefresh: refresh,
          ),
        ),
      ),
    );

    final heard = <String>{
      ...history.trackPlayCounts.keys,
      ...history.recentTrackKeys,
    };
    final heardTitles = heard
        .map((key) => _normalizeSongTitle(key.split('|').first))
        .where((title) => title.isNotEmpty)
        .toSet();
    final candidates = <_ScoredRecommendation>[];
    final seenTracks = <String>{};
    var insertionOrder = 0;
    for (final group in groups) {
      final tracks = group.tracks;
      final start = tracks.isEmpty ? 0 : (round * 7) % tracks.length;
      final rotatedTracks = <ArtistCatalogTrack>[
        ...tracks.skip(start),
        ...tracks.take(start),
      ];
      for (final track in rotatedTracks) {
        final key = listeningTrackKey(track.title, track.artist);
        if (heard.contains(key) ||
            heardTitles.contains(_normalizeSongTitle(track.title)) ||
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
        final metadata =
            track.title.isNotEmpty &&
                track.artist.isNotEmpty &&
                track.artworkUrl.startsWith('https://')
            ? 100.0
            : 55.0;
        final score =
            .30 * affinity +
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
        rotation: round,
      );
      candidates.addAll(fallback);
    }

    final recentKeys = _recentlyShown.toSet();
    final unseenCandidates = candidates.where((candidate) {
      final item = candidate.value;
      return !recentKeys.contains(listeningTrackKey(item.title, item.artist));
    }).toList();
    // If the catalog is small, keep the feed usable while still preferring
    // songs that were not shown in the previous discovery sessions.
    final pool = unseenCandidates.length >= math.min(6, limit)
        ? unseenCandidates
        : candidates;
    final selected = <ExploreRecommendation>[];
    final artistCounts = <String, int>{};
    final remaining = List<_ScoredRecommendation>.of(pool);
    while (remaining.isNotEmpty && selected.length < limit) {
      remaining.sort((a, b) {
        final adjustedA =
            a.value.score -
            (artistCounts[_normalize(a.value.artist)] ?? 0) * 18;
        final adjustedB =
            b.value.score -
            (artistCounts[_normalize(b.value.artist)] ?? 0) * 18;
        final order = adjustedB.compareTo(adjustedA);
        return order == 0 ? a.order.compareTo(b.order) : order;
      });
      final nextIndex = remaining.indexWhere(
        (item) => (artistCounts[_normalize(item.value.artist)] ?? 0) < 2,
      );
      if (nextIndex < 0) break;
      final next = remaining.removeAt(nextIndex).value;
      selected.add(next);
      final key = _normalize(next.artist);
      artistCounts.update(key, (count) => count + 1, ifAbsent: () => 1);
    }
    final sessions = await _buildSessions(
      youtube: youtube,
      history: history,
      seeds: seeds,
      favoriteArtists: favorites,
      catalogRecommendations: selected,
      round: round,
    );
    if (sessions.isEmpty && selected.length > 1) {
      sessions.add(
        ExploreDiscoverySession(
          id: 'related_fallback',
          title: 'Relacionado con tus gustos',
          subtitle: 'Más canciones online conectadas con tu historial.',
          items: List.unmodifiable(selected.skip(1)),
        ),
      );
    }
    final sessionRecommendations = sessions
        .expand((session) => session.items)
        .toList(growable: false);
    final finalRecommendations = sessionRecommendations.isNotEmpty
        ? sessionRecommendations
        : selected;
    for (final item in finalRecommendations) {
      _recentlyShown.add(listeningTrackKey(item.title, item.artist));
    }
    if (_recentlyShown.length > 60) {
      _recentlyShown.removeRange(0, _recentlyShown.length - 60);
    }
    await preferences.setStringList(_recentStorageKey, _recentlyShown);
    return ExploreDiscoveryFeed(
      recommendations: List.unmodifiable(finalRecommendations),
      seeds: List.unmodifiable(seeds),
      sessions: List.unmodifiable(sessions),
    );
  }

  Future<List<ExploreDiscoverySession>> _buildSessions({
    required YoutubeExplode youtube,
    required ListeningHistoryProfile history,
    required List<String> seeds,
    required List<String> favoriteArtists,
    required List<ExploreRecommendation> catalogRecommendations,
    required int round,
  }) async {
    final definitions = <_SessionDefinition>[];
    const pinnedOrder = ['your_artists', 'similar', 'more_like_this'];
    const pinnedIds = {'your_artists', 'similar', 'more_like_this'};
    final availableDefinitions = _sessionDefinitions
        .where((definition) => definition.available)
        .toList(growable: false);
    definitions.addAll(
      pinnedOrder.map(
        (id) => availableDefinitions.firstWhere(
          (definition) => definition.id == id,
        ),
      ),
    );
    final rotatingDefinitions = availableDefinitions
        .where((definition) => !pinnedIds.contains(definition.id))
        .toList(growable: false);
    final start = (round * 8) % rotatingDefinitions.length;
    for (
      var offset = 0;
      offset < rotatingDefinitions.length && definitions.length < 10;
      offset++
    ) {
      final definition =
          rotatingDefinitions[(start + offset) % rotatingDefinitions.length];
      definitions.add(definition);
    }

    final recentlyShownTitles = _recentlyShown
        .map((key) => _normalizeSongTitle(key.split('|').first))
        .toSet();
    final heardTitles = <String>{
      ...history.trackPlayCounts.keys.map(
        (key) => _normalizeSongTitle(key.split('|').first),
      ),
      ...history.recentTrackKeys.map(
        (key) => _normalizeSongTitle(key.split('|').first),
      ),
    };
    final usableRecentTracks = history.recentTracks
        .where((track) => !_isKnownNonMusicContent(track.title, track.artist))
        .toList(growable: false);
    final recentTrack = usableRecentTracks.isEmpty
        ? null
        : usableRecentTracks.first;
    final catalogSplitIndex = (catalogRecommendations.length + 1) ~/ 2;
    final rawSessions = await Future.wait(
      definitions.asMap().entries.map((entry) async {
        final index = entry.key;
        final definition = entry.value;
        final seed = definition.id == 'favorites' && favoriteArtists.isNotEmpty
            ? favoriteArtists[(round + index) % favoriteArtists.length]
            : seeds[(round + index) % seeds.length];
        final sessionSeed =
            (definition.id == 'your_artists' || definition.id == 'favorites') &&
                favoriteArtists.isNotEmpty
            ? favoriteArtists[(round + index) % favoriteArtists.length]
            : seed;
        final otherSeed = seeds.length > 1
            ? seeds[(round + index + 1) % seeds.length]
            : seed;
        final song = recentTrack?.title ?? seed;
        final songArtist = recentTrack?.artist ?? seed;
        if (!definition.available) {
          return ExploreDiscoverySession(
            id: definition.id,
            title: definition.title,
            subtitle: definition.subtitle,
            items: const [],
            sourceUnavailable: true,
          );
        }
        if (definition.id == 'similar' && catalogRecommendations.isNotEmpty) {
          return ExploreDiscoverySession(
            id: definition.id,
            title: definition.title,
            subtitle:
                'Canciones de artistas relacionados por el catálogo online.',
            items: catalogRecommendations
                .take(catalogSplitIndex)
                .toList(growable: false),
          );
        }
        if (definition.id == 'connected' &&
            catalogRecommendations.length > catalogSplitIndex) {
          return ExploreDiscoverySession(
            id: definition.id,
            title: definition.title,
            subtitle: definition.subtitle,
            items: catalogRecommendations
                .skip(catalogSplitIndex)
                .toList(growable: false),
          );
        }
        final songFocused = const {
          'similar',
          'collaboration',
          'more_like_this',
          'unexpected',
          'try_this',
          'together',
          'bridge',
        }.contains(definition.id);
        final songContext = recentTrack == null || !songFocused
            ? ''
            : ' "${recentTrack.title}" "$songArtist"';
        // The explicit own-artists row must include listened artists as well
        // as local favorites. Previously, having even one local favorite
        // caused every artist learned from online listening history to vanish
        // from this row.
        final artistSearchSeeds =
            definition.id == 'your_artists' || definition.id == 'favorites'
            ? <String>[...favoriteArtists, ...seeds]
                  .fold<List<String>>([], (unique, artist) {
                    if (artist.trim().isNotEmpty &&
                        !unique.any(
                          (value) => _normalize(value) == _normalize(artist),
                        )) {
                      unique.add(artist.trim());
                    }
                    return unique;
                  })
                  .take(6)
                  .toList(growable: false)
            : [sessionSeed];
        try {
          final searchResults = await Future.wait(
            artistSearchSeeds.map((artistSeed) async {
              final artistFocused =
                  definition.id == 'your_artists' ||
                  definition.id == 'favorites';
              final artistQuery = artistFocused
                  ? '"$artistSeed" canciones official audio canciones oficiales'
                  : definition.query
                        .replaceAll('{artist}', artistSeed)
                        .replaceAll('{other}', otherSeed)
                        .replaceAll('{song}', song);
              final musicOnlyQuery =
                  '$artistQuery$songContext canción canción oficial audio '
                  '-podcast -entrevista -programa -reacción -reaction -review '
                  '-episodio -episode -noticias -shorts';
              try {
                return await youtube.search
                    .search(musicOnlyQuery)
                    .timeout(const Duration(seconds: 12));
              } catch (_) {
                return null;
              }
            }),
          );
          final items = <ExploreRecommendation>[];
          searchResultsLoop:
          for (
            var seedIndex = 0;
            seedIndex < searchResults.length;
            seedIndex++
          ) {
            final videos = searchResults[seedIndex];
            if (videos == null) continue;
            final artistSeed = artistSearchSeeds[seedIndex];
            for (final video in videos.take(24)) {
              final title = video.title.trim();
              final artist = video.author.trim();
              final id = video.id.value;
              final titleKey = _normalizeSongTitle(title);
              if (title.isEmpty ||
                  artist.isEmpty ||
                  id.isEmpty ||
                  _matchesSongTitle(heardTitles, titleKey) ||
                  _matchesSongTitle(recentlyShownTitles, titleKey) ||
                  ((definition.id == 'your_artists' ||
                          definition.id == 'favorites') &&
                      !_mentionsSeedArtist(title, artist, artistSeed)) ||
                  !_isMusicOnlyResult(
                    title: title,
                    channel: artist,
                    duration: video.duration,
                    seedArtists: [...seeds, artistSeed],
                  )) {
                continue;
              }
              items.add(
                ExploreRecommendation(
                  id: id,
                  videoId: id,
                  title: title,
                  artist: artist,
                  artworkUrl: video.thumbnails.highResUrl,
                  seedArtist: artistSeed,
                  score: 70 - items.length.toDouble(),
                  reason: 'Canción de $artistSeed',
                ),
              );
              if (items.length == 8) break searchResultsLoop;
            }
          }
          return ExploreDiscoverySession(
            id: definition.id,
            title: definition.title,
            subtitle: definition.subtitle,
            items: items,
          );
        } catch (_) {
          return ExploreDiscoverySession(
            id: definition.id,
            title: definition.title,
            subtitle: definition.subtitle,
            items: const [],
          );
        }
      }),
    );

    // Keep each song in one session so the page offers genuinely different
    // routes instead of repeating the same search result in every row.
    final seenIds = <String>{};
    final seenTracks = <String>{};
    final sessions = <ExploreDiscoverySession>[];
    for (final session in rawSessions) {
      if (session.sourceUnavailable) {
        sessions.add(session);
        continue;
      }
      if (session.items.isEmpty) continue;
      final uniqueItems = session.items
          .where((item) {
            final key = listeningTrackKey(item.title, item.artist);
            return seenIds.add(item.id) && seenTracks.add(key);
          })
          .toList(growable: false);
      if (uniqueItems.isEmpty) continue;
      sessions.add(
        ExploreDiscoverySession(
          id: session.id,
          title: session.title,
          subtitle: session.subtitle,
          items: List.unmodifiable(uniqueItems),
        ),
      );
    }
    return sessions;
  }

  double _popularity(int? fans) {
    if (fans == null || fans <= 0) return 20;
    return (math.log(fans + 1) / math.log(100000001) * 100)
        .clamp(0.0, 100.0)
        .toDouble();
  }

  List<String> _splitArtistCredits(String value) {
    final cleanValue = value
        .replaceAll(
          RegExp(
            r'\s*(?:[-|:])\s*(?:topic|official channel)$',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(RegExp(r'\s+vevo$', caseSensitive: false), '');
    final credits = cleanValue
        .replaceAll(
          RegExp(r'\b(?:feat(?:uring)?|ft|with)\.?\s*', caseSensitive: false),
          ', ',
        )
        .split(
          RegExp(r'\s+(?:&|x|×|and|y|con)\s+|[,;|/]+', caseSensitive: false),
        );
    return credits
        .map((artist) => artist.replaceAll(RegExp(r'[()\[\]{}]+'), '').trim())
        .where((artist) => artist.length > 1)
        .toList(growable: false);
  }

  List<String> _featuredArtistsFromTitle(String title) {
    final match = RegExp(
      r'\b(?:feat(?:uring)?|ft)\.?\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(title);
    if (match == null) return const [];
    final credits = (match.group(1) ?? '')
        .replaceAll(
          RegExp(
            r'\s*[\[(](?:official|video|audio|lyrics|letra)[^\])]*.*$',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(RegExp(r'[)\]}]+$'), '');
    return _splitArtistCredits(credits);
  }

  List<String> _artistsFromTitle(String title) {
    final featured = _featuredArtistsFromTitle(title);
    if (featured.isNotEmpty) return featured;
    final withoutMarkers = title.replaceAll(
      RegExp(
        r'\s*[\[(]?(official video|official audio|video oficial|audio oficial|lyrics|letra|visualizer|videoclip)[^\])]*[\])]?$',
        caseSensitive: false,
      ),
      '',
    );
    for (final part in withoutMarkers.split(RegExp(r'\s[-–:|]\s'))) {
      final names = _splitArtistCredits(part);
      if (names.length > 1) return names;
    }
    return const [];
  }

  bool _isMusicOnlyResult({
    required String title,
    required String channel,
    required Duration? duration,
    required Iterable<String> seedArtists,
  }) {
    if (_isKnownNonMusicContent(title, channel)) return false;
    if (duration != null &&
        (duration.inSeconds < 60 || duration > const Duration(minutes: 12))) {
      return false;
    }
    final normalizedTitle = _normalize(title);
    final musicMarker = RegExp(
      r'\b(official audio|audio oficial|official video|video oficial|music video|video musical|videoclip|visualizer|lyric video|video lyric|lyrics|letra oficial|vevo|topic|records|music)\b',
    );
    if (musicMarker.hasMatch(_normalize(title)) ||
        musicMarker.hasMatch(_normalize(channel))) {
      return true;
    }
    final knownArtistMention = seedArtists.any((artist) {
      final normalizedArtist = _normalize(artist);
      return normalizedArtist.length > 2 &&
          (normalizedTitle.contains(normalizedArtist) ||
              _normalize(channel).contains(normalizedArtist));
    });
    if (duration == null) return knownArtistMention;
    final songTitlePattern = RegExp(r'\s[-–:|]\s').hasMatch(title);
    return knownArtistMention || songTitlePattern;
  }

  bool _mentionsSeedArtist(String title, String channel, String seedArtist) {
    final artist = _normalize(seedArtist);
    if (artist.length < 3) return false;
    return _normalize(title).contains(artist) ||
        _normalize(channel).contains(artist);
  }

  bool _isKnownNonMusicContent(String title, String channel) => RegExp(
    r'\b(podcast|entrevista|interview|programa|episodio|episode|reaccion|reaction|review|noticias|news|noticiero|talk show|got talent|talent show|the voice|la voz|yo me llamo|al rojo vivo|famous miau|sorprende a todos|imitador|imitadora|audicion|reality|television|tv show|canal de tv|bailando con las estrellas|concursante|participante|reportaje|documental|documentary|trailer|teaser|shorts|live concert|full concert|concierto completo|en vivo|en directo)\b',
  ).hasMatch(_normalize('$title $channel'));

  String _normalizeSongTitle(String value) => _normalize(
    value
        .replaceAll(
          RegExp(
            r'\s*[\[(]?(official video|official audio|video oficial|audio oficial|lyrics|letra|visualizer|videoclip|4k|hd)[^\])]*[\])]?$',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(RegExp(r'\s+vevo$', caseSensitive: false), ''),
  );

  bool _matchesSongTitle(Set<String> knownTitles, String candidate) =>
      knownTitles.any(
        (known) =>
            known.length >= 4 &&
            (candidate == known ||
                candidate.startsWith('$known ') ||
                known.startsWith('$candidate ')),
      );

  Future<List<_ScoredRecommendation>> _searchOnlineRelated({
    required YoutubeExplode youtube,
    required List<String> seeds,
    required ListeningHistoryProfile history,
    required Set<String> excludedTitles,
    required int firstOrder,
    required int rotation,
  }) async {
    final heardTitles = <String>{
      ...history.trackPlayCounts.keys.map(
        (key) => _normalizeSongTitle(key.split('|').first),
      ),
      ...history.recentTrackKeys.map(
        (key) => _normalizeSongTitle(key.split('|').first),
      ),
    };
    final candidates = <_ScoredRecommendation>[];
    final seenTitles = <String>{...heardTitles};
    for (final key in excludedTitles) {
      seenTitles.add(key.split('|').first);
    }
    final seenVideoIds = <String>{};
    var order = firstOrder;
    const queryStyles = [
      'canciones similares',
      'artistas similares',
      'nuevos artistas del mismo estilo',
      'si te gusta este artista escucha',
      'música parecida a',
    ];
    final styleOffset = rotation % queryStyles.length;

    for (var pass = 0; pass < 2 && candidates.length < 12; pass++) {
      final results = await Future.wait([
        for (final seed in seeds)
          () async {
            final style =
                queryStyles[(styleOffset + pass) % queryStyles.length];
            final query =
                '$style $seed canción oficial audio -podcast -entrevista '
                '-programa -reacción -reaction -review -episodio -shorts';
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
          final titleKey = _normalizeSongTitle(title);
          if (title.isEmpty ||
              artist.isEmpty ||
              id.isEmpty ||
              !_isMusicOnlyResult(
                title: title,
                channel: artist,
                duration: video.duration,
                seedArtists: seeds,
              ) ||
              !seenVideoIds.add(id) ||
              !seenTitles.add(titleKey)) {
            continue;
          }
          final metadata = video.thumbnails.highResUrl.isNotEmpty ? 90.0 : 70.0;
          final affinity = (82 - seedIndex * 9).toDouble();
          final historySignal = (78 - seedIndex * 8).toDouble();
          const novelty = 100.0;
          const popularity = 20.0;
          const diversity = 85.0;
          final score =
              .30 * affinity +
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
                reason: 'Relacionado con tus gustos: $seed',
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
                  .search(
                    '${queryStyles[(styleOffset + 2) % queryStyles.length]} '
                    '$seed canción oficial audio -podcast -entrevista -programa',
                  )
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
          final titleKey = _normalizeSongTitle(title);
          if (title.isEmpty ||
              artist.isEmpty ||
              id.isEmpty ||
              !_isMusicOnlyResult(
                title: title,
                channel: artist,
                duration: video.duration,
                seedArtists: seeds,
              ) ||
              !seenVideoIds.add(id) ||
              !seenTitles.add(titleKey)) {
            continue;
          }
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
                reason: 'Una nueva ruta musical desde $seed',
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

class _SessionDefinition {
  const _SessionDefinition(
    this.id,
    this.title,
    this.subtitle,
    this.query, {
    this.available = true,
  });

  final String id;
  final String title;
  final String subtitle;
  final String query;
  final bool available;
}
