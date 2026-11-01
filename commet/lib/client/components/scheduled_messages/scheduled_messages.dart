import 'dart:async';
import 'dart:convert';

import 'package:commet/client/client.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/debug/log.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;

/// Vommet: a message waiting on the homeserver (MSC4140 delayed event).
class ScheduledMessage {
  const ScheduledMessage({
    required this.delayId,
    required this.roomId,
    required this.type,
    required this.content,
    required this.sendAt,
  });

  final String delayId;
  final String roomId;
  final String type;
  final Map<String, dynamic> content;
  final DateTime sendAt;

  bool get encrypted => type == matrix.EventTypes.Encrypted;

  /// One entry of the `delayed_events` list; null for anything that isn't a
  /// scheduled message (state events, such as the call-leave heartbeat).
  static ScheduledMessage? fromJson(Map<String, dynamic> json) {
    final id = json["delay_id"];
    final roomId = json["room_id"];
    final type = json["type"];
    final content = json["content"];
    final delay = json["delay"];
    final since = json["running_since"];
    if (id is! String || roomId is! String || type is! String) return null;
    if (json.containsKey("state_key")) return null;
    if (type != matrix.EventTypes.Message &&
        type != matrix.EventTypes.Encrypted) {
      return null;
    }
    if (content is! Map || delay is! int || since is! int) return null;
    return ScheduledMessage(
      delayId: id,
      roomId: roomId,
      type: type,
      content: Map<String, dynamic>.from(content),
      sendAt: DateTime.fromMillisecondsSinceEpoch(since + delay),
    );
  }
}

/// Vommet: what Schedule message asks [ScheduledMessages.sendScheduled] to do
/// with the message the normal send path builds.
class ScheduleRequest {
  ScheduleRequest(this.sendAt);
  final DateTime sendAt;
  final Completer<String> done = Completer<String>();
}

/// Why scheduling failed, in words for the user.
class ScheduleException implements Exception {
  const ScheduleException(this.message, {this.maxDelay});
  final String message;

  /// The longest delay the homeserver allows, when that was the problem.
  final Duration? maxDelay;

  @override
  String toString() => message;
}

/// Vommet: scheduled send, held by the homeserver with MSC4140 delayed
/// events, so it goes out while the app is closed. There is no local queue:
/// on a homeserver without `org.matrix.msc4140` the option is grayed out.
class ScheduledMessages {
  static const feature = "org.matrix.msc4140";
  static const _path = "/client/unstable/org.matrix.msc4140/delayed_events";
  static const _zoneKey = #vommetScheduleRequest;

  /// Bumped whenever a list changes.
  static final ValueNotifier<int> changed = ValueNotifier(0);

  static final Map<matrix.Client, (bool, DateTime)> _supported = {};
  static final Map<matrix.Client, List<ScheduledMessage>> _items = {};
  static final Map<matrix.Client, Timer> _dueTimers = {};

  /// How long a /versions answer is trusted; a homeserver that gains MSC4140
  /// lights the option up within this time.
  static const _recheck = Duration(hours: 1);

  static matrix.Client? _matrixClient(Client client) =>
      client is MatrixClient ? client.matrixClient : null;

  /// The last known answer, without asking the homeserver; null when it
  /// hasn't been asked yet.
  static bool? supportedCached(Client client) {
    final mx = _matrixClient(client);
    return mx == null ? false : _supported[mx]?.$1;
  }

  /// Whether the homeserver advertises MSC4140 in /versions.
  static Future<bool> supported(Client client) async {
    final mx = _matrixClient(client);
    if (mx == null) return false;
    final known = _supported[mx];
    if (known != null && DateTime.now().difference(known.$2) < _recheck) {
      return known.$1;
    }
    var result = false;
    try {
      final versions = await mx.getVersions();
      result = versions.unstableFeatures?[feature] == true;
    } catch (error, trace) {
      Log.onError(error, trace, content: "Could not check delayed events");
      return known?.$1 ?? false;
    }
    final was = known?.$1;
    _supported[mx] = (result, DateTime.now());
    if (was != result) changed.value++;
    return result;
  }

