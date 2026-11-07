// Vommet issue 1226: actual phone media review, normal composer and SDK sends.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:commet/client/attachment.dart';
import 'package:commet/client/matrix/components/profile/matrix_profile_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/config/layout_style.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/rich_text_field.dart';
import 'package:commet/ui/molecules/message_input.dart';
import 'package:commet/ui/organisms/attachment_processor/video_trim.dart';
import 'package:commet/ui/organisms/chat/chat.dart';
import 'package:commet/ui/organisms/media_send_sheet/media_send_sheet.dart';
import 'package:commet/utils/autofill_utils.dart';
import 'package:commet/utils/emoji/unicode_emoji.dart';
import 'package:commet/utils/video_trim.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

import 'roomlist_fixture.dart';

const roomId = '!caption:example.com';
const reporter = '@dark:nether.im';
const captureKey = ValueKey('issue-1226-capture');
const inputKey = ValueKey('composer-input');

class _Picker extends ImagePickerPlatform {
  List<XFile> media = [];
  XFile? camera;

  @override
  Future<List<XFile>> getMedia({required MediaOptions options}) async => media;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async =>
      source == ImageSource.camera ? camera : null;
}

class _Files extends FilePicker {
  FilePickerResult? result;

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
      result;
}

void phoneTest(String name, WidgetTesterCallback body,
        {TargetPlatform platform = TargetPlatform.android}) =>
    testWidgets(name, body, variant: TargetPlatformVariant.only(platform));

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late MatrixClient client;
  var serial = 0;
  var attached = <PendingFileAttachment>[];
  var sent = <Map<String, dynamic>>[];
  Future<void>? sending;
  Completer<void>? wireComplete;
  var expectedFiles = 0;
  final photo = img.encodePng(img.fill(img.Image(width: 80, height: 60),
      color: img.ColorRgb8(76, 122, 169)));
  PendingFileAttachment file([String name = 'photo.png']) =>
      PendingFileAttachment(
          name: name, mimeType: 'image/png', data: photo, size: photo.length);

  setUp(() async {
    // unit_test is outside the analyzer's recognized test directory.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('FlutterWebRTC.Event'), (_) async => null);
    await UnicodeEmojis.load();
    client = await signedInClient('caption-${serial++}', userId: reporter);
    client.self = MatrixProfile(client, matrix.Profile(userId: reporter));
    await sync(client, join: {
      roomId: matrix.JoinedRoomUpdate(state: [
        ...roomState(roomId, name: 'Vommet'),
        stateEvent(
            'm.room.member', {'membership': 'join', 'displayname': 'dark'},
            stateKey: reporter),
        stateEvent(
            'm.room.member', {'membership': 'join', 'displayname': 'Dara'},
            stateKey: '@dara:example.org'),
      ])
    });
    // Explicit loaded SDK member cache, as after the room timeline/member load.
    // Sync fixtures use partial rooms and otherwise leave this cache empty.
    client.getMatrixClient().getRoomById(roomId)!.states['m.room.member'] = {
      for (final entry
          in {reporter: 'dark', '@dara:example.org': 'Dara'}.entries)
        entry.key: matrix.StrippedStateEvent(
            type: 'm.room.member',
            stateKey: entry.key,
            senderId: reporter,
            content: {'membership': 'join', 'displayname': entry.value}),
    };
    attached = [];
    sent = [];
    sending = null;
    wireComplete = null;
    expectedFiles = 0;
    stubResponse = (request) {
      if (request.url.path.contains('/send/')) {
        sent.add(jsonDecode(request.body) as Map<String, dynamic>);
        if (expectedFiles > 0 &&
            sent.where((e) => e['msgtype'] != 'm.text').length ==
                expectedFiles &&
            wireComplete?.isCompleted == false) wireComplete!.complete();
      }
      if (request.url.path.endsWith('/upload')) {
        return http.Response(
            jsonEncode({'content_uri': 'mxc://example.com/photo'}), 200,
            headers: {'content-type': 'application/json'});
      }
      return null;
    };
  });
  tearDown(() async {
    stubResponse = null;
    // ignore: invalid_use_of_visible_for_testing_member
    MessageInputState.debugPhoneOs = null;
    await preferences.layoutOverride.set(null);
    await pickLayoutStyle(LayoutStyle.discord);
    await client.getMatrixClient().dispose(closeDatabase: true);
  });

  Future<void> pump(WidgetTester tester,
      {Size size = const Size(360, 804),
      double scale = 1,
      double keyboard = 265,
      bool phone = true,
      bool editing = false,
      MatrixClient? account,
      String selectedRoom = roomId,
      MatrixClient? overrideAccount,
      Stream<List<PendingFileAttachment>>? shares,
      Future<bool> Function(PendingFileAttachment)? check}) async {
    final owner = account ?? client;
    final room = owner.getRoom(selectedRoom)!;
    if (account == null && selectedRoom == roomId) {
      expect(room.memberIds, contains(reporter));
      expect(AutofillUtils.search('@d', owner, room: room), isNotEmpty);
    }
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.reset);
    // The OS/size are explicit and independent of CI's MOBILE define.
    // ignore: invalid_use_of_visible_for_testing_member
    MessageInputState.debugPhoneOs = phone;
    await preferences.layoutOverride.set(phone ? 'mobile' : 'desktop');
    if (Platform.environment['VOMMET_1226_CAPTURE_DIR'] != null) {
      await tester.runAsync(() async {
        for (final name in ['RobotoCustom', 'Roboto']) {
          await (FontLoader(name)
                ..addFont(Future.value(ByteData.sublistView(
                    File('assets/font/roboto/Roboto-Regular.ttf')
                        .readAsBytesSync()))))
              .load();
        }
        final icons = Platform.environment['SPECIMEN_ICON_FONT'];
        if (icons != null) {
          await (FontLoader('MaterialIcons')
                ..addFont(Future.value(
                    ByteData.sublistView(File(icons).readAsBytesSync()))))
              .load();
        }
      });
    }
    await tester.pumpWidget(RepaintBoundary(
      key: captureKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeDark.theme,
        builder: (context, child) => MediaQuery(
          data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(scale),
              viewInsets: EdgeInsets.only(bottom: keyboard)),
          child: child!,
        ),
        home: Scaffold(
          resizeToAvoidBottomInset: scale == 1,
          appBar: AppBar(title: const Text('Vommet · issue 1226')),
          body: StatefulBuilder(
              builder: (context, refresh) => Column(children: [
                    const Expanded(child: Center(child: Text('Conversation'))),
                    MessageInput(
                      client: owner,
                      room: room,
                      interactionType: editing
                          ? EventInteractionType.edit
                          : scale > 1
                              ? EventInteractionType.reply
                              : null,
                      relatedEventBody: scale > 1 ? 'A quoted message' : null,
                      relatedEventSenderName: 'Dara',
                      availibleEmoticons: const [],
                      onSendVoiceMessage: (_, {overrideClient}) async => true,
                      attachments: attached,
                      checkAttachment: check,
                      sharedFiles: shares,
                      addAttachment: (file) async =>
                          refresh(() => attached.add(file)),
                      removeAttachment: (file) =>
                          refresh(() => attached.remove(file)),
                      moveAttachment: (_, __) {},
                      findOverrideClient: (text) =>
                          text.startsWith('other ') ? overrideAccount : null,
                      processAutofill: (text) =>
                          AutofillUtils.search(text, owner, room: room),
                      onSendMessage: (text, {overrideClient}) {
                        final batch = List<PendingFileAttachment>.of(attached);
                        expectedFiles = batch.length;
                        sending = tester.runAsync(() async {
                          wireComplete = Completer<void>();
                          final target =
                              (overrideClient ?? owner).getRoom(selectedRoom)!;
                          final files = await target.processAttachments(batch);
                          await target.sendMessage(
                              message: text, processedAttachments: files);
                          if (batch.isEmpty) return;
                          await wireComplete!.future;
                          // All requests have been observed; wait for the
                          // SDK's final send/local-echo transaction too.
                          await Future.wait(owner
                              .getMatrixClient()
                              .getRoomById(roomId)!
                              .sendingQueue
                              .map((completion) => completion.future));
                        });
                        return MessageInputSendResult.success;
                      },
                    ),
                  ])),
        ),
      ),
    ));
    await tester.runAsync(() => precacheImage(
        MemoryImage(photo), tester.element(find.byType(Scaffold))));
    await tester.pump();
  }

  MessageInputState state(WidgetTester tester) => tester
      .state<MessageInputState>(find.byType(MessageInput, skipOffstage: false));

  Future<void> open(WidgetTester tester,
      [List<PendingFileAttachment>? files]) async {
    unawaited(state(tester).openMediaSendSheet(files ?? [file()]));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  Future<void> capture(WidgetTester tester, String name) async {
    final dir = Platform.environment['VOMMET_1226_CAPTURE_DIR'];
    if (dir == null) return;
    final boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(captureKey));
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final target = File('$dir/$name.png');
      target.parent.createSync(recursive: true);
      target.writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final style in LayoutStyle.values) {
    for (final narrow in [false, true]) {
      phoneTest(
          '${style.name}: keyboard-open ${narrow ? "320x640 large" : "360x804"} media caption',
          (tester) async {
        await pickLayoutStyle(style);
        await pump(tester,
            size: narrow ? const Size(320, 640) : const Size(360, 804),
            scale: narrow ? 1.5 : 1,
            keyboard: narrow ? 230 : 265);
        final originalController = state(tester).controller;
        final originalEditor =
            tester.state<EditableTextState>(find.byType(EditableText));
        final priorPicker = ImagePickerPlatform.instance;
        addTearDown(() => ImagePickerPlatform.instance = priorPicker);
        ImagePickerPlatform.instance = _Picker()
          ..media = [
            XFile.fromData(photo, path: '/photo.png', mimeType: 'image/png')
          ];
        unawaited(state(tester).pickFromPhotoLibrary());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        final caption = find.byKey(const ValueKey('media-send-caption'));
        // Capture the real old sheet as well as the integrated new review.
        final field =
            caption.evaluate().isNotEmpty ? caption : find.byKey(inputKey);
        await tester.enterText(field,
            'Android, 11-06d, and this should apply to all versions. @d');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await capture(tester, '${style.name}-${narrow ? "narrow" : "phone"}');
        expect(caption, findsNothing);
        expect(find.byKey(inputKey), findsOneWidget);
        expect(state(tester).controller, same(originalController));
        expect(tester.state<EditableTextState>(find.byType(EditableText)),
            same(originalEditor));
        expect(find.byKey(const ValueKey('composer-autofill-card')),
            findsOneWidget);
        expect(find.text(reporter), findsOneWidget);
        expect(tester.getRect(find.byKey(inputKey)).bottom,
            lessThanOrEqualTo(narrow ? 410 : 539));
        expect(tester.takeException(), isNull);
        // Typing more must keep the reporter's own user available.
        await tester.enterText(find.byKey(inputKey), 'Look @dar please');
        state(tester).controller.selection =
            const TextSelection.collapsed(offset: 9);
        state(tester).onTextfieldUpdated(state(tester).controller.text);
        await tester.pump();
        await tester.pump();
        await tester.pump();
        await tester.tap(find.text('dark'));
        await tester.pump();
        expect(state(tester).controller.text, 'Look $reporter please');
        expect(state(tester).controller.selection.isValid, isTrue);
        await tester.tap(find.byKey(const ValueKey('media-send-close')));
        await tester.pump();
        expect(find.byType(MediaSendSheet), findsNothing);
        expect(state(tester).controller.text, 'Look $reporter please');
        expect(attached, isEmpty);
        expect(sent, isEmpty);
      });
    }
  }

  for (final style in LayoutStyle.values) {
    phoneTest('${style.name}: desktop tray remains unchanged', (tester) async {
      await pickLayoutStyle(style);
      await pump(tester,
          size: const Size(1200, 800), phone: false, keyboard: 0);
      await state(tester).handlePickedAttachment(file());
      await tester.pump();
      await tester.enterText(find.byKey(inputKey), 'Android, 11-06d. @d');
      await tester.pump();
      await tester.pump();
      await capture(tester, '${style.name}-desktop');
      expect(find.byType(MediaSendSheet), findsNothing);
      expect(find.byKey(inputKey), findsOneWidget);
      expect(find.text(reporter), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, platform: TargetPlatform.linux);
  }

  phoneTest('ranges, edits and composing never retain a hidden mention',
      (tester) async {
    await pump(tester);
    await open(tester);
    final input = state(tester);
    await tester.enterText(find.byKey(inputKey), 'é\n@dar tail');
    input.controller.selection = const TextSelection.collapsed(offset: 6);
    input.onTextfieldUpdated(input.controller.text);
    await tester.pump();
    await tester.pump();
    expect(input.getAutofillTextRange(), (2, 6));
    await tester.pump();
    await tester.tap(find.text('dark'));
    await tester.pump();
    expect(input.controller.text, 'é\n$reporter tail');
    await tester.enterText(find.byKey(inputKey), 'before $reporter after');
    await tester.enterText(find.byKey(inputKey), 'before after');
    await tester.pump();
    await tester.pump();
    expect(find.text(reporter), findsNothing);
    input.controller.value = const TextEditingValue(
        text: '@dar',
        selection: TextSelection.collapsed(offset: 4),
        composing: TextRange(start: 0, end: 4));
    input.onTextfieldUpdated(input.controller.text);
    await tester.pump();
    await tester.pump();
    expect(
        find.byKey(const ValueKey('composer-autofill-card')), findsOneWidget);
    await tester.tap(find.text('dark'));
    await tester.pump();
    expect(input.controller.text, '$reporter ');
    expect(input.controller.value.composing, TextRange.empty);
    input.controller.value = const TextEditingValue(text: '@dar');
    input.onTextfieldUpdated(input.controller.text);
    expect(input.getAutofillTextRange(cursorPosition: -1), (-1, -1));
    expect(tester.takeException(), isNull);
  });

  for (final mention
      in {'dark': reporter, 'Dara': '@dara:example.org'}.entries) {
    phoneTest(
        'Send ${mention.key}: mention HTML, intent, batch and media metadata',
        (tester) async {
      await pump(tester);
      final first = file();
      await open(tester, [first]);
      await tester.enterText(find.byKey(inputKey), 'Look @dar');
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text(mention.key));
      await tester.pump();
      final review =
          tester.state<MediaSendSheetState>(find.byType(MediaSendSheet));
      review.toggleSpoiler(first);
      await tester.pump();
      review.spoilerReasons[first]!.text = 'test reason';
      state(tester).sendMessage();
      state(tester).sendMessage(); // A second tap cannot submit twice.
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      await sending;
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
      expect(attached, [same(first)]);
      expect(first.spoilerReason, 'test reason');
      expect(first.removeHiddenInfo, isTrue);
      final text = sent.singleWhere((e) => e['msgtype'] == 'm.text');
      expect(text['format'], 'org.matrix.custom.html');
      expect(text['formatted_body'],
          contains('https://matrix.to/#/${mention.value}'));
      expect(text['m.mentions'], {
        'user_ids': [mention.value]
      });
      final media = sent.singleWhere((e) => e['msgtype'] == 'm.image');
      expect(media['body'], 'photo.png');
      expect(media['m.mentions'], isNot(contains('user_ids')));
      // Existing group semantics: one text event, one media event, same batch.
      final batchKey = text.keys.singleWhere((k) => k.contains('send_batch'));
      expect(media[batchKey], text[batchKey]);
      expect(state(tester).controller.text, isEmpty);
    });
  }

  phoneTest(
      'closing, last removal and empty captions keep existing attachments',
      (tester) async {
    await pump(tester);
    final existing = file('existing.png');
    attached.add(existing);
    await tester.enterText(find.byKey(inputKey), 'keep $reporter');
    await open(tester);
    tester.state<MediaSendSheetState>(find.byType(MediaSendSheet)).remove(tester
        .state<MediaSendSheetState>(find.byType(MediaSendSheet))
        .files
        .single);
    await tester.pump();
    expect(attached, [existing]);
    expect(state(tester).controller.text, 'keep $reporter');
    await open(tester);
    await tester.enterText(find.byKey(inputKey), '');
    await tester.pump();
    expect(find.byIcon(Icons.send), findsOneWidget);
    await tester.enterText(find.byKey(inputKey), '   ');
    state(tester).sendMessage();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    await sending;
    expect(sent.where((e) => e['msgtype'] == 'm.text'), isEmpty);
    expect(attached.length, 2);
    state(tester).unfocus();
    await tester.pump();
    await tester.tap(find.byKey(inputKey));
    await tester.pump();
    expect(state(tester).textFocus.hasFocus, isTrue);
  });

  phoneTest('Back saves the draft and room changes discard provisional media',
      (tester) async {
    await pump(tester);
    await open(tester);
    await tester.enterText(find.byKey(inputKey), 'keep @dar');
    // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(MediaSendSheet), findsNothing);
    expect(state(tester).controller.text, 'keep @dar');
    await open(tester);
    await tester.runAsync(() => sync(client,
        join: {'!other:example.com': joined('!other:example.com')}));
    await pump(tester, selectedRoom: '!other:example.com');
    expect(find.byType(MediaSendSheet), findsNothing);
    expect(state(tester).controller.text, isEmpty);
    expect(attached, isEmpty);
  });

  phoneTest('a delayed size check cannot attach to the next room',
      (tester) async {
    final checked = Completer<bool>();
    await pump(tester, check: (_) => checked.future);
    unawaited(state(tester).onSharedFiles([file(), file()]));
    await tester.runAsync(() =>
        sync(client, join: {'!next:example.com': joined('!next:example.com')}));
    var wrongRoomChecks = 0;
    await pump(tester, selectedRoom: '!next:example.com', check: (_) async {
      wrongRoomChecks++;
      return true;
    });
    checked.complete(false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(MediaSendSheet), findsNothing);
    expect(attached, isEmpty);
    expect(wrongRoomChecks, 0);
  });

  phoneTest(
      'Android share, Add, File and keyboard media retain one composer review',
      (tester) async {
    final shares = StreamController<List<PendingFileAttachment>>();
    addTearDown(() {
      unawaited(shares.close());
    });
    final priorPicker = ImagePickerPlatform.instance;
    addTearDown(() => ImagePickerPlatform.instance = priorPicker);
    final picker = _Picker();
    ImagePickerPlatform.instance = picker;
    final shared = file('shared.png');
    await pump(tester,
        keyboard: 0,
        shares: shares.stream,
        check: (candidate) async => candidate.name != 'rejected.png');
    shares.add([shared, file('rejected.png')]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byKey(const ValueKey('phone-media-review')), findsOneWidget);
    expect(find.byKey(inputKey), findsOneWidget);
    final review =
        tester.state<MediaSendSheetState>(find.byType(MediaSendSheet));
    expect(review.files, [same(shared)]);
    await tester.tap(find.byKey(const ValueKey('media-send-add')));
    await tester.pump();
    expect(review.files, [same(shared)], reason: 'Cancel keeps the batch');
    picker.media = [
      XFile.fromData(photo, path: '/added.png', mimeType: 'image/png')
    ];
    await tester.tap(find.byKey(const ValueKey('media-send-add')));
    await tester.pump();
    await tester.pump();
    await state(tester).onKeyboardContentInserted(
        const KeyboardInsertedContent(mimeType: 'text/plain', uri: ''));
    await state(tester).onKeyboardContentInserted(KeyboardInsertedContent(
        mimeType: 'image/png', uri: 'content://image', data: photo));
    await tester.pump();
    final filePicker = _Files();
    FilePicker.platform = filePicker;
    await state(tester).pickFiles();
    expect(review.files, hasLength(3));
    filePicker.result = FilePickerResult([
      PlatformFile(name: 'file.png', bytes: photo, size: photo.length),
    ]);
    await state(tester).pickFiles();
    await tester.pump();
    expect(review.files.map((file) => file.name),
        ['shared.png', 'added.png', 'image.png', 'file.png']);
    expect(attached, isEmpty);
  });

  phoneTest('iOS camera cancellation and return preserve the draft',
      (tester) async {
    final priorPicker = ImagePickerPlatform.instance;
    addTearDown(() => ImagePickerPlatform.instance = priorPicker);
    final picker = _Picker();
    ImagePickerPlatform.instance = picker;
    await pump(tester, keyboard: 0);
    await tester.enterText(find.byKey(inputKey), '@dar');
    await state(tester).captureFromCamera(video: false);
    await tester.pump();
    expect(find.byType(MediaSendSheet), findsNothing);
    picker.camera =
        XFile.fromData(photo, path: '/camera.png', mimeType: 'image/png');
    unawaited(state(tester).captureFromCamera(video: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byKey(const ValueKey('phone-media-review')), findsOneWidget);
    expect(find.byKey(inputKey), findsOneWidget);
    expect(state(tester).controller.text, '@dar');
    expect(find.byType(MediaSendSheet), findsOneWidget);
  }, platform: TargetPlatform.iOS);

  phoneTest('inline trim failure keeps the caption and enables recovery',
      (tester) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(VideoTrimJob.channel, (_) async => true);
    addTearDown(
        () => messenger.setMockMethodCallHandler(VideoTrimJob.channel, null));
    final editor = VideoTrimAction.editor;
    addTearDown(() => VideoTrimAction.editor = editor);
    final file = PendingFileAttachment(
        name: 'clip.mp4',
        mimeType: 'video/mp4',
        data: photo,
        size: photo.length)
      ..thumbnailFile = photo;
    VideoTrimAction.editor = (_, original, __) async => VideoTrimEdit(
        original.snapshotForSend(),
        PendingFileAttachment(
          name: 'trim.mp4',
          mimeType: 'video/mp4',
          size: 3,
          data: Uint8List(2),
        )..thumbnailFile = photo,
        1,
        2);
    await pump(tester, keyboard: 0);
    await open(tester, [file]);
    expect(find.byKey(const ValueKey('phone-media-review')), findsOneWidget);
    expect(find.byKey(inputKey), findsOneWidget);
    final review = tester.widget<MediaSendSheet>(find.byType(MediaSendSheet));
    expect(review.room, same(client.getRoom(roomId)));
    await tester.enterText(find.byKey(inputKey), 'Keep this caption');
    final input = state(tester);
    await tester.tap(find.byKey(const ValueKey('video-trim')));
    await tester.pump();
    expect(input.controller.text, 'Keep this caption');
    await tester.runAsync(() =>
        tester.state<MediaSendSheetState>(find.byType(MediaSendSheet)).send());
    await tester.pump();
    expect(attached, isEmpty);
    expect(
        find.text(
            'The trimmed video could not be read. Reset trim or try again.'),
        findsOneWidget);
    expect(input.controller.text, 'Keep this caption');
    await tester.tap(find.byKey(const ValueKey('video-trim-reset')));
    await tester.pump();
    expect(file.name, 'clip.mp4');
    expect(input.controller.text, 'Keep this caption');
    expect(tester.takeException(), isNull);
  });

  phoneTest('prefix suggestions use the effective account in the shared room',
      (tester) async {
    final other = await tester.runAsync(() async {
      final value = await signedInClient('prefix-${serial++}');
      await sync(value, join: {roomId: joined(roomId)});
      value.getMatrixClient().getRoomById(roomId)!.states['m.room.member'] = {
        '@dan:example.org': matrix.StrippedStateEvent(
            type: 'm.room.member',
            stateKey: '@dan:example.org',
            senderId: me,
            content: {'membership': 'join', 'displayname': 'Dan'}),
      };
      return value;
    });
    addTearDown(() => other!.getMatrixClient().dispose(closeDatabase: true));
    await pump(tester, overrideAccount: other);
    await open(tester);
    await tester.enterText(find.byKey(inputKey), 'other @da');
    await tester.pump();
    await tester.pump();
    expect(find.text(reporter), findsNothing);
    expect(find.text('@dan:example.org'), findsOneWidget);
    expect((state(tester).controller as RichTextEditingController).room,
        same(other!.getRoom(roomId)));
    await tester.tap(find.text('Dan'));
    await tester.pump();
    expect(state(tester).controller.text, 'other @dan:example.org ');
    await pump(tester, overrideAccount: other, editing: true);
    expect(find.byType(MediaSendSheet), findsNothing);
    expect(attached, isEmpty);
    await tester.enterText(find.byKey(inputKey), 'other @da');
    await tester.pump();
    await tester.pump();
    expect((state(tester).controller as RichTextEditingController).room,
        same(client.getRoom(roomId)));
  });

  phoneTest('another room/account cannot receive an old review or suggestion',
      (tester) async {
    await pump(tester);
    await open(tester);
    await tester.enterText(find.byKey(inputKey), '@dar');
    await tester.pump();
    final other = await tester.runAsync(() async {
      final value = await signedInClient('other-${serial++}');
      await sync(value, join: {roomId: joined(roomId)});
      return value;
    });
    addTearDown(() => other!.getMatrixClient().dispose(closeDatabase: true));
    await pump(tester, account: other);
    expect(find.byType(MediaSendSheet), findsNothing);
    expect(find.byKey(const ValueKey('composer-autofill-card')), findsNothing);
    expect(attached, isEmpty);
    expect(sent, isEmpty);
  });
}
