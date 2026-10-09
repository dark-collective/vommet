import 'dart:async';
import 'package:commet/client/components/emoticon/emoticon.dart';
import 'package:commet/client/matrix/components/read_receipts/matrix_read_receipt_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event_encrypted.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:commet/client/timeline_events/timeline_event_sticker.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/diagnostic/diagnostics.dart';
import 'package:commet/telemetry/telemetry.dart';

import '../client.dart';
import 'package:matrix/matrix.dart' as matrix;

class MatrixTimeline extends Timeline {
  matrix.Timeline? _matrixTimeline;
  late matrix.Room _matrixRoom;

  late MatrixRoom _room;

  final StreamController<void> _loadingStatusChangedController =
      StreamController.broadcast();

  @override
  Stream<void> get onLoadingStatusChanged =>
      _loadingStatusChangedController.stream;

  matrix.Timeline? get matrixTimeline => _matrixTimeline;

  // Vommet: decryption counters for one visit to the room, sent when you
  // leave it (the timeline itself lives on for the whole app session) as the
  // opt-in diagnostics event "timeline_crypto". Only counts; nothing about
  // which room or which messages.
  final Stopwatch _visitClock = Stopwatch();
  StreamSubscription<String>? _sessionKeySub;
  int _utdAtOpen = 0;
  int _keyArrivals = 0;
  int _decrypted = 0;
  int _removed = 0;
  int _removedUtd = 0;
  int _eventsPeak = 0;

  static bool _isUtd(matrix.Event e) => e.type == matrix.EventTypes.Encrypted;

  int _countUtd() {
    final events = _matrixTimeline?.events;
    if (events == null) return 0;
    var n = 0;
    for (final e in events) {
      if (_isUtd(e)) n++;
    }
    return n;
  }

  MatrixTimeline(
    MatrixClient client,
    MatrixRoom room,
    matrix.Room matrixRoom, {
    matrix.Timeline? initialTimeline,
  }) {
    events = List.empty(growable: true);
    _matrixRoom = matrixRoom;
    this.client = client;
    this.room = room;
    _room = room;
    _matrixTimeline = initialTimeline;

    if (_matrixTimeline != null) {
      convertAllTimelineEvents();
    }
  }

  Future<void> initTimeline({String? contextEventId}) async {
    if (contextEventId == "") {
      contextEventId = null;
    }

    // Vommet: time opening a room (Developer › Performance, and opt-in
    // diagnostics as "room_open"). Only timings and counts; no IDs or text.
    final clock = Stopwatch()..start();
    final loadsRunning = (client as MatrixClient).startupLoadsRunning;
    var historyRequested = false;
    var convertMs = 0;
    Object? error;
    try {
      _matrixTimeline = await _matrixRoom.getTimeline(
          onInsert: onEventInserted,
          onChange: onEventChanged,
          onRemove: onEventRemoved,
          eventContextId: contextEventId);

      if (_matrixTimeline?.events.isEmpty == true) {
        historyRequested = true;
        await _matrixTimeline?.requestHistory();
      }

      _matrixRoom.postLoad();

      // This could maybe make load times realllly slow if we have a ton of stuff in the cache?
      // Might be better to only convert as many as we would need to display immediately and then convert the rest on demand
      final convertClock = Stopwatch()..start();
      convertAllTimelineEvents();
      convertMs = convertClock.elapsedMilliseconds;

      _utdAtOpen = _countUtd();
      _eventsPeak = events.length;
      _visitClock.start();
      _sessionKeySub =
          _matrixRoom.onSessionKeyReceived.stream.listen((_) => _keyArrivals++);
    } catch (e) {
      error = e;
      rethrow;
    } finally {
      clock.stop();
      Diagnostics.general.addResult("Open room (load timeline)", clock.elapsed);
      Telemetry.record("room_open", {
        "ms": clock.elapsedMilliseconds,
        "events": events.length,
        "history_requested": historyRequested,
        "convert_ms": convertMs,
        "startup_loads_running": loadsRunning,
        "encrypted": _matrixRoom.encrypted,
        if (_matrixRoom.encrypted) "utd": _utdAtOpen,
        "at_start": !(_matrixTimeline?.canRequestHistory ?? true),
        ...Telemetry.errorFields(error, withType: false, withStatus: false),
      });
    }
  }

