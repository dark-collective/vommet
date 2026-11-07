import 'dart:async';
import 'dart:io';

import 'package:commet/client/attachment.dart';
import 'package:commet/ui/organisms/attachment_processor/video_trim.dart';
import 'package:commet/utils/video_trim.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class FixtureJob extends VideoTrimJob {
  bool fail = false;
  (int, int)? requested;
  Completer<VideoTrimEdit>? gate;
  @override
  Future<void> load(PendingFileAttachment original) async {
    if (fail) throw StateError('unsupported');
    cuts = [0, 3000000, 9000000, 16000000];
    source = File('/fixture.mp4');
  }

  @override
  Future<VideoTrimEdit> save(
      PendingFileAttachment original, int first, int last) async {
    requested = (first, last);
    if (gate != null) return gate!.future;
    return VideoTrimEdit(original, original, first, last);
  }

  @override
  Future<void> close() async {
    cancel();
  }
}

void main() {
  final original = PendingFileAttachment(
      name: 'Walk.mp4', mimeType: 'video/mp4', data: Uint8List(32));
  Future<void> pump(WidgetTester tester, FixtureJob job) async {
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => Dialog(
                        child: VideoTrimDialog(
                            original: original,
                            job: job,
                            preview: const ColoredBox(color: Colors.black)))),
                child: const Text('Open')))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'time controls snap to inspected points and Apply uses the selected interval',
      (tester) async {
    final job = FixtureJob();
    await pump(tester, job);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('video-trim-apply')))
            .onPressed,
        isNull);
    tester
        .widget<RangeSlider>(find.byKey(const ValueKey('video-trim-range')))
        .onChanged!(const RangeValues(4200000, 11000000));
    await tester.pump();
    expect(
        tester
            .widgetList<DropdownButton<int>>(find.byType(DropdownButton<int>))
            .map((w) => w.value),
        [1, 2]);
    expect(find.text('0:03.000'), findsOneWidget);
    expect(find.text('0:09.000'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('video-trim-apply')));
    await tester.pumpAndSettle();
    expect(job.requested, (1, 2));
    expect(find.byType(VideoTrimDialog), findsNothing);
  });
  testWidgets('unsupported source explains failure and offers only Cancel',
      (tester) async {
    await pump(tester, FixtureJob()..fail = true);
    expect(find.text(VideoTrimDialog.failed), findsOneWidget);
    expect(find.byKey(const ValueKey('video-trim-apply')), findsNothing);
    await tester.tap(find.text(VideoTrimDialog.cancel));
    await tester.pumpAndSettle();
    expect(find.byType(VideoTrimDialog), findsNothing);
  });
  testWidgets('copy failure shows the error and leaves the original unchanged',
      (tester) async {
    final job = FixtureJob()..gate = Completer<VideoTrimEdit>();
    await pump(tester, job);
    tester
        .widget<RangeSlider>(find.byType(RangeSlider))
        .onChanged!(const RangeValues(3000000, 16000000));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('video-trim-apply')));
    await tester.pump();
    job.gate!.completeError(StateError('copy rejected'));
    await tester.pumpAndSettle();
    expect(find.text(VideoTrimDialog.failed), findsOneWidget);
    expect(find.byKey(const ValueKey('video-trim-apply')), findsNothing);
    expect(original.name, 'Walk.mp4');
  });
  testWidgets(
      'Cancel while copying closes immediately; late completion cannot apply',
      (tester) async {
    final job = FixtureJob()..gate = Completer<VideoTrimEdit>();
    await pump(tester, job);
    tester
        .widget<RangeSlider>(find.byKey(const ValueKey('video-trim-range')))
        .onChanged!(const RangeValues(3000000, 16000000));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('video-trim-apply')));
    await tester.pump();
    expect(find.text(VideoTrimDialog.saving), findsOneWidget);
    await tester.tap(find.text(VideoTrimDialog.cancel));
    await tester.pumpAndSettle();
    expect(job.canceled, isTrue);
    job.gate!.complete(VideoTrimEdit(original, original, 1, 3));
    await tester.pumpAndSettle();
    expect(find.byType(VideoTrimDialog), findsNothing);
    expect(original.name, 'Walk.mp4');
    expect(tester.takeException(), isNull);
  });
}
