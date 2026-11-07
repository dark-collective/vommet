import 'dart:async';

import 'package:commet/utils/transcription_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final android in [false, true]) {
    for (final width in [32, 64]) {
      for (final compiled in [false, true]) {
        test(
            'loaded capability wins on Android=$android $width-bit compiled=$compiled',
            () {
          final runtime = TranscriptionRuntime(
            initialized: () => true,
            isAndroid: () => android,
            androidCanRetry: () => width == 64,
            compiledSupport: () => compiled,
          );
          expect(runtime.available, compiled);
        });
      }
    }
  }

  for (final android in [false, true]) {
    for (final width in [32, 64]) {
      test('unloaded Android=$android $width-bit support uses the ABI fallback',
          () {
        final runtime = TranscriptionRuntime(
          initialized: () => false,
          isAndroid: () => android,
          androidCanRetry: () => width == 64,
          compiledSupport: () => throw StateError('bridge is unloaded'),
        );
        expect(runtime.available, !android || width == 64);
      });
    }
  }

  test('an already loaded bridge is reused', () async {
    final runtime = TranscriptionRuntime(
      initialized: () => true,
      initialize: () => throw StateError('must reuse the loaded bridge'),
    );
    await runtime.prepare();
  });

  test('concurrent callers share a load and a later caller reuses it',
      () async {
    var initialized = false;
    var calls = 0;
    final load = Completer<void>();
    final runtime = TranscriptionRuntime(
      initialized: () => initialized,
      initialize: () {
        calls++;
        return load.future;
      },
    );
    final first = runtime.prepare();
    final second = runtime.prepare();
    expect(calls, 1);
    initialized = true;
    load.complete();
    await Future.wait([first, second]);
    await runtime.prepare();
    expect(calls, 1);
  });

  test('a failed load reaches every caller and a later request can retry',
      () async {
    var calls = 0;
    var initialized = false;
    final loads = [Completer<void>(), Completer<void>()];
    final runtime = TranscriptionRuntime(
      initialized: () => initialized,
      isAndroid: () => true,
      androidCanRetry: () => true,
      compiledSupport: () => true,
      initialize: () => loads[calls++].future,
    );
    final first = expectLater(runtime.prepare(), throwsStateError);
    final second = expectLater(runtime.prepare(), throwsStateError);
    expect(calls, 1);
    loads[0].completeError(StateError('library load failed'));
    await Future.wait([first, second]);
    expect(runtime.available, isTrue);
    final retry = runtime.prepare();
    expect(calls, 2);
    initialized = true;
    loads[1].complete();
    await retry;
    expect(runtime.available, isTrue);
  });

  test('32-bit Android remains unavailable after a failed bridge load',
      () async {
    final runtime = TranscriptionRuntime(
      initialized: () => false,
      isAndroid: () => true,
      androidCanRetry: () => false,
      initialize: () => Future.error(StateError('missing native library')),
    );
    expect(runtime.available, isFalse);
    await expectLater(runtime.prepare(), throwsStateError);
    expect(runtime.available, isFalse);
  });
}
