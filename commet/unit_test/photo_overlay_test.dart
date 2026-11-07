// Vommet issue 1056: still-photo loading, composition and manipulation.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:commet/cache/file_cache.dart';
import 'package:commet/client/components/emoticon/dynamic_emoticon_pack.dart';
import 'package:commet/client/components/emoticon/emoji_pack.dart';
import 'package:commet/client/components/emoticon/emoticon.dart';
import 'package:commet/client/components/emoticon/emoticon_component.dart';
import 'package:commet/client/components/room_component.dart';
import 'package:commet/client/room.dart';
import 'package:commet/client/matrix/components/emoticon/matrix_emoticon.dart';
import 'package:commet/client/matrix/matrix_media_failures.dart';
import 'package:commet/config/layout_style.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/emoji_widget.dart';
import 'package:commet/ui/organisms/attachment_crop/attachment_crop.dart';
import 'package:commet/ui/organisms/attachment_crop/image_markup.dart';
import 'package:commet/ui/organisms/attachment_crop/photo_overlay_asset.dart';
import 'package:commet/ui/organisms/attachment_crop/photo_overlay_canvas.dart';
import 'package:commet/ui/organisms/attachment_crop/photo_overlay_picker.dart';
import 'package:commet/utils/emoji/unicode_emoji.dart';
import 'package:crop_image/crop_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show FontLoader, rootBundle, LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix/matrix_api_lite/generated/fixed_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

Uint8List png(int w, int h, [img.Color? color]) =>
    img.encodePng(img.Image(width: w, height: h, numChannels: 4)
      ..clear(color ?? img.ColorRgba8(200, 40, 40, 255)));
Uint8List fixture(String name) =>
    File('unit_test/fixtures/photo_overlays/$name').readAsBytesSync();
Future<ui.Image> pixels(Uint8List bytes) => decodeImageFromList(bytes);

class _Sdk extends Fake implements matrix.Client {
  Uint8List bytes = png(900, 600);
  Object? error;
  int calls = 0;
  @override
  String get userID => '@overlay:example.org';
  @override
  Future<FileResponse> getContent(String serverName, String mediaId,
      {bool? allowRemote, int? timeoutMs, bool? allowRedirect}) async {
    expect([serverName, mediaId], ['example.org', 'overlay']);
    calls++;
    if (error != null) throw error!;
    return FileResponse(data: bytes);
  }
}

class _Cache extends Fake implements FileCache {
  Uint8List? bytes;
  @override
  Future<bool> hasFile(String identifier, {bool sensitive = false}) async =>
      bytes != null;
  @override
  Future<Uint8List?> readFile(String identifier,
      {bool sensitive = false}) async {
    expect(identifier, 'matrix-mxc://example.org/overlay');
    return bytes;
  }

  @override
  Future<void> writeFile(String identifier, Uint8List value,
      {bool sensitive = false}) async {
    expect(identifier, 'matrix-mxc://example.org/overlay');
    bytes = value;
  }
}

class _OtherImage extends Fake implements Emoticon {
  @override
  ImageProvider get image => MemoryImage(png(2, 2));
}

class _Packs extends Fake implements RoomEmoticonComponent {
  _Packs(this.pack);
  final EmoticonPack pack;
  @override
  List<EmoticonPack> get availableStickers => [pack];
  @override
  List<EmoticonPack> get availableEmoji => [];
}

class _Room extends Fake implements Room {
  _Room(this.packs);
  final RoomEmoticonComponent packs;
  @override
  T? getComponent<T extends RoomComponent>() => packs as T;
}

Future<void> tap(WidgetTester t, Finder finder) async {
  await t.tap(finder);
  await t.pumpAndSettle();
}

Future<Completer<ui.Image?>> openPicker(
    WidgetTester t, Future<ui.Image> Function(Emoticon) load,
    {Room? room, ImageProvider? preview}) async {
  final result = Completer<ui.Image?>();
  await t.pumpWidget(MaterialApp(
      theme: ThemeDark.theme.copyWith(platform: TargetPlatform.android),
      home: Builder(
          builder: (context) => TextButton(
              onPressed: () async => result.complete(await showDialog<ui.Image>(
                  context: context,
                  builder: (_) => Dialog(
                      child: SizedBox(
                          width: 600,
                          height: 500,
                          child: PhotoOverlayPicker(
                              room: room, loadAsset: load))))),
              child: const Text('open')))));
  if (preview != null)
    await t.runAsync(
        () => precacheImage(preview, t.element(find.byType(TextButton))));
  await tap(t, find.text('open'));
  return result;
}

