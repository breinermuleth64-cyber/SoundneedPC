import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

const Color _hover = Color(0xFF202025);

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

  static const Color _background = Color(0xFF0B0B0E);
  static const Color _surface = Colors.transparent;
  static const Color _border = Color(0xFF29292F);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: compact ? 84 : 254,
      padding: EdgeInsets.fromLTRB(compact ? 9 : 13, 0, compact ? 9 : 13, 4),
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _border.withValues(alpha: 0.85), width: 1),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 24,
              offset: Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 8 : 12,
            30,
            compact ? 8 : 12,
            18,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionLabel('BIBLIOTECA'),
                const SizedBox(height: 9),

                _navItem(context, CupertinoIcons.music_note_list, 'Tu música'),
                _navItem(context, CupertinoIcons.heart, 'Favoritos'),

                const SizedBox(height: 25),

                _buildSectionLabel('EXPLORAR'),
                const SizedBox(height: 9),

                _navItem(context, CupertinoIcons.circle_grid_3x3, 'Álbumes'),
                _navItem(context, CupertinoIcons.person_2, 'Artistas'),
                _navItem(context, CupertinoIcons.music_note_list, 'Playlists'),

                if (section == 'Playlists' && !compact) ...[
                  const SizedBox(height: 7),
                  Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Container(
                      width: 2,
                      height: playlistNames.isEmpty
                          ? 0
                          : (playlistNames.length * 33.0).clamp(0, 165),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  ...playlistNames.map(
                    (name) => Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: _navItem(context, Icons.circle, name, small: true),
                    ),
                  ),
                ],
              ],
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
        child: Center(child: Container(width: 22, height: 1, color: _border)),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: Text(
        label,
        style: TextStyle(
          color: mutedColor.withValues(alpha: 0.75),
          fontSize: 9,
          letterSpacing: 1.7,
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
      padding: const EdgeInsets.only(bottom: 4),
      child: Tooltip(
        message: compact ? label : '',
        child: _SidebarNavButton(
          compact: compact,
          small: small,
          selected: selected,
          icon: icon,
          label: label,
          accentColor: accentColor,
          mutedColor: mutedColor,
          onTap: () => onNavigate(label),
        ),
      ),
    );
  }
}

class _SidebarNavButton extends StatefulWidget {
  const _SidebarNavButton({
    required this.compact,
    required this.small,
    required this.selected,
    required this.icon,
    required this.label,
    required this.accentColor,
    required this.mutedColor,
    required this.onTap,
  });

  final bool compact;
  final bool small;
  final bool selected;
  final IconData icon;
  final String label;
  final Color accentColor;
  final Color mutedColor;
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

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        height: widget.small ? 33 : 43,
        decoration: BoxDecoration(
          color: active
              ? widget.accentColor.withValues(alpha: 0.13)
              : _hovered
              ? _hover
              : Colors.transparent,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: active
                ? widget.accentColor.withValues(alpha: 0.17)
                : Colors.transparent,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(13),
            onTap: widget.onTap,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 0 : (widget.small ? 10 : 12),
              ),
              child: Row(
                mainAxisAlignment: compact
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: [
                  if (active && !compact && !widget.small)
                    Container(
                      width: 3,
                      height: 19,
                      margin: const EdgeInsets.only(right: 9),
                      decoration: BoxDecoration(
                        color: widget.accentColor,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  Icon(
                    widget.icon,
                    size: widget.small ? 10 : 19,
                    color: active ? widget.accentColor : widget.mutedColor,
                  ),
                  if (!compact) ...[
                    SizedBox(width: widget.small ? 9 : 11),
                    Expanded(
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: active ? Colors.white : widget.mutedColor,
                          fontSize: widget.small ? 11 : 12,
                          fontWeight: active
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                    if (active && widget.small)
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: widget.accentColor,
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
