import 'dart:async';

import 'package:commet/client/attachment.dart';
import 'package:commet/client/client.dart';
import 'package:commet/client/components/command/command_component.dart';
import 'package:commet/client/components/component.dart';
import 'package:commet/client/components/scheduled_messages/scheduled_messages.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/config/layout_style.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/composer_translation.dart';
import 'package:commet/ui/molecules/message_input.dart';
import 'package:commet/ui/organisms/chat/chat.dart';
import 'package:commet/ui/organisms/scheduled_messages/scheduled_messages_view.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

class _Homeserver extends Fake implements matrix.Client {
  _Homeserver({required this.supportsScheduling});

  bool supportsScheduling;
  bool versionsFail = false;
  int versionCalls = 0;
  Completer<matrix.GetVersionsResponse>? versions;

  @override
  Future<matrix.GetVersionsResponse> getVersions({
    Duration cacheLifetime = const Duration(days: 3),
    bool throwOnUpdateFailure = false,
  }) async {
    versionCalls++;
    if (versionsFail) throw StateError('offline');
    if (versions != null) return versions!.future;
    return matrix.GetVersionsResponse(
      versions: ['v1.11'],
      unstableFeatures: {ScheduledMessages.feature: supportsScheduling},
    );
  }

  @override
  Future<Map<String, Object?>> request(
    matrix.RequestType type,
    String action, {
    dynamic data = '',
    String contentType = 'application/json',
    Map<String, Object?>? query,
  }) async =>
      {'delayed_events': <Object>[]};
}

class _Client implements MatrixClient {
  _Client(this.matrixClient);

  @override
  final _Homeserver matrixClient;

  @override
  T? getComponent<T extends Component>() =>
      T == CommandComponent ? _Commands() as T : null;

  @override
  String get identifier => '@me:example.org';

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Commands extends Fake implements CommandComponent {
  @override
  bool isExecutable(String text) => text.startsWith('/');
}

class _Room implements Room {
  _Room(this.client);

  @override
  final Client client;

  @override
  String get identifier => '!composer:example.org';

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Translation extends ComposerTranslation {
  _Translation()
      : super(roomId: '!composer:example.org', recentTextsFromOthers: () => []);

  bool previewFails = false;

  @override
  Future<String?> prepareSend(BuildContext context, String draft) async =>
      'Nos vemos a las seis';

  @override
  Future<List<({String text, String? to})>?> previewSend(
    BuildContext context,
    String draft,
  ) async =>
      previewFails ? null : [(text: 'Nos vemos a las seis', to: 'es')];
}

void main() {
  for (final style in LayoutStyle.values) {
    for (final desktop in [false, true]) {
      testWidgets(
        '$style ${desktop ? 'desktop' : 'phone'} opens the existing scheduler',
        (tester) async {
          final sent = <String>[];
          await pumpComposer(tester, sent, style: style, desktop: desktop);
          final send = find.byIcon(Icons.send);
          final schedule = find.text(ScheduleStrings.scheduleMessageLabel);
          await tester.longPress(send);
          await tester.pumpAndSettle();
          expect(find.byType(MenuItemButton), findsNothing);
          expect(sent, isEmpty);

          await tester.enterText(find.byType(TextField), 'See you at six');
          await tester.pumpAndSettle();
          final navigator = Navigator.of(tester.element(send));
          if (desktop) {
            await tester.tap(
              send,
              buttons: kSecondaryMouseButton,
              kind: PointerDeviceKind.mouse,
            );
          } else {
            await tester.longPress(send);
          }
          await tester.pumpAndSettle();

          expect(schedule, findsOneWidget);
          expect(
            tester.getBottomRight(schedule).dy,
            lessThan(tester.getTopLeft(send).dy),
          );
          expect(find.text('Preview translation'), findsNothing);
          expect(sent, isEmpty);

          await tester.tap(schedule);
          await tester.pumpAndSettle();
          expect(find.text(ScheduleStrings.schedulePickTitle), findsOneWidget);
          expect(sent, isEmpty);

          await navigator.maybePop();
          await tester.pumpAndSettle();
          final sendFocus = Focus.of(tester.element(send));
          sendFocus.requestFocus();
          await tester.pump();
          await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.f10);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
          await tester.pumpAndSettle();
          expect(schedule, findsOneWidget);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(schedule, findsNothing);
          expect(sendFocus.hasPrimaryFocus, isTrue);

          await tester.longPress(send);
          await tester.pumpAndSettle();
          expect(schedule, findsOneWidget);
          await navigator.maybePop();
          await tester.pumpAndSettle();
          expect(schedule, findsNothing);
          expect(sent, isEmpty);

          await tester.tap(send);
          await tester.pumpAndSettle();
          expect(sent, ['See you at six']);
        },
        variant: TargetPlatformVariant.only(
            desktop ? TargetPlatform.linux : TargetPlatform.android),
      );
    }
  }

