import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';
import 'package:commet/telemetry/telemetry.dart';
import 'package:commet/client/components/component_registry.dart';
import 'package:commet/utils/voice_message.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/components/emoticon/emoticon.dart';
import 'package:commet/client/components/emoticon_recent/recent_emoticon_component.dart';
import 'package:commet/client/components/petname/petname_component.dart';
import 'package:commet/client/components/profile/profile_component.dart';
import 'package:commet/client/components/push_notification/notification_content.dart';
import 'package:commet/client/components/push_notification/notification_manager.dart';
import 'package:commet/client/components/room_component.dart';
import 'package:commet/client/components/user_color/user_color_component.dart';
import 'package:commet/client/components/user_blocking/user_blocking_component.dart';
import 'package:commet/client/matrix/components/calendar_room_component/matrix_calendar_room_component.dart';
import 'package:commet/client/matrix/components/emoticon/matrix_room_emoticon_component.dart';
import 'package:commet/client/matrix/components/read_receipts/matrix_read_receipt_component.dart';
import 'package:commet/client/matrix/components/user_presence/matrix_user_presence.dart';
import 'package:commet/client/matrix/matrix_attachment.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_member.dart';
import 'package:commet/client/matrix/matrix_mxc_image_provider.dart';
import 'package:commet/client/matrix/matrix_peer.dart';
import 'package:commet/client/matrix/matrix_role.dart';
import 'package:commet/client/matrix/matrix_room_permissions.dart';
import 'package:commet/client/matrix/matrix_timeline.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event_add_reaction.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event_call.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event_create_room.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event_edit.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event_edit_calendar.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event_emote.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event_encrypted.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event_membership.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event_message.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event_pinned_messages.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event_power_levels.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event_redaction.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event_sticker.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event_unknown.dart';
import 'package:commet/client/member.dart';
import 'package:commet/client/permissions.dart';
import 'package:commet/client/role.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event_emote.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:commet/client/timeline_events/timeline_event_sticker.dart';
import 'package:commet/config/build_config.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/image_utils.dart';
import 'package:commet/utils/message_timestamps.dart';
import 'package:commet/utils/mime.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:html_unescape/html_unescape.dart';
import 'package:matrix/matrix_api_lite/model/stripped_state_event.dart';

// ignore: implementation_imports
import 'package:commet/utils/org_italics.dart' as mx_markdown;

import '../attachment.dart';
import '../client.dart';
import 'package:matrix/matrix.dart' as matrix;

class MatrixRoom extends Room {
  late matrix.Room _matrixRoom;

  late String _displayName;

  late MatrixRoomPermissions _permissions;

  final StreamController<void> _onUpdate = StreamController.broadcast();

  final StreamController<void> onTimelineLoaded = StreamController.broadcast();

  late final List<RoomComponent<MatrixClient, MatrixRoom>> _components;

  ImageProvider? _avatar;

  @override
  String? get avatarId => _matrixRoom.avatar?.toString();

  late MatrixClient _client;

  MatrixTimeline? _timeline;

  matrix.Room get matrixRoom => _matrixRoom;

  @override
  String get displayName =>
      _displayName.startsWith("#") ? _displayName.substring(1) : _displayName;

  @override
  Stream<void> get onUpdate => _onUpdate.stream;

  @override
  Permissions get permissions => _permissions;

  @override
  bool get isE2EE => _matrixRoom.encrypted;

  @override
  int get highlightedNotificationCount => _matrixRoom.highlightCount;

  @override
  int get notificationCount => _matrixRoom.notificationCount;

  late DateTime _lastStateEventTimestamp;

  /// Vommet: the newer of our preview event and the SDK's last event (which
  /// sync keeps current, including its "refreshing" placeholder for a just
  /// joined room; ours only follows plain messages). With neither, the newest
  /// state event the room holds (e.g. our join) rather than 1970: a DM
  /// accepted before anything was said, or before its preview caught up,
  /// sank to the bottom of the DM list.
  @override
  DateTime get lastEventTimestamp {
    final own = lastEvent?.originServerTs;
    final sdk = _matrixRoom.lastEvent?.originServerTs;
    if (own != null && sdk != null) return sdk.isAfter(own) ? sdk : own;
    if (own != null || sdk != null) return (own ?? sdk)!;

    DateTime? newest;
    for (final byKey in _matrixRoom.states.values) {
      for (final state in byKey.values) {
        if (state is! matrix.Event) continue;
        if (newest == null || state.originServerTs.isAfter(newest)) {
          newest = state.originServerTs;
        }
      }
    }
    return newest ?? _lastStateEventTimestamp;
  }

  @override
  TimelineEvent? lastEvent;

  @override
  TimelineEvent? lastMessage;

  @override
  Iterable<String> get memberIds =>
      _matrixRoom.getParticipants([matrix.Membership.join]).map((e) => e.id);

  @override
  String get developerInfo =>
      const JsonEncoder.withIndent('  ').convert(_matrixRoom.states);

  Color? hashColor;
  @override
  Color get defaultColor {
    var comp = client.getComponent<DirectMessagesComponent>();
    if (comp?.isRoomDirectMessage(this) == true) {
      var user = comp?.getDirectMessagePartnerId(this);
      if (user != null) {
        var member = getMember(user);
        if (member != null) {
          return member.defaultColor;
        }
      }
    }

    if (hashColor != null) return hashColor!;

    hashColor = MatrixPeer.hashColor(identifier);

    return hashColor!;
  }

