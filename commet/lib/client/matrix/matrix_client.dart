import 'dart:async';
import 'package:commet/telemetry/sync_stats.dart';
import 'package:commet/telemetry/telemetry_http.dart';
import 'package:commet/telemetry/history_sharing_telemetry.dart';
import 'package:commet/telemetry/room_key_share_telemetry.dart';
import 'package:commet/telemetry/telemetry.dart';
import 'package:commet/telemetry/telemetry_errors.dart';
import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;
import 'package:commet/client/alert.dart';
import 'package:commet/client/auth.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/components/component.dart';
import 'package:commet/client/components/component_registry.dart';
import 'package:commet/client/error_profile.dart';
import 'package:commet/client/matrix/auth/matrix_oidc_login_flow.dart';
import 'package:commet/client/matrix/auth/matrix_sso_login_flow.dart';
import 'package:commet/client/matrix/offline_sending.dart';
import 'package:commet/client/matrix/auth/matrix_username_password_login_flow.dart';
import 'package:commet/client/matrix/components/encrypted_search_index/matrix_encrypted_search_index_component.dart';
import 'package:commet/client/matrix/components/matrix_sync_listener.dart';
import 'package:commet/client/matrix/nicknames/matrix_nicknames.dart';
import 'package:commet/client/matrix/components/profile/matrix_profile_component.dart';
import 'package:commet/client/matrix/components/emoticon/matrix_emoticon_component.dart';
import 'package:commet/client/matrix/components/voip_room/matrix_voip_room_component.dart';
import 'package:commet/client/matrix/database/matrix_database.dart';
import 'package:commet/ui/organisms/space_join_picker/space_join_picker.dart';
import 'package:commet/client/matrix/extensions/matrix_client_extensions.dart';
import 'package:commet/client/matrix/matrix_native_implementations.dart';
import 'package:commet/client/matrix/matrix_room_preview.dart';
import 'package:commet/client/matrix/power_level_tags.dart';
import 'package:commet/client/room_preview.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/config/build_config.dart';
import 'package:commet/client/matrix/matrix_default_push_rule.dart';
import 'package:commet/config/global_config.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/diagnostic/diagnostics.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:commet/main.dart';
import 'package:commet/client/components/push_notification/sent_here.dart';
import 'package:commet/utils/notifying_list.dart';
import 'package:commet/utils/notifying_list_index.dart';
import 'package:commet/utils/notifying_list_filter.dart';
import 'package:commet/utils/stored_stream_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:commet/ui/navigation/navigation_utils.dart';
import 'package:commet/ui/pages/settings/app_settings_page.dart';
import 'dart:convert';
import 'package:commet/client/client.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:drift/drift.dart' show BooleanExpressionOperators;
import 'package:matrix_dart_sdk_drift_db/matrix_dart_sdk_drift_db.dart'
    show MatrixSdkDriftDatabase;
import 'package:matrix/encryption.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vodozemac;

import '../../ui/atoms/code_block.dart';
import 'matrix_room.dart';
import 'matrix_space.dart';
import 'package:vodozemac/vodozemac.dart' as vod;
import 'package:commet/config/preferences/preference.dart';
import 'package:matrix/src/models/timeline_chunk.dart' as mx_chunk;

class MatrixClient extends Client {
  late matrix.Client _matrixClient;
  late final List<Component<MatrixClient>> componentsInternal;

  Future? firstSync;

  bool firstSyncComplete = false;

  // Vommet: rooms and spaces used to call postLoad() (load all their
  // non-preloaded state) in their constructors, i.e. every room at once at
  // startup. On a 231-room account those queries queued on the database
  // for ~5 s each, and the room list's own lookups (names, avatars,
  // presence) and saving the first sync waited behind them. They now load
  // one at a time, spaces first; opening a room still loads it at once
  // (the timeline calls postLoad directly).
  final List<(matrix.Room, void Function())> _spacePostLoads = [];
  final List<(matrix.Room, void Function())> _roomPostLoads = [];
  bool _postLoadRunning = false;
  Completer<void>? _postLoadsDrained;

  /// Completes when the queued room loads have drained; immediately if none
  /// are running. Rooms are queued synchronously while [init] builds the
  /// room list, so after it returns this covers the startup loads.
  @override
  Future<void> get startupLoadsDone {
    if (!_postLoadRunning) return Future.value();
    return (_postLoadsDrained ??= Completer<void>()).future;
  }

  /// Vommet: true while the deferred room-state loads from startup are still
  /// running (recorded with timeline timings, to see whether they slow down
  /// opening a room).
  bool get startupLoadsRunning => _postLoadRunning;

  void queuePostLoad(matrix.Room room,
      {bool isSpace = false, required void Function() onLoaded}) {
    (isSpace ? _spacePostLoads : _roomPostLoads).add((room, onLoaded));
    if (!_postLoadRunning) _drainPostLoads();
  }

  /// Vommet: rooms whose deferred state is loaded with one query. One query
  /// per room spent most of its time waiting between queries rather than
  /// running them (8.1 s for 235 rooms on a phone, 1.2 s of it database
  /// work), and the splash waits for these loads.
  static const _postLoadBatchSize = 40;

  /// What [matrix.Room.postLoad] does, for several rooms at once: their
  /// non-preloaded state (preloaded types are left out, members are stored
  /// separately) from one query. Falls back to [matrix.Room.postLoad] on a
  /// database other than the drift store. Returns how many rooms it loaded.
  /// Public for unit_test/batched_postload_test.dart (the analyzer doesn't
  /// count unit_test/ as tests, so @visibleForTesting would warn there).
  ///
  /// Vommet issue 581: runs inside a database transaction, so it happens
  /// between syncs, never during one. A sync saves a partial room's deferred
  /// state (m.room.topic and the like) only to the database and leaves it to
  /// this load. The web database answered reads made during a sync with the
  /// data from before the sync's writes, so a load started for the rooms that
  /// sync had just added missed their state, marked them loaded anyway, and
  /// their topics stayed missing until a restart. On drift, a sync could also
  /// save new state between the query and the rooms being marked loaded.
  static Future<int> postLoadRooms(
      matrix.Client client, List<matrix.Room> rooms) async {
    if (rooms.isEmpty) return 0;
    var count = 0;
    await client.database.transaction(() async {
      count = await _postLoadRoomsNow(client, rooms);
    });
    return count;
  }

  static Future<int> _postLoadRoomsNow(
      matrix.Client client, List<matrix.Room> rooms) async {
    final database = client.database;
    if (database is! MatrixSdkDriftDatabase) {
      for (final room in rooms) {
        await room.postLoad();
      }
      return rooms.length;
    }
    final byId = {for (final room in rooms) room.id: room};
    final important = client.importantStateEvents.toList();
    final db = database.db;
    // Vommet: timed apart (Developer › Performance, opt-in diagnostics) to
    // tell waiting for the database from decoding on the UI isolate.
    final query = Stopwatch()..start();
    final rows = await (db.select(db.nonPreloadRoomState)
          ..where((tbl) =>
              tbl.roomId.isIn(byId.keys) & tbl.type.isNotIn(important)))
        .get();
    Diagnostics.general.addResult("Deferred room state query", query.elapsed);
    final apply = Stopwatch()..start();
    for (final row in rows) {
      final room = byId[row.roomId];
      // Opened meanwhile: its timeline already ran postLoad.
      if (room == null || !room.partial) continue;
      room.setState(matrix.Event.fromJson(
          jsonDecode(row.content) as Map<String, dynamic>, room));
    }
    for (final room in rooms) {
      room.partial = false;
    }
    Diagnostics.general.addResult("Deferred room state apply", apply.elapsed);
    return rooms.length;
  }