  void convertAllTimelineEvents() {
    for (int i = 0; i < _matrixTimeline!.events.length; i++) {
      var converted = _room.convertEvent(_matrixTimeline!.events[i]);
      insertEvent(i, converted);
    }
  }

  void onEventInserted(index) {
    if (_matrixTimeline == null) return;
    insertEvent(index, _room.convertEvent(_matrixTimeline!.events[index]));
    if (events.length > _eventsPeak) _eventsPeak = events.length;
  }

  void onEventChanged(index) {
    if (_matrixTimeline == null) return;

    if (index < _matrixTimeline!.events.length) {
      if (index < events.length &&
          events[index] is MatrixTimelineEventEncrypted &&
          !_isUtd(_matrixTimeline!.events[index])) {
        _decrypted++;
      }
      events[index] = (room as MatrixRoom).convertEvent(
          _matrixTimeline!.events[index],
          timeline: _matrixTimeline);

      notifyChanged(index);
    }
  }

  void onEventRemoved(index) {
    if (index < events.length) {
      _removed++;
      if (events[index] is MatrixTimelineEventEncrypted) _removedUtd++;
    }
    onRemove.add(index);
    events.removeAt(index);
  }

  @override
  Future<void> loadMoreHistory() async {
    if (_matrixTimeline?.canRequestHistory == true) {
      // Vommet: time loading older messages (Developer › Performance, and
      // opt-in diagnostics as "history_load").
      final clock = Stopwatch()..start();
      final before = events.length;
      final loadsRunning = (client as MatrixClient).startupLoadsRunning;
      Object? error;
      var f = _matrixTimeline!.requestHistory();
      _loadingStatusChangedController.add(null);

      try {
        await f;
      } catch (e) {
        error = e;
        rethrow;
      } finally {
        clock.stop();
        Diagnostics.general.addResult("Load older messages", clock.elapsed);
        Telemetry.record("history_load", {
          "ms": clock.elapsedMilliseconds,
          "events": (events.length - before).clamp(0, 1000000),
          "startup_loads_running": loadsRunning,
          "encrypted": _matrixRoom.encrypted,
          ...Telemetry.errorFields(error, withType: false),
        });
      }
    }
    _loadingStatusChangedController.add(null);
  }

  @override
  bool get canLoadFuture => _matrixTimeline?.canRequestFuture ?? false;

  @override
  bool get canLoadHistory => _matrixTimeline?.canRequestHistory ?? false;

  @override
  bool get isLoadingFuture => _matrixTimeline?.isRequestingFuture ?? false;

  @override
  bool get isLoadingHistory => _matrixTimeline?.isRequestingHistory ?? false;

  @override
  Future<void> loadMoreFuture() async {
    if (canLoadFuture) {
      int waitSec = 4;
      _loadingStatusChangedController.add(null);
      while (true) {
        var f = _matrixTimeline?.requestFuture();

        try {
          await f;
          _loadingStatusChangedController.add(null);
          break;
        } on matrix.MatrixException catch (e) {
          if (e.error == matrix.MatrixError.M_LIMIT_EXCEEDED) {
            Log.i("Rate limited, waiting $waitSec second(s)...");
            await Future.delayed(Duration(seconds: waitSec));
            waitSec *= 2;
            continue;
          } else {
            Log.e(e);
            break;
          }
        } catch (e) {
          Log.e(e);
          break;
        }
      }
    }
  }

  @override
  void markAsRead(TimelineEvent event) async {
    var receipts = room.getComponent<MatrixReadReceiptComponent>();
    if (event.status == TimelineEventStatus.synced ||
        event.status == TimelineEventStatus.sent) {
      await _matrixTimeline?.setReadMarker(
          public: receipts?.usePublicReadReceiptsForRoom);

      receipts?.handleEvent(event.eventId, room.client.self!.identifier);
    }
  }

  @override
  Future<TimelineEvent?> fetchEventByIdInternal(String eventId) async {
    var event = await _matrixRoom.getEventById(eventId);
    if (event == null) return null;
    return _room.convertEvent(event);
  }

