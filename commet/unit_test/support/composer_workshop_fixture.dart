// Vommet issue 1142: real room fixtures; OS media polling disabled.
import 'package:commet/utils/now_playing/now_playing.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'room_page_fixtures.dart';

const comparisonSurface = ValueKey('issue-1142-surface');
Future<void> alignmentSetUp() async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('FlutterWebRTC.Event'), (_) async => null);
  await roomPageSetUp();
  // OS media polling is unrelated to alignment and CI has no session bus.
  await nowPlayingPreference.set(false);
}

Future<void> alignmentTearDown() async {
  await roomPageTearDown();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('FlutterWebRTC.Event'), null);
}
