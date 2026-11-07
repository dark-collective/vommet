import 'package:commet/client/attachment.dart';
import 'package:commet/config/layout_style.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/organisms/attachment_processor/attachment_processor.dart';
import 'package:commet/ui/organisms/media_send_sheet/media_send_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Vommet issue 1051: real entry points, including CI's explicit narrow size.
void androidWidgets(String name, WidgetTesterCallback body) =>
    testWidgets(name, body,
        variant: TargetPlatformVariant.only(TargetPlatform.android));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('im.nether.chat/video_trim');
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            channel, (call) async => call.method == 'supported' ? true : null);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  for (final style in LayoutStyle.values) {
    for (final phone in [true, false]) {
      for (final sheet in [true, false]) {
        androidWidgets(
            'trim entry ${style.name} ${phone ? '390x844' : '1000x800'} ${sheet ? 'sheet' : 'dialog'}',
            (tester) async {
          await LayoutOptions.discord.save();
          if (style == LayoutStyle.telegram)
            await LayoutOptions.telegram.save();
          await layoutStyleCustomPicked.set(style == LayoutStyle.custom);
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize =
              phone ? const Size(390, 844) : const Size(1000, 800);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final file = PendingFileAttachment(
              name: 'Walk.mp4', mimeType: 'video/mp4', data: Uint8List(32));
          await tester.pumpWidget(MaterialApp(
              home: sheet
                  ? MediaSendSheet(files: [file])
                  : Scaffold(
                      body: SingleChildScrollView(
                          child: AttachmentProcessor(attachment: file)))));
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('video-trim')), findsOneWidget);
          expect(find.text('Trim video'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
