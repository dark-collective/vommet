// Vommet (schema v34): how long each step of a device or person
// verification took, as the opt-in diagnostics event "verification". One
// event per verification this device took part in, when it ends (done,
// cancelled, or given up on after 15 minutes).
//
// Step times are milliseconds from the request: when it was sent (the
// requester) or when this device's sync handed it over (the responder).
// Steps this device received come from the moment the sync got to them;
// steps it sent from the moment the SDK finished sending them. The human
// parts (tapping Accept, comparing the emoji) are separate fields, so
// network and processing time can be told from people's time.
//
// The sync fields say how much of the wait was this device's own sync loop:
// for every step received, how long the response carrying it had already
// been in before the SDK got to it (apply wait), and how long the loop had
// been busy with the previous response before that request went out (no
// request open, so the server couldn't deliver it). Plus the sync rounds
// applied during the verification and their apply time.
//
// Numbers, booleans and fixed words only: never which user, device, room or
// transaction, and nothing from the emoji or keys.

import 'dart:async';

import 'package:commet/telemetry/telemetry.dart';
import 'package:matrix/encryption/utils/key_verification.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix/matrix.dart' show EventTypes;

/// The cancel codes the schema lists; anything else is "other".
const verificationCancelCodes = [
  "m.user",
  "m.timeout",
  "m.accepted",
  "m.mismatched_sas",
  "m.mismatched_commitment",
  "m.unknown_method",
  "m.unexpected_message",
  "m.invalid_message",
  "m.key_mismatch",
  "m.user_mismatch",
  "m.unknown_transaction",
  "m.invalid_key",
  "im.fluffychat.unknown_device",
  "m.unknown",
];

/// The steps of one verification as one device saw them. Plain data, fed
/// by [VerificationTelemetry] (and by tests), turned into event fields by
/// [fields].
class VerificationRecord {
  /// True for the device that sent the request.
  final bool requester;

  /// Verifying one of your own devices (to-device), not another person.
  final bool self;
  final bool inRoom;

  /// Since app start; steps are counted from here.
  int originMs;

  /// Whether this client's first sync was still running at [originMs].
  bool firstSyncPending;

  /// Responder: the request came in the session's first sync response.
  bool? coldStart;

  /// Responder: how old the request was when it arrived (sender's clock).
  int? requestAgeMs;

  final Map<String, int> _steps = {};
  int syncRounds = 0;
  int syncErrors = 0;
  int syncApplyTotalMs = 0;
  int syncApplyWorstMs = 0;
  int recvEvents = 0;
  int recvApplyWaitTotalMs = 0;
  int recvApplyWaitMaxMs = 0;
  int recvLoopBusyTotalMs = 0;
  int recvLoopBusyMaxMs = 0;
  bool _sas = false;
  bool _qr = false;

  VerificationRecord({
    required this.requester,
    required this.self,
    this.inRoom = false,
    required this.originMs,
    this.firstSyncPending = false,
  });

  /// The step names and when they were first seen, from [originMs].
  Map<String, int> get steps => Map.unmodifiable(_steps);

  void mark(String step, int nowMs) {
    _steps.putIfAbsent(step, () => nowMs - originMs);
  }

  bool has(String step) => _steps.containsKey(step);

  /// The responder's request dialog showed (after any device key fetch).
  void shown(int nowMs) => mark("shown", nowMs);

