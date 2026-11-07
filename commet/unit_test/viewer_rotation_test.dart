// Vommet issue 1216: drive the real viewer and local preference writes.
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:commet/cache/file_provider.dart';
import 'package:commet/client/attachment.dart';
import 'package:commet/client/matrix/matrix_mxc_image_provider.dart';
import 'package:commet/client/member.dart';
import 'package:commet/client/room.dart';
import 'package:commet/client/timeline.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:commet/config/layout_style.dart';
import 'package:commet/config/preferences.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/lightbox.dart';
import 'package:commet/ui/atoms/lightbox_full_screen.dart';
import 'package:commet/ui/atoms/lightbox_gallery.dart';
import 'package:commet/utils/media_spoiler.dart';
import 'package:commet/utils/private_files/sign_out_wipe.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:matrix/matrix.dart' as mx;
import 'package:shared_preferences/shared_preferences.dart';

class _Account extends Fake implements mx.Client {
  _Account(this.userID);
  @override
  String? userID;
  @override
  Uri get homeserver => Uri.parse('https://example.org/');
  @override
  bool isLogged() => true;
}

Uint8List picture({bool exif = false}) {
  final image = img.Image(width: 240, height: 120);
  img.fill(image, color: img.ColorRgb8(52, 99, 142));
  img.fillRect(image,
      x1: 0, y1: 0, x2: 79, y2: 119, color: img.ColorRgb8(240, 182, 75));
  img.drawString(image, 'UP',
      font: img.arial24, x: 110, y: 12, color: img.ColorRgb8(255, 255, 255));
  if (exif) image.exif.imageIfd.orientation = 6;
  return Uint8List.fromList(exif ? img.encodeJpg(image) : img.encodePng(image));
}

class _Source extends MatrixMxcImage {
  _Source(mx.Client account, String media, {bool exif = false})
      : decoded = MemoryImage(picture(exif: exif)),
        super(Uri.parse('mxc://example.org/$media'), account,
            doThumbnail: false, doFullres: false);
  final MemoryImage decoded;
  @override
  ImageProvider forViewer() => decoded;
}

// Dependencies only: a platform preference write that remains in flight.
class _DelayedPreferences extends Fake implements SharedPreferences {
  final values = <String, Object>{};
  final writes = <Completer<bool>>[];

  @override
  Object? get(String key) => values[key];

  @override
  Future<bool> setInt(String key, int value) {
    values[key] = value;
    final write = Completer<bool>();
    writes.add(write);
    return write.future;
  }
}

class _PreferencesWithDelayedWrites extends Preferences {
  final delayed = _DelayedPreferences();

  @override
  SharedPreferences get vommetSharedPreferences => delayed;
}

class _ControlledImage extends ImageProvider<_ControlledImage> {
  final frames = _ControlledFrames();

  @override
  Future<_ControlledImage> obtainKey(ImageConfiguration configuration) async =>
      this;

  @override
  void resolveStreamForKey(
    ImageConfiguration configuration,
    ImageStream stream,
    _ControlledImage key,
    ImageErrorListener handleError,
  ) {
    stream.setCompleter(frames);
  }
}

class _ControlledFrames extends ImageStreamCompleter {
  bool get listening => hasListeners;

  void fail(Object error) => reportError(exception: error, silent: true);
}

class _File extends Fake implements FileProvider {}

class _Member extends Fake implements Member {
  @override
  String get displayName => 'Alexandria with a very long display name';
}

class _Room extends Fake implements Room {
  @override
  Member getMemberOrFallback(String id) => _Member();
}

class _Message extends Fake implements TimelineEventMessage {
  _Message(this.eventId, ImageProvider image)
      : attachments = [
          ImageAttachment(image, _File(),
              name: 'photo.png', mimeType: 'image/png')
        ];
  @override
  final String eventId;
  @override
  final List<Attachment> attachments;
  @override
  String get senderId => '@alex:example.org';
  @override
  TimelineEventStatus get status => TimelineEventStatus.sending;
}

class _Timeline extends Fake implements Timeline {
  _Timeline(this.events);
  @override
  final List<TimelineEvent> events;
  @override
  final room = _Room();
  @override
  bool get canLoadHistory => false;
  @override
  final onEventAdded = StreamController<int>.broadcast(sync: true);
  @override
  final onChange = StreamController<int>.broadcast(sync: true);
  @override
  final onRemove = StreamController<int>.broadcast(sync: true);
  Future<void> close() async {
    await onEventAdded.close();
    await onChange.close();
    await onRemove.close();
  }
}

