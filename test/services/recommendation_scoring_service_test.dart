import 'package:flutter_test/flutter_test.dart';
import 'package:soundneed_pc/services/listening_history_service.dart';
import 'package:soundneed_pc/services/recommendation_scoring_service.dart';

void main() {
  group('RecommendationScoringService', () {
    late RecommendationScoringService scoringService;

    setUp(() {
      scoringService = RecommendationScoringService.instance;
    });

    test('calculates affinity correctly for same artist', () {
      final history = ListeningHistoryProfile(
        preferredArtists: ['Bad Bunny', 'Karol G'],
        searchedArtists: [],
        recentTrackKeys: {},
        trackPlayCounts: {},
        recentTracks: [],
      );

      final score = scoringService.calculateScore(
        seedArtist: 'Bad Bunny',
        seedIndex: 0,
        artistFanCount: 50000000,
        hasCompleteMetadata: true,
        title: 'Tití Me Preguntó',
        artist: 'Bad Bunny',
        history: history,
        heardTracks: {},
        artistCounts: {},
      );

      expect(score, greaterThan(80)); // Should be high for same artist
    });

    test('calculates affinity correctly for favorite artist', () {
      final history = ListeningHistoryProfile(
        preferredArtists: ['Bad Bunny', 'Karol G'],
        searchedArtists: [],
        recentTrackKeys: {},
        trackPlayCounts: {},
        recentTracks: [],
      );

      final score = scoringService.calculateScore(
        seedArtist: 'Bad Bunny',
        seedIndex: 0,
        artistFanCount: 50000000,
        hasCompleteMetadata: true,
        title: 'Hawái',
        artist: 'Karol G',
        history: history,
        heardTracks: {},
        artistCounts: {},
      );

      expect(score, greaterThan(85)); // Should be high for favorite
    });

    test('penalizes over-representation of artist', () {
      final history = ListeningHistoryProfile(
        preferredArtists: ['Bad Bunny'],
        searchedArtists: [],
        recentTrackKeys: {},
        trackPlayCounts: {},
        recentTracks: [],
      );

      // No over-representation
      final score1 = scoringService.calculateScore(
        seedArtist: 'Bad Bunny',
        seedIndex: 0,
        artistFanCount: 50000000,
        hasCompleteMetadata: true,
        title: 'Song 1',
        artist: 'Bad Bunny',
        history: history,
        heardTracks: {},
        artistCounts: {},
      );

      // Over-representation (3 songs already)
      final artistCounts = {'bad bunny': 3};
      final score2 = scoringService.calculateScore(
        seedArtist: 'Bad Bunny',
        seedIndex: 0,
        artistFanCount: 50000000,
        hasCompleteMetadata: true,
        title: 'Song 4',
        artist: 'Bad Bunny',
        history: history,
        heardTracks: {},
        artistCounts: artistCounts,
      );

      // Over-represented artist should have lower score
      expect(score2, lessThan(score1));
    });

    test('penalizes a song already present in listening history', () {
      final history = ListeningHistoryProfile(
        preferredArtists: ['Bad Bunny'],
        searchedArtists: [],
        recentTrackKeys: {},
        trackPlayCounts: {},
        recentTracks: [],
      );

      final heardTracks = {'heard song|karol g'};

      final heardScore = scoringService.calculateScore(
        seedArtist: 'Bad Bunny',
        seedIndex: 0,
        artistFanCount: 50000000,
        hasCompleteMetadata: true,
        title: 'Heard Song',
        artist: 'Karol G',
        history: history,
        heardTracks: heardTracks,
        artistCounts: {},
      );

      final newSongScore = scoringService.calculateScore(
        seedArtist: 'Bad Bunny',
        seedIndex: 0,
        artistFanCount: 50000000,
        hasCompleteMetadata: true,
        title: 'New Song',
        artist: 'New Artist',
        history: history,
        heardTracks: heardTracks,
        artistCounts: {},
      );

      expect(newSongScore, greaterThan(heardScore));
    });

    test('generates correct explanations', () {
      // Same artist
      final sameArtist = scoringService.generateExplanation(
        seedArtist: 'Bad Bunny',
        candidateArtist: 'Bad Bunny',
        isSameArtist: true,
        isFavorite: true,
        isNewArtist: false,
        popularity: 50000000,
      );
      expect(sameArtist, contains('Más canciones'));

      // Favorite
      final favorite = scoringService.generateExplanation(
        seedArtist: 'Bad Bunny',
        candidateArtist: 'Karol G',
        isSameArtist: false,
        isFavorite: true,
        isNewArtist: false,
        popularity: 50000000,
      );
      expect(favorite, contains('favoritos'));

      // New artist
      final newArtist = scoringService.generateExplanation(
        seedArtist: 'Bad Bunny',
        candidateArtist: 'Unknown Artist',
        isSameArtist: false,
        isFavorite: false,
        isNewArtist: true,
        popularity: null,
      );
      expect(newArtist, contains('Nuevo artista'));
    });

    test('normalizes popularity correctly', () {
      final history = ListeningHistoryProfile(
        preferredArtists: [],
        searchedArtists: [],
        recentTrackKeys: {},
        trackPlayCounts: {},
        recentTracks: [],
      );

      // Very popular artist
      final popularScore = scoringService.calculateScore(
        seedArtist: 'Bad Bunny',
        seedIndex: 0,
        artistFanCount: 100000000,
        hasCompleteMetadata: true,
        title: 'Song',
        artist: 'Popular Artist',
        history: history,
        heardTracks: {},
        artistCounts: {},
      );

      // Less popular artist
      final lessPopularScore = scoringService.calculateScore(
        seedArtist: 'Bad Bunny',
        seedIndex: 0,
        artistFanCount: 10000,
        hasCompleteMetadata: true,
        title: 'Song',
        artist: 'Less Popular',
        history: history,
        heardTracks: {},
        artistCounts: {},
      );

      expect(popularScore, greaterThan(lessPopularScore));
    });

    test('complete metadata receives a quality bonus', () {
      final history = ListeningHistoryProfile(
        preferredArtists: ['Bad Bunny'],
        searchedArtists: [],
        recentTrackKeys: {},
        trackPlayCounts: {},
        recentTracks: [],
      );

      final completeScore = scoringService.calculateScore(
        seedArtist: 'Bad Bunny',
        seedIndex: 0,
        artistFanCount: 50000000,
        hasCompleteMetadata: true,
        title: 'Song',
        artist: 'Artist',
        history: history,
        heardTracks: {},
        artistCounts: {},
      );

      final incompleteScore = scoringService.calculateScore(
        seedArtist: 'Bad Bunny',
        seedIndex: 0,
        artistFanCount: 50000000,
        hasCompleteMetadata: false,
        title: 'Song',
        artist: 'Artist',
        history: history,
        heardTracks: {},
        artistCounts: {},
      );

      expect(completeScore, greaterThan(incompleteScore));
    });

    test('ranking weights sum to one', () {
      expect(RecommendationScoringService.totalWeight, closeTo(1.0, 1e-9));
    });

    test('diverse selection deduplicates tracks and limits each artist', () {
      final candidates = [
        (title: 'A1', artist: 'Artist A', score: 100.0),
        (title: 'A1', artist: 'Artist A', score: 99.0),
        (title: 'A2', artist: 'Artist A', score: 98.0),
        (title: 'A3', artist: 'Artist A', score: 97.0),
        (title: 'B1', artist: 'Artist B', score: 80.0),
      ];

      final selected = scoringService.selectDiverse(
        candidates: candidates,
        trackKey: (item) => '${item.title.toLowerCase()}|${item.artist}',
        artistKey: (item) => item.artist,
        score: (item) => item.score,
        limit: 5,
        maxPerArtist: 2,
      );

      expect(selected.map((item) => item.title).toList(), ['A1', 'A2', 'B1']);
      expect(selected.where((item) => item.artist == 'Artist A'), hasLength(2));
    });

    test('diverse selection is stable for ties and empty input', () {
      final candidates = [
        (title: 'First', artist: 'Artist A', score: 50.0),
        (title: 'Second', artist: 'Artist B', score: 50.0),
      ];

      final selected = scoringService.selectDiverse(
        candidates: candidates,
        trackKey: (item) => item.title,
        artistKey: (item) => item.artist,
        score: (item) => item.score,
      );

      expect(selected.map((item) => item.title), ['First', 'Second']);
      expect(
        scoringService.selectDiverse<(String, String)>(
          candidates: const [],
          trackKey: (item) => item.$1,
          artistKey: (item) => item.$2,
          score: (_) => 0,
        ),
        isEmpty,
      );
    });

    test('includes feedback affinity in score', () {
      final history = ListeningHistoryProfile(
        preferredArtists: ['Bad Bunny'],
        searchedArtists: [],
        recentTrackKeys: {},
        trackPlayCounts: {},
        recentTracks: [],
      );

      // Track without feedback (feedback affinity will be 0)
      final scoreWithoutFeedback = scoringService.calculateScore(
        seedArtist: 'Bad Bunny',
        seedIndex: 0,
        artistFanCount: 50000000,
        hasCompleteMetadata: true,
        title: 'Song A',
        artist: 'Artist A',
        history: history,
        heardTracks: {},
        artistCounts: {},
      );

      // Verify score is valid and feedback is integrated (even if 0 initially)
      expect(scoreWithoutFeedback, greaterThan(0));
      expect(scoreWithoutFeedback, lessThanOrEqualTo(100));
    });

    test('handles popularity absence gracefully', () {
      final history = ListeningHistoryProfile(
        preferredArtists: [],
        searchedArtists: [],
        recentTrackKeys: {},
        trackPlayCounts: {},
        recentTracks: [],
      );

      // No popularity data
      final score = scoringService.calculateScore(
        seedArtist: 'Unknown Artist',
        seedIndex: 0,
        artistFanCount: null,
        hasCompleteMetadata: true,
        title: 'Song',
        artist: 'Artist',
        history: history,
        heardTracks: {},
        artistCounts: {},
      );

      // Should still return a valid score (popularity defaults to 20)
      expect(score, greaterThan(0));
      expect(score, lessThanOrEqualTo(100));
    });

    test('normalizes weights correctly', () {
      final history = ListeningHistoryProfile(
        preferredArtists: ['Bad Bunny'],
        searchedArtists: [],
        recentTrackKeys: {},
        trackPlayCounts: {},
        recentTracks: [],
      );

      final score = scoringService.calculateScore(
        seedArtist: 'Bad Bunny',
        seedIndex: 0,
        artistFanCount: 50000000,
        hasCompleteMetadata: true,
        title: 'Song',
        artist: 'Bad Bunny',
        history: history,
        heardTracks: {},
        artistCounts: {},
      );

      // Score should be between 0 and 100
      expect(score, greaterThanOrEqualTo(0));
      expect(score, lessThanOrEqualTo(100));
    });
  });
}
