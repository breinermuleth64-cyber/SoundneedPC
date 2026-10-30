import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'artist_catalog_service.dart';
import 'explore_feedback_service.dart';
import 'listening_history_service.dart';
import 'recommendation_scoring_service.dart';

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
    this.fromCatalog = false,
    this.artistFanCount,
  });

  final String id;
  final String title;
  final String artist;
  final String artworkUrl;
  final String seedArtist;
  final String? videoId;
  final double score;
  final String reason;
  final bool fromCatalog;
  final int? artistFanCount;
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

/// Coalesces Explore loads and queues at most one forced refresh behind an
/// active request. Feed freshness is based on the last successful load time.
class ExploreFeedRefreshCoordinator {
  ExploreFeedRefreshCoordinator({this.ttl = const Duration(minutes: 30)});

  final Duration ttl;

  Future<void>? _inFlight;
  bool _inFlightIsForced = false;
  bool _forcedRefreshPending = false;
  Completer<void>? _forcedRefreshCompleter;
  Future<void> Function()? _forcedRefreshReload;

  bool isFresh({
    required bool hasSuccessfulLoad,
    required DateTime? updatedAt,
    bool isStale = false,
    DateTime? now,
  }) {
    if (!hasSuccessfulLoad || updatedAt == null || isStale) return false;
    final age = (now ?? DateTime.now()).difference(updatedAt);
    return !age.isNegative && age < ttl;
  }

  Future<void> load({
    required bool force,
    required bool hasSuccessfulLoad,
    required DateTime? updatedAt,
    required Future<void> Function() reload,
    bool isStale = false,
    DateTime? now,
  }) {
    if (!force &&
        isFresh(
          hasSuccessfulLoad: hasSuccessfulLoad,
          updatedAt: updatedAt,
          isStale: isStale,
          now: now,
        )) {
      return Future<void>.value();
    }

    final active = _inFlight;
    if (active != null) {
      if (!force) return active;
      if (_inFlightIsForced) return active;
      _forcedRefreshPending = true;
      _forcedRefreshCompleter ??= Completer<void>();
      _forcedRefreshReload ??= reload;
      return _forcedRefreshCompleter!.future;
    }
    return _start(reload, isForced: force);
  }

  Future<void> _start(
    Future<void> Function() reload, {
    required bool isForced,
  }) {
    final completer = Completer<void>();
    final future = completer.future;
    _inFlight = future;
    _inFlightIsForced = isForced;
    unawaited(_execute(reload, completer));
    return future;
  }

  Future<void> _execute(
    Future<void> Function() reload,
    Completer<void> completer,
  ) async {
    Object? error;
    StackTrace? stackTrace;
    try {
      await reload();
    } catch (caughtError, caughtStackTrace) {
      error = caughtError;
      stackTrace = caughtStackTrace;
    }

    if (identical(_inFlight, completer.future)) {
      _inFlight = null;
      _inFlightIsForced = false;
    }
    if (_forcedRefreshPending) {
      _forcedRefreshPending = false;
      final queuedCompleter = _forcedRefreshCompleter;
      _forcedRefreshCompleter = null;
      final queuedReload = _forcedRefreshReload ?? reload;
      _forcedRefreshReload = null;
      final queuedLoad = _start(queuedReload, isForced: true);
      queuedLoad.then<void>(
        (_) => queuedCompleter?.complete(),
        onError: (Object queuedError, StackTrace queuedStackTrace) {
          queuedCompleter?.completeError(queuedError, queuedStackTrace);
        },
      );
    }

    if (error == null) {
      completer.complete();
    } else {
      completer.completeError(error, stackTrace!);
    }
  }
}

/// Pure selectors for the data-backed Explore strategies.
class ExploreSessionStrategySelector {
  const ExploreSessionStrategySelector._();

  static List<ExploreRecommendation> ownArtistSongs(
    Iterable<ExploreRecommendation> candidates, {
    int limit = 10,
  }) =>
      candidates
          .where(
            (item) =>
                item.seedArtist.isNotEmpty &&
                _normalize(item.artist) == _normalize(item.seedArtist),
          )
          .take(limit)
          .toList(growable: false);

  static List<ExploreRecommendation> favoriteArtistSongs(
    Iterable<ExploreRecommendation> candidates, {
    required Iterable<String> favoriteArtists,
    int limit = 10,
  }) {
    final favorites = favoriteArtists.map(_normalize).toSet();
    return candidates
        .where(
          (item) =>
              item.fromCatalog && favorites.contains(_normalize(item.artist)),
        )
        .take(limit)
        .toList(growable: false);
  }

  static List<ExploreRecommendation> popularRelatedArtists(
    Iterable<ExploreRecommendation> candidates, {
    int limit = 10,
  }) {
    final result = candidates
        .where((item) => item.fromCatalog && (item.artistFanCount ?? 0) > 0)
        .where((item) => _normalize(item.artist) != _normalize(item.seedArtist))
        .toList()
      ..sort(
        (a, b) => (b.artistFanCount ?? 0).compareTo(a.artistFanCount ?? 0),
      );
    return result.take(limit).toList(growable: false);
  }

