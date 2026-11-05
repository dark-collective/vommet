// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';

import 'package:commet/client/client.dart';
import 'package:commet/config/layout_style.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/composer_translation.dart';
import 'package:commet/ui/molecules/message_input.dart';
import 'package:commet/utils/translation/message_translation.dart';
import 'package:commet/utils/translation/room_translation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'translation_fakes.dart';

class _Client implements Client {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  for (final style in LayoutStyle.values) {
    for (final device in ["mobile", "desktop"]) {
      testWidgets("$style $device: active translation hides the room offer", (
        tester,
      ) async {
        SharedPreferences.setMockInitialValues({});
        await preferences.init();
        await preferences.layoutOverride.set(device);
        await (style == LayoutStyle.telegram
                ? LayoutOptions.telegram
                : LayoutOptions.discord)
            .save();
        if (style == LayoutStyle.custom) {
          await preferences.chatBubbleLayout.set(true);
        }
        await layoutStyleCustomPicked.set(style == LayoutStyle.custom);
        tester.view.physicalSize = Size(device == "mobile" ? 412 : 1000, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final dir = Directory.systemTemp.createTempSync("vommet-suggest-ui");
        addTearDown(() => dir.deleteSync(recursive: true));
        final translation = MessageTranslation(
          engine: FakeEngine(),
          baseDirectory: () async => dir,
          specs: [spec("es", "en", {})],
          android: false,
          systemLanguage: () => "en",
        );
        final rooms = RoomTranslation(translation: translation);
        addTearDown(rooms.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: MessageInput(
                  client: _Client(),
                  availibleEmoticons: const [],
                  onSendMessage: (message, {overrideClient}) =>
                      MessageInputSendResult.success,
                ),
              ),
            ),
          ),
        );
        final state = tester.state<MessageInputState>(
          find.byType(MessageInput),
        );
        // Supply the deterministic translation service to the real composer.
        state.composerTranslation = ComposerTranslation(
          roomId: "!room",
          translation: translation,
          rooms: rooms,
          recentTextsFromOthers: () =>
              ["[es] hola", "[es] buenos días", "[es] ¿qué tal?"],
        )..addListener(state.onComposerTranslationChanged);
        state.onComposerTranslationChanged();
        await tester.pumpAndSettle();
        expect(find.byType(ComposerTranslationSuggestion), findsOneWidget);

        await rooms.setTranslateWriting("!room", true);
        await tester.pumpAndSettle();
        expect(find.byType(ComposerTranslationSuggestion), findsNothing);

        await rooms.setTranslateWriting("!room", false);
        await tester.pumpAndSettle();
        expect(find.byType(ComposerTranslationSuggestion), findsOneWidget);

        await rooms.setOn("!room", true);
        await tester.pumpAndSettle();
        expect(find.byType(ComposerTranslationSuggestion), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
