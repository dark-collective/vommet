import 'package:commet/client/components/voip/share_quality.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/config/layout_style.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/call_data_saver.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class ShareQualityStrings {
  static String get shareQualityTitle => Intl.message("Share your screen",
      name: "shareQualityTitle",
      desc:
          "Title of the step before going live that picks the screen share's quality");

  static String get shareQualityHeading => Intl.message("Quality",
      name: "shareQualityHeading",
      desc: "Screen share quality: heading over the size choices");

  static String get shareQualityAuto => Intl.message("Auto (recommended)",
      name: "shareQualityAuto",
      desc:
          "Screen share quality: the choice that uses your settings and lowers the quality by itself when needed");

  static String get shareQualityAutoShort => Intl.message("Auto",
      name: "shareQualityAutoShort",
      desc: "Screen share quality, short form of 'Auto (recommended)'");

  static String get shareQualitySource => Intl.message("Source",
      name: "shareQualitySource",
      desc:
          "Screen share quality: the choice that sends the screen or window at its own size");

  static String get shareQualityFramerate => Intl.message("Frame rate",
      name: "shareQualityFramerate",
      desc: "Screen share quality: heading over the frame rate choices");

  static String shareQualityFps(int fps) => Intl.message("$fps fps",
      name: "shareQualityFps",
      args: [fps],
      desc: "Screen share quality: a frame rate choice, e.g. '30 fps'");

  static String get shareQualityGoLive => Intl.message("Go live",
      name: "shareQualityGoLive",
      desc: "Screen share quality step: button that starts sharing");

  static String get shareQualityCancel => Intl.message("Cancel",
      name: "shareQualityCancel",
      desc: "Screen share picker: button that closes it without sharing");

  static String get shareQualityAdvanced => Intl.message("Advanced",
      name: "shareQualityAdvanced",
      desc:
          "Screen share picker: heading of the section that opens to show the codec, optimize for and simulcast choices");

  static String get shareQualityCodec => Intl.message("Codec",
      name: "shareQualityCodec",
      desc: "Screen share quality: heading over the video codec choices");

  static String get shareQualityCodecNoteH264 => Intl.message(
      "Auto uses H.264, which has hardware encoding on nearly every device.",
      name: "shareQualityCodecNoteH264",
      desc:
          "Screen share quality: line under the codec choices when the codec in Settings is H.264");

  static String shareQualityCodecNote(String codec) => Intl.message(
      "Auto uses $codec, the codec in Settings.",
      name: "shareQualityCodecNote",
      args: [codec],
      desc:
          "Screen share quality: line under the codec choices, e.g. 'Auto uses VP9, the codec in Settings.'");

  static String get shareQualityOptimize => Intl.message("Optimize for",
      name: "shareQualityOptimize",
      desc:
          "Screen share quality: heading over the choice of keeping the frame rate or the sharpness when the connection is slow");

  static String get shareQualitySmooth => Intl.message("Smooth motion",
      name: "shareQualitySmooth",
      desc:
          "Screen share quality, optimize for: keep the frame rate (games, video)");

  static String get shareQualitySharp => Intl.message("Sharp text",
      name: "shareQualitySharp",
      desc:
          "Screen share quality, optimize for: keep the resolution (text, code, slides)");

  static String get shareQualitySimulcast => Intl.message("Simulcast",
      name: "shareQualitySimulcast",
      desc:
          "Screen share quality: switch that also sends a smaller copy of the stream");

  static String get shareQualitySimulcastHint => Intl.message(
      "Also sends a smaller copy, so slow viewers stay smooth. Uses more of your CPU and upload.",
      name: "shareQualitySimulcastHint",
      desc: "Screen share quality: line under the Simulcast switch");

  static String shareQualityBitrateHint(String size, int fps, String mbps) =>
      Intl.message(
          "$size at $fps fps sends up to $mbps Mbps. Higher quality needs more upload.",
          name: "shareQualityBitrateHint",
          args: [size, fps, mbps],
          desc:
              "Screen share quality: hint under the choices, e.g. '1080p at 60 fps sends up to 9 Mbps. Higher quality needs more upload.'");

  static String get shareQualityDataSaver => Intl.message(
      "Use less data for calls is on, so your stream is 720p at most.",
      name: "shareQualityDataSaver",
      desc:
          "Screen share quality: line shown while the data saver limits the stream, which disables the bigger sizes");

  static String get shareQualitySystemNext => Intl.message(
      "Next, your system asks which screen or window to share.",
      name: "shareQualitySystemNext",
      desc:
          "Screen share quality step, where the system picks the source: line under the title");

  static String get streamSettingsTitle => Intl.message("Stream settings",
      name: "streamSettingsTitle",
      desc:
          "Title of the menu that changes your screen share's quality while you're live");

  static String get streamSettingsRestartNote =>
      Intl.message("Codec or simulcast changes restart the stream briefly.",
          name: "streamSettingsRestartNote",
          desc: "Stream settings while live: note under the choices");

  static String get streamSettingsNextShareNote => Intl.message(
      "Codec and simulcast changes apply to your next stream here.",
      name: "streamSettingsNextShareNote",
      desc:
          "Stream settings while live, where the stream can't restart without asking the system again: note under the choices");

  static String get streamSettingsTooltip => Intl.message("Stream settings",
      name: "streamSettingsTooltip",
      desc:
          "Tooltip on the gear that opens your screen share's quality settings while you're live");

  static String describeCurrent() =>
      ShareQuality.describe(ShareQuality.resolution, ShareQuality.framerate,
          auto: shareQualityAutoShort, source: shareQualitySource);

  static String sizeLabel(ShareResolution r, {bool long = false}) =>
      ShareQuality.sizeLabel(r,
          auto: long ? shareQualityAuto : shareQualityAutoShort,
          source: shareQualitySource);

  static String codecLabel(ShareCodec c) => c == ShareCodec.auto
      ? shareQualityAutoShort
      : ShareQuality.codecLabel(c.name);

  static String optimizeLabel(ShareOptimize o) => switch (o) {
        ShareOptimize.smooth => shareQualitySmooth,
        ShareOptimize.text => shareQualitySharp
      };

  static String get codecNote => ShareQuality.settingsCodec == "h264"
      ? shareQualityCodecNoteH264
      : shareQualityCodecNote(
          ShareQuality.codecLabel(ShareQuality.settingsCodec));

  static String bitrateHint(ShareResolution r, double fps) {
    final sent = ShareQuality.sent(r, fps);
    final shown =
        CallDataSaver.isActive && r.aboveDataSaver ? ShareResolution.p720 : r;
    return shareQualityBitrateHint(sizeLabel(shown), sent.framerate.round(),
        ShareQuality.mbps(sent.bitrate));
  }
}

