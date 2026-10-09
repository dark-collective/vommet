import 'dart:async';
import 'dart:convert';

import 'package:commet/config/build_config.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/config/preferences/bool_preference.dart';
import 'package:commet/config/preferences/double_preference.dart';
import 'package:commet/config/preferences/preference.dart';
import 'package:commet/config/preferences/string_list_preference.dart';
import 'package:commet/config/preferences/string_preference.dart';
import 'package:commet/config/theme_config.dart';
import 'package:commet/main.dart';
import 'package:flutter/material.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_amoled.dart';
import 'package:tiamat/config/style/theme_json_converter.dart';
import 'package:tiamat/config/style/theme_dark.dart';
import 'package:tiamat/config/style/theme_gradient.dart';
import 'package:tiamat/config/style/theme_light.dart';
import 'package:tiamat/config/style/theme_you.dart';

class Preferences {
  SharedPreferences? _preferences;

  static const String registeredMatrixClients = "registered_matrix_clients";

  static const String _pushGateway = "push_gateway";

  static const String _optedInExperiments = "opted_in_experiments";

  static const String _syncedCalendarUrls = "synced_calendar_urls";

  static const String _runningDonationCheckFlow = "running_donation_check_flow";

  static const String _systemHotkey = "system_wide_hotkey";

  static final StreamController onSettingChangedController =
      StreamController.broadcast();
  Stream get onSettingChanged => onSettingChangedController.stream;
  bool isInit = false;

  Future<void> init() async {
    _preferences = await SharedPreferences.getInstance();
    Preference.preferences = _preferences;
    isInit = true;
  }

  List<String>? getRegisteredMatrixClients() {
    if (_preferences!.containsKey(registeredMatrixClients)) {
      return _preferences!.getStringList(registeredMatrixClients);
    }

    return null;
  }

  void addRegisteredMatrixClient(String name) {
    List<String> names = List.empty(growable: true);
    if (_preferences!.containsKey(registeredMatrixClients)) {
      names = List.from(_preferences!.getStringList(registeredMatrixClients)!,
          growable: true);
    }

    names.add(name);
    _preferences!.setStringList(registeredMatrixClients, names);
  }

  void removeRegisteredMatrixClient(String name) {
    List<String>? names;
    if (_preferences!.containsKey(registeredMatrixClients)) {
      names = _preferences!.getStringList(registeredMatrixClients)!;
    }

    if (names != null) {
      if (names.contains(name)) {
        names.remove(name);
      }
      _preferences!.setStringList(registeredMatrixClients, names);
    }
  }

  Future<ThemeData> resolveTheme({Brightness? overrideBrightness}) async {
    if (overrideBrightness == null && shouldFollowSystemTheme.value) {
      overrideBrightness =
          WidgetsBinding.instance.platformDispatcher.platformBrightness;
    }

    if (!PlatformUtils.isWeb) {
      var custom = await ThemeConfig.getThemeByName(preferences.theme.value);
      if (custom != null) {
        var jsonString = await custom.readAsString();
        var json = const JsonDecoder().convert(jsonString);
        var themedata = await ThemeJsonConverter.fromJson(json, custom);
        if (themedata != null) {
          return themedata;
        }
      }
    }

    // Gradient themes carry their own brightness, like custom themes.
    if (theme.value.startsWith(ThemeGradient.prefix)) {
      var preset = ThemeGradient.byId(theme.value);
      if (preset != null) {
        return ThemeGradient.theme(preset);
      }
    }

    if (overrideBrightness == null && shouldFollowSystemColors.value) {
      if (theme.value == "dark") {
        overrideBrightness = Brightness.dark;
      }

      if (theme.value == "light") {
        overrideBrightness = Brightness.light;
      }
    }

    if (overrideBrightness != null && shouldFollowSystemColors.value) {
      return ThemeYou.theme(overrideBrightness);
    }

    if (overrideBrightness == Brightness.dark) {
      return switch (theme.value) {
        "dark" => ThemeDark.theme,
        "amoled" => ThemeAmoled.theme,
        _ => ThemeDark.theme,
      };
    }

    if (overrideBrightness == Brightness.light) {
      return ThemeLight.theme;
    }

    return switch (theme.value) {
      "light" => ThemeLight.theme,
      "dark" => ThemeDark.theme,
      "amoled" => ThemeAmoled.theme,
      _ => ThemeDark.theme,
    };
  }

