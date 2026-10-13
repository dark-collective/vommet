import 'dart:async';

import 'package:commet/client/sounds/app_sounds.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/navigation/navigation_utils.dart';
import 'package:commet/ui/pages/settings/categories/app/double_preference_slider.dart';
import 'package:commet/ui/pages/settings/mobile_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:intl/intl.dart';

/// Vommet: every sound the app plays, grouped, each changeable (AppSounds).
class SoundSettingsPage extends StatefulWidget {
  const SoundSettingsPage({super.key});

  static Future<void> open(BuildContext context) => NavigationUtils.navigateTo(
      context, SettingsSubPage(builder: (_) => const SoundSettingsPage()));

  @override
  State<SoundSettingsPage> createState() => _SoundSettingsPageState();
}

class _SoundSettingsPageState extends State<SoundSettingsPage> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        tiamat.Panel(
          mode: tiamat.TileType.surfaceContainerLow,
          header: soundSettingsHeader,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: tiamat.Text.labelLow(soundSettingsExplain),
              ),
              DoublePreferenceSlider(
                preference: preferences.notificationsVolume,
                min: 0,
                max: 150,
                numDecimals: 0,
                units: "%",
                title: soundSettingsVolume,
                description: PlatformUtils.isAndroid
                    ? soundSettingsVolumeAndroid
                    : soundSettingsVolumeDesktop,
              ),
            ],
          ),
        ),
        for (final group in SoundGroup.values) ...[
          const SizedBox(height: 10),
          tiamat.Panel(
            mode: tiamat.TileType.surfaceContainerLow,
            header: group.label,
            child: Column(
              children: [
                for (final e
                    in SoundEvent.values.where((e) => e.group == group))
                  SoundRow(event: e),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// One sound: its name, the current choice, a preview button; tapping it
/// opens [SoundSheet].
class SoundRow extends StatefulWidget {
  const SoundRow({required this.event, super.key});
  final SoundEvent event;

  @override
  State<SoundRow> createState() => _SoundRowState();
}

class _SoundRowState extends State<SoundRow> {
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _sub = preferences.soundChoices.onChanged.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    final custom = AppSounds.choice(e).mode == SoundMode.custom;
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      title: tiamat.Text.label(e.label),
      subtitle: Row(children: [
        if (custom) ...[
          Icon(Icons.audio_file_outlined, size: 14, color: scheme.primary),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(AppSounds.describe(e),
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: custom ? scheme.primary : scheme.onSurfaceVariant)),
        ),
      ]),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (AppSounds.source(e) != null) SoundPreviewButton(event: e),
        Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
      ]),
      onTap: () => SoundSheet.show(context, e),
    );
  }
}

/// Plays [event]'s current sound; tap again to stop (ringtones are long).
class SoundPreviewButton extends StatefulWidget {
  const SoundPreviewButton({required this.event, this.media, super.key});
  final SoundEvent event;

  /// A specific sound to play instead of the current choice.
  final Media? media;

  @override
  State<SoundPreviewButton> createState() => _SoundPreviewButtonState();
}

class _SoundPreviewButtonState extends State<SoundPreviewButton> {
  static Player? _player;
  static _SoundPreviewButtonState? _playing;
  StreamSubscription? _completed;

  bool get playing => _playing == this;

  @override
  void dispose() {
    if (playing) _stop();
    super.dispose();
  }

  void _stop() {
    _completed?.cancel();
    _player?.stop();
    final was = _playing;
    _playing = null;
    if (was != null && was.mounted) was.setState(() {});
  }

  Future<void> _toggle() async {
    if (playing) {
      _stop();
      return;
    }
    final sound = widget.media ?? AppSounds.media(widget.event);
    if (sound == null) return;
    _playing?._stop();
    try {
      _player ??= Player(configuration: PlayerConfiguration());
      _player!.setVolume(preferences.notificationsVolume.value);
      await _player!.setPlaylistMode(PlaylistMode.none);
      await _player!.open(sound);
      _playing = this;
      _completed = _player!.stream.completed.listen((done) {
        if (done && playing) _stop();
      });
      if (mounted) setState(() {});
    } catch (e, s) {
      Log.onError(e, s);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(playing ? Icons.stop_rounded : Icons.play_arrow_rounded),
      tooltip: playing ? soundSettingsStop : soundSettingsPreview,
      onPressed: _toggle,
    );
  }
}

/// The choices for one sound: its default (if it has one), none, your file,
/// or a new file.
class SoundSheet extends StatefulWidget {
  const SoundSheet({required this.event, super.key});
  final SoundEvent event;

  static Future<void> show(BuildContext context, SoundEvent event) =>
      AdaptiveDialog.show(context,
          title: event.label, builder: (_) => SoundSheet(event: event));

  @override
  State<SoundSheet> createState() => _SoundSheetState();
}

class _SoundSheetState extends State<SoundSheet> {
  bool busy = false;
  String? error;

