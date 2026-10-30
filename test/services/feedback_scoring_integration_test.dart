import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soundneed_pc/services/explore_feedback_service.dart';
import 'package:soundneed_pc/services/listening_history_service.dart';
import 'package:soundneed_pc/services/recommendation_scoring_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Feedback + Scoring Integration', () {
    late RecommendationScoringService scoringService;
    late ExploreFeedbackService feedbackService;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      ExploreFeedbackService.instance.resetForTesting();
      scoringService = RecommendationScoringService.instance;
      feedbackService = ExploreFeedbackService.instance;
    });

    test('feedback increases affinity in scoring', () async {
      final history = ListeningHistoryProfile(
        preferredArtists: ['Artist A'],
        recentTracks: [],
        recentTrackKeys: [],
        trackPlayCounts: {},
      );

      // First, score without feedback
      final scoreWithoutFeedback = scoringService.calculateScore(
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

      // Add positive feedback
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

      // Score should be higher with feedback
      expect(scoreWithFeedback, greaterThan(scoreWithoutFeedback));
    });

    test('feedback does not duplicate favorite signal', () async {
      final history = ListeningHistoryProfile(
        preferredArtists: ['Artist B'], // Artist B is already a favorite
        recentTracks: [],
        recentTrackKeys: [],
        trackPlayCounts: {},
      );

      // Score with favorite artist (without explicit feedback)
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

      // Feedback should add some boost, but not double-count
      // The increase should be reasonable (feedback is scaled by 0.15)
      final increase = scoreWithFeedback - scoreFavoriteOnly;
      expect(increase, lessThan(20.0)); // Should not be a huge jump
      expect(increase, greaterThan(0.0)); // But should still increase
    });

    test('negative feedback decreases score', () async {
      final history = ListeningHistoryProfile(
        preferredArtists: [],
        searchedArtists: [],
        recentTracks: [],
        recentTrackKeys: [],
        trackPlayCounts: {},
      );

      // Score without feedback
      final scoreWithoutFeedback = scoringService.calculateScore(
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

      // Score should be lower with negative feedback
      expect(scoreWithFeedback, lessThan(scoreWithoutFeedback));
    });

    test('multiple feedback interactions accumulate correctly', () async {
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

      // Score with accumulated feedback
      final finalScore = scoringService.calculateScore(
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

      // Should be significantly higher
      expect(finalScore, greaterThan(baselineScore + 5.0));
    });

    test('feedback affects only the specific track', () async {
      final history = ListeningHistoryProfile(
        preferredArtists: [],
        searchedArtists: [],
        recentTracks: [],
        recentTrackKeys: [],
        trackPlayCounts: {},
      );

      // Add feedback to Track A
      await feedbackService.recordInteraction(
        title: 'Song A',
        artist: 'Artist B',
        type: FeedbackType.like,
      );

      // Score Track A (with feedback)
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

      // Score Track B (no feedback)
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

      // Track A should score higher due to feedback
      expect(scoreA, greaterThan(scoreB));
    });

    test('feedback is normalized correctly with special characters', () async {
      final history = ListeningHistoryProfile(
        preferredArtists: [],
        searchedArtists: [],
        recentTracks: [],
        recentTrackKeys: [],
        trackPlayCounts: {},
      );

      // Add feedback with special characters
      await feedbackService.recordInteraction(
        title: 'Canción',
        artist: 'Álvaro',
        type: FeedbackType.like,
      );

      // Score with normalized name
      final score = scoringService.calculateScore(
        seedArtist: 'Artist A',
        seedIndex: 0,
        artistFanCount: 1000000,
        hasCompleteMetadata: true,
        title: 'Canción',
        artist: 'alvaro', // Normalized
        history: history,
        heardTracks: {},
        artistCounts: {},
      );

      // Should have feedback boost
      expect(score, greaterThan(70.0)); // Base affinity (100) + bonus
    });
  });
}
