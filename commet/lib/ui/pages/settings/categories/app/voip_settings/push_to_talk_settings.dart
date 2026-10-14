import 'dart:async';

import 'package:commet/config/platform_utils.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/pages/settings/categories/app/boolean_preference_toggle.dart';
import 'package:commet/ui/pages/settings/categories/app/double_preference_slider.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:commet/utils/system_wide_shortcuts/system_wide_shortcuts.dart';
import 'package:flutter/material.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:intl/intl.dart';

/// Vommet: Voice settings' Input Mode panel: voice activity (the default) or
/// push to talk, with its key, release delay and talk sounds (Discord's).
class PushToTalkSettings extends StatefulWidget {
  const PushToTalkSettings({super.key});

  @override
  State<PushToTalkSettings> createState() => _PushToTalkSettingsState();
}

class _PushToTalkSettingsState extends State<PushToTalkSettings> {
  late final StreamSubscription _sub;

  AppShortcut? get _shortcut => SystemWideShortcuts.shortcuts["push_to_talk"];

  bool get _desktop => PlatformUtils.isLinux || PlatformUtils.isWindows;

  @override
  void initState() {
    super.initState();
    _sub = preferences.voipPushToTalk.onChanged
        .listen((_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final on = preferences.voipPushToTalk.value;
    return tiamat.Panel(
      header: pushToTalkInputModeHeader,
      mode: tiamat.TileType.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          _mode(context, pushToTalkVoiceActivity,
              pushToTalkVoiceActivityDescription, false, on),
          _mode(
              context,
              pushToTalkTitle,
              _desktop
                  ? pushToTalkDescriptionDesktop
                  : pushToTalkDescriptionMobile,
              true,
              on),
          if (on) ...[
            if (_desktop) _key(context),
            DoublePreferenceSlider(
              preference: preferences.voipPushToTalkReleaseDelay,
              title: pushToTalkReleaseDelay,
              description: pushToTalkReleaseDelayDescription,
              min: 0,
              max: 2,
              divisions: 40,
              formatValue: (v) =>
                  pushToTalkReleaseDelayValue(v.toStringAsFixed(2)),
            ),
            BooleanPreferenceToggle(
              preference: preferences.voipPushToTalkSounds,
              title: pushToTalkTalkSounds,
              description: pushToTalkTalkSoundsDescription,
            ),
            _note(context, Icons.mic_none, pushToTalkMicOpenNote),
          ],
        ],
      ),
    );
  }

  Widget _mode(BuildContext context, String title, String description,
      bool value, bool current) {
    final scheme = Theme.of(context).colorScheme;
    final selected = value == current;
    return Material(
      color: selected
          ? scheme.surfaceContainerHigh
          : scheme.surfaceContainer.withAlpha(100),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
              color: selected
                  ? scheme.primary.withAlpha(160)
                  : scheme.secondary.withAlpha(20))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => preferences.voipPushToTalk.set(value),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 12, 6),
          child: Row(children: [
            Radio<bool>(
                value: value,
                groupValue: current,
                onChanged: (v) => preferences.voipPushToTalk.set(value)),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  tiamat.Text(title),
                  tiamat.Text.labelLow(description),
                ])),
          ]),
        ),
      ),
    );
  }

  Widget _key(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hotkey = _shortcut?.hotkey;
    final everywhere = SystemWideShortcuts.pushToTalkWorksEverywhere;
    return Container(
      decoration: BoxDecoration(
          color: scheme.surfaceContainer.withAlpha(100),
          border: Border.all(color: scheme.secondary.withAlpha(20)),
          borderRadius: BorderRadius.circular(8)),
      padding: const EdgeInsets.all(8),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            Row(spacing: 12, children: [
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    tiamat.Text(pushToTalkKeyTitle),
                    tiamat.Text.labelLow(hotkey == null
                        ? pushToTalkKeyNone
                        : everywhere
                            ? pushToTalkKeyEverywhere
                            : pushToTalkKeyFocusedOnly),
                  ])),
              if (hotkey != null) HotKeyVirtualView(hotKey: hotkey),
              tiamat.Button.secondary(
                  text: hotkey == null ? pushToTalkSetKey : pushToTalkChangeKey,
                  onTap: () => _pickKey(context)),
            ]),
            if (!everywhere)
              _note(context, Icons.info_outline, pushToTalkFocusedOnlyNote),
          ]),
    );
  }

  Future<void> _pickKey(BuildContext context) async {
    final shortcut = _shortcut;
    if (shortcut == null) return;
    var cleared = false;
    final key = await AdaptiveDialog.show<HotKey>(context, dismissible: false,
        builder: (context) {
      HotKey? hotkey = shortcut.hotkey;
      return Column(
        spacing: 8,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          tiamat.Text.largeTitle(pushToTalkPressKey),
          SizedBox(
            height: 50,
            child: Center(
              child: HotKeyRecorder(
                  initalHotKey: hotkey, onHotKeyRecorded: (k) => hotkey = k),
            ),
          ),
          tiamat.Button(
            text: CommonStrings.promptSubmit,
            onTap: () => Navigator.of(context).pop(hotkey),
          ),
          tiamat.Button.secondary(
            text: pushToTalkClearKey,
            onTap: () {
              cleared = true;
              Navigator.of(context).pop(null);
            },
          ),
        ],
      );
    });
    if (key != null) {
      await shortcut.setHotkey(key);
    } else if (cleared) {
      await shortcut.clearHotkey();
    }
    if (mounted) setState(() {});
  }

  Widget _note(BuildContext context, IconData icon, String text) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6,
        children: [
          Icon(icon,
              size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
          Expanded(child: tiamat.Text.labelLow(text)),
        ],
      );
}