  Future<void> clear() async {
    await _preferences!.clear();
  }

  Future<void> setPushGateway(String value) async {
    await _preferences!.setString(_pushGateway, value);
  }

  // Vommet: upstream's default is push.commet.chat, Commet's own gateway. The
  // fork ships no Google-services build, and for UnifiedPush it defaults to
  // the UnifiedPush project's public Matrix gateway. Pushers registered with
  // the old default are replaced on the next start (updatePushers deletes
  // pushers whose gateway URL differs).
  String get pushGateway => BuildConfig.ENABLE_GOOGLE_SERVICES
      ? "push.commet.chat"
      : _preferences!.getString(_pushGateway) ??
          "matrix.gateway.unifiedpush.org";

  Future<void> setExperimentEnabled(String experiment, bool value) async {
    var experiments = _preferences?.getStringList(_optedInExperiments) ??
        List.empty(growable: true);

    if (value) {
      if (experiments.contains(experiment) == false) {
        experiments.add(experiment);
      }
    } else {
      experiments.removeWhere((e) => e == experiment);
    }

    await _preferences!.setStringList(_optedInExperiments, experiments);
  }

  bool isExperimentEnabled(String experiment) {
    return _preferences
            ?.getStringList(_optedInExperiments)
            ?.contains(experiment) ==
        true;
  }

  Map<String, dynamic> getCalendarSources(String roomId) {
    var content = _preferences!.getString(_syncedCalendarUrls + ".${roomId}");
    if (content != null) {
      return jsonDecode(content);
    } else {
      return {};
    }
  }

  Future<void> setCalendarSources(String roomId, Map<String, dynamic> sources) {
    return _preferences!
        .setString(_syncedCalendarUrls + ".${roomId}", jsonEncode(sources));
  }

  (String, DateTime)? get runningDonationCheckFlow {
    var result = _preferences!.getString(_runningDonationCheckFlow);

    if (result != null) {
      var data = jsonDecode(result);
      var user = data["user"] as String;
      var timestamp = data["time"] as int;

      var time = DateTime.fromMillisecondsSinceEpoch(timestamp);

      return (user, time);
    }

    return null;
  }

  Future<void> setRunningDonationCheckFlow(
      String value, DateTime timestamp) async {
    _preferences!.setString(
        _runningDonationCheckFlow,
        jsonEncode({
          "user": value,
          "time": timestamp.millisecondsSinceEpoch,
        }));

    onSettingChangedController.add(null);
  }

  Future<void> clearRunningDonationCheckFlow() async {
    _preferences!.remove(_runningDonationCheckFlow);

    onSettingChangedController.add(null);
  }

  String getHotkeyId(String name) {
    return _systemHotkey + ".$name";
  }

  Future<void> setSystemHotkey(String name, HotKey? key) async {
    var k = getHotkeyId(name);

    if (key == null) {
      await _preferences!.remove(k);
    } else {
      await _preferences!.setString(k, jsonEncode(key.toJson()));
    }
  }

  HotKey? getSystemHotkey(String name) {
    var item = _preferences!.getString(getHotkeyId(name));
    if (item == null) return null;

    return HotKey.fromJson(jsonDecode(item));
  }

  Future<void> setVoipUserVolume(String userId, double volume) async {
    _preferences!.setDouble("call_user_volume:${userId}", volume);
  }

  double getVoipUserVolume(String userId) {
    return _preferences?.getDouble("call_user_volume:${userId}") ?? 1.0;
  }

  /// Vommet: the presence an account chose on its profile card: "online"
  /// (follows app activity), "idle" or "invisible".
  String getPresenceMode(String clientId) {
    return _preferences?.getString("presence_mode:${clientId}") ?? "online";
  }

  Future<void> setPresenceMode(String clientId, String mode) async {
    await _preferences!.setString("presence_mode:${clientId}", mode);
  }