  for (final supported in [true, false]) {
    testWidgets(
      'translation preview with scheduler support = $supported',
      (
        tester,
      ) async {
        final sent = <String>[];
        await pumpComposer(tester, sent, supported: supported);
        await tester.enterText(find.byType(TextField), 'See you at six');
        final state =
            tester.state<MessageInputState>(find.byType(MessageInput));
        state.composerTranslation?.dispose();
        state.composerTranslation = _Translation()
          ..onDraftChanged('See you at six')
          ..setParagraphTarget(0, 'es');
        state.onComposerTranslationChanged();
        await tester.pumpAndSettle();

        await tester.longPress(find.byIcon(Icons.send));
        await tester.pumpAndSettle();
        final preview = find.text('Preview translation');
        expect(preview, findsOneWidget);
        expect(
          find.text(ScheduleStrings.scheduleMessageLabel),
          supported ? findsOneWidget : findsNothing,
        );
        expect(find.text('Will send'), findsNothing);

        await tester.tap(preview);
        await tester.pumpAndSettle();
        expect(find.text('Will send'), findsOneWidget);
        expect(find.text('Nos vemos a las seis'), findsOneWidget);
        expect(sent, isEmpty);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }

  testWidgets(
    'holding Send on an unsupported homeserver does not send',
    (
      tester,
    ) async {
      final sent = <String>[];
      await pumpComposer(tester, sent, supported: false);
      await tester.enterText(find.byType(TextField), 'See you at six');
      await tester.pumpAndSettle();

      await tester.longPress(find.byIcon(Icons.send));
      await tester.pumpAndSettle();
      expect(find.byType(MenuItemButton), findsNothing);
      expect(sent, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  testWidgets(
    'confirmed Schedule uses a delayed request, cancellation keeps text',
    (tester) async {
      final sent = <String>[];
      final fixture = await pumpComposer(tester, sent);
      await tester.enterText(find.byType(TextField), 'See you at six');
      await tester.pumpAndSettle();
      expect(Theme.of(tester.element(find.byType(MessageInput))).platform,
          TargetPlatform.android);
      await openScheduler(tester);
      final navigator = Navigator.of(tester.element(find.byType(MessageInput)));
      await navigator.maybePop();
      await tester.pumpAndSettle();
      expect(sent, isEmpty);
      expect(
          tester
              .state<MessageInputState>(find.byType(MessageInput))
              .controller
              .text,
          'See you at six');
      await openScheduler(tester);
      await tester.tap(find.byKey(const ValueKey('schedule-preset-0')));
      await tester.pumpAndSettle();
      expect(sent, ['See you at six']);
      expect(fixture.schedules, hasLength(1));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'failed scheduling restores the draft and shows the existing error',
    (tester) async {
      final fixture = await pumpComposer(tester, []);
      fixture.sendError = const ScheduleException('Server refused schedule');
      await tester.enterText(find.byType(TextField), 'Keep this draft');
      await openScheduler(tester);
      await tester.tap(find.byKey(const ValueKey('schedule-preset-0')));
      await tester.pumpAndSettle();
      expect(find.text(ScheduleStrings.scheduleFailedTitle), findsOneWidget);
      expect(
          tester
              .state<MessageInputState>(find.byType(MessageInput))
              .controller
              .text,
          'Keep this draft');
      expect(fixture.schedules, hasLength(1));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  for (final change in [
    'draft',
    'room',
    'thread',
    'processing',
    'capability'
  ]) {
    testWidgets(
      'picker confirmation rejects changed $change',
      (tester) async {
        final sent = <String>[];
        final fixture = await pumpComposer(tester, sent);
        await tester.enterText(find.byType(TextField), 'Original');
        await openScheduler(tester);
        final state =
            tester.state<MessageInputState>(find.byType(MessageInput));
        switch (change) {
          case 'draft':
            state.controller.text = 'Replacement';
          case 'room':
            fixture.room = _Room(fixture.client);
            await fixture.pump(tester);
          case 'thread':
            fixture.canSchedule = false;
            await fixture.pump(tester);
          case 'processing':
            fixture.processing = true;
            await fixture.pump(tester);
          case 'capability':
            fixture.client.matrixClient.supportsScheduling = false;
            await ScheduledMessages.supported(fixture.client, force: true);
            await tester.pumpAndSettle();
        }
        await tester.tap(find.byKey(const ValueKey('schedule-preset-0')));
        await tester.pumpAndSettle();
        fixture.processing = false;
        await fixture.pump(tester);
        expect(sent, isEmpty);
        expect(fixture.schedules, isEmpty);
        expect(state.controller.text,
            change == 'draft' ? 'Replacement' : 'Original');
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }

  for (final excluded in [
    'thread',
    'edit',
    'forward',
    'files',
    'command',
    'account',
    'blank'
  ]) {
    testWidgets(
      'Send menu excludes scheduling for $excluded',
      (tester) async {
        final sent = <String>[];
        final fixture = await pumpComposer(tester, sent);
        await tester.enterText(find.byType(TextField), 'Original');
        await openSendMenu(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        switch (excluded) {
          case 'thread':
            fixture.canSchedule = false;
          case 'edit':
            fixture.interaction = EventInteractionType.edit;
          case 'forward':
            fixture.forward = true;
          case 'files':
            fixture.attachments = [
              PendingFileAttachment(
                  data: Uint8List.fromList([1]),
                  name: 'file.txt',
                  mimeType: 'text/plain')
            ];
          case 'command':
            await tester.enterText(find.byType(TextField), '/command');
          case 'account':
            tester
                    .state<MessageInputState>(find.byType(MessageInput))
                    .senderOverride =
                _Client(_Homeserver(supportsScheduling: true));
          case 'blank':
            await tester.enterText(find.byType(TextField), '   ');
        }
        await fixture.pump(tester);
        await tester.longPress(find.byIcon(Icons.send));
        await tester.pumpAndSettle();
        expect(find.byType(MenuItemButton), findsNothing);
        expect(sent, isEmpty);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }

  testWidgets(
    'capability loss closes the open menu and releases Back',
    (tester) async {
      final sent = <String>[];
      final fixture = await pumpComposer(tester, sent);
      await tester.enterText(find.byType(TextField), 'Original');
      await openSendMenu(tester);
      final navigator = Navigator.of(tester.element(find.byType(MessageInput)));
      expect(navigator.canPop(), isTrue);
      fixture.client.matrixClient.supportsScheduling = false;
      await ScheduledMessages.supported(fixture.client, force: true);
      await tester.pumpAndSettle();
      expect(find.byType(MenuItemButton), findsNothing);
      expect(navigator.canPop(), isFalse);
      expect(sent, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'outside tap and removal clean up an open Send menu',
    (tester) async {
      final sent = <String>[];
      final fixture = await pumpComposer(tester, sent);
      await tester.enterText(find.byType(TextField), 'Original');
      await openSendMenu(tester);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byType(MenuItemButton), findsNothing);
      await openSendMenu(tester);
      fixture.room = _Room(fixture.client);
      await fixture.pump(tester);
      expect(find.byType(MenuItemButton), findsNothing);
      final navigator = Navigator.of(tester.element(find.byType(MessageInput)));
      expect(navigator.canPop(), isFalse);
      await openSendMenu(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(sent, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'screen reader action opens Send actions without sending',
    (tester) async {
      final sent = <String>[];
      await pumpComposer(tester, sent);
      await tester.enterText(find.byType(TextField), 'Original');
      await tester.pumpAndSettle();
      final node = tester.getSemantics(find.byIcon(Icons.send));
      final data = node.getSemanticsData();
      final actions = data.customSemanticsActionIds ?? <int>[];
      expect(actions, isNotEmpty);
      node.owner!
          .performAction(node.id, SemanticsAction.customAction, actions.first);
      await tester.pumpAndSettle();
      expect(find.text(ScheduleStrings.scheduleMessageLabel), findsOneWidget);
      node.owner!
          .performAction(node.id, SemanticsAction.customAction, actions.first);
      await tester.pumpAndSettle();
      expect(find.text(ScheduleStrings.scheduleMessageLabel), findsOneWidget);
      expect(sent, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  testWidgets(
    'a scheduled attempt during processing never queues an immediate send',
    (tester) async {
      final sent = <String>[];
      final fixture = await pumpComposer(tester, sent);
      await tester.enterText(find.byType(TextField), 'Original');
      await openSendMenu(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      fixture.processing = true;
      await fixture.pump(tester);
      final state = tester.state<MessageInputState>(find.byType(MessageInput));
      ScheduledMessages.runScheduled(
          ScheduleRequest(DateTime(2030)), state.sendMessage);
      await tester.pump(const Duration(milliseconds: 50));
      fixture.processing = false;
      await fixture.pump(tester);
      expect(sent, isEmpty);
      expect(state.controller.text, 'Original');
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  for (final failure in [false, true]) {
    testWidgets(
      'unknown or failed capability stays idle, network error = $failure',
      (tester) async {
        final sent = <String>[];
        final fixture = await pumpComposer(tester, sent);
        await tester.enterText(find.byType(TextField), 'Original');
        await openSendMenu(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        final server = _Homeserver(supportsScheduling: true)
          ..versionsFail = failure;
        if (!failure) server.versions = Completer<matrix.GetVersionsResponse>();
        final account = _Client(server);
        addTearDown(() => ScheduledMessages.forget(account));
        fixture.canSchedule = false;
        await fixture.pump(tester);
        fixture.room = _Room(account);
        fixture.canSchedule = true;
        await fixture.pump(tester);
        for (var press = 0; press < 2; press++) {
          await tester.longPress(find.byIcon(Icons.send));
          await tester.pumpAndSettle();
          expect(find.byType(MenuItemButton), findsNothing);
          expect(sent, isEmpty);
        }
        expect(server.versionCalls, 1);
        if (!failure) {
          server.versions!.complete(matrix.GetVersionsResponse(
              versions: ['v1.11'],
              unstableFeatures: {ScheduledMessages.feature: true}));
          await tester.pumpAndSettle();
          await openSendMenu(tester);
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }

  for (final failure in [false, true]) {
    testWidgets(
      'translation preview completion preserves send intent, error = $failure',
      (tester) async {
        final sent = <String>[];
        await pumpComposer(tester, sent);
        await tester.enterText(find.byType(TextField), 'Original');
        final state =
            tester.state<MessageInputState>(find.byType(MessageInput));
        state.composerTranslation?.dispose();
        state.composerTranslation = _Translation()
          ..previewFails = failure
          ..onDraftChanged('Original')
          ..setParagraphTarget(0, 'es');
        state.onComposerTranslationChanged();
        await tester.pumpAndSettle();
        await openSendMenu(tester);
        await tester.tap(find.text('Preview translation'));
        await tester.pumpAndSettle();
        if (failure) {
          expect(find.text('Will send'), findsNothing);
          expect(state.controller.text, 'Original');
          expect(sent, isEmpty);
        } else {
          expect(find.text('Will send'), findsOneWidget);
          await tester.tap(find.text('Send'));
          await tester.pumpAndSettle();
          expect(sent, ['Nos vemos a las seis']);
          expect(state.controller.text, isEmpty);
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }
  for (final change in ['room', 'thread', 'unmount']) {
    testWidgets('support lookup ignores a changed $change', (tester) async {
      final sent = <String>[];
      final fixture = await pumpComposer(tester, sent);
      await tester.enterText(find.byType(TextField), 'Original');
      await openSendMenu(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      fixture.canSchedule = false;
      await fixture.pump(tester);
      final server = _Homeserver(supportsScheduling: true)
        ..versions = Completer<matrix.GetVersionsResponse>();
      final account = _Client(server);
      addTearDown(() => ScheduledMessages.forget(account));
      fixture.room = _Room(account);
      fixture.canSchedule = true;
      await fixture.pump(tester);
      final pending = tester
          .state<MessageInputState>(find.byType(MessageInput))
          .scheduleMessage();
      switch (change) {
        case 'room':
          fixture.room = _Room(fixture.client);
          await fixture.pump(tester);
        case 'thread':
          fixture.canSchedule = false;
          await fixture.pump(tester);
        case 'unmount':
          await tester.pumpWidget(const SizedBox.shrink());
      }
      server.versions!.complete(matrix.GetVersionsResponse(
          versions: ['v1.11'],
          unstableFeatures: {ScheduledMessages.feature: true}));
      await tester.pumpAndSettle();
      await pending;
      expect(find.text(ScheduleStrings.schedulePickTitle), findsNothing);
      expect(sent, isEmpty);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }
}

Future<_Fixture> pumpComposer(
  WidgetTester tester,
  List<String> sent, {
  LayoutStyle style = LayoutStyle.discord,
  bool desktop = false,
  bool supported = true,
}) async {
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  await preferences.init();
  await preferences.layoutOverride.set(desktop ? 'desktop' : 'mobile');
  await (style == LayoutStyle.telegram
          ? LayoutOptions.telegram
          : LayoutOptions.discord)
      .save();
  if (style == LayoutStyle.custom) {
    await preferences.chatBubbleLayout.set(true);
  }
  await layoutStyleCustomPicked.set(style == LayoutStyle.custom);
  tester.view.physicalSize = Size(desktop ? 1000 : 390, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final fixture = _Fixture(sent, supported: supported, desktop: desktop);
  addTearDown(() => ScheduledMessages.forget(fixture.client));
  await fixture.pump(tester);
  return fixture;
}

class _Fixture {
  _Fixture(this.sent, {required bool supported, required this.desktop})
      : client = _Client(_Homeserver(supportsScheduling: supported)) {
    room = _Room(client);
  }

  final List<String> sent;
  final _Client client;
  final bool desktop;
  late Room room;
  bool canSchedule = true;
  bool processing = false;
  bool forward = false;
  EventInteractionType? interaction;
  List<PendingFileAttachment>? attachments;
  Object? sendError;
  final schedules = <ScheduleRequest>[];

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeDark.theme.copyWith(
        platform: desktop ? TargetPlatform.linux : TargetPlatform.android,
      ),
      home: Scaffold(
        body: Column(children: [
          const Expanded(child: SizedBox()),
          MessageInput(
            client: client,
            room: room,
            canSchedule: canSchedule,
            isProcessing: processing,
            interactionType: interaction,
            relatedEventSenderName: interaction == null ? null : 'Me',
            relatedEventBody: interaction == null ? null : 'Earlier text',
            hasPendingForward: forward,
            attachments: attachments,
            availibleEmoticons: const [],
            onSendMessage: (message, {overrideClient}) {
              sent.add(message);
              final schedule = ScheduledMessages.currentRequest;
              if (schedule != null) {
                schedules.add(schedule);
                if (sendError == null) {
                  schedule.done.complete('scheduled');
                } else {
                  schedule.done.completeError(sendError!);
                }
              }
              return MessageInputSendResult.success;
            },
          ),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
  }
}

Future<void> openSendMenu(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.longPress(find.byIcon(Icons.send));
  await tester.pumpAndSettle();
  expect(find.text(ScheduleStrings.scheduleMessageLabel), findsOneWidget);
}

Future<void> openScheduler(WidgetTester tester) async {
  await openSendMenu(tester);
  await tester.tap(find.text(ScheduleStrings.scheduleMessageLabel));
  await tester.pumpAndSettle();
  expect(find.text(ScheduleStrings.schedulePickTitle), findsOneWidget);
}