  // cache the result of push rule because this was becoming an expensive operation for ui stuff
  matrix.PushRuleState? _pushRule;

  /// Vommet: whether the account's own rules notify for an ordinary message
  /// here when the room has no rule of its own (cached with [_pushRule]).
  bool? _defaultNotifies;

  /// Vommet: what was just chosen, until the push rules come back in sync.
  PushRule? _chosenPushRule;
  StreamSubscription? _pushRulesSub;

  @override
  PushRule get pushRule {
    // Vommet: follow push rule changes made elsewhere (another client); the
    // cache used to keep the old setting until a restart.
    _pushRulesSub ??= _matrixRoom.client.onSync.stream
        .where(
            (s) => s.accountData?.any((e) => e.type == "m.push_rules") == true)
        .listen((_) {
      _pushRule = null;
      _defaultNotifies = null;
      _chosenPushRule = null;
      _onUpdate.add(null);
    });

    if (_chosenPushRule case final chosen?) return chosen;

    if (_pushRule == null) {
      _pushRule = _matrixRoom.pushRuleState;
    }

    switch (_pushRule!) {
      case matrix.PushRuleState.notify:
        // Vommet: the SDK's "notify" only means "no rule for this room". If
        // the account's default (e.g. "Messages in group chats: Off" set in
        // Element) doesn't notify here, the room only notifies for mentions
        // and keywords, and showing "All Messages" was wrong.
        _defaultNotifies ??= _notifiesForOrdinaryMessage();
        return _defaultNotifies! ? PushRule.notify : PushRule.mentionsOnly;
      case matrix.PushRuleState.mentionsOnly:
        return PushRule.mentionsOnly;
      case matrix.PushRuleState.dontNotify:
        return PushRule.dontNotify;
    }
  }

  /// Vommet: evaluates the account's push rules for an ordinary message from
  /// someone else in this room, ignoring this room's own mute and mentions
  /// rules (but keeping an explicit "notify" room rule).
  bool _notifiesForOrdinaryMessage() {
    try {
      final client = _matrixRoom.client;
      final rules = client.globalPushRules;
      if (rules == null) return true;
      final set = matrix.PushRuleSet(
        override: rules.override?.where((r) => r.ruleId != identifier).toList(),
        content: rules.content,
        room: rules.room
            ?.where(
                (r) => r.ruleId != identifier || r.actions.contains("notify"))
            .toList(),
        sender: rules.sender,
        underride: rules.underride,
      );
      final probe = matrix.Event(
        type: _matrixRoom.encrypted
            ? matrix.EventTypes.Encrypted
            : matrix.EventTypes.Message,
        content: {"msgtype": "m.text", "body": ""},
        senderId: "@vommet-probe:invalid",
        eventId: "\$vommet-probe",
        room: _matrixRoom,
        originServerTs: DateTime.now(),
      );
      return matrix.PushruleEvaluator.fromRuleset(set).match(probe).notify;
    } catch (e, s) {
      Log.onError(e, s, content: "Couldn't evaluate the room's push rules");
      return true;
    }
  }

  bool get _hasNotifyRoomRule =>
      _matrixRoom.client.globalPushRules?.room?.any(
          (r) => r.ruleId == identifier && r.actions.contains("notify")) ==
      true;

  @override
  Future<void> setPushRule(PushRule rule) async {
    var newRule = _matrixRoom.pushRuleState;
    final client = _matrixRoom.client;

    switch (rule) {
      case PushRule.notify:
        newRule = matrix.PushRuleState.notify;
        break;
      case PushRule.mentionsOnly:
        newRule = matrix.PushRuleState.mentionsOnly;
        break;
      case PushRule.dontNotify:
        newRule = matrix.PushRuleState.dontNotify;
        break;
    }

    // Vommet: an explicit "notify" room rule (see below) must go when muting
    // or switching to mentions; the SDK only knows its own rules.
    if (rule != PushRule.notify && _hasNotifyRoomRule) {
      await client.deletePushRule(matrix.PushRuleKind.room, identifier);
    }

    await _matrixRoom.setPushRuleState(newRule);

    // Vommet: "All Messages" in a room where the account's default doesn't
    // notify (e.g. group chats turned off in Element) needs a rule of its
    // own, as Element writes for its room "All messages".
    if (rule == PushRule.notify && !_notifiesForOrdinaryMessage()) {
      await client
          .setPushRule(matrix.PushRuleKind.room, identifier, ["notify"]);
    }

    _pushRule = null;
    _defaultNotifies = null;
    _chosenPushRule = rule;
    _onUpdate.add(null);
  }

  @override
  ImageProvider<Object>? get avatar {
    final comp = client.getComponent<DirectMessagesComponent>();

    if (comp == null) {
      return _avatar;
    }

    if (comp.isRoomDirectMessage(this)) {
      final partner = comp.getDirectMessagePartnerId(this);
      if (partner != null) {
        return getMemberOrFallback(partner).avatar;
      }
    }

    return _avatar;
  }

  @override
  Client get client => _client;

