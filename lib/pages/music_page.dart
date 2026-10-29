import 'package:flutter/material.dart';

import '../widgets/collection_hero.dart';
import '../widgets/library_content.dart';
import '../widgets/middle_content_panel.dart';

class MusicPage extends StatelessWidget {
  const MusicPage({required this.config, super.key});

  final LibraryPageConfig config;

  @override
  Widget build(BuildContext context) => MiddleContentPanel(
    section: 'Tu música',
    config: config,
    showHeader: false,
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CollectionHero(config: config),
        const SizedBox(height: 32),
        config.body,
      ],
    ),
  );
}

class _CollectionHero extends StatelessWidget {
  const _CollectionHero({required this.config});

  final LibraryPageConfig config;

  @override
  Widget build(BuildContext context) => CollectionHero(
    eyebrow: 'TU BIBLIOTECA',
    title: 'Tu música',
    description: 'Tus canciones locales, reunidas en un solo lugar.',
    icon: Icons.library_music_rounded,
    count: config.trackCount,
    countLabel: config.trackCount == 1 ? 'canción' : 'canciones',
    compact: config.compact,
    accent: config.accentColor,
    secondaryAccent: config.secondaryColor,
  );
}
