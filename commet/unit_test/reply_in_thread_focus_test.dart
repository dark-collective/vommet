import 'dart:async';
import 'dart:convert';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/account_switch_prefix/account_switch_prefix.dart';
import 'package:commet/client/components/component.dart';
import 'package:commet/client/components/emoticon/emoji_pack.dart';
import 'package:commet/client/components/emoticon/emoticon.dart';
import 'package:commet/client/components/emoticon/emoticon_component.dart';
import 'package:commet/client/components/gif/gif_search_result.dart';
import 'package:commet/client/components/profile/profile_component.dart';
import 'package:commet/client/components/room_component.dart';
import 'package:commet/client/error_profile.dart';
import 'package:commet/client/matrix/components/emoticon/matrix_emoticon.dart';
import 'package:commet/client/matrix/components/emoticon/matrix_room_emoticon_component.dart';
import 'package:commet/client/matrix/components/gif/matrix_gif_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/matrix/matrix_room_replacement.dart';
import 'package:commet/client/matrix/matrix_timeline.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event_unknown.dart';
import 'package:commet/client/permissions.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/config/layout_style.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/message_input.dart';
import 'package:commet/ui/organisms/chat/chat.dart';
import 'package:commet/ui/organisms/room_side_panel/room_side_panel.dart';
import 'package:commet/ui/pages/main/main_page.dart';
import 'package:commet/utils/chat_navigation.dart';
import 'package:commet/utils/emoji/unicode_emoji.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

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
  _Client([this.identifier = "client"]);

  @override
  final String identifier;

  @override
  Profile? self;

  AccountSwitchPrefix? accountSwitchPrefix;

  @override
  int? get maxFileSize => null;

  @override
  T? getComponent<T extends Component>() =>
      accountSwitchPrefix is T ? accountSwitchPrefix as T : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => _quiet(invocation);
}

class _AccountSwitchPrefix extends Fake implements AccountSwitchPrefix {
  _AccountSwitchPrefix(this.target);
  final Client target;

  @override
  (Client, SendAsPattern)? getPrefixedAccount(String text, Room currentRoom) {
    const pattern = SendAsPattern(before: 'other:');
    return pattern.matches(text) ? (target, pattern) : null;
  }
}

class _Room implements Room {
  _Room([String accountId = "client"]) : _client = _Client(accountId);

  final _Client _client;

  @override
  Client get client => _client;

  @override
  String get identifier => "!room:x";

  @override
  String get localId => "${client.identifier}:$identifier";

  @override
  String get displayName => "Room";

  @override
  bool get isE2EE => false;

  @override
  Timeline? get timeline => null;

  @override
  Permissions get permissions => _Permissions();

  @override
  Future<Timeline> getTimeline(
          {String? contextEventId, Object? holder, bool followShown = false}) =>
      Completer<Timeline>().future;

  final _emoticons = _Emoticons();

  @override
  T? getComponent<T extends RoomComponent>() =>
      _emoticons is T ? _emoticons as T : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => _quiet(invocation);
}

class _NavigationPage extends Fake
    with Diagnosticable
    implements MainPageState {
  _NavigationPage([String accountId = "client"])
      : currentRoom = _Room(accountId);

  @override
  final Room currentRoom;
}

const _mediaUrl = 'mxc://example.org/media';
const _sentId = r'$sent';
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);
final _gif =
    base64Decode('R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7');

class _SendDatabase implements matrix.DatabaseApi {
  // No local echo persistence in this fixture. Room.sendEvent still builds
  // the real relation and sends the event over the SDK's HTTP transport.
  @override
  Future<void> transaction(Future<void> Function() action) async {}

  @override
  int get maxFileSize => 0;

  @override
  Future<matrix.Event?> getEventById(String eventId, matrix.Room room) async =>
      null;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _SendSdk extends matrix.Client {
  _SendSdk(http.Client server)
      : super(
          'thread-media-test',
          database: _SendDatabase(),
          httpClient: server,
        ) {
    baseUri = Uri.parse('https://example.org');
    bearerToken = 'fixture';
  }

  @override
  String get userID => '@me:example.org';

  @override
  bool isLogged() => false;
}

class _MediaClient extends _Client implements MatrixClient {
  _MediaClient(this.matrixClient);

  @override
  final matrix.Client matrixClient;

  @override
  matrix.Client getMatrixClient() => matrixClient;

  @override
  List<Space> get spaces => [];

  late final gifs = MatrixGifComponent(this);