final left = find.byKey(const ValueKey('viewer_rotate_-1'));
final right = find.byKey(const ValueKey('viewer_rotate_1'));
final menu = find.byKey(const ValueKey('lightbox_menu_button'));
Finder get shownViewer => find.byType(InteractiveViewer).hitTestable().first;
Finder get shownImage =>
    find.descendant(of: shownViewer, matching: find.byType(Image)).first;
int turns(WidgetTester t) => t
    .widget<RotatedBox>(find
        .descendant(of: shownViewer, matching: find.byType(RotatedBox))
        .first)
    .quarterTurns;
TransformationController transform(WidgetTester t) =>
    t.widget<InteractiveViewer>(shownViewer).transformationController!;
Rect imageBounds(WidgetTester t) {
  final box = t.renderObject<RenderBox>(shownImage);
  return MatrixUtils.transformRect(
      box.getTransformTo(null), Offset.zero & box.size);
}

Future<void> open(WidgetTester t, ImageProvider image,
    {Size size = const Size(1280, 800),
    double textScale = 1,
    Widget? viewer}) async {
  if (image is _Source) {
    await t.runAsync(
        () => image.decoded.resolve(const ImageConfiguration()).firstImage());
  }
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  await t.pumpWidget(MaterialApp(
      theme: ThemeData(
          brightness: Brightness.dark,
          platform:
              size.width < 600 ? TargetPlatform.android : TargetPlatform.linux),
      home: MediaQuery(
          data: MediaQueryData(
              size: size, textScaler: TextScaler.linear(textScale)),
          child: viewer ?? Lightbox(image: image))));
  await t.pumpAndSettle();
}

Future<void> turn(WidgetTester t, Finder button) async {
  expect(button.hitTestable(), findsOneWidget);
  await t.tap(button.hitTestable());
  await t.pumpAndSettle();
}

Future<void> reset(WidgetTester t) async {
  await t.tap(menu);
  await t.pumpAndSettle();
  await t.tap(find.text('Reset rotation'));
  await t.pumpAndSettle();
}

