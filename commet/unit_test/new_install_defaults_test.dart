// Vommet: settings that are on for new installs only (New Home, the People
// and "Standalone rooms" buttons, GIF search) or off for new installs only
// (encrypting new rooms). Installs that already had an account keep the old
// default, once; a fresh install that signs in keeps the new one.
import 'package:commet/config/room_encryption_default.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/organisms/new_home/new_home.dart';
import 'package:commet/ui/organisms/new_home/new_home_shortcuts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> start(Map<String, Object> stored) async {
    // unit_test/ isn't a directory the analyzer counts as tests.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues(stored);
    await preferences.init();
  }

  Map<String, bool> values() => {
        "newHome": experimentNewHome.value,
        "people": peopleInRail.value,
        "rooms": preferences.showRoomsInSidebar.value,
        "gifs": preferences.tenorGifSearchEnabled.value,
        "encrypt": encryptNewRoomsByDefault.value,
      };

  const newDefaults = {
    "newHome": true,
    "people": true,
    "rooms": true,
    "gifs": true,
    "encrypt": false
  };
  const oldDefaults = {
    "newHome": false,
    "people": false,
    "rooms": false,
    "gifs": false,
    "encrypt": true
  };

  test("the list covers exactly these settings", () {
    expect(preferences.onForNewInstallsOnly.map((p) => p.key).toSet(), {
      experimentNewHome.key,
      peopleInRail.key,
      preferences.showRoomsInSidebar.key,
      preferences.tenorGifSearchEnabled.key,
    });
    expect(preferences.offForNewInstallsOnly.map((p) => p.key).toSet(),
        {encryptNewRoomsByDefault.key});
  });

  test("a new install gets the new defaults", () async {
    await start({});
    expect(values(), newDefaults);
    // "Only when I turn it on" is the default for new rooms.
    expect(encryptNewRoomsByDefault.value, isFalse);
  });

  test("a new install keeps them on after signing in and restarting", () async {
    await start({});
    preferences.addRegisteredMatrixClient("new-account");
    await preferences.init();
    expect(values(), newDefaults);
  });

  test("an install that already had an account keeps the old defaults",
      () async {
    await start({
      "registered_matrix_clients": ["old-account"]
    });
    expect(values(), oldDefaults);
    // New rooms stay encrypted there, as before.
    expect(encryptNewRoomsByDefault.value, isTrue);
  });

  test("an existing install keeps what it switched on", () async {
    await start({
      "registered_matrix_clients": ["old-account"],
      experimentNewHome.key: true,
      preferences.tenorGifSearchEnabled.key: true,
      encryptNewRoomsByDefault.key: false,
    });
    expect(values(), {
      "newHome": true,
      "people": false,
      "rooms": false,
      "gifs": true,
      "encrypt": false
    });
  });

  test("checked once: new-user defaults stay after a reset and a restart",
      () async {
    await start({
      "registered_matrix_clients": ["old-account"]
    });
    expect(values(), oldDefaults);
    for (final p in [
      ...preferences.onForNewInstallsOnly,
      ...preferences.offForNewInstallsOnly
    ]) {
      await p.reset();
    }
    await preferences.init();
    expect(values(), newDefaults);
  });

  test("an install already pinned by the old check keeps its value", () async {
    // The # button's earlier one-off check stored false on existing installs.
    await start({
      "registered_matrix_clients": ["old-account"],
      preferences.showRoomsInSidebar.key: false,
      "vommet_old_defaults_checked": [preferences.showRoomsInSidebar.key],
    });
    expect(preferences.showRoomsInSidebar.value, isFalse);
    expect(experimentNewHome.value, isFalse);
  });
}
