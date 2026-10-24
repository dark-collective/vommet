import 'package:flutter/material.dart';

abstract class Member {
  String get identifier;
  String get userName;
  String get displayName;
  String? get detail;
  String? get avatarId;
  ImageProvider? get avatar;

  /// Avatar for big tiles (call view). Starts on the small thumbnail and
  /// upgrades to full resolution, so it stays sharp on high-DPI screens.
  ImageProvider? get largeAvatar;
  Color get defaultColor;
}