  /// One look at the request: on each SDK update and on a timer.
  /// [fromUpdate] means the SDK just called its onUpdate.
  void observe(
    int nowMs,
    KeyVerificationState state,
    String? lastStep, {
    bool fromUpdate = false,
  }) {
    if (state == KeyVerificationState.askSas ||
        state == KeyVerificationState.waitingSas) {
      _sas = true;
    }
    if (state == KeyVerificationState.showQRSuccess ||
        state == KeyVerificationState.confirmQRScan) {
      _qr = true;
    }
    if (requester) {
      if (lastStep == EventTypes.KeyVerificationReady) mark("ready", nowMs);
      // The SDK answers a ready with its start and then says waitingAccept.
      if (fromUpdate &&
          state == KeyVerificationState.waitingAccept &&
          has("ready")) {
        mark("start", nowMs);
      }
      if (lastStep == EventTypes.KeyVerificationAccept) {
        mark("accept", nowMs);
        // Set once its handling, which sends our key, is over.
        mark("key_sent", nowMs);
      }
    } else {
      if (!has("accepted") &&
          state != KeyVerificationState.askAccept &&
          state != KeyVerificationState.error &&
          state != KeyVerificationState.done) {
        mark("accepted", nowMs);
      }
      // The SDK says askChoice once our ready went out.
      if (state == KeyVerificationState.askChoice) mark("ready", nowMs);
      // Set once the start's handling, which sends our accept, is over.
      if (has("accepted") && lastStep == EventTypes.KeyVerificationStart) {
        mark("start", nowMs);
        mark("accept", nowMs);
      }
      // The responder sends its key before showing the emoji.
      if (state == KeyVerificationState.askSas) mark("key_sent", nowMs);
    }
    if (state == KeyVerificationState.askSas) {
      mark("key_received", nowMs);
      mark("sas_shown", nowMs);
    }
    if (state == KeyVerificationState.waitingSas) {
      mark("sas_confirmed", nowMs);
    }
    if (lastStep == "m.key.verification.mac") mark("mac_received", nowMs);
    // Asked for the recovery key (to sign the result, or before starting).
    if (state == KeyVerificationState.askSSSS) mark("ssss", nowMs);
    if (state == KeyVerificationState.done) mark("done", nowMs);
  }

  /// A verification event for this request arrived in a sync response.
  /// [applyWaitMs]: how long that response had been in already;
  /// [loopBusyMs]: how long the previous response was being applied before
  /// that request went out.
  void received(
    int nowMs,
    String type, {
    int? applyWaitMs,
    int? loopBusyMs,
  }) {
    recvEvents++;
    if (applyWaitMs != null && applyWaitMs >= 0) {
      recvApplyWaitTotalMs += applyWaitMs;
      if (applyWaitMs > recvApplyWaitMaxMs) recvApplyWaitMaxMs = applyWaitMs;
    }
    if (loopBusyMs != null && loopBusyMs >= 0) {
      recvLoopBusyTotalMs += loopBusyMs;
      if (loopBusyMs > recvLoopBusyMaxMs) recvLoopBusyMaxMs = loopBusyMs;
    }
    final step = switch (type) {
      EventTypes.KeyVerificationReady when requester => "ready",
      EventTypes.KeyVerificationStart when !requester => "start",
      EventTypes.KeyVerificationAccept when requester => "accept",
      "m.key.verification.key" => "key_received",
      "m.key.verification.mac" => "mac_received",
      _ => null,
    };
    if (step != null) mark(step, nowMs);
  }

  /// A sync round finished (or failed) while this verification ran.
  void syncRound(int responseAtMs, int finishedAtMs, {bool error = false}) {
    if (finishedAtMs < originMs) return;
    if (error) {
      syncErrors++;
      return;
    }
    syncRounds++;
    final from = responseAtMs > originMs ? responseAtMs : originMs;
    final ms = finishedAtMs - from;
    if (ms <= 0) return;
    syncApplyTotalMs += ms;
    if (ms > syncApplyWorstMs) syncApplyWorstMs = ms;
  }

  String get method => _sas
      ? "sas"
      : _qr
          ? "qr"
          : "none";

  static String cancelCode(String? code) =>
      code != null && verificationCancelCodes.contains(code) ? code : "other";