  @override
  String get identifier => _matrixRoom.id;

  @override
  Timeline? get timeline => _timeline;

  StreamSubscription? _onUpdateSubscription;

  MatrixRoom(
      MatrixClient client, matrix.Room room, matrix.Client matrixClient) {
    _matrixRoom = room;
    _client = client;

    _updateDisplayName();
    _components = ComponentRegistry.getMatrixRoomComponents(client, this);

    // Vommet: queued, not all rooms at once (see MatrixClient.queuePostLoad).
    client.queuePostLoad(_matrixRoom, onLoaded: () => _onUpdate.add(null));

    _lastStateEventTimestamp = DateTime.fromMillisecondsSinceEpoch(0);
    matrix.Event? latest = room.lastEvent;

    if (latest != null) {
      lastEvent = convertEvent(latest);

      if (latest.type == matrix.EventTypes.Message) {
        lastMessage = lastEvent;
      }
    }

    updateAvatar();

    _onUpdateSubscription = _matrixRoom.client.onRoomState.stream
        .where((event) => event.roomId == _matrixRoom.id)
        .listen(onRoomStateUpdated);

    _matrixRoom.client.onSync.stream
        .where((i) => i.rooms?.join?.containsKey(_matrixRoom.id) == true)
        .listen(onRoomSyncUpdate);

    _matrixRoom.client.onEvent.stream
        .where((event) => event.roomID == _matrixRoom.id)
        .listen(onEvent);

    _matrixRoom.client.onNotification.stream
        .where((event) => event.roomId == _matrixRoom.id)
        .listen(onNotification);

    _permissions = MatrixRoomPermissions(_matrixRoom);
  }

  /// Vommet: when the room's last event or message is deleted, update the
  /// room list preview now (it kept showing the deleted text until a
  /// restart).
  void _onRedaction(Map<String, dynamic> json) {
    final redacts = json["redacts"] ??
        (json["content"] as Map<String, dynamic>?)?["redacts"];
    if (redacts is! String) return;

    TimelineEvent? redactedCopy(TimelineEvent? previous) {
      if (previous is! MatrixTimelineEvent) return null;
      if (previous.eventId != redacts) return null;
      final copy = matrix.Event.fromJson(previous.event.toJson(), _matrixRoom);
      copy.setRedactionEvent(matrix.Event.fromJson(json, _matrixRoom));
      return convertEvent(copy);
    }

    final newLastEvent = redactedCopy(lastEvent);
    final newLastMessage = redactedCopy(lastMessage);
    if (newLastEvent == null && newLastMessage == null) return;

    if (newLastEvent != null) lastEvent = newLastEvent;
    if (newLastMessage != null) lastMessage = newLastMessage;
    _onUpdate.add(null);
  }

  Future<void> updateAvatar({bool fromCache = true}) async {
    if (_matrixRoom.avatar != null) {
      _avatar = MatrixMxcImage(_matrixRoom.avatar!, _matrixRoom.client,
          thumbnailHeight: 64, fullResHeight: 128, autoLoadFullRes: false);
    } else if (_matrixRoom.isDirectChat) {
      var user = _matrixRoom
          .unsafeGetUserFromMemoryOrFallback(_matrixRoom.directChatMatrixID!);
      var url = user.avatarUrl;
      if (url != null) {
        _avatar = MatrixMxcImage(url, _matrixRoom.client,
            thumbnailHeight: 64, fullResHeight: 128, autoLoadFullRes: false);
      }
    }

    _onUpdate.add(null);
  }

  void onEvent(matrix.EventUpdate eventUpdate) async {
    if (eventUpdate.roomID != identifier) {
      return;
    }

    if (eventUpdate.content["type"] == matrix.EventTypes.Redaction) {
      _onRedaction(eventUpdate.content);
      return;
    }

    if (eventUpdate.content["type"] == matrix.EventTypes.Message) {
      var roomEvent =
          await matrixRoom.getEventById(eventUpdate.content['event_id']);

      if (roomEvent == null) {
        return;
      }

      var event = convertEvent(roomEvent);

      (client as MatrixClient).onTimelineEventController.add((this, event));

      if (lastEvent == null) {
        lastEvent = event;
        _onUpdate.add(null);
      } else if (event.originServerTs.isAfter(lastEvent!.originServerTs)) {
        lastEvent = event;
        _onUpdate.add(null);
      }

      if (event is TimelineEventMessage ||
          event is TimelineEventSticker ||
          event is TimelineEventEmote) {
        if (lastMessage == null) {
          lastMessage = event;
          _onUpdate.add(null);
        } else if (event.originServerTs.isAfter(lastMessage!.originServerTs)) {
          lastMessage = event;
          _onUpdate.add(null);
        }
      }
    }
  }

  void onNotification(matrix.Event matrixEvent) {
    var event = convertEvent(matrixEvent);

    handleNotification(event);
  }

