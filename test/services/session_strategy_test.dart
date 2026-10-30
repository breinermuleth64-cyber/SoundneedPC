import 'package:flutter_test/flutter_test.dart';
import 'package:soundneed_pc/services/explore_discovery_service.dart';

void main() {
  group('Explore session strategies', () {
    final candidates = <ExploreRecommendation>[
      _item('own', 'Known Song', 'Beyoncé', 'Beyoncé', fromCatalog: true),
      _item('similar', 'Related Song', 'New Neighbor', 'Beyoncé', fromCatalog: true),
      _item('connected', 'Discovery Song', 'Fresh Artist', 'History Artist', fromCatalog: true),
      _item('known', 'Known Neighbor Song', 'Known Artist', 'History Artist', fromCatalog: true),
      _item('unverified', 'Search Result', 'Random Channel', 'Beyoncé', fromCatalog: false),
    ];

    test('own artist strategy returns songs by the seed artist', () {
      final songs = ExploreSessionStrategySelector.ownArtistSongs(candidates);

      expect(songs.map((item) => item.id), ['own']);
    });

    test('similar strategy uses catalog related artists from favorite seeds', () {
      final songs = ExploreSessionStrategySelector.relatedToSeeds(
        candidates,
        seedArtists: ['Beyonce'],
      );

      expect(songs.map((item) => item.id), ['similar']);
    });

    test('discovery strategy favors new artists from listening seeds', () {
      final songs = ExploreSessionStrategySelector.newRelatedArtists(
        candidates,
        seedArtists: ['History Artist'],
        listenedArtists: ['History Artist', 'Known Artist'],
      );

      expect(songs.map((item) => item.id), ['connected']);
    });

    test('empty catalog candidates produce empty sessions safely', () {
      expect(
        ExploreSessionStrategySelector.relatedToSeeds(
          const [],
          seedArtists: ['Beyoncé'],
        ),
        isEmpty,
      );
      expect(
        ExploreSessionStrategySelector.newRelatedArtists(
          const [],
          seedArtists: ['Beyoncé'],
          listenedArtists: const [],
        ),
        isEmpty,
      );
    });

    test('favorite artist session excludes related and unverified artists', () {
      final songs = ExploreSessionStrategySelector.favoriteArtistSongs(
        candidates,
        favoriteArtists: ['Beyoncé'],
      );
      expect(songs.map((item) => item.id), ['own']);
    });

    test('popularity and deep cut sessions use real fan counts', () {
      final catalog = [
        _item('popular', 'Popular Song', 'Popular Artist', 'Beyoncé',
            fromCatalog: true, fanCount: 900000),
        _item('deep', 'Deep Song', 'Deep Artist', 'Beyoncé',
            fromCatalog: true, fanCount: 1200),
        _item('unknown', 'Unknown Song', 'Unknown Artist', 'Beyoncé',
            fromCatalog: true),
      ];

      expect(
        ExploreSessionStrategySelector.popularRelatedArtists(catalog)
            .map((item) => item.id),
        ['popular', 'deep'],
      );
      expect(
        ExploreSessionStrategySelector.deepCutArtists(catalog)
            .map((item) => item.id),
        ['deep', 'popular'],
      );
    });
  });
}

ExploreRecommendation _item(
  String id,
  String title,
  String artist,
  String seedArtist, {
  required bool fromCatalog,
  int? fanCount,
}) => ExploreRecommendation(
  id: id,
  title: title,
  artist: artist,
  artworkUrl: '',
  seedArtist: seedArtist,
  score: 50,
  reason: 'test',
  fromCatalog: fromCatalog,
  artistFanCount: fanCount,
);
