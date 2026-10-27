import 'package:flutter/material.dart';

import '../widgets/library_content.dart';
import '../widgets/middle_content_panel.dart';

class ExplorePage extends StatelessWidget {
  const ExplorePage({
    required this.config,
    required this.onNavigate,
    super.key,
  });

  final LibraryPageConfig config;
  final ValueChanged<String> onNavigate;

  static const _muted = Color(0xFF9292A5);
  static const _cyan = Color(0xFF83E8FF);
  static const _surface = Color(0xFF17171D);

  @override
  Widget build(BuildContext context) => MiddleContentPanel(
    section: 'Explorar',
    config: config,
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Descubre canciones, álbumes y artistas.',
          style: TextStyle(color: _muted, fontSize: 14),
        ),
        const SizedBox(height: 26),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth > 720 ? 3 : 1;
            final cardWidth = columns == 1
                ? constraints.maxWidth
                : (constraints.maxWidth - 28) / 3;
            return Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                _ExploreCard(
                  width: cardWidth,
                  icon: Icons.music_note_rounded,
                  title: 'Canciones',
                  subtitle: '${config.trackCount} canciones en tu biblioteca',
                  onTap: () => onNavigate('Tu música'),
                ),
                _ExploreCard(
                  width: cardWidth,
                  icon: Icons.album_rounded,
                  title: 'Álbumes',
                  subtitle: 'Explora tu colección por álbum',
                  onTap: () => onNavigate('Álbumes'),
                ),
                _ExploreCard(
                  width: cardWidth,
                  icon: Icons.people_alt_rounded,
                  title: 'Artistas',
                  subtitle: 'Encuentra música por artista',
                  onTap: () => onNavigate('Artistas'),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 30),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF29292F)),
          ),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome_rounded, color: _cyan, size: 24),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Música para descubrir',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'Encuentra algo nuevo en las listas y recomendaciones de Inicio.',
                      style: TextStyle(color: _muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              TextButton.icon(
                onPressed: () => onNavigate('Inicio'),
                icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                label: const Text('Ir a Inicio'),
                style: TextButton.styleFrom(foregroundColor: _cyan),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ExploreCard extends StatefulWidget {
  const _ExploreCard({
    required this.width,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final double width;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  State<_ExploreCard> createState() => _ExploreCardState();
}

class _ExploreCardState extends State<_ExploreCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: widget.width,
      height: 154,
      decoration: BoxDecoration(
        color: const Color(0xFF17171D),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _hovered ? const Color(0xFF83E8FF).withValues(alpha: .5) : const Color(0xFF29292F),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(widget.icon, color: const Color(0xFF83E8FF), size: 26),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 5),
                    Text(widget.subtitle, style: const TextStyle(color: Color(0xFF9292A5), fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
