import 'dart:async';
import 'dart:io';

import 'package:commet/telemetry/telemetry.dart';
import 'package:commet/ui/pages/setup/menus/telemetry_consent.dart';
import 'package:commet/cache/file_cache.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/components/component.dart';
import 'package:commet/client/components/push_notification/android/unified_push_notifier.dart';
import 'package:commet/client/components/push_notification/notification_manager.dart';
import 'package:commet/config/build_config.dart';
import 'package:commet/config/global_config.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/config/preferences.dart';
import 'package:commet/config/subplatforms/subplatforms.dart';
import 'package:commet/debug/l10n_debug_lookup.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/diagnostic/diagnostics.dart';
import 'package:commet/generated/intl/messages_all.dart';
import 'package:commet/rust/frb_generated.dart';
import 'package:commet/single_instance.dart';
import 'package:commet/ui/organisms/overlay_windows/overlay_window_manager.dart';
import 'package:commet/ui/pages/bubble/bubble_page.dart';
import 'package:commet/ui/pages/fatal_error/fatal_error_page.dart';
import 'package:commet/ui/pages/login/login_page.dart';
import 'package:commet/ui/pages/main/main_page.dart';
import 'package:commet/ui/pages/setup/menus/check_for_updates.dart';
import 'package:commet/ui/pages/setup/menus/welcome_setup.dart';
import 'package:commet/utils/android_intent_helper.dart';
import 'package:commet/utils/app_focus_util.dart';
import 'package:commet/utils/custom_safe_area.dart';
import 'package:commet/utils/custom_uri.dart';
import 'package:commet/utils/background_tasks/background_task_manager.dart';
import 'package:commet/utils/database/database_server.dart';
import 'package:commet/utils/emoji/unicode_emoji.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:commet/utils/first_time_setup.dart';
import 'package:commet/ui/pages/setup/menus/whats_new_setup.dart';
import 'package:commet/utils/focus_node_monitor.dart';
import 'package:commet/utils/scaled_app.dart';
import 'package:commet/utils/share_intake.dart';
import 'package:commet/utils/shortcuts_manager.dart';
import 'package:commet/utils/system_wide_shortcuts/system_wide_shortcuts.dart';
import 'package:commet/utils/text_scale_changer.dart';
import 'package:commet/utils/update_checker.dart';
import 'package:commet/utils/window_management.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:receive_intent/receive_intent.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tiamat/config/style/theme_changer.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:tiamat/config/style/theme_dark.dart';
import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

final GlobalKey<NavigatorState> navigator = GlobalKey();
FileCache? fileCache;
Preferences preferences = Preferences();
ShortcutsManager shortcutsManager = ShortcutsManager();
BackgroundTaskManager backgroundTaskManager = BackgroundTaskManager();
ClientManager? clientManager;

bool isHeadless = false;

/// Vommet: started when the app's Dart code starts; startup steps are
/// recorded against it in Settings › Developer › Performance › General.
final Stopwatch startupClock = Stopwatch();

Future<T> _timedStartupStep<T>(String name, Future<T> Function() step) async {
  final clock = Stopwatch()..start();
  final result = await step();
  Diagnostics.general.addResult("Startup: $name", clock.elapsed);
  return result;
}

Future<void>? loading;

List<String> commandLineArgs = [];

@pragma('vm:entry-point')
void unifiedPushEntry() async {
  isHeadless = true;
  Log.prefix = "unified-push";
  await WidgetsFlutterBinding.ensureInitialized();
  await preferences.init();
  await UnifiedPushNotifier().init();
}

@pragma('vm:entry-point')
void onBackgroundNotificationResponse(NotificationResponse details) {
  print("Got a background notification response: $details");
}