/// Vommet: the choices of one share, before they're applied: the picker
/// starts from the last ones (simulcast from Settings) and applies them on
/// Go live.
class ShareQualityDraft {
  ShareResolution resolution;
  double framerate;
  ShareCodec codec;
  ShareOptimize optimize;
  bool simulcast;

  ShareQualityDraft.current()
      : resolution = ShareQuality.resolution,
        framerate = ShareQuality.framerateChoice,
        codec = ShareQuality.codec,
        optimize = ShareQuality.optimize,
        simulcast = preferences.shareSimulcast.value;

  /// The share about to start uses these; simulcast only for it.
  Future<void> apply() async {
    await ShareQuality.save(resolution, framerate,
        codec: codec, optimize: optimize);
    ShareQuality.simulcast = simulcast;
  }
}

Widget _heading(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: .5,
            color: Theme.of(context).colorScheme.onSurfaceVariant)));

Widget _chip(String label, bool selected, VoidCallback? onTap) => ChoiceChip(
    label: Text(label),
    selected: selected,
    showCheckmark: true,
    onSelected: onTap == null ? null : (_) => onTap());

Widget _note(BuildContext context, String text, {IconData? icon}) {
  final color = Theme.of(context).colorScheme.onSurfaceVariant;
  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    if (icon != null) ...[
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 8)
    ],
    Expanded(
        child: Text(text,
            style:
                Theme.of(context).textTheme.bodySmall?.copyWith(color: color)))
  ]);
}

Widget _sizeChips(ShareResolution selected, bool long,
        void Function(ShareResolution) onTap) =>
    Wrap(spacing: 8, runSpacing: 8, children: [
      for (final r in ShareResolution.values)
        _chip(ShareQualityStrings.sizeLabel(r, long: long), r == selected,
            CallDataSaver.isActive && r.aboveDataSaver ? null : () => onTap(r))
    ]);

