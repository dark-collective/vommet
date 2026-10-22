import 'dart:async';
import 'dart:io';

import 'package:commet/telemetry/telemetry.dart';
import 'package:commet/ui/pages/setup/menus/telemetry_consent.dart';
import 'package:commet/cache/file_cache.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:commet/client/components/component.dart';
import 'package:commet/client/components/push_notification/android/unified_push_notifier.dart';
import 'package:commet/client/components/push_notification/notification_manager.dart';
import 'package:commet/config/app_language.dart';
import 'package:commet/config/build_config.dart';
import 'package:commet/config/fold_layout.dart';
import 'package:commet/config/splash_messages.dart';
import 'package:commet/config/global_config.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/config/preferences.dart';
import 'package:commet/config/title_bar_brightness.dart';
import 'package:commet/config/subplatforms/subplatforms.dart';
import 'package:commet/debug/l10n_debug_lookup.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/diagnostic/diagnostics.dart';
import 'package:commet/generated/intl/messages_all.dart';
import 'package:commet/rust/frb_generated.dart';
import 'package:commet/single_instance.dart';
import 'package:commet/ui/atoms/release_notice_bar.dart';
import 'package:commet/ui/organisms/overlay_windows/overlay_window_manager.dart';
import 'package:commet/ui/pages/bubble/bubble_page.dart';
import 'package:commet/ui/pages/fatal_error/fatal_error_page.dart';
import 'package:commet/ui/pages/splash/splash_page.dart';
import 'package:commet/ui/pages/login/login_page.dart';
import 'package:commet/ui/pages/main/main_page.dart';
import 'package:commet/ui/pages/setup/menus/check_for_updates.dart';
import 'package:commet/ui/pages/setup/menus/welcome_setup.dart';
import 'package:commet/ui/pages/setup/onboarding/onboarding_setup.dart';
import 'package:commet/ui/pages/guides/getting_started.dart';
import 'package:commet/utils/android_intent_helper.dart';
import 'package:commet/utils/android_renderer.dart';
import 'package:commet/utils/app_focus_util.dart';
import 'package:commet/utils/app_language_setup.dart';
import 'package:commet/utils/app_localizations.dart';
import 'package:commet/utils/custom_safe_area.dart';
import 'package:commet/utils/custom_uri.dart';
import 'package:commet/utils/background_tasks/background_task_manager.dart';
import 'package:commet/utils/database/database_server.dart';
import 'package:commet/utils/emoji/unicode_emoji.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:commet/utils/first_time_setup.dart';
import 'package:commet/ui/pages/setup/menus/whats_new_setup.dart';
import 'package:commet/utils/focus_node_monitor.dart';
import 'package:commet/utils/linux_connectivity.dart';
import 'package:commet/utils/scaled_app.dart';
import 'package:commet/utils/share_intake.dart';
import 'package:commet/utils/shortcuts_manager.dart';
import 'package:commet/utils/system_wide_shortcuts/system_wide_shortcuts.dart';
import 'package:commet/utils/text_scale_changer.dart';
import 'package:commet/utils/update_checker.dart';
import 'package:commet/utils/window_management.dart';
import 'package:commet/config/app_font.dart';
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
import 'package:tiamat/config/style/theme_dark.dart';
import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:commet/utils/clock_format.dart';

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
      localizationsDelegates: AppLocalizations.delegates,
      locale: AppLocalizations.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => ClockFormatScope(
            child: Provider<ClientManager>(
              create: (context) => clientManager!,
              child: child,
            ),
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

    // Vommet: draw the splash (with a random message) right away instead of
    // leaving the platform splash, or a blank window on Linux, up while the
    // accounts load. startGui replaces it with the app.
    if (!isHeadless) {
      runApp(SplashPage(message: randomSplashMessage()));
    }

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

  if (PlatformUtils.isLinux) LinuxConnectivity.install();

  fileCache = FileCache.getFileCacheInstance();

  await _timedStartupStep(
      "file cache + config",
      () => Future.wait([
            if (fileCache != null) fileCache!.init(),
            GlobalConfig.init(),
          ]));

  // Vommet: clean the media cache after startup, not during it. Skipped if
  // the cache was replaced or closed meanwhile (the integration tests start
  // the app once per test); a failure is only logged.
  final cacheToClean = fileCache;
  Future.delayed(const Duration(seconds: 30), () async {
    if (cacheToClean == null || cacheToClean != fileCache) return;
    try {
      await cacheToClean.clean();
    } catch (e) {
      Log.w("Media cache clean-up failed: $e");
    }
  });

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

  // Vommet: the app language setting, else the best translation for the
  // device's locales (script/country aware: zh_Hant, pt_BR), else English.
  // `locale.languageCode` below is that translation's id (e.g. "zh_Hant"),
  // not just the device's language code; kept as a record so the upstream
  // lines using it stay as they are.
  AppLanguages.startupPreference = preferences.appLanguage.value;
  final language = AppLanguages.resolve(
      AppLanguages.startupPreference, PlatformDispatcher.instance.locales);
  AppLanguages.current = language;
  final locale = (languageCode: language.id);

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

  // Vommet: date/number formats for a language intl has no data for
  // (Esperanto → English) or only a poorer guess (zh_Hant → zh_TW, not zh).
  AppLanguageSetup.ensureFormattingLocale(language.id, language.formatLocale);
}

