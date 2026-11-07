// Vommet issue 1216: image-only orientation controls; the source is unchanged.
import 'package:commet/utils/image/viewer_rotation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

String get viewerRotateLeft => Intl.message(
      'Rotate left 90°',
      name: 'viewerRotateLeft',
      desc: 'Turn the viewed image counterclockwise',
    );
String get viewerRotateRight => Intl.message(
      'Rotate right 90°',
      name: 'viewerRotateRight',
      desc: 'Turn the viewed image clockwise',
    );
String get viewerResetRotation => Intl.message(
      'Reset rotation',
      name: 'viewerResetRotation',
      desc: 'Remove this image viewing correction',
    );

class LightboxRotationControls extends StatelessWidget {
  const LightboxRotationControls({required this.rotation, super.key});

  final ViewerRotation rotation;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (direction, label, icon) in [
            (-1, viewerRotateLeft, Icons.rotate_left),
            (1, viewerRotateRight, Icons.rotate_right),
          ])
            IconButton(
              key: ValueKey('viewer_rotate_$direction'),
              constraints: const BoxConstraints.tightFor(width: 48, height: 48),
              tooltip: label,
              color: Colors.white,
              icon: Icon(icon),
              onPressed: () => rotation.turn(direction),
            ),
        ],
      );
}
