import 'package:commet/client/components/widgets/docked/widget_dock.dart';
import 'package:commet/config/experiment_entries.dart';
import 'package:commet/config/experiment_registry.dart';
import 'package:commet/config/preferences/bool_preference.dart';
import 'package:commet/config/preferences/preference.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/timeline_events/deleted_message_placeholder.dart';
import 'package:commet/ui/organisms/new_home/new_home.dart';
import 'package:commet/ui/pages/room_info/room_info_experiment.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Vommet: experiments are on unless the user switched them off; a few stay
// opt-in.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Experiment experiment(BoolPreference p, {bool optIn = false}) => Experiment(
      preference: p,
      title: "t",
      description: "d",
      category: ExperimentCategory.messages,
      optIn: optIn);

  Future<void> load(Map<String, Object> stored) async {
    // unit_test/ isn't a directory the analyzer counts as tests.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues(stored);
    await preferences.init();
  }

  test("loading the preferences makes the registered experiments opt-out",
      () async {
    await load({});
    expect(BoolPreference.defaultOnKeys,
        contains(preferences.experimentForwardMessages.key));
    expect(preferences.experimentForwardMessages.value, isTrue);
  });

  test("an untouched experiment is on, one switched off stays off", () async {
    final p = BoolPreference("test_experiment", defaultValue: false);
    // Loading the preferences re-applies the registry's keys, so add the
    // test's own experiment after each load.
    void register() => BoolPreference.defaultOnKeys
        .addAll(ExperimentRegistry.defaultOnKeysOf([experiment(p)]));

    await load({});
    register();
    expect(p.value, isTrue);
    expect(Preference.preferences!.containsKey(p.key), isFalse);

    await load({"test_experiment": false});
    register();
    expect(p.value, isFalse);
  });

  test("opt-in experiments stay off", () {
    final flagged = BoolPreference("test_opt_in", defaultValue: false);
    expect(
        ExperimentRegistry.defaultOnKeysOf([experiment(flagged, optIn: true)]),
        isEmpty);
  });

  test("sliding sync is on by default, and stays off once switched off",
      () async {
    final p = BoolPreference("experiment_sliding_sync", defaultValue: false);
    // Loading the preferences re-applies the registry's keys, so add this
    // experiment after each load (as the registry entry would).
    void register() => BoolPreference.defaultOnKeys
        .addAll(ExperimentRegistry.defaultOnKeysOf([experiment(p)]));

    await load({});
    register();
    expect(p.value, isTrue);

    await load({"experiment_sliding_sync": false});
    register();
    expect(p.value, isFalse);
  });

  test("other settings keep their own defaults", () async {
    await load({});
    expect(preferences.minimizeOnClose.value,
        preferences.minimizeOnClose.defaultValue);
  });

  // Graduated experiments (10-25): always on, off the Experiments page.
  group("graduated experiments", () {
    test("read on even when they were switched off", () async {
      await load({
        for (final key in ExperimentRegistry.graduatedKeys) key: false,
      });
      for (final key in ExperimentRegistry.graduatedKeys) {
        expect(BoolPreference(key, defaultValue: false).value, isTrue,
            reason: key);
      }
      for (final p in [
        preferences.experimentEnableE2eeElementCall,
        preferences.experimentEncryptionMarkers,
        preferences.experimentBlockUsers,
        preferences.experimentMessageTimestamps,
        preferences.experimentMessageDrafts,
        preferences.experimentSidebarPinnedRooms,
        preferences.experimentLastRoomPerSpace,
        preferences.experimentVoiceRoomChat,
        preferences.experimentDmTrustWarnings,
        preferences.experimentCallCards,
        preferences.experimentSidebarSubspaceGuides,
      ]) {
        expect(ExperimentRegistry.graduatedKeys, contains(p.key));
        expect(p.value, isTrue, reason: p.key);
        await p.set(false);
        expect(p.value, isTrue, reason: "${p.key} after set(false)");
      }
    });

    test("are not on the Experiments page", () async {
      await load({});
      final listed = experimentEntries().map((e) => e.preference.key);
      for (final key in ExperimentRegistry.graduatedKeys) {
        expect(listed, isNot(contains(key)));
      }
    });

    test("other settings are not forced on", () async {
      await load({"vommet_experiment_forward_messages": false});
      expect(preferences.experimentForwardMessages.value, isFalse);
    });
  });

  // Experiments that became ordinary settings (10-25): same keys, on unless
  // switched off, off the Experiments page.
  group("experiments moved to settings", () {
    List<BoolPreference> moved() => [
          preferences.experimentNoiseSuppression,
          preferences.experimentAutoGainControl,
          preferences.experimentSidebarNewestUnreadDms,
          preferences.experimentSlidingSync,
          preferences.experimentSecureSetup,
          preferences.experimentBannerLayout,
          experimentDeletedMessagePlaceholders,
        ];

    test("are on for someone who never changed them", () async {
      await load({});
      for (final p in moved()) {
        expect(p.value, isTrue, reason: p.key);
      }
    });

    test("keep a choice made while they were experiments", () async {
      await load({for (final p in moved()) p.key: false});
      for (final p in moved()) {
        expect(p.value, isFalse, reason: p.key);
      }
    });

    test("are not on the Experiments page", () async {
      await load({});
      final listed = experimentEntries().map((e) => e.preference.key);
      for (final p in moved()) {
        expect(listed, isNot(contains(p.key)));
      }
    });
  });

  // New Home on for everyone (10-25).
  group("New Home", () {
    test("an install that had it kept off gets it on, once", () async {
      await load({
        "registered_matrix_clients": ["matrix_client"],
        "vommet_experiment_new_home": false,
      });
      expect(experimentNewHome.value, isTrue);

      // Switched off again: stays off from now on.
      await experimentNewHome.set(false);
      await preferences.init();
      expect(experimentNewHome.value, isFalse);
    });

    test("an existing install that never stored it gets it on", () async {
      await load({
        "registered_matrix_clients": ["matrix_client"],
      });
      expect(experimentNewHome.value, isTrue);
      expect(
          Preference.preferences!.containsKey(experimentNewHome.key), isFalse);
    });

    test("a new install has it on", () async {
      await load({});
      expect(experimentNewHome.value, isTrue);
    });
  });

  // Docked widgets, Redacted mode, Read state per thread and Nickname per
  // space on by default; the Friends tab removed (10-25).
  group("experiments on by default since 10-25", () {
    const keys = [
      "vommet_experiment_docked_widgets",
      "vommet_experiment_redacted_mode",
      "vommet_experiment_thread_read_state",
      "vommet_experiment_space_nicknames",
    ];

    test("are on by default", () {
      final on = ExperimentRegistry.defaultOnKeysOf(experimentEntries());
      for (final key in keys) {
        expect(on, contains(key), reason: key);
      }
    });

    test("Redacted mode itself stays off until switched on", () async {
      await load({});
      expect(preferences.experimentRedactedMode.value, isTrue);
      expect(preferences.redactionEnabled.value, isFalse);
    });

    test("read state per thread and nicknames keep a stored off", () async {
      await load({
        "vommet_experiment_thread_read_state": false,
        "vommet_experiment_space_nicknames": false,
      });
      expect(preferences.experimentThreadReadState.value, isFalse);
      expect(
          BoolPreference("vommet_experiment_space_nicknames",
                  defaultValue: false)
              .value,
          isFalse);
    });

    test("the Friends tab is no longer an experiment", () {
      expect(experimentEntries().map((e) => e.preference.key),
          isNot(contains("vommet_experiment_friends_tab")));
    });

    test("Docked widgets: a stored off is cleared once", () async {
      await load({"vommet_experiment_docked_widgets": false});
      expect(WidgetDock.experiment.value, isTrue);
      expect(Preference.preferences!.containsKey(WidgetDock.experiment.key),
          isFalse);

      // Switched off again: stays off from now on.
      await WidgetDock.experiment.set(false);
      await preferences.init();
      expect(WidgetDock.experiment.value, isFalse);
    });

    test("Docked widgets: a stored on stays on", () async {
      await load({"vommet_experiment_docked_widgets": true});
      expect(WidgetDock.experiment.value, isTrue);
    });
  });

  test("New room info page is on by default and can be switched off", () async {
    await load({});
    expect(experimentRoomInfoPage.value, isTrue);
    await load({"vommet_experiment_room_info_page": false});
    expect(experimentRoomInfoPage.value, isFalse);
  });
}
