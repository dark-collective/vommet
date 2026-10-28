import 'dart:typed_data';

import 'package:commet/client/components/voip/share_quality.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/debug/log.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: what the Go live step ended with.
enum ShareQualityStepResult { goLive, back }

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

  static String get shareQualityHint => Intl.message(
      "Higher quality uses more upload bandwidth. Auto lowers the quality by itself when your connection can't keep up.",
      name: "shareQualityHint",
      desc: "Screen share quality: hint under the choices");

  static String get shareQualityEveryTime => Intl.message(
      "Show this every time",
      name: "shareQualityEveryTime",
      desc:
          "Screen share quality step: checkbox that shows the step each time you share (otherwise the choice is remembered)");

  static String get shareQualityChangeSource => Intl.message("Change source",
      name: "shareQualityChangeSource",
      desc:
          "Screen share quality: link that goes back to choosing which screen or window to share");

  static String get shareQualityBack => Intl.message("Back",
      name: "shareQualityBack",
      desc: "Screen share quality step: button that goes back to the sources");

  static String get shareQualityGoLive => Intl.message("Go live",
      name: "shareQualityGoLive",
      desc: "Screen share quality step: button that starts sharing");

  static String get shareQualityWindow => Intl.message("Window",
      name: "shareQualityWindow",
      desc: "Screen share quality step: under the name of a shared window");

  static String get shareQualityScreen => Intl.message("Screen",
      name: "shareQualityScreen",
      desc: "Screen share quality step: under the name of a shared screen");

  static String get streamSettingsTitle => Intl.message("Stream settings",
      name: "streamSettingsTitle",
      desc:
          "Title of the dialog that changes your screen share's quality while you're live");

  static String get streamSettingsSubtitle =>
      Intl.message("Changes apply right away; viewers keep watching.",
          name: "streamSettingsSubtitle",
          desc: "Stream settings dialog: line under the title");

  static String get streamSettingsTooltip => Intl.message("Stream settings",
      name: "streamSettingsTooltip",
      desc:
          "Tooltip on the gear that opens your screen share's quality settings while you're live");

  static String describeCurrent() =>
      ShareQuality.describe(ShareQuality.resolution, ShareQuality.framerate,
          auto: shareQualityAutoShort, source: shareQualitySource);
}

/// The Quality and Frame rate choices, with the bandwidth hint.
class ShareQualityChoices extends StatelessWidget {
  const ShareQualityChoices(
      {required this.resolution,
      required this.framerate,
      required this.onChanged,
      super.key});

  final ShareResolution resolution;
  final double framerate;
  final void Function(ShareResolution resolution, double framerate) onChanged;

  String _label(ShareResolution r) => switch (r) {
        ShareResolution.auto => ShareQualityStrings.shareQualityAuto,
        ShareResolution.p720 => "720p",
        ShareResolution.p1080 => "1080p",
        ShareResolution.source => ShareQualityStrings.shareQualitySource,
      };

  Widget _heading(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text.toUpperCase(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: .5,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );

  Widget _chip(BuildContext context, String label, bool selected,
          VoidCallback onTap) =>
      ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: true,
        onSelected: (_) => onTap(),
      );

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _heading(context, ShareQualityStrings.shareQualityHeading),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final r in ShareResolution.values)
          _chip(context, _label(r), r == resolution,
              () => onChanged(r, framerate)),
      ]),
      const SizedBox(height: 16),
      _heading(context, ShareQualityStrings.shareQualityFramerate),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final fps in ShareQuality.framerates)
          _chip(context, ShareQualityStrings.shareQualityFps(fps.round()),
              fps == framerate, () => onChanged(resolution, fps)),
      ]),
      const SizedBox(height: 12),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline,
            size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
            child: Text(ShareQualityStrings.shareQualityHint,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant))),
      ]),
    ]);
  }
}

/// The Go live step after picking a screen or window: what you share
/// (with Change source), the quality, "Show this every time", Back and
/// Go live. Pops a [ShareQualityStepResult]; nothing when dismissed.
class ShareQualityStep extends StatefulWidget {
  const ShareQualityStep(
      {required this.sourceName,
      this.isWindow = false,
      this.thumbnail,
      super.key});

  final String sourceName;
  final bool isWindow;
  final Uint8List? thumbnail;

  static Future<ShareQualityStepResult?> show(BuildContext context,
      {required String sourceName,
      bool isWindow = false,
      Uint8List? thumbnail}) {
    return tiamat.PopupDialog.show<ShareQualityStepResult>(context,
        title: ShareQualityStrings.shareQualityTitle,
        content: ShareQualityStep(
            sourceName: sourceName, isWindow: isWindow, thumbnail: thumbnail));
  }

  @override
  State<ShareQualityStep> createState() => _ShareQualityStepState();
}

