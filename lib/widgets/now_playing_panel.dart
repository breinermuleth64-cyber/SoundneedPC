import 'package:flutter/material.dart';

import 'soundneed_svg_icon.dart';

class NowPlayingPanel extends StatelessWidget {
  const NowPlayingPanel({
    required this.artwork,
    required this.artworkSize,
    required this.onAudioTap,
    required this.onVideoTap,
    required this.audioPlaying,
    required this.onCollapse,
    required this.onOpenExplore,
    this.audioActive = true,
    this.videoEnabled = true,
    this.videoActive = false,
    this.videoLoading = false,
    super.key,
  });

  final Widget artwork;
  final double artworkSize;
  final VoidCallback onAudioTap;
  final VoidCallback? onVideoTap;
  final bool audioPlaying;
  final VoidCallback onCollapse;
  final VoidCallback onOpenExplore;
  final bool audioActive;
  final bool videoEnabled;
  final bool videoActive;
  final bool videoLoading;

  static const _muted = Color(0xFF9292A5);

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF29292F)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Ocultar vista previa',
                  visualDensity: VisualDensity.compact,
                  splashRadius: 18,
                  onPressed: onCollapse,
                  icon: const SoundNeedSvgIcon(
                    'close-pane',
                    size: 24,
                    color: _muted,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Abrir en Explorar',
                  visualDensity: VisualDensity.compact,
                  splashRadius: 18,
                  onPressed: onOpenExplore,
                  icon: Icon(
                    Icons.open_in_full_rounded,
                    color: _muted,
                    size: 20,
                  ),
                ),
                PopupMenuButton<_PreviewPanelAction>(
                  tooltip: 'Opciones',
                  icon: const Icon(Icons.more_horiz_rounded, color: _muted),
                  onSelected: (action) {
                    switch (action) {
                      case _PreviewPanelAction.toggleMode:
                        onVideoTap?.call();
                        break;
                      case _PreviewPanelAction.hide:
                        onCollapse();
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: _PreviewPanelAction.toggleMode,
                      enabled: videoEnabled && (videoActive || !videoLoading),
                      child: Text(
                        videoActive ? 'Volver al audio' : 'Ver video',
                      ),
                    ),
                    const PopupMenuItem(
                      value: _PreviewPanelAction.hide,
                      child: Text('Ocultar vista previa'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: SizedBox(
              width: artworkSize,
              height: artworkSize,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  artwork,
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: const Color(0xE51A1113),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: .12),
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x44000000),
                            blurRadius: 14,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _CoverModeButton(
                            tooltip: audioActive
                                ? (audioPlaying
                                      ? 'Audio activo'
                                      : 'Audio pausado')
                                : 'Cambiar a audio',
                            icon: audioActive && audioPlaying
                                ? Icons.graphic_eq_rounded
                                : Icons.equalizer_rounded,
                            onTap: onAudioTap,
                            active: audioActive,
                          ),
                          const SizedBox(width: 2),
                          _CoverModeButton(
                            tooltip: videoLoading
                                ? 'Cargando video'
                                : videoActive
                                ? 'Volver al audio'
                                : 'Ver video',
                            icon: Icons.smart_display_rounded,
                            onTap: videoEnabled && !videoLoading
                                ? onVideoTap
                                : null,
                            video: true,
                            active: videoActive,
                            loading: videoLoading,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF650B0B),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(32),
                ),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Muestra de la letra',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'No, ¿pero sabe qué?',
                    style: TextStyle(
                      color: Color(0xFFFFC5BC),
                      fontSize: 24,
                      height: 1.18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 18),
                  Text(
                    'Aquí aparecerá la letra de la canción.',
                    style: TextStyle(
                      color: Color(0xCCFFFFFF),
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _PreviewPanelAction { toggleMode, hide }

class _CoverModeButton extends StatelessWidget {
  const _CoverModeButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.video = false,
    this.active = false,
    this.loading = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onTap;
  final bool video;
  final bool active;
  final bool loading;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: video
          ? onTap == null
                ? const Color(0xFF514447)
                : active
                ? const Color(0xFFB82026)
                : const Color(0xFF7F171C)
          : active
          ? const Color(0xFF6C2429)
          : const Color(0xFF351719),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 35,
          height: 35,
          child: loading
              ? const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Icon(
                  icon,
                  color: onTap == null && !active
                      ? Colors.white54
                      : Colors.white,
                  size: video ? 20 : 17,
                ),
        ),
      ),
    ),
  );
}
