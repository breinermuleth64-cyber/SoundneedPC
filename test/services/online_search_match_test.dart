import 'package:flutter_test/flutter_test.dart';
import 'package:soundneed_pc/services/online_search_service.dart';

void main() {
  group('Online search matching', () {
    test('selects the matching recording when channel name differs', () {
      final selected = OnlineSearchService.bestTrackMatch(
        title: 'Polos Opuestos Remix (Blessd Version)',
        artist: 'Kris R.',
        candidates: const [
          OnlineSearchResult(
            videoId: 'unrelate001',
            title: 'Polos Opuestos Remix (Blessd Version) - Official Audio',
            artist: 'Kris R - Topic',
            thumbnail: '',
            durationSeconds: 196,
          ),
          OnlineSearchResult(
            videoId: 'unrelate002',
            title: 'Polos Opuestos Remix (Blessd Version)',
            artist: 'Random Mix Channel',
            thumbnail: '',
            durationSeconds: 196,
          ),
        ],
      );

      expect(selected?.videoId, 'unrelate001');
    });

    test('rejects a title match with an unrelated artist and short clip', () {
      final selected = OnlineSearchService.bestTrackMatch(
        title: 'Polos Opuestos',
        artist: 'Kris R.',
        candidates: const [
          OnlineSearchResult(
            videoId: 'shortclip01',
            title: 'Polos Opuestos Remix',
            artist: 'Random Channel',
            thumbnail: '',
            durationSeconds: 20,
          ),
          OnlineSearchResult(
            videoId: 'wrongartst1',
            title: 'Polos Opuestos Remix',
            artist: 'Random Channel',
            thumbnail: '',
            durationSeconds: 190,
          ),
        ],
      );

      expect(selected, isNull);
    });
  });
}
