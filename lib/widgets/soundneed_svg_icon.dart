import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class SoundNeedSvgIcon extends StatelessWidget {
  const SoundNeedSvgIcon(
    this.name, {
    required this.size,
    required this.color,
    super.key,
  });

  final String name;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/icons/icons8-$name.svg',
    width: size,
    height: size,
    colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    excludeFromSemantics: true,
  );
}
