import 'dart:async';
import 'dart:typed_data';

import 'package:commet/client/attachment.dart';
import 'package:commet/client/client.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/message_input.dart';
import 'package:commet/ui/organisms/attachment_processor/attachment_processor.dart';
import 'package:commet/ui/organisms/media_send_sheet/media_send_sheet.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeClient implements Client {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Picker extends FilePicker {
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async =>
      FilePickerResult([
        for (final name in ["x.pdf", "y.txt"])
          PlatformFile(
              name: name, size: 3, bytes: Uint8List.fromList([1, 2, 3])),
      ]);
}

PendingFileAttachment file(String name) => PendingFileAttachment(
    name: name,
    mimeType: "application/pdf",
    size: 3,
    data: Uint8List.fromList([1, 2, 3]));

// Vommet issue 1066: files shared into a room from another app open the
// phone send screen as one batch, like an in-app pick.
void main() {
  late StreamController<List<PendingFileAttachment>> shared;

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    shared = StreamController();
  });

  tearDown(() {
    // ignore: invalid_use_of_visible_for_testing_member
    MessageInputState.debugPhoneOs = null;
    shared.close();
  });

  Future<void> pumpComposer(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: MessageInput(
            client: FakeClient(),
            availibleEmoticons: const [],
            sharedFiles: shared.stream,
            addAttachment: (_) async {},
            onSendMessage: (message, {overrideClient}) =>
                MessageInputSendResult.success,
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('a share of 3 files opens one send sheet with 3 items in order',
      (tester) async {
    // ignore: invalid_use_of_visible_for_testing_member
    MessageInputState.debugPhoneOs = true;
    await pumpComposer(tester);

    shared.add([file("a.pdf"), file("b.pdf"), file("c.pdf")]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(MediaSendSheet), findsOneWidget);
    expect(find.byType(AttachmentProcessor), findsNothing);
    final sheet =
        tester.state<MediaSendSheetState>(find.byType(MediaSendSheet));
    expect(sheet.files.map((f) => f.name), ["a.pdf", "b.pdf", "c.pdf"]);
  });

  testWidgets('without the phone send sheet, shares keep the per-file dialog',
      (tester) async {
    // ignore: invalid_use_of_visible_for_testing_member
    MessageInputState.debugPhoneOs = false;
    await pumpComposer(tester);

    shared.add([file("a.pdf"), file("b.pdf")]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(MediaSendSheet), findsNothing);
    expect(find.byType(AttachmentProcessor), findsOneWidget);
  });

  testWidgets('on a phone, + File opens one send sheet with every pick',
      (tester) async {
    // ignore: invalid_use_of_visible_for_testing_member
    MessageInputState.debugPhoneOs = true;
    FilePicker.platform = _Picker();
    await pumpComposer(tester);

    final state = tester.state<MessageInputState>(find.byType(MessageInput));
    unawaited(state.pickFiles());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(MediaSendSheet), findsOneWidget);
    expect(find.byType(AttachmentProcessor), findsNothing);
    final sheet =
        tester.state<MediaSendSheetState>(find.byType(MediaSendSheet));
    expect(sheet.files.map((f) => f.name), ["x.pdf", "y.txt"]);
  });
}
