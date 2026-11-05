// Web side of CameraBackgroundBlur: loads web/vommet_blur/vommet_blur.js on
// first use and wraps its window.vommetBlur as a LiveKit track processor.

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:dart_webrtc/dart_webrtc.dart' show MediaStreamTrackWeb;
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:web/web.dart' as web;

extension type _VommetBlur(JSObject _) implements JSObject {
  external bool isSupported();
  external JSPromise<_BlurHandle> create(web.MediaStreamTrack track,
      int blurRadius, int slowFrameMs, JSFunction onSlow);
}

extension type _BlurHandle(JSObject _) implements JSObject {
  external web.MediaStreamTrack get track;
  external JSPromise<JSAny?> destroy();
}

bool browserSupported() =>
    globalContext.has('VideoFrame') && globalContext.has('OffscreenCanvas');

Future<_VommetBlur?>? _loading;

Future<_VommetBlur?> _load() => _loading ??= _loadScript();

Future<_VommetBlur?> _loadScript() async {
  if (!globalContext.has('vommetBlur')) {
    final script =
        web.document.createElement('script') as web.HTMLScriptElement;
    script.type = 'module';
    script.src = 'vommet_blur/vommet_blur.js';
    final loaded = Completer<bool>();
    script.onload = ((web.Event _) => loaded.complete(true)).toJS;
    script.onerror = ((web.Event _) => loaded.complete(false)).toJS;
    web.document.head!.appendChild(script);
    if (!await loaded.future) {
      _loading = null;
      return null;
    }
  }
  final blur = globalContext['vommetBlur'] as JSObject?;
  if (blur == null) return null;
  final api = _VommetBlur(blur);
  return api.isSupported() ? api : null;
}

Future<lk.TrackProcessor<lk.VideoProcessorOptions>?> createBlurProcessor(
    {required int blurRadius,
    required int slowFrameMs,
    required void Function() onSlow}) async {
  final api = await _load();
  if (api == null) return null;
  return _BlurProcessor(api, blurRadius, slowFrameMs, onSlow);
}

class _BlurProcessor extends lk.TrackProcessor<lk.VideoProcessorOptions> {
  _BlurProcessor(this._api, this.blurRadius, this.slowFrameMs, this.onSlow);

  final _VommetBlur _api;
  final int blurRadius;
  final int slowFrameMs;
  final void Function() onSlow;

  _BlurHandle? _handle;
  rtc.MediaStreamTrack? _processed;

  @override
  String get name => 'vommet-background-blur';

  @override
  Future<void> init(lk.VideoProcessorOptions options) async {
    final source = options.track;
    if (source is! MediaStreamTrackWeb) {
      throw StateError('background blur needs a browser camera track');
    }
    final handle = await _api
        .create(source.jsTrack, blurRadius, slowFrameMs, onSlow.toJS)
        .toDart;
    _handle = handle;
    _processed = MediaStreamTrackWeb(handle.track);
  }

  @override
  Future<void> restart(lk.VideoProcessorOptions options) async {
    await destroy();
    await init(options);
  }

  @override
  Future<void> destroy() async {
    final handle = _handle;
    _handle = null;
    _processed = null;
    if (handle != null) await handle.destroy().toDart;
  }

  @override
  Future<void> onPublish(lk.Room room) async {}

  @override
  Future<void> onUnpublish() async {}

  @override
  rtc.MediaStreamTrack? get processedTrack => _processed;
}