  Future<void> _drainPostLoads() async {
    _postLoadRunning = true;
    final clock = Stopwatch()..start();
    var count = 0;

    // Vommet: keep the app responsive while this runs. Each onLoaded makes
    // the room lists rebuild; one per room meant hundreds of rebuilds in a
    // row and taps went unanswered until the queue drained (operator
    // report). Callbacks are batched (at most every 250 ms, and at the end)
    // and the loop yields to the event loop after every room, so input and
    // frames get their turn.
    final pending = <void Function()>[];
    final sinceFlush = Stopwatch()..start();
    void flush() {
      final callbacks = Stopwatch()..start();
      for (final onLoaded in pending) {
        try {
          onLoaded();
        } catch (e, s) {
          Log.onError(e, s, content: "Deferred postLoad callback failed");
        }
      }
      pending.clear();
      sinceFlush.reset();
      // Vommet: the rooms' and spaces' own updates once their state is in;
      // timed apart from the query and its apply for the startup breakdown.
      Diagnostics.general
          .addResult("Deferred room state callbacks", callbacks.elapsed);
    }

    try {
      while (_spacePostLoads.isNotEmpty || _roomPostLoads.isNotEmpty) {
        final batch = <(matrix.Room, void Function())>[];
        while (batch.length < _postLoadBatchSize &&
            (_spacePostLoads.isNotEmpty || _roomPostLoads.isNotEmpty)) {
          batch.add(_spacePostLoads.isNotEmpty
              ? _spacePostLoads.removeAt(0)
              : _roomPostLoads.removeAt(0));
        }
        try {
          count += await postLoadRooms(_matrixClient, [
            for (final (room, _) in batch)
              if (room.partial) room
          ]);
          for (final (_, onLoaded) in batch) {
            pending.add(onLoaded);
          }
        } catch (e, s) {
          Log.onError(e, s, content: "Deferred batch postLoad failed");
          // One at a time, as before, so one bad room doesn't hold up the
          // rest of the batch.
          for (final (room, onLoaded) in batch) {
            try {
              if (room.partial) {
                // Vommet issue 581: between syncs, as postLoadRooms does.
                await _matrixClient.database.transaction(room.postLoad);
                count += 1;
              }
              pending.add(onLoaded);
            } catch (e, s) {
              Log.onError(e, s,
                  content: "Deferred postLoad failed: ${room.id}");
            }
          }
        }

        if (sinceFlush.elapsedMilliseconds >= 250) flush();
        await Future.delayed(Duration.zero);
      }
    } finally {
      flush();
      _postLoadRunning = false;
      Diagnostics.general
          .addResult("Deferred room state loads ($count rooms)", clock.elapsed);
      _postLoadsDrained?.complete();
      _postLoadsDrained = null;
    }
  }

  matrix.MediaConfig? config;

  matrix.Client get matrixClient => _matrixClient;

  late String _id;

  // Vommet issue 427: set once the client had a session, so a later loggedOut
  // (the server ended it) can be told apart from a client that never had one
  bool _hadSession = false;
  String? _sessionUserId;
  bool _loggingOut = false;
  Alert? _signedOutAlert;
  AlertManager? _signedOutAlertManager;

  final NotifyingList<Room> _rooms = NotifyingList.empty(growable: true);
  final NotifyingList<Space> _spaces = NotifyingList.empty(growable: true);

  final NotifyingList<Peer> _peers = NotifyingList.empty(growable: true);

  final Map<String, Peer> _peersMap = {};

  final StreamController _onSync = StreamController.broadcast();
  final MatrixDefaultPushRule _defaultPushRule = MatrixDefaultPushRule();

  final StreamController<(Room, TimelineEvent)> onTimelineEventController =
      StreamController.broadcast();

  @override
  Stream<(Room, TimelineEvent<Client>)> get onTimelineEvent =>
      onTimelineEventController.stream;

  matrix.NativeImplementations get nativeImplentations => BuildConfig.WEB
      ? const matrix.NativeImplementationsDummy()
      : NativeImplementationsCustom(compute);

  MatrixClient({
    required String identifier,
    required matrix.DatabaseApi database,
  }) {
    if (preferences.developerMode.value) {
      matrix.Logs().level = matrix.Level.verbose;
    } else {
      matrix.Logs().level = matrix.Level.warning;
    }

    _id = identifier;
    _matrixClient = _createMatrixClient(identifier, database);
    _matrixClient.onLoginStateChanged.stream.listen(_onLoginStateChanged);

    self = ErrorProfile();

    favoriteRooms = NotifyingListFilter(
      _rooms,
      where: (item) {
        return (item as MatrixRoom).matrixRoom.isFavourite;
      },
      onFilterParamsChanged: [
        _matrixClient.onSync.stream.where((sync) {
          return sync.rooms?.join?.values.any((i) =>
                  i.accountData?.any((i) => i.type == "m.tag") == true) ==
              true;
        })
      ],
    );

    _matrixClient.onSync.stream.listen(onMatrixClientSync);
    // Vommet: remember what this device sent, for notification quieting.
    SentHere.track(_matrixClient);
    componentsInternal = ComponentRegistry.getMatrixComponents(this);
  }

  static Future<MatrixClient> create(String identifier) async {
    final database = await getMatrixDatabase(identifier);
    return MatrixClient(identifier: identifier, database: database);
  }

  static String hash(String name) {
    var bytes = utf8.encode(name);
    var hash = sha256.convert(bytes);
    return hash.toString();
  }

  @override
  bool get supportsE2EE => true;

  @override
  int? get maxFileSize => config?.mUploadSize;

  /// Vommet issue 410: the media config is fetched once at startup with no
  /// retry, so a failed fetch left every upload unchecked. Try again here.
  Future<int?> fetchMaxFileSize() async {
    if (config == null) {
      try {
        config = await _matrixClient
            .getConfig()
            .timeout(const Duration(seconds: 10));
      } catch (error, trace) {
        Log.onError(error, trace, content: "Failed to fetch the media config");
      }
    }
    return maxFileSize;
  }

  @override
  String get identifier => _id;

  @override
  Stream<Peer> get onPeerAdded => _peers.onAdd;

  @override
  Stream<Room> get onRoomAdded => _rooms.onAdd;

  @override
  Stream<Space> get onSpaceAdded => _spaces.onAdd;

  @override
  Stream<Room> get onRoomRemoved => _rooms.onRemove;

  @override
  Stream<Space> get onSpaceRemoved => _spaces.onRemove;

  @override
  Stream<void> get onSync => _onSync.stream;

  @override
  List<Peer> get peers => _peers;

  @override
  NotifyingList<Room> get rooms => _rooms;

  @override
  List<Room> get singleRooms => throw UnimplementedError();

  @override
  List<Space> get spaces => _spaces;

  @override
  late NotifyingListFilter<Room> favoriteRooms;

  @override
  StoredStreamController<ClientConnectionStatusUpdate> connectionStatusChanged =
      StoredStreamController<ClientConnectionStatusUpdate>();

  static String get matrixClientOlmMissingMessage => Intl.message(
        "libolm is not installed or was not found. End to End Encryption will not be available until this is resolved",
        name: "matrixClientOlmMissingMessage",
        desc:
            "Text that explains to the user that libolm dependency is not found",
      );

  static String get matrixClientVodozemacMissingMessage => Intl.message(
        "vodozemac is not installed or was not found. End to End Encryption will not be available until this is resolved",
        name: "matrixClientVodozemacMissingMessage",
        desc:
            "Text that explains to the user that vodozemac dependency is not found",
      );

  static String get matrixClientEncryptionWarningTitle => Intl.message(
        "Encryption Warning",
        name: "matrixClientEncryptionWarningTitle",
        desc: "Title of a warning about encryption",
      );

  static String get matrixClientAccountSignedOutTitle => Intl.message(
        "Account signed out",
        name: "matrixClientAccountSignedOutTitle",
        desc: "Title of the alert shown when an account's session has ended",
      );

  static String matrixClientAccountSignedOutMessage(String account) =>
      Intl.message(
        "$account was signed out, for example from another device. Tap to open Settings: Logout removes it from Manage Accounts, and you can add it again to sign back in",
        args: [account],
        name: "matrixClientAccountSignedOutMessage",
        desc:
            "Message of the alert shown when an account's session has ended. Tapping it opens the settings",
      );