@pragma('vm:entry-point')
void bubble() async {
  Log.prefix = "bubble";
  ensureBindingInit();
  await initNecessary();
  await initGuiRequirements();

  String? initialRoomId;
  String? initialClientId;

  var intent = await ReceiveIntent.getInitialIntent();

  if (intent?.extra?.containsKey("bubbleExtra") == true) {
    var uri = CustomURI.parse(intent!.extra!["bubbleExtra"]);

    if (uri is OpenRoomURI) {
      initialClientId = uri.clientId;
      initialRoomId = uri.roomId;
    }
  }

  Log.prefix = "bubble-$initialRoomId";

  var initialTheme = await preferences.resolveTheme();

  runApp(MaterialApp(
      title: 'Vommet',
      theme: initialTheme,
      navigatorKey: navigator,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => Provider<ClientManager>(
            create: (context) => clientManager!,
            child: child,
          ),
      home: BubblePage(
        clientManager!,
        initialClientId: initialClientId,
        initialRoom: initialRoomId,
      )));
}

void main(List<String> args) async {
  commandLineArgs = args;
  print(args);

  if (runWebViewTitleBarWidget(args)) {
    return;
  }

  final format = DateFormat('HH:mm:ss');

  Logger.root.onRecord.listen((record) {
    print('${format.format(record.time)} ${record.level} : ${record.message}');
  });

  runZonedGuarded(appMain, Log.onError, zoneSpecification: Log.spec);
}

void appMain() async {
  startupClock.start();
  Log.prefix = "main";
  try {
    if (BuildConfig.WEB) {
      var info = await DeviceInfoPlugin().deviceInfo;
      if (info is WebBrowserInfo) {
        Layout.browserInfo = info;
      }
    }

    ensureBindingInit();

    if (PlatformUtils.isLinux || PlatformUtils.isWindows) {
      if (await SingleInstance.tryConnectToMainInstance(commandLineArgs)) {
        exit(0);
      } else {
        SingleInstance.becomeMainInstance();
      }
    }

    FlutterError.onError = Log.getFlutterErrorReporter(FlutterError.onError);

    isHeadless = PlatformUtils.isAndroid &&
        AppLifecycleState.detached == WidgetsBinding.instance.lifecycleState;

    loading = initNecessary();

    if (isHeadless) {
      WidgetsBinding.instance.addObserver(AppStarter());
      await loading;
      return;
    } else {
      await loading;
    }

    CustomURI.init();
    SystemWideShortcuts.init();

    await startGui();
  } catch (error, stacktrace) {
    Telemetry.recordCrash(error, stacktrace, source: "zone", fatal: true);
    runApp(FatalErrorPage(error, stacktrace));
  }
}

WidgetsBinding ensureBindingInit() {
  ScaledWidgetsFlutterBinding.ensureInitialized(
    scaleFactor: (deviceSize) {
      return 1;
    },
  );

  return WidgetsFlutterBinding.ensureInitialized();
}

bool _rustLibReady = false;

/// Initializes the bare necessities for the app to run in headless mode
Future<void> initNecessary() async {
  sqfliteFfiInit();
  await _timedStartupStep("preferences", () => preferences.init());
  if (!isHeadless) await Telemetry.init();
  await _timedStartupStep("database server", () => initDatabaseServer());

  // Vommet: once per process; the integration tests run initNecessary per test.
  if ((PlatformUtils.isWindows || PlatformUtils.isLinux) && !_rustLibReady) {
    await RustLib.init();
    _rustLibReady = true;
  }

  fileCache = FileCache.getFileCacheInstance();

  await _timedStartupStep(
      "file cache + config",
      () => Future.wait([
            if (fileCache != null) fileCache!.init(),
            GlobalConfig.init(),
          ]));

  fileCache?.clean();

  clientManager =
      await _timedStartupStep("accounts loaded", () => ClientManager.init());
  Diagnostics.setPostInit();

  shortcutsManager.init();
  NotificationManager.init();

  NeedsPostLoginInit.doPostLoginInit();
}