  static List<ExploreRecommendation> deepCutArtists(
    Iterable<ExploreRecommendation> candidates, {
    int limit = 10,
  }) {
    final result = candidates
        .where((item) => item.fromCatalog && (item.artistFanCount ?? 0) > 0)
        .where((item) => _normalize(item.artist) != _normalize(item.seedArtist))
        .toList()
      ..sort(
        (a, b) => (a.artistFanCount ?? 0).compareTo(b.artistFanCount ?? 0),
      );
    return result.take(limit).toList(growable: false);
  }

  static List<ExploreRecommendation> topAffinity(
    Iterable<ExploreRecommendation> candidates, {
    int limit = 10,
  }) {
    final result = candidates.where((item) => item.fromCatalog).toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return result.take(limit).toList(growable: false);
  }

  static List<ExploreRecommendation> relatedToSeeds(
    Iterable<ExploreRecommendation> candidates, {
    required Iterable<String> seedArtists,
    int limit = 10,
  }) {
    final seeds = seedArtists.map(_normalize).toSet();
    return candidates
        .where(
          (item) =>
              item.fromCatalog &&
              _normalize(item.artist) != _normalize(item.seedArtist) &&
              seeds.contains(_normalize(item.seedArtist)),
        )
        .take(limit)
        .toList(growable: false);
  }

  static List<ExploreRecommendation> newRelatedArtists(
    Iterable<ExploreRecommendation> candidates, {
    required Iterable<String> seedArtists,
    required Iterable<String> listenedArtists,
    int limit = 10,
  }) {
    final seeds = seedArtists.map(_normalize).toSet();
    final known = listenedArtists.map(_normalize).toSet();
    return candidates
        .where(
          (item) =>
              item.fromCatalog &&
              _normalize(item.artist) != _normalize(item.seedArtist) &&
              seeds.contains(_normalize(item.seedArtist)) &&
              !known.contains(_normalize(item.artist)),
        )
        .take(limit)
        .toList(growable: false);
  }

