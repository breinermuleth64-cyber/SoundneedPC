import 'package:flutter/material.dart';

import '../models/track.dart';
import '../widgets/library_content.dart';
import '../widgets/media_collection_browser.dart';
import '../widgets/middle_content_panel.dart';

class AlbumsPage extends StatelessWidget {
  const AlbumsPage({
    required this.config,
    required this.tracks,
    required this.loading,
    required this.compact,
    required this.currentTrackPath,
    required this.isPlaying,
    required this.favoritePaths,
    required this.onToggleFavorite,
    required this.onAddToPlaylist,
    required this.onPlayTracks,
    super.key,
  });

  final LibraryPageConfig config;
  final List<Track> tracks;
  final bool loading;
  final bool compact;
  final String? currentTrackPath;
  final bool isPlaying;
  final Set<String> favoritePaths;
  final ValueChanged<Track> onToggleFavorite;
  final ValueChanged<Track> onAddToPlaylist;
  final PlayCollectionTracks onPlayTracks;

  @override
  Widget build(BuildContext context) => MiddleContentPanel(
    section: 'Álbumes',
    config: config,
    body: loading
        ? config.body
        : MediaCollectionBrowser(
            tracks: tracks,
            showArtists: false,
            compact: compact,
            currentTrackPath: currentTrackPath,
            isPlaying: isPlaying,
            favoritePaths: favoritePaths,
            onToggleFavorite: onToggleFavorite,
            onAddToPlaylist: onAddToPlaylist,
            onPlayTracks: onPlayTracks,
          ),
  );
}
