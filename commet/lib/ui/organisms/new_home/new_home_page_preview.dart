import 'dart:async';

import 'package:commet/utils/event_bus.dart';
import 'package:flutter/material.dart';

/// Vommet issue 782: a whole page (People, Direct messages, Rooms browser)
/// beside other Overview cards shows only its first rows, then
/// "See all N ›", which opens the whole page. Alone on its tab it is still
/// the whole page.
abstract final class NewHomePagePreview {
  /// Rows a page shows as a card beside other cards.
  static const rows = 5;

  /// Opens the whole page on top of Home. It closes itself when a room
  /// opens from it, so the room shows.
  static void open(BuildContext context,
      {required String title, required WidgetBuilder builder}) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _WholePage(title: title, builder: builder)));
  }
}

/// "See all N ›" under a page's first rows.
class NewHomeSeeAll extends StatelessWidget {
  const NewHomeSeeAll({super.key, required this.total, required this.onTap});

  final int total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          key: const ValueKey("NewHomeSeeAll"),
          onPressed: onTap,
          child: Text("See all $total ›"),
        ),
      );
}

class _WholePage extends StatefulWidget {
  const _WholePage({required this.title, required this.builder});

  final String title;
  final WidgetBuilder builder;

  @override
  State<_WholePage> createState() => _WholePageState();
}

class _WholePageState extends State<_WholePage> {
  StreamSubscription? sub;

  @override
  void initState() {
    super.initState();
    sub = EventBus.openRoom.stream.listen((_) {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  void dispose() {
    sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        key: const ValueKey("NewHomeWholePage"),
        appBar: AppBar(title: Text(widget.title)),
        body: widget.builder(context),
      );
}