  String _acceptedCapabilitiesKey(String clientId, String widgetNamespace) =>
      "accepted_widget_capabilities:${clientId}:${widgetNamespace}";

  String _rejectedCapabilitiesKey(String clientId, String widgetNamespace) =>
      "rejected_widget_capabilities:${clientId}:${widgetNamespace}";

  String _widgetAllowedKey(String clientId, String widgetNamespace) =>
      "allowed_widget:${clientId}:${widgetNamespace}";

  Future<void> setWidgetAllowed(
      String clientId, String widgetNamespace, bool allowed) async {
    await _preferences?.setBool(
        _widgetAllowedKey(clientId, widgetNamespace), allowed);
  }

  bool getWidgetAllowed(String clientId, String widgetNamespace) {
    return _preferences
            ?.getBool(_widgetAllowedKey(clientId, widgetNamespace)) ??
        false;
  }

  Future<void> allowWidgetCapabilityPermissions(String clientId,
      String widgetNamespace, List<String> capabilities) async {
    var currentAccepted = _preferences?.getStringList(
            _acceptedCapabilitiesKey(clientId, widgetNamespace)) ??
        [];

    var currentRejected = _preferences?.getStringList(
            _rejectedCapabilitiesKey(clientId, widgetNamespace)) ??
        [];

    currentAccepted = List.from(currentAccepted, growable: true);

    currentRejected = List.from(currentRejected, growable: true);

    for (var capability in capabilities) {
      currentRejected.remove(capability);

      if (currentAccepted.contains(capability) == false) {
        currentAccepted.add(capability);
      }
    }

    _preferences?.setStringList(
        _acceptedCapabilitiesKey(clientId, widgetNamespace), currentAccepted);
    _preferences?.setStringList(
        _rejectedCapabilitiesKey(clientId, widgetNamespace), currentRejected);
  }

  Future<void> rejectWidgetCapabilityPermissions(String clientId,
      String widgetNamespace, List<String> capabilities) async {
    var currentAccepted = _preferences?.getStringList(
            _acceptedCapabilitiesKey(clientId, widgetNamespace)) ??
        [];

    var currentRejected = _preferences?.getStringList(
            _rejectedCapabilitiesKey(clientId, widgetNamespace)) ??
        [];

    currentAccepted = List.from(currentAccepted, growable: true);

    currentRejected = List.from(currentRejected, growable: true);

    for (var capability in capabilities) {
      currentAccepted.remove(capability);

      if (currentRejected.contains(capability) == false) {
        currentRejected.add(capability);
      }
    }

    _preferences?.setStringList(
        _acceptedCapabilitiesKey(clientId, widgetNamespace), currentAccepted);
    _preferences?.setStringList(
        _rejectedCapabilitiesKey(clientId, widgetNamespace), currentRejected);
  }

  // Vommet experiment: Block / Unblock in profiles and a blocked users list
  // in Settings › Security.
  BoolPreference experimentBlockUsers =
      BoolPreference("vommet_experiment_block_users", defaultValue: false);

  Future<List<String>> getAcceptedWidgetCapabilities(
      String clientId, String widgetNamespace) async {
    return _preferences?.getStringList(
            _acceptedCapabilitiesKey(clientId, widgetNamespace)) ??
        [];
  }

  Future<List<String>> getRejectedWidgetCapabilities(
      String clientId, String widgetNamespace) async {
    return _preferences?.getStringList(
            _rejectedCapabilitiesKey(clientId, widgetNamespace)) ??
        [];
  }

  Future<void> clearWidgetSettings(
      String clientId, String widgetNamespace) async {
    await _preferences
        ?.remove(_acceptedCapabilitiesKey(clientId, widgetNamespace));

    await _preferences
        ?.remove(_rejectedCapabilitiesKey(clientId, widgetNamespace));

    await _preferences?.remove(_widgetAllowedKey(clientId, widgetNamespace));
  }

  static const String _roomsListCache = "rooms_list_cache";

