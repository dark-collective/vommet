import 'package:commet/config/layout_config.dart';
import 'package:commet/ui/organisms/new_home/new_home.dart';
import 'package:commet/ui/organisms/new_home/new_home_main.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: the Tile around Home. With New Home on, Home's main area shows
/// New Home's pages (Overview, People, Rooms). The Friends tab experiment
/// that used to switch Home | Friends here was removed 10-25: New Home's
/// People shows the same list. Stands in for Home's own Tile so the main
/// pages change one word each.
class FriendsHomeTile extends StatelessWidget {
  const FriendsHomeTile({
    super.key,
    required this.child,
    this.caulkPadLeft = false,
    this.caulkClipTopLeft = false,
    this.caulkClipBottomLeft = false,
    this.caulkPadTop = false,
    this.caulkPadBottom = false,
  });

  final Widget child;
  final bool caulkPadLeft;
  final bool caulkClipTopLeft;
  final bool caulkClipBottomLeft;
  final bool caulkPadTop;
  final bool caulkPadBottom;

  @override
  Widget build(BuildContext context) {
    return tiamat.Tile(
      caulkPadLeft: caulkPadLeft,
      caulkClipTopLeft: caulkClipTopLeft,
      caulkClipBottomLeft: caulkClipBottomLeft,
      caulkPadTop: caulkPadTop,
      caulkPadBottom: caulkPadBottom,
      child: newHomeEnabled
          ? NewHomeMain(home: child, phone: MediaQuery.of(context).mobile)
          : child,
    );
  }
}
