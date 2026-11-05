// Vommet (operator report 2026-11-03): Discord's unread rule for
// "Mentions only" and muted rooms, through the real MatrixRoom push rule.
import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/room_unread_source.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_model.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_source.dart';
import 'package:commet/utils/notification_utils.dart';
import 'package:commet/utils/unread_index.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:shared_preferences/shared_preferences.dart';
import 'roomlist_fixture.dart';

const _room = '!room:example.com';
const _room2 = '!room2:example.com';
const _space = '!space:example.com';

/// Muted rooms get an override rule, mentions-only ones a room rule; the
/// user mention rule follows them, as on the server.
matrix.BasicEvent _ruleSet({
  List<String> muted = const [],
  List<String> mentionsOnly = const [],
  bool userMention = false,
}) =>
    matrix.BasicEvent(
      type: 'm.push_rules',
      content: {
        'global': {
          'override': [
            for (final id in muted)
              {
                'rule_id': id,
                'default': false,
                'enabled': true,
                'conditions': [
                  {'kind': 'event_match', 'key': 'room_id', 'pattern': id},
                ],
                'actions': ['dont_notify'],
              },
            if (userMention) ..._mentionRules,
          ],
          'room': [
            for (final id in mentionsOnly)
              {
                'rule_id': id,
                'default': false,
                'enabled': true,
                'actions': ['dont_notify'],
              },
          ],
        },
      },
    );

const _highlight = [
  'notify',
  {'set_tweak': 'highlight'},
];

/// The server's default mention rules, after any user-defined override.
const _mentionRules = [
  {
    'rule_id': '.m.rule.is_user_mention',
    'default': true,
    'enabled': true,
    'conditions': [
      {
        'kind': 'event_property_contains',
        'key': r'content.m\.mentions.user_ids',
        'value': me,
      },
    ],
    'actions': _highlight,
  },
  {
    'rule_id': '.m.rule.contains_display_name',
    'default': true,
    'enabled': true,
    'conditions': [
      {'kind': 'contains_display_name'},
    ],
    'actions': _highlight,
  },
  {
    'rule_id': '.m.rule.is_room_mention',
    'default': true,
    'enabled': true,
    'conditions': [
      {
        'kind': 'event_property_is',
        'key': r'content.m\.mentions.room',
        'value': true,
      },
      {'kind': 'sender_notification_permission', 'key': 'room'},
    ],
    'actions': _highlight,
  },
  {
    'rule_id': '.m.rule.roomnotif',
    'default': true,
    'enabled': true,
    'conditions': [
      {'kind': 'event_match', 'key': 'content.body', 'pattern': '@room'},
      {'kind': 'sender_notification_permission', 'key': 'room'},
    ],
    'actions': _highlight,
  },
];

/// My display name and bob's right to ping the room.
List<matrix.MatrixEvent> _mentionState(String id) => [
      ...roomState(id).where((e) => e.type != 'm.room.member'),
      stateEvent(
        'm.room.member',
        {'membership': 'join', 'displayname': 'Alice'},
        stateKey: me,
      ),
      stateEvent('m.room.power_levels', {
        'users': {me: 100, '@bob:example.com': 50},
        'notifications': {'room': 50},
      }),
    ];

/// A message from bob; a real server sends no highlight for it in a muted
/// room (the mute override beats the mention rules).
matrix.JoinedRoomUpdate _bobSays(
  String id,
  Map<String, Object?> content, {
  String eventId = '\$mention',
}) =>
    matrix.JoinedRoomUpdate(
      state: _mentionState(id),
      unreadNotifications: matrix.UnreadNotificationCounts(
        notificationCount: 0,
        highlightCount: 0,
      ),
      timeline: matrix.TimelineUpdate(
        events: [
          matrix.MatrixEvent(
            type: 'm.room.message',
            content: {'msgtype': 'm.text', ...content},
            senderId: '@bob:example.com',
            eventId: eventId,
            originServerTs: DateTime.now(),
          ),
        ],
      ),
    );

