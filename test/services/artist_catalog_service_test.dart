import 'package:flutter_test/flutter_test.dart';
import 'package:soundneed_pc/services/artist_catalog_service.dart';

void main() {
  group('ArtistCatalogService name matching', () {
    final service = ArtistCatalogService.instance;

    test('normalizes accented names consistently with catalog spelling', () {
      expect(
        service.normalizeArtistNameForTesting('Beyoncé'),
        service.normalizeArtistNameForTesting('Beyonce'),
      );
      expect(
        service.normalizeArtistNameForTesting('Zoë Saldaña'),
        service.normalizeArtistNameForTesting('Zoe Saldana'),
      );
    });

    test('ignores punctuation and casing in artist names', () {
      expect(
        service.normalizeArtistNameForTesting('AC/DC'),
        service.normalizeArtistNameForTesting('ac dc'),
      );
    });
  });
}