String get pushToTalkInputModeHeader => Intl.message("Input Mode",
    name: "pushToTalkInputModeHeader",
    desc: "Header of the call input mode settings panel");

String get pushToTalkVoiceActivity => Intl.message("Voice activity",
    name: "pushToTalkVoiceActivity",
    desc: "Input mode option: send audio whenever you talk");

String get pushToTalkVoiceActivityDescription =>
    Intl.message("Your microphone sends whenever you talk",
        name: "pushToTalkVoiceActivityDescription",
        desc: "Description of the voice activity input mode");

String get pushToTalkTitle => Intl.message("Push to talk",
    name: "pushToTalkTitle", desc: "Input mode option: push to talk");

String get pushToTalkDescriptionDesktop => Intl.message(
    "Your microphone only sends while you hold a key or the talk button",
    name: "pushToTalkDescriptionDesktop",
    desc: "Description of push to talk on desktop");

String get pushToTalkDescriptionMobile => Intl.message(
    "Your microphone only sends while you hold the talk button in the call",
    name: "pushToTalkDescriptionMobile",
    desc: "Description of push to talk on mobile");

String get pushToTalkReleaseDelay => Intl.message("Release delay",
    name: "pushToTalkReleaseDelay",
    desc: "Title of the push to talk release delay slider");

String get pushToTalkReleaseDelayDescription => Intl.message(
    "Keeps sending a moment after you let go, so the end of a word isn't cut off",
    name: "pushToTalkReleaseDelayDescription",
    desc: "Description of the push to talk release delay slider");

String pushToTalkReleaseDelayValue(String value) => Intl.message("$value s",
    args: [value],
    name: "pushToTalkReleaseDelayValue",
    desc: "Release delay value in seconds; value is a number like '0.25'");

String get pushToTalkTalkSounds => Intl.message("Talk sounds",
    name: "pushToTalkTalkSounds",
    desc: "Title of the push to talk sounds toggle");

String get pushToTalkTalkSoundsDescription =>
    Intl.message("A soft click when you start and stop talking",
        name: "pushToTalkTalkSoundsDescription",
        desc: "Description of the push to talk sounds toggle");

String get pushToTalkMicOpenNote => Intl.message(
    "While push to talk is on, your microphone stays open for the whole call, so the start of each sentence isn't clipped. Your system's \"microphone in use\" light stays on until you leave.",
    name: "pushToTalkMicOpenNote",
    desc: "Note shown while push to talk is on");

String get pushToTalkKeyTitle => Intl.message("Push to talk key",
    name: "pushToTalkKeyTitle", desc: "Title of the push to talk key setting");

String get pushToTalkKeyNone =>
    Intl.message("Pick a key to hold while you talk",
        name: "pushToTalkKeyNone",
        desc: "Shown when no push to talk key is set");

String get pushToTalkKeyEverywhere =>
    Intl.message("Hold it to talk. Works while you're in another app",
        name: "pushToTalkKeyEverywhere",
        desc: "Shown when the push to talk key works globally");

String get pushToTalkKeyFocusedOnly => Intl.message(
    "Hold it to talk while Vommet is focused",
    name: "pushToTalkKeyFocusedOnly",
    desc:
        "Shown when the push to talk key works only while the app is focused");

String get pushToTalkSetKey => Intl.message("Set key",
    name: "pushToTalkSetKey", desc: "Button that sets the push to talk key");

String get pushToTalkChangeKey => Intl.message("Change",
    name: "pushToTalkChangeKey",
    desc: "Button that changes the push to talk key");

String get pushToTalkFocusedOnlyNote => Intl.message(
    "On this system the key only works while Vommet is focused. You can still hold the talk button in the call.",
    name: "pushToTalkFocusedOnlyNote",
    desc: "Note when global shortcuts are unavailable on this system");

String get pushToTalkPressKey =>
    Intl.message("Press the key to hold while you talk",
        name: "pushToTalkPressKey",
        desc: "Title of the dialog recording the push to talk key");

String get pushToTalkClearKey => Intl.message("Clear Key",
    name: "pushToTalkClearKey",
    desc: "Button that clears the push to talk key");
