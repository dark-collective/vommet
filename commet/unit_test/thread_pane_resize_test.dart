import 'package:commet/client/client.dart';
import 'package:commet/client/components/room_component.dart';
import 'package:commet/config/layout_style.dart';
import 'package:commet/config/preferences/preference.dart';
import 'package:commet/config/room_layout_options.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/layout/pane_widths.dart';
import 'package:commet/ui/organisms/room_side_panel/room_side_panel.dart';
import 'package:commet/ui/pages/main/room_chat_layout.dart';
import 'package:commet/ui/pages/settings/categories/app/banner_and_pane_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

// Vommet issue 1189: drive the production layout and edge gestures, with a
// stateful panel double reporting state before its content has rebuilt.
class _Room extends Fake implements Room {
  @override
  T? getComponent<T extends RoomComponent>() => null;
}

class _Panel extends StatefulWidget {
  const _Panel(this.changed, {super.key});
  final ValueChanged<SidePanelState> changed;
  @override
  State<_Panel> createState() => _PanelState();
}

class _PanelState extends State<_Panel> {
  SidePanelState state = SidePanelState.defaultView;
  void show(SidePanelState value) => setState(() {
        state = value;
        widget.changed(value);
      });
  @override
  Widget build(BuildContext context) => switch (state) {
        SidePanelState.nothing => const SizedBox(width: 0),
        SidePanelState.defaultView => SizedBox(
            width: PaneWidths.right.effective,
            child: const Text('Members', key: ValueKey('1189-members'))),
        _ => SizedBox(
            width: state == SidePanelState.threads ? 320 : double.infinity,
            child: Text(state.name, key: const ValueKey('1189-thread'))),
      };
}

final _panel = GlobalKey<_PanelState>();
final _thread = find.byKey(const ValueKey('1189-thread'));
final _chat = find.byKey(const ValueKey('1189-chat'));
Finder get _handle => find.byWidgetPredicate(
    (w) => w is PaneResizeHandle && !identical(w.pane, PaneWidths.right));
const _widthKey = 'vommet_thread_pane_width';

Future<void> _pump(WidgetTester tester, {double width = 1120}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 844);
  await tester.pumpWidget(MaterialApp(
    theme: ThemeDark.theme,
    home: Material(
      child: RoomChatLayout(
        room: _Room(),
        header: const SizedBox(height: 50, child: Text('Room header')),
        chat: const TextField(key: ValueKey('1189-chat')),
        panel: (changed) => _Panel(changed, key: _panel),
      ),
    ),
  ));
  _panel.currentState!.show(SidePanelState.thread);
  await tester.pumpAndSettle();
  expect(_thread, findsOneWidget);
  expect(_chat, findsOneWidget);
  expect(tester.takeException(), isNull);
}

