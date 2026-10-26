import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'soundneed_svg_icon.dart';

const Color _hover = Color(0xFF202025);
const Color _cyan = Color(0xFF83E8FF);
const Color _muted = Color(0xFF9292A5);
const Color _border = Color(0xFF29292F);

class SoundNeedSidebar extends StatelessWidget {
  const SoundNeedSidebar({
    required this.compact,
    required this.section,
    required this.playlistView,
    required this.playlistNames,
    required this.panelColor,
    required this.accentColor,
    required this.mutedColor,
    required this.onNavigate,
    required this.collapsed,
    required this.onTogglePanel,
    super.key,
  });

  final bool compact;
  final String section;
  final String? playlistView;
  final List<String> playlistNames;
  final Color panelColor;
  final Color accentColor;
  final Color mutedColor;
  final ValueChanged<String> onNavigate;
  final bool collapsed;
  final ValueChanged<bool> onTogglePanel;

  static const Color _surface = Colors.transparent;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOutCubic,
      width: compact ? 84 : 254,
      padding: EdgeInsets.fromLTRB(compact ? 9 : 13, 0, compact ? 9 : 13, 0),
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 7 : 11,
            22,
            compact ? 7 : 11,
            16,
          ),
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context)
                .copyWith(scrollbars: false),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SidebarPanelHeader(
                    compact: compact,
                    collapsed: collapsed,
                    onTogglePanel: onTogglePanel,
                  ),
                  const SizedBox(height: 27),

                  _buildSectionLabel('BIBLIOTECA'),
                  const SizedBox(height: 10),

                  _navItem(
                    context,
                    CupertinoIcons.music_note_list,
                    'Tu música',
                  ),
                  _navItem(context, Icons.folder_open_rounded, 'Carpetas'),

                  const SizedBox(height: 25),

                  _buildSectionLabel('EXPLORAR'),
                  const SizedBox(height: 10),

                  _navItem(context, CupertinoIcons.circle_grid_3x3, 'Álbumes'),
                  _navItem(context, CupertinoIcons.person_2, 'Artistas'),
                  _navItem(
                    context,
                    CupertinoIcons.music_note_list,
                    'Playlists',
                  ),

                  if (section == 'Playlists' && !compact) ...[
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.only(left: 13),
                      child: Container(
                        width: 2,
                        height: playlistNames.isEmpty
                            ? 0
                            : (playlistNames.length * 34.0).clamp(0.0, 170.0),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    ...playlistNames.map(
                      (name) => Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: _navItem(
                          context,
                          Icons.circle,
                          name,
                          small: true,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    if (compact) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Center(
          child: Container(
            width: 24,
            height: 1,
            color: _border.withValues(alpha: 0.9),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(left: 12, bottom: 2),
      child: Text(
        label,
        style: TextStyle(
          color: mutedColor.withValues(alpha: 0.85),
          fontSize: 9,
          letterSpacing: 1.65,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _navItem(
    BuildContext context,
    IconData icon,
    String label, {
    bool small = false,
  }) {
    final selected =
        section == label || (section == 'Playlists' && label == playlistView);

    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Tooltip(
        message: compact ? label : '',
        child: _SidebarNavButton(
          compact: compact,
          small: small,
          selected: selected,
          icon: icon,
          label: label,
          onTap: () => onNavigate(label),
        ),
      ),
    );
  }
}

class _SidebarPanelHeader extends StatefulWidget {
  const _SidebarPanelHeader({
    required this.compact,
    required this.collapsed,
    required this.onTogglePanel,
  });

  final bool compact;
  final bool collapsed;
  final ValueChanged<bool> onTogglePanel;

  @override
  State<_SidebarPanelHeader> createState() => _SidebarPanelHeaderState();
}

class _SidebarPanelHeaderState extends State<_SidebarPanelHeader> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: SizedBox(
      width: double.infinity,
      height: 46,
      child: widget.compact
          ? Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: _hovered
                    ? _toggleButton(key: const ValueKey('open-panel'))
                    : const SoundNeedSvgIcon(
                        'dashboard-layout',
                        key: ValueKey('panel-icon'),
                        size: 30,
                        color: _muted,
                      ),
              ),
            )
          : Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        width: 3,
                        height: 17,
                        decoration: BoxDecoration(
                          color: _cyan.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'NAVEGACIÓN',
                        style: TextStyle(
                          color: Color(0xFFB7B7C5),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 140),
                  opacity: _hovered ? 1 : 0,
                  child: IgnorePointer(
                    ignoring: !_hovered,
                    child: _toggleButton(),
                  ),
                ),
              ],
            ),
    ),
  );

  Widget _toggleButton({Key? key}) => IconButton(
    key: key,
    tooltip: widget.collapsed ? 'Abrir panel' : 'Cerrar panel',
    visualDensity: VisualDensity.compact,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints.tightFor(width: 38, height: 38),
    splashRadius: 20,
    onPressed: () => widget.onTogglePanel(!widget.collapsed),
    icon: SoundNeedSvgIcon(
      widget.collapsed ? 'close-pane' : 'open-pane',
      size: 24,
      color: _hovered ? Colors.white : _muted,
    ),
  );
}

class _SidebarNavButton extends StatefulWidget {
  const _SidebarNavButton({
    required this.compact,
    required this.small,
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool compact;
  final bool small;
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_SidebarNavButton> createState() => _SidebarNavButtonState();
}

class _SidebarNavButtonState extends State<_SidebarNavButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected;
    final compact = widget.compact;
    final small = widget.small;
    const selectedFill = Colors.white;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 135),
        curve: Curves.easeOutCubic,
        height: small ? 34 : 46,
        decoration: BoxDecoration(
          color: active
              ? selectedFill.withValues(alpha: 0.07)
              : _hover.withValues(alpha: _hovered ? 0.72 : 0),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active
                ? selectedFill.withValues(alpha: 0.12)
                : Colors.transparent,
            width: 0.8,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: widget.onTap,
            hoverColor: Colors.transparent,
            splashColor: Colors.white.withValues(alpha: 0.07),
            highlightColor: Colors.transparent,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 0 : (small ? 10 : 11),
              ),
              child: Row(
                mainAxisAlignment: compact
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: [
                  if (active && !compact && !small)
                    Container(
                      width: 2.5,
                      height: 18,
                      margin: const EdgeInsets.only(right: 9),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(3),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.white.withValues(alpha: 0.12),
                            blurRadius: 5,
                          ),
                        ],
                      ),
                    ),
                  AnimatedScale(
                    scale: _hovered && !active ? 1.05 : 1,
                    duration: const Duration(milliseconds: 130),
                    child: Icon(
                      widget.icon,
                      size: small ? 12 : 23,
                      color: active || _hovered ? Colors.white : _muted,
                    ),
                  ),
                  if (!compact) ...[
                    SizedBox(width: small ? 9 : 11),
                    Expanded(
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: active
                              ? Colors.white
                              : _hovered
                              ? const Color(0xFFE0E0E8)
                              : Colors.white70,
                          fontSize: small ? 11 : 12,
                          letterSpacing: small ? 0 : 0.1,
                          fontWeight: active
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                    if (active && small)
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
