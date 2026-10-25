import 'package:flutter/material.dart';

class LibraryPageConfig {
  const LibraryPageConfig({
    required this.compact,
    required this.hasNowPlayingPanel,
    required this.title,
    this.playlistView,
    required this.trackCount,
    required this.onCreatePlaylist,
    required this.playlistNames,
    required this.playlistCounts,
    required this.onOpenPlaylist,
    required this.onRenamePlaylist,
    required this.onDeletePlaylist,
    required this.body,
    required this.error,
    required this.onDismissError,
    required this.queueOpen,
    required this.queuePanel,
  });

  final bool compact;
  final bool hasNowPlayingPanel;
  final String title;
  final String? playlistView;
  final int trackCount;
  final VoidCallback onCreatePlaylist;
  final List<String> playlistNames;
  final Map<String, int> playlistCounts;
  final ValueChanged<String> onOpenPlaylist;
  final ValueChanged<String> onRenamePlaylist;
  final ValueChanged<String> onDeletePlaylist;
  final Widget body;
  final String? error;
  final VoidCallback onDismissError;
  final bool queueOpen;
  final Widget queuePanel;
}
