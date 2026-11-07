import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/component.dart';
import 'package:commet/config/layout_style.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/message_input.dart';
import 'package:commet/ui/organisms/chat/chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Client extends Fake implements Client {
  @override
  T? getComponent<T extends Component>() => null;
}

class _Composer {
  bool editing = false;
  bool? pending;
  bool failed = false;
  int confirmations = 0;
  int normalSends = 0;
  int cancellations = 0;
  final steps = <bool>[];
  final replies = <bool>[];
  final sendResult = Completer<void>();

  TextEditingController controller(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).controller!;

  Future<void> mount(WidgetTester tester, {double width = 370}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(platform: TargetPlatform.linux),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(1.25)),
          child: child!,
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomLeft,
            child: SizedBox(
              width: width,
              child: StatefulBuilder(
                builder: (context, update) => MessageInput(
                  client: _Client(),
                  availibleEmoticons: const [],
                  interactionType: editing ? EventInteractionType.edit : null,
                  relatedEventBody: 'original',
                  relatedEventSenderName: 'You',
                  stepEditTarget: ({required older, required text}) {
                    steps.add(older);
                    if (editing) update(() => pending = older);
                    return true;
                  },
                  stepReplyTarget: ({required older}) => replies.add(older),
                  editStepOlder: pending,
                  editStepFailed: failed,
                  cancelEditStep: () => update(() => pending = null),
                  confirmEditStep: (text, outgoing) async {
                    confirmations++;
                    await sendResult.future;
                    update(() => failed = true);
                  },
                  cancelReply: () => cancellations++,
                  onSendMessage: (_, {overrideClient}) {
                    normalSends++;
                    return MessageInputSendResult.success;
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  }
}

void main() {
  final linux = TargetPlatformVariant.only(TargetPlatform.linux);
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await preferences.layoutOverride.set('desktop');
  });

  testWidgets('fresh empty Up opens once, Ctrl+Up still repeats replies', (
    tester,
  ) async {
    final composer = _Composer();
    await composer.mount(tester, width: 1000);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
    expect(composer.steps, [true]);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(composer.steps, [true]);
    expect(composer.replies, [true, true]);

    composer.controller(tester).value = const TextEditingValue(
      text: 'unsent draft',
      selection: TextSelection.collapsed(offset: 12),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    expect(composer.controller(tester).text, 'unsent draft');
    expect(composer.steps, [true]);
    await composer.dispose(tester);
  }, variant: linux);

  testWidgets('soft wraps and held arrows move the caret before a fresh step', (
    tester,
  ) async {
    final composer = _Composer()..editing = true;
    await composer.mount(tester);
    final text = List.filled(16, 'wrapped text').join(' ');
    await tester.enterText(find.byType(TextField), text);
    final controller = composer.controller(tester);
    controller.selection = TextSelection.collapsed(offset: text.length);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
    expect(controller.selection.extentOffset, lessThan(text.length));
    for (var i = 0; i < 16; i++) {
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowUp);
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
    expect(composer.steps, isEmpty);
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 3);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    expect(composer.steps, isEmpty);
    controller.value = TextEditingValue(
      text: text,
      selection: const TextSelection.collapsed(offset: 0),
      composing: const TextRange(start: 0, end: 3),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    expect(composer.steps, isEmpty);
    controller.value = TextEditingValue(
      text: text,
      selection: const TextSelection.collapsed(offset: 0),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    expect(composer.steps, [true]);
    await composer.dispose(tester);
  }, variant: linux);

  for (final style in LayoutStyle.values) {
    testWidgets(
      '${style.name}: prompt preserves text on Esc and failed Enter',
      (tester) async {
        await pickLayoutStyle(style);
        final composer = _Composer()..editing = true;
        await composer.mount(tester);
        await tester.enterText(find.byType(TextField), 'my changed text');
        final controller = composer.controller(tester);
        controller.selection =
            TextSelection.collapsed(offset: controller.text.length);
        await tester.pump();
        final selection = controller.selection;
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(composer.steps, [false]);
        expect(find.text('Keep editing'), findsOneWidget);
        controller.selection = const TextSelection.collapsed(offset: 0);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.escape);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
        expect(composer.cancellations, 0);
        expect(controller.text, 'my changed text');
        expect(controller.selection, selection);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        expect(composer.confirmations, 1);
        expect(composer.normalSends, 0);
        composer.sendResult.complete();
        await tester.pump();
        expect(
          find.textContaining('Your changes are still here'),
          findsOneWidget,
        );
        expect(controller.text, 'my changed text');
        await composer.dispose(tester);
      },
      variant: linux,
    );
  }
}
