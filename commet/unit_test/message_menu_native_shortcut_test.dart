// Vommet issue 1213: drive the registered callback at the platform boundary.
import 'dart:async';

import 'package:commet/main.dart' show preferences;
import 'package:commet/utils/hover_reply_binding.dart';
import 'package:commet/utils/system_wide_shortcuts/system_wide_shortcuts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/atoms/context_menu.dart';

class _Platform extends HotKeyManagerPlatform {
  final events = StreamController<Map<Object?, Object?>>.broadcast();
  final registered = <HotKey>[];

  @override
  Stream<Map<Object?, Object?>> get onKeyEventReceiver => events.stream;

  @override
  Future<void> register(HotKey hotKey) async => registered.add(hotKey);

  @override
  Future<void> unregister(HotKey hotKey) async => registered.remove(hotKey);

  void press(HotKey key) => events.add({
        'type': 'onKeyDown',
        'data': {'identifier': key.identifier},
      });
}

void main() {
  testWidgets('registered native callback defers to the open menu', (t) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    final previous = HotKeyManagerPlatform.instance;
    final platform = _Platform();
    HotKeyManagerPlatform.instance = platform;
    addTearDown(() async {
      HotKeyManagerPlatform.instance = previous;
      await platform.events.close();
    });
    var calls = 0;
    final shortcut = AppShortcut(
      getDisplayName: () => 'Mute',
      callback: () => calls++,
    );
    final key = HotKey(key: PhysicalKeyboardKey.keyR);
    await shortcut.setHotkey(key);
    addTearDown(shortcut.clearHotkey);
    expect(platform.registered, [key]);

    platform.press(key);
    await t.pump();
    expect(calls, 1);
    await t.pumpWidget(MaterialApp(
      theme: ThemeData(platform: TargetPlatform.linux),
      home: Scaffold(
          body: Stack(children: [
        ContextMenuOverlay(globalOffset: const Offset(100, 100), items: [
          ContextMenuItem(
              text: 'Reply', accelerator: () => 'R', onPressed: () {}),
        ]),
      ])),
    ));
    await t.pumpAndSettle();
    platform.press(key);
    await t.pump();
    expect(calls, 1, reason: 'The native callback must defer to the menu');

    await t.pumpWidget(const SizedBox());
    await t.pump();
    platform.press(key);
    await t.pump();
    expect(calls, 2);
    await HoverReplyBinding.capture(() async {
      platform.press(key);
      await t.pump();
      expect(calls, 2, reason: 'The recorder still suppresses native actions');
    });
  });
}