  static String get matrixClientAccountSignedOutReason => Intl.message(
        "signed out",
        name: "matrixClientAccountSignedOutReason",
        desc:
            "Why an account couldn't be loaded, when its session had already ended. Shown after 'Couldn't load this account:'",
      );

  static Future<void> loadFromDB(
    ClientManager manager, {
    bool isBackgroundService = false,
  }) async {
    await _checkSystem(manager);

    await Diagnostics.general.timeAsync("loadFromDB", () async {
      var clients = preferences.getRegisteredMatrixClients();

      List<Future> futures = List.empty(growable: true);

      if (clients != null) {
        for (var clientName in clients) {
          var client = await MatrixClient.create(clientName);
          manager.addClient(client);
          futures.add(
            Diagnostics.general.timeAsync(
              "Initializing client $clientName",
              () async {
                try {
                  await client.init(
                    true,
                    isBackgroundService: isBackgroundService,
                  );

                  // Vommet issue 427: the session ended in an earlier run, so
                  // the database came back without one
                  if (!client.isLoggedIn()) {
                    client.self = ErrorProfile(
                        reason: matrixClientAccountSignedOutReason);
                    client._showSignedOutAlert(manager.alertManager,
                        "${clientName.substring(0, 8)}...");
                  }
                } catch (error, trace) {
                  Log.onError(
                    error,
                    trace,
                    content: "Unable to load client $clientName from database",
                  );

                  client.self = ErrorProfile(reason: error.toString());
                  // Vommet: the browser refused to store (QuotaExceededError,
                  // e.g. a private window's storage is full): say so.
                  final storageFull =
                      error.toString().contains("QuotaExceededError");
                  manager.alertManager.addAlert(
                    Alert(
                      AlertType.warning,
                      messageGetter: () => storageFull
                          ? matrixClientStorageFullMessage
                          : "One of the registered accounts (${clientName.substring(0, 8)}...) was unable to load correctly, please check the logs for more details",
                      titleGetter: () => storageFull
                          ? matrixClientStorageFullTitle
                          : "Unable to load account",
                    ),
                  );
                }
              },
            ),
          );
        }
      }

      await Future.wait(futures);
    });
  }

  static Future<void> _checkSystem(ClientManager clientManager) async {
    try {
      await vodozemac.init(wasmPath: './assets/assets/vodozemac/');
      if (!vod.isInitialized()) {
        throw Exception("Vodozemac failed to initialize!");
      }
    } catch (exception, trace) {
      Log.onError(exception, trace, content: "Failed to initialize vodozemac");
      clientManager.alertManager.addAlert(
        Alert(
          AlertType.warning,
          titleGetter: () => matrixClientEncryptionWarningTitle,
          messageGetter: () => matrixClientVodozemacMissingMessage,
        ),
      );
    }
  }

  static matrix.NativeImplementations get nativeImplementations =>
      BuildConfig.WEB
          ? const matrix.NativeImplementationsDummy()
          : matrix.NativeImplementationsIsolate(
              compute,
              vodozemacInit: vodozemac.init,
            );
  @override
  Future<void> init(
    bool loadingFromCache, {
    bool isBackgroundService = false,
  }) async {
    if (!_matrixClient.isLogged()) {
      // Vommet: native OIDC sessions renew their access token (#45). Set
      // before init, whose first sync may already need a refresh.
      await MatrixOidcLoginFlow.attachRefresh(_matrixClient);

      await Diagnostics.general.timeAsync("Matrix client init", () async {
        await _matrixClient.init(
          waitForFirstSync: !loadingFromCache,
          waitUntilLoadCompletedLoaded: true,
          onMigration: () => Log.w("Matrix Database is migrating"),
        );
      });

      await _updateOwnProfile();

      if (!isBackgroundService) {
        final syncClock = Stopwatch()..start();
        // Vommet: wait for the sync init() started (timeout 0), not a new
        // oneShotSync(). By now that sync may be done and the loop already
        // long-polling for up to 30 s, which oneShotSync() would join.
        firstSync = (_matrixClient.firstSyncReceived ??
                _matrixClient.oneShotSync(timeout: Duration.zero))
            .then((_) {
          firstSyncComplete = true;
          Telemetry.record("sync_initial", {
            "ms": syncClock.elapsedMilliseconds,
            "own_server": SyncStats.onOwnServer(_matrixClient.userID),
            "rooms": _matrixClient.rooms.length,
            "sliding_sync": _usesSlidingSync,
            "outcome": "ok",
          });
        }, onError: (Object error, StackTrace trace) {
          Telemetry.record("sync_initial", {
            "ms": syncClock.elapsedMilliseconds,
            "own_server": SyncStats.onOwnServer(_matrixClient.userID),
            ...Telemetry.errorFields(error, withType: false, withStatus: false),
          });
          Error.throwWithStackTrace(error, trace);
        });
      }
    }

    _matrixClient.getConfig().then((value) {
      config = value;
    });

    // Vommet: opt-in diagnostics for shared encrypted history (MSC4268).
    if (!isBackgroundService) HistorySharingTelemetry.track(_matrixClient);
    // Vommet: opt-in diagnostics for who each room key we send reaches.
    if (!isBackgroundService) RoomKeyShareTelemetry.track(_matrixClient);

    // Vommet issue 69: rooms you join get your space nickname (only while
    // the experiment is on, and only fresh joins; checked per room).
    if (!isBackgroundService) MatrixNicknames.of(this).listenForJoins();

    _updateRoomslist();
    _updateSpacesList();

    // Vommet: resend what was still unsent when the app last closed.
    if (preferences.experimentOfflineSending.value && !isBackgroundService) {
      unawaited(firstSync?.then((_) => OfflineSending.resume(_matrixClient)));
    }
  }

  void onMatrixClientSync(matrix.SyncUpdate update) {
    _handleComponentSync(update);

    _onSync.add(null);
    _updateRoomslist();
    _updateSpacesList();
    _handleSpaceChildren(update);
    _applyDefaultPushRules(update);
  }

  void _applyDefaultPushRules(matrix.SyncUpdate update) {
    _defaultPushRule.onSync(_matrixClient, update,
        roomDefault:
            MatrixDefaultPushRule.parse(preferences.defaultRoomPushRule.value),
        directDefault: MatrixDefaultPushRule.parse(
            preferences.defaultDirectPushRule.value),
        apply: (room, rule) async {
      // Through the Commet room when it exists: it writes the rule
      // "All Messages" needs when the account's default doesn't notify,
      // and keeps its cached level (used for unread badges) in step.
      final wrapped = getRoom(room.id);
      if (wrapped != null) {
        await wrapped.setPushRule(rule);
      } else {
        await room.setPushRuleState(MatrixDefaultPushRule.toMatrix(rule));
      }
    });
  }

  void _handleSpaceChildren(matrix.SyncUpdate update) {
    if (update.rooms?.join?.isNotEmpty == true) {
      for (var pair in update.rooms!.join!.entries) {
        var id = pair.key;
        var update = pair.value;

        if (update.timeline?.events?.isNotEmpty == true) {
          for (var event in update.timeline!.events!) {
            if (event.type == matrix.EventTypes.SpaceChild) {
              var space = getSpace(id);
              (space as MatrixSpace?)?.updateRoomsList();
            }
          }
        }
      }
    }
  }

  void _handleComponentSync(matrix.SyncUpdate update) {
    var roomUpdates = update.rooms?.join;
    if (roomUpdates != null) {
      for (var key in roomUpdates.keys) {
        var room = getRoom(key);
        if (room != null) {
          var components = room.getAllComponents();
          for (var comp in components) {
            if (comp is MatrixRoomSyncListener) {
              (comp as MatrixRoomSyncListener).onSync(roomUpdates[key]!);
            }
          }
        }
      }
    }
  }

  @override
  bool isLoggedIn() => _matrixClient.isLogged();

