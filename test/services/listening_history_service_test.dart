import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soundneed_pc/services/listening_history_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ListeningHistoryService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('loads records in the existing persisted format', () async {
      final playedAt = DateTime.now().subtract(const Duration(days: 2));
      SharedPreferences.setMockInitialValues({
        'soundneed_pc_listening_history_v1': jsonEncode([
          {
            'title': 'Canción guardada',
            'artist': 'Artista guardado',
            'playedAt': playedAt.toIso8601String(),
          },
        ]),
      });

      final profile = await ListeningHistoryService.instance.load();

      expect(profile.preferredArtists, ['Artista guardado']);
      expect(profile.recentTracks.single.title, 'Canción guardada');
      expect(profile.trackPlayCounts.values.single, 1);
    });

    test(
      'persists a recorded listen so it is available to later loads',
      () async {
        final service = ListeningHistoryService.instance;

        await service.record(title: 'Nueva canción', artist: 'Nuevo artista');
        final profile = await service.load();

        expect(profile.preferredArtists, ['Nuevo artista']);
        expect(
          profile.recentTrackKeys,
          contains('nueva cancion|nuevo artista'),
        );
      },
    );
  });
}