class _ShareQualityStepState extends State<ShareQualityStep> {
  ShareResolution resolution = ShareQuality.resolution;
  double framerate = ShareQuality.framerate;
  bool everyTime = ShareQuality.askEveryTime.value;

  @override
  void initState() {
    super.initState();
    // A frame rate from Settings that isn't one of the choices: the nearest.
    if (!ShareQuality.framerates.contains(framerate)) {
      framerate = ShareQuality.framerates.reduce(
          (a, b) => (a - framerate).abs() <= (b - framerate).abs() ? a : b);
    }
  }

  void pop(ShareQualityStepResult result) =>
      Navigator.of(context).pop<ShareQualityStepResult>(result);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 560,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                Container(
                  width: 128,
                  height: 72,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(6)),
                  child: widget.thumbnail == null || widget.thumbnail!.isEmpty
                      ? Icon(
                          widget.isWindow
                              ? Icons.web_asset_rounded
                              : Icons.desktop_windows_rounded,
                          color: Colors.white54)
                      : Image.memory(widget.thumbnail!,
                          fit: BoxFit.cover, gaplessPlayback: true),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.sourceName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 15)),
                        Text(
                            widget.isWindow
                                ? ShareQualityStrings.shareQualityWindow
                                : ShareQualityStrings.shareQualityScreen,
                            style: TextStyle(color: scheme.onSurfaceVariant)),
                        const SizedBox(height: 4),
                        InkWell(
                          mouseCursor: WidgetStateMouseCursor.clickable,
                          onTap: () => pop(ShareQualityStepResult.back),
                          child: Text(
                              ShareQualityStrings.shareQualityChangeSource,
                              style: TextStyle(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ]),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            ShareQualityChoices(
              resolution: resolution,
              framerate: framerate,
              onChanged: (r, f) => setState(() {
                resolution = r;
                framerate = f;
              }),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              value: everyTime,
              onChanged: (v) => setState(() => everyTime = v ?? false),
              title: Text(ShareQualityStrings.shareQualityEveryTime),
            ),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(
                  onPressed: () => pop(ShareQualityStepResult.back),
                  child: Text(ShareQualityStrings.shareQualityBack)),
              const SizedBox(width: 8),
              FilledButton.icon(
                icon: const Icon(Icons.screen_share_rounded, size: 18),
                label: Text(ShareQualityStrings.shareQualityGoLive),
                onPressed: () async {
                  await ShareQuality.save(resolution, framerate,
                      everyTime: everyTime);
                  if (mounted) pop(ShareQualityStepResult.goLive);
                },
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

/// Stream settings while you're live (the gear on your stream, and on the
/// Voice connected panel): the same choices, applied right away.
class StreamSettingsDialog extends StatefulWidget {
  const StreamSettingsDialog({required this.session, super.key});

  final VoipSession session;

  static Future<void> show(BuildContext context, VoipSession session) =>
      tiamat.PopupDialog.show(context,
          title: ShareQualityStrings.streamSettingsTitle,
          content: StreamSettingsDialog(session: session));

  @override
  State<StreamSettingsDialog> createState() => _StreamSettingsDialogState();
}

class _StreamSettingsDialogState extends State<StreamSettingsDialog> {
  ShareResolution resolution = ShareQuality.resolution;
  double framerate = ShareQuality.framerate;

  Future<void> change(ShareResolution r, double f) async {
    setState(() {
      resolution = r;
      framerate = f;
    });
    await ShareQuality.save(r, f);
    final session = widget.session;
    if (session is ShareQualityTarget) {
      try {
        await (session as ShareQualityTarget).applyShareQuality();
      } catch (e, s) {
        Log.onError(e, s, content: "Couldn't apply the stream settings");
      }
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 460,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(ShareQualityStrings.streamSettingsSubtitle,
                style: TextStyle(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            ShareQualityChoices(
                resolution: resolution,
                framerate: ShareQuality.framerates.contains(framerate)
                    ? framerate
                    : -1,
                onChanged: change),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: Text(ShareQualityStrings.describeCurrent(),
                  style:
                      TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}

/// The gear that opens [StreamSettingsDialog] while you share your screen.
class StreamSettingsButton extends StatelessWidget {
  const StreamSettingsButton(
      {required this.session, this.size = 18, this.dark = true, super.key});

  final VoipSession session;
  final double size;

  /// Drawn over a video (a dark chip), not on a panel.
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: ShareQualityStrings.streamSettingsTooltip,
      child: Material(
        color: dark ? Colors.black.withValues(alpha: .6) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          borderRadius: BorderRadius.circular(6),
          onTap: () => StreamSettingsDialog.show(context, session),
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Icon(Icons.settings_rounded,
                size: size, color: dark ? Colors.white : null),
          ),
        ),
      ),
    );
  }
}