  @override
  T? getComponent<T extends Component>() => gifs is T ? gifs as T : null;
}

class _SendTimeline extends Fake implements MatrixTimeline {
  @override
  matrix.Timeline? get matrixTimeline => null;
}

class _MediaRoom extends _Room implements MatrixRoom {
  _MediaRoom(matrix.Client sdk)
      : client = _MediaClient(sdk),
        matrixRoom = matrix.Room(id: '!room:x', client: sdk);

  @override
  final _MediaClient client;

  @override
  final matrix.Room matrixRoom;

  @override
  late final RoomReplacement replacement = MatrixRoomReplacement(this);

  @override
  Timeline? timeline;

  late final stickers = MatrixRoomEmoticonComponent(client, this);
  late Completer<void> converted;

  @override
  T? getComponent<T extends RoomComponent>() =>
      stickers is T ? stickers as T : null;

  @override
  TimelineEvent convertEvent(matrix.Event event, {matrix.Timeline? timeline}) {
    converted.complete();
    return MatrixTimelineEventUnknown(event, client: client);
  }
}

class _Sticker extends MatrixEmoticon {
  _Sticker(matrix.Client client)
      : super(
          Uri.parse(_mediaUrl),
          client,
          shortcode: 'cat',
          usage: EmoticonUsage.sticker,
          packUsage: EmoticonUsage.sticker,
        );

  // Decode fixture pixels locally. The sticker send still resolves MIME type
  // from the MXC and builds its actual event payload.
  @override
  ImageProvider<Object> get image => MemoryImage(_png);
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

  final linux = TargetPlatformVariant.only(TargetPlatform.linux);

  // Vommet issue 1068: an account switch can replace the composer in the
  // frame before the target thread is routed.
  testWidgets('account switch routes the thread after the composer unmounts',
      (tester) async {
    final navigation = ChatNavigation();
    addTearDown(navigation.dispose);
    final threads = <(String, String, String)>[];
    final threadSub = navigation.openThread.stream.listen(threads.add);
    addTearDown(threadSub.cancel);
    const root = r'$root';
    var showComposer = true;
    late StateSetter updateComposer;
    final room = _Room();
    room._client.accountSwitchPrefix =
        _AccountSwitchPrefix(_Client('other')..self = ErrorProfile());
    await tester.pumpWidget(MaterialApp(
        theme: ThemeDark.theme,
        home: Scaffold(
            body: ChatNavigationScope(
                navigation: navigation,
                child: StatefulBuilder(builder: (context, setState) {
                  updateComposer = setState;
                  if (!showComposer) return const SizedBox();
                  return Chat(room, threadId: root);
                })))));
    final rooms = <(String?, String)>[];
    final roomSub = navigation.openRoom.stream.listen((args) {
      rooms.add((args.clientId, args.roomId));
      updateComposer(() => showComposer = false);
    });
    addTearDown(roomSub.cancel);

    final chat = find.byType(Chat);
    await tester.enterText(find.byType(EditableText), 'other: hello');
    await tester.pump();
    await tester.tap(find.text('Sending as: Error'));
    await tester.pump();
    expect(chat, findsNothing);
    expect(rooms, [('other', room.identifier)]);
    expect(tester.takeException(), isNull);
    expect(threads, [('other', room.identifier, root)]);
    await settle(tester);
  }, variant: linux);

  testWidgets('panel highlight cleanup tolerates workspace disposal',
      (tester) async {
    await preferences.hideRoomSidePanel.set(true);
    final navigation = ChatNavigation();
    addTearDown(navigation.dispose);
    final page = _NavigationPage();
    await tester.pumpWidget(MaterialApp(
        theme: ThemeDark.theme,
        home: Scaffold(
            body: ChatNavigationScope(
                navigation: navigation, child: RoomSidePanel(state: page)))));
    navigation.openThreadFor(('client', '!room:x', r'$root'));
    await tester.pump();
    await tester.pump();
    expect(navigation.openThreadRootId.value, r'$root');

    // The workspace owner disposes navigation once the subtree is gone.
    tester.binding.addPostFrameCallback((_) => navigation.dispose());
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
    await settle(tester);
  }, variant: linux);

