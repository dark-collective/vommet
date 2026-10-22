// Vommet: settings that are on for new installs only (New Home, the People
// and "Standalone rooms" buttons, GIF search). Installs that already had an
// account keep the old default (off), once; a fresh install that signs in
// keeps the new one.
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
      };

  const allOn = {"newHome": true, "people": true, "rooms": true, "gifs": true};
  const allOff = {
    "newHome": false,
    "people": false,
    "rooms": false,
    "gifs": false
  };

  test("the list covers exactly these settings", () {
    expect(preferences.onForNewInstallsOnly.map((p) => p.key).toSet(), {
      experimentNewHome.key,
      peopleInRail.key,
      preferences.showRoomsInSidebar.key,
      preferences.tenorGifSearchEnabled.key,
    });
  });

  test("a new install gets them on", () async {
    await start({});
    expect(values(), allOn);
    // Unchanged: new rooms start encrypted.
    expect(encryptNewRoomsByDefault.value, isTrue);
  });

  test("a new install keeps them on after signing in and restarting", () async {
    await start({});
    preferences.addRegisteredMatrixClient("new-account");
    await preferences.init();
    expect(values(), allOn);
  });

  test("an install that already had an account keeps them off", () async {
    await start({
      "registered_matrix_clients": ["old-account"]
    });
    expect(values(), allOff);
  });

  test("an existing install keeps what it switched on", () async {
    await start({
      "registered_matrix_clients": ["old-account"],
      experimentNewHome.key: true,
      preferences.tenorGifSearchEnabled.key: true,
    });
    expect(values(),
        {"newHome": true, "people": false, "rooms": false, "gifs": true});
  });

  test("checked once: new-user defaults stay after a reset and a restart",
      () async {
    await start({
      "registered_matrix_clients": ["old-account"]
    });
    expect(values(), allOff);
    for (final p in preferences.onForNewInstallsOnly) {
      await p.reset();
    }
    await preferences.init();
    expect(values(), allOn);
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
