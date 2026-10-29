import 'package:flutter/material.dart';

import '../services/explore_discovery_service.dart';
import '../widgets/library_content.dart';
import '../widgets/middle_content_panel.dart';

class ExploreOnlinePage extends StatelessWidget {
  const ExploreOnlinePage({
    required this.config,
    required this.recommendations,
    required this.seedArtists,
    required this.loading,
    required this.error,
    required this.onRefresh,
    required this.onPlay,
    super.key,
  });

  final LibraryPageConfig config;
  final List<ExploreRecommendation> recommendations;
  final List<String> seedArtists;
  final bool loading;
  final String? error;
  final VoidCallback onRefresh;
  final ValueChanged<ExploreRecommendation> onPlay;

  static const _accent = Color(0xFF83E8FF);

  @override
  Widget build(BuildContext context) => MiddleContentPanel(
    section: 'Explorar',
    config: config,
    showHeader: false,
    body: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 700;
        final featured = recommendations.isEmpty ? null : recommendations.first;
        final groups = <String, List<ExploreRecommendation>>{};
        for (final recommendation in recommendations.skip(1)) {
          groups.putIfAbsent(recommendation.seedArtist, () => []).add(recommendation);
        }
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(compact ? 20 : 34, 30, compact ? 20 : 34, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('TU RADAR MUSICAL', style: TextStyle(color: _accent, fontSize: 11, letterSpacing: 2, fontWeight: FontWeight.w700)),
                        SizedBox(height: 8),
                        Text('Descubre', style: TextStyle(fontSize: 40, height: 1, letterSpacing: -1.4, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Actualizar recomendaciones',
                    onPressed: loading ? null : onRefresh,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                seedArtists.isEmpty
                    ? 'Música online seleccionada para abrir nuevos caminos.'
                    : 'Artistas relacionados con ${seedArtists.take(3).join(', ')}',
                style: const TextStyle(color: Colors.white60, fontSize: 13),
              ),
              const SizedBox(height: 24),
              if (loading && featured == null)
                const _DiscoveryMessage(
                  icon: Icons.graphic_eq_rounded,
                  title: 'Buscando sonidos para ti',
                  detail: 'Estamos conectando tus gustos con artistas relacionados.',
                  loading: true,
                )
              else if (error != null && featured == null)
                _DiscoveryMessage(
                  icon: Icons.cloud_off_rounded,
                  title: 'No se pudieron cargar las recomendaciones',
                  detail: error!,
                  onRetry: onRefresh,
                )
              else if (featured == null && seedArtists.isNotEmpty)
                _DiscoveryMessage(
                  icon: Icons.search_off_rounded,
                  title: 'Aún no encontramos canciones relacionadas',
                  detail: 'Intenta actualizar para buscar otra selección basada en tu historial.',
                  onRetry: onRefresh,
                )
              else if (featured == null)
                const _DiscoveryMessage(
                  icon: Icons.headphones_rounded,
                  title: 'Escucha un poco y vuelve a Explorar',
                  detail: 'Cuando tengas reproducciones online, buscaremos artistas relacionados y canciones nuevas para ti.',
                )
              else ...[
                _FeaturedRecommendation(
                  item: featured,
                  compact: compact,
                  onTap: () => onPlay(featured),
                ),
                const SizedBox(height: 30),
                _RecommendationRow(
                  title: 'Te puede gustar',
                  subtitle: 'Nuevas canciones afines a lo que escuchas',
                  items: recommendations,
                  onPlay: onPlay,
                ),
                for (final entry in groups.entries) ...[
                  const SizedBox(height: 30),
                  _RecommendationRow(
                    title: 'Relacionado con ${entry.key}',
                    subtitle: 'Artistas conectados por similitud musical',
                    items: entry.value,
                    onPlay: onPlay,
                  ),
                ],
              ],
              if (error != null && featured != null) ...[
                const SizedBox(height: 14),
                Text(error!, style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ],
          ),
        );
      },
    ),
  );
}

class _FeaturedRecommendation extends StatelessWidget {
  const _FeaturedRecommendation({required this.item, required this.compact, required this.onTap});
  final ExploreRecommendation item;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFF171A20),
    borderRadius: BorderRadius.circular(20),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: SizedBox(
        height: compact ? 215 : 260,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _NetworkArtwork(url: item.artworkUrl),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerRight,
                  end: Alignment.centerLeft,
                  colors: [Colors.black.withValues(alpha: .18), Colors.black.withValues(alpha: .92)],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(compact ? 20 : 28),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('DESCUBRIMIENTO PARA TI', style: TextStyle(color: ExploreOnlinePage._accent, fontSize: 10, letterSpacing: 1.8, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: compact ? 24 : 32, fontWeight: FontWeight.w800, height: 1.05)),
                    const SizedBox(height: 5),
                    Text(item.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 15)),
                    const SizedBox(height: 14),
                    Row(children: [const Icon(Icons.play_circle_fill_rounded, color: Color(0xFF83E8FF), size: 28), const SizedBox(width: 9), Text(item.reason, style: const TextStyle(color: Colors.white70, fontSize: 12))]),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _RecommendationRow extends StatelessWidget {
  const _RecommendationRow({required this.title, required this.subtitle, required this.items, required this.onPlay});
  final String title;
  final String subtitle;
  final List<ExploreRecommendation> items;
  final ValueChanged<ExploreRecommendation> onPlay;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
      const SizedBox(height: 3),
      Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12)),
      const SizedBox(height: 14),
      SizedBox(
        height: 188,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (context, index) {
            final item = items[index];
            return SizedBox(
              width: 142,
              child: InkWell(
                onTap: () => onPlay(item),
                borderRadius: BorderRadius.circular(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(width: 142, child: _NetworkArtwork(url: item.artworkUrl)))),
                    const SizedBox(height: 8),
                    Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    Text(item.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60, fontSize: 11)),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ],
  );
}

class _DiscoveryMessage extends StatelessWidget {
  const _DiscoveryMessage({required this.icon, required this.title, required this.detail, this.loading = false, this.onRetry});
  final IconData icon;
  final String title;
  final String detail;
  final bool loading;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(26),
    decoration: BoxDecoration(color: const Color(0xFF171A20), borderRadius: BorderRadius.circular(18)),
    child: Row(
      children: [
        if (loading) const SizedBox(width: 34, height: 34, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF83E8FF))) else Icon(icon, size: 32, color: const Color(0xFF83E8FF)),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)), const SizedBox(height: 5), Text(detail, style: const TextStyle(color: Colors.white60, fontSize: 13))])),
        if (onRetry != null) IconButton(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded)),
      ],
    ),
  );
}

class _NetworkArtwork extends StatelessWidget {
  const _NetworkArtwork({required this.url});
  final String url;
  @override
  Widget build(BuildContext context) => url.isEmpty
      ? _placeholder()
      : Image.network(url, fit: BoxFit.cover, errorBuilder: (_, _, _) => _placeholder());

  Widget _placeholder() => Container(color: const Color(0xFF20232B), alignment: Alignment.center, child: const Icon(Icons.music_note_rounded, color: Colors.white54, size: 34));
}