/// Joins the rooms first, then delivers their timelines in a later sync, as
/// a message reaches a room the client already knows.
Future<void> _syncLater(
  MatrixClient client, {
  required List<matrix.BasicEvent> accountData,
  required Map<String, matrix.JoinedRoomUpdate> join,
}) async {
  await sync(
    client,
    accountData: accountData,
    join: {
      for (final MapEntry(:key, :value) in join.entries)
        key: matrix.JoinedRoomUpdate(state: value.state),
    },
  );
  await sync(
    client,
    join: {
      for (final MapEntry(:key, :value) in join.entries)
        if (value.timeline != null)
          key: matrix.JoinedRoomUpdate(
            state: value.state,
            timeline: value.timeline,
            unreadNotifications: value.unreadNotifications,
          ),
    },
  );
}

const _userMention = {
  'body': 'hey',
  'm.mentions': {
    'user_ids': [me],
  },
};

/// mentionsOnly is a room rule without notify; muted an override rule.
matrix.BasicEvent _rules({bool muted = false}) => matrix.BasicEvent(
      type: 'm.push_rules',
      content: {
        'global': {
          'override': [
            if (muted)
              {
                'rule_id': _room,
                'default': false,
                'enabled': true,
                'conditions': [
                  {'kind': 'event_match', 'key': 'room_id', 'pattern': _room},
                ],
                'actions': ['dont_notify'],
              },
          ],
          'room': [
            if (!muted)
              {
                'rule_id': _room,
                'default': false,
                'enabled': true,
                'actions': ['dont_notify'],
              },
          ],
        },
      },
    );