  /// The request of a Schedule message running in this zone, if any.
  static ScheduleRequest? get currentRequest {
    final value = Zone.current[_zoneKey];
    return value is ScheduleRequest ? value : null;
  }

  /// Runs [send] so that the text message it sends is scheduled for
  /// [request] instead of sent now.
  static T runScheduled<T>(ScheduleRequest request, T Function() send) =>
      runZoned(send, zoneValues: {_zoneKey: request});

  /// The scheduled messages of [roomId], soonest first (from the last
  /// [refresh]).
  static List<ScheduledMessage> inRoom(Client client, String roomId) {
    final mx = _matrixClient(client);
    if (mx == null) return const [];
    return (_items[mx] ?? const [])
        .where((m) => m.roomId == roomId)
        .toList(growable: false);
  }

  /// Sorts and keeps the scheduled messages of a `delayed_events` answer.
  static List<ScheduledMessage> parse(Object? json) {
    final list = json is Map ? json["delayed_events"] : null;
    if (list is! List) return const [];
    final items = list
        .whereType<Map>()
        .map((e) => ScheduledMessage.fromJson(Map<String, dynamic>.from(e)))
        .whereType<ScheduledMessage>()
        .toList();
    items.sort((a, b) => a.sendAt.compareTo(b.sendAt));
    return items;
  }

  /// Loads this account's scheduled messages from the homeserver.
  static Future<List<ScheduledMessage>> refresh(Client client) async {
    final mx = _matrixClient(client);
    if (mx == null || !await supported(client)) return const [];
    final items = <ScheduledMessage>[];
    String? from;
    // Pages, in case a homeserver pages the list (MSC4140 allows it).
    for (var page = 0; page < 20; page++) {
      final result = await mx.request(
        matrix.RequestType.GET,
        _path,
        query: {if (from != null) "from": from},
      );
      items.addAll(parse(result));
      final next = result["next_batch"];
      if (next is! String || next.isEmpty) break;
      from = next;
    }
    items.sort((a, b) => a.sendAt.compareTo(b.sendAt));
    _items[mx] = items;
    _scheduleDueRefresh(client, mx, items);
    changed.value++;
    return items;
  }

  /// Refreshes again just after the next message is due, so it leaves the
  /// list when it has been sent.
  static void _scheduleDueRefresh(
    Client client,
    matrix.Client mx,
    List<ScheduledMessage> items,
  ) {
    _dueTimers.remove(mx)?.cancel();
    if (items.isEmpty) return;
    final ms = items.first.sendAt
        .difference(DateTime.now())
        .inMilliseconds
        .clamp(0, const Duration(days: 1).inMilliseconds);
    final wait = Duration(milliseconds: ms);
    _dueTimers[mx] = Timer(wait + const Duration(seconds: 5), () {
      _dueTimers.remove(mx);
      refresh(client).catchError((Object error, StackTrace trace) {
        Log.onError(error, trace, content: "Could not refresh scheduled");
        return const <ScheduledMessage>[];
      });
    });
  }

  /// The content of a scheduled text message: [content] as the normal send
  /// path built it, plus the reply relation it would have added.
  static Map<String, dynamic> contentFor(
    Map<String, dynamic> content, {
    String? inReplyToEventId,
  }) {
    final result = Map<String, dynamic>.from(content);
    if (inReplyToEventId != null) {
      result["m.relates_to"] = {
        "m.in_reply_to": {"event_id": inReplyToEventId},
      };
    }
    return result;
  }

