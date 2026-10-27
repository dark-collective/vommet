import 'dart:async';
import 'dart:typed_data';

import 'package:commet/client/matrix/components/direct_messages/matrix_direct_chat_ids.dart';
import 'package:commet/client/client.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/nicknames/nickname_experiment.dart';
import 'package:commet/client/matrix/nicknames/nickname_rules.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/telemetry/telemetry.dart';
import 'package:matrix/matrix.dart' as matrix;

/// Vommet: applies your per-space / per-room nicknames and pictures by
/// writing your own `m.room.member` displayname and avatar_url in each room
/// (name and picture in one write). Behind the
/// `vommet_experiment_space_nicknames` experiment: with it off nothing here
/// writes anything (the saved rules just stay in account data).
///
/// Every write goes through one queue, so batches never interleave, and a
/// room is only written when the server's current member event shows a
/// different name. Nothing reacts to member events, so writes can't loop.
class MatrixNicknames {
  final MatrixClient client;

  /// Pause between member-event writes when applying to many rooms, so a big
  /// space doesn't hit the server's rate limit.
  static const writeInterval = Duration(milliseconds: 400);

  /// After a global name change, check the rules again this much later, in
  /// case the server rewrote the rooms after our first pass.
  static const recheckDelay = Duration(seconds: 30);

  /// Retries of one write when the server answers M_LIMIT_EXCEEDED.
  static const maxRateLimitRetries = 4;

  MatrixNicknames(this.client);

  static final Expando<MatrixNicknames> _instances = Expando();

  /// The (one) instance for [client].
  static MatrixNicknames of(MatrixClient client) =>
      _instances[client] ??= MatrixNicknames(client);

  static bool get enabled => experimentSpaceNicknames.value;

  matrix.Client get _mx => client.getMatrixClient();

  NicknameRules get rules => NicknameRules.fromJson(
      _mx.accountData[NicknameRules.accountDataType]?.content);

  /// Your per-space / per-room pictures (mxc URIs), same shape as [rules].
  NicknameRules get avatarRules => NicknameRules.fromJson(
      _mx.accountData[NicknameRules.avatarAccountDataType]?.content);

  Future<void> _queue = Future.value();

