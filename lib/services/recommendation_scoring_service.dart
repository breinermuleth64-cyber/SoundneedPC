import 'dart:math' as math;

import 'explore_feedback_service.dart';
import 'listening_history_service.dart';

/// Explicit scoring system for music recommendations with real signals.
class RecommendationScoringService {
  RecommendationScoringService._();

  static final instance = RecommendationScoringService._();

  /// Weights for different signals (must sum to 1.0)
  /// Adjusted to make differences more visible in recommendations
  static const affinityWeight = 0.35;
  static const historyWeight = 0.20;
  static const noveltyWeight = 0.15;
  static const popularityWeight = 0.10;
  static const diversityWeight = 0.10;
  static const metadataWeight = 0.10;

  static const totalWeight =
      affinityWeight +
      historyWeight +
      noveltyWeight +
      popularityWeight +
      diversityWeight +
      metadataWeight;

  /// Calculates a score for a recommendation based on real signals.
  double calculateScore({
    required String seedArtist,
    required int seedIndex,
    required int? artistFanCount,
    required bool hasCompleteMetadata,
    required String title,
    required String artist,
    required ListeningHistoryProfile history,
    required Set<String> heardTracks,
    required Map<String, int> artistCounts,
  }) {
    // Feedback affinity: Get user's explicit feedback for this specific track
    // This is the ONLY place where feedback is used to avoid duplication
    final feedbackAffinity = ExploreFeedbackService.instance.getAffinityScore(
      title,
      artist,
    );
    final artistFeedback = ExploreFeedbackService.instance
        .getArtistAffinityScore(artist);

    // Affinity: How close this artist is to the user's preferences
    // We integrate feedback into affinity instead of using a separate weight
    final affinity = _calculateAffinity(
      seedIndex,
      seedArtist,
      artist,
      history,
      feedbackAffinity,
      artistFeedback,
    );

    // History signal: How relevant this artist is based on listening history
    final historySignal = _calculateHistorySignal(seedIndex, artist, history);

    // Novelty: Is this artist/song new to the user?
    final novelty = _calculateNovelty(artist, title, history, heardTracks);

    // Popularity: Based on actual fan count from catalog
    final popularity = _calculatePopularity(artistFanCount);
    final effectivePopularityWeight =
        artistFanCount == null || artistFanCount <= 0 ? 0.0 : popularityWeight;
    final activeWeightTotal =
        affinityWeight +
        historyWeight +
        noveltyWeight +
        effectivePopularityWeight +
        diversityWeight +
        metadataWeight;

    // Diversity: Penalize if this artist is already dominating the session
    final diversity = _calculateDiversity(artist, artistCounts);

    // Missing metadata is penalized conservatively; it is not evidence that a
    // song is bad, but a complete catalog record is easier to verify/play.
    final metadata = hasCompleteMetadata ? 100.0 : 35.0;
    final weightedScore =
        affinityWeight * affinity +
        historyWeight * historySignal +
        noveltyWeight * novelty +
        effectivePopularityWeight * popularity +
        diversityWeight * diversity +
        metadataWeight * metadata;
    final score = weightedScore / activeWeightTotal;

    final finalScore = score.clamp(0.0, 100.0);

    return finalScore;
  }

  /// Selects the highest scoring unique tracks while limiting artist dominance.
  /// Ties preserve source order, making identical inputs deterministic.
  List<T> selectDiverse<T>({
    required Iterable<T> candidates,
    required String Function(T) trackKey,
    required String Function(T) artistKey,
    required double Function(T) score,
    int limit = 20,
    int maxPerArtist = 2,
  }) {
    if (limit <= 0 || maxPerArtist <= 0) return const [];
    final unique = <(T, int)>[];
    final seenTracks = <String>{};
    var sourceOrder = 0;
    for (final candidate in candidates) {
      final key = trackKey(candidate).trim();
      if (key.isNotEmpty && seenTracks.add(key)) {
        unique.add((candidate, sourceOrder));
      }
      sourceOrder++;
    }

    final counts = <String, int>{};
    final selected = <T>[];
    while (unique.isNotEmpty && selected.length < limit) {
      unique.sort((a, b) {
        final artistA = artistKey(a.$1).trim().toLowerCase();
        final artistB = artistKey(b.$1).trim().toLowerCase();
        final scoreA = score(a.$1) - (counts[artistA] ?? 0) * 18.0;
        final scoreB = score(b.$1) - (counts[artistB] ?? 0) * 18.0;
        final byScore = scoreB.compareTo(scoreA);
        return byScore != 0 ? byScore : a.$2.compareTo(b.$2);
      });
      final index = unique.indexWhere(
        (entry) =>
            (counts[artistKey(entry.$1).trim().toLowerCase()] ?? 0) <
            maxPerArtist,
      );
      if (index < 0) break;
      final next = unique.removeAt(index).$1;
      selected.add(next);
      final key = artistKey(next).trim().toLowerCase();
      counts.update(key, (count) => count + 1, ifAbsent: () => 1);
    }
    return List.unmodifiable(selected);
  }

