import 'package:commet/ui/atoms/floating_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet: the floating background-task tile (sticker import progress) stays
// inside the window when its label grows after it was placed.
void main() {
  const view = Size(800, 600);
  final tileKey = GlobalKey();

  // Overlay reads initialEntries once, so the tile's width comes from a
  // notifier rather than from re-pumping a new tree.
  Future<ValueNotifier<double>> pumpTile(WidgetTester tester, double width,
      {Alignment corner = Alignment.topRight}) async {
    final w = ValueNotifier(width);
    await tester.pumpWidget(MaterialApp(
      home: Overlay(initialEntries: [
        OverlayEntry(
            builder: (_) => TileOverlay(
                  initialPosition: corner,
                  child: ValueListenableBuilder<double>(
                      valueListenable: w,
                      builder: (_, width, __) =>
                          SizedBox(key: tileKey, width: width, height: 30)),
                )),
      ]),
    ));
    await tester.pumpAndSettle();
    return w;
  }

  testWidgets('a tile that grows keeps its right edge in the window',
      (tester) async {
    tester.view.physicalSize = view;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final width = await pumpTile(tester, 120);
    expect(tester.getRect(find.byKey(tileKey)).right, 790);
    expect(tester.getRect(find.byKey(tileKey)).top, 10);

    width.value = 360;
    await tester.pumpAndSettle();
    final grown = tester.getRect(find.byKey(tileKey));
    expect(grown.right, 790);
    expect(grown.left, 430);
  });

  testWidgets('a tile wider than the window is limited to the window',
      (tester) async {
    tester.view.physicalSize = view;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Overlay(initialEntries: [
        OverlayEntry(
            builder: (_) => TileOverlay(
                  child: Text("x" * 400, key: tileKey),
                )),
      ]),
    ));
    await tester.pumpAndSettle();
    final rect = tester.getRect(find.byKey(tileKey));
    expect(rect.left, greaterThanOrEqualTo(10));
    expect(rect.right, lessThanOrEqualTo(790));
  });

  testWidgets('a flick to the left snaps the tile to the left corner',
      (tester) async {
    tester.view.physicalSize = view;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpTile(tester, 120);
    await tester.drag(find.byKey(tileKey), const Offset(-500, 400));
    await tester.pumpAndSettle();
    final rect = tester.getRect(find.byKey(tileKey));
    expect(rect.left, 10);
    expect(rect.bottom, 590);
  });

  testWidgets('a scrolling card (the pack import queue) lays out in the tile',
      (tester) async {
    tester.view.physicalSize = view;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Material(
        child: Overlay(initialEntries: [
          OverlayEntry(
              builder: (_) => TileOverlay(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox(
                        key: tileKey,
                        width: 360,
                        child: ListView.builder(
                            shrinkWrap: true,
                            itemExtent: 32,
                            itemCount: 7,
                            itemBuilder: (_, i) => Text("pack $i")),
                      ),
                    ]),
                  )),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getRect(find.byKey(tileKey)).right, 790);
  });
}
