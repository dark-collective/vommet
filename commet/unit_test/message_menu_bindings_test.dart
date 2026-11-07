// Vommet issue 1213: persistence and duplicate-safe rebinding.
import 'package:commet/ui/pages/settings/categories/app/shortcut_settings/message_menu_settings.dart';
import 'package:commet/utils/message_menu_bindings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late MessageMenuBindings bindings;
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    bindings = MessageMenuBindings(prefs);
  });

  test('rebind persists, blocks hidden-action duplicates, clears and resets',
      () async {
    expect(bindings.keys.values, ['R', 'E', 'C', 'D', 'F', 'T']);
    expect(await bindings.set(MessageMenuAction.reply, 'e'), false);
    expect(bindings.keys[MessageMenuAction.edit], 'E');
    expect(await bindings.set(MessageMenuAction.reply, 'x'), true);
    expect(MessageMenuBindings(prefs).keys[MessageMenuAction.reply], 'X');
    for (final invalid in ['', 'RR', 'é', '1']) {
      expect(await bindings.set(MessageMenuAction.reply, invalid), false);
    }
    expect(await bindings.set(MessageMenuAction.edit, null), true);
    expect(bindings.keys[MessageMenuAction.edit], isNull);
    expect(await bindings.set(MessageMenuAction.reply, 'E'), true);
    await bindings.reset();
    expect(prefs.containsKey(MessageMenuBindings.storageKey), false);
    expect(bindings.keys.values, ['R', 'E', 'C', 'D', 'F', 'T']);
    await bindings.set(MessageMenuAction.reply, 'X');
    await bindings.set(MessageMenuAction.reply, 'R');
    expect(prefs.containsKey(MessageMenuBindings.storageKey), false);
  });

  test('invalid storage falls back; duplicate stored keys are disabled',
      () async {
    await prefs.setString(MessageMenuBindings.storageKey, '[]');
    expect(bindings.keys[MessageMenuAction.reply], 'R');
    await prefs.setString(MessageMenuBindings.storageKey, 'broken json');
    expect(bindings.keys[MessageMenuAction.reply], 'R');
    await prefs.setString(MessageMenuBindings.storageKey, '{"reply":"E"}');
    expect(bindings.keys[MessageMenuAction.reply], isNull);
    expect(bindings.keys[MessageMenuAction.edit], isNull);
  });

  testWidgets('settings reject duplicate, save a letter, clear and restore',
      (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
        theme: ThemeData(platform: TargetPlatform.linux),
        home: Scaffold(
            body: SingleChildScrollView(
                child: MessageMenuSettings(bindings: bindings)))));
    await t.tap(find.text('Reply'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '1');
    await t.pumpAndSettle();
    expect(
        t
            .widget<TextButton>(find.widgetWithText(TextButton, 'Submit'))
            .onPressed,
        isNull);
    await t.enterText(find.byType(TextField), 'x');
    await t.pumpAndSettle();
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(find.text('R'), findsOneWidget);
    await t.tap(find.text('Reply'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'e');
    await t.pumpAndSettle();
    expect(find.textContaining('already assigned to Edit'), findsOneWidget);
    expect(
        t
            .widget<TextButton>(find.widgetWithText(TextButton, 'Submit'))
            .onPressed,
        isNull);
    await t.enterText(find.byType(TextField), 'x');
    await t.pumpAndSettle();
    await t.tap(find.text('Submit'));
    await t.pumpAndSettle();
    expect(find.text('X'), findsOneWidget);
    await t.tap(find.text('Reply'));
    await t.pumpAndSettle();
    await t.tap(find.text(MessageMenuSettings.clear));
    await t.pumpAndSettle();
    expect(find.text(MessageMenuSettings.unbound), findsOneWidget);
    await t.tap(find.text(MessageMenuSettings.restore));
    await t.pumpAndSettle();
    expect(find.text('R'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
