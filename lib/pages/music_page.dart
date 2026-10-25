import 'package:flutter/material.dart';

import '../widgets/library_content.dart';
import '../widgets/middle_content_panel.dart';

const _cyan = Color(0xFF83E8FF);

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
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: EdgeInsets.all(config.compact ? 22 : 30),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF183B46), Color(0xFF17232D), Color(0xFF171722)],
      ),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: _cyan.withValues(alpha: .16)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'TU ESPACIO, TU SONIDO',
              style: TextStyle(
                color: _cyan,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.8,
              ),
              ),
              const SizedBox(height: 10),
              Text(
                'Tu música,\na tu manera.',
                style: TextStyle(
                  fontSize: config.compact ? 27 : 34,
                  height: 1.08,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 9),
              Text(
                '${config.trackCount} canciones en tu biblioteca',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
        if (!config.compact) ...[
          const SizedBox(width: 18),
          Container(
            width: 78,
            height: 78,
            decoration: BoxDecoration(
              color: _cyan.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(Icons.graphic_eq_rounded, color: _cyan, size: 42),
          ),
        ],
      ],
    ),
  );
}
