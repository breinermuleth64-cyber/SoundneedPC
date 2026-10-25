import '../models/track.dart';

/// Shared playlist filtering and ordering rules used by both collection views
/// and the add-song picker.
class PlaylistSearchService {
  const PlaylistSearchService._();

  static String normalize(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ü', 'u')
      .replaceAll('ñ', 'n');

  static bool matchesTrack(Track track, String query) {
    final normalizedQuery = normalize(query);
    if (normalizedQuery.isEmpty) return true;
    return normalize(track.title).contains(normalizedQuery) ||
        normalize(track.artist).contains(normalizedQuery) ||
        normalize(track.album).contains(normalizedQuery);
  }

  static bool matchesPlaylist(String name, List<Track> tracks, String query) {
    final normalizedQuery = normalize(query);
    if (normalizedQuery.isEmpty || normalize(name).contains(normalizedQuery)) {
      return true;
    }
    return tracks.any((track) => matchesTrack(track, normalizedQuery));
  }

  static List<Track> filterTracks(Iterable<Track> tracks, String query) =>
      tracks.where((track) => matchesTrack(track, query)).toList();

  static List<Track> sortTracks(Iterable<Track> tracks, String sort) {
    final result = tracks.toList();
    switch (sort) {
      case 'title':
        result.sort((a, b) => normalize(a.title).compareTo(normalize(b.title)));
        break;
      case 'artist':
        result.sort(
          (a, b) => normalize(a.artist).compareTo(normalize(b.artist)),
        );
        break;
      case 'album':
        result.sort((a, b) => normalize(a.album).compareTo(normalize(b.album)));
        break;
    }
    return result;
  }
}
