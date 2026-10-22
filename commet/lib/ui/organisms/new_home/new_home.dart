// Vommet: the switch and shared state for the "New Home" experiment: Home's
// column gets Overview / People / Rooms rows above the direct messages, and
// Overview shows cards you can reorder, hide and set up. Kept beside the
// feature, not in preferences.dart, so this topic doesn't touch a file most
// topics edit.
import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/config/preferences/bool_preference.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/ui/organisms/new_home/new_home_layout.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' as matrix;

final BoolPreference experimentNewHome =
    BoolPreference("vommet_experiment_new_home", defaultValue: false);

bool get newHomeEnabled => experimentNewHome.value;

/// Opens Home again so the column and main area switch straight away.
void onNewHomeToggled(bool _) => EventBus.openHomeScreen.add(null);

enum NewHomePage {
  overview("Overview", Icons.dashboard_rounded),
  people("People", Icons.people_alt_rounded),
  rooms("Rooms", Icons.tag_rounded);

  const NewHomePage(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// The page the Home column's rows picked (desktop main area).
final ValueNotifier<NewHomePage> newHomePage =
    ValueNotifier(NewHomePage.overview);

/// The Overview layout, read from and saved to private account data of the
/// first signed-in account, so all your devices share it.
class HomeLayoutStore {
  HomeLayoutStore._();
  static final HomeLayoutStore instance = HomeLayoutStore._();

  final ValueNotifier<HomeLayout> layout = ValueNotifier(HomeLayout.defaults);

  MatrixClient? _client;
  StreamSubscription? _sync;

  /// Follows the first Matrix account of [manager]; cheap to call again.
  void attach(ClientManager manager) {
    final client = manager.clients.whereType<MatrixClient>().firstOrNull;
    if (identical(client, _client)) return;
    _sync?.cancel();
    _client = client;
    if (client == null) {
      layout.value = HomeLayout.defaults;
      return;
    }
    _read();
    _sync = client.matrixClient.onSync.stream.listen((update) {
      if (update.accountData?.any((e) => e.type == HomeLayout.accountDataKey) ??
          false) {
        _read();
      }
    });
  }

  Map<String, dynamic>? get _content =>
      _client?.matrixClient.accountData[HomeLayout.accountDataKey]?.content;

  void _read() => layout.value = HomeLayout.parse(_content);

  Future<void> save(HomeLayout next) async {
    layout.value = next;
    final client = _client;
    final userId = client?.matrixClient.userID;
    if (client == null || userId == null) return;
    try {
      await client.matrixClient
          .setAccountData(userId, HomeLayout.accountDataKey, next.toJson());
    } catch (e) {
      Log.w("New Home: couldn't save the Overview layout: $e");
    }
  }
}

/// Whether Home should leave [room] out of its lists, like the room lists
/// do: a sticker room (they live under Settings › Emoticons) or a room that
/// was upgraded into one you're in.
bool hiddenFromNewHome(Room room) {
  if (room is! MatrixRoom) return false;
  final matrixRoom = room.matrixRoom;
  if (matrixRoom.getState(stickerRoomStateType) != null) return true;
  final replacement = matrixRoom
      .getState(matrix.EventTypes.RoomTombstone)
      ?.content["replacement_room"];
  return replacement is String &&
      matrixRoom.client.getRoomById(replacement)?.membership ==
          matrix.Membership.join;
}

/// The state event that marks a sticker room (Vommet's sticker rooms).
const String stickerRoomStateType = "im.nether.vommet.sticker_room";
