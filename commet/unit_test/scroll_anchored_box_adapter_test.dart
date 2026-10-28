import 'package:commet/ui/layout/scroll_anchored_box_adapter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The sidebar's shape: a pinned header over one box holding the room rows.
/// Row 2 stands in for a voice room whose participant list grows or shrinks.
class _List extends StatelessWidget {
  const _List(
      {required this.controller,
      required this.voiceRoomHeight,
      this.anchored = true});

  final ScrollController controller;
  final double voiceRoomHeight;
  final bool anchored;

  @override
  Widget build(BuildContext context) {
    final rooms = Column(children: [
      for (var i = 0; i < 40; i++)
        SizedBox(
          key: ValueKey("room-$i"),
          height: i == 2 ? voiceRoomHeight : 50,
          child: Text("room $i"),
        ),
    ]);
    return MaterialApp(
      home: SizedBox(
        height: 400,
        child: CustomScrollView(controller: controller, slivers: [
          SliverPersistentHeader(pinned: true, delegate: _Header()),
          anchored
              ? ScrollAnchoredBoxAdapter(child: rooms)
              : SliverToBoxAdapter(child: rooms),
        ]),
      ),
    );
  }
}

class _Header extends SliverPersistentHeaderDelegate {
  @override
  double get minExtent => 40;
  @override
  double get maxExtent => 40;
  @override
  Widget build(
          BuildContext context, double shrinkOffset, bool overlapsContent) =>
      const SizedBox.expand(child: ColoredBox(color: Colors.black));
  @override
  bool shouldRebuild(_Header oldDelegate) => false;
}

double _screenTop(WidgetTester tester, int room) =>
    tester.getTopLeft(find.byKey(ValueKey("room-$room"))).dy;

void main() {
  testWidgets("a row growing above the viewport doesn't move visible rooms",
      (tester) async {
    final controller = ScrollController();
    await tester.pumpWidget(_List(controller: controller, voiceRoomHeight: 50));
    controller.jumpTo(800);
    await tester.pump();
    final before = _screenTop(tester, 20);

    await tester
        .pumpWidget(_List(controller: controller, voiceRoomHeight: 130));
    expect(_screenTop(tester, 20), before);
    expect(controller.offset, 880);

    // Scrolling up reaches the grown row.
    controller.jumpTo(0);
    await tester.pump();
    expect(tester.getSize(find.byKey(const ValueKey("room-2"))).height, 130);
  });

  testWidgets("a row shrinking above the viewport doesn't move visible rooms",
      (tester) async {
    final controller = ScrollController();
    await tester
        .pumpWidget(_List(controller: controller, voiceRoomHeight: 130));
    controller.jumpTo(800);
    await tester.pump();
    final before = _screenTop(tester, 20);

    await tester.pumpWidget(_List(controller: controller, voiceRoomHeight: 50));
    expect(_screenTop(tester, 20), before);
    expect(controller.offset, 720);
  });

  testWidgets("at the top of the list, changes show as before", (tester) async {
    final controller = ScrollController();
    await tester.pumpWidget(_List(controller: controller, voiceRoomHeight: 50));
    final before = _screenTop(tester, 5);

    await tester
        .pumpWidget(_List(controller: controller, voiceRoomHeight: 130));
    expect(controller.offset, 0);
    expect(_screenTop(tester, 5), before + 80);
  });

  testWidgets("a visible row growing pushes the rows below it", (tester) async {
    final controller = ScrollController();
    await tester.pumpWidget(_List(controller: controller, voiceRoomHeight: 50));
    // Room 2 (y 100..150 in the list) sits just under the pinned header.
    controller.jumpTo(80);
    await tester.pump();
    final voiceRoom = _screenTop(tester, 2);
    final below = _screenTop(tester, 4);

    await tester
        .pumpWidget(_List(controller: controller, voiceRoomHeight: 130));
    expect(_screenTop(tester, 2), voiceRoom);
    expect(_screenTop(tester, 4), below + 80);
  });

  testWidgets("without anchoring the visible rooms jump (the bug)",
      (tester) async {
    final controller = ScrollController();
    await tester.pumpWidget(
        _List(controller: controller, voiceRoomHeight: 50, anchored: false));
    controller.jumpTo(800);
    await tester.pump();
    final before = _screenTop(tester, 20);

    await tester.pumpWidget(
        _List(controller: controller, voiceRoomHeight: 130, anchored: false));
    expect(_screenTop(tester, 20), before + 80);
  });
}
