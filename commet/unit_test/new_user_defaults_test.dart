import 'package:commet/config/new_user_defaults.dart';
import 'package:commet/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Vommet: "Back to new-user defaults" saves, resets to each preference's own
// default (not "everything off") and restores exactly what was stored.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // unit_test/ isn't a directory the analyzer counts as tests.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      // The opposite of what a new user gets: its defaultValue is off, but
      // experiments are on by default, and new-user defaults mean that
      // default, not "off".
      "vommet_experiment_forward_messages": false,
      "app_theme": "light",
      "app_theme_light": "nordic-polar",
      "notifications_volume": 50.0,
      "allowed_remote_video_hosts": ["example.org"],
    });
    await preferences.init();
  });

  test("experiments go back to their own defaults and restore", () async {
    final forward = preferences.experimentForwardMessages;
    expect(NewUserDefaults.changedExperiments.map((e) => e.preference.key),
        [forward.key]);

    final changed =
        await NewUserDefaults.reset(experiments: true, appSettings: false);
    expect(changed.map((e) => e.preference.key), [forward.key]);
    expect(forward.value, forward.defaultForNewUser);
    expect(forward.hasStoredValue, isFalse);
    expect(preferences.theme.value, "light", reason: "app settings untouched");
    expect(NewUserDefaults.hasSavedSetup, isTrue);
    expect(NewUserDefaults.savedExperimentCount, 1);
    expect(NewUserDefaults.changedExperiments, isEmpty);

    await NewUserDefaults.restore();
    expect(forward.value, !forward.defaultForNewUser);
    expect(NewUserDefaults.hasSavedSetup, isFalse);
  });

  test("app settings reset and restore, unstored ones stay unstored", () async {
    final effects = preferences.messageEffectsEnabled;
    expect(effects.hasStoredValue, isFalse);

    await NewUserDefaults.reset(experiments: false, appSettings: true);
    expect(preferences.theme.value, preferences.theme.defaultForNewUser);
    expect(preferences.themeLight.value, isNull);
    expect(preferences.notificationsVolume.hasStoredValue, isFalse);
    expect(preferences.allowedRemoteVideoHosts.value, isEmpty);
    expect(preferences.experimentForwardMessages.hasStoredValue, isTrue,
        reason: "experiments untouched");

    await NewUserDefaults.restore();
    expect(preferences.theme.value, "light");
    expect(preferences.themeLight.value, "nordic-polar");
    expect(preferences.notificationsVolume.value, 50.0);
    expect(preferences.allowedRemoteVideoHosts.value, ["example.org"]);
    expect(effects.hasStoredValue, isFalse);
  });
}