  Future<void> handleNotification(TimelineEvent event,
      {Function(String reason)? onNotificationRejected}) async {
    if (!shouldNotify(event, onNotificationRejected: onNotificationRejected)) {
      onNotificationRejected?.call("shouldNotify returned false");
      return;
    }

    if (event is MatrixTimelineEventCall ||
        event is MatrixTimelineEventUnknown) {
      onNotificationRejected?.call("Event type does not trigger notifications");
      return;
    }

    if (event is TimelineEventMessage || event is TimelineEventSticker) {
      // let push notifications handle it
      if (BuildConfig.ANDROID) {
        onNotificationRejected?.call(
            "Notifications should be handled by a push service on Android, but we are in the desktop notifications handler");
        return;
      }

      var notification =
          await MessageNotificationContent.fromEvent(event, this);
      if (notification != null) {
        NotificationManager.notify(notification,
            onNotificationRejected: onNotificationRejected);
      } else {
        onNotificationRejected?.call("Notification content was null");
      }
    }
  }

  @override
  bool shouldNotify(TimelineEvent event,
      {Function(String reason)? onNotificationRejected}) {
    if ((client as MatrixClient).firstSyncComplete == false) {
      return false;
    }

    // never notify for a message that came from an account we are logged in to!
    if (clientManager?.clients
            .any((element) => element.self?.identifier == event.senderId) ==
        true) {
      onNotificationRejected
          ?.call("Message came from a user logged in to this client");
      return false;
    }

    var timeDiff = DateTime.now().difference(event.originServerTs);

    // dont notify if we are receiving an old message
    if (timeDiff.inMinutes > 10) {
      onNotificationRejected?.call("Message is over 10 minutes old");
      return false;
    }

    var evaluator = _matrixRoom.client.pushruleEvaluator;
    var match = evaluator.match((event as MatrixTimelineEvent).event);

    if (match.notify == false) {
      onNotificationRejected?.call("Did not pass push rules");
    }

    return match.notify;
  }

  @override
  Future<List<ProcessedAttachment>> processAttachments(
      List<PendingFileAttachment> attachments) async {
    return await Future.wait(attachments.map((e) async {
      final clock = Stopwatch()..start();
      final processed = (await processAttachment(e))!;
      processed.telemetryMs = {
        ...e.telemetryMs,
        "process_ms": clock.elapsedMilliseconds,
      };
      return processed;
    }));
  }

  Future<MatrixProcessedAttachment?> processAttachment(
      PendingFileAttachment attachment) async {
    await attachment.resolve();
    if (attachment.data == null) return null;

    if (attachment.mimeType == "image/bmp") {
      var img = MemoryImage(attachment.data!);
      var image = await ImageUtils.imageProviderToImage(img);
      var bytes = await image.toByteData(format: ImageByteFormat.png);
      attachment.data = bytes!.buffer.asUint8List();
      attachment.mimeType = "image/png";
    }

    var fileExtension = attachment.mimeType != null
        ? Mime.extensionFromMime(attachment.mimeType!)
        : null;
    if (fileExtension == null) {
      fileExtension = "";
    } else {
      fileExtension = ".${fileExtension}";
    }

    try {
      if (Mime.imageTypes.contains(attachment.mimeType)) {
        await decodeImageFromList(attachment.data!);

        final name = attachment.name ?? "unknown${fileExtension}";

        return MatrixProcessedAttachment(await matrix.MatrixImageFile.create(
            bytes: attachment.data!,
            name: name,
            mimeType: attachment.mimeType,
            nativeImplementations:
                (client as MatrixClient).nativeImplentations));
      }
    } catch (error, stack) {
      // This image is probably corrupt, since it has a mime type we should be able to display,
      // But we can't decode the image. Just clear the mime type so clients dont try to display this bad file
      attachment.mimeType = 'application/octet-stream';
      Log.onError(error, stack);
    }

    matrix.MatrixImageFile? thumbnailImageFile;
    if (attachment.thumbnailFile != null) {
      var decodedImage = await decodeImageFromList(attachment.thumbnailFile!);

      thumbnailImageFile = matrix.MatrixImageFile(
          bytes: attachment.thumbnailFile!,
          width: decodedImage.width,
          height: decodedImage.height,
          mimeType: attachment.thumbnailMime,
          name: "thumbnail");
    }

    final name = attachment.name ?? "Unknown${fileExtension}";

    if (Mime.videoTypes.contains(attachment.mimeType)) {
      return MatrixProcessedAttachment(
        matrix.MatrixVideoFile(
          bytes: attachment.data!,
          name: name,
          mimeType: attachment.mimeType,
          width: attachment.dimensions?.width.toInt(),
          height: attachment.dimensions?.height.toInt(),
          duration: attachment.length?.inMilliseconds,
        ),
        thumbnailFile: thumbnailImageFile,
      );
    }

    return MatrixProcessedAttachment(
        matrix.MatrixFile(
            bytes: attachment.data!, name: name, mimeType: attachment.mimeType),
        thumbnailFile: thumbnailImageFile);
  }