  matrix.Client _createMatrixClient(String name, matrix.DatabaseApi database) {
    // Vommet: times each request family for the opt-in diagnostics
    // (http_stats); a plain pass-through while diagnostics are off.
    final telemetryHttp = TelemetryHttpClient(http.Client());
    var client = matrix.Client(
      name,
      httpClient: telemetryHttp,
      verificationMethods: {
        KeyVerificationMethod.emoji,
        KeyVerificationMethod.numbers,
      },
      importantStateEvents: {
        "im.ponies.room_emotes",
        "m.room.power_levels",
        // Vommet: power level tags name the member list's role sections, so
        // they're needed before a room's deferred state load.
        PowerLevelTags.stableType,
        PowerLevelTags.unstableType,
        "m.room.join_rules",
        "page.codeberg.everypizza.room.banner",
        "chat.commet.calendar_event",
        MatrixVoipRoomComponent.callMemberStateEvent,
        // Vommet: needed at startup to keep sticker rooms out of the room
        // lists; without it they showed on Home until a later state change.
        MatrixEmoticonComponent.stickerRoomStateKey,
      },
      supportedLoginTypes: {
        matrix.AuthenticationTypes.password,
        matrix.AuthenticationTypes.sso,
      },
      nativeImplementations: nativeImplementations,
      database: database,
      logLevel: matrix.Level.verbose,
      // Vommet: with "Send while offline", keep retrying unsent messages for
      // days instead of the SDK's 1 minute (read at startup).
      sendTimelineEventTimeout: preferences.experimentOfflineSending.value
          ? OfflineSending.window
          : const Duration(minutes: 1),
    );

    client.slidingSync = preferences.experimentSlidingSync.value;
    client.onSyncStatus.stream.listen(onSyncStatusChanged);
    SyncStats.attach(client);
    telemetryHttp.ownServer = () => SyncStats.onOwnServer(client.userID);

    return client;
  }

  matrix.Client getMatrixClient() {
    return _matrixClient;
  }

  void _onLoginStateChanged(matrix.LoginState state) {
    if (state == matrix.LoginState.loggedIn) {
      _hadSession = true;
      _sessionUserId = _matrixClient.userID ?? _sessionUserId;
      return;
    }
    if (state != matrix.LoginState.loggedOut || !_hadSession || _loggingOut) {
      return;
    }

    // Vommet issue 427: the server ended the session (signed out from another
    // device, or the token was revoked) and the SDK cleared the local data.
    // Say so, instead of leaving an account that silently stops working
    _hadSession = false;
    final manager = clientManager?.alertManager;
    if (manager != null) {
      _showSignedOutAlert(
          manager, _sessionUserId ?? "${_id.substring(0, 8)}...");
    }
  }

  void _showSignedOutAlert(AlertManager manager, String account) {
    if (_signedOutAlert != null) return;
    _signedOutAlertManager = manager;
    _signedOutAlert = Alert(
      AlertType.warning,
      titleGetter: () => matrixClientAccountSignedOutTitle,
      messageGetter: () => matrixClientAccountSignedOutMessage(account),
      action: (context) =>
          NavigationUtils.navigateTo(context, const AppSettingsPage()),
    );
    manager.addAlert(_signedOutAlert!);
  }

  @override
  Future<void> logout() async {
    _loggingOut = true;
    if (_signedOutAlert != null) {
      _signedOutAlertManager?.clearAlert(_signedOutAlert!);
      _signedOutAlert = null;
    }

    preferences.removeRegisteredMatrixClient(_matrixClient.clientName);
    // Vommet: the encrypted search index holds decrypted messages; it goes
    // with the account like the message store does.
    await getComponent<MatrixEncryptedSearchIndexComponent>()?.deleteIndex();
    // Vommet issue 321: a client that never got a session (it failed to load)
    // has nothing to log out on the server; clear its local data only
    if (!_matrixClient.isLogged()) {
      await _matrixClient.clear();
      return;
    }

    // Best effort on the server; the SDK clears the database in a finally, so
    // local data goes even when the server refuses or can't be reached
    await _matrixClient.logout();
  }

  Future<void> _postLoginSuccess() async {
    _trackFirstSyncAfterSignIn();
    await _updateOwnProfile();
    for (var component in getAllComponents()!) {
      if (component is NeedsPostLoginInit) {
        (component as NeedsPostLoginInit).postLoginInit();
      }
    }
  }

  /// Vommet: only init() (a session loaded from storage) used to set
  /// [firstSync] and [firstSyncComplete]. After a fresh sign-in they stayed
  /// null/false until the app restarted, and MatrixRoom.shouldNotify, which
  /// waits for the first sync so the catch-up doesn't notify, dropped every
  /// desktop notification. The SDK's login() already ran that first sync;
  /// track it the same way.
  void _trackFirstSyncAfterSignIn() {
    if (firstSync != null) return;
    final mx = _matrixClient;
    final pending = mx.firstSyncReceived ??
        (mx.prevBatch != null ? Future<void>.value() : mx.onSync.stream.first);
    firstSync = pending.then((_) {
      firstSyncComplete = true;
    }, onError: (Object error, StackTrace trace) {
      // The sync loop goes on: the next sync that lands counts.
      Log.w("First sync after sign-in failed ($error); waiting for the next");
      return mx.onSync.stream.first.then((_) => firstSyncComplete = true);
    });
  }

  Future<void> _updateOwnProfile() async {
    final id = _matrixClient.userID;
    // Vommet issue 555: a member event of yours (a new name or picture, from
    // here or another device) means `self` is out of date. A rename sends one
    // per room, so refresh once they're in.
    _ownProfileUpdates ??= _matrixClient.onUserProfileUpdate.stream
        .where((userId) => userId == _matrixClient.userID)
        .listen((_) => _scheduleOwnProfileRefresh());
    if (id != null) {
      final generation = ++_ownProfileGeneration;
      var data = await _matrixClient.database.getUserProfile(id);
      if (generation != _ownProfileGeneration) return;
      // Vommet: an outdated cache entry holds the old name or picture; keep
      // showing what we have until the server answers.
      if (data != null && (!data.outdated || self is! MatrixProfile)) {
        _setOwnProfile(matrix.Profile(
          userId: id,
          displayName: data.displayname,
          avatarUrl: data.avatarUrl,
        ));

        // Update own profile, but lets not wait for it before continuing
        _matrixClient.getProfileFromUserId(id).then((profile) {
          if (generation == _ownProfileGeneration) _setOwnProfile(profile);
        });
      } else {
        final profile = await _matrixClient.getProfileFromUserId(id);
        if (generation == _ownProfileGeneration) _setOwnProfile(profile);
      }
    }
  }

  bool _bannedRoomsReloadStarted = false;

  void _updateRoomslist() {
    // Vommet: once the first sync is in, bring back rooms we were banned
    // from (the SDK drops them on restart). After a fresh sign-in there is
    // no firstSync future: start once a sync has landed.
    if (!_bannedRoomsReloadStarted) {
      if (firstSync != null) {
        _bannedRoomsReloadStarted = true;
        firstSync!.then((_) => _reloadBannedRooms(), onError: (_) {});
      } else if (_matrixClient.prevBatch != null) {
        _bannedRoomsReloadStarted = true;
        _reloadBannedRooms();
      }
    }

    // Vommet: materialised once. As a lazy `where`, the removeWhere below
    // re-ran the filter (Room.isSpace reads room state) over every room for
    // each listed room, on every sync.
    final joinedRooms = _matrixClient.rooms
        .where((element) => !element.isSpace && element.membership.isJoin)
        .toList();
    final joinedIds = {for (final room in joinedRooms) room.id};

    // Vommet: rooms we were banned from stay listed (read-only) until the
    // user dismisses them. The SDK moves them into its archive.
    var bannedRooms = _matrixClient.archivedRooms
        .map((a) => a.room)
        .where((element) => !element.isSpace && _isOwnBan(element))
        .toList();

    for (var room in [...joinedRooms, ...bannedRooms]) {
      var existing = getRoom(room.id);
      if (existing is MatrixRoom && existing.matrixRoom == room) continue;

      // A rejoined (unbanned) room comes back as a new SDK object.
      if (existing != null) rooms.remove(existing);
      rooms.add(MatrixRoom(this, room, _matrixClient));
    }

    var known = _bannedRoomIds;
    var current = bannedRooms.map((r) => r.id).toSet();
    // Only add here; ids leave the list when the user dismisses or rejoins.
    var rejoined = joinedIds.where(known.contains);
    if (!current.every(known.contains) || rejoined.isNotEmpty) {
      _bannedRoomIds = {...known, ...current}..removeAll(rejoined);
    }

    rooms.removeWhere((e) =>
        !joinedIds.contains(e.identifier) && !current.contains(e.identifier));
  }