  Map<String, List<String>> getRoomsListCache() {
    var str = _preferences?.getString(_roomsListCache) ?? "{}";
    var data = jsonDecode(str) as Map<String, dynamic>;

    var result = Map<String, List<String>>.new();
    for (var entry in data.entries) {
      result[entry.key] = data.tryGetList<String>(entry.key) ?? [];
    }

    return result;
  }

  Future<void> storeRoomsListCache(Map<String, List<String>> rooms) async {
    await _preferences?.setString(_roomsListCache, jsonEncode(rooms));
  }

  BoolPreference shouldFollowSystemTheme =
      BoolPreference("should_follow_system_theme", defaultValue: false);

  BoolPreference shouldFollowSystemColors =
      BoolPreference("should_follow_system_colors", defaultValue: false);

  // Vommet: a "Manage rooms" editor for a space.
  BoolPreference experimentManageSpaceRooms =
      BoolPreference("experiment_manage_space_rooms", defaultValue: false);

  BoolPreference minimizeOnClose =
      BoolPreference("minimize_on_close", defaultValue: false);

  BoolPreference developerMode =
      BoolPreference("developer_mode", defaultValue: false);

  // Vommet: secure messaging setup at sign-in (Vommet issue 129). On by
  // default; an experiment only so it can be turned off for crash triage.
  BoolPreference experimentSecureSetup =
      BoolPreference("experiment_secure_setup", defaultValue: true);

  BoolPreference showStateEvents =
      BoolPreference("show_state_events", defaultValue: true);

  BoolPreference collapseStateEvents =
      BoolPreference("collapse_state_events", defaultValue: true);

  // Vommet: lay out consecutive pictures/videos from one sender as a mosaic.
  BoolPreference groupConsecutiveMedia =
      BoolPreference("group_consecutive_media", defaultValue: true);

  BoolPreference debugTranslations =
      BoolPreference("enable_translations_debug", defaultValue: false);

  BoolPreference tenorGifSearchEnabled =
      BoolPreference("enable_tenor_gif_search", defaultValue: false);

  //Workaround for: https://github.com/commetchat/commet/issues/202
  BoolPreference stickerCompatibilityMode =
      BoolPreference("sticker_compatibility_mode", defaultValue: true);

  BoolPreference useFallbackTurnServer =
      BoolPreference("use_fallback_turn_server", defaultValue: false);

  BoolPreference urlPreviewInE2EEChat =
      BoolPreference("use_url_preview_in_e2ee_chat", defaultValue: false);

  // Vommet: org-mode style /italics/ in sent messages.
  BoolPreference orgModeItalics =
      BoolPreference("org_mode_italics", defaultValue: true);

  // Vommet: formatting bar on selection (desktop), Aa button (phone).
  BoolPreference formattingPopup =
      BoolPreference("formatting_popup", defaultValue: true);

  BoolPreference messageEffectsEnabled =
      BoolPreference("message_effects_enabled", defaultValue: true);

  BoolPreference showRoomAvatars =
      BoolPreference("show_room_avatars", defaultValue: true);

  BoolPreference showRoomsInSidebar =
      BoolPreference("show_rooms_in_sidebar", defaultValue: false);

  BoolPreference usePlaceholderRoomAvatars =
      BoolPreference("use_placeholder_room_avatars", defaultValue: false);

  // Vommet: on by default (Discord shows media everywhere).
  BoolPreference previewMediaInPublicRooms =
      BoolPreference("preview_media_in_public_rooms", defaultValue: true);

  BoolPreference previewMediaInPrivateRooms =
      BoolPreference("preview_media_in_private_rooms", defaultValue: true);

  BoolPreference showMediaInNotifications =
      BoolPreference("show_media_in_notifications", defaultValue: true);

  BoolPreference formatNotificationBody =
      BoolPreference("format_notification_body", defaultValue: true);

  BoolPreference previewUrlInNotifications =
      BoolPreference("preview_urls_in_notification", defaultValue: true);

  BoolPreference useLegacyNotificationHandler =
      BoolPreference("use_legacy_notification_handler", defaultValue: false);

  BoolPreference openRoomsAtLastReadMessage =
      BoolPreference("open_rooms_at_last_read_message", defaultValue: false);

