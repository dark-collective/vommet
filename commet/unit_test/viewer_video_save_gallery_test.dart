import 'dart:async';

import 'package:commet/cache/file_provider.dart';
import 'package:commet/ui/atoms/lightbox_feedback.dart';
import 'package:commet/ui/atoms/lightbox_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Video extends Fake implements FileProvider {}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const gallery = MethodChannel('gal');
  tearDown(() =>
      binding.defaultBinaryMessenger.setMockMethodCallHandler(gallery, null));

  testWidgets(
      'gallery refusal uses viewer feedback and concurrent saves share permission request',
      (tester) async {
    final gate = Completer<bool>();
    var requests = 0;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(gallery,
        (call) async {
      switch (call.method) {
        case 'hasAccess':
          return false;
        case 'requestAccess':
          requests++;
          return gate.future;
      }
      fail('Permission refusal must not read or save media');
    });
    late BuildContext context;
    await tester.pumpWidget(
        MaterialApp(home: LightboxFeedback(child: Builder(builder: (value) {
      context = value;
      return const SizedBox.expand();
    }))));
    final file = _Video();
    final first = LightboxMenu.saveVideo(context, file, toGallery: true);
    final second = LightboxMenu.saveVideo(context, file, toGallery: true);
    await tester.pump();
    expect(requests, 1);
    gate.complete(false);
    await tester.pump();
    await Future.wait([first, second]);
    await tester.pumpAndSettle();
    expect(find.text('Vommet needs permission to add to your gallery'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    // The completed request is removed, allowing another explicit attempt.
    await LightboxMenu.saveVideo(context, file, toGallery: true);
    await tester.pump();
    expect(requests, 2);
    await tester.pumpWidget(const SizedBox());
  });
}
