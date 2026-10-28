import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/room.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event_emote.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart' as matrix;

/// How a filter rule's term is matched.
enum MessageFilterKind { word, phrase, regex }

/// What a filtered message leaves in the timeline.
enum FilteredMessageDisplay { note, nothing }

/// One rule: hide messages whose text matches [term].
class MessageFilterRule {
  const MessageFilterRule(
      {required this.term, required this.kind, this.rooms = const []});

  final String term;
  final MessageFilterKind kind;

  /// Room ids the rule applies to; empty for every room.
  final List<String> rooms;

  /// The rule for what was typed in the add box: `/pattern/` is a regex,
  /// several words a phrase, one word a whole word. Null when empty.
  static MessageFilterRule? fromInput(String input) {
    final text = input.trim();
    if (text.isEmpty) return null;
    final regex = RegExp(r'^/(.+)/i?$').firstMatch(text);
    if (regex != null) {
      return MessageFilterRule(
          term: regex.group(1)!, kind: MessageFilterKind.regex);
    }
    return MessageFilterRule(
        term: text,
        kind: text.contains(RegExp(r'\s'))
            ? MessageFilterKind.phrase
            : MessageFilterKind.word);
  }

  static MessageFilterRule? fromJson(Object? json) {
    if (json is! Map) return null;
    final term = json["term"];
    if (term is! String || term.isEmpty) return null;
    final kind = MessageFilterKind.values
            .where((k) => k.name == json["kind"])
            .firstOrNull ??
        MessageFilterKind.phrase;
    final rooms = json["rooms"];
    return MessageFilterRule(
        term: term,
        kind: kind,
        rooms: rooms is List ? rooms.whereType<String>().toList() : const []);
  }

  Map<String, Object?> toJson() => {
        "term": term,
        "kind": kind.name,
        if (rooms.isNotEmpty) "rooms": rooms,
      };

  MessageFilterRule withRooms(List<String> rooms) =>
      MessageFilterRule(term: term, kind: kind, rooms: rooms);

  /// The term written the way the add box takes it.
  String get label => kind == MessageFilterKind.regex ? "/$term/i" : term;

  /// Null when [term] is not a valid regex.
  RegExp? get pattern => _patterns.putIfAbsent("${kind.name}:$term", () {
        try {
          final source = switch (kind) {
            MessageFilterKind.regex => term,
            MessageFilterKind.phrase => RegExp.escape(term),
            MessageFilterKind.word => r'(?<![\p{L}\p{N}_])' +
                RegExp.escape(term) +
                r'(?![\p{L}\p{N}_])',
          };
          return RegExp(source, caseSensitive: false, unicode: true);
        } catch (_) {
          return null;
        }
      });

  static final Map<String, RegExp?> _patterns = {};

  bool appliesIn(String roomId) => rooms.isEmpty || rooms.contains(roomId);

  bool matches(String text) => pattern?.hasMatch(text) ?? false;
}

/// The account's filter list and its options.
class MessageFilterSettings {
  const MessageFilterSettings({
    this.rules = const [],
    this.display = FilteredMessageDisplay.note,
    this.noNotifications = true,
    this.skipOwnAndDms = true,
    this.matchSenderNames = true,
  });

  final List<MessageFilterRule> rules;
  final FilteredMessageDisplay display;
  final bool noNotifications;
  final bool skipOwnAndDms;
  final bool matchSenderNames;

  static MessageFilterSettings parse(Map<String, Object?>? content) {
    if (content == null) return const MessageFilterSettings();
    final rules = content["rules"];
    return MessageFilterSettings(
      rules: rules is List
          ? rules.map(MessageFilterRule.fromJson).nonNulls.toList()
          : const [],
      display: content["show_as"] == "nothing"
          ? FilteredMessageDisplay.nothing
          : FilteredMessageDisplay.note,
      noNotifications: content["no_notifications"] != false,
      skipOwnAndDms: content["skip_own_and_dms"] != false,
      matchSenderNames: content["match_sender_names"] != false,
    );
  }

  Map<String, Object?> toJson() => {
        "rules": rules.map((r) => r.toJson()).toList(),
        "show_as": display.name,
        "no_notifications": noNotifications,
        "skip_own_and_dms": skipOwnAndDms,
        "match_sender_names": matchSenderNames,
      };

