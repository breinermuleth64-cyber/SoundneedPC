import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart' show kPrimaryButton;
import 'package:flutter/material.dart';

import 'soundneed_svg_icon.dart';

const Color _text = Color(0xFFF4F4F5);
const Color _iconMuted = Color(0xFF85858F);
const Color _red = Color(0xFFEF4444);

class SoundNeedTopBar extends StatefulWidget {
  const SoundNeedTopBar({
    super.key,
    required this.compact,
    required this.section,
    required this.query,
    required this.searchController,
    required this.onSearchChanged,
    required this.scanning,
    required this.onlineMode,
    required this.maximized,
    required this.backgroundColor,
    required this.surfaceColor,
    required this.accentColor,
    required this.mutedColor,
    required this.onHome,
    required this.onSettings,
    required this.onNotifications,
    required this.onExplore,
    required this.onMinimize,
    required this.onToggleMaximize,
    required this.onClose,
    required this.onDragWindow,
  });

  final bool compact;
  final String section;
  final String query;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final bool scanning;
  final bool onlineMode;
  final bool maximized;

  final Color backgroundColor;
  final Color surfaceColor;
  final Color accentColor;
  final Color mutedColor;

  final VoidCallback onHome;
  final VoidCallback onSettings;
  final VoidCallback onNotifications;
  final VoidCallback onExplore;
  final VoidCallback onMinimize;
  final VoidCallback onToggleMaximize;
  final VoidCallback onClose;
  final VoidCallback onDragWindow;

  @override
  State<SoundNeedTopBar> createState() => _SoundNeedTopBarState();
}

class _SoundNeedTopBarState extends State<SoundNeedTopBar> {
  final GlobalKey _homeKey = GlobalKey();
  final GlobalKey _searchKey = GlobalKey();
  final GlobalKey _settingsKey = GlobalKey();
  final GlobalKey _notificationsKey = GlobalKey();
  final GlobalKey _exploreKey = GlobalKey();
  final GlobalKey _downloadsKey = GlobalKey();
  final GlobalKey _minimizeKey = GlobalKey();
  final GlobalKey _maximizeKey = GlobalKey();
  final GlobalKey _closeKey = GlobalKey();

  bool _searchFocused = false;

  static const Color _background = Colors.transparent;
  static const Color _surface = Color(0xFF141417);
  static const Color _hover = Color(0xFF242428);
  static const Color _border = Color(0xFF29292F);
  static const Color _muted = Color(0xFF85858F);
  static const Color _green = Color(0xFF4ADE80);

