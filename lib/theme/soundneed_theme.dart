import 'package:flutter/material.dart';

/// Shared desktop design tokens. Artwork can add atmosphere behind the UI,
/// while these surfaces and controls keep SoundNeed's graphite/cyan identity.
abstract final class SoundNeedPalette {
  static const background = Color(0xFF090C13);
  static const panel = Color(0xFF101722);
  static const surface = Color(0xFF151E2A);
  static const raised = Color(0xFF1B2634);
  static const accent = Color(0xFF83E8FF);
  static const accentDeep = Color(0xFF173443);
  static const text = Color(0xFFF4F7FB);
  static const muted = Color(0xFF98A5B6);
  static const border = Color(0xFF293746);
  static const favorite = Color(0xFFFF637D);

  static const radiusSmall = 12.0;
  static const radiusMedium = 18.0;
  static const radiusLarge = 24.0;
  static const controlSize = 44.0;
}

abstract final class SoundNeedTheme {
  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: SoundNeedPalette.background,
    canvasColor: SoundNeedPalette.background,
    colorScheme: const ColorScheme.dark(
      primary: SoundNeedPalette.accent,
      onPrimary: SoundNeedPalette.background,
      secondary: SoundNeedPalette.accent,
      surface: SoundNeedPalette.panel,
      onSurface: SoundNeedPalette.text,
      onSurfaceVariant: SoundNeedPalette.muted,
      outline: SoundNeedPalette.border,
    ),
    fontFamily: 'Segoe UI',
    textTheme:
        const TextTheme(
          displayLarge: TextStyle(
            fontSize: 38,
            height: 1.04,
            fontWeight: FontWeight.w700,
            letterSpacing: -1.35,
          ),
          displayMedium: TextStyle(
            fontSize: 32,
            height: 1.08,
            fontWeight: FontWeight.w700,
            letterSpacing: -1.0,
          ),
          headlineLarge: TextStyle(
            fontSize: 26,
            height: 1.12,
            fontWeight: FontWeight.w700,
            letterSpacing: -.65,
          ),
          headlineMedium: TextStyle(
            fontSize: 22,
            height: 1.16,
            fontWeight: FontWeight.w600,
            letterSpacing: -.4,
          ),
          titleLarge: TextStyle(
            fontSize: 18,
            height: 1.25,
            fontWeight: FontWeight.w600,
            letterSpacing: -.2,
          ),
          titleMedium: TextStyle(
            fontSize: 15,
            height: 1.3,
            fontWeight: FontWeight.w600,
          ),
          bodyLarge: TextStyle(fontSize: 15, height: 1.45),
          bodyMedium: TextStyle(fontSize: 13, height: 1.42),
          bodySmall: TextStyle(fontSize: 11, height: 1.38),
          labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          labelMedium: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ).apply(
          displayColor: SoundNeedPalette.text,
          bodyColor: SoundNeedPalette.text,
        ),
    iconTheme: const IconThemeData(size: 20, color: SoundNeedPalette.muted),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size.square(SoundNeedPalette.controlSize),
        padding: const EdgeInsets.all(10),
        foregroundColor: SoundNeedPalette.text,
        hoverColor: SoundNeedPalette.accent.withValues(alpha: .10),
        overlayColor: SoundNeedPalette.accent.withValues(alpha: .14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SoundNeedPalette.radiusSmall),
        ),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      foregroundColor: SoundNeedPalette.text,
      titleTextStyle: TextStyle(
        color: SoundNeedPalette.text,
        fontSize: 19,
        fontWeight: FontWeight.w600,
        letterSpacing: -.3,
      ),
    ),
    cardTheme: CardThemeData(
      color: SoundNeedPalette.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SoundNeedPalette.radiusMedium),
        side: const BorderSide(color: SoundNeedPalette.border),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      dense: false,
      minVerticalPadding: 8,
      iconColor: SoundNeedPalette.muted,
      textColor: SoundNeedPalette.text,
      titleTextStyle: TextStyle(
        color: SoundNeedPalette.text,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      subtitleTextStyle: TextStyle(
        color: SoundNeedPalette.muted,
        fontSize: 12,
        height: 1.35,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: SoundNeedPalette.surface,
      hintStyle: const TextStyle(color: SoundNeedPalette.muted, fontSize: 13),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SoundNeedPalette.radiusMedium),
        borderSide: const BorderSide(color: SoundNeedPalette.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SoundNeedPalette.radiusMedium),
        borderSide: const BorderSide(color: SoundNeedPalette.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SoundNeedPalette.radiusMedium),
        borderSide: const BorderSide(
          color: SoundNeedPalette.accent,
          width: 1.3,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(44, 44),
        backgroundColor: SoundNeedPalette.accent,
        foregroundColor: SoundNeedPalette.background,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SoundNeedPalette.radiusSmall),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(44, 44),
        foregroundColor: SoundNeedPalette.text,
        side: const BorderSide(color: SoundNeedPalette.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SoundNeedPalette.radiusSmall),
        ),
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: SoundNeedPalette.accent,
      inactiveTrackColor: Colors.white.withValues(alpha: .14),
      thumbColor: SoundNeedPalette.accent,
      overlayColor: SoundNeedPalette.accent.withValues(alpha: .12),
      trackHeight: 3,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: SoundNeedPalette.raised,
        borderRadius: BorderRadius.circular(SoundNeedPalette.radiusSmall),
        border: Border.all(color: SoundNeedPalette.border),
      ),
      textStyle: const TextStyle(color: SoundNeedPalette.text, fontSize: 12),
    ),
  );
}