  BoolPreference askBeforeDeletingMessageEnabled =
      BoolPreference("ask_before_deleting_message_enabled", defaultValue: true);

  // Vommet experiment: "Forward" in the message menu.
  BoolPreference experimentForwardMessages =
      BoolPreference("vommet_experiment_forward_messages", defaultValue: false);

  // Vommet experiment: keep unsent text when switching rooms.
  BoolPreference experimentMessageDrafts =
      BoolPreference("vommet_experiment_message_drafts", defaultValue: false);

  BoolPreference silenceNotifications = BoolPreference(
      "silence_notifications_when_other_device_active",
      defaultValue: true);

  BoolPreference showNotificationBadgesInTaskbar =
      BoolPreference("show_notification_badges_in_taskbar", defaultValue: true);

  BoolPreference disableTextCursorManagement =
      BoolPreference("disable_text_cursor_management", defaultValue: false);

  BoolPreference hideRoomSidePanel =
      BoolPreference("hide_room_side_panel", defaultValue: false);

  // Vommet: messages sent while offline go out when back online, also after
  // a restart (see OfflineSending).
  BoolPreference experimentOfflineSending =
      BoolPreference("experiment_offline_sending", defaultValue: false);

  BoolPreference experimentMessageTimestamps =
      BoolPreference("experiment_message_timestamps", defaultValue: false);

  BoolPreference experimentRoomCalls =
      BoolPreference("experiment_room_calls", defaultValue: false);

  BoolPreference experimentMultiSfu =
      BoolPreference("experiment_multi_sfu", defaultValue: false);

  BoolPreference showRoomPreviewsInSpaceSidebar =
      BoolPreference("show_room_previews_in_space_sidebar", defaultValue: true);

  BoolPreference autoFocusMessageTextBox = BoolPreference(
      "auto_focus_message_textbox",
      defaultGetter: () => PlatformUtils.isAndroid ? false : true,
      defaultValue: false);

  BoolPreference selectAutoCompleteSuggestion =
      BoolPreference("select_auto_complete_suggestion", defaultValue: false);

  BoolPreference automaticallyOpenSpace =
      BoolPreference("open_space_on_room_navigation", defaultValue: true);

  BoolPreference pauseAnimationsWhenNotFocused =
      BoolPreference("pause_animations_When_not_focused", defaultValue: true);

  BoolPreference autoRotateImages =
      BoolPreference("lightbox_rotate_images", defaultValue: false);

  // Vommet experiment: arrow keys / swipe between a room's pictures and
  // videos in the image viewer.
  BoolPreference experimentLightboxGallery =
      BoolPreference("vommet_experiment_lightbox_gallery", defaultValue: false);

  BoolPreference autoRotateVideos =
      BoolPreference("lightbox_rotate_videos", defaultValue: false);

  DoublePreference textScale =
      DoublePreference("text_scale", defaultValue: 1.0);

  // Vommet: desktop pane widths (the space/room list and the member panel),
  // set by dragging their edges; double-click an edge to reset.
  DoublePreference leftPaneWidth =
      DoublePreference("vommet_left_pane_width", defaultValue: 250);

  DoublePreference rightPaneWidth =
      DoublePreference("vommet_right_pane_width", defaultValue: 250);

  // Vommet experiment: Discord-style layout (collapsing banners, online and
  // offline member sections, resizable panes).
  BoolPreference experimentBannerLayout =
      BoolPreference("vommet_experiment_banner_layout", defaultValue: false);

  // Vommet experiment: read state per thread (threaded read receipts, unread
  // marks in the room's thread list).
  BoolPreference experimentThreadReadState = BoolPreference(
      "vommet_experiment_thread_read_state",
      defaultValue: false);

  // Vommet: the glow behind banner titles: "theme" (the theme's colour, the
  // default), "classic" (always the classic blue) or "off".
  StringPreference bannerGradient =
      StringPreference("vommet_banner_gradient", defaultValue: "theme");

  BoolPreference doSimulcast =
      BoolPreference("livekit_use_simulcast", defaultValue: false);

