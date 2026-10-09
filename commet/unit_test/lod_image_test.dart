import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:commet/utils/image/lod_image.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

// 1x1 PNG
final png = base64Decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==");

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ui.Codec> decode(ui.ImmutableBuffer buffer,
          {ui.TargetImageSize Function(int, int)? getTargetSize}) =>
      PaintingBinding.instance.instantiateImageCodecWithSize(buffer);

  test("a failed load stays contained and the next fetch retries", () async {
    var calls = 0;
    var fail = true;
    var completer = LODImageCompleter(
      callback: decode,
      autoLoadFullres: false,
      loadThumbnail: () async {
        calls++;
        if (fail) throw Exception("M_NOT_FOUND: Local media not found");
        return Uint8List.fromList(png);
      },
    );

    ImageInfo? shown;
    Object? streamError;
    completer.addListener(ImageStreamListener(
      (image, _) => shown = image,
      onError: (e, _) => streamError = e,
    ));

    // the constructor's load fails; no uncaught error, nothing shown
    await completer.fetchThumbnail();
    await Future.delayed(Duration.zero);
    expect(calls, 1);
    expect(shown, isNull);
    expect(streamError, isNull, reason: "not reported to the stream");
    expect(completer.thumbnailLoading, isNull,
        reason: "a failed load must not stay cached as in flight");

    // the media comes back: the next fetch loads it
    fail = false;
    await completer.fetchThumbnail();
    expect(calls, 2);
    expect(shown, isNotNull);
    expect(completer.currentlyLoadedImage, LODImageType.thumbnail);
  });

  test("a corrupt image is contained too", () async {
    var completer = LODImageCompleter(
      callback: decode,
      autoLoadFullres: true,
      loadFullRes: () async => Uint8List.fromList([1, 2, 3, 4]),
    );
    await completer.fetchFullRes();
    expect(completer.currentlyLoadedImage, isNull);
    expect(completer.fullResLoading, isNull);
  });

  // Vommet: the completer above recovers when fetched again, but the
  // sticker picker never fetches: it resolves the provider, and Flutter's
  // image cache handed back the same empty completer, so a sticker whose
  // first load failed stayed blank until restart.
  test("a failed image is evicted, so the next resolve loads it again",
      () async {
    var calls = 0;
    var fail = true;
    var provider = LODImageProvider(
      id: "lod-test-evict",
      autoLoadFullRes: true,
      loadFullRes: () async {
        calls++;
        if (fail) throw Exception("M_LIMIT_EXCEEDED");
        return Uint8List.fromList(png);
      },
    );

    Future<ImageInfo?> resolve() async {
      var shown = Completer<ImageInfo?>();
      var stream = provider.resolve(ImageConfiguration.empty);
      var listener = ImageStreamListener((image, _) {
        if (!shown.isCompleted) shown.complete(image);
      });
      stream.addListener(listener);
      var image = await shown.future
          .timeout(const Duration(seconds: 2), onTimeout: () => null);
      stream.removeListener(listener);
      return image;
    }

    expect(await resolve(), isNull);
    expect(calls, 1);
    expect(PaintingBinding.instance.imageCache.containsKey("lod-test-evict"),
        isFalse);

    fail = false;
    expect(await resolve(), isNotNull);
    expect(calls, 2);
  });

  test("nothing-loaded fires only once every load has failed", () async {
    var thumbnail = Completer<Uint8List?>();
    var fired = 0;
    var completer = LODImageCompleter(
      callback: decode,
      autoLoadFullres: true,
      onNothingLoaded: () => fired++,
      loadThumbnail: () => thumbnail.future,
      loadFullRes: () async => throw Exception("502"),
    );
    await Future.delayed(const Duration(milliseconds: 50));
    expect(fired, 0, reason: "the thumbnail is still loading");

    thumbnail.complete(Uint8List.fromList(png));
    await completer.fetchThumbnail();
    await Future.delayed(Duration.zero);
    expect(fired, 0, reason: "the thumbnail loaded");
    expect(completer.currentlyLoadedImage, LODImageType.thumbnail);

    var failing = LODImageCompleter(
      callback: decode,
      autoLoadFullres: true,
      onNothingLoaded: () => fired++,
      loadThumbnail: () async => throw Exception("502"),
      loadFullRes: () async => throw Exception("502"),
    );
    await failing.fetchFullRes();
    await Future.delayed(const Duration(milliseconds: 50));
    expect(fired, 1);
  });

  test("a blank image retries on its own while it's still shown", () async {
    var calls = 0;
    var completer = LODImageCompleter(
      callback: decode,
      autoLoadFullres: false,
      loadThumbnail: () async {
        calls++;
        if (calls == 1) throw Exception("network hiccup");
        return Uint8List.fromList(png);
      },
    );

    ImageInfo? shown;
    completer.addListener(ImageStreamListener((image, _) => shown = image));

    // the first load fails and nothing is shown...
    await Future.delayed(const Duration(milliseconds: 200));
    expect(calls, 1);
    expect(shown, isNull);

    // ...and without anyone asking again, it retries and shows the image
    await Future.delayed(const Duration(milliseconds: 2500));
    expect(calls, 2);
    expect(shown, isNotNull);
    expect(completer.currentlyLoadedImage, LODImageType.thumbnail);
  });
}
