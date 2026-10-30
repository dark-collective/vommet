import 'dart:io' show Platform;

import 'package:commet/ui/atoms/primary_selection_field.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PrimarySelectionField.insert', () {
    test('inserts at the offset and puts the cursor after the text', () {
      final value = PrimarySelectionField.insert(
          const TextEditingValue(text: 'hello world'), 6, 'big ');
      expect(value.text, 'hello big world');
      expect(value.selection, const TextSelection.collapsed(offset: 10));
    });

    test('clamps an offset outside the text', () {
      expect(
          PrimarySelectionField.insert(
                  const TextEditingValue(text: 'ab'), -1, 'x')
              .text,
          'xab');
      expect(
          PrimarySelectionField.insert(
                  const TextEditingValue(text: 'ab'), 9, 'x')
              .text,
          'abx');
    });
  });

  group('PrimarySelectionField on Linux', () {
    const channel = MethodChannel('im.nether.vommet/clipboard');
    final calls = <MethodCall>[];

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'readPrimary' ? 'pasted ' : true;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    Future<TextEditingController> pump(WidgetTester tester,
        {bool enabled = true, ValueChanged<String>? onChanged}) async {
      final controller = TextEditingController(text: 'one two');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PrimarySelectionField(
            controller: controller,
            enabled: enabled,
            onChanged: onChanged,
            child: TextField(controller: controller),
          ),
        ),
      ));
      return controller;
    }

    Future<void> middleClick(WidgetTester tester, Offset at) async {
      final gesture = await tester.startGesture(at,
          kind: PointerDeviceKind.mouse, buttons: kMiddleMouseButton);
      await gesture.up();
      await tester.pumpAndSettle();
    }

    testWidgets('selecting text sets the primary selection', (tester) async {
      final controller = await pump(tester);
      controller.selection =
          const TextSelection(baseOffset: 4, extentOffset: 7);
      await tester.pump();
      expect(calls.single.method, 'setPrimary');
      expect(calls.single.arguments, 'two');
    });

    testWidgets('middle-click pastes the primary selection', (tester) async {
      String? changed;
      final controller = await pump(tester, onChanged: (t) => changed = t);
      await middleClick(tester, tester.getTopLeft(find.byType(TextField)));
      expect(calls.map((c) => c.method), contains('readPrimary'));
      expect(controller.text, 'pasted one two');
      expect(changed, 'pasted one two');
    });

    testWidgets('a read-only field ignores middle-click', (tester) async {
      final controller = await pump(tester, enabled: false);
      await middleClick(tester, tester.getCenter(find.byType(TextField)));
      expect(calls, isEmpty);
      expect(controller.text, 'one two');
    });
  }, skip: !Platform.isLinux);
}
