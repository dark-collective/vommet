import 'package:flutter/widgets.dart';

abstract class Role {
  String get name;

  IconData get icon;

  /// Vommet: a colour and an emoji or image icon, from MSC3949 power level
  /// tags (Vommet issue 67); null when the role has none.
  Color? get color;
  String? get emoji;
  ImageProvider? get image;
}
