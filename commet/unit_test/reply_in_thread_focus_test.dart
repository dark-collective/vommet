import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/component.dart';
import 'package:commet/client/components/emoticon/emoji_pack.dart';
import 'package:commet/client/components/emoticon/emoticon_component.dart';
import 'package:commet/client/components/room_component.dart';
import 'package:commet/client/permissions.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/organisms/chat/chat.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Members a fake doesn't spell out: event streams (onUpdate...) never fire,
// flags (isBanned, canX, hasX) are false, anything else is null.
dynamic _quiet(Invocation invocation) {
  if (!invocation.isGetter) return null;
  final name = "${invocation.memberName}".split('"')[1];
  if (RegExp(r"^on[A-Z]").hasMatch(name)) return const Stream<Never>.empty();
  if (RegExp(r"^(is|can|has)[A-Z]").hasMatch(name)) return false;
  return null;
}

class _Permissions extends Permissions {
  @override
  bool get canSendMessage => true;
}

class _Emoticons implements RoomEmoticonComponent {
  @override
  List<EmoticonPack> get availableEmoji => [];

  @override
  List<EmoticonPack> get availableStickers => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => _quiet(invocation);
}

// A client and room with no components but emoji; the timeline never finishes loading.
class _Client implements Client {
  @override
  String get identifier => "client";

  @override
  int? get maxFileSize => null;

  @override
  T? getComponent<T extends Component>() => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => _quiet(invocation);
}

class _Room implements Room {
  final _client = _Client();

  @override
  Client get client => _client;

  @override
  String get identifier => "!room:x";

  @override
  String get localId => "client:!room:x";

  @override
  String get displayName => "Room";

  @override
  bool get isE2EE => false;

  @override
  Timeline? get timeline => null;

  @override
  Permissions get permissions => _Permissions();

  @override
  Future<Timeline> getTimeline({String? contextEventId}) =>
      Completer<Timeline>().future;

  final _emoticons = _Emoticons();

  @override
  T? getComponent<T extends RoomComponent>() =>
      _emoticons is T ? _emoticons as T : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => _quiet(invocation);
}

// Vommet issue 322: "Reply in Thread" puts the cursor in the thread's message
// box, even with "Autofocus Message Input" off (Android's default).
void main() {
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await preferences.autoFocusMessageTextBox.set(false);
  });

  // The room's message box has the focus, then the thread's view opens.
  Future<FocusNode> pumpChat(WidgetTester tester,
      {String? threadId, bool focusMessageInput = false}) async {
    final room = FocusNode(debugLabel: "room");
    addTearDown(room.dispose);
    Widget page({required bool thread}) => MaterialApp(
          home: Scaffold(
            body: Column(children: [
              TextField(focusNode: room),
              if (thread)
                Expanded(
                  child: Chat(_Room(),
                      threadId: threadId, focusMessageInput: focusMessageInput),
                ),
            ]),
          ),
        );

    await tester.pumpWidget(page(thread: false));
    room.requestFocus();
    await tester.pump();
    await tester.pumpWidget(page(thread: true));
    await tester.pump();
    return room;
  }

  // Lets the message box's timers (keyboard height debounce) run out.
  Future<void> settle(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 2));

  bool chatInputFocused(WidgetTester tester) {
    final focused = FocusManager.instance.primaryFocus?.context;
    return focused != null &&
        focused.findAncestorWidgetOfExactType<Chat>() != null;
  }

  testWidgets("a thread opened for a reply focuses its message box",
      (tester) async {
    final room =
        await pumpChat(tester, threadId: "\$root", focusMessageInput: true);

    expect(chatInputFocused(tester), isTrue);
    expect(room.hasFocus, isFalse);
    await settle(tester);
  });

  testWidgets("a thread opened to read leaves the focus alone", (tester) async {
    final room = await pumpChat(tester, threadId: "\$root");

    expect(chatInputFocused(tester), isFalse);
    expect(room.hasFocus, isTrue);
    await settle(tester);
  });

  testWidgets("Reply in Thread focuses the open thread's message box",
      (tester) async {
    await pumpChat(tester, threadId: "\$root");

    EventBus.replyInThread.add("\$other");
    await tester.pump();
    expect(chatInputFocused(tester), isFalse);

    EventBus.replyInThread.add("\$root");
    await tester.pump();
    expect(chatInputFocused(tester), isTrue);
    await settle(tester);
  });
}