Widget _fpsChips(double selected, void Function(double) onTap) =>
    Wrap(spacing: 8, runSpacing: 8, children: [
      for (final fps in ShareQuality.framerates)
        _chip(ShareQualityStrings.shareQualityFps(fps.round()), fps == selected,
            () => onTap(fps))
    ]);

Widget _codecChips(ShareCodec selected, void Function(ShareCodec)? onTap) =>
    Wrap(spacing: 8, runSpacing: 8, children: [
      for (final c in ShareCodec.values)
        _chip(ShareQualityStrings.codecLabel(c), c == selected,
            onTap == null ? null : () => onTap(c))
    ]);

Widget _optimizeChips(
        ShareOptimize selected, void Function(ShareOptimize) onTap) =>
    Wrap(spacing: 8, runSpacing: 8, children: [
      for (final o in ShareOptimize.values)
        _chip(
            ShareQualityStrings.optimizeLabel(o), o == selected, () => onTap(o))
    ]);

/// Vommet: the quality part of the Go live step (Layout A): Quality, Frame
/// rate, a collapsible Advanced (codec, optimize for, simulcast; remembers
/// whether it's open) and what it sends. Changes [draft] in place.
class ShareQualitySection extends StatefulWidget {
  const ShareQualitySection({required this.draft, this.onChanged, super.key});

  final ShareQualityDraft draft;
  final VoidCallback? onChanged;

  @override
  State<ShareQualitySection> createState() => _ShareQualitySectionState();
}

class _ShareQualitySectionState extends State<ShareQualitySection> {
  bool advanced = ShareQuality.advancedOpen.value;

  void change(void Function(ShareQualityDraft d) edit) {
    setState(() => edit(widget.draft));
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.draft;
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<bool>(
        valueListenable: CallDataSaver.active,
        builder: (context, saver, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _heading(context, ShareQualityStrings.shareQualityHeading),
                  _sizeChips(d.resolution, true,
                      (r) => change((d) => d.resolution = r)),
                  if (saver) ...[
                    const SizedBox(height: 8),
                    _note(context, ShareQualityStrings.shareQualityDataSaver,
                        icon: Icons.data_saver_on_rounded)
                  ],
                  const SizedBox(height: 16),
                  _heading(context, ShareQualityStrings.shareQualityFramerate),
                  _fpsChips(d.framerate, (f) => change((d) => d.framerate = f)),
                  const SizedBox(height: 12),
                  InkWell(
                      mouseCursor: WidgetStateMouseCursor.clickable,
                      borderRadius: BorderRadius.circular(6),
                      onTap: () {
                        setState(() => advanced = !advanced);
                        ShareQuality.advancedOpen.set(advanced);
                      },
                      child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(children: [
                            Text(
                                ShareQualityStrings.shareQualityAdvanced
                                    .toUpperCase(),
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: .5,
                                        color: scheme.onSurfaceVariant)),
                            const SizedBox(width: 4),
                            Icon(
                                advanced
                                    ? Icons.expand_less_rounded
                                    : Icons.expand_more_rounded,
                                size: 18,
                                color: scheme.onSurfaceVariant)
                          ]))),
                  AnimatedSize(
                      duration: const Duration(milliseconds: 150),
                      alignment: Alignment.topCenter,
                      child: !advanced
                          ? const SizedBox(width: double.infinity)
                          : Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _heading(context,
                                        ShareQualityStrings.shareQualityCodec),
                                    _codecChips(d.codec,
                                        (c) => change((d) => d.codec = c)),
                                    const SizedBox(height: 6),
                                    _note(
                                        context, ShareQualityStrings.codecNote),
                                    const SizedBox(height: 16),
                                    _heading(
                                        context,
                                        ShareQualityStrings
                                            .shareQualityOptimize),
                                    _optimizeChips(d.optimize,
                                        (o) => change((d) => d.optimize = o)),
                                    const SizedBox(height: 12),
                                    _SimulcastRow(
                                        value: d.simulcast,
                                        onChanged: (v) =>
                                            change((d) => d.simulcast = v))
                                  ]))),
                  const SizedBox(height: 12),
                  _note(
                      context,
                      ShareQualityStrings.bitrateHint(
                          d.resolution, d.framerate),
                      icon: Icons.info_outline)
                ]));
  }
}