  bool _isOwnBan(matrix.Room room) {
    final userId = _matrixClient.userID;
    if (userId == null) return false;
    return room
            .getState(matrix.EventTypes.RoomMember, userId)
            ?.content["membership"] ==
        "ban";
  }

  /// Vommet: ids of rooms we were banned from and have not dismissed, kept
  /// per account. The SDK forgets archived rooms on restart, so a non-empty
  /// list makes us reload the server's archive once after startup.
  String get _bannedRoomsKey => "vommet_banned_rooms_$identifier";

  Set<String> get _bannedRoomIds =>
      (Preference.preferences?.getStringList(_bannedRoomsKey) ?? []).toSet();

  set _bannedRoomIds(Set<String> ids) {
    if (ids.isEmpty) {
      Preference.preferences?.remove(_bannedRoomsKey);
    } else {
      Preference.preferences?.setStringList(_bannedRoomsKey, ids.toList());
    }
  }

  /// Vommet: bring back rooms and spaces we were banned from that the SDK
  /// doesn't hold (a ban while the app was closed, a fresh sign-in, or any
  /// restart: the SDK keeps its archive in memory only). Rather than the
  /// SDK's full archive sync, ask the server about the rooms that can be
  /// bans: the ones we remember, plus unjoined children of our spaces.
  Future<void> _reloadBannedRooms() async {
    final joined = _matrixClient.rooms
        .where((r) => r.membership == matrix.Membership.join)
        .map((r) => r.id)
        .toSet();
    final held = _matrixClient.archivedRooms.map((a) => a.room.id).toSet();
    final candidates = <String>{
      ..._bannedRoomIds,
      for (final space in _matrixClient.rooms.where((r) => r.isSpace))
        for (final child in space.spaceChildren)
          if (child.roomId != null) child.roomId!,
    }..removeWhere((id) => joined.contains(id) || held.contains(id));
    if (candidates.isEmpty) return;

    matrix.SyncUpdate response;
    try {
      final filter = matrix.Filter(
        presence: matrix.EventFilter(limit: 0),
        accountData: matrix.EventFilter(limit: 0),
        room: matrix.RoomFilter(
          rooms: candidates.take(500).toList(),
          includeLeave: true,
          state: matrix.StateFilter(lazyLoadMembers: true),
          timeline: matrix.StateFilter(limit: 10),
          accountData: matrix.StateFilter(limit: 0),
          ephemeral: matrix.StateFilter(limit: 0),
        ),
      );
      response = await _matrixClient.sync(
          filter: jsonEncode(filter.toJson()), timeout: 0);
    } catch (e, s) {
      Log.onError(e, s, content: "Failed to load banned rooms");
      return;
    }

    final found = <String>{};
    for (final entry in response.rooms?.leave?.entries ??
        <MapEntry<String, matrix.LeftRoomUpdate>>[]) {
      final room = matrix.Room(
          id: entry.key,
          membership: matrix.Membership.leave,
          client: _matrixClient);
      final update = entry.value;
      for (final event in [
        ...?update.state,
        ...?update.timeline?.events,
      ]) {
        if (event.stateKey == null) continue;
        room.setState(matrix.Event.fromMatrixEvent(event, room));
      }
      if (!_isOwnBan(room)) continue;
      room.prev_batch = update.timeline?.prevBatch;
      final timeline = matrix.Timeline(
        room: room,
        chunk: mx_chunk.TimelineChunk(
          events: update.timeline?.events?.reversed
                  .map((e) => matrix.Event.fromMatrixEvent(e, room))
                  .toList() ??
              [],
        ),
      );
      if (_matrixClient.getArchiveRoomFromCache(room.id) != null) continue;
      _matrixClient.archivedRooms
          .add(matrix.ArchivedRoom(room: room, timeline: timeline));
      found.add(room.id);
    }

    // Remember what we found; drop remembered ids the server no longer
    // reports as a ban (unbanned and rejoined, forgotten elsewhere, ...).
    final stillHeld = _matrixClient.archivedRooms
        .map((a) => a.room)
        .where(_isOwnBan)
        .map((r) => r.id)
        .toSet();
    _bannedRoomIds = {..._bannedRoomIds, ...found}.intersection(stillHeld);

    _updateRoomslist();
    _updateSpacesList();
  }

  Future<void> dismissBannedSpace(MatrixSpace space) async {
    await space.matrixRoom.forget();
    _bannedRoomIds = _bannedRoomIds..remove(space.identifier);
    _spaces.remove(space);
    await space.close();
  }

  Future<void> dismissBannedRoom(MatrixRoom room) async {
    await room.matrixRoom.forget();
    _bannedRoomIds = _bannedRoomIds..remove(room.identifier);
    rooms.remove(room);
    await room.close();
  }

  void _updateSpacesList() {
    var allSpaces = _matrixClient.rooms.where(
      (element) =>
          element.isSpace && element.membership == matrix.Membership.join,
    );

    // Vommet: spaces we were banned from stay (faded) until dismissed. A
    // live ban keeps the same SDK object; after a restart they come from
    // the archive. A rejoined space comes back as a new object.
    var bannedSpaces = _matrixClient.archivedRooms
        .map((a) => a.room)
        .where((element) => element.isSpace && _isOwnBan(element))
        .toList();
    for (var space in [...allSpaces, ...bannedSpaces]) {
      var existing = getSpace(space.id);
      if (existing is MatrixSpace && existing.matrixRoom != space) {
        _spaces.remove(existing);
      }
    }
    var known = _bannedRoomIds;
    var bannedIds = bannedSpaces.map((s) => s.id);
    if (!bannedIds.every(known.contains)) {
      _bannedRoomIds = {...known, ...bannedIds};
    }
    allSpaces = [...allSpaces, ...bannedSpaces];

    bool didChange = false;

    // Vommet: drop spaces we left (here or on another device). Only adding
    // kept a left space on the rail until a restart.
    var keep = allSpaces.map((s) => s.id).toSet();
    for (var space in spaces.toList()) {
      if (keep.contains(space.identifier)) continue;
      _spaces.remove(space);
      unawaited(space.close());
      didChange = true;
    }

    for (var space in allSpaces) {
      if (hasSpace(space.id)) continue;
      spaces.add(MatrixSpace(this, space, _matrixClient));
      didChange = true;
    }

    if (didChange) {
      for (var space in spaces.whereType<MatrixSpace>()) {
        space.updateRoomsList();
        // Vommet: joining or leaving a parent space changes which of the
        // others sit on the rail.
        space.updateTopLevelStatus();
      }
    }
  }