  MessageFilterSettings copyWith({
    List<MessageFilterRule>? rules,
    FilteredMessageDisplay? display,
    bool? noNotifications,
    bool? skipOwnAndDms,
    bool? matchSenderNames,
  }) =>
      MessageFilterSettings(
        rules: rules ?? this.rules,
        display: display ?? this.display,
        noNotifications: noNotifications ?? this.noNotifications,
        skipOwnAndDms: skipOwnAndDms ?? this.skipOwnAndDms,
        matchSenderNames: matchSenderNames ?? this.matchSenderNames,
      );

  /// The first rule that hides a message with [text] from [senderName] in
  /// [roomId], or null. [isOwn] and [isDm] are skipped when
  /// [skipOwnAndDms] is on.
  MessageFilterRule? match({
    required String roomId,
    required String text,
    String? senderName,
    bool isOwn = false,
    bool isDm = false,
  }) {
    if (rules.isEmpty) return null;
    if (skipOwnAndDms && (isOwn || isDm)) return null;
    for (final rule in rules) {
      if (!rule.appliesIn(roomId)) continue;
      if (rule.matches(text)) return rule;
      if (matchSenderNames && senderName != null && rule.matches(senderName)) {
        return rule;
      }
    }
    return null;
  }
}

/// Vommet: message filters hide messages that match words, phrases or
/// regexes, on this account only. The list lives in the account's private
/// account data, so it follows you to your other Vommet devices; nobody
/// else is told and nothing is deleted.
class MessageFilters {
  static const String type = "im.nether.vommet.message_filters";

  /// Bumps when the filters change, here or on another device, or when a
  /// hidden message is shown.
  static final ValueNotifier<int> changed = ValueNotifier(0);

  /// Messages the user tapped Show on, this run only.
  static final Set<String> revealed = {};

  static final Map<matrix.Client, StreamSubscription> _watching = {};

  static matrix.Client? _matrixClient(Client client) =>
      client is MatrixClient ? client.matrixClient : null;

  static bool supported(Client client) => _matrixClient(client) != null;

  static MessageFilterSettings of(Client client) {
    final mx = _matrixClient(client);
    if (mx == null) return const MessageFilterSettings();
    _watch(mx);
    final content = mx.accountData[type]?.content;
    // Timeline rows ask on every build; parse once per change.
    final cached = _parsed[mx];
    if (cached != null && identical(cached.$1, content)) return cached.$2;
    final settings = MessageFilterSettings.parse(content);
    _parsed[mx] = (content, settings);
    return settings;
  }

  static final Map<matrix.Client, (Object?, MessageFilterSettings)> _parsed =
      {};

  static Future<void> save(
      Client client, MessageFilterSettings settings) async {
    final mx = _matrixClient(client);
    if (mx == null) return;
    final content = settings.toJson();
    await mx.setAccountData(mx.userID!, type, content);
    // Apply it now rather than when the sync echoes it back.
    mx.accountData[type] = matrix.BasicEvent(type: type, content: content);
    changed.value++;
    for (final room in client.rooms) {
      if (room is MatrixRoom) room.refreshPreview();
    }
  }

  /// The rule hiding [event] in [room], or null. Only messages, emotes and
  /// polls are filtered; reactions and state never are.
  static MessageFilterRule? matchEvent(Room room, TimelineEvent event,
      {bool isPoll = false}) {
    if (event is! TimelineEventMessage &&
        event is! TimelineEventEmote &&
        !isPoll) {
      return null;
    }
    final settings = of(room.client);
    if (settings.rules.isEmpty) return null;
    return settings.match(
      roomId: room.identifier,
      text: event.plainTextBody,
      senderName: room.getMemberOrFallback(event.senderId).displayName,
      isOwn: event.senderId == room.client.self?.identifier,
      isDm: room.client
              .getComponent<DirectMessagesComponent>()
              ?.isRoomDirectMessage(room) ==
          true,
    );
  }

  /// Whether [event] is hidden from room previews and notifications.
  static bool hidesEverywhere(Room room, TimelineEvent event) =>
      matchEvent(room, event) != null;

  static void reveal(String eventId) {
    revealed.add(eventId);
    changed.value++;
  }

  static void _watch(matrix.Client client) {
    if (_watching.containsKey(client)) return;
    _watching[client] = client.onSync.stream.listen((sync) {
      if (sync.accountData?.any((e) => e.type == type) == true) {
        changed.value++;
      }
    });
  }
}
