import 'dart:math';

import 'package:commet/client/components/voip/screen_share_audio.dart';
import 'package:commet/ui/organisms/call_view/screen_capture_source_widget.dart';
import 'package:commet/ui/organisms/call_view/screen_share_audio_picker.dart';
import 'package:commet/ui/organisms/call_view/share_quality_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'package:tiamat/tiamat.dart' as tiamat;

class ScreenCaptureSourceDialog extends StatefulWidget {
  const ScreenCaptureSourceDialog(this.sources, this.onThumbnailChanged,
      {super.key});
  final List<DesktopCapturerSource> sources;
  final Stream<DesktopCapturerSource> onThumbnailChanged;

  @override
  State<ScreenCaptureSourceDialog> createState() =>
      _ScreenCaptureSourceDialogState();
}

/// What the dialog pops: the video source and (Vommet) the audio to share.
typedef ScreenCaptureChoice = (DesktopCapturerSource, ScreenShareAudio);

// Vommet issue 859 (Layout A): picking a source selects it; the quality
// sits below the sources and audio, and Go live starts the share with
// both (the choices are applied then). Cancel closes without sharing.
class _ScreenCaptureSourceDialogState extends State<ScreenCaptureSourceDialog> {
  late List<DesktopCapturerSource> screenSources;
  late List<DesktopCapturerSource> windowSources;
  ScreenShareAudio audio = ScreenShareAudio.lastChoice;
  final draft = ShareQualityDraft.current();
  DesktopCapturerSource? selected;

  Future<void> goLive() async {
    final source = selected;
    if (source == null) return;
    await draft.apply();
    if (mounted) {
      Navigator.of(context).pop<ScreenCaptureChoice>((source, audio));
    }
  }

  @override
  void initState() {
    this.screenSources =
        widget.sources.where((i) => i.type == SourceType.Screen).toList();
    this.windowSources =
        widget.sources.where((i) => i.type == SourceType.Window).toList();
    if (widget.sources.length == 1) selected = widget.sources.first;

    super.initState();
  }

  Widget grid(List<DesktopCapturerSource> sources) {
    final scheme = Theme.of(context).colorScheme;
    return MasonryGridView.count(
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      physics: const NeverScrollableScrollPhysics(),
      addAutomaticKeepAlives: false,
      crossAxisCount: 2,
      shrinkWrap: true,
      itemCount: sources.length,
      itemBuilder: (context, index) {
        final source = sources[index];
        final isSelected = selected?.id == source.id;
        return Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  width: 2,
                  color: isSelected ? scheme.primary : Colors.transparent)),
          child: ScreenCaptureSourceWidget(
            source,
            widget.onThumbnailChanged,
            onTap: () => setState(() => selected = source),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final height = min(760.0, MediaQuery.of(context).size.height * .85);
    return SizedBox(
      width: 700,
      height: height,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (ScreenShareAudio.canChoose) ...[
                    ScreenShareAudioPicker(
                      value: audio,
                      onChanged: (a) => setState(() => audio = a),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (windowSources.isNotEmpty) ...[
                    tiamat.Text.largeTitle("Windows:"),
                    grid(windowSources),
                    SizedBox(
                      height: 32,
                    )
                  ],
                  if (screenSources.isNotEmpty) ...[
                    tiamat.Text.largeTitle("Screens:"),
                    grid(screenSources),
                  ],
                  const SizedBox(height: 24),
                  ShareQualitySection(draft: draft),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          ShareQualityButtons(onGoLive: selected == null ? null : goLive),
        ],
      ),
    );
  }
}
