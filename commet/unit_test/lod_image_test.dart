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

    // A failed load is never reported to the stream, so "nothing shown" can
    // only be a wait: the failure itself is microtasks only (no decode), so
    // it's done before any timer, and half a second stays well clear of the
    // completer's own 2 s retry. A load that succeeds waits for the image,
    // however long a busy machine takes to decode it.
    Future<ImageInfo?> resolve(Duration wait) async {
      var shown = Completer<ImageInfo?>();
      var stream = provider.resolve(ImageConfiguration.empty);
      var listener = ImageStreamListener((image, _) {
        if (!shown.isCompleted) shown.complete(image);
      });
      stream.addListener(listener);
      var image = await shown.future.timeout(wait, onTimeout: () => null);
      stream.removeListener(listener);
      return image;
    }

    expect(await resolve(const Duration(milliseconds: 500)), isNull);
    expect(calls, 1);
    expect(PaintingBinding.instance.imageCache.containsKey("lod-test-evict"),
        isFalse);

    fail = false;
    expect(await resolve(const Duration(seconds: 30)), isNotNull);
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

    // Waits for the image instead of a fixed 2.7 s: the retry fires after
    // 2 s, but the decode that follows runs in the engine on real time, and
    // on a loaded CI box it took longer than the 0.7 s that was left.
    final watch = Stopwatch()..start();
    var shown = Completer<ImageInfo>();
    completer.addListener(ImageStreamListener((image, _) {
      if (!shown.isCompleted) shown.complete(image);
    }));

    // the first load fails and nothing is shown...
    await Future.delayed(const Duration(milliseconds: 200));
    expect(calls, 1);
    expect(shown.isCompleted, isFalse);

    // ...and without anyone asking again, it retries and shows the image
    await shown.future.timeout(const Duration(seconds: 30));
    // the LOD is recorded right after the frame goes out (microtasks only)
    await Future.delayed(Duration.zero);
    expect(calls, 2);
    expect(watch.elapsed, greaterThanOrEqualTo(const Duration(seconds: 2)),
        reason: "the first retry waits its 2 s");
    expect(completer.currentlyLoadedImage, LODImageType.thumbnail);
  });

  // Vommet issue 337: a picture whose thumbnail load failed kept showing
  // its blurhash, because the blurhash counted as "something shown" and the
  // retry above never ran.
  test("a picture stuck on its blurhash retries the thumbnail", () async {
    var calls = 0;
    var completer = LODImageCompleter(
      callback: decode,
      autoLoadFullres: false,
      blurhash: "LEHV6nWB2yk8pyo0adR*.7kCMdnj",
      loadThumbnail: () async {
        calls++;
        if (calls == 1) {
          // fails after the blurhash is up, like a slow homeserver
          await Future.delayed(const Duration(milliseconds: 100));
          throw Exception("timed out");
        }
        return Uint8List.fromList(png);
      },
    );

    var sharp = Completer<void>();
    completer.addListener(ImageStreamListener((image, _) {
      // the LOD is recorded right after the frame goes out
      Future.delayed(Duration.zero, () {
        if (completer.currentlyLoadedImage == LODImageType.thumbnail &&
            !sharp.isCompleted) {
          sharp.complete();
        }
      });
    }));

    await Future.delayed(const Duration(milliseconds: 300));
    expect(calls, 1);
    expect(completer.currentlyLoadedImage, LODImageType.blurhash);

    await sharp.future.timeout(const Duration(seconds: 30));
    expect(calls, 2);
  });
}
