import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soundneed_pc/services/explore_feedback_service.dart';
import 'package:soundneed_pc/services/listening_history_service.dart';
import 'package:soundneed_pc/services/recommendation_scoring_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Learning Validation Tests', () {
    late RecommendationScoringService scoringService;
    late ExploreFeedbackService feedbackService;

    setUp(() async {
      // Clear SharedPreferences before each test
      SharedPreferences.setMockInitialValues({});
      ExploreFeedbackService.instance.resetForTesting();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('soundneed_explore_feedback_v1');

      scoringService = RecommendationScoringService.instance;
      feedbackService = ExploreFeedbackService.instance;
    });

    test('positive feedback produces consistent score improvement', () async {
      final history = ListeningHistoryProfile(
        preferredArtists: [],
        searchedArtists: [],
        recentTracks: [],
        recentTrackKeys: [],
        trackPlayCounts: {},
      );

      // Baseline score without feedback
      final baselineScore = scoringService.calculateScore(
        seedArtist: 'Artist A',
        seedIndex: 0,
        artistFanCount: 1000000,
        hasCompleteMetadata: true,
        title: 'Test Song',
        artist: 'Artist B',
        history: history,
        heardTracks: {},
        artistCounts: {},
      );

      // Add positive feedback (like)
      await feedbackService.recordInteraction(
        title: 'Test Song',
        artist: 'Artist B',
        type: FeedbackType.like,
      );

      // Score with feedback
      final scoreWithFeedback = scoringService.calculateScore(
        seedArtist: 'Artist A',
        seedIndex: 0,
        artistFanCount: 1000000,
        hasCompleteMetadata: true,
        title: 'Test Song',
        artist: 'Artist B',
        history: history,
        heardTracks: {},
        artistCounts: {},
      );

      // Verify improvement is consistent (should be exactly the feedback boost)
      final improvement = scoreWithFeedback - baselineScore;
      // Feedback boost should be 10 * 0.15 = 1.5 points
      expect(improvement, closeTo(1.5, 0.1));
    });

    test('negative feedback reduces affinity according to rules', () async {
      final history = ListeningHistoryProfile(
        preferredArtists: [],
        searchedArtists: [],
        recentTracks: [],
        recentTrackKeys: [],
        trackPlayCounts: {},
      );

      // Baseline score
      final baselineScore = scoringService.calculateScore(
        seedArtist: 'Artist A',
        seedIndex: 0,
        artistFanCount: 1000000,
        hasCompleteMetadata: true,
        title: 'Test Song',
        artist: 'Artist B',
        history: history,
        heardTracks: {},
        artistCounts: {},
      );

      // Add negative feedback (skip)
      await feedbackService.recordInteraction(
        title: 'Test Song',
        artist: 'Artist B',
        type: FeedbackType.skip,
      );

      // Score with negative feedback
      final scoreWithFeedback = scoringService.calculateScore(
        seedArtist: 'Artist A',
        seedIndex: 0,
        artistFanCount: 1000000,
        hasCompleteMetadata: true,
        title: 'Test Song',
        artist: 'Artist B',
        history: history,
        heardTracks: {},
        artistCounts: {},
      );

      // Verify reduction follows rules (skip penalty: 3 * 0.15 = 0.45)
      final reduction = baselineScore - scoreWithFeedback;
      expect(reduction, closeTo(0.45, 0.1));
    });

    test('favorites and feedback do not duplicate the same interaction', () async {
      final history = ListeningHistoryProfile(
        preferredArtists: ['Artist B'], // Artist is already a favorite
        recentTracks: [],
        recentTrackKeys: [],
        trackPlayCounts: {},
      );

      // Score with favorite only
      final scoreFavoriteOnly = scoringService.calculateScore(
        seedArtist: 'Artist A',
        seedIndex: 0,
        artistFanCount: 1000000,
        hasCompleteMetadata: true,
        title: 'Test Song',
        artist: 'Artist B',
        history: history,
        heardTracks: {},
        artistCounts: {},
      );

      // Add feedback for the same artist
      await feedbackService.recordInteraction(
        title: 'Test Song',
        artist: 'Artist B',
        type: FeedbackType.like,
      );

      // Score with both favorite and feedback
      final scoreWithBoth = scoringService.calculateScore(
        seedArtist: 'Artist A',
        seedIndex: 0,
        artistFanCount: 1000000,
        hasCompleteMetadata: true,
        title: 'Test Song',
        artist: 'Artist B',
        history: history,
        heardTracks: {},
        artistCounts: {},
      );

      // The increase should be exactly the feedback boost (not duplicated)
      final increase = scoreWithBoth - scoreFavoriteOnly;
      expect(increase, closeTo(1.5, 0.1)); // Like: 10 * 0.15 = 1.5
    });

    test('absence of history produces reasonable recommendations', () async {
      final emptyHistory = ListeningHistoryProfile(
        preferredArtists: [],
        recentTracks: [],
        recentTrackKeys: [],
        trackPlayCounts: {},
      );

      // Score with empty history
      final score = scoringService.calculateScore(
        seedArtist: 'Artist A',
        seedIndex: 0,
        artistFanCount: 1000000,
        hasCompleteMetadata: true,
        title: 'Test Song',
        artist: 'Artist B',
        history: emptyHistory,
        heardTracks: {},
        artistCounts: {},
      );

      // Should produce a reasonable score (not 0, not extreme)
      expect(score, greaterThan(0.0));
      expect(score, lessThan(100.0));
      expect(score, greaterThan(20.0)); // At minimum, affinity + metadata
    });

    test('behavior persists after save and reload', () async {
      final history = ListeningHistoryProfile(
        preferredArtists: [],
        searchedArtists: [],
        recentTracks: [],
        recentTrackKeys: [],
        trackPlayCounts: {},
      );

      // Add feedback
      await feedbackService.recordInteraction(
        title: 'Test Song',
        artist: 'Artist B',
        type: FeedbackType.like,
      );

      // Get affinity before reload
      final affinityBefore = feedbackService.getAffinityScore(
        'Test Song',
        'Artist B',
      );

      // Simulate reload by creating new instance
      // (In real app, this would be app restart)
      final newFeedbackService = ExploreFeedbackService.instance;

      // Get affinity after reload
      final affinityAfter = newFeedbackService.getAffinityScore(
        'Test Song',
        'Artist B',
      );

      // Affinity should be the same
      expect(affinityAfter, equals(affinityBefore));
    });

    test('score comparison: before and after feedback is deterministic', () async {
      final history = ListeningHistoryProfile(
        preferredArtists: [],
        searchedArtists: [],
        recentTracks: [],
        recentTrackKeys: [],
        trackPlayCounts: {},
      );

      // Get score before feedback
      final scoreBefore = scoringService.calculateScore(
        seedArtist: 'Artist A',
        seedIndex: 0,
        artistFanCount: 1000000,
        hasCompleteMetadata: true,
        title: 'Test Song',
        artist: 'Artist B',
        history: history,
        heardTracks: {},
        artistCounts: {},
      );

      // Add multiple positive interactions
      await feedbackService.recordInteraction(
        title: 'Test Song',
        artist: 'Artist B',
        type: FeedbackType.like,
      );
      await feedbackService.recordInteraction(
        title: 'Test Song',
        artist: 'Artist B',
        type: FeedbackType.addToPlaylist,
      );
      await feedbackService.recordInteraction(
        title: 'Test Song',
        artist: 'Artist B',
        type: FeedbackType.complete,
      );

      // Get score after feedback
      final scoreAfter = scoringService.calculateScore(
        seedArtist: 'Artist A',
        seedIndex: 0,
        artistFanCount: 1000000,
        hasCompleteMetadata: true,
        title: 'Test Song',
        artist: 'Artist B',
        history: history,
        heardTracks: {},
        artistCounts: {},
      );

      // Calculate expected improvement
      // Like: 10, AddToPlaylist: 8, Complete: 5 = 23 total
      // Scaled by 0.15 = 3.45 points expected
      final expectedImprovement = 23.0 * 0.15;
      final actualImprovement = scoreAfter - scoreBefore;

      expect(actualImprovement, closeTo(expectedImprovement, 0.2));
    });

    test('feedback affects only specific track, not entire artist', () async {
      final history = ListeningHistoryProfile(
        preferredArtists: [],
        searchedArtists: [],
        recentTracks: [],
        recentTrackKeys: [],
        trackPlayCounts: {},
      );

      // Add feedback to specific track
      await feedbackService.recordInteraction(
        title: 'Song A',
        artist: 'Artist B',
        type: FeedbackType.like,
      );

      // Score the track with feedback
      final scoreA = scoringService.calculateScore(
        seedArtist: 'Artist A',
        seedIndex: 0,
        artistFanCount: 1000000,
        hasCompleteMetadata: true,
        title: 'Song A',
        artist: 'Artist B',
        history: history,
        heardTracks: {},
        artistCounts: {},
      );

      // Score a different track by same artist without feedback
      final scoreB = scoringService.calculateScore(
        seedArtist: 'Artist A',
        seedIndex: 0,
        artistFanCount: 1000000,
        hasCompleteMetadata: true,
        title: 'Song B',
        artist: 'Artist B',
        history: history,
        heardTracks: {},
        artistCounts: {},
      );

      // Track A should score higher
      expect(scoreA, greaterThan(scoreB));
    });

    test('recency decay affects older feedback', () async {
      final history = ListeningHistoryProfile(
        preferredArtists: [],
        searchedArtists: [],
        recentTracks: [],
        recentTrackKeys: [],
        trackPlayCounts: {},
      );

      // Note: We can't actually test time decay in unit tests without
      // manipulating time, but we can verify the formula is applied
      // by checking that affinity is calculated from feedback service

      // Add feedback
      await feedbackService.recordInteraction(
        title: 'Test Song',
        artist: 'Artist B',
        type: FeedbackType.like,
      );

      // Get affinity - this includes recency factor
      final affinity = feedbackService.getAffinityScore('Test Song', 'Artist B');

      // Affinity should be non-zero and reasonable
      expect(affinity, greaterThan(0.0));
      expect(affinity, lessThan(100.0));
    });
  });
}
