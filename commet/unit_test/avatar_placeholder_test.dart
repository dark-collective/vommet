import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

// An avatar whose image never arrives, fails, or is already loaded. Keyed by
// [id] so two instances for different users compare unequal.
class _TestAvatarImage extends ImageProvider<_TestAvatarImage> {
  _TestAvatarImage.pending(this.id)
      : image = null,
        fails = false;
  _TestAvatarImage.failing(this.id)
      : image = null,
        fails = true;
  _TestAvatarImage.loaded(this.id, ui.Image this.image) : fails = false;

  final String id;
  final ui.Image? image;
  final bool fails;
  final completer = _NeverLoadsCompleter();

  @override
  Future<_TestAvatarImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
      _TestAvatarImage key, ImageDecoderCallback decode) {
    if (image != null) {
      return OneFrameImageStreamCompleter(
          SynchronousFuture(ImageInfo(image: image!)));
    }
    return completer;
  }

  @override
  bool operator ==(Object other) =>
      other is _TestAvatarImage && other.id == id && other.fails == fails;

  @override
  int get hashCode => Object.hash(id, fails);
}

// Never delivers a frame unless told to fail (like a download that failed).
class _NeverLoadsCompleter extends ImageStreamCompleter {
  void fail() => reportError(exception: Exception("avatar failed to load"));
}

Widget _avatar(ImageProvider image, String name) => MaterialApp(
      home: Scaffold(
        body: tiamat.Avatar(
            image: image, placeholderText: name, placeholderColor: Colors.red),
      ),
    );

void main() {
  setUp(() {
    PaintingBinding.instance.imageCache.clear();
  });

  testWidgets("shows the letter placeholder while the avatar loads",
      (tester) async {
    await tester.pumpWidget(_avatar(_TestAvatarImage.pending("@bob"), "Bob"));
    expect(find.text("B"), findsOneWidget);
  });

  testWidgets("shows the letter placeholder when the avatar fails to load",
      (tester) async {
    final avatar = _TestAvatarImage.failing("@bob");
    await tester.pumpWidget(_avatar(avatar, "Bob"));
    avatar.completer.fail();
    await tester.pump();
    expect(find.text("B"), findsOneWidget);
  });

  testWidgets("a reused avatar never keeps the previous user's image",
      (tester) async {
    final image = await tester.runAsync(() => createTestImage());

    await tester
        .pumpWidget(_avatar(_TestAvatarImage.loaded("@me", image!), "Me"));
    await tester.pump();
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);

    // Same tree position, another user whose avatar never loads (like a
    // reused autocomplete row).
    await tester.pumpWidget(_avatar(_TestAvatarImage.pending("@bob"), "Bob"));
    await tester.pump();
    expect(find.text("B"), findsOneWidget);
    expect(
        tester
            .widgetList<RawImage>(find.byType(RawImage))
            .where((i) => i.image != null),
        isEmpty);
  });
}