void main() {
  setUp(() async {
    // unit_test/ is outside the SDK's recognized test/ directory.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });
  testWidgets('Matrix original bytes, cache, errors and unsupported providers',
      (t) async {
    final previousCache = fileCache,
        previousFailures = MatrixMediaFailures.instance;
    final cache = _Cache(), client = _Sdk();
    fileCache = cache;
    addTearDown(() {
      fileCache = previousCache;
      MatrixMediaFailures.instance = previousFailures;
    });
    final sticker = MatrixEmoticon(
        Uri.parse('mxc://example.org/overlay'), client,
        packUsage: EmoticonUsage.sticker,
        shortcode: 'overlay',
        usage: EmoticonUsage.sticker);
    await t.runAsync(() async {
      for (var i = 0; i < 2; i++) {
        final image = await PhotoOverlayAsset.load(sticker);
        expect([image.width, image.height], [900, 600],
            reason: 'original, not the 512px picker preview');
        image.dispose();
      }
      expect(client.calls, 1);
      expect(cache.bytes, same(client.bytes));
      for (final code in ['M_NOT_FOUND', 'M_LIMIT_EXCEEDED']) {
        cache.bytes = null;
        MatrixMediaFailures.instance = MatrixMediaFailures();
        client.error = matrix.MatrixException.fromJson(
            {'errcode': code, 'error': 'fixture', 'retry_after_ms': 60000});
        final before = client.calls;
        await expectLater(
            PhotoOverlayAsset.load(sticker), throwsA(same(client.error)));
        expect(client.calls, before + 1,
            reason: 'one load, no automatic recovery loop');
        if (code == 'M_NOT_FOUND') {
          await expectLater(
              PhotoOverlayAsset.load(sticker), throwsA(same(client.error)));
          expect(client.calls, before + 1,
              reason: 'permanent media failure is cached');
        }
      }
      cache.bytes = fixture('animated.webp');
      await expectLater(PhotoOverlayAsset.load(sticker), throwsFormatException);
      await expectLater(
          PhotoOverlayAsset.load(_OtherImage()), throwsFormatException);
    });
    final calls = client.calls;
    await t.pump(const Duration(minutes: 2));
    expect(client.calls, calls);
  });

  testWidgets(
      'encoded and engine frame checks reject animation and unknown formats',
      (t) async {
    await t.runAsync(() async {
      for (final bytes in [
        fixture('still.webp'),
        png(8, 8),
        img.encodeJpg(img.Image(width: 8, height: 8))
      ]) {
        final image = await PhotoOverlayAsset.decode(bytes);
        expect(image.width, 8);
        image.dispose();
      }
      for (final file in ['animated.png', 'animated.webp']) {
        expect(PhotoOverlayAsset.isStill(fixture(file)), isFalse);
        await expectLater(
            PhotoOverlayAsset.decode(fixture(file)), throwsFormatException);
      }
      await expectLater(PhotoOverlayAsset.decode(Uint8List.fromList([1, 2, 3])),
          throwsFormatException);
    });
  });

  testWidgets(
      'emoji rasterization exports color glyphs and joined/skin-tone sequences',
      (t) async {
    await t.runAsync(() async {
      await (FontLoader('EmojiFont')
            ..addFont(
                rootBundle.load('assets/font/emoji-font/TwemojiCOLR.otf')))
          .load();
      for (final text in ['🙂', '👍🏽', '👩‍💻']) {
        final image = await PhotoOverlayAsset.load(UnicodeEmoticon(text));
        final data =
            (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
                .buffer
                .asUint8List();
        expect(
            [for (var i = 3; i < data.length; i += 4) data[i]]
                .any((a) => a > 0),
            isTrue);
        expect(
            [
              for (var i = 0; i < data.length; i += 4)
                if (data[i + 3] > 0) data[i] != data[i + 1]
            ].any((v) => v),
            isTrue,
            reason: 'a color emoji, not a monochrome missing-glyph box');
        image.dispose();
      }
    });
  });

  testWidgets(
      'overlays survive crop/rotation, export encoding, and interleaved undo',
      (t) async {
    await t.runAsync(() async {
      final source = await pixels(png(100, 60));
      final sticker = await PhotoOverlayAsset.decode(
          png(20, 10, img.ColorRgba8(20, 60, 240, 255)));
      final markup = ImageMarkup();
      markup.add(MarkupRedaction(const Rect.fromLTWH(.1, .1, .2, .2)));
      final e = MarkupOverlay(sticker, const Rect.fromLTWH(.4, .4, .2, .1));
      markup.add(e);
      final old = e.rect;
      markup.transformOverlay(e, e.rect.shift(const Offset(.2, 0)),
          before: old);
      markup.removeOverlay(e);
      markup.undo();
      expect(markup.edits.last, same(e));
      markup.undo();
      expect(e.rect, old);
      final output = await AttachmentCrop.render(source, markup.edits,
          crop: const Rect.fromLTRB(.1, .1, .9, .9),
          rotation: CropRotation.right);
      expect([output.width, output.height], [48, 80]);
      final encoded = await AttachmentCrop.encodeCropped(output, 'photo.png');
      final decoded = img.decodePng(encoded.data)!;
      expect(decoded.any((p) => p.b > 200 && p.r < 50), isTrue);
      expect(decoded.any((p) => p.r == 0 && p.g == 0 && p.b == 0), isTrue);
      expect(decoded.exif.isEmpty, isTrue);
      expect(decoded.textData, isNull);
      final jpeg = await AttachmentCrop.encodeCropped(output, 'photo.jpg');
      expect(jpeg.mimeType, 'image/jpeg');
      markup.undo();
      expect(markup.edits.whereType<MarkupOverlay>(), isEmpty);
      final plain = await AttachmentCrop.render(source, markup.edits,
          crop: const Rect.fromLTRB(0, 0, 1, 1), rotation: CropRotation.up);
      final plainData = img.decodePng(
          (await AttachmentCrop.encodeCropped(plain, 'photo.png')).data)!;
      expect(plainData.any((p) => p.b > 200), isFalse);
      markup.clear();
      markup.undo();
      expect(markup.edits, isEmpty);
      source.dispose();
      output.dispose();
      plain.dispose();
      markup.dispose();
    });
  });

  for (final style in LayoutStyle.values) {
    for (final size in [const Size(360, 800), const Size(1280, 900)]) {
      testWidgets(
          '${style.name}: add, drag, resize, remove, undo and cancel on $size',
          (t) async {
        await pickLayoutStyle(style);
        await preferences.layoutOverride
            .set(size.width < 600 ? "mobile" : "desktop");
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final controller = CropController();
        addTearDown(controller.dispose);
        final bytes = png(400, 300);
        late ui.Image sticker;
        await t.runAsync(() async {
          sticker = await pixels(png(40, 20, img.ColorRgba8(20, 60, 240, 255)));
          await UnicodeEmojis.load();
        });
        addTearDown(sticker.dispose);
        await t.pumpWidget(MaterialApp(
            theme: ThemeDark.theme.copyWith(
                platform: size.width < 600
                    ? TargetPlatform.android
                    : TargetPlatform.linux),
            home: Scaffold(body: SizedBox())));
        await t.runAsync(() => precacheImage(
            MemoryImage(bytes), t.element(find.byType(Scaffold))));
        await t.pumpWidget(MaterialApp(
            theme: ThemeDark.theme.copyWith(
                platform: size.width < 600
                    ? TargetPlatform.android
                    : TargetPlatform.linux),
            home: Scaffold(
                body: AttachmentCropView(bytes, controller, 4 / 3,
                    overlayLoader: (_) async => sticker.clone(),
                    onDone: (image) {
                      image.dispose();
                      throw StateError('fixture export error');
                    }))));
        await t.pumpAndSettle();
        expect(Theme.of(t.element(find.byType(AttachmentCropView))).platform,
            size.width < 600 ? TargetPlatform.android : TargetPlatform.linux);
        await tap(t, find.text('Stickers'));
        await tap(t, find.text('Add'));
        expect(find.text(PhotoOverlayPicker.empty), findsOneWidget);
        await tap(t, find.text('Emoji'));
        await tap(t, find.byType(EmojiWidget).first);
        expect(find.byType(PhotoOverlayPicker), findsNothing);
        final canvas =
            t.widget<PhotoOverlayCanvas>(find.byType(PhotoOverlayCanvas));
        final e = canvas.markup.edits.whereType<MarkupOverlay>().single;
        final old = e.rect;
        final body = find.byKey(ValueKey(e));
        await t.drag(body, const Offset(100, 0));
        await t.pumpAndSettle();
        expect(e.rect.left, greaterThan(old.left));
        final canceledBefore = e.rect;
        final gesture = await t.startGesture(t.getCenter(body));
        await gesture.moveBy(const Offset(60, 0));
        await t.pump();
        expect(e.rect, isNot(canceledBefore));
        await gesture.cancel();
        await t.pumpAndSettle();
        expect(e.rect, canceledBefore);
        final previous = e.rect;
        await t.drag(
            find.byWidgetPredicate((w) =>
                w is Semantics &&
                w.properties.label == PhotoOverlayCanvas.resize),
            const Offset(60, 30));
        await t.pumpAndSettle();
        expect(e.rect.width, greaterThan(previous.width));
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pumpAndSettle();
        expect(
            t
                .widget<TextButton>(find.widgetWithText(TextButton, 'Remove'))
                .onPressed,
            isNull);
        await tap(t, body);
        await t.sendKeyEvent(LogicalKeyboardKey.delete);
        await t.pumpAndSettle();
        expect(canvas.markup.edits, isEmpty);
        await tap(t, find.byTooltip('Undo'));
        await tap(t, find.text('Remove'));
        expect(canvas.markup.edits, isEmpty);
        await tap(t, find.byTooltip('Undo'));
        expect(canvas.markup.edits.single, same(e));
        final sizeBefore = e.rect;
        await tap(t, find.byType(Slider));
        expect(e.rect.width, isNot(sizeBefore.width));
        await tap(t, find.byTooltip('Undo'));
        expect(e.rect, sizeBefore);
        // Crop/rotation and photo zoom must preserve the overlay coordinate system.
        await tap(t, find.byTooltip('Undo'));
        await tap(t, find.byTooltip('Undo'));
        controller.rotateRight();
        await t.pumpAndSettle();
        await tap(t, body);
        final rotated = e.rect;
        await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await t.pumpAndSettle();
        expect(e.rect.center.dy, lessThan(rotated.center.dy));
        await tap(t, find.byTooltip('Zoom in'));
        final zoomedBefore = e.rect;
        await t.drag(body, const Offset(60, 0));
        await t.pumpAndSettle();
        expect(e.rect.center.dy, lessThan(zoomedBefore.center.dy));
        final viewportCenter = t.getCenter(find.byKey(canvas.viewport));
        final zoomBefore = canvas.zoom.value.getMaxScaleOnAxis(),
            rectBeforePinch = e.rect;
        final one = await t.startGesture(viewportCenter - const Offset(20, 0),
            pointer: 31);
        final two = await t.startGesture(viewportCenter + const Offset(20, 0),
            pointer: 32);
        await two.moveBy(const Offset(40, 0));
        await t.pump();
        expect(canvas.zoom.value.getMaxScaleOnAxis(), greaterThan(zoomBefore));
        expect(e.rect, rectBeforePinch);
        await one.up();
        await two.up();
        await t.pumpAndSettle();
        final trackpad =
            await t.createGesture(kind: ui.PointerDeviceKind.trackpad);
        final beforeTrackpad = canvas.zoom.value.getMaxScaleOnAxis();
        await trackpad.panZoomStart(viewportCenter);
        await trackpad.panZoomUpdate(viewportCenter, scale: 1.1);
        await t.pump();
        expect(
            canvas.zoom.value.getMaxScaleOnAxis(), greaterThan(beforeTrackpad));
        await trackpad.panZoomEnd();
        await t.runAsync(() async {
          final dynamic editor = t.state(find.byType(AttachmentCropView));
          await editor.done();
        });
        await t.pumpAndSettle();
        expect(
            find.text(
                "Couldn't export this picture. Your edits are kept; try Done again."),
            findsOneWidget);
        expect(canvas.markup.edits.whereType<MarkupOverlay>(), hasLength(1));
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets(
      'animated base disables Add while crop draw and redact stay available',
      (t) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await preferences.layoutOverride.set('mobile');
    final controller = CropController();
    addTearDown(controller.dispose);
    final bytes = fixture('animated.png');
    await t.pumpWidget(MaterialApp(
        theme: ThemeDark.theme.copyWith(platform: TargetPlatform.android),
        home: Scaffold(
            body: AttachmentCropView(bytes, controller, 1,
                onDone: (image) => image.dispose()))));
    // Animated precache waits for a scheduled frame; let the real codec run,
    // then advance bounded frames instead of awaiting a settling animation.
    await t.runAsync(() async => (await pixels(bytes)).dispose());
    await t.pump(const Duration(milliseconds: 300));
    expect(controller.getImage(), isNotNull);
    await t.tap(find.text('Stickers'));
    await t.pump(const Duration(milliseconds: 300));
    expect(
        find.text(
            'Overlays are available for still JPEG, PNG and WebP photos.'),
        findsOneWidget);
    expect(
        t
            .widget<TextButton>(find.ancestor(
                of: find.text('Add'),
                matching: find.byWidgetPredicate((w) => w is TextButton)))
            .onPressed,
        isNull);
    for (final tool in ['Crop', 'Draw', 'Redact']) {
      await t.tap(find.text(tool));
      await t.pump(const Duration(milliseconds: 300));
      expect(
          t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, tool)).selected,
          isTrue);
    }
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('picker keeps load error, retries, and never sends', (t) async {
    var loads = 0;
    final sdk = _Sdk();
    final sticker = MatrixEmoticon(Uri.parse('mxc://example.org/overlay'), sdk,
        packUsage: EmoticonUsage.sticker,
        shortcode: 'overlay',
        usage: EmoticonUsage.sticker);
    final previous = fileCache;
    fileCache = _Cache()..bytes = sdk.bytes;
    addTearDown(() => fileCache = previous);
    late ui.Image image;
    await t.runAsync(() async {
      await UnicodeEmojis.load();
      image = await pixels(png(10, 10));
    });
    final result = await openPicker(t, (picked) async {
      expect(picked, same(sticker));
      if (++loads == 1) throw const FormatException('load failed');
      return image;
    },
        room: _Room(_Packs(DynamicEmoticonPack(
            emoticons: [sticker],
            displayName: 'Room pack',
            identifier: 'fixture-pack',
            usage: EmoticonUsage.sticker,
            icon: Icons.star))),
        preview: sticker.image);
    expect(find.text('Room pack'), findsWidgets);
    await tap(t, find.byType(EmojiWidget).first);
    expect(find.text('load failed'), findsOneWidget);
    expect(find.text('Send'), findsNothing);
    await tap(t, find.text('Retry'));
    expect(await result.future, same(image));
    image.dispose();
  });
  testWidgets(
      'covered picker recovers; cancel disposes late loads without closing parent',
      (t) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await preferences.layoutOverride.set('mobile');
    await pickLayoutStyle(LayoutStyle.discord);
    var pending = Completer<ui.Image>();
    var loads = 0;
    late ui.Image image;
    await t.runAsync(() async {
      await UnicodeEmojis.load();
      image = await pixels(png(10, 10));
    });
    addTearDown(() {
      if (!image.debugDisposed) image.dispose();
    });
    final result = await openPicker(t, (_) {
      loads++;
      return pending.future;
    });
    await tap(t, find.text('Emoji'));
    await t.tap(find.byType(EmojiWidget).first);
    await t.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await t.tap(find.byType(EmojiWidget).first, warnIfMissed: false);
    expect(loads, 1);
    final navigator = Navigator.of(t.element(find.byType(PhotoOverlayPicker)));
    unawaited(navigator.push<void>(MaterialPageRoute(
        builder: (_) => const Scaffold(body: Text('cover')))));
    await t.pump();
    await t.pump(const Duration(milliseconds: 350));
    pending.complete(image);
    await t.pump();
    navigator.pop();
    await t.pump();
    await t.pump(const Duration(milliseconds: 350));
    expect(image.debugDisposed, isTrue);
    expect(find.byType(LinearProgressIndicator), findsNothing,
        reason: 'a covered picker must recover when it becomes current again');
    await t.pumpAndSettle();
    pending = Completer<ui.Image>();
    await t.runAsync(() async {
      image = await pixels(png(10, 10));
    });
    await t.tap(find.byType(EmojiWidget).first);
    await t.pump();
    expect(loads, 2);
    await t.tap(find.text('Cancel'));
    await t.pump();
    pending.complete(image);
    await t.pumpAndSettle();
    expect(await result.future, isNull);
    expect(image.debugDisposed, isTrue);
    expect(find.text('open'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
