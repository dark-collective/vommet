import 'package:commet/config/layout_config.dart';
import 'package:commet/ui/atoms/scaled_safe_area.dart';
import 'package:commet/ui/organisms/friends/friends_experiment.dart';
import 'package:commet/ui/organisms/friends/friends_view.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: the Tile around Home, with a Home | Friends switch when the
/// Friends tab experiment is on (Vommet issue 93). Tabs sit on top on
/// desktop and at the bottom on phones. Home stays alive while Friends shows.
/// Stands in for Home's own Tile so the main pages change one word each.
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
      child: friendsTabEnabled ? _HomeTabs(home: child) : child,
    );
  }
}

class _HomeTabs extends StatefulWidget {
  const _HomeTabs({required this.home});
  final Widget home;

  @override
  State<_HomeTabs> createState() => _HomeTabsState();
}

class _HomeTabsState extends State<_HomeTabs> {
  int tab = 0;

  @override
  Widget build(BuildContext context) {
    final phone = MediaQuery.of(context).mobile;
    final pages = IndexedStack(
      index: tab,
      sizing: StackFit.expand,
      children: [widget.home, FriendsView(phone: phone)],
    );

    if (phone) {
      return Column(children: [
        Expanded(child: pages),
        ScaledSafeArea(
          top: false,
          child: NavigationBar(
            height: 60,
            selectedIndex: tab,
            onDestinationSelected: (i) => setState(() => tab = i),
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.home_rounded), label: "Home"),
              NavigationDestination(
                  icon: Icon(Icons.people_alt_rounded), label: "Friends"),
            ],
          ),
        ),
      ]);
    }

    final scheme = ColorScheme.of(context);
    Widget tabButton(int i, IconData icon, String label) {
      final selected = tab == i;
      final color = selected ? scheme.onSurface : scheme.onSurfaceVariant;
      return Material(
        color: selected ? scheme.surfaceContainerHighest : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => tab = i),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
              Icon(icon, size: 17, color: color),
              Text(label,
                  style: TextStyle(fontWeight: FontWeight.w700, color: color)),
            ]),
          ),
        ),
      );
    }

    return Column(children: [
      ScaledSafeArea(
        bottom: false,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(color: scheme.surfaceContainerHighest))),
          child: Row(spacing: 6, children: [
            tabButton(0, Icons.home_rounded, "Home"),
            tabButton(1, Icons.people_alt_rounded, "Friends"),
          ]),
        ),
      ),
      Expanded(child: pages),
    ]);
  }
}