  testWidgets('only the target account consumes and reopens a pending thread',
      (tester) async {
    await preferences.hideRoomSidePanel.set(true);
    final navigation = ChatNavigation();
    addTearDown(navigation.dispose);
    const root = r'$root';
    const room = '!room:x';
    Widget page(String account) => MaterialApp(
        theme: ThemeDark.theme,
        home: Scaffold(
            body: ChatNavigationScope(
                navigation: navigation,
                child: RoomSidePanel(
                    key: ValueKey(account), state: _NavigationPage(account)))));

    navigation.setPendingThread(room, root,
        clientId: 'other', eventId: r'$one');
    await tester.pumpWidget(page('client'));
    navigation.doOpenRoom(room, clientId: 'client', threadId: root);
    await tester.pump();
    expect(find.byType(Chat), findsNothing);

    await tester.pumpWidget(page('other'));
    await tester.pump();
    final thread = find.byType(Chat);
    final first = tester.widget<Chat>(thread);
    expect(first.threadId, root);
    expect(first.room.client.identifier, 'other');

    navigation.setPendingThread(room, root,
        clientId: 'other', eventId: r'$two');
    navigation.doOpenRoom(room, clientId: 'other', threadId: root);
    await tester.pump();
    expect(tester.widget<Chat>(thread).threadId, root);
    expect(tester.widget<Chat>(thread).key, isNot(first.key));
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  }, variant: linux);

  for (final style in LayoutStyle.values) {
    for (final size in [const Size(1440, 900), const Size(390, 844)]) {
      // Vommet issue 1068: actual Chat/MessageInput and RoomSidePanel consumers.
      testWidgets(
          'reply focus stays in its workspace and survives sibling removal $style $size',
          (tester) async {
        await pickLayoutStyle(style);
        await preferences.layoutOverride
            .set(size.width < 600 ? 'mobile' : 'desktop');
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final first = ChatNavigation();
        final second = ChatNavigation();
        Widget workspace(ChatNavigation nav, String key) => Expanded(
            child: ChatNavigationScope(
                key: ValueKey(key),
                navigation: nav,
                child: Chat(_Room(), threadId: r'$root')));
        Widget page({bool both = true}) => MaterialApp(
            theme: ThemeDark.theme,
            home: Scaffold(
                body: Flex(
                    direction:
                        size.width < 600 ? Axis.vertical : Axis.horizontal,
                    children: [
                  workspace(first, 'first'),
                  if (both) workspace(second, 'second')
                ])));
        await tester.pumpWidget(page());
        await tester.pump();
        first.openThreadFor(('client', '!room:x', r'$root'), reply: true);
        await tester.pump();
        expect(
            ChatNavigationScope.read(
                FocusManager.instance.primaryFocus!.context!),
            same(first));
        await tester.pumpWidget(page(both: false));
        await tester.pump();
        first.openThreadFor(('client', '!room:x', r'$root'), reply: true);
        await tester.pump();
        expect(
            ChatNavigationScope.read(
                FocusManager.instance.primaryFocus!.context!),
            same(first));
        await tester.pumpWidget(const SizedBox());
        await settle(tester);
        first.dispose();
        second.dispose();
      }, variant: linux);

      testWidgets(
          'thread panels, highlights and close are workspace-local $style $size',
          (tester) async {
        await preferences.hideRoomSidePanel.set(true);
        await pickLayoutStyle(style);
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final first = ChatNavigation();
        final second = ChatNavigation();
        final pages = [_NavigationPage(), _NavigationPage()];
        Widget workspace(ChatNavigation nav, int index) => Expanded(
            child: ChatNavigationScope(
                key: ValueKey(index),
                navigation: nav,
                child: RoomSidePanel(state: pages[index])));
        Widget page({bool both = true}) => MaterialApp(
            theme: ThemeDark.theme,
            home: Scaffold(
                body: Flex(
                    direction:
                        size.width < 600 ? Axis.vertical : Axis.horizontal,
                    children: [
                  workspace(first, 0),
                  if (both) workspace(second, 1)
                ])));
        await tester.pumpWidget(page());
        first.openThreadFor(('client', '!room:x', r'$first'));
        await tester.pump();
        await tester.pump();
        expect(find.byType(Chat), findsOneWidget);
        expect(tester.widget<Chat>(find.byType(Chat)).threadId, r'$first');
        expect(first.openThreadRootId.value, r'$first');
        expect(second.openThreadRootId.value, isNull);
        second.openThreadFor(('client', '!room:x', r'$second'));
        await tester.pump();
        await tester.pump();
        expect(find.byType(Chat), findsNWidgets(2));
        first.closeThread.add(null);
        await tester.pump();
        await tester.pump();
        expect(find.byType(Chat), findsOneWidget);
        expect(tester.widget<Chat>(find.byType(Chat)).threadId, r'$second');
        first.openThreadFor(('client', '!room:x', r'$second'));
        await tester.pump();
        await tester.pump();
        await tester.pumpWidget(page(both: false));
        await tester.pump();
        expect(first.openThreadRootId.value, r'$second',
            reason: 'sibling disposal must not clear this highlight');
        await tester.pumpWidget(const SizedBox());
        await settle(tester);
        first.dispose();
        second.dispose();
      }, variant: linux);
    }
  }

