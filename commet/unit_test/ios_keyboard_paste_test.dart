// ignore_for_file: invalid_use_of_visible_for_testing_member

// Vommet issue 1113: on iPadOS, pasting an image from the on-screen
// keyboard's paste button sends UIKit's `paste:` to the native text input
// view. The iOS runner intercepts this and routes the image bytes to
// Dart via `im.nether.vommet/clipboard` so the attachment preview opens.

import 'package:commet/client/client.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/message_input.dart';
import 'package:commet/ui/organisms/attachment_processor/attachment_processor.dart';
import 'package:commet/utils/image_clipboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

class _FakeClient implements Client {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel("im.nether.vommet/clipboard");

  Future<void> sendPasteImage([Object? arguments]) async {
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec()
          .encodeMethodCall(MethodCall("pasteImage", arguments)),
      (_) {},
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  group("ImageClipboard.listenForPaste", () {
    test("delivers image bytes sent over the clipboard channel", () async {
      Uint8List? received;
      final unlisten = ImageClipboard.listenForPaste((data) {
        received = data;
      });

      final testBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      await sendPasteImage(testBytes);

      expect(received, equals(testBytes));

      unlisten();
    });

    test("calling unlisten removes the listener", () async {
      int count = 0;
      final unlisten = ImageClipboard.listenForPaste((_) {
        count++;
      });

      await sendPasteImage(Uint8List.fromList([10, 20]));
      expect(count, equals(1));

      unlisten();

      await sendPasteImage(Uint8List.fromList([30, 40]));
      expect(count, equals(1));
    });

    test("delivers null when pasteImage has no data payload", () async {
      bool called = false;
      Uint8List? received = Uint8List(1);
      final unlisten = ImageClipboard.listenForPaste((data) {
        called = true;
        received = data;
      });

      await sendPasteImage(null);

      expect(called, isTrue);
      expect(received, isNull);

      unlisten();
    });
  });

  group("MessageInput keyboard paste on iOS", () {
    testWidgets("opens attachment preview when focused", (tester) async {
      await preferences.layoutOverride.set('mobile');
      tester.view.physicalSize = const Size(820, 1180);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MessageInput(
            client: _FakeClient(),
            availibleEmoticons: const [],
          ),
        ),
      ));
      await tester.pump();

      // Focus the input
      final field = find.byType(TextField);
      await tester.tap(field);
      await tester.pump();

      final testPng = img.encodePng(
          img.Image(width: 4, height: 4)..clear(img.ColorRgb8(200, 40, 40)));

      await sendPasteImage(testPng);
      await tester.pump();

      // Attachment preview dialog (AttachmentProcessor) is shown
      final preview = find.byType(AttachmentProcessor);
      expect(preview, findsOneWidget);
      expect(
          tester.widget<AttachmentProcessor>(preview).attachment.data, testPng);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets("ignores paste notification when unfocused", (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const TextField(key: ValueKey("other_field")),
              MessageInput(
                client: _FakeClient(),
                availibleEmoticons: const [],
              ),
            ],
          ),
        ),
      ));
      await tester.pump();

      // Focus the other field, leaving MessageInput unfocused
      await tester.tap(find.byKey(const ValueKey("other_field")));
      await tester.pump();

      final testPng = Uint8List.fromList([1, 2, 3]);
      await sendPasteImage(testPng);
      await tester.pump();

      // No attachment preview dialog opened
      expect(find.byType(AttachmentProcessor), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets("stops listening when disposed", (tester) async {
      final showComposer = ValueNotifier<bool>(true);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: showComposer,
            builder: (context, show, _) => show
                ? MessageInput(
                    client: _FakeClient(),
                    availibleEmoticons: const [],
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ));
      await tester.pump();

      // Focus composer
      await tester.tap(find.byType(TextField));
      await tester.pump();

      // Unmount composer
      showComposer.value = false;
      await tester.pump();

      final testPng = Uint8List.fromList([1, 2, 3]);
      // Should not throw or open dialog
      await sendPasteImage(testPng);
      await tester.pump();

      expect(find.byType(AttachmentProcessor), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  });
}
