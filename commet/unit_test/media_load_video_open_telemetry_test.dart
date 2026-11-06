// Vommet issue 1065 (telemetry schema v46): the real VideoPlayerImplementation
// ends a video's watch (path stream, step opening) when the player has loaded
// a file streamed straight from the homeserver, not when open() returns:
// media_kit's open() only hands mpv the URL, and mpv's own fetch from the
// homeserver is the part Vommet's http_stats can't see. The player is the
// LoadingFakePlayer (media_kit's needs libmpv), with no video output.
// unit_test/ isn't a recognised test directory for the analyzer.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:io';
import 'dart:typed_data';

import 'package:commet/cache/file_provider.dart';
import 'package:commet/cache/streamable_file_provider.dart';
import 'package:commet/main.dart';
import 'package:commet/telemetry/media_load_telemetry.dart';
import 'package:commet/telemetry/telemetry_schema.dart';
import 'package:commet/ui/molecules/video_player/video_player_controller.dart';
import 'package:commet/ui/molecules/video_player/video_player_implementation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'media_load_fake_player.dart';

/// An unencrypted video on a homeserver with range requests: the player
/// opens it straight from the homeserver, as MxcFileProvider hands it over.
class _DirectVideo implements FileProvider, StreamableFileProvider {
  @override
  Future<StreamSource?> getStreamSource() async => StreamSource(
      Uri.parse("https://hs.invalid/_matrix/client/v1/media/download/x/y"),
      opening: MediaLoadWatch(
          path: "stream", kind: "video", encrypted: false, step: "opening"));
  @override
  Future<Uri?> resolve() async => null;
  @override
  String get fileIdentifier => "video";
  @override
  Stream<DownloadProgress>? get onProgressChanged => null;
  @override
  Future<Uint8List?> getFileData() async => null;
  @override
  Future<void> save(String filepath) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final schema = TelemetrySchema.parse(
      File("assets/telemetry/schema.json").readAsStringSync());
  final events = <Map<String, Object?>>[];
  late LoadingFakePlayer player;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  setUp(() {
    events.clear();
    player = LoadingFakePlayer();
    VideoPlayerImplementation.createPlayer = () => player;
    VideoPlayerImplementation.createController = (_) => null;
    MediaLoadWatch.stallAfter = const Duration(seconds: 10);
    MediaLoadWatch.enabled = () => true;
    MediaLoadWatch.record = (name, fields) {
      final ev = <String, Object?>{"e": name, "t": 1};
      fields.forEach((k, v) {
        if (v != null) ev[k] = v;
      });
      expect(schema.validateEvent(ev), isTrue,
          reason: "$name must fit the telemetry schema: $ev");
      events.add(ev);
    };
  });

  tearDown(() => MediaLoadWatch.enabled = () => false);

  Future<void> showVideo(WidgetTester tester) async {
    await tester.pumpWidget(SizedBox(
        width: 640,
        height: 340,
        child: VideoPlayerImplementation(
            controller: VideoPlayerController(), videoFile: _DirectVideo())));
    await tester.pump();
    await tester.pump();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  }

  testWidgets("1065 a direct video mpv never loads stalls at opening",
      (tester) async {
    player.openHangs = true;
    await showVideo(tester);
    await tester.pump(const Duration(seconds: 9));
    expect(events, isEmpty);
    await tester.pump(const Duration(seconds: 2));
    final stall = events.singleWhere((e) => e["e"] == "media_load_stall");
    expect(stall["path"], "stream");
    expect(stall["kind"], "video");
    expect(stall["step"], "opening");
    expect(events.where((e) => e["e"] == "media_load"), isEmpty);
    // Closing it ends the stalled watch as cancelled.
    await tester.pumpWidget(const SizedBox());
    final end = events.singleWhere((e) => e["e"] == "media_load");
    expect(end["outcome"], "cancelled");
    expect(end["step"], "opening");
    expect(end["stalled"], true);
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets("1065 a direct video that loads records an ok end",
      (tester) async {
    await showVideo(tester);
    // open() has returned; mpv hasn't loaded the file yet.
    expect(events, isEmpty);
    await tester.pump(const Duration(milliseconds: 400));
    final end = events.singleWhere((e) => e["e"] == "media_load");
    expect(end["path"], "stream");
    expect(end["step"], "opening");
    expect(end["outcome"], "ok");
    expect(end["stalled"], false);
    await tester.pump(const Duration(seconds: 11));
    expect(events.where((e) => e["e"] == "media_load_stall"), isEmpty);
    await close(tester);
  });

  testWidgets("1065 a direct video mpv fails to load records an error end",
      (tester) async {
    player.loadError = "Failed to open";
    await showVideo(tester);
    expect(events, isEmpty);
    await tester.pump(const Duration(milliseconds: 400));
    // mpv's error may be non-fatal: the end waits 1 s for a load signal.
    expect(events, isEmpty);
    await tester.pump(const Duration(seconds: 1));
    final end = events.singleWhere((e) => e["e"] == "media_load");
    expect(end["path"], "stream");
    expect(end["outcome"], "error");
    expect(end["error_type"], isNotNull);
    await close(tester);
  });

  testWidgets("1065 a direct video loaded after a non-fatal mpv error is ok",
      (tester) async {
    player.loadError = "Non-fatal";
    player.loadsAfterError = true;
    await showVideo(tester);
    await tester.pump(const Duration(seconds: 2));
    final end = events.singleWhere((e) => e["e"] == "media_load");
    expect(end["outcome"], "ok");
    expect(end.containsKey("error_type"), isFalse);
    await close(tester);
  });

  testWidgets("1065 a direct video closed before it loads ends cancelled",
      (tester) async {
    player.openHangs = true;
    await showVideo(tester);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpWidget(const SizedBox());
    final end = events.singleWhere((e) => e["e"] == "media_load");
    expect(end["path"], "stream");
    expect(end["outcome"], "cancelled");
    await tester.pump(const Duration(seconds: 30));
    expect(events.where((e) => e["e"] == "media_load_stall"), isEmpty);
  });
}