  /// Sends [content] to [room] as a delayed event for [request], encrypted
  /// like any message in an encrypted room. Completes [request] with the
  /// delay id, or with a [ScheduleException].
  static Future<void> sendScheduled(
    ScheduleRequest request,
    matrix.Room room,
    Map<String, dynamic> content, {
    String? inReplyToEventId,
  }) async {
    try {
      final delay = request.sendAt.difference(DateTime.now());
      if (delay.inSeconds < 1) {
        throw ScheduleException(scheduleErrorTimeInPast);
      }
      var type = matrix.EventTypes.Message;
      var payload = contentFor(content, inReplyToEventId: inReplyToEventId);
      final client = room.client;
      if (room.encrypted) {
        final encryption = client.encryption;
        if (!client.encryptionEnabled || encryption == null) {
          throw ScheduleException(scheduleErrorEncryption);
        }
        payload = await encryption.encryptGroupMessagePayload(room.id, payload);
        type = matrix.EventTypes.Encrypted;
      }
      final txnId = client.generateUniqueTransactionId();
      final Map<String, Object?> result;
      try {
        result = await client.request(
          matrix.RequestType.PUT,
          "/client/v3/rooms/${Uri.encodeComponent(room.id)}/send/${Uri.encodeComponent(type)}/${Uri.encodeComponent(txnId)}",
          contentType: "application/json",
          data: jsonEncode(payload),
          query: {"org.matrix.msc4140.delay": delay.inMilliseconds.toString()},
        );
      } on matrix.MatrixException catch (e) {
        throw describeError(e.raw);
      }
      final id = result["delay_id"];
      if (id is! String) throw ScheduleException(scheduleErrorUnsupported);
      request.done.complete(id);
      final mx = room.client;
      final list = [...?_items[mx]];
      list.add(
        ScheduledMessage(
          delayId: id,
          roomId: room.id,
          type: type,
          content: payload,
          sendAt: request.sendAt,
        ),
      );
      list.sort((a, b) => a.sendAt.compareTo(b.sendAt));
      _items[mx] = list;
      changed.value++;
    } catch (error, trace) {
      if (error is! ScheduleException) {
        Log.onError(error, trace, content: "Scheduling a message failed");
      }
      if (!request.done.isCompleted) {
        request.done.completeError(
          error is ScheduleException ? error : ScheduleException("$error"),
        );
      }
    }
  }

  /// The homeserver's refusal of a delayed send, in words.
  static ScheduleException describeError(Map<String, Object?> raw) {
    final code = raw["errcode"];
    if (code == "M_MAX_DELAY_EXCEEDED") {
      final max = raw["max_delay"];
      final maxDelay = max is int ? Duration(milliseconds: max) : null;
      return ScheduleException(scheduleErrorTooFar, maxDelay: maxDelay);
    }
    if (code == "M_UNRECOGNIZED" || code == "M_NOT_FOUND") {
      return ScheduleException(scheduleErrorUnsupported);
    }
    final error = raw["error"];
    return ScheduleException(error is String ? error : "$code");
  }

  static Future<void> _act(Client client, String delayId, String action) async {
    final mx = _matrixClient(client);
    if (mx == null) return;
    try {
      await mx.request(
        matrix.RequestType.POST,
        "$_path/${Uri.encodeComponent(delayId)}",
        contentType: "application/json",
        data: jsonEncode({"action": action}),
      );
    } finally {
      _items[mx]?.removeWhere((m) => m.delayId == delayId);
      changed.value++;
    }
  }

  /// Deletes a scheduled message; it is never sent.
  static Future<void> cancel(Client client, String delayId) =>
      _act(client, delayId, "cancel");

  /// Sends a scheduled message right away.
  static Future<void> sendNow(Client client, String delayId) =>
      _act(client, delayId, "send");