  void _recordAttachmentSend(
      MatrixProcessedAttachment a, int sendMs, Object? error,
      {required int batchSize, required int batchIndex}) {
    if (!Telemetry.enabled) return;
    final f = a.file;
    final kind = switch (f) {
      matrix.MatrixImageFile() => "image",
      matrix.MatrixVideoFile() => "video",
      matrix.MatrixAudioFile() => "audio",
      _ => "file",
    };
    final ms = a.telemetryMs;
    final start = ms["_start"];
    final mime = f.mimeType;
    Telemetry.record("attachment_send", {
      "kind": kind,
      "mime": RegExp(r"^[a-z]{1,16}/[a-z0-9][a-z0-9.+-]{0,63}$").hasMatch(mime)
          ? mime
          : null,
      "bytes": f.size,
      "width": f is matrix.MatrixImageFile ? f.width : null,
      "height": f is matrix.MatrixImageFile ? f.height : null,
      "encrypted": _matrixRoom.encrypted,
      "batch_size": batchSize,
      "batch_index": batchIndex,
      "thumbnail": a.thumbnailFile != null,
      "resolve_ms": ms["resolve_ms"],
      "exif_ms": ms["exif_ms"],
      "process_ms": ms["process_ms"],
      "send_ms": sendMs,
      "total_ms": start == null ? null : Telemetry.sinceStart - start,
      ...Telemetry.errorFields(error),
    });
  }

  @override
  Future<void> sendVoiceMessage(VoiceRecording recording,
      {TimelineEvent? inReplyTo, String? threadRootEventId}) async {
    final file = matrix.MatrixAudioFile(
      bytes: recording.bytes,
      name: recording.fileName,
      mimeType: recording.format.mimeType,
      duration: recording.duration.inMilliseconds,
    );
    await _matrixRoom.sendFileEvent(
      file,
      inReplyTo: inReplyTo is MatrixTimelineEvent ? inReplyTo.event : null,
      threadRootEventId: threadRootEventId,
      extraContent:
          VoiceMessage.extraContent(recording.duration, recording.waveform),
    );
  }

  @override
  Future<TimelineEvent?> sendMessage(
      {String? message,
      TimelineEvent? inReplyTo,
      TimelineEvent? replaceEvent,
      String? threadRootEventId,
      String? threadLastEventId,
      Map<String, dynamic>? fileExtraContent,
      List<ProcessedAttachment>? processedAttachments}) async {
    matrix.Event? replyingTo;

    if (inReplyTo != null) {
      replyingTo = await _matrixRoom.getEventById(inReplyTo.eventId);
    }

    if (processedAttachments != null) {
      final files =
          processedAttachments.whereType<MatrixProcessedAttachment>().toList();
      Future.wait(files.indexed.map((entry) async {
        final (index, e) = entry;
        final clock = Stopwatch()..start();
        Object? error;
        try {
          await _matrixRoom.sendFileEvent(e.file,
              threadLastEventId: threadLastEventId,
              threadRootEventId: threadRootEventId,
              extraContent: fileExtraContent,
              thumbnail: e.thumbnailFile);
        } catch (err, trace) {
          // Was an unhandled async error; the SDK has already marked the
          // event as failed in the timeline (retry/cancel menu).
          error = err;
          Log.onError(err, trace, content: "Failed to send attachment");
        }
        _recordAttachmentSend(e, clock.elapsedMilliseconds, error,
            batchSize: files.length, batchIndex: index);
      }));
    }

    if (message != null && message.trim().isNotEmpty) {
      // MSC3160: <t:UNIX> / $[UNIX] become <time> elements (experiment).
      final timestamps = preferences.experimentMessageTimestamps.value
          ? MessageTimestamps.expand(message)
          : null;

      final event = <String, dynamic>{
        'msgtype': matrix.MessageTypes.Text,
        'body': timestamps?.plainBody ?? message
      };

      var emoticons = getComponent<MatrixRoomEmoticonComponent>();
      var html = mx_markdown.markdown(timestamps?.markdownInput ?? message,
          getEmotePacks: emoticons != null
              ? () =>
                  emoticons.getEmotePacksFlat(matrix.ImagePackUsage.emoticon)
              : null,
          getMention: _matrixRoom.getMention);
      if (timestamps != null) html = timestamps.applyToHtml(html);

      if (HtmlUnescape().convert(html.replaceAll(RegExp(r'<br />\n?'), '\n')) !=
          event['body']) {
        event['format'] = 'org.matrix.custom.html';
        event['formatted_body'] = html;
      }

      var document = html_parser.parse(html);

      var mentionsList = _findEventMentions(document);

      var mentions = {};

      if (mentionsList.contains("@room")) {
        mentions["room"] = true;
        mentionsList.remove("@room");
      }

      if (mentionsList.isNotEmpty) {
        mentions["user_ids"] = mentionsList.toList();
      }

      event["m.mentions"] = mentions;

      var id = await _matrixRoom.sendEvent(event,
          inReplyTo: replyingTo,
          editEventId: replaceEvent?.eventId,
          threadLastEventId: threadLastEventId,
          threadRootEventId: threadRootEventId);

      if (id != null) {
        var event = await _matrixRoom.getEventById(id);
        return convertEvent(event!);
      }
    }

    return null;
  }

