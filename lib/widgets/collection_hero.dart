import 'package:flutter/material.dart';

/// Shared visual header for the user's music collections.
/// Playback and navigation remain owned by the page that supplies the content.
class CollectionHero extends StatelessWidget {
  const CollectionHero({
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.icon,
    this.count,
    this.countLabel,
    this.action,
    this.compact = false,
    this.accent = const Color(0xFF83E8FF),
    this.secondaryAccent,
    super.key,
  });

  final String eyebrow;
  final String title;
  final String description;
  final IconData icon;
  final int? count;
  final String? countLabel;
  final Widget? action;
  final bool compact;
  final Color accent;
  final Color? secondaryAccent;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final narrow = compact || constraints.maxWidth < 620;
      final secondary = secondaryAccent ?? accent;
      final iconSize = narrow ? 56.0 : 68.0;
      final identity = Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 620),
            curve: Curves.easeOutCubic,
            width: iconSize,
            height: iconSize,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accent.withValues(alpha: .24),
                  secondary.withValues(alpha: .13),
                ],
              ),
              borderRadius: BorderRadius.circular(narrow ? 18 : 22),
              border: Border.all(color: accent.withValues(alpha: .31)),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: .11),
                  blurRadius: 18,
                  spreadRadius: -6,
                ),
              ],
            ),
            child: Icon(icon, color: accent, size: narrow ? 29 : 35),
          ),
          SizedBox(width: narrow ? 14 : 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 620),
                  curve: Curves.easeOutCubic,
                  style: TextStyle(
                    color: accent,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.65,
                  ),
                  child: Text(
                    eyebrow.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: const Color(0xFFF4F7FB),
                    fontSize: narrow ? 23 : 29,
                    height: 1.08,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.75,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  description,
                  maxLines: narrow ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFACB8C7),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      );

      final summary = count == null || countLabel == null
          ? null
          : AnimatedContainer(
              duration: const Duration(milliseconds: 620),
              curve: Curves.easeOutCubic,
              constraints: const BoxConstraints(minWidth: 82),
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    accent.withValues(alpha: .14),
                    secondary.withValues(alpha: .08),
                  ],
                ),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: accent.withValues(alpha: .24)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 620),
                    curve: Curves.easeOutCubic,
                    style: TextStyle(
                      color: accent,
                      fontSize: 19,
                      height: 1,
                      fontWeight: FontWeight.w800,
                    ),
                    child: Text('$count'),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    countLabel!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFB5C1CE),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            );

      return ClipRRect(
        borderRadius: BorderRadius.circular(23),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 620),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(const Color(0xFF141A24), accent, .18)!,
                Color.lerp(const Color(0xFF11151D), secondary, .10)!,
                const Color(0xFF151722),
              ],
            ),
            border: Border.all(color: accent.withValues(alpha: .26)),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: .12),
                blurRadius: 30,
                spreadRadius: -10,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                right: -76,
                top: -118,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 620),
                  curve: Curves.easeOutCubic,
                  width: 310,
                  height: 310,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        accent.withValues(alpha: .18),
                        secondary.withValues(alpha: .055),
                        Colors.transparent,
                      ],
                      stops: const [0, .54, 1],
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 22,
                bottom: -148,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 620),
                  width: 210,
                  height: 210,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: secondary.withValues(alpha: .07),
                      width: 26,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: 22,
                bottom: 22,
                child: Container(
                  width: 3,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [accent, secondary.withValues(alpha: .42)],
                    ),
                    borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(4),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  narrow ? 18 : 24,
                  narrow ? 19 : 24,
                  narrow ? 18 : 24,
                  narrow ? 19 : 24,
                ),
                child: narrow
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          identity,
                          if (summary != null || action != null) ...[
                            const SizedBox(height: 15),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [?summary, ?action],
                            ),
                          ],
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(child: identity),
                          if (summary != null) ...[
                            const SizedBox(width: 18),
                            summary,
                          ],
                          if (action != null) ...[
                            const SizedBox(width: 12),
                            action!,
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