class _SimulcastRow extends StatelessWidget {
  const _SimulcastRow({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(ShareQualityStrings.shareQualitySimulcast,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        _note(context, ShareQualityStrings.shareQualitySimulcastHint)
      ])),
      const SizedBox(width: 12),
      Switch(value: value, onChanged: onChanged)
    ]);
  }
}

/// Cancel and Go live, under the Go live step.
class ShareQualityButtons extends StatelessWidget {
  const ShareQualityButtons({required this.onGoLive, super.key});

  /// Null while there's nothing to share yet.
  final VoidCallback? onGoLive;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisAlignment: MainAxisAlignment.end, children: [
      TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(ShareQualityStrings.shareQualityCancel)),
      const SizedBox(width: 8),
      FilledButton.icon(
          icon: const Icon(Icons.screen_share_rounded, size: 18),
          label: Text(ShareQualityStrings.shareQualityGoLive),
          onPressed: onGoLive)
    ]);
  }
}

/// Vommet: the Go live step alone, where the system picks the source
/// (Wayland portal, browsers, Android): the quality, then the system's own
/// prompt. A bottom sheet on phones. Whether to go on (the choices are
/// applied then).
class ShareQualityPrompt extends StatefulWidget {
  const ShareQualityPrompt({this.sheet = false, super.key});

  final bool sheet;

  static Future<bool> show(BuildContext context) async {
    if (!context.mounted) return false;
    final bool? result;
    if (PlatformUtils.isAndroid ||
        MediaQuery.of(context).layout == LayoutType.mobile) {
      result = await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (context) => const ShareQualityPrompt(sheet: true));
    } else {
      result = await tiamat.PopupDialog.show<bool>(context,
          title: ShareQualityStrings.shareQualityTitle,
          content: const ShareQualityPrompt());
    }
    return result == true;
  }

  @override
  State<ShareQualityPrompt> createState() => _ShareQualityPromptState();
}

class _ShareQualityPromptState extends State<ShareQualityPrompt> {
  final draft = ShareQualityDraft.current();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.sheet) ...[
            Text(ShareQualityStrings.shareQualityTitle,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4)
          ],
          Text(ShareQualityStrings.shareQualitySystemNext,
              style: TextStyle(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          ShareQualitySection(draft: draft),
          const SizedBox(height: 16),
          ShareQualityButtons(onGoLive: () async {
            await draft.apply();
            if (context.mounted) Navigator.of(context).pop(true);
          })
        ]);
    if (widget.sheet) {
      return SafeArea(
          child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16), child: body));
    }
    return SizedBox(
        width: 520,
        child: SingleChildScrollView(
            padding: const EdgeInsets.all(8), child: body));
  }
}

/// Vommet: what the stream menu changes, live. Size, frame rate and
/// optimize-for apply to the running share; codec and simulcast restart it
/// (where it can restart without the system's prompt).
class _LiveShare {
  _LiveShare(this.session);

  final VoipSession session;

  ShareQualityTarget? get target =>
      session is ShareQualityTarget ? session as ShareQualityTarget : null;

  bool get canRestart => target?.canRestartShare ?? false;

  Future<void> quality(
      {ShareResolution? resolution,
      double? framerate,
      ShareOptimize? optimize}) async {
    await ShareQuality.save(resolution ?? ShareQuality.resolution,
        framerate ?? ShareQuality.framerate,
        optimize: optimize);
    try {
      await target?.applyShareQuality();
    } catch (e, s) {
      Log.onError(e, s, content: "Couldn't apply the stream settings");
    }
  }

  Future<void> restart({ShareCodec? codec, bool? simulcast}) async {
    if (!canRestart) return;
    if (codec != null) await ShareQuality.codecPreference.set(codec.name);
    if (simulcast != null) ShareQuality.simulcast = simulcast;
    try {
      await target?.restartShare();
    } catch (e, s) {
      Log.onError(e, s, content: "Couldn't restart the stream");
    }
  }
}

/// Vommet: stream settings while live as rows that open into choices: the
/// Telegram-style sheet, and the bottom sheet on phones.
class StreamSettingsSheet extends StatefulWidget {
  const StreamSettingsSheet(
      {required this.session, this.showTitle = false, super.key});

  final VoipSession session;
  final bool showTitle;

