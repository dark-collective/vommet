import 'dart:async';

import 'package:commet/client/components/personal_space_order.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/space_menu.dart';
import 'package:commet/ui/pages/arrange_space/arrange_space_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/personal_order_fixtures.dart';

Future<void> moveGeneralUp(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Move general up or down'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Move up'));
  await tester.pumpAndSettle();
}

void main() {
  late ArrangeSpace space;
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    space = personalOrderFixture();
  });
  Future<void> pump(WidgetTester tester, {double scale = 1}) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
        home: ArrangeSpacePage(space)));
    await tester.pumpAndSettle();
  }

  testWidgets('member can arrange with row actions; no write until Save',
      (tester) async {
    await pump(tester);
    expect(space.permissions.canEditChildren, isFalse);
    expect(find.text('@alex:example.org'), findsOneWidget);
    await moveGeneralUp(tester);
    expect(space.writes, 0);
    expect(find.text('Personal order · unsaved'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(space.writes, 1);
    expect(space.personalChildOrder!.first, '!general:example.org');
    expect(space.children.first.id, '!announcements:example.org');
    expect(space.childrenForMe.first.id, '!general:example.org');
    expect(find.text('Personal order saved'), findsOneWidget);
  });
  testWidgets('reset is previewed; Cancel and Save reset have distinct effects',
      (tester) async {
    await pump(tester);
    final before = space.personalChildOrder!.toList();
    await tester.tap(find.text('Reset to space default'));
    await tester.pumpAndSettle();
    expect(space.writes, 0);
    expect(find.text('Space default · preview'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(space.personalChildOrder, before);
    await tester.tap(find.text('Reset to space default'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save reset'));
    await tester.pumpAndSettle();
    expect(space.personalChildOrder, isNull);
    expect(
        space.childrenForMe.map((c) => c.id), space.children.map((c) => c.id));
  });
  testWidgets('failed save retains draft and retry succeeds', (tester) async {
    space.failSave = true;
    await pump(tester);
    await moveGeneralUp(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not save'), findsOneWidget);
    expect(find.text('Personal order · unsaved'), findsOneWidget);
    space.failSave = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(space.personalChildOrder!.first, '!general:example.org');
  });
  testWidgets('incoming edit requires reload before overwriting it',
      (tester) async {
    await pump(tester);
    await moveGeneralUp(tester);
    space.personalChildOrder = ['!lounge:example.org'];
    space.changed();
    await tester.pumpAndSettle();
    expect(find.textContaining('changed elsewhere'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(space.writes, 0);
  });
  testWidgets('a menu opened before sync still moves the selected child',
      (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('Move general up or down'));
    await tester.pumpAndSettle();
    space.personalChildOrder = [
      '!lounge:example.org',
      '!projects:example.org',
      '!general:example.org',
      '!announcements:example.org',
      '!help:example.org'
    ];
    space.changed();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move up'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(space.personalChildOrder!.take(2),
        ['!lounge:example.org', '!general:example.org']);
  });
  testWidgets('save in flight blocks duplicate saves', (tester) async {
    space.pendingSave = Completer<void>();
    await pump(tester);
    await moveGeneralUp(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();
    expect(space.writes, 1);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    space.pendingSave!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Personal order saved'), findsOneWidget);
  });
  testWidgets('200 percent text fits and exposes semantic move actions',
      (tester) async {
    final handle = tester.ensureSemantics();
    try {
      await pump(tester, scale: 2);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
          find.byTooltip('Move general up or down'), 160,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp('general, position 2 of 5')),
          findsOneWidget);
      // The row's menu also supports keyboard activation, avoiding drag gestures.
      await tester.scrollUntilVisible(
          find.byTooltip('Move general up or down'), 160,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.byTooltip('Move general up or down'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    } finally {
      handle.dispose();
    }
  });
  testWidgets('member and admin menus separate personal and shared scope',
      (tester) async {
    await preferences.experimentManageSpaceRooms.set(true);
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      final member = SpaceMenu.entries(context, space);
      expect(member.map((e) => e.label), contains(arrangeForMeLabel));
      expect(
          member.map((e) => e.label), isNot(contains(changeSpaceDefaultLabel)));
      final admin = personalOrderFixture(admin: true);

      final entries = SpaceMenu.entries(context, admin);
      expect(entries.map((e) => e.label),
          containsAll([arrangeForMeLabel, changeSpaceDefaultLabel]));
      return const SizedBox();
    })));
  });
}