  Future<void> removeReaction(
      TimelineEvent reactingTo, Emoticon reaction) async {
    var event = await _matrixRoom.getEventById(reactingTo.eventId);
    if (event == null) return;

    if (!event.hasAggregatedEvents(
        _matrixTimeline!, matrix.RelationshipTypes.reaction)) return;

    var events = event
        .aggregatedEvents(_matrixTimeline!, matrix.RelationshipTypes.reaction)
        .where((element) => element.senderId == _matrixRoom.client.userID);

    for (var e in events) {
      if (!e.content.containsKey("m.relates_to")) continue;
      var content = e.content["m.relates_to"] as Map<String, Object?>;

      if (content.containsKey("key") && content["key"] == reaction.key) {
        await _matrixRoom.redactEvent(e.eventId);
        return;
      }
    }
  }

  @override
  Future<void> deleteEvent(TimelineEvent event) async {
    var matrixEvent = await _matrixTimeline!.getEventById(event.eventId);
    if (event.status == TimelineEventStatus.error) {
      await matrixEvent?.cancelSend();
    } else {
      await _matrixRoom.redactEvent(event.eventId);
    }
  }

  @override
  bool canDeleteEvent(TimelineEvent event) {
    if (event.senderId != room.client.self!.identifier &&
        room.permissions.canDeleteOtherUserMessages != true) return false;

    if (event is TimelineEventMessage) {
      return true;
    }

    if (event is TimelineEventSticker) {
      return true;
    }

    return true;
  }

  @override
  void endVisit() => _recordCryptoVisit();

  @override
  Future<void> close() async {
    _recordCryptoVisit();
    _visitClock.stop();
    await _sessionKeySub?.cancel();
    _matrixTimeline?.cancelSubscriptions();
    await onEventAdded.close();
    await onChange.close();
    await onRemove.close();
  }

  void _recordCryptoVisit() {
    if (!_visitClock.isRunning || !_matrixRoom.encrypted) return;
    final utdAtClose = _countUtd();
    final interesting =
        _utdAtOpen > 0 || utdAtClose > 0 || _keyArrivals > 0 || _removedUtd > 0;
    if (interesting) _sendCryptoVisit(utdAtClose);
    // The next visit starts from where this one ended.
    _utdAtOpen = utdAtClose;
    _keyArrivals = _decrypted = _removed = _removedUtd = 0;
    _eventsPeak = events.length;
    _visitClock.reset();
  }

  void _sendCryptoVisit(int utdAtClose) {
    Telemetry.record("timeline_crypto", {
      "open_s": _visitClock.elapsed.inSeconds,
      "utd_at_open": _utdAtOpen,
      "utd_at_close": utdAtClose,
      "key_arrivals": _keyArrivals,
      "decrypted": _decrypted,
      "removed": _removed,
      "removed_utd": _removedUtd,
      "events_peak": _eventsPeak,
      "events_at_close": events.length,
    });
  }

  @override
  bool isEventRedacted(TimelineEvent<Client> event) {
    var e = event as MatrixTimelineEvent;
    return e.event.getDisplayEvent(_matrixTimeline!).redacted;
  }

  @override
  String getDisplayId(TimelineEvent<Client> event) {
    var e = event as MatrixTimelineEvent;
    var ev = e.event.getDisplayEvent(matrixTimeline!);

    return "${event.eventId}-${ev.eventId}";
  }

  /// Vommet (#102): rebuilds this timeline from the room's stored history,
  /// after the room's history was thrown away to be loaded again
  /// (MatrixHistoryGapComponent.reloadHistory). The open room view keeps
  /// this object, so the events are removed and added through the usual
  /// notifications instead of replacing it.
  Future<void> reload() async {
    // The old SDK timeline stays assigned (but deaf) until the new one is
    // ready: the view may still ask about events while they are removed.
    _matrixTimeline?.cancelSubscriptions();
    for (var i = events.length - 1; i >= 0; i--) {
      onEventRemoved(i);
    }
    _loadingStatusChangedController.add(null);

    var fresh = await _matrixRoom.getTimeline(
        onInsert: onEventInserted,
        onChange: onEventChanged,
        onRemove: onEventRemoved);
    _matrixTimeline = fresh;
    convertAllTimelineEvents();
    if (fresh.canRequestHistory) {
      await fresh.requestHistory();
    }
    _loadingStatusChangedController.add(null);
  }
}