matrix.JoinedRoomUpdate _withMessage({
  int highlights = 0,
  String id = _room,
}) =>
    matrix.JoinedRoomUpdate(
      state: roomState(id),
      unreadNotifications: matrix.UnreadNotificationCounts(
        notificationCount: highlights,
        highlightCount: highlights,
      ),
      timeline: matrix.TimelineUpdate(
        events: [
          matrix.MatrixEvent(
            type: 'm.room.message',
            content: {'msgtype': 'm.text', 'body': 'hi'},
            senderId: '@bob:example.com',
            eventId: '\$bob1$id',
            originServerTs: DateTime.now(),
          ),
        ],
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MatrixClient client;
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    client = await signedInClient('unread-push-rule');
  });
  tearDown(() async {
    await UnreadIndex.disposeFor(client);
    for (final room in client.rooms) await room.close();
    await client.matrixClient.dispose(closeDatabase: true);
  });
  Room room() => client.rooms.firstWhere((r) => r.identifier == _room);

  test(
    'mentions-only room with a new message from bob shows the dot',
    () async {
      await sync(
        client,
        accountData: [_rules()],
        join: {_room: _withMessage()},
      );
      expect(room().pushRule, PushRule.mentionsOnly);
      final unread = computeRoomUnread(room());
      expect((unread.activity, unread.badge, unread.unread), (true, 0, true));
    },
  );

  for (final (name, content) in [
    ('an m.mentions mention', _userMention),
    ('my display name', {'body': 'Alice, look'}),
    ('@room', {'body': '@room look'}),
    (
      'an m.mentions room mention',
      {
        'body': 'look',
        'm.mentions': {'room': true},
      }
    ),
  ]) {
    test('unencrypted muted room: $name shows the red badge, no dot', () async {
      await _syncLater(
        client,
        accountData: [
          _ruleSet(muted: [_room], userMention: true),
        ],
        join: {_room: _bobSays(_room, content)},
      );
      expect(room().pushRule, PushRule.dontNotify);
      // What a real server sends for a muted room.
      expect((room() as MatrixRoom).matrixRoom.highlightCount, 0);
      final unread = computeRoomUnread(room());
      expect(
        (unread.muted, unread.highlights, unread.badge, unread.activity),
        (true, 1, 1, false),
      );
      // Red, like any mention badge.
      expect(unread.noisy, isTrue);
    });
  }

  test('muted room: @room from someone who may not ping counts nothing',
      () async {
    final update = _bobSays(_room, {'body': '@room look'});
    await _syncLater(
      client,
      accountData: [
        _ruleSet(muted: [_room], userMention: true),
      ],
      join: {
        _room: matrix.JoinedRoomUpdate(
          state: [
            ...update.state!,
            stateEvent('m.room.power_levels', {
              'users': {me: 100},
              'notifications': {'room': 50},
            }),
          ],
          timeline: update.timeline,
        ),
      },
    );
    expect(computeRoomUnread(room()).unread, isFalse);
  });

  test(
    'unencrypted muted room: the scan finds a stored mention after a restart',
    () async {
      await sync(
        client,
        accountData: [
          _ruleSet(muted: [_room], userMention: true),
        ],
        join: {
          _room: _bobSays(_room, {'body': 'old'}, eventId: '\$read'),
        },
      );
      final sdk = client.matrixClient.getRoomById(_room)!;
      sdk.receiptState = matrix.LatestReceiptState.fromJson({
        'global': {
          'public': {'e': '\$read', 'ts': 1},
        },
      });
      await sync(client, join: {
        _room: matrix.JoinedRoomUpdate(
          timeline: _bobSays(_room, _userMention).timeline,
        ),
      });
      expect(room().highlightedNotificationCount, 1);
      final original = room() as MatrixRoom;
      await original.close();
      client.rooms.remove(original);
      UnreadIndex.debugStorageReads = 0;
      final recreated = MatrixRoom(client, sdk, client.matrixClient);
      client.rooms.add(recreated);
      await UnreadIndex.of(client)
          .onChanged
          .firstWhere((_) => recreated.highlightedNotificationCount == 1)
          .timeout(const Duration(seconds: 5));
      final unread = computeRoomUnread(recreated);
      expect((unread.badge, unread.noisy, unread.activity), (1, true, false));
      // ignore: avoid_print
      print('muted room scan storage reads: ${UnreadIndex.debugStorageReads}');
      expect(UnreadIndex.debugStorageReads, lessThanOrEqualTo(3));
    },
  );

  test('muted room without a highlight shows nothing', () async {
    await sync(
      client,
      accountData: [_rules(muted: true)],
      join: {_room: _withMessage()},
    );
    expect(room().pushRule, PushRule.dontNotify);
    expect(computeRoomUnread(room()).unread, isFalse);
  });

  test(
    'a space whose mentions-only room has a new message shows the pill',
    () async {
      await sync(
        client,
        accountData: [_rules()],
        join: {
          _space: joined(_space, children: [_room]),
          _room: _withMessage(),
        },
      );
      final space = client.spaces.firstWhere((s) => s.identifier == _space);
      expect(space.unread.activity, isTrue);
      expect(space.unread.badge, 0);
    },
  );

  test(
    'a real space: a muted room mention counts, muted plain activity does not',
    () async {
      await _syncLater(
        client,
        accountData: [
          _ruleSet(muted: [_room, _room2], userMention: true),
        ],
        join: {
          _space: joined(_space, children: [_room, _room2]),
          _room: _bobSays(_room, _userMention),
          _room2: _withMessage(id: _room2),
        },
      );
      final space = client.spaces.firstWhere((s) => s.identifier == _space);
      final unread = space.unread;
      expect(
        (unread.badge, unread.highlights, unread.activity),
        (1, 1, false),
      );
      expect(UnreadTotals.tray([(space.localId, unread, false)]).$1, 1);
      final tray = NotificationUtils.countNotifications(
        space.rooms.map((r) => (r, false)),
      );
      expect(tray.$1, 1);
    },
  );

  test(
    'a muted space shows only its mentions, not a mentions-only room dot',
    () async {
      await sync(
        client,
        accountData: [
          _ruleSet(muted: [_space], mentionsOnly: [_room]),
        ],
        join: {
          _space: joined(_space, children: [_room, _room2]),
          _room: _withMessage(),
          _room2: _withMessage(id: _room2, highlights: 1),
        },
      );
      final space = client.spaces.firstWhere((s) => s.identifier == _space);
      expect(space.pushRule, PushRule.dontNotify);
      final unread = space.unread;
      expect(
        (unread.badge, unread.highlights, unread.activity),
        (1, 1, false),
      );
    },
  );

  test('the chat list digest of a muted space shows its mention', () async {
    await _syncLater(
      client,
      accountData: [
        _ruleSet(muted: [_space, _room], userMention: true),
      ],
      join: {
        _space: joined(_space, children: [_room, _room2]),
        _room: _bobSays(_room, _userMention),
        _room2: _withMessage(id: _room2),
      },
    );
    final manager = ClientManager()..clients.add(client);
    final source = UnifiedChatSource(manager);
    addTearDown(source.dispose);
    final row = source.allRows
        .whereType<SpaceTopRow>()
        .firstWhere((r) => r.roomId == _space);
    expect(row.space.muted, isTrue);
    final digest = SpaceDigest.of(row.space);
    expect(
      (digest.unread, digest.mentions, digest.unreadMark),
      (1, 1, false),
    );
  });

  test(
    'an encrypted muted room badges a mention detected on this device',
    () async {
      await sync(
        client,
        accountData: [
          _ruleSet(muted: [_room], userMention: true),
        ],
        join: {
          _room: matrix.JoinedRoomUpdate(
            state: [
              ...roomState(_room),
              stateEvent(matrix.EventTypes.Encryption, {
                'algorithm': 'm.megolm.v1.aes-sha2',
              }),
            ],
          ),
        },
      );
      final sdk = client.matrixClient.getRoomById(_room)!;
      matrix.Event message(String id, Map<String, Object?> extra) {
        final time = DateTime.now();
        return matrix.Event(
          type: matrix.EventTypes.Message,
          eventId: id,
          senderId: '@bob:example.com',
          originServerTs: time,
          room: sdk,
          content: {'msgtype': 'm.text', 'body': 'hi', ...extra},
          originalSource: matrix.MatrixEvent(
            type: matrix.EventTypes.Encrypted,
            eventId: id,
            senderId: '@bob:example.com',
            originServerTs: time,
            content: {
              'algorithm': 'm.megolm.v1.aes-sha2',
              'ciphertext': 'fixture',
            },
          ),
        );
      }

      await sync(
        client,
        join: {
          _room: matrix.JoinedRoomUpdate(
            timeline: matrix.TimelineUpdate(
              events: [
                message('\$read', {}),
              ],
            ),
          ),
        },
      );
      sdk.receiptState = matrix.LatestReceiptState.fromJson({
        'global': {
          'public': {'e': '\$read', 'ts': 1},
        },
      });
      await sync(
        client,
        join: {
          _room: matrix.JoinedRoomUpdate(
            timeline: matrix.TimelineUpdate(
              events: [
                message('\$plain', {}),
                message('\$mention', {
                  'm.mentions': {
                    'user_ids': [me],
                  },
                }),
              ],
            ),
          ),
        },
      );
      expect(room().pushRule, PushRule.dontNotify);
      var unread = computeRoomUnread(room());
      expect(
        (unread.badge, unread.highlights, unread.noisy, unread.activity),
        (1, 1, true, false),
      );
      // After a restart only the unread index's scan of stored events
      // finds it again.
      final original = room() as MatrixRoom;
      await original.close();
      client.rooms.remove(original);
      final recreated = MatrixRoom(client, sdk, client.matrixClient);
      client.rooms.add(recreated);
      await UnreadIndex.of(client)
          .onChanged
          .firstWhere((_) => recreated.highlightedNotificationCount == 1)
          .timeout(const Duration(seconds: 5));
      unread = computeRoomUnread(recreated);
      expect((unread.badge, unread.activity), (1, false));
    },
  );

  group('a room muted after the server counted a mention', () {
    // Highlight counts are fixed when the event arrives: A is counted by the
    // server before the mute and stays counted; B arrives after the mute and
    // the server never counts it.
    matrix.JoinedRoomUpdate mention(String eventId, int server) =>
        matrix.JoinedRoomUpdate(
          unreadNotifications: matrix.UnreadNotificationCounts(
            notificationCount: server,
            highlightCount: server,
          ),
          timeline: _bobSays(_room, _userMention, eventId: eventId).timeline,
        );
    matrix.JoinedRoomUpdate serverCount(int server) => matrix.JoinedRoomUpdate(
          unreadNotifications: matrix.UnreadNotificationCounts(
            notificationCount: server,
            highlightCount: server,
          ),
        );

    late matrix.Room sdk;
    MatrixRoom current() => room() as MatrixRoom;

    Future<int> settled(int expected) async {
      await UnreadIndex.of(client)
          .onChanged
          .firstWhere((_) => current().highlightedNotificationCount == expected)
          .timeout(const Duration(seconds: 3), onTimeout: () => null);
      return current().highlightedNotificationCount;
    }

    Future<int> restart(int expected) async {
      final original = current();
      await original.close();
      client.rooms.remove(original);
      final recreated = MatrixRoom(client, sdk, client.matrixClient);
      client.rooms.add(recreated);
      return settled(expected);
    }

    /// A notify room, read up to an old message, then mention A with the
    /// server's count 1.
    Future<void> mentionThenMute() async {
      await sync(
        client,
        accountData: [_ruleSet(userMention: true)],
        join: {
          _room: _bobSays(_room, {'body': 'old'}, eventId: '\$read'),
        },
      );
      sdk = client.matrixClient.getRoomById(_room)!;
      sdk.receiptState = matrix.LatestReceiptState.fromJson({
        'global': {
          'public': {'e': '\$read', 'ts': 1},
        },
      });
      await sync(client, join: {_room: mention('\$a', 1)});
      expect(current().highlightedNotificationCount, 1);
      await sync(
        client,
        accountData: [
          _ruleSet(muted: [_room], userMention: true),
        ],
        join: {_room: serverCount(1)},
      );
      expect(current().pushRule, PushRule.dontNotify);
    }

    test('muting keeps one badge for the server-counted mention', () async {
      await mentionThenMute();
      expect(await settled(2), 1);
      final unread = computeRoomUnread(current());
      expect((unread.badge, unread.noisy, unread.activity), (1, true, false));
      expect(await restart(2), 1);
    });

    test('a mention after the mute adds one', () async {
      await mentionThenMute();
      await sync(client, join: {_room: mention('\$b', 1)});
      expect(await settled(2), 2);
      expect(await restart(2), 2);
    });

    test('a mention after the mute alone counts one', () async {
      await sync(
        client,
        accountData: [
          _ruleSet(muted: [_room], userMention: true),
        ],
        join: {
          _room: _bobSays(_room, {'body': 'old'}, eventId: '\$read'),
        },
      );
      sdk = client.matrixClient.getRoomById(_room)!;
      sdk.receiptState = matrix.LatestReceiptState.fromJson({
        'global': {
          'public': {'e': '\$read', 'ts': 1},
        },
      });
      await sync(client, join: {_room: mention('\$b', 0)});
      expect(await settled(1), 1);
      expect(await restart(1), 1);
    });

    test('unmuting keeps the mention the server never counted', () async {
      await mentionThenMute();
      await sync(client, join: {_room: mention('\$b', 1)});
      expect(await settled(2), 2);
      await sync(
        client,
        accountData: [_ruleSet(userMention: true)],
        join: {_room: serverCount(1)},
      );
      expect(current().pushRule, isNot(PushRule.dontNotify));
      expect(await settled(2), 2);
      // A later mention while unmuted is the server's.
      await sync(client, join: {_room: mention('\$c', 2)});
      expect(await settled(3), 3);
      // Known limit: after a restart only the server's count is left.
      expect(await restart(2), 2);
    });
  });

  /// Our join as the timeline carries it: a first join has no previous
  /// membership, a rejoin follows a leave.
  matrix.MatrixEvent ourJoin({bool rejoin = false}) => matrix.MatrixEvent(
        type: 'm.room.member',
        content: {'membership': 'join', 'displayname': 'Alice'},
        stateKey: me,
        senderId: me,
        eventId: rejoin ? '\$rejoin' : '\$join',
        originServerTs: DateTime.now(),
        prevContent: rejoin ? {'membership': 'leave'} : null,
      );
  matrix.MatrixEvent bob(String eventId, Map<String, Object?> content) =>
      matrix.MatrixEvent(
        type: 'm.room.message',
        content: {'msgtype': 'm.text', ...content},
        senderId: '@bob:example.com',
        eventId: eventId,
        originServerTs: DateTime.now(),
      );

  /// The sync that brings the room in: its state before the timeline (with
  /// our member when we joined before it), the timeline as given, and our
  /// receipt on [readUpTo], if any.
  matrix.JoinedRoomUpdate firstSync(
    List<matrix.MatrixEvent> timeline, {
    String? readUpTo,
    bool joinedBefore = false,
  }) =>
      matrix.JoinedRoomUpdate(
        state: _mentionState(_room)
            .where((e) => joinedBefore || e.stateKey != me)
            .toList(),
        unreadNotifications: matrix.UnreadNotificationCounts(
          notificationCount: 0,
          highlightCount: 0,
        ),
        timeline: matrix.TimelineUpdate(events: timeline),
        ephemeral: [
          if (readUpTo != null)
            matrix.BasicEvent(type: 'm.receipt', content: {
              readUpTo: {
                'm.read': {
                  me: {'ts': 1},
                },
              },
            }),
        ],
      );

  /// Every badge value the UI could read: on each room update, each unread
  /// index change, and after each sync.
  List<int> watchBadges() {
    final seen = <int>[];
    void look() {
      for (final r in client.rooms.where((r) => r.identifier == _room)) {
        seen.add(r.highlightedNotificationCount);
      }
    }

    for (final r in client.rooms) r.onUpdate.listen((_) => look());
    client.onRoomAdded.listen((r) => r.onUpdate.listen((_) => look()));
    UnreadIndex.of(client).onChanged.listen((_) => look());
    addTearDown(look);
    return seen;
  }

  Future<int> settledBadge(int expected) async {
    await UnreadIndex.of(client)
        .onChanged
        .firstWhere((_) => room().highlightedNotificationCount == expected)
        .timeout(const Duration(seconds: 3), onTimeout: () => null);
    return room().highlightedNotificationCount;
  }

  final muted = _ruleSet(muted: [_room], userMention: true);

  for (final (name, content) in [
    ('my display name', {'body': 'Alice, look'}),
    ('an m.mentions mention', _userMention),
  ])
    test(
      'a brand-new muted room: $name after our join in its first sync badges '
      'it',
      () async {
        // The room, our join and the message arrive in one sync, as on the
        // real path when someone invites you and talks at once.
        final seen = watchBadges();
        await sync(
          client,
          accountData: [muted],
          join: {
            _room: firstSync([ourJoin(), bob('\$mention', content)]),
          },
        );
        expect(room().pushRule, PushRule.dontNotify);
        expect(await settledBadge(1), 1);
        final unread = computeRoomUnread(room());
        expect((unread.highlights, unread.activity), (1, false));
        expect(seen.where((n) => n > 1), isEmpty);
      },
    );

  group('a first sync never badges a read or pre-join mention', () {
    test('rejoining a muted room: its mentions from before the join', () async {
      await sync(
        client,
        accountData: [muted],
        join: {
          _room: firstSync([ourJoin()]),
        },
      );
      await sync(client, leave: {_room: left('leave')});
      expect(client.rooms.where((r) => r.identifier == _room), isEmpty);
      final seen = watchBadges();
      // A server sends the shared history before our join on a rejoin.
      await sync(
        client,
        join: {
          _room: firstSync([
            bob('\$old1', {'body': 'Alice, look'}),
            bob('\$old2', _userMention),
            ourJoin(rejoin: true),
            bob('\$plain', {'body': 'welcome back'}),
          ]),
        },
      );
      expect(room().pushRule, PushRule.dontNotify);
      expect(await settledBadge(1), 0);
      expect(seen, everyElement(0));
    });

    test('an initial sync: a mention before our receipt', () async {
      // A fresh login or a cleared cache: our join is older than the
      // timeline, and the room's stored order isn't known yet.
      final seen = watchBadges();
      await sync(
        client,
        accountData: [muted],
        join: {
          _room: firstSync([
            bob('\$m', _userMention),
            bob('\$r', {'body': 'later'}),
          ], readUpTo: '\$r', joinedBefore: true),
        },
      );
      expect(room().pushRule, PushRule.dontNotify);
      expect(await settledBadge(1), 0);
      expect(seen, everyElement(0));
    });

    test('a first sync with our join: a mention before our receipt', () async {
      final seen = watchBadges();
      await sync(
        client,
        accountData: [muted],
        join: {
          _room: firstSync([
            ourJoin(),
            bob('\$m', {'body': 'Alice, look'}),
            bob('\$r', {'body': 'later'}),
          ], readUpTo: '\$r'),
        },
      );
      expect(await settledBadge(1), 0);
      expect(seen, everyElement(0));
    });

    test('an initial sync: a mention after our receipt is the scan\'s',
        () async {
      // The first sync counts nothing here; the unread index scans the
      // muted room from its receipt and finds the mention.
      final seen = watchBadges();
      await sync(
        client,
        accountData: [muted],
        join: {
          _room: firstSync([
            bob('\$r', {'body': 'old'}),
            bob('\$m', _userMention),
          ], readUpTo: '\$r', joinedBefore: true),
        },
      );
      expect(await settledBadge(1), 1);
      expect(seen.where((n) => n > 1), isEmpty);
    });
  });
}