/// Initializes gui requirements and launches the gui
Future<void> startGui() async {
  String? initialRoomId;
  String? initialClientId;

  initGuiRequirements();
  AndroidRenderer.confirmAfterFirstFrame();

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
    // Vommet: language, layout, theme, spacing and encryption first, on the
    // same fresh installs (Vommet issue 524).
    if (!onboardingShown.value) {
      OnboardingSetup.menus().forEach(FirstTimeSetup.registerPostLoginSetup);
    }
    FirstTimeSetup.registerPostLoginSetup(WelcomeSetup());
    // Vommet: then the Getting started walkthrough.
    GettingStarted.registerIfNew();
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
    storeRoomsListCache(clientManager!);
    // Vommet: background notifications find a push's account in this cache.
    // Written only here, it missed rooms that loaded after startup or were
    // joined later, and their pushes were dropped; keep it current.
    Timer? pending;
    void refresh(_) {
      pending?.cancel();
      pending = Timer(const Duration(seconds: 2),
          () => storeRoomsListCache(clientManager!));
    }

    clientManager!.onRoomAdded.listen(refresh);
    clientManager!.onRoomRemoved.listen(refresh);
    clientManager!.onClientAdded.stream.listen(refresh);
    clientManager!.onClientRemoved.stream.listen(refresh);
  }

  // Vommet: the splash (SplashPage, drawn in appMain) stays up until runApp
  // below replaces it. Rooms load their state in the
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

  // Vommet: the GTK title bar follows the theme (Vommet issue 384).
  if (PlatformUtils.isLinux) TitleBarBrightness.init(initialTheme);
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
                // Vommet: the app font setting.
                themeFilter: AppFont.apply,
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
                    // Vommet: the app language, so Flutter's own texts and
                    // CJK glyph choice follow it.
                    localizationsDelegates: AppLocalizations.delegates,
                    locale: AppLocalizations.locale,
                    supportedLocales: AppLocalizations.supportedLocales,
                    debugShowCheckedModeBanner: false,
                    navigatorKey: navigator,
                    // Vommet: a transparent Material above the Navigator, so
                    // buttons in overlay entries (call tile, banners,
                    // composer popups) find one. Without it, hovering such a
                    // button throws a null check in Material.of in release
                    // builds, on every mouse enter.
                    // Vommet: HingeDisplayFeatures reports the fold of a
                    // foldable iPhone like Android reports its own.
                    // Vommet: ClockFormatScope applies the 12/24-hour clock
                    // setting (Vommet issue 347).
                    builder: (context, child) => HingeDisplayFeatures(
                      child: ClockFormatScope(
                        child: Material(
                          type: MaterialType.transparency,
                          child: Provider<ClientManager>(
                            create: (context) => clientManager,
                            // Vommet: the new-version bar along the bottom.
                            child: GlobalRedactionScope(
                                child: ReleaseNoticeBar(child: child)),
                          ),
                        ),
                      ),
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

/// Every account's room ids, for routing pushes to the right account when
/// the app isn't running (see PushClientRouting).
void storeRoomsListCache(ClientManager clientManager) {
  var roomsListCache = <String, List<String>>{};
  for (var client in clientManager.clients) {
    roomsListCache[client.identifier] =
        client.rooms.map((i) => i.identifier).toList();
  }
  preferences.storeRoomsListCache(roomsListCache);
}