  TimelineEvent convertEvent(matrix.Event event, {matrix.Timeline? timeline}) {
    var c = client as MatrixClient;
    try {
      if (event.redacted) {
        return MatrixTimelineEventUnknown(event, client: c);
      }

      // Vommet: hide cached events from blocked users (the server already
      // leaves out new ones).
      if (c.getComponent<UserBlockingComponent>()?.isBlocked(event.senderId) ==
          true) {
        return MatrixTimelineEventUnknown(event, client: c);
      }

      if (event.type == matrix.EventTypes.Message) {
        if (event.relationshipType == "m.replace")
          return MatrixTimelineEventEdit(event, client: c);
        if (event.content["chat.commet.type"] == "chat.commet.sticker" &&
            event.content['url'] is String)
          return MatrixTimelineEventSticker(event, client: c);

        if (event.messageType == "m.emote")
          return MatrixTimelineEventEmote(event, client: c);

        return MatrixTimelineEventMessage(event, client: c);
      }

      final result = switch (event.type) {
        matrix.EventTypes.Sticker =>
          event.content['url'] is String || event.content.containsKey('file')
              ? MatrixTimelineEventSticker(event, client: c)
              : null,
        matrix.EventTypes.Encrypted =>
          MatrixTimelineEventEncrypted(event, client: c),
        matrix.EventTypes.RoomCreate =>
          MatrixTimelineEventCreateRoom(event, client: c),
        matrix.EventTypes.RoomPowerLevels =>
          MatrixTimelineEventPowerLevels(event, client: c),
        matrix.EventTypes.Reaction =>
          MatrixTimelineEventAddReaction(event, client: c),
        matrix.EventTypes.RoomMember =>
          MatrixTimelineEventMembership(event, client: c),
        matrix.EventTypes.Redaction =>
          MatrixTimelineEventRedaction(event, client: c),
        matrix.EventTypes.CallInvite =>
          MatrixTimelineEventCall(event, client: c),
        matrix.EventTypes.CallAnswer =>
          MatrixTimelineEventCall(event, client: c),
        matrix.EventTypes.CallHangup =>
          MatrixTimelineEventCall(event, client: c),
        matrix.EventTypes.CallReject =>
          MatrixTimelineEventCall(event, client: c),
        matrix.EventTypes.RoomPinnedEvents =>
          MatrixTimelineEventPinnedMessages(event, client: c),
        "chat.commet.calendar_events" =>
          MatrixTimelineEventEditCalendar(event, client: c),
        _ => null
      };

      if (result != null) {
        return result;
      } else {
        return MatrixTimelineEventUnknown(event, client: c);
      }
    } catch (err, trace) {
      Log.e("Failed to parse event ${event.eventId} in room ${event.roomId}");
      Log.onError(err, trace, content: "Failed to parse event: ${event.type}");
      return MatrixTimelineEventUnknown(event, client: c);
    }
  }

  @override
  Future<void> enableE2EE() async {
    await _matrixRoom.enableEncryption();
  }

  @override
  Future<void> setDisplayName(String newName) async {
    _displayName = newName;
    _onUpdate.add(null);
    await _matrixRoom.setName(newName);
  }

  @override
  Color getColorOfUser(String userId) {
    return client.getComponent<UserColorComponent>()?.getColor(userId) ??
        MatrixPeer.hashColor(userId);
  }

  @override
  Future<TimelineEvent?> addReaction(
      TimelineEvent reactingTo, Emoticon reaction) async {
    var recent = client.getComponent<RecentEmoticonComponent>();
    recent?.reactedEmoticon(this, reaction);

    var id = await _matrixRoom.sendReaction(reactingTo.eventId, reaction.key);
    if (id != null) {
      var event = await _matrixRoom.getEventById(id);
      return convertEvent(event!);
    }

    return null;
  }

  @override
  Future<void> removeReaction(
      TimelineEvent reactingTo, Emoticon reaction) async {
    return (timeline! as MatrixTimeline).removeReaction(reactingTo, reaction);
  }

  @override
  T? getComponent<T extends RoomComponent>() {
    for (var component in _components) {
      if (component is T) return component as T;
    }

    return null;
  }

  @override
  List<T> getAllComponents<T extends RoomComponent<Client, Room>>() {
    return List.from(_components);
  }

  @override
  Future<void> close() async {
    await _onUpdate.close();
    await _onUpdateSubscription?.cancel();
    await timeline?.close();
  }

  @override
  Future<Timeline> getTimeline({String? contextEventId}) async {
    _timeline = MatrixTimeline(client as MatrixClient, this, matrixRoom);
    await _timeline!.initTimeline(contextEventId: contextEventId);
    onTimelineLoaded.add(null);
    return _timeline!;
  }

  @override
  Future<ImageProvider?> getShortcutImage() async {
    if (avatar != null) return avatar;

    final comp = client.getComponent<DirectMessagesComponent>();

    if (comp?.isRoomDirectMessage(this) == true) {
      var user = await client
          .getComponent<UserProfileComponent>()!
          .getProfile(comp!.getDirectMessagePartnerId(this)!);

      if (user.avatar != null) {
        return user.avatar;
      }
    }

    return client.spaces
        .where((space) => space.containsRoom(identifier))
        .firstOrNull
        ?.avatar;
  }

  @override
  Future<TimelineEvent?> getEvent(String eventId) async {
    var event = await _matrixRoom.getEventById(eventId);
    if (event == null) {
      return null;
    }

    if (event.type == matrix.EventTypes.Encrypted) {
      try {
        await event.requestKey();
      } catch (_) {
        Log.i("Failed to decrypt event: $event");
      }
    }

    return convertEvent(event);
  }