  /// Moves [message] to [sendAt]: the same content is scheduled again, then
  /// the old one is canceled.
  static Future<void> reschedule(
    Client client,
    ScheduledMessage message,
    DateTime sendAt,
  ) async {
    final mx = _matrixClient(client);
    if (mx == null) return;
    final delay = sendAt.difference(DateTime.now());
    if (delay.inSeconds < 1) throw ScheduleException(scheduleErrorTimeInPast);
    final Map<String, Object?> result;
    try {
      result = await mx.request(
        matrix.RequestType.PUT,
        "/client/v3/rooms/${Uri.encodeComponent(message.roomId)}/send/${Uri.encodeComponent(message.type)}/${Uri.encodeComponent(mx.generateUniqueTransactionId())}",
        contentType: "application/json",
        data: jsonEncode(message.content),
        query: {"org.matrix.msc4140.delay": delay.inMilliseconds.toString()},
      );
    } on matrix.MatrixException catch (e) {
      throw describeError(e.raw);
    }
    final id = result["delay_id"];
    if (id is! String) throw ScheduleException(scheduleErrorUnsupported);
    try {
      await mx.request(
        matrix.RequestType.POST,
        "$_path/${Uri.encodeComponent(message.delayId)}",
        contentType: "application/json",
        data: jsonEncode({"action": "cancel"}),
      );
    } catch (_) {
      // Never leave it scheduled twice: drop the new one, keep the old one.
      await mx.request(
        matrix.RequestType.POST,
        "$_path/${Uri.encodeComponent(id)}",
        contentType: "application/json",
        data: jsonEncode({"action": "cancel"}),
      );
      rethrow;
    }
    final list = [...?_items[mx]]
      ..removeWhere((m) => m.delayId == message.delayId)
      ..add(
        ScheduledMessage(
          delayId: id,
          roomId: message.roomId,
          type: message.type,
          content: message.content,
          sendAt: sendAt,
        ),
      );
    list.sort((a, b) => a.sendAt.compareTo(b.sendAt));
    _items[mx] = list;
    changed.value++;
  }

  /// The text of [message]: decrypted with this device's copy of the room
  /// key when it was encrypted. Null when it can't be read here.
  static Future<String?> textOf(Client client, ScheduledMessage message) async {
    final mx = _matrixClient(client);
    if (mx == null) return null;
    var content = message.content;
    if (message.encrypted) {
      final room = mx.getRoomById(message.roomId);
      final encryption = mx.encryption;
      if (room == null || encryption == null) return null;
      try {
        final event = matrix.Event(
          content: content,
          type: message.type,
          eventId: "\$scheduled-${message.delayId}",
          senderId: mx.userID ?? "",
          originServerTs: message.sendAt,
          room: room,
        );
        final decrypted = await encryption.decryptRoomEvent(event);
        if (decrypted.type != matrix.EventTypes.Message) return null;
        content = decrypted.content;
      } catch (_) {
        return null;
      }
    }
    final body = content["body"];
    return body is String ? body : null;
  }

  /// Times offered by the picker, all after [now]: in one hour, this
  /// evening at 18:00 (or tomorrow's when that has passed), tomorrow at 09:00
  /// and next Monday at 09:00.
  static List<DateTime> presets(DateTime now) {
    final hour = now.add(const Duration(hours: 1));
    var evening = DateTime(now.year, now.month, now.day, 18);
    if (!evening.isAfter(now.add(const Duration(minutes: 30)))) {
      evening = DateTime(now.year, now.month, now.day + 1, 18);
    }
    final tomorrow = DateTime(now.year, now.month, now.day + 1, 9);
    final daysToMonday = (DateTime.monday - now.weekday + 7) % 7;
    final monday = DateTime(
      now.year,
      now.month,
      now.day + (daysToMonday == 0 ? 7 : daysToMonday),
      9,
    );
    final result = <DateTime>[];
    for (final t in [hour, evening, tomorrow, monday]) {
      if (!result.contains(t)) result.add(t);
    }
    result.sort();
    return result;
  }

  static String get scheduleErrorTimeInPast => Intl.message(
        "Pick a time in the future.",
        name: "scheduleErrorTimeInPast",
        desc: "Scheduled send: error when the picked time has already passed",
      );

  static String get scheduleErrorEncryption => Intl.message(
        "Encryption isn't ready on this device yet, so this message can't be "
        "scheduled.",
        name: "scheduleErrorEncryption",
        desc: "Scheduled send: error in an encrypted room when this device "
            "can't encrypt yet",
      );

  static String get scheduleErrorTooFar => Intl.message(
        "Your homeserver can't hold a message that long. Pick an earlier time.",
        name: "scheduleErrorTooFar",
        desc: "Scheduled send: error when the homeserver refuses a delay that "
            "long",
      );

  static String get scheduleErrorUnsupported => Intl.message(
        "Your homeserver doesn't support scheduled messages.",
        name: "scheduleErrorUnsupported",
        desc: "Scheduled send: error when the homeserver has no delayed events",
      );
}
