import 'dart:async';

import 'package:commet/client/matrix/room_stream_router.dart';
import 'package:commet/client/matrix/components/emoticon/image_pack_types.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:matrix/matrix.dart' as matrix;

abstract class MatrixEmoticonStateManager {
  Map<String, dynamic> getState(String packKey);

  Map<String, dynamic> getAllStates();

  Future<void> setState(String packKey, Map<String, dynamic> content);

  Stream<void> get onStateChanged;

  String get id;
}

class MatrixEmoticonPersonalStateManager implements MatrixEmoticonStateManager {
  MatrixClient client;

  StreamController<void> onStateChangedController =
      StreamController.broadcast();

  MatrixEmoticonPersonalStateManager(this.client) {
    var mx = client.getMatrixClient();

    mx.onLoginStateChanged.stream
        .where((event) => event == matrix.LoginState.loggedIn)
        .listen((event) async {
      if (mx.accountDataLoading != null) {
        await mx.accountDataLoading;
      }

      onStateChangedController.add(null);
    });

    mx.onSync.stream.where((e) => e.accountData != null).listen((update) {
      if (update.accountData?.any((e) =>
              e.type == "im.ponies.user_emotes" ||
              ImagePackTypes.enabledRoomsTypes.contains(e.type)) ==
          true) {
        onStateChangedController.add(null);
      }
    });
  }

  @override
  Stream<void> get onStateChanged => onStateChangedController.stream;

  @override
  Map<String, dynamic> getAllStates() {
    var state = getState("im.ponies.user_emotes");
    if (state.isEmpty) return {};
    return {"im.ponies.user_emotes": state};
  }

  @override
  Future<void> setState(String packKey, Map<String, dynamic> content) {
    return client.getMatrixClient().setAccountData(
        client.getMatrixClient().userID!,
        "im.ponies.user_emotes",
        ImagePackTypes.withOrder(content));
  }

  @override
  Map<String, dynamic> getState(String packKey) {
    return client
            .getMatrixClient()
            .accountData['im.ponies.user_emotes']
            ?.content ??
        {};
  }

  @override
  String get id => client.identifier;
}

class MatrixEmoticonRoomStateManager implements MatrixEmoticonStateManager {
  matrix.Room room;

  StreamController<void> onStateChangedController =
      StreamController.broadcast();

  MatrixEmoticonRoomStateManager(this.room) {
    var mx = room.client;

    // Vommet: this room's state changes only (see RoomStreamRouter); issue
    // 731: packs under the spec's type and the old one.
    RoomStreamRouter.of(mx)
        .roomState(room.id)
        .where((event) => ImagePackTypes.isRoomPackType(event.state.type))
        .listen((event) {
      onStateChangedController.add(null);
    });

    onStateChangedController.add(null);
  }

  @override
  Map<String, dynamic> getAllStates() => ImagePackTypes.roomPacks(room);

  @override
  Map<String, dynamic> getState(String packKey) {
    var states = getAllStates();
    var data = states[packKey];
    return data;
  }

  @override
  Future<void> setState(String packKey, Map<String, dynamic> content) =>
      writeRoomPack(room, packKey, content);

  /// Vommet issue 731: writes a pack under every pack type this user may
  /// send (the spec's first), with its images numbered (MSC4389). Fails only
  /// when no write succeeded.
  static Future<void> writeRoomPack(
      matrix.Room room, String packKey, Map<String, dynamic> content) async {
    content = ImagePackTypes.withOrder(content);
    Object? firstError;
    var written = 0;
    for (final type in ImagePackTypes.roomPackTypes) {
      if (!room.canChangeStateEvent(type)) continue;
      try {
        final eventId = await room.client
            .setRoomStateWithKey(room.id, type, packKey, content);
        written++;
        final result = await room.getEventById(eventId);
        if (result != null) {
          (room.states[type] ??= {})[packKey] = result;
        }
      } catch (e) {
        firstError ??= e;
      }
    }
    if (written == 0) {
      throw firstError ??
          StateError("No permission to edit image packs in ${room.id}");
    }
  }

  @override
  Stream<void> get onStateChanged => onStateChangedController.stream;

  @override
  String get id => room.id;
}