  @override
  List<Member> membersList() {
    var users = _matrixRoom.getParticipants();
    return users.map((e) => MatrixMember(_client, e)).toList();
  }

  @override
  Future<List<Member>> fetchMembersList({bool cache = false}) async {
    var results = await _matrixRoom
        .requestParticipants([matrix.Membership.join], true, cache);

    return results.map((e) => MatrixMember(_client, e)).toList();
  }

  @override
  bool get isMembersListComplete => _matrixRoom.participantListComplete;

  @override
  Member getMemberOrFallback(String id) {
    return MatrixMember(
        _client, _matrixRoom.unsafeGetUserFromMemoryOrFallback(id));
  }

  @override
  Future<Member> fetchMember(String id) async {
    var member = await _matrixRoom.requestUser(id);
    if (member != null) {
      return MatrixMember(_client, member);
    } else {
      return getMemberOrFallback(id);
    }
  }

  @override
  List<(Member, Role)> importantMembers() {
    var state = _matrixRoom.states["m.room.power_levels"]?[""];
    if (state == null) return [];

    var roles = (state.content["users"] as Map<String, dynamic>?);
    if (roles == null) return [];

    var ids = roles.keys;

    List<(Member, MatrixRole)> result = List.empty(growable: true);

    var creationEvent = _matrixRoom.states[matrix.EventTypes.RoomCreate]?[""];
    var creator = creationEvent?.senderId;
    var roomVersion = int.tryParse(_matrixRoom.roomVersion ?? "1");

    if (roomVersion != null && roomVersion >= 12) {
      if (_matrixRoom.roomVersion != null && creator != null) {
        var additionalCreators =
            creationEvent?.content.tryGetList<String>("additional_creators");

        for (var id in [
          creator,
          if (additionalCreators != null) ...additionalCreators
        ]) {
          result.add((getMemberOrFallback(id), MatrixRole(150)));
        }
      }
    }

    result.addAll(ids
        .map((e) => (getMemberOrFallback(e), MatrixRole(roles[e])))
        .where((element) => element.$2.rank != 0));

    result;

    result.sort((a, b) => b.$2.rank.compareTo(a.$2.rank));

    return result;
  }

  @override
  Role getMemberRole(String identifier) {
    return MatrixRole(_matrixRoom.getPowerLevelByUserId(identifier));
  }

  void _updateDisplayName() {
    _displayName = _matrixRoom.getLocalizedDisplayname();

    var comp = client.getComponent<DirectMessagesComponent>();

    if (comp?.isRoomDirectMessage(this) == true) {
      var partner = comp!.getDirectMessagePartnerId(this);

      if (partner != null) {
        var nicknames = client.getComponent<PetNameComponent>();
        if (nicknames != null) {
          var name = nicknames.getPetName(partner);
          if (name != null) {
            _displayName = name;
            return;
          }
        }

        var name =
            matrixRoom.unsafeGetUserFromMemoryOrFallback(partner).displayName;
        if (name != null) {
          _displayName = name;
        }
      }
    }
  }

  void onRoomStateUpdated(({String roomId, StrippedStateEvent state}) event) {
    _updateDisplayName();
    if (event.state.type == "m.room.name" ||
        event.state.type == "m.room.avatar" ||
        event.state.type == "m.room.topic") {
      _onUpdate.add(null);
    }
  }

  @override
  Future<void> cancelSend(TimelineEvent event) async {
    final mxEvent = event as MatrixTimelineEvent;
    await mxEvent.event.cancelSend();
  }

  @override
  Future<void> retrySend(TimelineEvent event) async {
    final mxEvent = event as MatrixTimelineEvent;
    await mxEvent.event.sendAgain();
  }

  @override
  bool get shouldPreviewMedia {
    switch (_matrixRoom.joinRules) {
      case matrix.JoinRules.public:
        return preferences.previewMediaInPublicRooms.value;

      case matrix.JoinRules.knock:
      case matrix.JoinRules.invite:
      case matrix.JoinRules.private:
        return preferences.previewMediaInPrivateRooms.value;

      case matrix.JoinRules.restricted:
        if (_client.spaces.any((e) =>
            e.visibility is RoomVisibilityPublic &&
            e.containsRoom(_matrixRoom.id))) {
          // if any public space contains this room, consider the room public
          // this is kind of flawed, because there could be public spaces we are not a member of
          return preferences.previewMediaInPublicRooms.value;
        } else {
          return preferences.previewMediaInPrivateRooms.value;
        }

      default:
        return false;
    }
  }

  @override
  Member? getMember(String id) {
    final user = matrixRoom.getState(matrix.EventTypes.RoomMember, id);
    if (user != null) {
      return MatrixMember(_client, user.asUser(matrixRoom));
    }

    return null;
  }

  void onRoomSyncUpdate(matrix.SyncUpdate event) {
    var update = event.rooms?.join?[_matrixRoom.id];

    if (update == null) return;

    _onUpdate.add(null);
  }

  @override
  bool get isSpecialRoomType =>
      matrixRoom
          .getState(matrix.EventTypes.RoomCreate)
          ?.content
          .containsKey("type") ??
      false;

  @override
  Future<void> banUser(String id) {
    return matrixRoom.ban(id);
  }

  @override
  Future<void> kickUser(String id) {
    return matrixRoom.kick(id);
  }