  BoolPreference enableNotifications =
      BoolPreference("notifications_enabled", defaultValue: true);

  BoolPreference suppressNotificationWhenRoomFocused = BoolPreference(
      "suppress_notification_when_room_focused",
      defaultValue: true);

  // Vommet: on by default so encrypted rooms' calls work out of the box.
  BoolPreference experimentEnableE2eeElementCall = BoolPreference(
      "experiment_enabled_e2ee_element_call",
      defaultValue: true);

  BoolPreference experimentSlidingSync =
      BoolPreference("experiment_sliding_sync", defaultValue: false);

  BoolPreference experimentNoiseSuppression =
      BoolPreference("experiment_noise_suppression", defaultValue: false);

  /// Vommet: ask libwebrtc to level the microphone (automatic gain control).
  /// Commet opens the microphone with it off, which sounds quieter than
  /// Element Call and Discord.
  BoolPreference experimentAutoGainControl =
      BoolPreference("experiment_auto_gain_control", defaultValue: false);

  /// Vommet: the profile card (status message, presence, avatar and banner)
  /// and the microphone volume slider.
  BoolPreference experimentQuickProfileControls =
      BoolPreference("experiment_quick_profile_controls", defaultValue: false);

  // Vommet: on by default; an experiment only so it can be switched off when
  // triaging a crash.
  BoolPreference experimentEncryptionMarkers =
      BoolPreference("experiment_encryption_markers", defaultValue: true);

  // Vommet: on by default; an experiment only so it can be switched off when
  // triaging a crash.
  BoolPreference experimentDmTrustWarnings =
      BoolPreference("experiment_dm_trust_warnings", defaultValue: true);

  BoolPreference useSharedIsolateInBackgroundTasks = BoolPreference(
      "use_shared_isolate_in_background_tasks",
      defaultValue: false);

  BoolPreference showPerformanceOverlay =
      BoolPreference("show_performance_overlay", defaultValue: false);

  DoublePreference notificationsVolume =
      DoublePreference("notifications_volume", defaultValue: 90.0);

  DoublePreference streamBitrate =
      DoublePreference("screenshare_bitrate_mbps", defaultValue: 8);

  DoublePreference streamAudioBitrate =
      DoublePreference("stream_audio_kbps", defaultValue: 96);

  DoublePreference streamFramerate =
      DoublePreference("screenshare_fps", defaultValue: 60);

  // Vommet: subspaces drawn with guide lines, voice rooms show who's in them.
  BoolPreference experimentSidebarSubspaceGuides =
      BoolPreference("experiment_sidebar_subspace_guides", defaultValue: false);

  // Vommet: quick ways to open a voice room's text chat.
  BoolPreference experimentVoiceRoomChat =
      BoolPreference("experiment_voice_room_chat", defaultValue: false);

  StringPreference streamCodec =
      StringPreference("livekit_screenshare_codec", defaultValue: "av1");

  StringPreference streamResolution = StringPreference(
      "livekit_screenshare_resolution",
      defaultValue: "1920x1080");

  DoublePreference appScale = DoublePreference("app_scale", defaultValue: 1.0);

  DoublePreference emojiPickerHeight =
      DoublePreference("emoji_picker_height", defaultValue: 300);

  BoolPreference experimentSidebarDesktopDrag =
      BoolPreference("experiment_sidebar_desktop_drag", defaultValue: false);

  BoolPreference experimentSidebarPinnedRooms =
      BoolPreference("experiment_sidebar_pinned_rooms", defaultValue: false);

  BoolPreference experimentSidebarNewestUnreadDms = BoolPreference(
      "experiment_sidebar_newest_unread_dms",
      defaultValue: false);

  DoublePreference customOnscreenKeyboardViewOffset = DoublePreference(
      "custom_onscreen_keyboard_view_offset",
      defaultValue: 0.0);

  StringPreference proxyUrl =
      StringPreference("proxy_url", defaultValue: "proxy.nether.im");

  StringPreference fallbackTurnServer = StringPreference("fallback_turn_server",
      defaultValue: "stun:turn.matrix.org");

  StringPreference theme = StringPreference("app_theme", defaultValue: "dark");