  static String _normalize(String value) => value
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
    // AFFINITY SESSION: Prioritizes songs closest to favorite artists
    // Uses explicit filtering by favorites and seed artist
    _SessionDefinition(
      'similar',
      'Suenan parecido',
      'Canciones cercanas a tus artistas favoritos.',
      'canciones similares a {artist}',
    ),
    // DISCOVERY SESSION: Prioritizes new artists not in user's history
    // Uses explicit filtering by artist not listened to
    _SessionDefinition(
      'connected',
      'Artistas conectados',
      'Artistas relacionados con lo que escuchas.',
      'artistas relacionados con {artist}',
    ),
    _SessionDefinition(
      'favorites',
      'Basado en tus favoritos',
      'Canciones de artistas que guardaste en favoritos.',
      '',
    ),
    _SessionDefinition(
      'popular_related',
      'Populares entre tus relacionados',
      'Artistas relacionados con más oyentes en Deezer.',
      '',
    ),
    _SessionDefinition(
      'deep_cuts',
      'Joyas por descubrir',
      'Artistas relacionados con menos seguidores en Deezer.',
      '',
    ),
    _SessionDefinition(
      'next_favorite',
      'Tu siguiente favorita',
      'Las canciones mejor puntuadas para tus gustos.',
      '',
    ),
    _SessionDefinition(
      'history_radio',
      'Vuelve a tus artistas',
      'Más canciones de artistas presentes en tu historial.',
      '',
    ),
    _SessionDefinition(
      'variety',
      'Una ruta diferente',
      'Una selección variada de artistas relacionados.',
      '',
    ),
    // LIMITATION: Uses same YouTube search pattern as below
    // Would need scene/graph data for true "universe" grouping
    _SessionDefinition(
      'universe',
      'Del mismo universo',
      'Sonidos de escenas musicales cercanas.',
      'música del mismo estilo que {artist}',
    ),
    // LIMITATION: YouTube search doesn't provide verified collaboration data
    // Would need MusicBrainz API for actual collaboration graph
    _SessionDefinition(
      'collaboration',
      'Si te gusta esta colaboración',
      'Búsqueda online de colaboraciones y artistas relacionados.',
      'colaboraciones de {artist} con otros artistas',
    ),
    // LIMITATION: No audio feature analysis available
    // Would need librosa (Python) or equivalent Dart library
    _SessionDefinition(
      'same_sound',
      'El mismo sonido, otros artistas',
      'Otros nombres dentro de una escena musical parecida.',
      'artistas nuevos parecidos a {artist}',
    ),
    // DISABLED: No production credits available in current data sources
    _SessionDefinition(
      'production',
      'Misma producción o productor',
      'Faltan créditos de producción verificables en las fuentes actuales.',
      '',
      available: false,
    ),
    // LIMITATION: Uses YouTube search with song context
    // Limited to what's searchable on YouTube
    _SessionDefinition(
      'more_like_this',
      'Más como esta',
      'Parte de una canción que ya escuchaste.',
      'canciones parecidas a {song} {artist}',
    ),
    // LIMITATION: Crosses two artists but uses YouTube search
    // Would need true artist similarity graph for better results
    _SessionDefinition(
      'unexpected',
      'La conexión inesperada',
      'Cruza dos artistas de tu historial.',
      'canciones que conectan {artist} y {other}',
    ),
    // LIMITATION: Uses YouTube search pattern
    _SessionDefinition(
      'try_this',
      'Si te gusta esta, prueba esta otra',
      'Sugerencias online a partir de tus artistas preferidos.',
      'si te gusta {artist} escucha artistas similares',
    ),
    // LIMITATION: Uses YouTube search pattern
    _SessionDefinition(
      'together',
      'Canciones que van juntas',
      'Música que combina con tus artistas habituales.',
      'canciones para escuchar después de {artist}',
    ),
    // YOUR_ARTISTS: Explicitly uses favorites + seeds from history
    // Provides more songs from artists the user already knows
    _SessionDefinition(
      'your_artists',
      'Más de tus artistas',
      'Canciones nuevas de artistas que ya escuchas.',
      'canciones de {artist}',
    ),
    // LIMITATION: Uses YouTube search pattern
    _SessionDefinition(
      'old_sounds',
      'Vuelve a tus sonidos',
      'Recupera artistas que aparecen en tu historial.',
      'canciones de artistas que escuchabas como {artist}',
    ),
    // LIMITATION: Uses YouTube search pattern
    _SessionDefinition(
      'less_known',
      'Tu lado menos conocido',
      'Explora alternativas menos conocidas de la escena.',
      'artistas menos conocidos similares a {artist}',
    ),
    // LIMITATION: Could filter by history, but uses YouTube search
    _SessionDefinition(
      'unknown_artists',
      'Artistas que todavía no conoces',
      'Artistas relacionados que no aparecen en tu historial.',
      'artistas nuevos para fans de {artist}',
    ),
    // LIMITATION: No audio feature analysis for energy detection
    _SessionDefinition(
      'energy_up',
      'Para subir la energía',
      'Búsqueda de música animada relacionada con tus gustos.',
      'música movida y energética parecida a {artist}',
    ),
    // LIMITATION: No audio feature analysis for tempo/mood
    _SessionDefinition(
      'slow_down',
      'Bajar revoluciones',
      'Búsqueda de sonidos tranquilos relacionados con tus gustos.',
      'música tranquila y relajada parecida a {artist}',
    ),
    // LIMITATION: No contextual or audio feature analysis
    _SessionDefinition(
      'mood',
      'Para ese ambiente',
      'Descubre música por ambiente y contexto.',
      'música romántica nostálgica para fans de {artist}',
    ),
    // LIMITATION: Uses genre keywords in search
    _SessionDefinition(
      'cross_genre',
      'Cruces de géneros',
      'Búsqueda de cruces entre escenas musicales.',
      'mezcla de géneros parecida a {artist} reggaeton pop trap',
    ),
    // LIMITATION: Uses era keywords in search
    _SessionDefinition(
      'another_era',
      'De otra época',
      'Explora sonidos de otras épocas desde tus gustos.',
      'música clásica de otra época similar a {artist}',
    ),
    // LIMITATION: Uses location keywords in search
    _SessionDefinition(
      'colombia_scene',
      'Escena colombiana',
      'Explora artistas colombianos relacionados; no es un ranking.',
      'artistas colombianos parecidos a {artist}',
    ),
    // LIMITATION: Uses country keywords in search
    _SessionDefinition(
      'world_sounds',
      'Sonidos del mundo',
      'Abre una ruta hacia escenas de otros países.',
      'música de otros países relacionada con {artist}',
    ),
    // DISABLED: No temporal data available to measure growth
    _SessionDefinition(
      'emerging',
      'Antes de que sean tendencia',
      'Faltan datos temporales para medir qué artistas están creciendo.',
      '',
      available: false,
    ),
    // DISABLED: No viral metrics available in current sources
    _SessionDefinition(
      'viral',
      'Descubrimientos virales',
      'La fuente actual no aporta métricas verificables de viralidad.',
      '',
      available: false,
    ),
    // LIMITATION: Uses classic keywords in search
    _SessionDefinition(
      'classics',
      'Clásicos que encajan contigo',
      'Búsqueda de clásicos cercanos a tus preferencias.',
      'canciones clásicas similares a {artist}',
    ),
    // LIMITATION: Would need multi-hop similarity graph
    _SessionDefinition(
      'chain',
      'Cadena de similitudes',
      'Sigue conexiones desde tus artistas hacia otros sonidos.',
      'artistas relacionados con los artistas similares a {artist}',
    ),
    // LIMITATION: Would need pathfinding in artist graph
    _SessionDefinition(
      'bridge',
      'El puente musical',
      'Busca un puente entre dos artistas de tu historial.',
      'música que conecta {artist} con {other}',
    ),
    // LIMITATION: Would need temporal data per artist
    _SessionDefinition(
      'evolution',
      'Evolución de un artista',
      'Busca distintas etapas y sonidos de tus artistas.',
      'evolución musical diferentes épocas de {artist}',
    ),
    // LIMITATION: Would need deeper graph analysis
    _SessionDefinition(
      'hidden',
      'Conexiones ocultas',
      'Investiga relaciones menos obvias entre artistas.',
      'conexiones musicales artistas relacionados con {artist} y {other}',
    ),
    // LIMITATION: General mix of search patterns
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
    int limit = 20,
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
      for (final track in history.recentTracks.take(30)) ...[
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
      if (seeds.length == 10) break;
    }
    if (seeds.isEmpty) {
      return const ExploreDiscoveryFeed(recommendations: [], seeds: []);
    }