  /// The event fields once it ended at [nowMs]. [outcome] is done,
  /// cancelled, error or abandoned; [byOther] says who cancelled.
  Map<String, Object?> fields(
    int nowMs, {
    required String outcome,
    String? cancelCode,
    bool? byOther,
  }) {
    int ms(int v) => v.clamp(0, 86400000);
    int count(int v) => v.clamp(0, 1000000);
    int? step(String name) {
      final v = _steps[name];
      return v == null ? null : ms(v);
    }

    final shownMs = _steps["shown"];
    final acceptedMs = _steps["accepted"];
    return {
      "role": requester ? "requester" : "responder",
      "kind": self ? "self" : "user",
      "in_room": inRoom,
      "method": method,
      "outcome": outcome,
      if (outcome == "cancelled") ...{
        "cancel_code": VerificationRecord.cancelCode(cancelCode),
        if (byOther != null) "cancelled_by": byOther ? "other" : "here",
      },
      "first_sync_pending": firstSyncPending,
      if (!requester && coldStart != null) "cold_start": coldStart,
      if (requestAgeMs != null) "request_age_ms": ms(requestAgeMs!),
      "shown_ms": step("shown"),
      if (shownMs != null && acceptedMs != null)
        "user_accept_ms": ms(acceptedMs - shownMs),
      "ready_ms": step("ready"),
      "start_ms": step("start"),
      "accept_ms": step("accept"),
      "key_sent_ms": step("key_sent"),
      "key_received_ms": step("key_received"),
      "sas_shown_ms": step("sas_shown"),
      "sas_confirmed_ms": step("sas_confirmed"),
      "mac_received_ms": step("mac_received"),
      "ssss_asked_ms": step("ssss"),
      "done_ms": step("done"),
      "end_ms": ms(nowMs - originMs),
      "sync_rounds": count(syncRounds),
      "sync_errors": count(syncErrors),
      "sync_apply_total_ms": ms(syncApplyTotalMs),
      "sync_apply_worst_ms": ms(syncApplyWorstMs),
      "recv_events": count(recvEvents),
      "recv_apply_wait_total_ms": ms(recvApplyWaitTotalMs),
      "recv_apply_wait_max_ms": ms(recvApplyWaitMaxMs),
      "recv_loop_busy_total_ms": ms(recvLoopBusyTotalMs),
      "recv_loop_busy_max_ms": ms(recvLoopBusyMaxMs),
    };
  }
}

/// A verification event seen before its request object was known.
class _Seen {
  final int atMs;
  final int round;
  final int? applyWaitMs;
  final int? loopBusyMs;
  final int? requestAgeMs;
  final bool firstSyncPending;
  _Seen(this.atMs, this.round, this.applyWaitMs, this.loopBusyMs,
      this.requestAgeMs, this.firstSyncPending);
}

/// Follows one live KeyVerification: a timer looks at it every 100 ms and
/// the SDK's onUpdate (wrapped, still calling whoever set it) catches the
/// steps that change no state.
class _Tracker {
  final _ClientWatch watch;
  final KeyVerification request;
  final VerificationRecord record;
  Timer? _timer;
  void Function()? _inner;
  bool _inWrapper = false;
  late final void Function() _wrapper = _onUpdate;
  bool _ended = false;

  static const _poll = Duration(milliseconds: 100);
  static const _giveUpMs = 15 * 60 * 1000;

  _Tracker(this.watch, this.request, this.record) {
    _wrap();
    _timer = Timer.periodic(_poll, (_) => _tick());
    _look(fromUpdate: false);
  }

  void _wrap() {
    final current = request.onUpdate;
    if (identical(current, _wrapper)) return;
    _inner = current;
    request.onUpdate = _wrapper;
  }

  void _onUpdate() {
    // Whoever set onUpdate after us may call us back from theirs.
    if (_inWrapper) return;
    _inWrapper = true;
    try {
      _look(fromUpdate: true);
    } catch (_) {
      // Diagnostics only: never in the way of the verification.
    }
    try {
      _inner?.call();
    } finally {
      _inWrapper = false;
    }
  }

  void _tick() {
    try {
      if (!_ended) _wrap();
      _look(fromUpdate: false);
    } catch (_) {
      _stop();
    }
  }