Future<void> _drag(WidgetTester tester, double dx) async {
  expect(_handle, findsOneWidget);
  // Use a second move after gesture recognition to make the delta explicit.
  final gesture = await tester.startGesture(tester.getCenter(_handle));
  await gesture.moveBy(Offset(dx.sign * 25, 0));
  await tester.pump();
  await gesture.moveBy(Offset(dx, 0));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await resizablePanels.set(true);
    await PaneWidths.right.reset();
  });
  tearDown(() async {
    await Preference.preferences?.remove(_widthKey);
  });

  for (final style in LayoutStyle.values) {
    testWidgets('1189 ${style.name}: drag, persist, reopen, reset to automatic',
        (tester) async {
      addTearDown(tester.view.reset);
      await pickLayoutStyle(style);
      if (style == LayoutStyle.custom) {
        await LayoutOptions.discord.save();
        await preferences.chatBubbleLayout.set(true);
      }
      await _pump(tester);
      expect(tester.getSize(_thread).width, 560);
      expect(Preference.preferences!.containsKey(_widthKey), isFalse);
      await _drag(tester, 240); // rightward narrows the right panel
      final dragged = tester.getSize(_thread).width;
      expect(dragged, lessThan(400));
      expect(tester.getSize(_chat).width, greaterThan(700));
      expect(Preference.preferences!.getDouble(_widthKey), dragged);
      expect(PaneWidths.right.effective, 250);
      _panel.currentState!.show(SidePanelState.defaultView);
      await tester.pumpAndSettle();
      expect(find.text('Members'), findsOneWidget);
      expect(tester.takeException(), isNull);
      _panel.currentState!.show(SidePanelState.thread);
      await tester.pumpAndSettle();
      expect(tester.getSize(_thread).width, dragged);
      // Destroy and recreate the layout; the saved width survives.
      await tester.pumpWidget(const SizedBox());
      await _pump(tester, width: 1400);
      expect(tester.getSize(_thread).width, dragged);
      await tester.tap(_handle);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(_handle);
      await tester.pumpAndSettle();
      expect(tester.getSize(_thread).width, 700);
      expect(Preference.preferences!.containsKey(_widthKey), isFalse);
      tester.view.physicalSize = const Size(1600, 844);
      await tester.pumpAndSettle();
      expect(tester.getSize(_thread).width, 800);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  }

  testWidgets('1189: bounds, transient clamp, narrow fallback and visible drag',
      (tester) async {
    addTearDown(tester.view.reset);
    await _pump(tester);
    await _drag(tester, -1000);
    expect(tester.getSize(_chat).width, 400);
    final saved = Preference.preferences!.getDouble(_widthKey);
    expect(saved, 720);
    tester.view.physicalSize = const Size(900, 844);
    await tester.pumpAndSettle();
    expect(tester.getSize(_thread).width, 500);
    expect(Preference.preferences!.getDouble(_widthKey), saved);
    // Start from the clamped visible edge, not the old saved request.
    await _drag(tester, 60);
    expect(tester.getSize(_thread).width, lessThan(470));
    await _drag(tester, 1000);
    expect(tester.getSize(_thread).width, 320);
    tester.view.physicalSize = const Size(680, 844);
    await tester.pumpAndSettle();
    expect(_handle, findsNothing);
    expect(tester.getSize(_thread).width, 340);
    expect(_chat, findsOneWidget);
    expect(Preference.preferences!.getDouble(_widthKey), 320);
    // Close into the hidden member branch, then float/expand it. The
    // GlobalKey must never carry a Flexible into the Stack.
    tester.view.physicalSize = const Size(500, 844);
    await tester.pumpAndSettle();
    final panelState = _panel.currentState;
    _panel.currentState!.show(SidePanelState.defaultView);
    await tester.pumpAndSettle();
    expect(
        RoomChatLayout.toggleFloatingMembers(_panel.currentContext!), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Members'), findsOneWidget);
    RoomChatLayout.setPanelExpanded(_panel.currentContext!, true);
    await tester.pumpAndSettle();
    RoomChatLayout.setPanelExpanded(_panel.currentContext!, false);
    await tester.pumpAndSettle();
    _panel.currentState!.show(SidePanelState.nothing);
    await tester.pumpAndSettle();
    _panel.currentState!.show(SidePanelState.thread);
    await tester.pumpAndSettle();
    expect(identical(panelState, _panel.currentState), isTrue);
    tester.view.physicalSize = const Size(1120, 844);
    await tester.pumpAndSettle();
    expect(tester.getSize(_thread).width, 320);
    // Between 720 and 800 the automatic half-width is outside the manual
    // maximum. A drag must not snap through the main chat's reserve.
    tester.view.physicalSize = const Size(760, 844);
    await tester.pumpAndSettle();
    await _drag(tester, -1000);
    expect(tester.getSize(_thread).width, 360);
    expect(tester.getSize(_chat).width, 400);
    await tester.tap(_handle);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(_handle);
    await tester.pumpAndSettle();
    expect(tester.getSize(_thread).width, 380);
    expect(Preference.preferences!.containsKey(_widthKey), isFalse);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('1189: setting off/on, snap reset and settings reset',
      (tester) async {
    addTearDown(tester.view.reset);
    await _pump(tester);
    await _drag(tester, 1000);
    await resizablePanels.set(false);
    await tester.pumpAndSettle();
    expect(_handle, findsNothing);
    expect(tester.getSize(_thread).width, 560);
    await resizablePanels.set(true);
    await tester.pumpAndSettle();
    expect(tester.getSize(_thread).width, 320);
    await _drag(tester, -240); // snap to the automatic half width
    expect(tester.getSize(_thread).width, 560);
    expect(Preference.preferences!.containsKey(_widthKey), isFalse);
    await _drag(tester, 1000);
    await tester.pumpWidget(MaterialApp(
        theme: ThemeDark.theme,
        home: const Material(child: BannerAndPaneSettings())));
    await tester.tap(find.text('Reset pane widths'));
    await tester.pumpAndSettle();
    expect(Preference.preferences!.containsKey(_widthKey), isFalse);
    await _pump(tester);
    expect(tester.getSize(_thread).width, 560);
    // Disposed layouts no longer receive the new settings subscription.
    await tester.pumpWidget(const SizedBox());
    await resizablePanels.set(false);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  // Controls: the old automatic panel also ignores this new preference.
  // These cases cover the feature's defensive persisted-width fallback;
  // they are not claimed as failures on the unmodified feature-free base.
  for (final invalid in [
    -120.0,
    0.0,
    double.nan,
    double.infinity,
    double.negativeInfinity
  ]) {
    testWidgets('1189 control: invalid saved width $invalid stays automatic',
        (tester) async {
      addTearDown(tester.view.reset);
      await Preference.preferences!.setDouble(_widthKey, invalid);
      await _pump(tester);
      expect(tester.getSize(_thread).width, 560);
      expect(tester.getSize(_chat).width, 560);
      tester.view.physicalSize = const Size(1400, 844);
      await tester.pumpAndSettle();
      expect(tester.getSize(_thread).width, 700);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  }

  for (final interruption in [
    'narrow resize',
    'Resize panels off',
    'thread close',
    'layout disposal'
  ]) {
    testWidgets(
        '1189: unfinished drag interrupted by $interruption restores saved width',
        (tester) async {
      addTearDown(tester.view.reset);
      await _pump(tester);
      await _drag(tester, 1000);
      final saved = Preference.preferences!.getDouble(_widthKey)!;
      final gesture = await tester.startGesture(tester.getCenter(_handle));
      await gesture.moveBy(const Offset(-25, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(-100, 0));
      await tester.pump();
      expect(tester.getSize(_thread).width, greaterThan(saved));
      if (interruption == 'narrow resize') {
        tester.view.physicalSize = const Size(680, 844);
      } else if (interruption == 'Resize panels off') {
        await resizablePanels.set(false);
      } else if (interruption == 'thread close') {
        _panel.currentState!.show(SidePanelState.defaultView);
      } else {
        await tester.pumpWidget(const SizedBox());
      }
      await tester.pumpAndSettle();
      expect(_handle, findsNothing);
      if (interruption == 'narrow resize' ||
          interruption == 'Resize panels off') {
        expect(tester.getSize(_thread).width,
            interruption == 'narrow resize' ? 340 : 560);
      }
      await gesture.up();
      await tester.pumpAndSettle();
      // The gesture's recognizer has been removed. Resuming the panel must
      // use the committed preference, not an abandoned in-memory drag.
      final committed = Preference.preferences!.getDouble(_widthKey)!;
      tester.view.physicalSize = const Size(1120, 844);
      await resizablePanels.set(true);
      if (interruption == 'thread close') {
        _panel.currentState!.show(SidePanelState.thread);
      } else if (interruption == 'layout disposal') {
        await _pump(tester);
      }
      await tester.pumpAndSettle();
      expect(tester.getSize(_thread).width, committed);
      await _drag(tester, -80);
      expect(tester.getSize(_thread).width, greaterThan(committed));
      expect(Preference.preferences!.getDouble(_widthKey),
          tester.getSize(_thread).width);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  }

  testWidgets('1189: explicit pointer cancellation saves the visible drag',
      (tester) async {
    addTearDown(tester.view.reset);
    await _pump(tester);
    final gesture = await tester.startGesture(tester.getCenter(_handle));
    await gesture.moveBy(const Offset(25, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(120, 0));
    await tester.pump();
    final visible = tester.getSize(_thread).width;
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(Preference.preferences!.getDouble(_widthKey), visible);
    await tester.pumpWidget(const SizedBox());
    await _pump(tester);
    expect(tester.getSize(_thread).width, visible);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}
