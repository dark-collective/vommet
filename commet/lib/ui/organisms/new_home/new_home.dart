// Vommet: the switch and shared state for the "New Home" experiment: Home is
// a set of tabs (Overview, People and Rooms by default), each with a side
// list in Home's column and a main page of cards (new_home_tabs.dart). Kept beside the
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
import 'package:commet/ui/organisms/new_home/new_home_tabs.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:matrix/matrix.dart' as matrix;

final BoolPreference experimentNewHome =
    BoolPreference("vommet_experiment_new_home", defaultValue: false);

bool get newHomeEnabled => experimentNewHome.value;

/// Opens Home again so the column and main area switch straight away.
void onNewHomeToggled(bool _) => EventBus.openHomeScreen.add(null);

/// The Home tab shown (its id), in Home's column and main area.
final ValueNotifier<String> newHomeTab = ValueNotifier(HomeTabs.overview);

/// Phones: a Home tab was picked; the main page slides the main panel in
/// (like opening a room), so swiping back to the column works.
final StreamController<String> newHomeShowPage = StreamController.broadcast();

/// A tab's icon, by its name in [HomeTabs.icons].
IconData homeTabIcon(String name) => switch (name) {
      "people" => Icons.people_alt_rounded,
      "tag" => Icons.tag_rounded,
      "star" => Icons.star_rounded,
      "chat" => Icons.chat_bubble_rounded,
      "mic" => Icons.mic_rounded,
      "gamepad" => Icons.sports_esports_rounded,
      "music" => Icons.music_note_rounded,
      "photo" => Icons.photo_library_rounded,
      "work" => Icons.work_rounded,
      "school" => Icons.school_rounded,
      "home" => Icons.home_rounded,
      "heart" => Icons.favorite_rounded,
      "code" => Icons.code_rounded,
      "sports" => Icons.sports_soccer_rounded,
      "book" => Icons.menu_book_rounded,
      _ => Icons.dashboard_rounded,
    };

/// Home's tabs, read from and saved to private account data of the first
/// signed-in account, so all your devices share them. [layout] is the shown
/// tab's main page, which the cards and the Card library edit.
class HomeLayoutStore {
  HomeLayoutStore._() {
    newHomeTab.addListener(_follow);
  }
  static final HomeLayoutStore instance = HomeLayoutStore._();

  final ValueNotifier<HomeTabs> tabs = _BuildSafeNotifier(HomeTabs.defaults);

  /// The shown tab's main page.
  final ValueNotifier<HomeLayout> layout =
      _BuildSafeNotifier(HomeTabs.defaults.tabs.first.main);

  MatrixClient? _client;
  StreamSubscription? _sync;

  /// The shown tab: [newHomeTab], or the first tab when it's gone.
  HomeTab get current =>
      tabs.value.tab(newHomeTab.value) ?? tabs.value.tabs.first;

  /// Follows the first Matrix account of [manager]; cheap to call again.
  void attach(ClientManager manager) {
    final client = manager.clients.whereType<MatrixClient>().firstOrNull;
    if (identical(client, _client)) return;
    _sync?.cancel();
    _client = client;
    if (client == null) {
      _set(HomeTabs.defaults);
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

  void _read() => _set(HomeTabs.parse(_content));

  void _set(HomeTabs next) {
    tabs.value = next;
    _follow();
  }

  /// Keeps [layout] on the shown tab; a removed tab falls back to the first.
  void _follow() {
    final tab = current;
    if (tab.id != newHomeTab.value) {
      // Not while a listener of newHomeTab is running.
      Future.microtask(() {
        if (tabs.value.tab(newHomeTab.value) == null) {
          newHomeTab.value = tabs.value.tabs.first.id;
        }
      });
    }
    layout.value = tab.main;
  }

  /// Saves [next] as the shown tab's main page.
  Future<void> save(HomeLayout next) =>
      saveTabs(tabs.value.replaceTab(current.copyWith(main: next)));

  Future<void> saveTabs(HomeTabs next) async {
    _set(next);
    final client = _client;
    final userId = client?.matrixClient.userID;
    if (client == null || userId == null) return;
    try {
      await client.matrixClient
          .setAccountData(userId, HomeLayout.accountDataKey, next.toJson());
    } catch (e) {
      Log.w("New Home: couldn't save the Home layout: $e");
    }
  }

  /// Shows the first tab holding [type] (a card or whole page). False when
  /// no tab holds it.
  bool showTabHolding(String type) {
    final tab = tabs.value.tabHolding(type);
    if (tab == null) return false;
    newHomeTab.value = tab.id;
    return true;
  }
}

/// Takes a new value at once, but tells its listeners after the frame when
/// it changes while widgets build (the first [HomeLayoutStore.attach] runs
/// from a build, with other widgets already listening).
class _BuildSafeNotifier<T> extends ValueNotifier<T> {
  _BuildSafeNotifier(super.value);

  bool _scheduled = false;

  @override
  void notifyListeners() {
    final binding = SchedulerBinding.instance;
    if (binding.schedulerPhase != SchedulerPhase.persistentCallbacks) {
      super.notifyListeners();
      return;
    }
    if (_scheduled) return;
    _scheduled = true;
    binding.addPostFrameCallback((_) {
      _scheduled = false;
      super.notifyListeners();
    });
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