  void _look({required bool fromUpdate}) {
    if (_ended) return;
    final now = Telemetry.sinceStart;
    record.observe(
      now,
      request.state,
      request.lastStep,
      fromUpdate: fromUpdate,
    );
    if (request.isDone) {
      _finish(now);
    } else if (now - record.originMs > _giveUpMs) {
      _finish(now, abandoned: true);
    }
  }

  void _finish(int now, {bool abandoned = false}) {
    _ended = true;
    final done = request.state == KeyVerificationState.done;
    final code = request.canceledCode;
    final outcome = abandoned
        ? "abandoned"
        : done
            ? "done"
            : request.canceled
                ? "cancelled"
                : "error";
    // A cancel we received sets lastStep to it; our own cancel() doesn't.
    // "m.accepted": another of our devices answered.
    final byOther = request.lastStep == EventTypes.KeyVerificationCancel ||
        code == "m.accepted";
    Telemetry.record(
      "verification",
      record.fields(now, outcome: outcome, cancelCode: code, byOther: byOther),
    );
    _stop();
  }

  void _stop() {
    _ended = true;
    _timer?.cancel();
    _timer = null;
    watch.trackers.remove(this);
    // Leave the chain as it was, minus us, unless someone replaced us.
    if (identical(request.onUpdate, _wrapper)) request.onUpdate = _inner;
  }
}

/// One account's sync rounds and live verifications.
class _ClientWatch {
  final matrix.Client client;
  final List<_Tracker> trackers = [];
  final Map<String, _Seen> pending = {};

  /// Responses seen so far (1 = the session's first).
  int rounds = 0;
  int? requestAtMs;
  int? responseAtMs;
  int? prevResponseAtMs;

  /// Request time of the round whose response is being applied.
  int? appliedRequestAtMs;
  bool firstSyncDone = false;

  static const maxTrackers = 4;
  static const maxPending = 16;
  static const pendingExpiryMs = 15 * 60 * 1000;

  _ClientWatch(this.client);

  void onStatus(matrix.SyncStatusUpdate event) {
    final now = Telemetry.sinceStart;
    switch (event.status) {
      case matrix.SyncStatus.waitingForResponse:
        requestAtMs = now;
      case matrix.SyncStatus.processing:
        rounds++;
        prevResponseAtMs = responseAtMs;
        responseAtMs = now;
        appliedRequestAtMs = requestAtMs;
      case matrix.SyncStatus.finished:
        firstSyncDone = true;
        final response = responseAtMs;
        if (response != null) {
          for (final t in trackers) {
            t.record.syncRound(response, now);
          }
        }
      case matrix.SyncStatus.error:
        for (final t in trackers) {
          t.record.syncRound(now, now, error: true);
        }
      default:
        break;
    }
  }

  _Tracker? _find(String txn) {
    for (final t in trackers) {
      if (t.request.transactionId == txn) return t;
    }
    return null;
  }

  void onToDevice(matrix.ToDeviceEvent event) {
    final type = event.type;
    if (!type.startsWith("m.key.verification.")) return;
    final txn = event.content["transaction_id"];
    if (txn is! String) return;
    final now = Telemetry.sinceStart;
    final response = responseAtMs;
    final applyWait = response == null ? null : now - response;
    final sent = appliedRequestAtMs;
    final prev = prevResponseAtMs;
    final loopBusy =
        sent == null || prev == null || sent < prev ? null : sent - prev;

    var tracker = _find(txn);
    if (tracker == null &&
        type != EventTypes.KeyVerificationRequest &&
        type != EventTypes.KeyVerificationStart) {
      tracker = _discoverOutgoing(txn);
    }
    if (tracker == null) {
      if (type == EventTypes.KeyVerificationRequest ||
          type == EventTypes.KeyVerificationStart) {
        _addPending(txn, _seen(now, applyWait, loopBusy, event.content));
      }
      return;
    }
    if (type == EventTypes.KeyVerificationRequest ||
        (type == EventTypes.KeyVerificationStart &&
            !tracker.record.requester &&
            !tracker.record.has("accepted"))) {
      // The dialog came up first; this is the request it was for.
      _applySeen(
          tracker.record, _seen(now, applyWait, loopBusy, event.content));
      return;
    }
    tracker.record
        .received(now, type, applyWaitMs: applyWait, loopBusyMs: loopBusy);
  }