  @override
  Future<Room> createRoom(CreateRoomArgs args) async {
    var creationContent = null;
    Map<String, Object?>? powerLevelAdditions = {};

    List<matrix.StateEvent>? initialState;
    if (args.roomType == RoomType.photoAlbum) {
      creationContent = {"type": "chat.commet.photo_album"};
    }

    if (args.roomType == RoomType.voipRoom) {
      creationContent = {"type": "org.matrix.msc3417.call"};
      powerLevelAdditions = {
        "events": {
          "org.matrix.msc3401.call": 0,
          "org.matrix.msc3401.call.member": 0
        }
      };
    }

    if (args.roomType == RoomType.calendar) {
      const widgetId = "chat.commet.room_calendar";
      var widgetHost = GlobalConfig.calendarWidgetHost;
      creationContent = {"type": "chat.commet.calendar"};
      initialState = [
        matrix.StateEvent(
          content: {
            "type": "chat.commet.widgets.calendar",
            "url":
                "https://${widgetHost}/#/?widgetId=\$matrix_widget_id&userId=\$matrix_user_id&theme=\$org.matrix.msc2873.client_theme&userDisplayName=\$matrix_display_name&userAvatarUrl=\$matrix_avatar_url&language=\$org.matrix.msc2873.client_language",
            "name": "Calendar",
            "data": {},
          },
          type: "im.vector.modular.widgets",
          stateKey: widgetId,
        ),
        matrix.StateEvent(
          content: {
            "widgets": {
              widgetId: {
                "container": "top",
                "height": 100,
                "width": 100,
                "index": 0,
              },
            },
          },
          type: "io.element.widgets.layout",
        ),
      ];
    }

    final coOwners = args.additionalCreators;
    if (coOwners.isNotEmpty) {
      creationContent = <String, Object?>{
        ...?(creationContent as Map<String, Object?>?),
        "additional_creators": coOwners,
      };
    }

    var visibility = switch (args.visibility) {
      final RoomVisibilityPrivate _ => matrix.Visibility.private,
      final RoomVisibilityPublic _ => matrix.Visibility.public,
      final RoomVisibilityRestricted _ => null,
      _ => matrix.Visibility.private,
    };

    if (args.visibility case RoomVisibilityRestricted restricted) {
      initialState ??= List.empty(growable: true);

      initialState = [
        ...initialState,
        for (var i in restricted.spaces)
          matrix.StateEvent(
              stateKey: i,
              type: matrix.EventTypes.SpaceParent,
              content: {
                "canonical": true,
                "via": [
                  if (self?.identifier.domain != null) self?.identifier.domain
                ]
              }),
        matrix.StateEvent(content: {
          "join_rule": "restricted",
          "allow": [
            for (var i in restricted.spaces)
              {"room_id": i, "type": "m.room_membership"},
          ]
        }, type: matrix.EventTypes.RoomJoinRules)
      ];
    }

    // Ask for encryption in the creation request itself. Enabling it
    // afterwards fails with "Encryption is already enabled!" on servers that
    // encrypt new rooms by default.
    if (args.enableE2EE == true) {
      initialState = [
        ...?initialState,
        matrix.StateEvent(
          type: matrix.EventTypes.Encryption,
          content: {"algorithm": matrix.AlgorithmTypes.megolmV1AesSha2},
        ),
      ];
    }

    var id = await _matrixClient.createRoom(
      creationContent: creationContent,
      name: args.name,
      initialState: initialState,
      topic: args.topic,
      visibility: visibility,
      roomVersion:
          coOwners.isNotEmpty ? CreateRoomArgs.coOwnerRoomVersion : null,
    );

    await _matrixClient.waitForRoomInSync(id);

    var matrixRoom = _matrixClient.getRoomById(id)!;

    if (powerLevelAdditions.isNotEmpty) {
      var events = await matrixClient.getRoomState(id);

      var currentPerms = events
          .firstWhereOrNull((i) => i.type == matrix.EventTypes.RoomPowerLevels)
          ?.content;

      if (currentPerms != null) {
        var newPerms = <String, dynamic>{
          ...currentPerms,
          "events": <String, dynamic>{
            ...?currentPerms["events"] as Map<String, dynamic>?,
            ...?powerLevelAdditions["events"] as Map<String, dynamic>?,
          }
        };
        _matrixClient.setRoomStateWithKey(
            id, matrix.EventTypes.RoomPowerLevels, "", newPerms);
      }
    }

    if (hasRoom(id)) return getRoom(id)!;
    var room = MatrixRoom(this, matrixRoom, _matrixClient);
    rooms.add(room);
    return room;
  }

  @override
  Future<Space> createSpace(CreateRoomArgs args) async {
    final visibility = args.visibility is RoomVisibilityPrivate
        ? matrix.Visibility.private
        : matrix.Visibility.public;
    final String id;
    if (args.additionalCreators.isEmpty) {
      id = await _matrixClient.createSpace(
        name: args.name,
        waitForSync: true,
        visibility: visibility,
      );
    } else {
      // Same request as the SDK's createSpace, plus the v12 co-owners.
      id = await _matrixClient.createRoom(
        name: args.name,
        visibility: visibility,
        creationContent: {
          "type": "m.space",
          "additional_creators": args.additionalCreators,
        },
        powerLevelContentOverride: {"events_default": 100},
        roomVersion: CreateRoomArgs.coOwnerRoomVersion,
      );
      await _matrixClient.waitForRoomInSync(id, join: true);
    }

    if (hasSpace(id)) return getSpace(id)!;
    var space = MatrixSpace(
      this,
      _matrixClient.getRoomById(id)!,
      _matrixClient,
    );
    spaces.add(space);
    return space;
  }

  @override
  Future<Space> joinSpace(String address) async {
    // Vommet: after joining a space, offer to join its rooms too.
    final info = parseAddressToIdAndVia(address);
    final wasIn = info != null &&
        _matrixClient.getRoomById(info.$1)?.membership ==
            matrix.Membership.join;
    final space = await _joinSpaceOnly(address);
    if (!wasIn) {
      unawaited(SpaceJoinPicker.offerAfterJoin(this, space.identifier,
          via: info?.$2 ?? const []));
    }
    return space;
  }

  Future<Space> _joinSpaceOnly(String address) async {
    var info = parseAddressToIdAndVia(address);
    if (info == null) {
      throw Exception("Invalid address");
    }
    var id = await _matrixClient.joinRoom(info.$1, via: info.$2);
    await _waitForJoinInSync(id);
    if (hasSpace(id)) return getSpace(id)!;

    var space = MatrixSpace(
      this,
      _matrixClient.getRoomById(id)!,
      _matrixClient,
    );
    spaces.add(space);
    return space;
  }

  // Vommet: joining a room you're already in changes nothing, so no sync
  // has to mention it again; waiting for one spun the Join button forever.
  Future<void> _waitForJoinInSync(String roomId) async {
    if (_matrixClient.getRoomById(roomId)?.membership ==
        matrix.Membership.join) {
      return;
    }
    await _matrixClient.waitForRoomInSync(roomId);
  }

  @override
  Future<Room> joinRoom(String address) async {
    var info = parseAddressToIdAndVia(address);
    if (info == null) {
      throw Exception("Invalid address");
    }

    var id = await _matrixClient.joinRoom(info.$1, via: info.$2);
    await _waitForJoinInSync(id);
    if (hasRoom(id)) return getRoom(id)!;

    var room = MatrixRoom(this, _matrixClient.getRoomById(id)!, _matrixClient);
    rooms.add(room);
    return room;
  }

  @override
  Future<void> close() async {
    // Vommet: stop components' timers and listeners first, so nothing
    // queries the database after dispose() closes it.
    for (var component in componentsInternal) {
      if (component is! NeedsCloseOnClientClose) continue;
      try {
        await (component as NeedsCloseOnClientClose).onClientClosed();
      } catch (e, s) {
        Log.onError(e, s, content: "Closing a component failed");
      }
    }
    await _matrixClient.dispose();
    _ownProfileRefresh?.cancel();
    await _ownProfileUpdates?.cancel();
  }

  /// Vommet issue 555: bumped by every change of [self], so a profile
  /// fetch that started earlier can't put an older one back.
  int _ownProfileGeneration = 0;
  Timer? _ownProfileRefresh;
  StreamSubscription<String>? _ownProfileUpdates;

  void _scheduleOwnProfileRefresh() {
    _ownProfileRefresh?.cancel();
    _ownProfileRefresh = Timer(const Duration(milliseconds: 500), () {
      _updateOwnProfile().catchError((Object e) {
        Log.w("Couldn't refresh your own profile: $e");
      });
    });
  }