  /// Runs [job] after every job queued before it.
  Future<T> _enqueue<T>(Future<T> Function() job) {
    final result = _queue.then((_) => job());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<void> _saveRules(NicknameRules rules,
      {String type = NicknameRules.accountDataType}) async {
    final content = rules.toJson();
    await _mx.setAccountData(_mx.userID!, type, content);

    // setAccountData is only the PUT; the SDK updates accountData when the
    // next sync delivers it. Mirror it now, so applying right after saving
    // uses the new rules instead of the old ones.
    _mx.accountData[type] = matrix.BasicEvent(type: type, content: content);
  }

  /// A space admin decides which rooms their space lists, so a direct
  /// message never takes a space's nickname: it would put a name meant for
  /// that space in front of whoever we're talking to.
  bool _isDirectMessage(String roomId) {
    final room = _mx.getRoomById(roomId);
    return room != null &&
        MatrixDirectChatIds.mayBeDirectChat(room) &&
        room.isDirectChat;
  }

  /// Spaces containing [roomId], nearest first. For a space, itself first.
  /// None for a direct message. Among the parents of one room, the one the
  /// room names as its canonical parent comes first, then by id, so every
  /// device picks the same space when a room is in several.
  List<String> parentSpaceIds(String roomId) {
    final result = <String>[];
    if (_isDirectMessage(roomId)) return result;
    var frontier = <String>[roomId];
    if (client.getSpace(roomId) != null) result.add(roomId);

    while (frontier.isNotEmpty) {
      final next = <String>[];
      for (final id in frontier) {
        final parents = [
          for (final space in client.spaces)
            if ((space.containsRoom(id) ||
                    space.subspaces.any((s) => s.identifier == id)) &&
                !result.contains(space.identifier))
              space.identifier,
        ];
        final room = _mx.getRoomById(id);
        bool canonical(String spaceId) =>
            room?.getState("m.space.parent", spaceId)?.content["canonical"] ==
            true;
        for (final p in orderParents(parents, canonical)) {
          if (result.contains(p)) continue;
          result.add(p);
          next.add(p);
        }
      }
      frontier = next;
    }
    return result;
  }

  /// [parents] of one room in the order rules look at them: its canonical
  /// parent first, then by id.
  static List<String> orderParents(
          Iterable<String> parents, bool Function(String) canonical) =>
      [...parents]..sort((a, b) {
          final ca = canonical(a), cb = canonical(b);
          if (ca != cb) return ca ? -1 : 1;
          return a.compareTo(b);
        });

  (String?, NicknameSource, String?) effective(String roomId) =>
      rules.resolve(roomId, parentSpaceIds(roomId));

  /// Your picture rule for [roomId] (an mxc URI), like [effective].
  (String?, NicknameSource, String?) effectiveAvatar(String roomId) =>
      avatarRules.resolve(roomId, parentSpaceIds(roomId));

  /// Every room and subspace inside [space], and the space itself.
  List<String> _roomsIn(Space space, [Set<String>? seen]) {
    seen ??= {};
    if (!seen.add(space.identifier)) return [];
    return [
      space.identifier,
      for (final r in space.rooms)
        if (!_isDirectMessage(r.identifier)) r.identifier,
      for (final s in space.subspaces) ..._roomsIn(s, seen),
    ];
  }

  /// Every room some name or picture rule covers.
  List<String> _roomsWithRules(NicknameRules r, [NicknameRules? avatars]) {
    final result = <String>{...r.rooms.keys, ...?avatars?.rooms.keys};
    for (final id in [...r.spaces.keys, ...?avatars?.spaces.keys]) {
      final space = client.getSpace(id);
      if (space != null) result.addAll(_roomsIn(space));
    }
    return result.toList();
  }

  /// Sets (or with null, clears) your nickname for one room and applies it.
  Future<void> setRoomNickname(String roomId, String? name) async {
    final r = rules;
    final clearing = name == null || name.trim().isEmpty;
    final trigger = clearing ? "room_clear" : "room_set";
    if (clearing) {
      r.rooms.remove(roomId);
    } else {
      r.rooms[roomId] = name.trim();
    }
    await _saveRulesRecorded(r, trigger);
    final failed = await _applyAll([roomId], trigger: trigger);
    if (failed.isNotEmpty) throw Exception("Couldn't update your name here");
  }

  /// Sets (or clears) your nickname for a space and applies it to the space
  /// and every room in it that has no own override. Clearing only touches
  /// rooms that still show the space nickname, so names set elsewhere stay.
  /// Returns the rooms where writing failed.
  Future<List<String>> setSpaceNickname(Space space, String? name,
      {void Function(int done, int total)? onProgress}) async {
    final r = rules;
    final previous = r.spaces[space.identifier];
    final clearing = name == null || name.trim().isEmpty;
    if (clearing) {
      if (previous == null) return [];
      r.spaces.remove(space.identifier);
    } else {
      r.spaces[space.identifier] = name.trim();
    }
    final trigger = clearing ? "space_clear" : "space_set";
    await _saveRulesRecorded(r, trigger);

    return _applyAll(_roomsIn(space),
        trigger: trigger,
        onlyIfShowing: clearing ? previous : null,
        onProgress: onProgress);
  }

  /// Uploads [bytes] (shrunk to an avatar size) for a per-place picture.
  Future<String> uploadPicture(Uint8List bytes, String? mimeType) async {
    final file = await matrix.MatrixImageFile.shrink(
        bytes: bytes,
        name: "avatar",
        mimeType: mimeType == "" ? null : mimeType,
        maxDimension: 512);
    final uri = await _mx.uploadContent(file.bytes,
        filename: file.name, contentType: file.mimeType);
    return uri.toString();
  }

  /// Sets (or with null, clears) your picture for one room and applies it.
  /// Clearing only touches the room if it still shows the old picture.
  Future<void> setRoomAvatar(String roomId, String? mxc) async {
    final r = avatarRules;
    final previous = r.rooms[roomId];
    if (mxc == null) {
      if (previous == null) return;
      r.rooms.remove(roomId);
    } else {
      r.rooms[roomId] = mxc;
    }
    final trigger = mxc == null ? "room_clear" : "room_set";
    await _saveRulesRecorded(r, trigger,
        type: NicknameRules.avatarAccountDataType);
    final failed = await _applyAll([roomId],
        trigger: trigger, names: false, revertAvatarFrom: previous);
    if (failed.isNotEmpty) {
      throw Exception("Couldn't update your picture here");
    }
  }

  /// Sets (or clears) your picture for a space and applies it to the space
  /// and every room in it without its own picture. Clearing only touches
  /// rooms still showing the space's picture. Names are left alone. Returns
  /// the rooms where writing failed.
  Future<List<String>> setSpaceAvatar(Space space, String? mxc,
      {void Function(int done, int total)? onProgress}) async {
    final r = avatarRules;
    final previous = r.spaces[space.identifier];
    if (mxc == null) {
      if (previous == null) return [];
      r.spaces.remove(space.identifier);
    } else {
      r.spaces[space.identifier] = mxc;
    }
    final trigger = mxc == null ? "space_clear" : "space_set";
    await _saveRulesRecorded(r, trigger,
        type: NicknameRules.avatarAccountDataType);
    return _applyAll(_roomsIn(space),
        trigger: trigger,
        names: false,
        revertAvatarFrom: previous,
        onProgress: onProgress);
  }

  Timer? _recheck;

  /// After your global display name ([globalName]) or picture changed from
  /// this app, writes the nicknames and pictures back: some servers rewrite
  /// every room's name and picture on a global change. Checks once now and
  /// once after [recheckDelay].
  void reapplyAfterGlobalChange({String? globalName}) {
    if (!enabled || _roomsWithRules(rules, avatarRules).isEmpty) return;

    Future<void> pass(String trigger) async {
      if (!enabled) return;
      final failed = await _applyAll(_roomsWithRules(rules, avatarRules),
          trigger: trigger, globalName: globalName);
      if (failed.isNotEmpty) {
        Log.w("Nicknames: couldn't re-apply in ${failed.length} room(s)");
      }
    }

    _recheck?.cancel();
    pass("global_change")
        .catchError((Object e) => Log.w("Nicknames: re-apply failed: $e"));
    _recheck = Timer(recheckDelay, () {
      pass("global_recheck")
          .catchError((Object e) => Log.w("Nicknames: re-apply failed: $e"));
    });
  }

  /// Saves [r], recording a `nickname_apply` event for [trigger] if that
  /// fails (nothing gets applied then).
  Future<void> _saveRulesRecorded(NicknameRules r, String trigger,
      {String type = NicknameRules.accountDataType}) async {
    try {
      await _saveRules(r, type: type);
    } catch (e) {
      _record(
          trigger,
          NicknameBatchStats()
            ..failStep = "save"
            ..firstError = e);
      rethrow;
    }
  }

  /// One `nickname_apply` telemetry event: counts only, never room ids or
  /// names. A no-op unless you opted in to diagnostics.
  void _record(String trigger, NicknameBatchStats stats, {int? ms}) {
    final r = rules;
    Telemetry.record("nickname_apply", {
      "trigger": trigger,
      ...stats.toFields(),
      "space_rules": r.spaces.length,
      "room_rules": r.rooms.length,
      "ms": ms,
    });
  }

  /// Applies the rules to [roomIds] one at a time through the queue. Returns
  /// the rooms where writing failed. With [names] false only pictures are
  /// written; [revertAvatarFrom] is a picture rule just removed (see
  /// [_applyTo]).
  Future<List<String>> _applyAll(List<String> roomIds,
      {required String trigger,
      String? onlyIfShowing,
      bool names = true,
      String? revertAvatarFrom,
      String? globalName,
      void Function(int done, int total)? onProgress}) {
    return _enqueue(() async {
      final me = _mx.userID;
      final failed = <String>[];
      if (me == null) return failed;
      final stats = NicknameBatchStats()..rooms = roomIds.length;
      final clock = Stopwatch()..start();

      // Fetched at most once per batch, and only when a room needs it.
      matrix.CachedProfileInformation? profile;
      Future<matrix.CachedProfileInformation> profileOnce() async {
        try {
          return profile ??=
              await _mx.getUserProfile(me, maxCacheAge: Duration.zero);
        } catch (e) {
          throw _StepError("profile", e);
        }
      }

      Future<String?> globalNameOnce() async =>
          globalName ?? (await profileOnce()).displayname;
      Future<String?> globalAvatarOnce() async =>
          (await profileOnce()).avatarUrl?.toString();

      for (var i = 0; i < roomIds.length; i++) {
        onProgress?.call(i, roomIds.length);
        try {
          final result = await _applyTo(roomIds[i], me,
              stats: stats,
              onlyIfShowing: onlyIfShowing,
              names: names,
              revertAvatarFrom: revertAvatarFrom,
              globalName: globalNameOnce,
              globalAvatar: globalAvatarOnce);
          stats.count(result);
          if (result == NicknameApplyResult.written) {
            await Future.delayed(writeInterval);
          }
        } catch (e) {
          Log.w("Nicknames: failed to set your name in ${roomIds[i]}: $e");
          failed.add(roomIds[i]);
          stats.failed++;
          if (stats.firstError == null) {
            stats.failStep = e is _StepError ? e.step : "write";
            stats.firstError = e is _StepError ? e.error : e;
          }
        }
      }
      onProgress?.call(roomIds.length, roomIds.length);
      _record(trigger, stats, ms: clock.elapsedMilliseconds);
      return failed;
    });
  }

  /// Writes the effective nickname and picture for [roomId] if the server
  /// shows different ones. With no name rule, goes back to the global display
  /// name. A picture is only written where a picture rule applies, or, when
  /// the rule [revertAvatarFrom] was just removed and the room still shows
  /// it, back to the global picture: a picture set here from another app
  /// stays.
  Future<NicknameApplyResult> _applyTo(String roomId, String me,
      {required NicknameBatchStats stats,
      String? onlyIfShowing,
      bool names = true,
      String? revertAvatarFrom,
      required Future<String?> Function() globalName,
      required Future<String?> Function() globalAvatar}) async {
    final room = _mx.getRoomById(roomId);
    if (room == null || room.membership != matrix.Membership.join) {
      return NicknameApplyResult.notJoined;
    }

    // Read the server's copy, not the local state: it may be behind (a
    // global name change still syncing), or missing (lazy-loaded members).
    // Never write a member event from scratch; that would drop the avatar.
    Map<String, Object?> current;
    try {
      current = await _mx.getRoomStateWithKey(
          roomId, matrix.EventTypes.RoomMember, me);
    } catch (e) {
      final local = room.getState(matrix.EventTypes.RoomMember, me)?.content;
      if (local == null) throw _StepError("read", e);
      stats.readFallback++;
      current = local;
    }
    if (current["membership"] != "join") return NicknameApplyResult.notJoined;
    if (names &&
        onlyIfShowing != null &&
        current["displayname"] != onlyIfShowing) {
      return NicknameApplyResult.kept;
    }

    String? name;
    if (names) {
      (name, _, _) = effective(roomId);
      name ??= await globalName();
    }

    var (avatar, _, _) = effectiveAvatar(roomId);
    var setAvatar = avatar != null;
    if (!setAvatar && revertAvatarFrom != null) {
      if (current["avatar_url"] != revertAvatarFrom) {
        if (!names) return NicknameApplyResult.kept;
      } else {
        avatar = await globalAvatar();
        setAvatar = true;
      }
    }

    final content = NicknameRules.updatedMemberContent(current, name,
        onlyIfShowing: onlyIfShowing,
        setName: names,
        setAvatar: setAvatar,
        avatar: avatar);
    if (content == null) return NicknameApplyResult.unchanged;

    var wait = const Duration(seconds: 4);
    for (var attempt = 0;; attempt++) {
      try {
        await _mx.setRoomStateWithKey(
            roomId, matrix.EventTypes.RoomMember, me, content);
        return NicknameApplyResult.written;
      } on matrix.MatrixException catch (e) {
        if (e.error == matrix.MatrixError.M_LIMIT_EXCEEDED) {
          stats.rateLimited++;
        }
        if (e.error != matrix.MatrixError.M_LIMIT_EXCEEDED ||
            attempt >= maxRateLimitRetries) {
          rethrow;
        }
        final retryAfter = e.retryAfterMs;
        final delay =
            retryAfter != null ? Duration(milliseconds: retryAfter) : wait;
        Log.i("Nicknames: rate limited, waiting ${delay.inSeconds} s");
        await Future.delayed(delay);
        wait *= 2;
      }
    }
  }

  StreamSubscription? _roomSubscription;
  StreamSubscription? _spaceSubscription;

  /// Rooms and subspaces joined later get their space's nickname.
  void listenForJoins() {
    _roomSubscription ??=
        client.onRoomAdded.listen((room) => _onJoined(room.identifier));
    _spaceSubscription ??=
        client.onSpaceAdded.listen((space) => _onJoined(space.identifier));
  }

  /// How old a join can be and still count as new. A device that was
  /// offline longer leaves it to the device you joined from.
  static const freshJoinWindow = Duration(hours: 24);

  /// Whether your latest member event in [roomId] is the join itself, and
  /// recent. Rooms also get "added" when they load (at startup, and sliding
  /// sync streams them in later); those already carry a name change after
  /// the join, or an old join, so they're left alone instead of re-checked
  /// on every launch.
  bool _isFreshJoin(String roomId) {
    final me = _mx.userID;
    if (me == null) return false;
    final event =
        _mx.getRoomById(roomId)?.getState(matrix.EventTypes.RoomMember, me);
    if (event is! matrix.Event) return false;
    if (event.content["membership"] != "join") return false;
    if (event.prevContent?["membership"] == "join") return false;
    return DateTime.now().difference(event.originServerTs) < freshJoinWindow;
  }

  void _onJoined(String roomId) {
    if (!enabled) return;
    final r = rules, a = avatarRules;
    if (r.isEmpty && a.isEmpty) return;
    if (!_isFreshJoin(roomId)) return;
    final parents = parentSpaceIds(roomId);
    final (name, _, _) = r.resolve(roomId, parents);
    final (avatar, _, _) = a.resolve(roomId, parents);
    if (name == null && avatar == null) return;
    _applyAll([roomId], trigger: "join").then((failed) {
      if (failed.isNotEmpty) {
        Log.w("Nicknames: couldn't set your name in new room $roomId");
      }
    });
  }

  void dispose() {
    _roomSubscription?.cancel();
    _spaceSubscription?.cancel();
    _recheck?.cancel();
  }
}

/// What applying the rules to one room did.
enum NicknameApplyResult { written, unchanged, kept, notJoined }

/// Counts for one batch, for the `nickname_apply` telemetry event.
class NicknameBatchStats {
  int rooms = 0;
  int written = 0;
  int unchanged = 0;
  int kept = 0;
  int notJoined = 0;
  int failed = 0;
  int rateLimited = 0;
  int readFallback = 0;

  /// Where the first failure happened: save, read, profile or write.
  String? failStep;
  Object? firstError;

  void count(NicknameApplyResult result) {
    switch (result) {
      case NicknameApplyResult.written:
        written++;
      case NicknameApplyResult.unchanged:
        unchanged++;
      case NicknameApplyResult.kept:
        kept++;
      case NicknameApplyResult.notJoined:
        notJoined++;
    }
  }

  /// Telemetry fields: counts, the failing step, and the first error's kind,
  /// Dart type, HTTP status and Matrix errcode (never its message).
  Map<String, Object?> toFields() => {
        "rooms": rooms,
        "written": written,
        "unchanged": unchanged,
        "kept": kept,
        "not_joined": notJoined,
        "failed": failed,
        "rate_limited": rateLimited,
        "read_fallback": readFallback,
        "fail_step": failStep,
        ...Telemetry.errorFields(firstError),
      };
}

/// A failure tagged with the step it happened in.
class _StepError implements Exception {
  _StepError(this.step, this.error);
  final String step;
  final Object error;

  @override
  String toString() => "$step: $error";
}