  @override
  List<Role> get availableRoles => [
        MatrixRole(100),
        MatrixRole(50),
        if (getComponent<MatrixCalendarRoomComponent>()?.hasCalendar == true)
          MatrixRole(25,
              nameOverride: "Calendar Moderator",
              iconOverride: Icons.calendar_month),
        MatrixRole(0),
      ];

  @override
  Future<void> setMemberRole(String id, Role role) async {
    await matrixRoom.setPower(id, (role as MatrixRole).powerLevel);

    await matrixRoom.waitForRoomInSync();
  }

  @override
  String? get topic => matrixRoom.topic;

  @override
  Future<void> setTopic(String topic) async {
    await matrixRoom.setDescription(topic);
    _onUpdate.add(null);
  }

  @override
  Future<void> setRoomAvatar(Uint8List bytes, String? mimeType) async {
    String name = "image";

    if (mimeType == null) mimeType = Mime.lookupType("", data: bytes);

    if (mimeType != null) {
      var extension = Mime.extensionFromMime(mimeType);
      name += ".$extension";
    }

    await matrixRoom.setAvatar(matrix.MatrixFile(bytes: bytes, name: name));
    _avatar = MemoryImage(bytes);
    _onUpdate.add(null);
  }

  @override
  Future<void> markAsRead() async {
    var tl = await matrixRoom.getTimeline();
    var readReceiptComponent = getComponent<MatrixReadReceiptComponent>();

    bool public = true;
    var presenceComp = client.getComponent<MatrixUserPresenceComponent>();

    if (presenceComp?.usePublicReadReceipts != null) {
      public = presenceComp!.usePublicReadReceipts;
    }

    if (readReceiptComponent?.usePublicReadReceiptsForRoom != null) {
      public = readReceiptComponent!.usePublicReadReceiptsForRoom!;
    }

    await tl.setReadMarker(public: public);
  }

  @override
  String? get lastRead =>
      _matrixRoom.fullyRead.isEmpty ? null : _matrixRoom.fullyRead;

  @override
  RoomVisibility get visibility {
    switch (_matrixRoom.joinRules) {
      case matrix.JoinRules.public:
        return RoomVisibilityPublic();
      case matrix.JoinRules.knock:
        return RoomVisibilityPrivate();
      case matrix.JoinRules.invite:
        return RoomVisibilityPrivate();
      case matrix.JoinRules.private:
        return RoomVisibilityPrivate();
      case matrix.JoinRules.restricted:
        return RoomVisibilityRestricted(matrixRoom
                .getState(matrix.EventTypes.RoomJoinRules)
                ?.content
                .tryGetList<Map<String, dynamic>>("allow")
                ?.map((i) => i.tryGet<String>("room_id"))
                .nonNulls
                .toList() ??
            []);
      case matrix.JoinRules.knockRestricted:
        return RoomVisibilityPrivate();
      case null:
        return RoomVisibilityPublic();
    }
  }

  @override
  Future<void> setVisibility(RoomVisibility visibility) async {
    var state = switch (visibility) {
      final RoomVisibilityPrivate _ => matrix.StateEvent(content: {
          "join_rule": "invite",
        }, type: matrix.EventTypes.RoomJoinRules),
      final RoomVisibilityPublic _ => matrix.StateEvent(
          content: {"join_rule": "public"},
          type: matrix.EventTypes.RoomJoinRules),
      final RoomVisibilityRestricted restricted => matrix.StateEvent(content: {
          "join_rule": "restricted",
          "allow": [
            for (var i in restricted.spaces)
              {"room_id": i, "type": "m.room_membership"},
          ]
        }, type: matrix.EventTypes.RoomJoinRules),
      RoomVisibility() => throw UnimplementedError(),
    };

    await _matrixRoom.client
        .setRoomStateWithKey(_matrixRoom.id, state.type, "", state.content);
  }

  Set<String> _findEventMentions(html_dom.Document document) {
    var result = Set<String>();

    result.addAll(_findChildMentions(document.nodes));

    return result;
  }

  static var roomMentionRegex = RegExp(r'(?<!\w)@room(?!\w)');

  Set<String> _findChildMentions(html_dom.NodeList children) {
    var result = Set<String>();

    for (var child in children) {
      if (child case html_dom.Element element) {
        if (element.localName == "pre" || element.localName == "code") continue;

        if (element.localName == "a") {
          var url = child.attributes["href"];
          if (url != null) {
            var parsed = Uri.tryParse(url);
            try {
              if (parsed?.authority == "matrix.to") {
                var id = parsed!.fragment.substring(1);
                var userId = Uri.decodeQueryComponent(id);

                if (userId.startsWith("@") && userId.isValidMatrixId) {
                  result.add(userId);
                }
              }
            } catch (_) {}
          }
        }
      }

      if (child case html_dom.Text text) {
        var data = text.data;
        if (roomMentionRegex.hasMatch(data)) {
          result.add("@room");
        }
      }

      result.addAll(_findChildMentions(child.nodes));
    }

    return result;
  }

  @override
  bool get isFavorite => matrixRoom.isFavourite;

  @override
  Future<void> setAsFavorite(bool favorite) {
    return matrixRoom.setFavourite(favorite);
  }
}