    debugPrint('Explore: === Starting discovery ===');
    debugPrint('Explore: Building discovery from ${seeds.length} seed artists');

    final catalog = ArtistCatalogService.instance;
    debugPrint('Explore: Looking up related catalog artists');
    final relatedBySeed = await Future.wait(
      seeds.map(
        (seed) async => (
          seed: seed,
          artists: (await catalog.relatedArtists(
            seed,
            forceRefresh: refresh,
          )).take(10).toList(),
        ),
      ),
    );
    debugPrint(
      'Explore: Related catalog artists found: ${relatedBySeed.fold<int>(0, (count, group) => count + group.artists.length)}',
    );

    // Resolve the listened artists themselves as well. The related-artist
    // catalog intentionally excludes known names, so without this exact lookup
    // Explorar could contain only similar artists and never songs by the user’s
    // own artists.
    final exactArtists = await Future.wait(
      seeds.map(
        (seed) async => (seed: seed, artist: await catalog.lookup(seed)),
      ),
    );
    final exactGroups = exactArtists
        .where((entry) => entry.artist != null && entry.artist!.id.isNotEmpty)
        .map((entry) => (entry.seed, entry.artist!))
        .toList(growable: false);
    debugPrint('Explore: Exact artist matches: ${exactGroups.length}');

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

    final round = ++_rotation;
    await preferences.setInt(_rotationStorageKey, _rotation);
    final groups = await Future.wait(
      [...exactGroups, ...related].map(
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

    final heard = _heardTrackKeys(history);

    // Load feedback data
    final feedbackService = ExploreFeedbackService.instance;
    await feedbackService.initialize();
    final scoringService = RecommendationScoringService.instance;

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
        if (_containsTrackKey(
              history.recentTrackKeys,
              track.title,
              track.artist,
            ) ||
            !seenTracks.add(key)) {
          continue;
        }

        // Check if we should show this track based on feedback
        if (!feedbackService.shouldShowAgain(track.title, track.artist)) {
          continue;
        }

        final seedIndex = seeds.indexWhere(
          (seed) => _normalize(seed) == _normalize(group.seed),
        );

        // Calculate score using the new scoring service
        final score = scoringService.calculateScore(
          seedArtist: group.seed,
          seedIndex: seedIndex,
          artistFanCount: group.artist.fanCount,
          hasCompleteMetadata:
              track.title.isNotEmpty &&
              track.artist.isNotEmpty &&
              track.artworkUrl.startsWith('https://'),
          title: track.title,
          artist: track.artist,
          history: history,
          heardTracks: heard,
          artistCounts: {}, // Will be filled during selection
        );

        // Generate explanation
        final isSameArtist = _normalize(track.artist) == _normalize(group.seed);
        final isFavorite = favorites.any(
          (f) => _normalize(f) == _normalize(track.artist),
        );
        final isNewArtist = !history.preferredArtists.any(
          (a) => _normalize(a) == _normalize(track.artist),
        );
        final reason = scoringService.generateExplanation(
          seedArtist: group.seed,
          candidateArtist: track.artist,
          isSameArtist: isSameArtist,
          isFavorite: isFavorite,
          isNewArtist: isNewArtist,
          popularity: group.artist.fanCount,
        );

        candidates.add(
          _ScoredRecommendation(
            ExploreRecommendation(
              id: track.id,
              title: track.title,
              artist: track.artist,
              artworkUrl: track.artworkUrl,
              seedArtist: group.seed,
              score: score,
              reason: reason,
              fromCatalog: true,
            artistFanCount: group.artist.fanCount,
            ),
            insertionOrder++,
          ),
        );
      }
    }

