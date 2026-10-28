import 'package:commet/ui/atoms/clickable_gesture_detector.dart';
import 'package:commet/ui/atoms/icon_button.dart' as commet;
import 'package:commet/ui/atoms/room_panel_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/config/style/theme_base.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

// Vommet issue 452: Flutter only shows the hand cursor over buttons and
// InkWells on web (adaptiveClickable); desktop should show it too.
void main() {
  // The cursor the mouse tracker would pick: the first non-deferring mouse
  // region under the pointer.
  Future<MouseCursor> cursorOver(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeBase.theme(ColorScheme.fromSeed(seedColor: Colors.blue)),
      home: Scaffold(body: Center(child: child)),
    ));
    final result = HitTestResult();
    tester.binding.hitTestInView(result,
        tester.getCenter(find.byKey(const Key("target"))), tester.view.viewId);
    for (final entry in result.path) {
      final Object target = entry.target;
      if (target is MouseTrackerAnnotation &&
          target.validForMouseTracker &&
          target.cursor != MouseCursor.defer) {
        return target.cursor;
      }
    }
    return SystemMouseCursors.basic;
  }

  final clickable = <String, Widget Function(void Function()? onTap)>{
    "room list tile": (onTap) => SizedBox(
        key: const Key("target"),
        width: 300,
        child: RoomPanelView(displayName: "Room", onTap: onTap)),
    "tiamat TextButton": (onTap) =>
        tiamat.TextButton("Settings", key: const Key("target"), onTap: onTap),
    "tiamat CircleButton": (onTap) => tiamat.CircleButton(
        key: const Key("target"), icon: Icons.add, onPressed: onTap),
    "material IconButton": (onTap) => IconButton(
        key: const Key("target"),
        icon: const Icon(Icons.add),
        onPressed: onTap),
    "ElevatedButton": (onTap) => ElevatedButton(
        key: const Key("target"), onPressed: onTap, child: const Text("Go")),
    "Switch": (onTap) => Switch(
        key: const Key("target"),
        value: false,
        onChanged: onTap == null ? null : (_) => onTap()),
    "ClickableGestureDetector": (onTap) => ClickableGestureDetector(
        onTap: onTap,
        child: const SizedBox(key: Key("target"), width: 50, height: 50)),
    "ClickableGestureDetector with a menu": (onTap) => ClickableGestureDetector(
        onTap: onTap,
        onSecondaryTap: () {},
        onLongPress: () {},
        child: const SizedBox(key: Key("target"), width: 50, height: 50)),
    "commet IconButton": (onTap) => commet.IconButton(
        key: const Key("target"), icon: Icons.send, onPressed: onTap),
    "ChoiceChip": (onTap) => ChoiceChip(
        key: const Key("target"),
        mouseCursor: WidgetStateMouseCursor.clickable,
        label: const Text("Unread only"),
        selected: false,
        onSelected: onTap == null ? null : (_) => onTap()),
    "DropdownButton": (onTap) => DropdownButton<int>(
        key: const Key("target"),
        mouseCursor: WidgetStateMouseCursor.clickable,
        value: 1,
        items: const [DropdownMenuItem(value: 1, child: Text("One"))],
        onChanged: onTap == null ? null : (_) => onTap()),
  };

  for (final entry in clickable.entries) {
    testWidgets("${entry.key} shows the hand cursor when clickable",
        (tester) async {
      expect(await cursorOver(tester, entry.value(() {})),
          SystemMouseCursors.click);
    });

    testWidgets("${entry.key} keeps the arrow when disabled", (tester) async {
      expect(await cursorOver(tester, entry.value(null)),
          isNot(SystemMouseCursors.click));
    });
  }
}
