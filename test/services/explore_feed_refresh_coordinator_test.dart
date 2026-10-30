import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:soundneed_pc/services/explore_discovery_service.dart';

void main() {
  group('ExploreFeedRefreshCoordinator', () {
    late ExploreFeedRefreshCoordinator coordinator;

    setUp(() => coordinator = ExploreFeedRefreshCoordinator());

    test('loads on first entry and reuses a fresh successful feed', () async {
      var calls = 0;
      Future<void> reload() async {
        calls++;
      }

      await coordinator.load(
        force: false,
        hasSuccessfulLoad: false,
        updatedAt: null,
        reload: reload,
      );
      expect(calls, 1);

      final now = DateTime(2026, 10, 29, 12);
      expect(
        coordinator.isFresh(
          hasSuccessfulLoad: true,
          updatedAt: now.subtract(const Duration(minutes: 29)),
          now: now,
        ),
        isTrue,
      );
      await coordinator.load(
        force: false,
        hasSuccessfulLoad: true,
        updatedAt: now.subtract(const Duration(minutes: 29)),
        reload: reload,
        now: now,
      );
      expect(calls, 1);
    });

    test('reloads an expired or explicitly stale feed', () async {
      var calls = 0;
      Future<void> reload() async {
        calls++;
      }
      final now = DateTime(2026, 10, 29, 12);

      await coordinator.load(
        force: false,
        hasSuccessfulLoad: true,
        updatedAt: now.subtract(const Duration(minutes: 31)),
        reload: reload,
        now: now,
      );
      await coordinator.load(
        force: false,
        hasSuccessfulLoad: true,
        updatedAt: now,
        isStale: true,
        reload: reload,
        now: now,
      );

      expect(calls, 2);
    });

    test('manual force reloads even a fresh feed', () async {
      var calls = 0;
      final now = DateTime(2026, 10, 29, 12);

      await coordinator.load(
        force: true,
        hasSuccessfulLoad: true,
        updatedAt: now,
        reload: () async {
          calls++;
        },
        now: now,
      );

      expect(calls, 1);
    });

    test('coalesces concurrent normal loads into one operation', () async {
      final release = Completer<void>();
      var calls = 0;
      Future<void> reload() async {
        calls++;
        await release.future;
      }

      final first = coordinator.load(
        force: false,
        hasSuccessfulLoad: false,
        updatedAt: null,
        reload: reload,
      );
      final second = coordinator.load(
        force: false,
        hasSuccessfulLoad: false,
        updatedAt: null,
        reload: reload,
      );
      expect(calls, 1);

      release.complete();
      await Future.wait([first, second]);
      expect(calls, 1);
    });

    test('queues at most one forced refresh behind an active load', () async {
      final releaseFirst = Completer<void>();
      var normalCalls = 0;
      var forcedCalls = 0;
      Future<void> normalReload() async {
        normalCalls++;
        await releaseFirst.future;
      }
      Future<void> forcedReload() async {
        forcedCalls++;
      }

      final first = coordinator.load(
        force: false,
        hasSuccessfulLoad: false,
        updatedAt: null,
        reload: normalReload,
      );
      final forcedOne = coordinator.load(
        force: true,
        hasSuccessfulLoad: false,
        updatedAt: null,
        reload: forcedReload,
      );
      final forcedTwo = coordinator.load(
        force: true,
        hasSuccessfulLoad: false,
        updatedAt: null,
        reload: forcedReload,
      );
      expect(normalCalls, 1);
      expect(forcedCalls, 0);

      releaseFirst.complete();
      await Future.wait([first, forcedOne, forcedTwo]);
      expect(normalCalls, 1);
      expect(forcedCalls, 1);
    });

    test('a force request reuses an already forced load', () async {
      final release = Completer<void>();
      var calls = 0;
      Future<void> forcedReload() async {
        calls++;
        await release.future;
      }

      final first = coordinator.load(
        force: true,
        hasSuccessfulLoad: true,
        updatedAt: DateTime(2026, 10, 29),
        reload: forcedReload,
      );
      final second = coordinator.load(
        force: true,
        hasSuccessfulLoad: true,
        updatedAt: DateTime(2026, 10, 29),
        reload: forcedReload,
      );
      expect(calls, 1);

      release.complete();
      await Future.wait([first, second]);
      expect(calls, 1);
    });

    test('releases the gate after failure so a later load can succeed', () async {
      await expectLater(
        coordinator.load(
          force: false,
          hasSuccessfulLoad: false,
          updatedAt: null,
          reload: () async => throw StateError('network failed'),
        ),
        throwsA(isA<StateError>()),
      );

      var calls = 0;
      await coordinator.load(
        force: false,
        hasSuccessfulLoad: false,
        updatedAt: null,
        reload: () async {
          calls++;
        },
      );
      expect(calls, 1);
    });
  });
}