  static Future<void> show(BuildContext context, VoipSession session) {
    if (PlatformUtils.isAndroid ||
        MediaQuery.of(context).layout == LayoutType.mobile) {
      return showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (context) => SafeArea(
              child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                  child:
                      StreamSettingsSheet(session: session, showTitle: true))));
    }
    return tiamat.PopupDialog.show<void>(context,
        title: ShareQualityStrings.streamSettingsTitle,
        content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
                child: StreamSettingsSheet(session: session))));
  }

  @override
  State<StreamSettingsSheet> createState() => _StreamSettingsSheetState();
}

enum _Row { quality, framerate, codec, optimize }

class _StreamSettingsSheetState extends State<StreamSettingsSheet> {
  late final live = _LiveShare(widget.session);
  _Row? open;

  Future<void> run(Future<void> Function() change) async {
    setState(() => open = null);
    await change();
    if (mounted) setState(() {});
  }

  Widget row(_Row id, String label, String value, Widget choices,
      {bool enabled = true}) {
    final scheme = Theme.of(context).colorScheme;
    final expanded = open == id;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(
          enabled: enabled,
          title: Text(label),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(value, style: TextStyle(color: scheme.onSurfaceVariant)),
            Icon(expanded ? Icons.expand_less_rounded : Icons.chevron_right)
          ]),
          onTap: () => setState(() => open = expanded ? null : id)),
      if (expanded && enabled)
        Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Align(alignment: Alignment.centerLeft, child: choices))
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final canRestart = live.canRestart;
    return ValueListenableBuilder<bool>(
        valueListenable: CallDataSaver.active,
        builder: (context, _, __) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.showTitle)
                    Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Text(ShareQualityStrings.streamSettingsTitle,
                            style: Theme.of(context).textTheme.titleLarge)),
                  row(
                      _Row.quality,
                      ShareQualityStrings.shareQualityHeading,
                      ShareQualityStrings.sizeLabel(ShareQuality.resolution),
                      _sizeChips(ShareQuality.resolution, false,
                          (r) => run(() => live.quality(resolution: r)))),
                  row(
                      _Row.framerate,
                      ShareQualityStrings.shareQualityFramerate,
                      ShareQualityStrings.shareQualityFps(
                          ShareQuality.framerate.round()),
                      _fpsChips(ShareQuality.framerateChoice,
                          (f) => run(() => live.quality(framerate: f)))),
                  row(
                      _Row.codec,
                      ShareQualityStrings.shareQualityCodec,
                      ShareQualityStrings.codecLabel(ShareQuality.codec),
                      _codecChips(ShareQuality.codec,
                          (c) => run(() => live.restart(codec: c))),
                      enabled: canRestart),
                  row(
                      _Row.optimize,
                      ShareQualityStrings.shareQualityOptimize,
                      ShareQualityStrings.optimizeLabel(ShareQuality.optimize),
                      _optimizeChips(ShareQuality.optimize,
                          (o) => run(() => live.quality(optimize: o)))),
                  SwitchListTile(
                      title: Text(ShareQualityStrings.shareQualitySimulcast),
                      subtitle:
                          Text(ShareQualityStrings.shareQualitySimulcastHint),
                      value: ShareQuality.simulcast,
                      onChanged: canRestart
                          ? (v) => run(() => live.restart(simulcast: v))
                          : null),
                  Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: _note(
                          context,
                          canRestart
                              ? ShareQualityStrings.streamSettingsRestartNote
                              : ShareQualityStrings.streamSettingsNextShareNote,
                          icon: Icons.info_outline)),
                  Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                      child: _note(
                          context,
                          ShareQualityStrings.bitrateHint(
                              ShareQuality.resolution, ShareQuality.framerate)))
                ]));
  }
}

/// The gear that opens the stream settings while you share your screen:
/// a Discord-style popover menu on desktop (Discord and Custom layout
/// styles), the Telegram-style sheet in Telegram style, a bottom sheet on
/// phones.
class StreamSettingsButton extends StatefulWidget {
  const StreamSettingsButton(
      {required this.session, this.size = 18, this.dark = true, super.key});

  final VoipSession session;
  final double size;

  /// Drawn over a video (a dark chip), not on a panel.
  final bool dark;

  @override
  State<StreamSettingsButton> createState() => _StreamSettingsButtonState();
}

class _StreamSettingsButtonState extends State<StreamSettingsButton> {
  late final live = _LiveShare(widget.session);

  /// Runs a change picked in the popover, then shows it on the next open.
  void change(Future<void> Function() edit) async {
    await edit();
    if (mounted) setState(() {});
  }

