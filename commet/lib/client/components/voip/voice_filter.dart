import 'dart:ffi' as ffi;

import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/rust/frb_generated.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;

/// Mirrors `VommetVoiceStats` in rust/voice/src/lib.rs.
final class _VoiceStats extends ffi.Struct {
  @ffi.Uint64()
  external int framesProcessed;
  @ffi.Uint64()
  external int framesBypassed;
  @ffi.Int32()
  external int lastSampleRate;
  @ffi.Float()
  external double lastVoiceProbability;
  @ffi.Uint8()
  external int engine;
  @ffi.Uint8()
  external int autoChoice;
  @ffi.Uint8()
  external int demoted;
  @ffi.Uint8()
  external int reserved;
  @ffi.Float()
  external double dfn3AverageUs;
  @ffi.Float()
  external double benchmarkP90Us;
}

class VoiceFilterStats {
  final int framesProcessed;
  final int framesBypassed;
  final int lastSampleRate;

  /// 0 none, 1 RNNoise, 2 DeepFilterNet3.
  final int engine;
  final int autoChoice;
  final bool demoted;
  final double dfn3AverageUs;
  final double benchmarkP90Us;

  const VoiceFilterStats(
      this.framesProcessed,
      this.framesBypassed,
      this.lastSampleRate,
      this.engine,
      this.autoChoice,
      this.demoted,
      this.dfn3AverageUs,
      this.benchmarkP90Us);
}

class _Native {
  final void Function(int) setMode;
  final void Function(double) setGain;
  final int Function() mode;
  final int Function() processFn;
  final void Function(ffi.Pointer<_VoiceStats>) stats;

  _Native(ffi.DynamicLibrary lib)
      : setMode = lib.lookupFunction<ffi.Void Function(ffi.Uint8),
            void Function(int)>('vommet_voice_set_mode'),
        setGain = lib.lookupFunction<ffi.Void Function(ffi.Float),
            void Function(double)>('vommet_voice_set_gain'),
        mode = lib.lookupFunction<ffi.Uint8 Function(), int Function()>(
            'vommet_voice_mode'),
        processFn = lib.lookupFunction<ffi.UintPtr Function(), int Function()>(
            'vommet_voice_process_fn'),
        stats = lib.lookupFunction<ffi.Void Function(ffi.Pointer<_VoiceStats>),
            void Function(ffi.Pointer<_VoiceStats>)>('vommet_voice_stats');
}

/// Microphone noise suppression, run by our Rust code (rust/voice) inside
/// libwebrtc's capture pipeline, after WebRTC's own processing.
///
/// Modes: "off", "standard" (RNNoise), "best" (DeepFilterNet3) and "auto",
/// which benchmarks DeepFilterNet3 once in the background and uses it when the
/// device has room, falling back to RNNoise during a call if it runs late.
/// Off unless the "Noise suppression" experiment is enabled.
///
/// Desktop needs the Vommet flutter_webrtc fork, which adds the
/// `setCapturePostProcessor` method; Android uses flutter_webrtc's own
/// AudioProcessingController through the vommet_voice plugin. Either way the
/// processor is installed once and then only re-moded.
class VoiceFilter {
  static const modes = ["off", "standard", "best", "auto"];

  static bool get isSupported =>
      PlatformUtils.isLinux ||
      PlatformUtils.isWindows ||
      PlatformUtils.isAndroid;

  static bool get isEnabled =>
      isSupported && preferences.experimentNoiseSuppression.value;

  /// Whether to ask libwebrtc for its own noise suppressor. Ours replaces it:
  /// on audio WebRTC already suppressed, DeepFilterNet3's DNSMOS overall
  /// score drops from 3.17 to 2.57. Applies when the microphone is opened, so
  /// a change mid-call takes full effect on the next call.
  static bool get useWebrtcNoiseSuppression =>
      !isEnabled || preferences.voipNoiseSuppression.value == "off";

  /// Vommet: the microphone volume runs in the same processor, after noise
  /// suppression, so it works with or without the noise suppression
  /// experiment.
  static bool get supportsVolume => isSupported;

  static double get microphoneVolume =>
      supportsVolume && preferences.experimentQuickProfileControls.value
          ? preferences.voipMicrophoneVolume.value
          : 1.0;

  static const _android = MethodChannel("im.nether.vommet/voice_filter");

  static _Native? _native;
  static bool _installed = false;

  static Future<_Native?> _load() async {
    if (_native != null) return _native;
    try {
      final ffi.DynamicLibrary lib;
      if (PlatformUtils.isAndroid) {
        lib = ffi.DynamicLibrary.open("libvommet_voice.so");
      } else {
        // On desktop the voice filter is linked into the Rust library.
        lib = (await loadExternalLibrary(
                RustLib.kDefaultExternalLibraryLoaderConfig))
            .ffiDynamicLibrary;
      }
      _native = _Native(lib);
    } catch (e, s) {
      Log.onError(e, s, content: "Could not load the voice filter");
    }
    return _native;
  }

  static int _modeCode(String mode) {
    final i = modes.indexOf(mode);
    return i < 0 ? 0 : i;
  }

  /// Sets the filter to the stored mode (or [mode]), installing it into
  /// libwebrtc the first time it's needed. Call it once libwebrtc is up, e.g.
  /// right before opening the microphone.
  ///
  /// [experimentEnabled] overrides the experiment toggle (for tests).
  static Future<void> apply({String? mode, bool? experimentEnabled}) async {
    if (!isSupported) return;
    final enabled = experimentEnabled ?? isEnabled;
    final code =
        enabled ? _modeCode(mode ?? preferences.voipNoiseSuppression.value) : 0;
    final gain = microphoneVolume;
    final needed = code != 0 || gain != 1.0;
    if (!needed && _native == null) return;

    final native = await _load();
    if (native == null) return;
    native.setMode(code);
    native.setGain(gain);

    if (_installed || !needed) return;
    try {
      if (PlatformUtils.isAndroid) {
        _installed = await _android.invokeMethod<bool>("install") ?? false;
      } else {
        await webrtc.WebRTC.invokeMethod('setCapturePostProcessor', {
          'function': native.processFn(),
          'userData': 0,
        });
        _installed = true;
      }
      Log.i("Voice filter installed: $_installed");
    } catch (e, s) {
      Log.onError(e, s, content: "Could not install the voice filter");
    }
  }

  static VoiceFilterStats? stats() {
    final native = _native;
    if (native == null) return null;
    final p = calloc<_VoiceStats>();
    try {
      native.stats(p);
      final s = p.ref;
      return VoiceFilterStats(
          s.framesProcessed,
          s.framesBypassed,
          s.lastSampleRate,
          s.engine,
          s.autoChoice,
          s.demoted != 0,
          s.dfn3AverageUs,
          s.benchmarkP90Us);
    } finally {
      calloc.free(p);
    }
  }

  static const _engines = ["none", "RNNoise", "DeepFilterNet3"];

  static String describeStats() {
    final s = stats();
    final native = _native;
    if (s == null || native == null) return "not loaded";
    String engine(int e) => e < _engines.length ? _engines[e] : "$e";
    return "mode=${modes[native.mode().clamp(0, modes.length - 1)]} "
        "installed=$_installed engine=${engine(s.engine)} "
        "auto=${engine(s.autoChoice)} demoted=${s.demoted} "
        "processed=${s.framesProcessed} bypassed=${s.framesBypassed} "
        "rate=${s.lastSampleRate} "
        "dfn3_avg=${s.dfn3AverageUs.toStringAsFixed(0)}us "
        "bench_p90=${s.benchmarkP90Us.toStringAsFixed(0)}us";
  }
}