  for (final media in ['sticker', 'GIF search result', 'saved GIF']) {
    testWidgets('$media uses the thread relation only in the thread composer', (
      tester,
    ) async {
      final emojiPacks = UnicodeEmojis.packs;
      UnicodeEmojis.packs = [];
      addTearDown(() => UnicodeEmojis.packs = emojiPacks);
      final sends = <http.Request>[];
      final uploads = <http.Request>[];
      final server = MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/cat.gif')) return http.Response.bytes(_gif, 200);
        if (path.contains('/download/')) return http.Response.bytes(_png, 200);
        final Object body;
        if (path.endsWith('/versions')) {
          body = {
            'versions': ['v1.10'],
          };
        } else if (path.endsWith('/config')) {
          body = {};
        } else if (path.endsWith('/upload')) {
          uploads.add(request);
          body = {'content_uri': _mediaUrl};
        } else if (path.contains('/send/')) {
          sends.add(request);
          body = {'event_id': _sentId};
        } else if (path.contains('/event/')) {
          final send = sends.last;
          body = {
            'event_id': _sentId,
            'type': send.url.pathSegments.reversed.skip(1).first,
            'sender': '@me:example.org',
            'origin_server_ts': 1,
            'room_id': '!room:x',
            'content': jsonDecode(send.body),
          };
        } else {
          throw StateError('Unexpected request: ${request.url}');
        }
        return http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final sdk = (await tester.runAsync(() async => _SendSdk(server)))!;
      addTearDown(() => sdk.dispose(closeDatabase: false));
      const root = r'$root';
      final gifUrl = Uri.parse('https://gif.example.org/cat.gif');
      final room = _MediaRoom(sdk);
      await preferences.stickerCompatibilityMode.set(media != 'sticker');

      for (final threadId in [null, root]) {
        await tester.pumpWidget(MaterialApp(
            home: Scaffold(
                body:
                    Chat(room, key: ValueKey(threadId), threadId: threadId))));
        final input = tester.widget<MessageInput>(find.byType(MessageInput));
        room.timeline = _SendTimeline();
        await tester.runAsync(() async {
          room.converted = Completer<void>();
          switch (media) {
            case 'sticker':
              input.sendSticker!(_Sticker(sdk));
              await room.converted.future.timeout(const Duration(seconds: 5));
            case 'GIF search result':
              final gif = GifSearchResult(gifUrl, gifUrl, 1, 1, 'image/gif');
              await input.sendGif!(gif).timeout(const Duration(seconds: 5));
            case 'saved GIF':
              await input.sendFavoriteGif!(MatrixFavoriteGif(room.client, {
                'body': 'cat.mp4',
                'url': _mediaUrl,
                'msgtype': 'm.video',
                'info': {'mimetype': 'video/mp4', 'w': 1, 'h': 1},
              }))
                  .timeout(const Duration(seconds: 5));
          }
        });
        room.timeline = null;
        final send = sends.removeLast();
        final content = jsonDecode(send.body) as Map<String, dynamic>;
        final type = send.url.pathSegments.reversed.skip(1).first;
        expect(content['url'], _mediaUrl);
        if (media == 'sticker') {
          expect(type, matrix.EventTypes.Sticker);
          expect(content['body'], 'cat.png');
          expect(content['info'], {'w': 1, 'h': 1, 'mimetype': 'image/png'});
          expect(uploads, isEmpty);
        } else if (media == 'GIF search result') {
          expect(type, matrix.EventTypes.Message);
          expect(content['body'], 'cat.gif');
          expect(content['msgtype'], 'm.image');
          expect(content['info'], {
            'chat.commet.animated': true,
            'w': 1,
            'h': 1,
            'mimetype': 'image/gif',
          });
          final upload = uploads.removeLast();
          expect(upload.bodyBytes, _gif);
          expect(upload.headers['content-type'], 'image/gif');
        } else {
          expect(type, matrix.EventTypes.Message);
          expect(content['body'], 'cat.mp4');
          expect(content['msgtype'], 'm.video');
          expect(content['info'], {'mimetype': 'video/mp4', 'w': 1, 'h': 1});
          expect(uploads, isEmpty);
        }
        expect(
          content['m.relates_to'],
          threadId == null
              ? isNull
              : {
                  'rel_type': 'm.thread',
                  'event_id': root,
                  'is_falling_back': true,
                },
        );
        await settle(tester);
      }
    });
  }
}
