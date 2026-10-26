import 'package:flutter/material.dart';

import 'library_content.dart';

const _cyan = Color(0xFF83E8FF);
const _muted = Color(0xFF9292A5);

/// Recuadro central reutilizado por las secciones de la biblioteca.
class MiddleContentPanel extends StatelessWidget {
  const MiddleContentPanel({
    required this.section,
    required this.config,
    this.body,
    this.showHeader = true,
    super.key,
  });

  final String section;
  final LibraryPageConfig config;
  final Widget? body;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(0, 0, config.hasNowPlayingPanel ? 0 : 13, 0),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFF29292F)),
        ),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            ListView(
              padding: EdgeInsets.fromLTRB(
                config.compact ? 22 : 38,
                section == 'Buscar' ? 28 : (showHeader ? 70 : 34),
                config.compact ? 22 : 38,
                28,
              ),
              cacheExtent: 500,
              children: [
                if (showHeader && section != 'Buscar')
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              section == 'Inicio'
                                  ? 'TU ESPACIO MUSICAL'
                                  : 'SOUNDNEED  /  ${section.toUpperCase()}',
                              style: const TextStyle(
                                color: _cyan,
                                fontSize: 10,
                                letterSpacing: 1.8,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 9),
                            Text(
                              config.title,
                              style: TextStyle(
                                fontSize: config.compact ? 29 : 36,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -1.2,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '${config.trackCount} canciones en tu biblioteca',
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (section == 'Playlists')
                        Semantics(
                          label: 'Crear playlist',
                          child: TooltipVisibility(
                            visible: false,
                            child: IconButton(
                              tooltip: 'Crear playlist',
                              onPressed: config.onCreatePlaylist,
                              icon: const Icon(
                                Icons.add_circle_outline,
                                color: _cyan,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                if (showHeader && section != 'Buscar')
                  const SizedBox(height: 28),
                body ?? config.body,
                const SizedBox(height: 95),
              ],
            ),
            if (config.error != null)
              Positioned(
                left: 20,
                right: 20,
                bottom: 14,
                child: Material(
                  color: const Color(0xFF512C36),
                  borderRadius: BorderRadius.circular(12),
                  child: ListTile(
                    dense: true,
                    leading: const Icon(
                      Icons.error_outline,
                      color: Colors.white,
                    ),
                    title: Text(
                      config.error!,
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: IconButton(
                      onPressed: config.onDismissError,
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ),
              ),
            if (config.queueOpen)
              Positioned(
                top: 14,
                right: 16,
                bottom: 14,
                width: 310,
                child: config.queuePanel,
              ),
          ],
        ),
      ),
    );
  }
}