  // Vommet: build date (ms) of the last build whose "What's new" was seen.
  NullableStringPreference whatsNewSeenBuild = NullableStringPreference(
      "vommet_whats_new_seen_build",
      defaultValue: null);

  NullableStringPreference lastOpenedVersion =
      NullableStringPreference("last_run_version", defaultValue: null);

  NullableBoolPreference unifiedPushEnabled =
      NullableBoolPreference("unified_push_enabled", defaultValue: null);

  // Vommet: the welcome screen after the first sign-in has been shown.
  BoolPreference welcomeShown =
      BoolPreference("vommet_welcome_shown", defaultValue: false);

  NullableBoolPreference checkForUpdates =
      NullableBoolPreference("check_for_updates", defaultValue: null);

  /// Opt-in diagnostics (Vommet). null = not asked yet; asked once on the
  /// consent screen, changeable in Settings › Privacy.
  NullableBoolPreference telemetryConsent =
      NullableBoolPreference("telemetry_consent", defaultValue: null);

  /// Random ID that diagnostics are filed under; never derived from an
  /// account. Kept when diagnostics are turned off (so earlier reports can
  /// still be deleted); replaced by "Delete my diagnostics".
  NullableStringPreference telemetryInstallId =
      NullableStringPreference("telemetry_install_id", defaultValue: null);

  /// Optional name tag the user types to group their own diagnostics across
  /// devices (Settings › Privacy). Empty by default; never filled in from the
  /// account. With a tag, reports aren't pseudonymous. See TelemetryTag.
  NullableStringPreference telemetryTag =
      NullableStringPreference("telemetry_tag", defaultValue: null);

  NullableStringPreference layoutOverride =
      NullableStringPreference("layout_override", defaultValue: null);

  /// "off", "standard" (RNNoise), "best" (DeepFilterNet3) or "auto"; only
  /// used while [experimentNoiseSuppression] is on.
  StringPreference voipNoiseSuppression =
      StringPreference("voip_noise_suppression", defaultValue: "auto");

  /// Vommet: microphone volume, 0.0 to 2.0 (Discord's 0-200 %); only used
  /// while [experimentQuickProfileControls] is on.
  DoublePreference voipMicrophoneVolume =
      DoublePreference("voip_microphone_volume", defaultValue: 1.0);

  /// Vommet: volume of everyone in a call, 0.0 to 2.0, on top of each
  /// person's own volume; only used while [experimentQuickProfileControls]
  /// is on.
  DoublePreference voipOutputVolume =
      DoublePreference("voip_output_volume", defaultValue: 1.0);

  /// The mode the call panel's noise suppression button turns back on.
  StringPreference voipNoiseSuppressionLastOn =
      StringPreference("voip_noise_suppression_last_on", defaultValue: "auto");

  NullableStringPreference voipDefaultAudioInput =
      NullableStringPreference("voip_default_audio_input", defaultValue: null);

  NullableStringPreference voipDefaultAudioOutput =
      NullableStringPreference("voip_default_audio_output", defaultValue: null);

  NullableStringPreference voipDefaultVideoInput =
      NullableStringPreference("voip_default_video_input", defaultValue: null);

  NullableStringPreference filterClient =
      NullableStringPreference("filter_client_id", defaultValue: null);

  StringListPreference roomDirectorySavedServers =
      StringListPreference("room_directory_saved_servers", defaultValue: []);

  BoolPreference roomDirectoryShowSuggestions =
      BoolPreference("room_directory_show_suggestions", defaultValue: true);

  NullableStringPreference fcmKey =
      NullableStringPreference("fcm_key", defaultValue: null);

  NullableStringPreference unifiedPushEndpoint =
      NullableStringPreference("unified_push_endpoint", defaultValue: null);

  NullableStringPreference lastDownloadLocation =
      NullableStringPreference("last_download_location", defaultValue: null);

  StringListPreference allowedRemoteVideoHosts =
      StringListPreference("allowed_remote_video_hosts", defaultValue: []);

  StringListPreference expandedSpaceGroups =
      StringListPreference("expanded_space_groups", defaultValue: []);
}
