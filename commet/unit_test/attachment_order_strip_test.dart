import 'package:commet/client/attachment.dart';
import 'package:commet/ui/molecules/attachment_order_strip.dart';
import 'package:commet/ui/organisms/media_send_sheet/media_send_sheet.dart';
import 'package:commet/main.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<PendingFileAttachment> fixtures(int count) => [
      for (var i = 0; i < count; i++)
        PendingFileAttachment(
            name: 'same.pdf', mimeType: 'application/pdf', data: Uint8List(0))
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<PendingFileAttachment> files;
  late StateSetter refresh;
  late List<bool> dragging;
  late int taps;
  late int removes;
  late int parentEscapes;
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    files = fixtures(4);
    dragging = [];
    taps = 0;
    removes = 0;
    parentEscapes = 0;
  });
  Future<void> pump(WidgetTester tester,
      {bool rtl = false, bool enabled = true, double width = 480}) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                    width: width,
                    child: StatefulBuilder(builder: (context, setState) {
                      refresh = setState;
                      return Focus(
                          onKeyEvent: (_, event) {
                            if (event is KeyDownEvent &&
                                event.logicalKey == LogicalKeyboardKey.escape)
                              parentEscapes++;
                            return KeyEventResult.ignored;
                          },
                          child: Directionality(
                              textDirection:
                                  rtl ? TextDirection.rtl : TextDirection.ltr,
                              child: AttachmentOrderStrip(
                                  files: files,
                                  itemWidth: 100,
                                  height: 100,
                                  enabled: enabled,
                                  onMove: (f, p) => setState(() {
                                        files.remove(f);
                                        files.insert(p, f);
                                      }),
                                  onDraggingChanged: dragging.add,
                                  itemBuilder: (index, wrap) =>
                                      Stack(children: [
                                        Positioned(
                                            left: 5,
                                            top: 5,
                                            child: wrap(GestureDetector(
                                                key: ValueKey(
                                                    ('thumb', files[index])),
                                                onTap: () => taps++,
                                                child: Container(
                                                    width: 70,
                                                    height: 48,
                                                    color: Colors.blue)))),
                                        Positioned(
                                            right: 0,
                                            top: 0,
                                            child: IconButton(
                                                key: ValueKey(
                                                    ('remove', files[index])),
                                                icon: const Icon(Icons.close),
                                                onPressed: () => removes++))
                                      ]))));
                    }))))));
    await tester.pumpAndSettle();
  }

  Finder thumb(PendingFileAttachment f) => find.byKey(ValueKey(('thumb', f)));
  testWidgets(
      'mouse drag reorders identity, tap and X retain independent actions',
      (tester) async {
    await pump(tester);
    final first = files.first;
    await tester.tap(thumb(first));
    expect(taps, 1);
    await tester.tap(find.byKey(ValueKey(('remove', first))));
    expect(removes, 1);
    expect(dragging, isEmpty);
    final g = await tester.startGesture(
        tester.getTopLeft(thumb(first)) + const Offset(10, 25),
        kind: PointerDeviceKind.mouse);
    for (var i = 0; i < 5; i++) {
      await g.moveBy(const Offset(46, 0));
      await tester.pump(const Duration(milliseconds: 80));
      if (i == 0) {
        // A second pointer must not activate the lifted tile's old controls.
        await tester.tap(find.byKey(ValueKey(('remove', first))),
            warnIfMissed: false);
        expect(removes, 1);
      }
    }
    await tester.pump(const Duration(milliseconds: 300));
    await g.up();
    await tester.pumpAndSettle();
    expect(files.indexOf(first), 2);
    expect(taps, 1);
    expect(dragging, [true, false]);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'touch scroll before hold does not reorder; holding then dragging does',
      (tester) async {
    files = fixtures(10);
    await pump(tester, width: 320);
    final before = List.of(files);
    await tester.drag(thumb(files[1]), const Offset(-180, 0));
    await tester.pumpAndSettle();
    expect(files, before);
    expect(dragging, isEmpty);
    // Scroll back to the first tile.
    await tester.drag(find.byType(ReorderableList), const Offset(500, 0));
    await tester.pumpAndSettle();
    final first = files.first;
    final g = await tester
        .startGesture(tester.getTopLeft(thumb(first)) + const Offset(10, 25));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await g.moveBy(const Offset(210, 0));
    await tester.pump(const Duration(milliseconds: 350));
    await g.up();
    await tester.pumpAndSettle();
    expect(files.indexOf(first), greaterThan(0));
    expect(dragging, [true, false]);
  });
  testWidgets(
      'RTL remains physically leftmost first; menu and Alt keys reorder',
      (tester) async {
    await pump(tester, rtl: true);
    final first = files.first, second = files[1];
    expect(tester.getCenter(thumb(first)).dx,
        lessThan(tester.getCenter(thumb(second)).dx));
    await tester.tap(find.byType(PopupMenuButton<int>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AttachmentOrderStrip.moveEarlier));
    await tester.pumpAndSettle();
    expect(files.first, second);
    final focus = tester.widget<Focus>(find.byKey(ObjectKey(second)));
    focus.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(files[1], second);
  });
  testWidgets(
      'Escape cancels drag; addition during drag cancels without losing files',
      (tester) async {
    await pump(tester);
    final before = List.of(files);
    final g = await tester.startGesture(
        tester.getTopLeft(thumb(files.first)) + const Offset(10, 25),
        kind: PointerDeviceKind.mouse);
    await g.moveBy(const Offset(150, 0));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await g.up();
    await tester.pumpAndSettle();
    expect(files, before);
    expect(parentEscapes, 0);
    expect(dragging.last, false);
    final g2 = await tester.startGesture(
        tester.getTopLeft(thumb(files.first)) + const Offset(10, 25),
        kind: PointerDeviceKind.mouse);
    await g2.moveBy(const Offset(150, 0));
    await tester.pump();
    final added = fixtures(1).single;
    refresh(() => files.add(added));
    await tester.pumpAndSettle();
    await g2.up();
    await tester.pumpAndSettle();
    expect(files, [...before, added]);
    expect(dragging.last, false);
    expect(tester.takeException(), isNull);
  });
  testWidgets('drop in the same slot releases mutation lock', (tester) async {
    await pump(tester);
    final before = List.of(files);
    final g = await tester.startGesture(
        tester.getTopLeft(thumb(files.first)) + const Offset(10, 25),
        kind: PointerDeviceKind.mouse);
    await g.moveBy(const Offset(18, 0));
    await tester.pump(const Duration(milliseconds: 300));
    await g.up();
    await tester.pumpAndSettle();
    expect(files, before);
    expect(dragging, [true, false]);
  });
  testWidgets('dragging at the edge auto-scrolls to files beyond the viewport',
      (tester) async {
    files = fixtures(15);
    await pump(tester, width: 320);
    final first = files.first;
    final g = await tester.startGesture(
        tester.getTopLeft(thumb(first)) + const Offset(10, 25),
        kind: PointerDeviceKind.mouse);
    await g.moveTo(const Offset(310, 30));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    await g.up();
    await tester.pumpAndSettle();
    expect(files.indexOf(first), greaterThan(2));
    expect(dragging.last, false);
  });
  testWidgets('single item and disabled state cannot start drag',
      (tester) async {
    files = fixtures(1);
    await pump(tester);
    await tester.drag(thumb(files.first), const Offset(150, 0),
        kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(dragging, isEmpty);
    files = fixtures(4);
    await pump(tester, enabled: false);
    await tester.drag(thumb(files.first), const Offset(150, 0),
        kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(dragging, isEmpty);
  });
  testWidgets('phone selection and file identity survive moves and removal',
      (tester) async {
    final initial = fixtures(4);
    await tester.pumpWidget(MaterialApp(home: MediaSendSheet(files: initial)));
    await tester.pumpAndSettle();
    final state =
        tester.state<MediaSendSheetState>(find.byType(MediaSendSheet));
    await tester.tap(find.byKey(const ValueKey(("media-send-tile", 1))));
    await tester.pump();
    final selected = initial[1];
    state.moveFile(initial[0], 3);
    await tester.pumpAndSettle();
    expect(state.current, same(selected));
    state.remove(initial[2]);
    await tester.pumpAndSettle();
    expect(state.current, same(selected));
    expect(state.files, [selected, initial[3], initial[0]]);
  });
}