  /// Vommet issue 555: sets [self] and tells the places showing it.
  void _setOwnProfile(matrix.Profile profile) {
    self = MatrixProfile(this, profile);
    EventBus.ownProfileChanged.add(this);
  }

  @override
  Future<void> setAvatar(Uint8List bytes, String mimeType) async {
    await _matrixClient.setAvatar(matrix.MatrixImageFile(
        bytes: bytes, name: "avatar", mimeType: mimeType));

    // Vommet issue 555: the cached profile still has the old picture.
    await _matrixClient.database
        .markUserProfileAsOutdated(_matrixClient.userID!);
    await _updateOwnProfile();
    // TODO: Handle refresh avatar
    // await (self as MatrixPeer).refreshAvatar();
  }

  @override
  Future<void> setDisplayName(String name) async {
    await _matrixClient.setProfileField(_matrixClient.userID!, "displayname", {
      "displayname": name,
    });

    // Vommet issue 555: show the new name at once (the cached profile still
    // has the old one; the refresh after the member events reads the server).
    final id = _matrixClient.userID!;
    await _matrixClient.database.markUserProfileAsOutdated(id);
    final current = self;
    _ownProfileGeneration++;
    _setOwnProfile(matrix.Profile(
      userId: id,
      displayName: name,
      avatarUrl: current is MatrixProfile ? current.profile.avatarUrl : null,
    ));

    // Vommet: the server just rewrote your name in every room; put your
    // space and room nicknames back.
    MatrixNicknames.of(this).reapplyAfterGlobalChange(name);
  }

  @override
  Iterable<Room> getEligibleRoomsForSpace(Space space) {
    return rooms.where((room) => !space.containsRoom(room.identifier));
  }

  @override
  Widget buildDebugInfo() {
    var data = _matrixClient.accountData.copy();

    return SelectionArea(
      child: Codeblock(
        language: "json",
        text: const JsonEncoder.withIndent('  ').convert(data),
      ),
    );
  }

  // Vommet: look rooms and spaces up by id without scanning the lists (the
  // room list update looked up every room this way on each sync).
  late final NotifyingListIndex<Room> _roomIndex =
      NotifyingListIndex(_rooms, (room) => room.identifier);
  late final NotifyingListIndex<Space> _spaceIndex =
      NotifyingListIndex(_spaces, (space) => space.identifier);

  @override
  Room? getRoom(String identifier) {
    return _roomIndex[identifier];
  }

  @override
  Space? getSpace(String identifier) {
    return _spaceIndex[identifier];
  }

  @override
  bool hasPeer(String identifier) {
    return _peersMap.containsKey(identifier);
  }

  @override
  bool hasRoom(String identifier) {
    return _roomIndex.containsKey(identifier);
  }

  @override
  bool hasSpace(String identifier) {
    return _spaceIndex.containsKey(identifier);
  }

  (String, List<String>?)? parseAddressToIdAndVia(String address) {
    String id = address;
    List<String>? via;

    if (address.startsWith("!") || address.startsWith("#")) {
      var split = address.split("?");
      id = split.first;

      if (split.length >= 2) {
        var query = Uri.splitQueryString(split[1]);
        if (query.containsKey("via")) {
          via = query["via"]!.split(",");
        }

        // dont need to use via when it is the homeserver this user is connected to
        via?.removeWhere((i) => i == matrixClient.userID!.domain);
      }
    }

    if (address.startsWith("https")) {
      var url = Uri.parse(address);
      var info = parseMatrixLink(url);

      if (info == null) {
        return null;
      }

      return parseAddressToIdAndVia(info.$3);
    }

    return (id, via);
  }

  @override
  Future<RoomPreview?> getRoomPreview(String address) async {
    try {
      var info = parseAddressToIdAndVia(address);
      if (info == null) return null;

      return await _matrixClient.getRoomPreview(info.$1, via: info.$2);
    } catch (exception, trace) {
      Log.onError(exception, trace);
      return null;
    }
  }

  @override
  Future<RoomPreview?> getSpacePreview(String address) async {
    return getRoomPreview(address);
  }

  @override
  T? getComponent<T extends Component>() {
    for (var component in componentsInternal) {
      if (component is T) return component as T;
    }

    return null;
  }

  @override
  List<T>? getAllComponents<T extends Component<Client>>() {
    List<T> components = List.empty(growable: true);
    for (var component in componentsInternal) {
      if (component is T) {
        components.add(component as T);
      }
    }

    return components;
  }

  /// Vommet: start listening before asking to leave. Sliding sync can
  /// deliver the leave before the /leave response arrives, and a wait begun
  /// after it never finished, so the room or space stayed listed until a
  /// restart. Capped too, so a sync that never mentions it can't hang us.
  Future<void> _leaveAndWaitForSync(String roomId) async {
    final inSync = _matrixClient.waitForRoomInSync(roomId, leave: true);
    await _matrixClient.leaveRoom(roomId);
    try {
      await inSync.timeout(const Duration(seconds: 10));
    } on TimeoutException {
      Log.w("Left $roomId but no sync mentioned it within 10 s");
    }
  }

  @override
  Future<void> leaveRoom(Room room) async {
    await _leaveAndWaitForSync(room.identifier);
    await room.close();
    _rooms.remove(room);
  }

  @override
  Future<void> leaveSpace(Space space) async {
    await _leaveAndWaitForSync(space.identifier);
    await space.close();
    _spaces.remove(space);
  }

  int _consecutiveSyncErrors = 0;

  /// Whether the stored sync token is a sliding sync one (the SDK fork
  /// prefixes those with `ss1:`).
  bool get _usesSlidingSync =>
      _matrixClient.prevBatch?.startsWith("ss1:") ?? false;

  /// The first few sync rounds after launch, timed: "load" is the request
  /// until the response arrives, "apply" the client processing it. Shows how
  /// long the sliding sync room list takes to fill in, and where.
  static const _timedSyncRounds = 5;
  int _syncRound = 0;
  final Stopwatch _syncRoundClock = Stopwatch();
  int? _syncRoundLoadMs;

  void _recordSyncRound(matrix.SyncStatusUpdate event) {
    if (_syncRound >= _timedSyncRounds) return;
    switch (event.status) {
      case matrix.SyncStatus.waitingForResponse:
        _syncRoundLoadMs = null;
        _syncRoundClock
          ..reset()
          ..start();
      case matrix.SyncStatus.processing:
        if (!_syncRoundClock.isRunning || _syncRoundLoadMs != null) return;
        _syncRoundLoadMs = _syncRoundClock.elapsedMilliseconds;
      case matrix.SyncStatus.finished:
        final loadMs = _syncRoundLoadMs;
        if (!_syncRoundClock.isRunning || loadMs == null) return;
        _syncRoundClock.stop();
        _syncRound++;
        if (!_usesSlidingSync) return;
        for (final (action, ms) in [
          ("load", loadMs),
          ("apply", _syncRoundClock.elapsedMilliseconds - loadMs),
        ]) {
          Telemetry.record("feature", {
            "feature": "sliding_sync",
            "action": action,
            "ms": ms,
            "count": _syncRound,
            "outcome": "ok",
          });
        }
      // A round that fails before its response (e.g. the client's 10 s cap
      // on a timeout-0 request) never reaches "finished"; record it too.
      case matrix.SyncStatus.error:
        if (!_syncRoundClock.isRunning || _syncRoundLoadMs != null) return;
        _syncRoundClock.stop();
        _syncRound++;
        if (!_usesSlidingSync) return;
        Telemetry.record("feature", {
          "feature": "sliding_sync",
          "action": "load",
          "ms": _syncRoundClock.elapsedMilliseconds,
          "count": _syncRound,
          "outcome": "error",
          "error_kind": TelemetryErrors.kind(event.error?.exception),
        });
      default:
        return;
    }
  }