  SoundEvent get e => widget.event;

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } on UnsupportedError catch (err) {
      error = err.message;
    } catch (err, s) {
      Log.onError(err, s);
      error = soundSettingsFileFailed(err.toString());
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppSounds.choice(e);
    final scheme = Theme.of(context).colorScheme;
    Widget option(String label,
            {required bool selected,
            String? subtitle,
            Widget? trailing,
            VoidCallback? onTap}) =>
        ListTile(
          leading: Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected ? scheme.primary : scheme.outline),
          title: tiamat.Text.label(label),
          subtitle: subtitle == null ? null : tiamat.Text.labelLow(subtitle),
          trailing: trailing,
          onTap: busy ? null : onTap,
        );

    final defaultLabel = e.asset != null
        ? soundSettingsDefault
        : e.sameAs != null
            ? soundSettingsSameAs(e.sameAs!.label.toLowerCase())
            : null;

    return SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: tiamat.Text.labelLow(e.description),
          ),
          if (defaultLabel != null)
            option(defaultLabel,
                selected: c.mode == SoundMode.standard,
                trailing: SoundPreviewButton(
                    event: e, media: AppSounds.defaultMedia(e)),
                onTap: () => _run(() => AppSounds.setDefault(e))),
          option(soundSettingsNone,
              selected: c.mode == SoundMode.none ||
                  (c.mode == SoundMode.standard && defaultLabel == null),
              subtitle: defaultLabel == null ? soundSettingsNoDefault : null,
              onTap: () => _run(() => AppSounds.setNone(e))),
          if (c.mode == SoundMode.custom)
            option(c.name ?? soundSettingsYourFile,
                selected: true,
                subtitle: soundSettingsYourFile,
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  SoundPreviewButton(event: e),
                  TextButton(
                      onPressed:
                          busy ? null : () => _run(() => AppSounds.pickFile(e)),
                      child: Text(soundSettingsChange)),
                ])),
          ListTile(
            leading: Icon(Icons.folder_open, color: scheme.primary),
            title: Text(soundSettingsChooseFile,
                style: TextStyle(color: scheme.primary)),
            onTap: busy ? null : () => _run(() => AppSounds.pickFile(e)),
          ),
          if (PlatformUtils.isAndroid && e.isAndroidChannelSound)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline,
                      size: 16, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child:
                        tiamat.Text.labelLow(soundSettingsAndroidChannelNote),
                  ),
                ],
              ),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(error!, style: TextStyle(color: scheme.error)),
            ),
        ],
      ),
    );
  }
}

String get soundSettingsHeader => Intl.message("Sounds",
    name: "soundSettingsHeader", desc: "Header of the Sounds settings panel");

String get soundSettingsExplain => Intl.message(
    "Tap a sound to change it. Pick any audio file to use your own.",
    name: "soundSettingsExplain",
    desc: "Explanation at the top of the Sounds settings");

String get soundSettingsVolume => Intl.message("Volume",
    name: "soundSettingsVolume", desc: "Title of the sound volume slider");

String get soundSettingsVolumeAndroid => Intl.message(
    "For sounds in calls. Notification sounds follow your phone's volume.",
    name: "soundSettingsVolumeAndroid",
    desc: "Description of the sound volume slider on Android");

String get soundSettingsVolumeDesktop =>
    Intl.message("For notifications, ringtones and call sounds",
        name: "soundSettingsVolumeDesktop",
        desc: "Description of the sound volume slider on other systems");

String get soundSettingsStop => Intl.message("Stop",
    name: "soundSettingsStop",
    desc: "Tooltip of the button that stops a sound preview");

String get soundSettingsPreview => Intl.message("Preview",
    name: "soundSettingsPreview",
    desc: "Tooltip of the button that plays a sound preview");

String soundSettingsFileFailed(String error) => Intl.message(
    "Couldn't use that file: $error",
    args: [error],
    name: "soundSettingsFileFailed",
    desc:
        "Error when a picked sound file cannot be used; error is the technical error text");

String get soundSettingsDefault => Intl.message("Default",
    name: "soundSettingsDefault", desc: "Sound option: the default sound");

String soundSettingsSameAs(String sound) => Intl.message("Same as $sound",
    args: [sound],
    name: "soundSettingsSameAs",
    desc:
        "Sound option: use the same sound as another event; sound is that event's name in lower case");

String get soundSettingsNone => Intl.message("None",
    name: "soundSettingsNone", desc: "Sound option: no sound");

String get soundSettingsNoDefault =>
    Intl.message("Vommet has no sound for this yet",
        name: "soundSettingsNoDefault",
        desc: "Subtitle of the None option when there is no default sound");

String get soundSettingsYourFile => Intl.message("Your file",
    name: "soundSettingsYourFile", desc: "Label of a custom sound file option");

String get soundSettingsChange => Intl.message("Change",
    name: "soundSettingsChange",
    desc: "Button that picks a different custom sound file");

String get soundSettingsChooseFile => Intl.message("Choose a file…",
    name: "soundSettingsChooseFile",
    desc: "Row that picks a custom sound file");

String get soundSettingsAndroidChannelNote => Intl.message(
    "Changing this sound resets the vibration and Do Not Disturb settings you made for it in Android's settings.",
    name: "soundSettingsAndroidChannelNote",
    desc: "Android note shown when changing a notification sound");
