import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Colors sampled from the current track artwork for collection accents.
class ArtworkPalette {
  const ArtworkPalette({required this.primary, required this.secondary});

  static const neutral = ArtworkPalette(
    primary: Color(0xFF83E8FF),
    secondary: Color(0xFF6EBBEA),
  );

  final Color primary;
  final Color secondary;
}

class ArtworkPaletteExtractor {
  const ArtworkPaletteExtractor._();

  static Future<ArtworkPalette> fromBytes(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: 24,
      targetHeight: 24,
    );
    try {
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (data == null) return ArtworkPalette.neutral;

        final weights = List<double>.filled(36, 0);
        final hueX = List<double>.filled(36, 0);
        final hueY = List<double>.filled(36, 0);
        final saturations = List<double>.filled(36, 0);
        final values = List<double>.filled(36, 0);
        for (var offset = 0; offset + 3 < data.lengthInBytes; offset += 4) {
          final alpha = data.getUint8(offset + 3) / 255;
          if (alpha < .72) continue;
          final color = Color.fromARGB(
            255,
            data.getUint8(offset),
            data.getUint8(offset + 1),
            data.getUint8(offset + 2),
          );
          final hsv = HSVColor.fromColor(color);
          if (hsv.saturation < .2 || hsv.value < .13 || hsv.value > .97) {
            continue;
          }
          final bin = (hsv.hue / 10).floor().clamp(0, 35);
          final weight = hsv.saturation * hsv.saturation * alpha;
          final radians = hsv.hue * math.pi / 180;
          weights[bin] += weight;
          hueX[bin] += math.cos(radians) * weight;
          hueY[bin] += math.sin(radians) * weight;
          saturations[bin] += hsv.saturation * weight;
          values[bin] += hsv.value * weight;
        }

        var dominant = 0;
        for (var bin = 1; bin < weights.length; bin++) {
          if (weights[bin] > weights[dominant]) dominant = bin;
        }
        if (weights[dominant] == 0) return ArtworkPalette.neutral;

        final hue =
            (math.atan2(hueY[dominant], hueX[dominant]) * 180 / math.pi + 360) %
            360;
        final saturation = (saturations[dominant] / weights[dominant])
            .clamp(.48, .84)
            .toDouble();
        final value = (values[dominant] / weights[dominant])
            .clamp(.62, .9)
            .toDouble();
        final primary = HSVColor.fromAHSV(1, hue, saturation, value).toColor();
        var secondDominant = -1;
        for (var bin = 0; bin < weights.length; bin++) {
          final binHue = bin * 10.0 + 5;
          final hueDistance = ((binHue - hue + 540) % 360) - 180;
          if (hueDistance.abs() < 34) continue;
          if (secondDominant < 0 || weights[bin] > weights[secondDominant]) {
            secondDominant = bin;
          }
        }
        final hasDistinctSecondary =
            secondDominant >= 0 &&
            weights[secondDominant] >= weights[dominant] * .32;
        final secondaryHue = hasDistinctSecondary
            ? (math.atan2(hueY[secondDominant], hueX[secondDominant]) *
                          180 /
                          math.pi +
                      360) %
                  360
            : (hue + 28) % 360;
        final secondarySaturation = hasDistinctSecondary
            ? (saturations[secondDominant] / weights[secondDominant])
                  .clamp(.42, .78)
                  .toDouble()
            : (saturation * .78).clamp(.4, .72).toDouble();
        final secondaryValue = hasDistinctSecondary
            ? (values[secondDominant] / weights[secondDominant])
                  .clamp(.56, .86)
                  .toDouble()
            : (value * .9).clamp(.54, .82).toDouble();
        final secondary = HSVColor.fromAHSV(
          1,
          secondaryHue,
          secondarySaturation,
          secondaryValue,
        ).toColor();
        return ArtworkPalette(primary: primary, secondary: secondary);
      } finally {
        image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }
}