  void _recordSyncStatus(matrix.SyncStatusUpdate event) {
    _recordSyncRound(event);
    if (event.status != matrix.SyncStatus.error) {
      if (event.status == matrix.SyncStatus.finished) {
        _consecutiveSyncErrors = 0;
      }
      return;
    }
    final n = ++_consecutiveSyncErrors;
    // First failure of a streak, then every 10x, so an offline laptop
    // doesn't produce one event per retry.
    if (n == 1 || n == 10 || n == 100 || n == 1000) {
      final error = event.error?.exception;
      Telemetry.record("sync_error", {
        "error_kind": TelemetryErrors.kind(error),
        "http_status": TelemetryErrors.httpStatus(error),
        if (TelemetryErrors.errcode(error) != null)
          "errcode": TelemetryErrors.errcode(error),
        "consecutive": n,
        "own_server": SyncStats.onOwnServer(_matrixClient.userID),
      });
    }
  }

  void onSyncStatusChanged(matrix.SyncStatusUpdate event) {
    _recordSyncStatus(event);
    ClientConnectionStatus value = ClientConnectionStatus.unknown;

    var connected = _matrixClient.onSync.value != null &&
        event.status != matrix.SyncStatus.error &&
        _matrixClient.prevBatch != null;

    if (connected) {
      value = ClientConnectionStatus.connected;
    } else {
      value = switch (event.status) {
        matrix.SyncStatus.waitingForResponse =>
          ClientConnectionStatus.connecting,
        matrix.SyncStatus.processing => ClientConnectionStatus.connecting,
        matrix.SyncStatus.cleaningUp => ClientConnectionStatus.connecting,
        matrix.SyncStatus.finished => ClientConnectionStatus.connected,
        matrix.SyncStatus.error => ClientConnectionStatus.disconnected,
      };
    }

    var result = ClientConnectionStatusUpdate(value);
    result.progress = event.progress;

    connectionStatusChanged.add(result);
  }

  @override
  Future<(bool, List<LoginFlow>?)> setHomeserver(Uri uri) async {
    try {
      var result =
          await _matrixClient.checkHomeserver(uri, fetchAuthMetadata: false);

      var flows = result.$3;

      var resultFlows = List<LoginFlow>.empty(growable: true);

      // Vommet: offer native OIDC sign-in when the server publishes OAuth 2.0
      // metadata (#45). Fetched separately so a server without the endpoint,
      // or one answering it with a non-Matrix error, still gets the old flows.
      if (MatrixOidcLoginFlow.isSupportedPlatform) {
        try {
          var metadata = await _matrixClient.getAuthMetadata();
          if (MatrixOidcLoginFlow.isUsable(metadata)) {
            resultFlows.add(MatrixOidcLoginFlow());
          }
        } catch (error) {
          Log.i("No native OIDC sign-in on $uri: $error");
        }
      }

      if (flows.any((element) => element.type == "m.login.password")) {
        resultFlows.add(MatrixPasswordLoginFlow());
      }

      if (flows.any((element) => element.type == "m.login.sso")) {
        resultFlows.addAll(await _getSsoFlows());
      }

      return (true, resultFlows);
    } catch (error, trace) {
      Log.onError(error, trace);
      return (false, null);
    }
  }

  Future<List<LoginFlow>> _getSsoFlows() async {
    List<LoginFlow> result = List.empty(growable: true);

    Map<String, dynamic> flows = await _matrixClient.request(
      matrix.RequestType.GET,
      "/client/v3/login",
    );

    flows["flows"].where((element) => element['type'] == "m.login.sso").forEach(
      (element) {
        element["identity_providers"]?.forEach((provider) {
          result.add(MatrixSSOLoginFlow.fromJson(this, provider));
        });
      },
    );

    if (result.isEmpty) {
      result.add(MatrixSSOLoginFlow(name: "homeserver", id: null));
    }

    return result;
  }

  @override
  Future<LoginResult> executeLoginFlow(LoginFlow flow) async {
    var result = await flow.submit(this);

    if (result is LoginResultSuccess) {
      preferences.addRegisteredMatrixClient(identifier);
      await _postLoginSuccess();
    }

    return result;
  }

  static (MatrixLinkType, String, String)? parseMatrixLink(Uri uri) {
    if (uri.authority != "matrix.to") {
      return null;
    }

    // Vommet: a matrix.to link with no "#..." part (e.g. bare "matrix.to",
    // linkified from chat text) threw a RangeError here, and since this runs
    // while rendering the message, the whole message became a grey error box
    // for everyone who saw it. Malformed %-escapes threw the same way.
    if (uri.fragment.length < 2) {
      return null;
    }

    String joinUrl;
    try {
      joinUrl = Uri.decodeComponent(uri.fragment.substring(1));
    } on ArgumentError {
      return null;
    }

    var roomId = joinUrl.split("?").first;

    if (roomId.startsWith("@")) {
      return (MatrixLinkType.user, roomId, joinUrl);
    }

    if (roomId.startsWith("!")) {
      return (MatrixLinkType.room, roomId, joinUrl);
    }

    if (roomId.startsWith("#")) {
      return (MatrixLinkType.roomAlias, roomId, joinUrl);
    }

    return null;
  }

  @override
  Room? getRoomByAlias(String identifier) {
    return rooms.firstWhereOrNull((r) => canonicalAliasMatches(
        (r as MatrixRoom)
            .matrixRoom
            .getState("m.room.canonical_alias")
            ?.content,
        identifier));
  }

  // Vommet: spaces aren't in [rooms], so a link to a space you're in
  // (#space:server) never matched and opened the join dialog instead.
  Space? getSpaceByAlias(String identifier) {
    return spaces.firstWhereOrNull((s) => canonicalAliasMatches(
        (s as MatrixSpace)
            .matrixRoom
            .getState("m.room.canonical_alias")
            ?.content,
        identifier));
  }

  /// Whether an `m.room.canonical_alias` content lists [alias], as the main
  /// alias or one of the alt aliases.
  static bool canonicalAliasMatches(
      Map<String, dynamic>? content, String alias) {
    if (content == null) return false;
    if (content["alias"] == alias) return true;

    var alts = content["alt_aliases"];
    if (alts is List<dynamic>) {
      return alts.contains(alias);
    }

    return false;
  }

  @override
  Future<bool> hasServerDisabledEncryption() async {
    var data = await matrixClient.getWellknown();
    Log.i(data);

    var prop =
        data.additionalProperties.tryGetMap<String, dynamic>("io.element.e2ee");

    var value = prop?.tryGet<bool>("force_disable");

    if (value == true) {
      return true;
    }

    return false;
  }

  @override
  Future<Room> joinRoomFromPreview(RoomPreview preview) async {
    // Vommet: a subspace joined from a preview offers its rooms too.
    if (preview.type == RoomType.space && !hasSpace(preview.roomId)) {
      final via =
          preview is MatrixSpaceRoomChunkPreview ? preview.via : <String>[];
      final room = await _joinRoomFromPreview(preview);
      unawaited(SpaceJoinPicker.offerAfterJoin(this, preview.roomId, via: via));
      return room;
    }
    return _joinRoomFromPreview(preview);
  }

  Future<Room> _joinRoomFromPreview(RoomPreview preview) {
    String roomId = preview.roomId;
    if (preview is MatrixSpaceRoomChunkPreview) {
      var via = preview.via;
      var query = "?via=" + via.join(",");

      roomId += query;
    }

    return joinRoom(roomId);
  }
}

enum MatrixLinkType { room, roomAlias, user }

String get matrixClientStorageFullTitle => Intl.message(
    "Browser storage is full",
    name: "matrixClientStorageFullTitle",
    desc:
        "Title of the warning when the browser refuses to store more data for an account");

String get matrixClientStorageFullMessage => Intl.message(
    "This browser won't let Vommet store more data, so your account couldn't be loaded. Private and incognito windows have little storage: open Vommet in a normal window, or free up space in the browser's site settings.",
    name: "matrixClientStorageFullMessage",
    desc:
        "Warning when the browser refuses to store more data (QuotaExceededError), e.g. in a private window");
