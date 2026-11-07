// Vommet (issues 602, 611): Settings › Privacy › Search › "Index encrypted
// chats". Kept beside the feature, not in preferences.dart.
import 'package:commet/config/build_config.dart';
import 'package:commet/config/preferences/bool_preference.dart';
import 'package:commet/config/preferences/string_preference.dart';
import 'package:intl/intl.dart';

/// When the background index of encrypted chats is built. Off still caches
/// what a search scans.
enum EncryptedIndexMode {
  off("off"),
  wifiOnly("wifi"),
  always("always");

  const EncryptedIndexMode(this.key);
  final String key;

  static EncryptedIndexMode fromKey(String key) =>
      values.firstWhere((m) => m.key == key, orElse: () => defaultMode);

  /// Always on desktop, Wi-Fi only on phones.
  static EncryptedIndexMode get defaultMode => BuildConfig.MOBILE
      ? EncryptedIndexMode.wifiOnly
      : EncryptedIndexMode.always;
}

final StringPreference encryptedIndexModePreference = StringPreference(
    "vommet_index_encrypted_chats",
    defaultValue: EncryptedIndexMode.defaultMode.key);

EncryptedIndexMode get encryptedIndexMode =>
    EncryptedIndexMode.fromKey(encryptedIndexModePreference.value);

/// Vommet issue 845: pause the background index whenever the device runs on
/// battery. On by default on laptops; off on phones, which are rarely
/// plugged in (battery saver and a low battery pause it anyway). Only shown
/// on devices with a battery.
final BoolPreference pauseIndexOnBatteryPreference = BoolPreference(
    "vommet_index_pause_on_battery",
    defaultValue: !BuildConfig.MOBILE);

String get pauseIndexOnBatteryTitle => Intl.message("Pause on battery power",
    name: "pauseIndexOnBatteryTitle",
    desc: "Setting: pause the encrypted search index while on battery");

String get pauseIndexOnBatteryDescription => Intl.message(
    "Indexing waits until this device is plugged in. Battery saver and low battery always pause it.",
    name: "pauseIndexOnBatteryDescription",
    desc: "Describes the 'Pause on battery power' setting");

String get searchSettingsHeader => Intl.message("Search",
    name: "searchSettingsHeader",
    desc: "Header of the search section in Settings › Privacy");

String get indexEncryptedChatsTitle => Intl.message("Index encrypted chats",
    name: "indexEncryptedChatsTitle",
    desc: "Setting: build a search index of encrypted chats on this device");

String get indexEncryptedChatsDescription => Intl.message(
    "Builds a search index of your encrypted chats and all DMs on this device so search and Shared counts are instant. Stored with your message cache.",
    name: "indexEncryptedChatsDescription",
    desc: "Describes the 'Index encrypted chats' setting");

String get indexModeOff => Intl.message("Off",
    name: "indexModeOff",
    desc: "Index encrypted chats: never in the background");

String get indexModeWifiOnly => Intl.message("Wi-Fi only",
    name: "indexModeWifiOnly",
    desc: "Index encrypted chats: only while on Wi-Fi");

String get indexModeAlways => Intl.message("Always",
    name: "indexModeAlways", desc: "Index encrypted chats: on any connection");

String indexProgress(int indexed, int total) =>
    Intl.message("Indexed $indexed of $total chats",
        args: [indexed, total],
        name: "indexProgress",
        desc: "Progress of the encrypted search index");

String get indexStateRunning => Intl.message("Running in the background",
    name: "indexStateRunning",
    desc: "The encrypted search index is being built");

String get indexStateWaitingForWifi => Intl.message("Waiting for Wi-Fi",
    name: "indexStateWaitingForWifi",
    desc: "The encrypted search index waits for a Wi-Fi connection");

String get indexStateOff => Intl.message(
    "Off. Search still looks through older messages when you search, and keeps what it found.",
    name: "indexStateOff",
    desc: "The encrypted search index is switched off");

String get indexStatePausedForBattery => Intl.message("Paused to save battery",
    name: "indexStatePausedForBattery",
    desc:
        "The search index waits while on battery power, battery saver is on or the battery is low");

String indexSize(String size) => Intl.message("Index size: $size",
    args: [size],
    name: "indexSize",
    desc: "How much space the search index takes on this device");

String get indexStateDone => Intl.message("Up to date",
    name: "indexStateDone", desc: "Every encrypted chat is indexed");

String get indexStateUnavailable =>
    Intl.message("Not available in this version of Vommet",
        name: "indexStateUnavailable",
        desc: "The encrypted search index can't run here (the web version)");

String get indexClear => Intl.message("Clear index",
    name: "indexClear", desc: "Button that deletes the encrypted search index");

String get indexClearPrompt => Intl.message(
    "Delete the search index of your encrypted chats from this device? It is built again in the background unless indexing is off.",
    name: "indexClearPrompt",
    desc: "Body of the clear search index confirmation");

String get indexCleared => Intl.message("Search index cleared",
    name: "indexCleared", desc: "Snackbar after the search index was cleared");
