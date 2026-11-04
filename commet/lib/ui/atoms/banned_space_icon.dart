import 'package:flutter/material.dart';

/// Vommet: rail icon of a space we were banned from: faded, with a red ban
/// mark in the bottom-right corner.
class BannedSpaceIcon extends StatelessWidget {
  const BannedSpaceIcon(this.icon, {super.key});

  final Widget icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(clipBehavior: Clip.none, children: [
      Opacity(opacity: 0.45, child: icon),
      Positioned(
        right: -2,
        bottom: -2,
        child: IgnorePointer(
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration:
                BoxDecoration(shape: BoxShape.circle, color: scheme.surfaceDim),
            child: Icon(Icons.block, size: 16, color: scheme.error),
          ),
        ),
      ),
    ]);
  }
}