/// Initializes everything that is needed to run in GUI mode
Future<void> initGuiRequirements() async {
  isHeadless = false;

  MediaKit.ensureInitialized();

  var locale = PlatformDispatcher.instance.locale;

  // Vommet: initializeMessages returns a SynchronousFuture, whose then() runs
  // its callback inside Future.wait's registration loop and trips a null
  // check there (swallowed in the app, fatal in integration tests). A plain
  // Future around it keeps Future.wait well-behaved.
  Future.wait([
    UnicodeEmojis.load(),
    if (!preferences.debugTranslations.value)
      Future.value(initializeMessages(locale.languageCode)),
    if (preferences.debugTranslations.value) initializeMessagesDebug(),
    initializeDateFormatting(locale.languageCode),
  ]);

  tiamat.getAppScale = () {
    return preferences.appScale.value;
  };

  Intl.defaultLocale = locale.languageCode;
}

/// Initializes gui requirements and launches the gui
Future<void> startGui() async {
  String? initialRoomId;
  String? initialClientId;

  initGuiRequirements();

  if (PlatformUtils.isAndroid) {
    enableEdgeToEdge();
    // Vommet: share target (content shared from other apps).
    ShareIntake.init();

    var initialIntent = await ReceiveIntent.getInitialIntent();
    ReceiveIntent.receivedIntentStream.listen((event) {
      Log.i("Received intent: ${initialIntent}");
      var uri = AndroidIntentHelper.getUriFromIntent(event);
      if (uri is OpenRoomURI) {
        EventBus.doOpenRoom(uri.roomId, clientId: uri.clientId);
      }
    });

    Log.i("Initial intent: ${initialIntent}");

    var uri = AndroidIntentHelper.getUriFromIntent(initialIntent);

    if (uri is OpenRoomURI) {
      initialClientId = uri.clientId;
      initialRoomId = uri.roomId;
    }
  }

  double scale = preferences.appScale.value;

  ScaledWidgetsFlutterBinding.maybeInstance?.scaleFactor = (deviceSize) {
    return scale;
  };

  var initialTheme = await preferences.resolveTheme();

  // Vommet: welcome screen after the first sign-in on a fresh install. Not
  // signed in at startup means no account yet (upgrades are already signed
  // in), and adding a second account later doesn't count either, because
  // the screen is shown once per install.
  if (!clientManager!.isLoggedIn() && !preferences.welcomeShown.value) {
    FirstTimeSetup.registerPostLoginSetup(WelcomeSetup());
  }

  if (preferences.checkForUpdates.value == null &&
      UpdateChecker.shouldCheckForUpdates) {
    FirstTimeSetup.registerPostLoginSetup(UpdateCheckerSetup());
  }

  if (preferences.telemetryConsent.value == null) {
    FirstTimeSetup.registerPostLoginSetup(TelemetryConsentSetup());
  }

  // Vommet: after an update, a "What's new" page lists the changes in every
  // build since the one last opened.
  await WhatsNewSetup.registerIfUpdated();

  if (PlatformUtils.isAndroid) {
    var roomsListCache = Map<String, List<String>>.new();
    for (var client in clientManager!.clients) {
      roomsListCache[client.identifier] =
          client.rooms.map((i) => i.identifier).toList();
    }

    preferences.storeRoomsListCache(roomsListCache);
  }

  // Vommet: the platform splash screen (Android, iOS, web; the window itself
  // on Windows) goes away at the first frame. Rooms load their state in the
  // background after the accounts are loaded (see MatrixClient.queuePostLoad),
  // and the app is not usable until that is in, so wait for it here rather
  // than show an app that cannot be used yet. Capped so a stuck load cannot
  // hold the splash forever.
  await _timedStartupStep(
      "splash held for room state",
      () => clientManager!
          .waitForStartupLoads()
          .timeout(const Duration(seconds: 20), onTimeout: () {}));

  runApp(App(
    clientManager: clientManager!,
    initialTheme: initialTheme,
    initialClientId: initialClientId,
    initialRoom: initialRoomId,
  ));

  WidgetsBinding.instance.addPostFrameCallback((_) {
    Diagnostics.general
        .addResult("Startup: first frame (since launch)", startupClock.elapsed);
  });

  WindowManagement.init().then((_) {
    AppFocus.init();
    Subplatforms.init();
  });
}