  _Seen _seen(int now, int? applyWait, int? loopBusy, Map content) {
    final ts = content["timestamp"];
    final age = ts is int ? DateTime.now().millisecondsSinceEpoch - ts : null;
    return _Seen(now, rounds, applyWait, loopBusy,
        age == null || age < 0 ? null : age, !firstSyncDone);
  }

  void _addPending(String txn, _Seen seen) {
    pending.removeWhere((_, s) => seen.atMs - s.atMs > pendingExpiryMs);
    if (pending.length >= maxPending) pending.remove(pending.keys.first);
    pending[txn] = seen;
  }

  static void _applySeen(VerificationRecord record, _Seen seen) {
    if (seen.atMs < record.originMs) {
      // Steps already marked keep their real time.
      final shift = record.originMs - seen.atMs;
      record.originMs = seen.atMs;
      record._steps.updateAll((_, v) => v + shift);
    }
    record.firstSyncPending = seen.firstSyncPending;
    record.coldStart = seen.round == 1;
    record.requestAgeMs = seen.requestAgeMs;
    record.received(seen.atMs, EventTypes.KeyVerificationRequest,
        applyWaitMs: seen.applyWaitMs, loopBusyMs: seen.loopBusyMs);
  }

  /// A to-device request we sent that nobody registered with us (started
  /// somewhere without [VerificationTelemetry.outgoing]): found by its
  /// transaction once the other side answers. Sent when the SDK last
  /// touched it, which for an unanswered request is its sending.
  _Tracker? _discoverOutgoing(String txn) {
    final request = client.encryption?.keyVerificationManager.getRequest(txn);
    if (request == null || !request.startedVerification) return null;
    final sinceSent =
        DateTime.now().difference(request.lastActivity).inMilliseconds;
    return start(request, requester: true, sinceSentMs: sinceSent);
  }

  _Tracker? start(KeyVerification request,
      {required bool requester, int sinceSentMs = 0}) {
    if (!Telemetry.enabled) return null;
    for (final t in trackers) {
      if (identical(t.request, request)) return t;
    }
    if (trackers.length >= maxTrackers || request.isDone) return null;
    final now = Telemetry.sinceStart;
    final origin = now - (sinceSentMs < 0 ? 0 : sinceSentMs);
    final record = VerificationRecord(
      requester: requester,
      self: request.userId == client.userID,
      inRoom: request.room != null,
      originMs: origin,
      firstSyncPending: !firstSyncDone,
    );
    if (!requester) {
      record.shown(now);
      final txn = request.transactionId;
      final seen = txn == null ? null : pending.remove(txn);
      if (seen != null) _applySeen(record, seen);
    }
    final tracker = _Tracker(this, request, record);
    if (!tracker._ended) trackers.add(tracker);
    return tracker;
  }
}

class VerificationTelemetry {
  static final Expando<_ClientWatch> _watches = Expando();

  /// Starts following [client]'s syncs and incoming verification requests.
  /// Called once per client when it's created, before its first sync.
  static void attach(matrix.Client client) {
    if (_watches[client] != null) return;
    final watch = _watches[client] = _ClientWatch(client);
    // Counted even while diagnostics are off, so "first sync" stays true
    // when they're switched on later.
    client.onSyncStatus.stream.listen(watch.onStatus);
    client.onToDeviceEvent.stream.listen((event) {
      if (Telemetry.enabled) watch.onToDevice(event);
    });
    client.onKeyVerificationRequest.stream.listen((request) {
      watch.start(request, requester: false);
    });
  }

  /// A verification this device just started; call right after
  /// startVerification() returns (the request has been sent by then).
  static void outgoing(KeyVerification request) {
    try {
      final client = request.client;
      attach(client);
      _watches[client]!.start(request, requester: true);
    } catch (_) {
      // Diagnostics only.
    }
  }
}
