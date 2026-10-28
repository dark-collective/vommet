import 'package:commet/main.dart';
import 'package:commet/ui/atoms/selected_segment_style.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet issue 593: what happens when a newer release is out. Off, notify
/// (the bar's Update button asks once before downloading), or download
/// automatically. Installing always takes a tap on the bar.
class ReleaseUpdatesSetting extends StatefulWidget {
  const ReleaseUpdatesSetting(
      {required this.title, required this.description, super.key});

  final String title;
  final String description;

  @override
  State<ReleaseUpdatesSetting> createState() => _ReleaseUpdatesSettingState();
}

enum _Mode { off, ask, auto }

class _ReleaseUpdatesSettingState extends State<ReleaseUpdatesSetting> {
  String get labelReleaseUpdatesOff => Intl.message("Off",
      name: "labelReleaseUpdatesOff",
      desc: "New releases setting: no bar when a newer release is out");

  String get labelReleaseUpdatesAsk => Intl.message("Notify and ask",
      name: "labelReleaseUpdatesAsk",
      desc: "New releases setting: show the bar, ask before downloading");

  String get labelReleaseUpdatesAuto => Intl.message("Download automatically",
      name: "labelReleaseUpdatesAuto",
      desc: "New releases setting: download the new release's file without "
          "asking (installing still takes a tap)");

  _Mode get mode => !preferences.releaseNotice.value
      ? _Mode.off
      : preferences.releaseAutoDownload.value
          ? _Mode.auto
          : _Mode.ask;

  Future<void> select(_Mode mode) async {
    await preferences.releaseNotice.set(mode != _Mode.off);
    await preferences.releaseAutoDownload.set(mode == _Mode.auto);
    // Picking a mode here answers the bar's one-time question.
    if (mode != _Mode.off) await preferences.releaseUpdateAsked.set(true);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          color: ColorScheme.of(context).surfaceContainer.withAlpha(100),
          border: BoxBorder.all(
              color: ColorScheme.of(context).secondary.withAlpha(20)),
          borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            tiamat.Text(widget.title),
            tiamat.Text.labelLow(widget.description),
            const SizedBox(height: 8),
            SegmentedButton<_Mode>(
              showSelectedIcon: false,
              style: selectedSegmentStyle(Theme.of(context).colorScheme),
              segments: [
                ButtonSegment(
                    value: _Mode.off, label: Text(labelReleaseUpdatesOff)),
                ButtonSegment(
                    value: _Mode.ask, label: Text(labelReleaseUpdatesAsk)),
                ButtonSegment(
                    value: _Mode.auto, label: Text(labelReleaseUpdatesAuto)),
              ],
              selected: {mode},
              onSelectionChanged: (s) => select(s.first),
            ),
          ],
        ),
      ),
    );
  }
}