void enableEdgeToEdge() async {
  var theme = await preferences.resolveTheme();
  SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge); // Enable Edge-to-Edge on Android 10+
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      systemNavigationBarColor:
          Colors.transparent, // Setting a transparent navigation bar color
      systemNavigationBarContrastEnforced: true, // Default
      systemNavigationBarIconBrightness: theme.brightness == Brightness.dark
          ? Brightness.light
          : Brightness.dark));
}

class App extends StatelessWidget {
  const App(
      {super.key,
      required this.clientManager,
      this.initialTheme,
      this.initialRoom,
      this.initialClientId});
  final ThemeData? initialTheme;
  final ClientManager clientManager;

  final String? initialRoom;
  final String? initialClientId;

  @override
  Widget build(BuildContext context) {
    return CustomSafeArea(
      child: OverlayWindowsManager(
        child: FocusNodeMonitor(
          child: TextScaleChanger(
            child: ThemeChanger(
                shouldFollowSystemTheme: () =>
                    preferences.shouldFollowSystemTheme.value,
                getDarkTheme: () {
                  return preferences.resolveTheme(
                      overrideBrightness: Brightness.dark);
                },
                getLightTheme: () {
                  return preferences.resolveTheme(
                      overrideBrightness: Brightness.light);
                },
                initialTheme: initialTheme ?? ThemeDark.theme,
                materialAppBuilder: (context, theme) {
                  return MaterialApp(
                    title: 'Vommet',
                    theme: theme,
                    showPerformanceOverlay:
                        preferences.showPerformanceOverlay.value,
                    debugShowCheckedModeBanner: false,
                    navigatorKey: navigator,
                    builder: (context, child) => Provider<ClientManager>(
                      create: (context) => clientManager,
                      child: child,
                    ),
                    home: AppView(
                      clientManager: clientManager,
                      initialClientId: initialClientId,
                      initialRoom: initialRoom,
                    ),
                  );
                }),
          ),
        ),
      ),
    );
  }
}

class AppView extends StatefulWidget {
  const AppView(
      {required this.clientManager,
      super.key,
      this.initialClientId,
      this.initialRoom});
  final ClientManager clientManager;
  final String? initialRoom;
  final String? initialClientId;

  @override
  State<AppView> createState() => _AppViewState();
}

class _AppViewState extends State<AppView> {
  StreamSubscription? _onClientRemovedSubscription;
  StreamSubscription? _onClientAddedSubscription;
  late bool isInitiallyLoggedIn;

  @override
  void initState() {
    super.initState();
    _onClientRemovedSubscription =
        widget.clientManager.onClientRemoved.stream.listen((_) {
      if (!widget.clientManager.isLoggedIn()) {
        navigator.currentState?.popUntil((route) => route.isFirst);
        setState(() {});
      }
    });
    _onClientAddedSubscription =
        widget.clientManager.onClientAdded.stream.listen((_) {
      setState(() {});
    });

    isInitiallyLoggedIn = widget.clientManager.isLoggedIn();
  }

  @override
  void dispose() {
    _onClientRemovedSubscription?.cancel();
    _onClientAddedSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.clientManager.isLoggedIn()
        ? MainPage(
            widget.clientManager,
            initialClientId: widget.initialClientId,
            initialRoom: widget.initialRoom,
            wasLoggedInAtStartup: isInitiallyLoggedIn,
          )
        : LoginPage(onSuccess: (_) {
            setState(() {});
          });
  }
}

class AppStarter with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.detached) return;
    if (loading != null) {
      await loading;
    }

    if (isHeadless) {
      startGui();
    }

    super.didChangeAppLifecycleState(state);
  }
}
