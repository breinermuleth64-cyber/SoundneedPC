import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soundneed_pc/services/explore_feedback_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ExploreFeedbackService', () {
    setUp(() async {
      // Clear SharedPreferences before each test
      SharedPreferences.setMockInitialValues({});
      ExploreFeedbackService.instance.resetForTesting();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('soundneed_explore_feedback_v1');
    });

    test('records click interaction correctly', () async {
      final service = ExploreFeedbackService.instance;

      await service.recordInteraction(
        title: 'Test Song',
        artist: 'Test Artist',
        type: FeedbackType.click,
      );

      final affinity = service.getAffinityScore('Test Song', 'Test Artist');
      expect(affinity, greaterThan(0.0));
    });

    test('records like interaction and increases affinity', () async {
      final service = ExploreFeedbackService.instance;

      await service.recordInteraction(
        title: 'Test Song',
        artist: 'Test Artist',
        type: FeedbackType.like,
      );

      final affinity = service.getAffinityScore('Test Song', 'Test Artist');
      // Like should give 10 points, which after scaling should be significant
      expect(affinity, greaterThan(5.0));
    });

    test('records skip interaction and decreases affinity', () async {
      final service = ExploreFeedbackService.instance;

      await service.recordInteraction(
        title: 'Test Song',
        artist: 'Test Artist',
        type: FeedbackType.skip,
      );

      final affinity = service.getAffinityScore('Test Song', 'Test Artist');
      // Skip should give -3 points, so affinity should be low
      expect(affinity, lessThan(5.0));
    });

    test('records addToPlaylist interaction', () async {
      final service = ExploreFeedbackService.instance;

      await service.recordInteraction(
        title: 'Test Song',
        artist: 'Test Artist',
        type: FeedbackType.addToPlaylist,
      );

      final affinity = service.getAffinityScore('Test Song', 'Test Artist');
      // AddToPlaylist should give 8 points
      expect(affinity, greaterThan(5.0));
    });

    test('records complete interaction', () async {
      final service = ExploreFeedbackService.instance;

      await service.recordInteraction(
        title: 'Test Song',
        artist: 'Test Artist',
        type: FeedbackType.complete,
      );

      final affinity = service.getAffinityScore('Test Song', 'Test Artist');
      // Complete should give 5 points
      expect(affinity, greaterThan(3.0));
    });

    test('accumulates multiple interactions correctly', () async {
      final service = ExploreFeedbackService.instance;

      await service.recordInteraction(
        title: 'Test Song',
        artist: 'Test Artist',
        type: FeedbackType.like,
      );
      await service.recordInteraction(
        title: 'Test Song',
        artist: 'Test Artist',
        type: FeedbackType.addToPlaylist,
      );
      await service.recordInteraction(
        title: 'Test Song',
        artist: 'Test Artist',
        type: FeedbackType.complete,
      );

      final affinity = service.getAffinityScore('Test Song', 'Test Artist');
      // Like (10) + AddToPlaylist (8) + Complete (5) = 23 before scaling
      expect(affinity, greaterThan(15.0));
    });

    test('hides track after 3 skips', () async {
      final service = ExploreFeedbackService.instance;

      await service.recordInteraction(
        title: 'Test Song',
        artist: 'Test Artist',
        type: FeedbackType.skip,
      );
      await service.recordInteraction(
        title: 'Test Song',
        artist: 'Test Artist',
        type: FeedbackType.skip,
      );
      await service.recordInteraction(
        title: 'Test Song',
        artist: 'Test Artist',
        type: FeedbackType.skip,
      );

      final shouldShow = service.shouldShowAgain('Test Song', 'Test Artist');
      expect(shouldShow, false);
    });

    test('shows track with fewer than 3 skips', () async {
      final service = ExploreFeedbackService.instance;

      await service.recordInteraction(
        title: 'Test Song',
        artist: 'Test Artist',
        type: FeedbackType.skip,
      );
      await service.recordInteraction(
        title: 'Test Song',
        artist: 'Test Artist',
        type: FeedbackType.skip,
      );

      final shouldShow = service.shouldShowAgain('Test Song', 'Test Artist');
      expect(shouldShow, true);
    });

    test('normalizes artist names correctly', () async {
      final service = ExploreFeedbackService.instance;

      await service.recordInteraction(
        title: 'Test Song',
        artist: 'Álvaro',
        type: FeedbackType.like,
      );

      // Should find the same record with normalized name
      final affinity = service.getAffinityScore('Test Song', 'alvaro');
      expect(affinity, greaterThan(0.0));
    });

    test('returns 0 affinity for unknown track', () async {
      final service = ExploreFeedbackService.instance;

      final affinity = service.getAffinityScore('Unknown Song', 'Unknown Artist');
      expect(affinity, 0.0);
    });

    test('should show unknown track', () async {
      final service = ExploreFeedbackService.instance;

      final shouldShow = service.shouldShowAgain('Unknown Song', 'Unknown Artist');
      expect(shouldShow, true);
    });

    test('listens to duration bonus for substantial listens', () async {
      final service = ExploreFeedbackService.instance;

      await service.recordInteraction(
        title: 'Test Song',
        artist: 'Test Artist',
        type: FeedbackType.click,
        listenDuration: const Duration(seconds: 35),
      );

      final affinity = service.getAffinityScore('Test Song', 'Test Artist');
      // Should have duration bonus
      expect(affinity, greaterThan(1.0));
    });

    test('different tracks are independent', () async {
      final service = ExploreFeedbackService.instance;

      await service.recordInteraction(
        title: 'Song A',
        artist: 'Artist A',
        type: FeedbackType.like,
      );

      final affinityA = service.getAffinityScore('Song A', 'Artist A');
      final affinityB = service.getAffinityScore('Song B', 'Artist B');

      expect(affinityA, greaterThan(0.0));
      expect(affinityB, 0.0);
    });

    test('artist affinity aggregates explicit likes and skips', () async {
      final service = ExploreFeedbackService.instance;

      await service.recordInteraction(
        title: 'Loved song',
        artist: 'Artist A',
        type: FeedbackType.like,
      );
      final likedAffinity = service.getArtistAffinityScore('Artist A');
      await service.recordInteraction(
        title: 'Skipped song',
        artist: 'Artist A',
        type: FeedbackType.skip,
      );

      expect(likedAffinity, greaterThan(0));
      expect(service.getArtistAffinityScore('Artist A'), lessThan(likedAffinity));
      expect(service.getArtistAffinityScore('Artist B'), 0);
    });
  });
}
