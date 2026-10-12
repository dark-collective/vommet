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
      header: "Input Mode",
      mode: tiamat.TileType.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          _mode(context, "Voice activity",
              "Your microphone sends whenever you talk", false, on),
          _mode(
              context,
              "Push to talk",
              _desktop
                  ? "Your microphone only sends while you hold a key or the talk button"
                  : "Your microphone only sends while you hold the talk button in the call",
              true,
              on),
          if (on) ...[
            if (_desktop) _key(context),
            DoublePreferenceSlider(
              preference: preferences.voipPushToTalkReleaseDelay,
              title: "Release delay",
              description:
                  "Keeps sending a moment after you let go, so the end of a word isn't cut off",
              min: 0,
              max: 2,
              divisions: 40,
              formatValue: (v) => "${v.toStringAsFixed(2)} s",
            ),
            BooleanPreferenceToggle(
              preference: preferences.voipPushToTalkSounds,
              title: "Talk sounds",
              description: "A soft click when you start and stop talking",
            ),
            _note(context, Icons.mic_none,
                "While push to talk is on, your microphone stays open for the whole call, so the start of each sentence isn't clipped. Your system's \"microphone in use\" light stays on until you leave."),
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
                    tiamat.Text("Push to talk key"),
                    tiamat.Text.labelLow(hotkey == null
                        ? "Pick a key to hold while you talk"
                        : everywhere
                            ? "Hold it to talk. Works while you're in another app"
                            : "Hold it to talk while Vommet is focused"),
                  ])),
              if (hotkey != null) HotKeyVirtualView(hotKey: hotkey),
              tiamat.Button.secondary(
                  text: hotkey == null ? "Set key" : "Change",
                  onTap: () => _pickKey(context)),
            ]),
            if (!everywhere)
              _note(context, Icons.info_outline,
                  "On this system the key only works while Vommet is focused. You can still hold the talk button in the call."),
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
          tiamat.Text.largeTitle("Press the key to hold while you talk"),
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
            text: "Clear Key",
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