  bool _isInteractiveAt(Offset position) {
    final keys = [
      _homeKey,
      _searchKey,
      _settingsKey,
      _notificationsKey,
      _exploreKey,
      _downloadsKey,
      _minimizeKey,
      _maximizeKey,
      _closeKey,
    ];

    for (final key in keys) {
      final context = key.currentContext;
      if (context == null) continue;

      final renderObject = context.findRenderObject();
      if (renderObject is! RenderBox ||
          !renderObject.hasSize ||
          !renderObject.attached) {
        continue;
      }

      final origin = renderObject.localToGlobal(Offset.zero);
      final rect = origin & renderObject.size;

      if (rect.contains(position)) return true;
    }

    return false;
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (!Platform.isWindows ||
        event.buttons != kPrimaryButton ||
        _isInteractiveAt(event.position)) {
      return;
    }

    widget.onDragWindow();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final compact = widget.compact || width < 760;
        final veryCompact = width < 540;
        final ultraCompact = width < 360;

        return Listener(
          onPointerDown: _handlePointerDown,
          child: Container(
            height: 76,
            padding: EdgeInsets.only(left: veryCompact ? 8 : 20, right: 0),
            decoration: const BoxDecoration(color: _background),
            child: Row(
              children: [
                if (!ultraCompact) ...[
                  _buildBrand(compact: compact),
                  SizedBox(width: veryCompact ? 8 : 22),
                  _buildHomeButton(),
                  const SizedBox(width: 8),
                  _buildTopBarIcon(
                    key: _downloadsKey,
                    icon: Icons.download_rounded,
                    svgName: 'downloading-updates',
                    tooltip: 'Descargas',
                    onPressed: () {},
                  ),
                  SizedBox(width: veryCompact ? 8 : 18),
                ],
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: veryCompact ? 6 : 18),
                    child: _buildSearch(compact: true),
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(width: 8),
                  _buildTopBarIcon(
                    key: _notificationsKey,
                    icon: Icons.notifications_none_rounded,
                    svgName: 'notification',
                    tooltip: 'Notificaciones',
                    onPressed: widget.onNotifications,
                  ),
                  const SizedBox(width: 8),
                  _buildTopBarIcon(
                    key: _settingsKey,
                    icon: Icons.settings_rounded,
                    svgName: 'settings',
                    tooltip: 'Configuración',
                    onPressed: widget.onSettings,
                  ),
                ],
                if (!compact) const SizedBox(width: 16),
                if (width >= 320) _buildWindowControls(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBrand({required bool compact}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: _surface,
            shape: BoxShape.circle,
            border: Border.all(color: _border),
          ),
          child: Center(
            child: Image.asset(
              'assets/icon/app_icon_source.png',
              fit: BoxFit.contain,
              width: 24,
              height: 24,
            ),
          ),
        ),
        if (!compact) ...[
          const SizedBox(width: 11),
          const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SoundNeed',
                style: TextStyle(
                  color: _text,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                ),
              ),
              SizedBox(height: 3),
              Text(
                'MUSIC DESKTOP',
                style: TextStyle(
                  color: _muted,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildHomeButton() {
    final isHome = widget.section.toLowerCase() == 'inicio';
    return _circleButton(
      key: _homeKey,
      icon: CupertinoIcons.house,
      svgName: isHome ? 'home-filled' : 'home',
      svgColor: isHome ? _text : _muted,
      tooltip: 'Inicio',
      onPressed: widget.onHome,
      size: 42,
      iconSize: 23,
      background: isHome ? _hover : _surface,
    );
  }

  Widget _buildSearch({required bool compact}) {
    return Container(
      key: _searchKey,
      height: 44,
      constraints: const BoxConstraints(maxWidth: 570, minWidth: 0),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: _searchFocused ? _text.withValues(alpha: 0.35) : _border,
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          SoundNeedSvgIcon(
            'search',
            color: _searchFocused ? _text : _muted,
            size: 24,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Focus(
              onFocusChange: (focused) {
                if (mounted) {
                  setState(() => _searchFocused = focused);
                }
              },
              child: TextField(
                controller: widget.searchController,
                onChanged: widget.onSearchChanged,
                style: const TextStyle(color: _text, fontSize: 13),
                cursorColor: _text,
                decoration: InputDecoration(
                  hintText: compact
                      ? 'Buscar música...'
                      : 'Buscar canciones, artistas o álbumes',
                  hintStyle: const TextStyle(color: _muted, fontSize: 12),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
          if (widget.query.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                tooltip: 'Limpiar búsqueda',
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  widget.searchController.clear();
                  widget.onSearchChanged('');
                },
                icon: const Icon(Icons.close_rounded, color: _muted, size: 17),
              ),
            )
          else
            const SizedBox(width: 4),
          IconButton(
            key: _exploreKey,
            tooltip: 'Explorar',
            visualDensity: VisualDensity.compact,
            splashRadius: 19,
            onPressed: widget.onExplore,
            icon: const SoundNeedSvgIcon(
              'layers-3',
              size: 20,
              color: _muted,
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }

  Widget _buildStatus({required bool compact}) {
    final label = widget.scanning
        ? 'Analizando'
        : widget.onlineMode
        ? 'En línea'
        : 'Biblioteca';

    final color = widget.scanning
        ? widget.accentColor
        : widget.onlineMode
        ? _green
        : _muted;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        if (!compact) ...[
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: _muted,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTopBarIcon({
    required Key key,
    required IconData icon,
    String? svgName,
    Color? svgColor,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return _circleButton(
      key: key,
      icon: icon,
      svgName: svgName,
      svgColor: svgColor,
      tooltip: tooltip,
      onPressed: onPressed,
      size: 40,
    );
  }

  Widget _buildWindowControls() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _circleButton(
          key: _minimizeKey,
          icon: CupertinoIcons.minus,
          tooltip: 'Minimizar',
          onPressed: widget.onMinimize,
          size: 34,
          width: 46,
          height: 76,
          iconSize: 17,
          background: Colors.transparent,
          borderColor: Colors.transparent,
          square: true,
        ),
        _circleButton(
          key: _maximizeKey,
          icon: widget.maximized
              ? CupertinoIcons.square_on_square
              : CupertinoIcons.square,
          tooltip: widget.maximized ? 'Restaurar' : 'Maximizar',
          onPressed: widget.onToggleMaximize,
          size: 34,
          width: 46,
          height: 76,
          iconSize: 16,
          background: Colors.transparent,
          borderColor: Colors.transparent,
          square: true,
        ),
        _circleButton(
          key: _closeKey,
          icon: CupertinoIcons.xmark,
          tooltip: 'Cerrar',
          onPressed: widget.onClose,
          size: 34,
          width: 46,
          height: 76,
          iconSize: 17,
          background: Colors.transparent,
          borderColor: Colors.transparent,
          hoverColor: _red,
          square: true,
        ),
      ],
    );
  }

  Widget _circleButton({
    Key? key,
    required IconData icon,
    String? svgName,
    Color? svgColor,
    required String tooltip,
    required VoidCallback onPressed,
    double size = 40,
    double iconSize = 23,
    Color background = _surface,
    Color borderColor = _border,
    Color hoverColor = _hover,
    bool square = false,
    double? width,
    double? height,
  }) {
    return _CircleButton(
      key: key,
      icon: icon,
      svgName: svgName,
      svgColor: svgColor,
      tooltip: tooltip,
      onPressed: onPressed,
      size: size,
      iconSize: iconSize,
      background: background,
      borderColor: borderColor,
      hoverColor: hoverColor,
      square: square,
      width: width,
      height: height,
    );
  }
}

class _CircleButton extends StatefulWidget {
  const _CircleButton({
    super.key,
    required this.icon,
    this.svgName,
    this.svgColor,
    required this.tooltip,
    required this.onPressed,
    required this.size,
    required this.iconSize,
    required this.background,
    required this.borderColor,
    required this.hoverColor,
    this.square = false,
    this.width,
    this.height,
  });

  final IconData icon;
  final String? svgName;
  final Color? svgColor;
  final String tooltip;
  final VoidCallback onPressed;
  final double size;
  final double iconSize;
  final Color background;
  final Color borderColor;
  final Color hoverColor;
  final bool square;
  final double? width;
  final double? height;

  @override
  State<_CircleButton> createState() => _CircleButtonState();
}

class _CircleButtonState extends State<_CircleButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 450),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          curve: Curves.easeOut,
          width: widget.width ?? widget.size,
          height: widget.height ?? widget.size,
          decoration: BoxDecoration(
            color: _hovered ? widget.hoverColor : widget.background,
            shape: widget.square ? BoxShape.rectangle : BoxShape.circle,
            borderRadius: widget.square ? BorderRadius.zero : null,
            border: Border.all(
              color: _hovered ? widget.hoverColor : widget.borderColor,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              customBorder: widget.square
                  ? RoundedRectangleBorder(borderRadius: BorderRadius.zero)
                  : const CircleBorder(),
              onTap: widget.onPressed,
              child: Center(
                child: widget.svgName == null
                    ? Icon(
                        widget.icon,
                        size: widget.iconSize,
                        color: _hovered && widget.hoverColor == _red
                            ? Colors.white
                            : _text,
                      )
                    : SoundNeedSvgIcon(
                        widget.svgName!,
                        size: widget.iconSize,
                        color: _hovered && widget.hoverColor == _red
                            ? Colors.white
                            : _hovered
                            ? _text
                            : (widget.svgColor ?? _iconMuted),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
