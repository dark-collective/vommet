// Vommet: the switch and shared state for the "New Home" experiment: Home is
// a set of tabs (Overview, People and Rooms by default), each with a side
// list in Home's column and a main page of cards (new_home_tabs.dart). Kept beside the
// feature, not in preferences.dart, so this topic doesn't touch a file most
// topics edit.
import 'dart:async';
import 'dart:convert';

import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/matrix/components/emoticon/matrix_emoticon_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/config/preferences/bool_preference.dart';
import 'package:commet/config/preferences/string_preference.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/ui/organisms/new_home/new_home_layout.dart';
import 'package:commet/ui/organisms/new_home/new_home_tab_icon.dart';
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

/// The view each Home tab shows (tab id to view id), kept while the app
/// runs; a tab not in it shows its first view (Vommet issue 674).
final ValueNotifier<Map<String, String>> newHomeViews = ValueNotifier({});

/// Phones: a Home tab was picked; the main page slides the main panel in
/// (like opening a room), so swiping back to the column works.
final StreamController<String> newHomeShowPage = StreamController.broadcast();

/// A tab's icon, by its name in [HomeTabs.icons] or its `m:` catalog name;
/// other kinds (emoji, images: [HomeTabIcon]) and unknown names draw the
/// default (Vommet issue 698).
IconData homeTabIcon(String name) =>
    catalogIconData(name) ??
    switch (name) {
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

/// The account (its Matrix id) Home's tabs are saved to on this device;
/// null or signed out = the first account (Vommet issue 647).
final NullableStringPreference newHomeLayoutAccount = NullableStringPreference(
    "vommet_new_home_layout_account",
    defaultValue: null);

/// Home's tabs, read from and saved to private account data of one account
/// ([newHomeLayoutAccount], else the first), so devices that pick the same
/// account share them. Only that account is written: the layout names the
/// other accounts' spaces. [layout] is the shown tab's main page, which the
/// cards and the Card library edit.
class HomeLayoutStore {
  HomeLayoutStore._() {
    newHomeTab.addListener(_follow);
    newHomeViews.addListener(_follow);
  }
  static final HomeLayoutStore instance = HomeLayoutStore._();

  final ValueNotifier<HomeTabs> tabs = _BuildSafeNotifier(HomeTabs.defaults);

  /// The shown view's cards (the shown tab's main page).
  final ValueNotifier<HomeLayout> layout =
      _BuildSafeNotifier(HomeTabs.defaults.tabs.first.main);

  MatrixClient? _client;
  ClientManager? _manager;
  StreamSubscription? _sync;

  /// The account Home's tabs are saved to.
  final ValueNotifier<MatrixClient?> account = ValueNotifier(null);

  /// The shown tab: [newHomeTab], or the first tab when it's gone; with
  /// every tab removed, an empty stand-in ([isEmpty]).
  HomeTab get current =>
      tabs.value.tab(newHomeTab.value) ??
      tabs.value.tabs.firstOrNull ??
      HomeTabs.none;

  /// Whether every tab was removed: Home says so and offers Customize.
  bool get isEmpty => tabs.value.tabs.isEmpty;

  /// The shown tab's shown view ([newHomeViews]), else its first.
  HomeView get currentView {
    final tab = current;
    return tab.view(newHomeViews.value[tab.id]) ?? tab.views.first;
  }

  /// Shows view [viewId] of tab [tabId] (from now on, while the app runs).
  void showView(String tabId, String viewId) {
    if (newHomeViews.value[tabId] == viewId) return;
    newHomeViews.value = {...newHomeViews.value, tabId: viewId};
  }

  /// Follows the picked Matrix account of [manager] ([newHomeLayoutAccount]),
  /// else its first; cheap to call again.
  void attach(ClientManager manager) {
    _manager = manager;
    final accounts = manager.clients.whereType<MatrixClient>();
    final picked = newHomeLayoutAccount.value;
    final client =
        accounts.where((c) => c.matrixClient.userID == picked).firstOrNull ??
            accounts.firstOrNull;
    if (identical(client, _client)) return;
    _sync?.cancel();
    _client = client;
    account.value = client;
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
    if (tab.id != newHomeTab.value && !isEmpty) {
      // Not while a listener of newHomeTab is running.
      Future.microtask(() {
        final first = tabs.value.tabs.firstOrNull;
        if (tabs.value.tab(newHomeTab.value) == null && first != null) {
          newHomeTab.value = first.id;
        }
      });
    }
    layout.value = currentView.main;
  }

  /// Saves Home's tabs to [client] from now on, on this device. An account
  /// that has none yet gets the current ones, so Home stays as it is; one
  /// that has them shows those.
  Future<void> useAccount(MatrixClient client) async {
    final manager = _manager;
    final userId = client.matrixClient.userID;
    if (manager == null || userId == null || identical(client, _client)) {
      return;
    }
    final current = tabs.value;
    final hasLayout =
        client.matrixClient.accountData[HomeLayout.accountDataKey] != null;
    if (!hasLayout) {
      try {
        await client.matrixClient.setAccountData(
            userId, HomeLayout.accountDataKey, current.toJson());
      } catch (e) {
        Log.w("New Home: couldn't save the Home layout: $e");
        return;
      }
    }
    await newHomeLayoutAccount.set(userId);
    undoHistory.value = const [];
    attach(manager);
    // Until the copy comes back in a sync.
    if (!hasLayout) _set(current);
  }

  /// Saves [next] as the shown view's cards.
  Future<void> save(HomeLayout next) => saveTabs(tabs.value
      .replaceTab(current.replaceView(currentView.copyWith(main: next))));

  /// Customize Home's Undo: every change made since Customize opened,
  /// oldest first. Empty outside Customize.
  final ValueNotifier<List<({HomeTabs before, HomeTabs after, String? label})>>
      undoHistory = ValueNotifier(const []);
  int _editors = 0;

  /// Customize Home opened: Undo starts from here.
  void beginEditing() {
    _editors++;
    undoHistory.value = const [];
  }

  /// Customize Home closed: the history goes (the changes stay saved).
  void endEditing() {
    if (_editors > 0) _editors--;
    if (_editors == 0) undoHistory.value = const [];
  }

  /// Undoes the newest change made in Customize Home. A tab it brings
  /// back is shown.
  Future<void> undo() async {
    final history = undoHistory.value;
    if (history.isEmpty) return;
    final last = history.last;
    undoHistory.value = history.sublist(0, history.length - 1);
    final shown = {for (final t in tabs.value.tabs) t.id};
    await saveTabs(last.before, undoable: false);
    final back = last.before.tabs.where((t) => !shown.contains(t.id));
    if (back.isNotEmpty) newHomeTab.value = back.first.id;
  }

  /// Saves [next]. While Customize Home is open the change can be undone,
  /// unless [undoable] is false (collapsing a section, Undo itself);
  /// [label] names it for Undo when the difference alone wouldn't.
  Future<void> saveTabs(HomeTabs next,
      {bool undoable = true, String? label}) async {
    final before = tabs.value;
    if (_editors > 0 &&
        undoable &&
        jsonEncode(before.toJson()) != jsonEncode(next.toJson())) {
      undoHistory.value = [
        ...undoHistory.value,
        (before: before, after: next, label: label)
      ];
    }
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
    final shown = tab.view(newHomeViews.value[tab.id]);
    if (shown == null || !shown.main.shows(type)) {
      final view = tab.viewHolding(type);
      if (view != null) showView(tab.id, view.id);
    }
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
  // Vommet issue 731: also MSC4476 pack rooms (see isStickerRoom).
  if (MatrixEmoticonComponent.isStickerRoom(matrixRoom)) return true;
  final replacement = matrixRoom
      .getState(matrix.EventTypes.RoomTombstone)
      ?.content["replacement_room"];
  return replacement is String &&
      matrixRoom.client.getRoomById(replacement)?.membership ==
          matrix.Membership.join;
}

/// The state event that marks a sticker room (Vommet's sticker rooms).
const String stickerRoomStateType = "im.nether.vommet.sticker_room";