  /// Calculates affinity based on seed position and artist relationship.
  double _calculateAffinity(
    int seedIndex,
    String seedArtist,
    String candidateArtist,
    ListeningHistoryProfile history,
    double feedbackAffinity,
    double artistFeedback,
  ) {
    // Higher seeds (lower index) have higher affinity
    final seedAffinity = (100 - seedIndex.clamp(0, 4) * 12).toDouble();

    // Bonus if this is a favorite artist - INCREASED for more visible difference
    final isFavorite = history.preferredArtists.any(
      (a) => _normalize(a) == _normalize(candidateArtist),
    );
    final favoriteBonus = isFavorite ? 35.0 : 0.0;

    // Bonus if the candidate is the same as the seed (more songs from liked artist)
    final isSameArtist = _normalize(seedArtist) == _normalize(candidateArtist);
    final sameArtistBonus = isSameArtist ? 25.0 : 0.0;

    // Integrate explicit feedback as a boost (max 20 points)
    // This is scaled so that max feedback (100) contributes 20 points to affinity
    final feedbackBoost =
        feedbackAffinity * 0.15 + artistFeedback * 0.20;

    return (seedAffinity + favoriteBonus + sameArtistBonus + feedbackBoost)
        .clamp(0.0, 100.0);
  }

  /// Calculates history signal based on how much the user listens to this artist.
  double _calculateHistorySignal(
    int seedIndex,
    String artist,
    ListeningHistoryProfile history,
  ) {
    // Base signal from seed position
    final baseSignal = (100 - seedIndex.clamp(0, 4) * 18).toDouble();

    // Check if this artist is in the user's listening history
    final artistKey = _normalize(artist);
    final isListened = history.preferredArtists.any(
      (a) => _normalize(a) == artistKey,
    );

    if (!isListened) {
      // New artist - lower signal but encourage discovery
      return baseSignal * 0.7;
    }

    // Find the rank of this artist in preferences
    final rank = history.preferredArtists.indexWhere(
      (a) => _normalize(a) == artistKey,
    );
    if (rank >= 0) {
      // Higher rank (earlier in list) = higher signal
      final rankBonus = (20 - rank.clamp(0, 19)).toDouble();
      return (baseSignal + rankBonus).clamp(0.0, 100.0);
    }

    return baseSignal;
  }

  /// Calculates novelty based on whether this is new content for the user.
  double _calculateNovelty(
    String artist,
    String title,
    ListeningHistoryProfile history,
    Set<String> heardTracks,
  ) {
    final trackKey = listeningTrackKey(title, artist);

    // If already heard, heavily reduce novelty - INCREASED penalty
    if (heardTracks.contains(trackKey)) {
      return 10.0; // Very low novelty for heard tracks
    }

    // Check if artist is known
    final artistKey = _normalize(artist);
    final artistKnown = history.preferredArtists.any(
      (a) => _normalize(a) == artistKey,
    );

    if (artistKnown) {
      // Known artist, new song - medium novelty
      return 70.0;
    }

    // Unknown artist - maximum novelty for discovery
    return 100.0;
  }

  /// Calculates popularity based on actual fan count from catalog.
  double _calculatePopularity(int? fanCount) {
    if (fanCount == null || fanCount <= 0) {
      return 0.0; // Omitted from the normalized score when unknown.
    }

    // Logarithmic scale to avoid huge artists dominating
    // Range: 0 to 100, where 100M+ fans = 100
    final normalized = (math.log(fanCount + 1) / math.log(100000001) * 100);
    return normalized.clamp(0.0, 100.0);
  }

  /// Calculates diversity score, penalizing over-representation.
  double _calculateDiversity(String artist, Map<String, int> artistCounts) {
    final artistKey = _normalize(artist);
    final count = artistCounts[artistKey] ?? 0;

    // Penalize exponentially as count increases
    // 0 songs = 100, 1 song = 85, 2 songs = 55, 3 songs = 25
    if (count == 0) return 100.0;
    if (count == 1) return 85.0;
    if (count == 2) return 55.0;
    if (count >= 3) return 25.0;
    return 100.0;
  }

  /// Generates an explanation for why a recommendation was made.
  String generateExplanation({
    required String seedArtist,
    required String candidateArtist,
    required bool isSameArtist,
    required bool isFavorite,
    required bool isNewArtist,
    required int? popularity,
  }) {
    if (isSameArtist) {
      return 'Más canciones de $seedArtist';
    }

    if (isFavorite) {
      return 'Relacionado con tus favoritos';
    }

    if (isNewArtist) {
      return 'Nuevo artista relacionado con $seedArtist';
    }

    if (popularity != null && popularity > 1000000) {
      return 'Popular en la escena de $seedArtist';
    }

    return 'Relacionado con $seedArtist';
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