  bool _sheet(BuildContext context) =>
      PlatformUtils.isAndroid ||
      MediaQuery.of(context).layout == LayoutType.mobile ||
      currentLayoutStyle == LayoutStyle.telegram;

  Widget _gear(VoidCallback onTap) => Tooltip(
      message: ShareQualityStrings.streamSettingsTooltip,
      child: Material(
          color: widget.dark
              ? Colors.black.withValues(alpha: .6)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
              mouseCursor: WidgetStateMouseCursor.clickable,
              borderRadius: BorderRadius.circular(6),
              onTap: onTap,
              child: Padding(
                  padding: const EdgeInsets.all(5),
                  child: Icon(Icons.settings_rounded,
                      size: widget.size,
                      color: widget.dark ? Colors.white : null)))));

  @override
  Widget build(BuildContext context) {
    if (_sheet(context)) {
      return _gear(() => StreamSettingsSheet.show(context, widget.session));
    }
    return MenuAnchor(
        menuChildren: _menu(context),
        builder: (context, controller, _) => _gear(
            () => controller.isOpen ? controller.close() : controller.open()));
  }

  Widget _check(bool on) => SizedBox(
      width: 20, child: on ? const Icon(Icons.check_rounded, size: 18) : null);

  Widget _submenu(
      BuildContext context, String label, String value, List<Widget> children) {
    final scheme = Theme.of(context).colorScheme;
    return SubmenuButton(
        menuChildren: children,
        child: SizedBox(
            width: 220,
            child: Row(children: [
              Expanded(child: Text(label)),
              Text(value, style: TextStyle(color: scheme.onSurfaceVariant))
            ])));
  }

  /// The popover's rows; built each time it opens.
  List<Widget> _menu(BuildContext context) {
    final canRestart = live.canRestart;
    final saver = CallDataSaver.isActive;
    return [
      Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Text(ShareQualityStrings.streamSettingsTitle,
              style: const TextStyle(fontWeight: FontWeight.w700))),
      _submenu(context, ShareQualityStrings.shareQualityHeading,
          ShareQualityStrings.sizeLabel(ShareQuality.resolution), [
        for (final r in ShareResolution.values)
          MenuItemButton(
              leadingIcon: _check(r == ShareQuality.resolution),
              onPressed: saver && r.aboveDataSaver
                  ? null
                  : () => change(() => live.quality(resolution: r)),
              child: Text(ShareQualityStrings.sizeLabel(r, long: true)))
      ]),
      _submenu(context, ShareQualityStrings.shareQualityFramerate,
          ShareQualityStrings.shareQualityFps(ShareQuality.framerate.round()), [
        for (final fps in ShareQuality.framerates)
          MenuItemButton(
              leadingIcon: _check(fps == ShareQuality.framerateChoice),
              onPressed: () => change(() => live.quality(framerate: fps)),
              child: Text(ShareQualityStrings.shareQualityFps(fps.round())))
      ]),
      _submenu(context, ShareQualityStrings.shareQualityCodec,
          ShareQualityStrings.codecLabel(ShareQuality.codec), [
        for (final c in ShareCodec.values)
          MenuItemButton(
              leadingIcon: _check(c == ShareQuality.codec),
              onPressed: canRestart
                  ? () => change(() => live.restart(codec: c))
                  : null,
              child: Text(ShareQualityStrings.codecLabel(c)))
      ]),
      _submenu(context, ShareQualityStrings.shareQualityOptimize,
          ShareQualityStrings.optimizeLabel(ShareQuality.optimize), [
        for (final o in ShareOptimize.values)
          MenuItemButton(
              leadingIcon: _check(o == ShareQuality.optimize),
              onPressed: () => change(() => live.quality(optimize: o)),
              child: Text(ShareQualityStrings.optimizeLabel(o)))
      ]),
      CheckboxMenuButton(
          value: ShareQuality.simulcast,
          onChanged: canRestart
              ? (v) => change(
                  () => live.restart(simulcast: v ?? !ShareQuality.simulcast))
              : null,
          child: Text(ShareQualityStrings.shareQualitySimulcast)),
      const Divider(height: 8),
      Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: SizedBox(
              width: 260,
              child: Text(
                  canRestart
                      ? ShareQualityStrings.streamSettingsRestartNote
                      : ShareQualityStrings.streamSettingsNextShareNote,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant))))
    ];
  }
}
