import 'package:flutter/material.dart';

import '../models/track.dart';
import '../services/home_discovery_service.dart';
import '../widgets/library_content.dart';
import '../widgets/media_collection_browser.dart';
import '../widgets/middle_content_panel.dart';

class ArtistsPage extends StatelessWidget {
  const ArtistsPage({
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
    this.featuredArtists = const [],
    this.worldArtists = const [],
    this.trendingTracks = const [],
    this.preferredArtists = const [],
    this.recentlyHeardTrackKeys = const {},
    this.onPlayArtistStation,
    this.onPlayChartTrack,
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
  final List<String> featuredArtists;
  final List<HomeChartArtist> worldArtists;
  final List<HomeChartTrack> trendingTracks;
  final List<String> preferredArtists;
  final Set<String> recentlyHeardTrackKeys;
  final ValueChanged<String>? onPlayArtistStation;
  final PlayChartTrack? onPlayChartTrack;

  @override
  Widget build(BuildContext context) => MiddleContentPanel(
    section: 'Artistas',
    config: config,
    body: loading
        ? config.body
        : MediaCollectionBrowser(
            tracks: tracks,
            showArtists: true,
            compact: compact,
            currentTrackPath: currentTrackPath,
            isPlaying: isPlaying,
            favoritePaths: favoritePaths,
            onToggleFavorite: onToggleFavorite,
            onAddToPlaylist: onAddToPlaylist,
            featuredArtists: featuredArtists,
            worldArtists: worldArtists,
            trendingTracks: trendingTracks,
            preferredArtists: preferredArtists,
            recentlyHeardTrackKeys: recentlyHeardTrackKeys,
            onPlayTracks: onPlayTracks,
            onPlayArtistStation: onPlayArtistStation,
            onPlayChartTrack: onPlayChartTrack,
          ),
  );
}