void main() {
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    preferences = Preferences();
    await preferences.init();
    await preferences.autoRotateImages.set(false);
    LightboxSystemBars.supported = () => false;
  });
  tearDown(() {
    LightboxFullScreen.exit();
  });

  for (final style in LayoutStyle.values) {
    for (final size in [
      const Size(390, 844),
      const Size(320, 568),
      const Size(1280, 800)
    ]) {
      testWidgets('$style $size four turns, reset, missing metadata and layout',
          (t) async {
        addTearDown(t.view.reset);
        await pickLayoutStyle(style);
        final source = _Source(_Account('@a:example.org'), 'landscape');
        await open(t, source, size: size, textScale: size.width == 320 ? 2 : 1);
        final base = imageBounds(t);
        for (var i = 1; i <= 4; i++) {
          await turn(t, right);
          expect(turns(t), i % 4);
          final bounds = imageBounds(t);
          expect(bounds.height > bounds.width, i.isOdd);
          expect(t.takeException(), isNull);
        }
        for (var i = 1; i <= 4; i++) {
          await turn(t, left);
          expect(turns(t), (4 - i) % 4);
        }
        await turn(t, left);
        expect(turns(t), 3);
        await reset(t);
        expect(turns(t), 0);
        expect(imageBounds(t).size, base.size);
        await t.tap(menu);
        await t.pumpAndSettle();
        final resetItem = find.ancestor(
          of: find.text('Reset rotation'),
          matching: find.byType(PopupMenuItem<String>),
        );
        expect(t.widget<PopupMenuItem<String>>(resetItem).enabled, isFalse);
        Navigator.of(t.element(resetItem)).pop();
        await t.pumpAndSettle();
        final prefs = await SharedPreferences.getInstance();
        expect(
            prefs
                .getKeys()
                .where((k) => k.startsWith('vommet_viewer_rotation.')),
            isEmpty);
      });
    }
  }

  testWidgets(
      'reopen, reconstructed provider, shared media and account isolation',
      (t) async {
    addTearDown(t.view.reset);
    final a = _Account('@a:example.org'), b = _Account('@b:example.org');
    await open(t, _Source(a, 'shared'));
    await turn(t, right);
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
    // Reconstruct both source and session: no dependency on event/page/cache keys.
    await open(t, _Source(_Account('@a:example.org'), 'shared'));
    expect(turns(t), 1);
    expect(imageBounds(t).height, greaterThan(imageBounds(t).width));
    await t.pumpWidget(const SizedBox());
    await open(t, _Source(b, 'shared'));
    expect(turns(t), 0);
    await turn(t, left);
    expect(turns(t), 3);
    await t.pumpWidget(const SizedBox());
    await open(t, _Source(a, 'reuploaded'));
    expect(turns(t), 0);
    await turn(t, right);
    await reset(t);
    await t.pumpWidget(const SizedBox());
    await open(t, _Source(a, 'shared'));
    expect(turns(t), 1);
    await reset(t);
    await t.pumpWidget(const SizedBox());
    await open(t, _Source(b, 'shared'));
    expect(turns(t), 3);
    final prefs = await SharedPreferences.getInstance();
    final key = prefs
        .getKeys()
        .singleWhere((k) => k.startsWith('vommet_viewer_rotation.'));
    await prefs.setInt(key, 99);
    await t.pumpWidget(const SizedBox());
    await open(t, _Source(b, 'shared'));
    expect(turns(t), 0);
    expect(prefs.containsKey(key), isFalse);
  });

  testWidgets('gallery switch and grid retain only each image correction',
      (t) async {
    addTearDown(t.view.reset);
    final a = _Source(_Account('@a:example.org'), 'a');
    final b = _Source(a.client, 'b');
    final timeline = _Timeline([_Message(r'$b', b), _Message(r'$a', a)]);
    addTearDown(timeline.close);
    await open(t, a,
        viewer: LightboxGallery(timeline: timeline, initialKey: r'$a/0'));
    await turn(t, right);
    expect(turns(t), 1);
    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(10, 100));
    await mouse.moveTo(const Offset(20, 110));
    await t.pump();
    await t.tap(find.byIcon(Icons.chevron_right).hitTestable());
    await t.pumpAndSettle();
    expect(turns(t), 0);
    await turn(t, left);
    expect(turns(t), 3);
    await mouse.moveTo(const Offset(25, 115));
    await t.pump();
    await t.tap(find.byIcon(Icons.chevron_left).hitTestable());
    await t.pumpAndSettle();
    expect(turns(t), 1);
    await t.tap(find.text('Show media grid'));
    await t.pumpAndSettle();
    expect(turns(t), 1);
    await t.tap(find.text('Hide media grid'));
    await t.pumpAndSettle();
    expect(turns(t), 1);
    await mouse.removePointer();
    expect(t.takeException(), isNull);
  });

  testWidgets('turn cancels zoom tween, pan, and context rotation restores fit',
      (t) async {
    addTearDown(t.view.reset);
    await open(t, _Source(_Account('@a:example.org'), 'zoom'));
    await turn(t, right);
    await t.tap(find.byKey(const ValueKey('lightbox_zoom_in')));
    await t.pump(const Duration(milliseconds: 50));
    // The context menu stays reachable while the visible chrome fades out.
    await t.longPress(shownImage);
    await t.pumpAndSettle();
    await t.tap(find.text('Rotate left 90°'));
    await t.pumpAndSettle();
    expect(turns(t), 0);
    expect(transform(t).value, Matrix4.identity());
    await t.tap(shownImage);
    await t.pumpAndSettle();
    expect(transform(t).value.getMaxScaleOnAxis(), greaterThan(1));
    final beforePan = transform(t).value.getTranslation();
    await t.drag(shownViewer, const Offset(-35, 20));
    await t.pumpAndSettle();
    expect(transform(t).value.getTranslation().x, lessThan(beforePan.x));
    await t.tap(shownImage,
        kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await t.pumpAndSettle();
    await t.tap(find.text('Rotate right 90°'));
    await t.pumpAndSettle();
    expect(turns(t), 1);
    expect(transform(t).value, Matrix4.identity());
    await t.tap(shownImage);
    await t.pumpAndSettle();
    expect(transform(t).value.getMaxScaleOnAxis(), greaterThan(1));
  });

  testWidgets(
      'EXIF-decoded base composes auto-fit/manual and fullscreen independently',
      (t) async {
    addTearDown(t.view.reset);
    await preferences.layoutOverride.set('mobile');
    await preferences.autoRotateImages.set(true);
    final source = _Source(_Account('@a:example.org'), 'exif', exif: true);
    await open(t, source, size: const Size(390, 844));
    final image = await t.runAsync(
        () => source.decoded.resolve(const ImageConfiguration()).firstImage());
    expect(image!.height, greaterThan(image.width),
        reason: 'EXIF 6 decoded upright once');
    await turn(t, right);
    expect(turns(t), 1);
    await turn(t, right);
    expect(turns(t), 2);
    await reset(t);
    expect(turns(t), 0);
    await t.pumpWidget(const SizedBox());
    await open(t, _Source(source.client, 'landscape'),
        size: const Size(390, 844));
    expect(turns(t), 1,
        reason: 'existing aspect-fit for landscape on portrait');
    await turn(t, right);
    expect(turns(t), 2, reason: 'fit must not cancel the manual turn');
    LightboxFullScreen.isWindowFullScreen = () async => false;
    LightboxFullScreen.setWindowFullScreen = (_) async {};
    LightboxFullScreen.enter();
    await t.pumpAndSettle();
    expect(turns(t), 1);
    LightboxFullScreen.exit();
    await t.pumpAndSettle();
    expect(turns(t), 2);
  });

  testWidgets('portrait pixels remain visible after turns on an explicit phone',
      (t) async {
    addTearDown(t.view.reset);
    final source = _Source(_Account('@a:example.org'), 'portrait', exif: true);
    final boundary = GlobalKey();
    await open(t, source,
        size: const Size(390, 844),
        viewer: RepaintBoundary(key: boundary, child: Lightbox(image: source)));
    for (final button in [left, right, right, left]) {
      await turn(t, button);
      final point = imageBounds(t).center;
      final color = await t.runAsync(() async {
        final render = boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 1);
        final bytes =
            await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        final offset = (point.dy.floor() * image.width + point.dx.floor()) * 4;
        final rgb = [for (var i = 0; i < 3; i++) bytes!.getUint8(offset + i)];
        image.dispose();
        return rgb;
      });
      for (var i = 0; i < 3; i++) {
        expect(color![i], closeTo([52, 99, 142][i], 8),
            reason:
                'the image must paint, not only keep a plausible bounding box');
      }
    }
  });

  testWidgets('anonymous pictures are session-only; custom/non-image unchanged',
      (t) async {
    addTearDown(t.view.reset);
    final image = MemoryImage(picture());
    await open(t, image);
    await turn(t, right);
    await t.pumpWidget(const SizedBox());
    await open(t, image);
    expect(turns(t), 0);
    await t.pumpWidget(const SizedBox());
    await open(t, image,
        viewer: Lightbox(customWidget: const Text('Custom preview')));
    expect(find.text('Custom preview'), findsOneWidget);
    expect(right, findsNothing);
    await open(t, image,
        viewer: Lightbox(video: _File(), thumbnail: image, closing: true));
    expect(right, findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(
        prefs.getKeys().where((k) => k.startsWith('vommet_viewer_rotation.')),
        isEmpty);
  });

  testWidgets(
      'sign-out invalidates queued writes and active leases, preserving other account',
      (t) async {
    addTearDown(t.view.reset);
    final a = _Account('@a:example.org'), b = _Account('@b:example.org');
    final first = _Source(a, 'shared');
    await open(t, _Source(b, 'shared'));
    await turn(t, left);
    await t.pumpWidget(const SizedBox());
    await open(t, first);
    await turn(t, right);
    // Dynamic access keeps the regression runnable on the base: it first fails
    // on absent real controls, rather than a missing feature API at compile time.
    final dynamic rotations = (preferences as dynamic).viewerRotations;
    final dynamic lease = rotations.acquire(first);
    lease.turn(1);
    a.userID = null;
    final wipe = Function.apply(SignOutWipe.new, [], {
      #sweepCopies: () async {},
      #clearViewerRotations: () => rotations.forgetAccount(a) as Future<void>,
    }) as SignOutWipe;
    await wipe.run();
    lease.turn(1);
    lease.release();
    await t.pumpAndSettle();
    expect(turns(t), 0);
    await t.pumpWidget(const SizedBox());
    await open(t, _Source(b, 'shared'));
    expect(turns(t), 3);
    await t.pumpWidget(const SizedBox());
    await open(t, _Source(_Account('@a:example.org'), 'shared'));
    expect(turns(t), 0);
  });

  testWidgets('reopening while equal-angle writes queue shows the newest turn',
      (t) async {
    addTearDown(t.view.reset);
    final prefs = _PreferencesWithDelayedWrites();
    preferences = prefs;
    await prefs.init();
    final account = _Account('@a:example.org');
    await open(t, _Source(account, 'delayed'));
    await turn(t, right);
    await turn(t, right);
    await turn(t, left);
    expect(turns(t), 1);
    expect(prefs.delayed.writes, hasLength(1));
    await t.pumpWidget(const SizedBox());

    prefs.delayed.writes[0].complete(true);
    await t.pump();
    expect(prefs.delayed.writes, hasLength(2));
    await open(t, _Source(account, 'delayed'));
    expect(turns(t), 1,
        reason: 'the middle write must not mask the latest turn');

    prefs.delayed.writes[1].completeError(StateError('fixture write failed'));
    await t.pump();
    expect(prefs.delayed.writes, hasLength(3));
    prefs.delayed.writes[2].complete(true);
    await t.pumpAndSettle();
    expect(prefs.delayed.values.values, [1]);
  });

  for (final failDecode in [false, true]) {
    testWidgets(
        'routed image turns and releases metadata after '
        '${failDecode ? 'decode failure' : 'dismissal while loading'}',
        (t) async {
      addTearDown(t.view.reset);
      final image = _ControlledImage();
      addTearDown(image.frames.keepAlive().dispose);
      await open(t, image,
          size: const Size(320, 568),
          textScale: 2,
          viewer: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Lightbox.show(context, image: image),
                child: const Text('Open photo'),
              ),
            ),
          ));
      await t.tap(find.text('Open photo'));
      await t.pumpAndSettle();
      await turn(t, right);
      expect(turns(t), 1);
      expect(image.frames.listening, isTrue);
      if (failDecode) {
        final error = StateError('fixture image failed to decode');
        image.frames.fail(error);
        await t.pump();
        expect(find.text(error.toString()), findsOneWidget);
        await turn(t, left);
        expect(turns(t), 0);
      }
      Navigator.of(t.element(find.byType(Lightbox))).pop();
      await t.pumpAndSettle();
      expect(find.byType(Lightbox), findsNothing);
      expect(image.frames.listening, isFalse);
    });
  }

  testWidgets('spoiler rotation cannot receive focus until revealed',
      (t) async {
    addTearDown(t.view.reset);
    final image = _Source(_Account('@a:example.org'), 'spoiler');
    final message = _Message(r'$spoiler', image);
    final spoiler = MediaSpoiler(key: message.eventId);
    (message.attachments.single as ImageAttachment).spoiler = spoiler;
    addTearDown(() => MediaSpoilerReveal.hide(spoiler.key));
    final timeline = _Timeline([message]);
    addTearDown(timeline.close);
    await open(t, image,
        size: const Size(320, 568),
        textScale: 2,
        viewer: LightboxGallery(timeline: timeline, initialKey: r'$spoiler/0'));
    expect(right, findsOneWidget);
    expect(right.hitTestable(), findsNothing);
    final icon =
        find.descendant(of: right, matching: find.byIcon(Icons.rotate_right));
    final node = Focus.of(t.element(icon));
    node.requestFocus();
    await t.pump();
    expect(node.hasFocus, isFalse);
    expect(find.byType(InteractiveViewer), findsNothing);

    await t.tap(find.text('Spoiler · Tap to reveal').first);
    await t.pumpAndSettle();
    await turn(t, right);
    expect(turns(t), 1);
  });
}

extension on ImageStream {
  Future<ui.Image> firstImage() {
    final result = Completer<ui.Image>();
    late ImageStreamListener listener;
    listener = ImageStreamListener((image, _) {
      removeListener(listener);
      result.complete(image.image);
    });
    addListener(listener);
    return result.future;
  }
}