    // Always add YouTube-based recommendations for more variety
    // This prioritizes your library over Deezer's potentially irrelevant suggestions
    final fallback = await _searchOnlineRelated(
      youtube: youtube,
      seeds: seeds,
      history: history,
      excludedTitles: seenTracks,
      firstOrder: insertionOrder,
      scoringService: scoringService,
      feedbackService: feedbackService,
    );
    debugPrint(
      'Explore: Added ${fallback.length} YouTube-based recommendations',
    );
    candidates.addAll(fallback);

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
    final ownArtistPool = pool
        .where(
          (item) =>
              item.value.seedArtist.isNotEmpty &&
              _normalize(item.value.artist) ==
                  _normalize(item.value.seedArtist),
        )
        .toList(growable: false);
    final relatedArtistPool = pool
        .where(
          (item) =>
              item.value.seedArtist.isNotEmpty &&
              _normalize(item.value.artist) !=
                  _normalize(item.value.seedArtist),
        )
        .toList(growable: false);
    final ownArtistLimit = relatedArtistPool.isEmpty
        ? limit
        : math.min(limit, math.max(2, (limit * 2) ~/ 5));
    final ownArtistSelection = scoringService.selectDiverse<_ScoredRecommendation>(
      candidates: ownArtistPool,
      trackKey: (item) =>
          '${_normalizeSongTitle(item.value.title)}|${_normalize(item.value.artist)}',
      artistKey: (item) => _normalize(item.value.artist),
      score: (item) =>
          item.value.score + (item.value.fromCatalog ? 20.0 : 0.0),
      limit: ownArtistLimit,
      maxPerArtist: 2,
    );
    final relatedArtistSelection = scoringService.selectDiverse<
      _ScoredRecommendation
    >(
      candidates: relatedArtistPool,
      trackKey: (item) =>
          '${_normalizeSongTitle(item.value.title)}|${_normalize(item.value.artist)}',
      artistKey: (item) => _normalize(item.value.artist),
      score: (item) =>
          item.value.score + (item.value.fromCatalog ? 20.0 : 0.0),
      limit: limit - ownArtistSelection.length,
      maxPerArtist: 2,
    );
    final selected = <ExploreRecommendation>[
      ...ownArtistSelection.map((item) => item.value),
      ...relatedArtistSelection.map((item) => item.value),
    ];
    final sessions = await _buildSessions(
      youtube: youtube,
      history: history,
      seeds: seeds,
      favoriteArtists: favorites,
      catalogRecommendations: pool
          .map((item) => item.value)
          .toList(growable: false),
      round: round,
      scoringService: scoringService,
      feedbackService: feedbackService,
    );
    debugPrint('Explore: Generated ${sessions.length} sessions');
    for (final session in sessions) {
      debugPrint('  - ${session.title}: ${session.items.length} items');
    }
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
    final recommendationKeys = <String>{};
    final sessionRecommendations = sessions
        .expand((session) => session.items)
        .where(
          (item) => recommendationKeys.add(
            listeningTrackKey(item.title, item.artist),
          ),
        )
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
    required RecommendationScoringService scoringService,
    required ExploreFeedbackService feedbackService,
  }) async {
    final definitions = <_SessionDefinition>[];
    // Only show strategies with actual catalog evidence. Legacy rows that were
    // just differently worded YouTube searches are deliberately not exposed.
    const implementedSessionIds = {
      'your_artists',
      'favorites',
      'similar',
      'connected',
      'popular_related',
      'deep_cuts',
      'next_favorite',
      'history_radio',
      'variety',
    };
    const pinnedOrder = [
      'your_artists',
      'favorites',
      'similar',
      'connected',
      'popular_related',
      'deep_cuts',
      'next_favorite',
      'history_radio',
      'variety',
    ];
    const pinnedIds = implementedSessionIds;
    final availableDefinitions = _sessionDefinitions
        .where(
          (definition) =>
              definition.available &&
              implementedSessionIds.contains(definition.id),
        )
        .toList(growable: false);
    debugPrint(
      'Explore: Available session definitions: ${availableDefinitions.length}',
    );
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
    final start = rotatingDefinitions.isEmpty
        ? 0
        : (round * 8) % rotatingDefinitions.length;
    debugPrint(
      'Explore: Rotating from index $start of ${rotatingDefinitions.length}',
    );
    for (
      var offset = 0;
      offset < rotatingDefinitions.length && definitions.length < 15;
      offset++
    ) {
      final definition =
          rotatingDefinitions[(start + offset) % rotatingDefinitions.length];
      definitions.add(definition);
    }
    debugPrint(
      'Explore: Total session definitions to build: ${definitions.length}',
    );

    final recentlyShownTracks = _recentlyShown.toSet();
    final heardTracks = history.recentTrackKeys;
    final usableRecentTracks = history.recentTracks
        .where((track) => !_isKnownNonMusicContent(track.title, track.artist))
        .toList(growable: false);
    final recentTrack = usableRecentTracks.isEmpty
        ? null
        : usableRecentTracks.first;
    final favoriteKeys = favoriteArtists.map(_normalize).toSet();
    final recentHistoryArtists = recentTrack == null
        ? const <String>[]
        : _splitArtistCredits(recentTrack.artist);
    final historyFocusArtist =
        recentHistoryArtists
            .where((artist) => !favoriteKeys.contains(_normalize(artist)))
            .firstOrNull ??
        history.preferredArtists
            .where((artist) => !favoriteKeys.contains(_normalize(artist)))
            .firstOrNull;
    List<ExploreRecommendation> diversify(
      Iterable<ExploreRecommendation> items, {
      int limit = 10,
      int maxPerArtist = 2,
      double Function(ExploreRecommendation)? score,
    }) =>
        scoringService.selectDiverse<ExploreRecommendation>(
          candidates: items,
          trackKey: (item) =>
              '${_normalizeSongTitle(item.title)}|${_normalize(item.artist)}',
          artistKey: (item) => _normalize(item.artist),
          score: score ?? (item) => item.score,
          limit: limit,
          maxPerArtist: maxPerArtist,
        );
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
        if (definition.id == 'your_artists') {
          final reservedArtists = {
            ...favoriteKeys,
            if (historyFocusArtist != null) _normalize(historyFocusArtist),
          };
          final ownArtistTracks = ExploreSessionStrategySelector.ownArtistSongs(
            catalogRecommendations.where(
              (item) => !reservedArtists.contains(_normalize(item.artist)),
            ),
          );
          return ExploreDiscoverySession(
            id: definition.id,
            title: definition.title,
            subtitle: 'Canciones de artistas de tu historial.',
            items: ownArtistTracks,
          );
        }
        if (definition.id == 'favorites') {
          return ExploreDiscoverySession(
            id: definition.id,
            title: definition.title,
            subtitle: definition.subtitle,
            items: diversify(
              ExploreSessionStrategySelector.favoriteArtistSongs(
                catalogRecommendations,
                favoriteArtists: favoriteArtists,
                limit: catalogRecommendations.length,
              ),
            ),
          );
        }
        final favoriteSeedKeys = favoriteArtists.map(_normalize).toSet();
        final affinitySeedKeys = favoriteSeedKeys.isNotEmpty
            ? favoriteSeedKeys
            : {_normalize(seeds.first)};
        final historySeedKeys = seeds
            .map(_normalize)
            .where((key) => !affinitySeedKeys.contains(key))
            .toSet();

        if (definition.id == 'similar') {
          final affinityRecommendations =
              ExploreSessionStrategySelector.relatedToSeeds(
                catalogRecommendations,
                seedArtists: affinitySeedKeys,
              );
          return ExploreDiscoverySession(
            id: definition.id,
            title: definition.title,
            subtitle: 'Canciones cercanas a tus artistas favoritos.',
            items: diversify(affinityRecommendations),
          );
        }
        if (definition.id == 'connected') {
          final discoveryRecommendations =
              ExploreSessionStrategySelector.newRelatedArtists(
                catalogRecommendations,
                seedArtists: historySeedKeys,
                listenedArtists: history.preferredArtists,
              );
          return ExploreDiscoverySession(
            id: definition.id,
            title: definition.title,
            subtitle: 'Artistas nuevos relacionados con lo que escuchas.',
            items: diversify(discoveryRecommendations),
          );
        }
        if (definition.id == 'popular_related') {
          final popular = ExploreSessionStrategySelector.popularRelatedArtists(
            catalogRecommendations,
            limit: catalogRecommendations.length,
          );
          return ExploreDiscoverySession(
            id: definition.id,
            title: definition.title,
            subtitle: definition.subtitle,
            items: diversify(
              popular,
              score: (item) => math.log((item.artistFanCount ?? 1) + 1),
            ),
          );
        }
        if (definition.id == 'deep_cuts') {
          final deepCuts = ExploreSessionStrategySelector.deepCutArtists(
            catalogRecommendations,
            limit: catalogRecommendations.length,
          );
          return ExploreDiscoverySession(
            id: definition.id,
            title: definition.title,
            subtitle: definition.subtitle,
            items: diversify(
              deepCuts,
              score: (item) => -math.log((item.artistFanCount ?? 1) + 1),
            ),
          );
        }
        if (definition.id == 'next_favorite') {
          return ExploreDiscoverySession(
            id: definition.id,
            title: definition.title,
            subtitle: definition.subtitle,
            items: diversify(
              ExploreSessionStrategySelector.topAffinity(
                catalogRecommendations,
                limit: catalogRecommendations.length,
              ),
            ),
          );
        }
        if (definition.id == 'history_radio') {
          final focusKey = _normalize(historyFocusArtist ?? '');
          return ExploreDiscoverySession(
            id: definition.id,
            title: definition.title,
            subtitle: definition.subtitle,
            items: historyFocusArtist == null
                ? const []
                : catalogRecommendations
                      .where(
                        (item) =>
                            item.fromCatalog &&
                            _normalize(item.artist) == focusKey &&
                            _normalize(item.seedArtist) == focusKey,
                      )
                      .take(10)
                      .toList(growable: false),
          );
        }
        if (definition.id == 'variety') {
          final varied = scoringService.selectDiverse<ExploreRecommendation>(
            candidates: catalogRecommendations.where((item) => item.fromCatalog),
            trackKey: (item) =>
                '${_normalizeSongTitle(item.title)}|${_normalize(item.artist)}',
            artistKey: (item) => _normalize(item.artist),
            score: (item) => item.score,
            limit: 10,
            maxPerArtist: 1,
          );
          return ExploreDiscoverySession(
            id: definition.id,
            title: definition.title,
            subtitle: definition.subtitle,
            items: varied,
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
                  '$artistQuery$songContext canción canción oficial audio official video '
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
              final channel = video.author.trim();
              final artist = _normalize(channel).contains(
                _normalize(artistSeed),
              )
                  ? channel
                  : artistSeed;
              final id = video.id.value;
              final titleKey = _normalizeSongTitle(title);
              if (title.isEmpty ||
                  artist.isEmpty ||
                  id.isEmpty ||
                  channel.isEmpty ||
                  _containsTrackKey(heardTracks, title, artist) ||
                  _containsTrackKey(recentlyShownTracks, title, artist) ||
                  ((definition.id == 'your_artists' ||
                          definition.id == 'favorites') &&
                      !_mentionsSeedArtist(title, channel, artistSeed)) ||
                  !_isMusicOnlyResult(
                    title: title,
                    channel: channel,
                    duration: video.duration,
                    seedArtists: [...seeds, artistSeed],
                  )) {
                continue;
              }
              // Calculate score using new scoring service
              final isSameArtist = _normalize(artist) == _normalize(artistSeed);
              final isFavorite = favoriteArtists.any(
                (f) => _normalize(f) == _normalize(artist),
              );
              final isNewArtist = !history.preferredArtists.any(
                (a) => _normalize(a) == _normalize(artist),
              );
              final sessionScore = scoringService.calculateScore(
                seedArtist: artistSeed,
                seedIndex: seedIndex,
                artistFanCount: null,
                hasCompleteMetadata: video.thumbnails.highResUrl.isNotEmpty,
                title: title,
                artist: artist,
                history: history,
                heardTracks: _heardTrackKeys(history),
                artistCounts: {},
              );

              final sessionReason = scoringService.generateExplanation(
                seedArtist: artistSeed,
                candidateArtist: artist,
                isSameArtist: isSameArtist,
                isFavorite: isFavorite,
                isNewArtist: isNewArtist,
                popularity: null,
              );

              items.add(
                ExploreRecommendation(
                  id: id,
                  videoId: id,
                  title: title,
                  artist: artist,
                  artworkUrl: video.thumbnails.highResUrl,
                  seedArtist: artistSeed,
                  score: sessionScore,
                  reason: sessionReason,
                  fromCatalog: false,
                ),
              );
              if (items.length == 12) break searchResultsLoop;
            }
          }
          debugPrint(
            'Explore: Session "${definition.title}" - ${items.length} items from YouTube',
          );
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

    // The featured hero is removed from every row in the page, so keep one
    // extra item per row to guarantee at least ten visible recommendations.
    const minimumSessionItems = 11;
    final fillCandidates = <String, ExploreRecommendation>{};
    void addFillCandidate(ExploreRecommendation item) {
      final key = listeningTrackKey(item.title, item.artist);
      final existing = fillCandidates[key];
      if (existing == null ||
          (item.fromCatalog && !existing.fromCatalog) ||
          item.score > existing.score) {
        fillCandidates[key] = item;
      }
    }

    for (final item in catalogRecommendations) {
      addFillCandidate(item);
    }
    for (final item in rawSessions.expand((session) => session.items)) {
      addFillCandidate(item);
    }

    // If catalog and related search data are still too small, collect one
    // broader music-only batch so every session has enough distinct tracks.
    if (fillCandidates.length < minimumSessionItems) {
      final searches = await Future.wait(
        seeds.take(6).map((seed) async {
          try {
            return await youtube.search
                .search(
                  '"$seed" songs official audio music '
                  '-podcast -interview -reaction -shorts',
                )
                .timeout(const Duration(seconds: 12));
          } catch (_) {
            return null;
          }
        }),
      );
      for (var seedIndex = 0; seedIndex < searches.length; seedIndex++) {
        final videos = searches[seedIndex];
        if (videos == null) continue;
        final seed = seeds[seedIndex];
        for (final video in videos.take(24)) {
          final title = video.title.trim();
          final artist = video.author.trim();
          final id = video.id.value;
          if (id.isEmpty ||
              title.isEmpty ||
              artist.isEmpty ||
              _isKnownNonMusicContent(title, artist) ||
              _containsTrackKey(heardTracks, title, artist) ||
              !_isMusicOnlyResult(
                title: title,
                channel: artist,
                duration: video.duration,
                seedArtists: [seed],
              ) ||
              !feedbackService.shouldShowAgain(title, artist)) {
            continue;
          }
          addFillCandidate(
            ExploreRecommendation(
              id: id,
              videoId: id,
              title: title,
              artist: artist,
              artworkUrl: video.thumbnails.highResUrl,
              seedArtist: seed,
              score: -20,
              reason: 'Relacionado con $seed',
            ),
          );
        }
      }
    }

    final sessions = <ExploreDiscoverySession>[];
    debugPrint('Explore: Filtering ${rawSessions.length} raw sessions');
    for (final session in rawSessions) {
      if (session.sourceUnavailable) {
        debugPrint('  - ${session.title}: source unavailable, keeping');
        sessions.add(session);
        continue;
      }
      final uniqueItems = <String, ExploreRecommendation>{};
      for (final item in session.items) {
        uniqueItems.putIfAbsent(
          listeningTrackKey(item.title, item.artist),
          () => item,
        );
      }
      final remaining = fillCandidates.entries
          .where((entry) => !uniqueItems.containsKey(entry.key))
          .toList()
        ..sort((a, b) {
          final aScore = a.value.score + (a.value.fromCatalog ? 20 : 0);
          final bScore = b.value.score + (b.value.fromCatalog ? 20 : 0);
          return bScore.compareTo(aScore);
        });
      if (uniqueItems.length < minimumSessionItems && remaining.isNotEmpty) {
        final targetCount = math.min(
          minimumSessionItems - uniqueItems.length,
          remaining.length,
        );
        final diverse = scoringService.selectDiverse<ExploreRecommendation>(
          candidates: remaining.map((entry) => entry.value).toList(),
          trackKey: (item) => listeningTrackKey(item.title, item.artist),
          artistKey: (item) => _normalize(item.artist),
          score: (item) => item.score + (item.fromCatalog ? 20 : 0),
          limit: targetCount,
          maxPerArtist: 3,
        );
        for (final item in diverse) {
          uniqueItems.putIfAbsent(
            listeningTrackKey(item.title, item.artist),
            () => item,
          );
        }
        if (uniqueItems.length < minimumSessionItems) {
          for (final entry in remaining) {
            uniqueItems.putIfAbsent(entry.key, () => entry.value);
            if (uniqueItems.length >= minimumSessionItems) break;
          }
        }
      }
      if (uniqueItems.isEmpty) continue;
      final items = uniqueItems.values.take(minimumSessionItems).toList();
      debugPrint(
        '  - ${session.title}: ${items.length} unique items, keeping',
      );
      sessions.add(
        ExploreDiscoverySession(
          id: session.id,
          title: session.title,
          subtitle: session.subtitle,
          items: List.unmodifiable(items),
        ),
      );
    }
    debugPrint('Explore: Final sessions after filtering: ${sessions.length}');
    return sessions;
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
        (duration.inSeconds < 60 || duration > const Duration(minutes: 20))) {
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

  Set<String> _heardTrackKeys(ListeningHistoryProfile history) => {
    ...history.trackPlayCounts.keys,
    ...history.recentTrackKeys,
  };

  bool _isKnownNonMusicContent(String title, String channel) => RegExp(
    r'\b(podcast|entrevista|interview|programa|episodio|episode|reaccion|reaction|review|noticias|news|noticiero|talk show|got talent|talent show|the voice|la voz|yo me llamo|al rojo vivo|famous miau|sorprende a todos|imitador|imitadora|audicion|reality|television|tv show|canal de tv|bailando con las estrellas|concursante|participante|reportaje|documental|documentary|trailer|teaser|shorts|live concert|full concert|concierto completo)\b',
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

  bool _containsTrackKey(Set<String> knownKeys, String title, String artist) {
    final candidateTitle = _normalizeSongTitle(title);
    final candidateArtists = _splitArtistCredits(artist)
        .map(_normalize)
        .where((name) => name.isNotEmpty)
        .toSet();
    if (candidateTitle.isEmpty || candidateArtists.isEmpty) return false;
    for (final key in knownKeys) {
      final parts = key.split('|');
      if (parts.length < 2 || _normalizeSongTitle(parts.first) != candidateTitle) {
        continue;
      }
      final knownArtists = _splitArtistCredits(parts.skip(1).join(' '))
          .map(_normalize)
          .where((name) => name.isNotEmpty)
          .toSet();
      if (candidateArtists.any(knownArtists.contains)) return true;
    }
    return false;
  }

  Future<List<_ScoredRecommendation>> _searchOnlineRelated({
    required YoutubeExplode youtube,
    required List<String> seeds,
    required ListeningHistoryProfile history,
    required Set<String> excludedTitles,
    required int firstOrder,
    required RecommendationScoringService scoringService,
    required ExploreFeedbackService feedbackService,
  }) async {
    final heardTrackKeys = _heardTrackKeys(history);
    final candidates = <_ScoredRecommendation>[];
    final seenTracks = <String>{...history.recentTrackKeys};
    for (final key in excludedTitles) {
      seenTracks.add(key);
    }
    final seenVideoIds = <String>{};
    var order = firstOrder;
    final results = await Future.wait([
      for (final seed in seeds)
        () async {
          try {
            return await youtube.search
                .search(
                  '"$seed" canciones official audio canción oficial '
                  '-podcast -entrevista -programa -reacción -review -shorts',
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
        final channel = video.author.trim();
        final id = video.id.value;
        final titleKey = _normalizeSongTitle(title);
        final channelMentionsSeed =
            _normalize(channel).contains(_normalize(seed));
        final artist = channelMentionsSeed ? channel : seed;
        final trackKey = listeningTrackKey(titleKey, artist);
        if (title.isEmpty ||
            channel.isEmpty ||
            id.isEmpty ||
            !_mentionsSeedArtist(title, channel, seed) ||
            !_isMusicOnlyResult(
              title: title,
              channel: channel,
              duration: video.duration,
              seedArtists: [seed],
            ) ||
            !seenVideoIds.add(id) ||
            _containsTrackKey(seenTracks, title, artist) ||
            !seenTracks.add(trackKey)) {
          continue;
        }

        // Check feedback
        if (!feedbackService.shouldShowAgain(title, artist)) {
          continue;
        }

        // Calculate score with new scoring service
        final score = scoringService.calculateScore(
          seedArtist: seed,
          seedIndex: seedIndex,
          artistFanCount: null, // YouTube doesn't provide fan count
          hasCompleteMetadata: video.thumbnails.highResUrl.isNotEmpty,
          title: title,
          artist: artist,
          history: history,
          heardTracks: heardTrackKeys,
          artistCounts: {},
        );

        // Generate explanation
        final isSameArtist = _normalize(artist) == _normalize(seed);
        final isNewArtist = !history.preferredArtists.any(
          (a) => _normalize(a) == _normalize(artist),
        );
        final reason = scoringService.generateExplanation(
          seedArtist: seed,
          candidateArtist: artist,
          isSameArtist: isSameArtist,
          isFavorite: false,
          isNewArtist: isNewArtist,
          popularity: null,
        );

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
              reason: reason,
              fromCatalog: false,
            ),
            order++,
          ),
        );
        if (candidates.length >= 18) break;
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
