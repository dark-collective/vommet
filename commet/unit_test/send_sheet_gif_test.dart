import 'package:commet/client/attachment.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/organisms/attachment_processor/video_gif_trim.dart';
import 'package:commet/ui/organisms/media_send_sheet/media_send_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

/// Vommet issue 1050: "Convert to GIF" on the phone send screen.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final gifBytes = img.encodeGif(img.Image(width: 4, height: 2));
  final made = ConvertedGif(gifBytes, 4, 2, const Duration(milliseconds: 4200));

  // No path: the preview shows no player, so no media_kit in tests.
  PendingFileAttachment video() => PendingFileAttachment(
      name: 'clip.mp4',
      mimeType: 'video/mp4',
      data: Uint8List.fromList(List.filled(32, 7)),
      size: 32);

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });
  tearDown(() {
    // ignore: invalid_use_of_visible_for_testing_member
    MediaSendSheet.debugTrim = null;
  });

  test('a video made into a GIF and back keeps the video as picked', () {
    final file = video();
    final original = VideoBeforeGif.apply(file, made);
    expect(file.mimeType, 'image/gif');
    expect(file.name, 'clip.gif');
    expect(file.path, isNull);
    expect(file.data, same(gifBytes));
    expect(file.size, gifBytes.lengthInBytes);
    expect(file.dimensions, const Size(4, 2));
    original.restore(file);
    expect(file.mimeType, 'video/mp4');
    expect(file.name, 'clip.mp4');
    expect(file.size, 32);
    expect(file.data!.length, 32);
    expect(file.dimensions, isNull);
  });

  testWidgets('GIF button converts the selected video, undo puts it back',
      (tester) async {
    PendingFileAttachment? asked;
    // ignore: invalid_use_of_visible_for_testing_member
    MediaSendSheet.debugTrim = (_, file) async {
      asked = file;
      return made;
    };
    final clip = video();
    final picture = PendingFileAttachment(
        name: 'a.gif', mimeType: 'image/gif', data: gifBytes);
    await tester
        .pumpWidget(MaterialApp(home: MediaSendSheet(files: [clip, picture])));
    await tester.pumpAndSettle();
    final state =
        tester.state<MediaSendSheetState>(find.byType(MediaSendSheet));

    expect(find.byKey(const ValueKey("media-send-gif")), findsOneWidget);
    expect(find.byKey(const ValueKey(("media-send-gif-tag", 0))), findsNothing);
    await tester.tap(find.byKey(const ValueKey("media-send-gif")));
    await tester.pumpAndSettle();

    expect(asked, same(clip));
    expect(clip.mimeType, 'image/gif');
    expect(state.files, [clip, picture]);
    expect(find.byKey(const ValueKey("media-send-gif")), findsNothing);
    expect(find.byKey(const ValueKey("media-send-gif-undo")), findsOneWidget);
    expect(find.text(MediaSendSheet.labelGifLength("4.2")), findsOneWidget);
    expect(
        find.byKey(const ValueKey(("media-send-gif-tag", 0))), findsOneWidget);

    // A picture has no GIF button.
    await tester.tap(find.byKey(const ValueKey(("media-send-tile", 1))));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey("media-send-gif")), findsNothing);
    expect(find.byKey(const ValueKey("media-send-gif-undo")), findsNothing);

    await tester.tap(find.byKey(const ValueKey(("media-send-tile", 0))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey("media-send-gif-undo")));
    await tester.pumpAndSettle();
    expect(clip.mimeType, 'video/mp4');
    expect(clip.name, 'clip.mp4');
    expect(state.gifs, isEmpty);
    expect(find.byKey(const ValueKey("media-send-gif")), findsOneWidget);
    expect(find.byKey(const ValueKey(("media-send-gif-tag", 0))), findsNothing);
  });

  testWidgets('canceling the clip editor leaves the video', (tester) async {
    // ignore: invalid_use_of_visible_for_testing_member
    MediaSendSheet.debugTrim = (_, __) async => null;
    final clip = video();
    await tester.pumpWidget(MaterialApp(home: MediaSendSheet(files: [clip])));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey("media-send-gif")));
    await tester.pumpAndSettle();
    expect(clip.mimeType, 'video/mp4');
    expect(find.byKey(const ValueKey("media-send-gif")), findsOneWidget);
  });
}
