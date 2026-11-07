import 'dart:ffi' as ffi;

import 'package:commet/client/components/voip/voice_filter_demotion.dart';
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
  @ffi.Uint64()
  external int framesResampled;
}

/// Mirrors `VommetAgcStats` in rust/voice/src/lib.rs.
final class _AgcStats extends ffi.Struct {
  @ffi.Uint64()
  external int frames;
  @ffi.Float()
  external double gainDb;
  @ffi.Float()
  external double speechLevelDbfs;
  @ffi.Float()
  external double noiseDbfs;
  @ffi.Float()
  external double headroomDb;
  @ffi.Uint8()
  external int enabled;
  @ffi.Uint8()
  external int confident;
  @ffi.Array(6)
  external ffi.Array<ffi.Uint8> reserved;
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

  /// Of [framesProcessed], the blocks libwebrtc delivered at another rate
  /// than 48 kHz, which the filter resampled for the engines.
  final int framesResampled;

  /// Why [demoted]: 1 DeepFilterNet3 ran too slow, 2 its output stayed
  /// silent on a speaking input (the Windows Voice Capture DSP's 16 kHz
  /// stream); 0 when not demoted.
  final int demoteReason;

  const VoiceFilterStats(
      this.framesProcessed,
      this.framesBypassed,
      this.lastSampleRate,
      this.engine,
      this.autoChoice,
      this.demoted,
      this.dfn3AverageUs,
      this.benchmarkP90Us,
      this.framesResampled,
      [this.demoteReason = 0]);
}

class _Native {
  final void Function(int) setMode;
  final void Function(double) setGain;
  final int Function() mode;
  final int Function() processFn;
  final void Function(ffi.Pointer<_VoiceStats>) stats;
  final void Function(int) setAgc;
  final void Function(ffi.Pointer<_AgcStats>) agcStats;

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
            void Function(ffi.Pointer<_VoiceStats>)>('vommet_voice_stats'),
        setAgc = lib.lookupFunction<ffi.Void Function(ffi.Uint8),
            void Function(int)>('vommet_voice_set_agc'),
        agcStats = lib.lookupFunction<ffi.Void Function(ffi.Pointer<_AgcStats>),
            void Function(ffi.Pointer<_AgcStats>)>('vommet_voice_agc_stats');
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
      supportsVolume ? preferences.voipMicrophoneVolume.value : 1.0;

  /// Vommet (issue 868): on Linux and Windows, libwebrtc's automatic gain
  /// control is AGC1 in analog mode, which only works by moving the system
  /// microphone volume, and the native audio path never lets it, so quiet or
  /// distant speech came out quieter and muffled. There our processor runs
  /// AGC2's adaptive digital controller instead (rust/voice/src/agc.rs), the
  /// one Chrome uses, and libwebrtc's stays off. Android keeps libwebrtc's.
  static bool get ownsAutoGainControl =>
      PlatformUtils.isLinux || PlatformUtils.isWindows;

  static bool get _autoGainControl =>
      preferences.experimentAutoGainControl.value;

  /// Whether to ask libwebrtc for its own automatic gain control.
  static bool get useWebrtcAutoGainControl =>
      _autoGainControl && !ownsAutoGainControl;

  static const _android = MethodChannel("im.nether.vommet/voice_filter");

  static _Native? _native;
  static bool _installed = false;

  /// Whether the processor is in libwebrtc's capture pipeline (it stays
  /// there once installed; "off" only re-modes it).
  static bool get installed => _installed;

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

  /// Whether the processor has to be in libwebrtc's pipeline: noise
  /// suppression, a volume other than 100 %, or automatic gain control.
  static bool processorNeeded(int modeCode, double gain, bool agc) =>
      modeCode != 0 || gain != 1.0 || agc;

  static int _modeCode(String mode) {
    final i = modes.indexOf(mode);
    return i < 0 ? 0 : i;
  }

  /// Sets the filter to the stored mode (or [mode]), installing it into
  /// libwebrtc the first time it's needed. Call it once libwebrtc is up, e.g.
  /// right before opening the microphone.
  ///
  /// [experimentEnabled] overrides the experiment toggle and
  /// [autoGainControl] the automatic gain control setting (for tests).
  /// Automatic gain control follows its setting mid-call too.
  static Future<void> apply(
      {String? mode, bool? experimentEnabled, bool? autoGainControl}) async {
    if (!isSupported) return;
    final enabled = experimentEnabled ?? isEnabled;
    final code =
        enabled ? _modeCode(mode ?? preferences.voipNoiseSuppression.value) : 0;
    final gain = microphoneVolume;
    final agc = ownsAutoGainControl && (autoGainControl ?? _autoGainControl);
    final needed = processorNeeded(code, gain, agc);
    if (!needed && _native == null) return;

    final native = await _load();
    if (native == null) return;
    native.setMode(code);
    native.setGain(gain);
    native.setAgc(agc ? 1 : 0);

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
      if (agc && !_installed) {
        // libwebrtc's AGC isn't asked for on this platform either.
        Log.w("Automatic gain control is on but the voice filter isn't "
            "installed, so the microphone isn't leveled");
      }
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
          s.benchmarkP90Us,
          s.framesResampled,
          s.demoted);
    } finally {
      calloc.free(p);
    }
  }

  /// Automatic gain control state, or null before the filter loaded.
  static ({
    int frames,
    bool enabled,
    bool confident,
    double gainDb,
    double speechLevelDbfs,
    double noiseDbfs,
    double headroomDb
  })? agcStats() {
    final native = _native;
    if (native == null) return null;
    final p = calloc<_AgcStats>();
    try {
      native.agcStats(p);
      final s = p.ref;
      return (
        frames: s.frames,
        enabled: s.enabled != 0,
        confident: s.confident != 0,
        gainDb: s.gainDb,
        speechLevelDbfs: s.speechLevelDbfs,
        noiseDbfs: s.noiseDbfs,
        headroomDb: s.headroomDb
      );
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
        "auto=${engine(s.autoChoice)} "
        "${describeDemotion(s.demoted, s.demoteReason)} "
        "processed=${s.framesProcessed} bypassed=${s.framesBypassed} "
        "resampled=${s.framesResampled} "
        "rate=${s.lastSampleRate} "
        "dfn3_avg=${s.dfn3AverageUs.toStringAsFixed(0)}us "
        "bench_p90=${s.benchmarkP90Us.toStringAsFixed(0)}us"
        "${_describeAgc()}";
  }

  static String _describeAgc() {
    final a = agcStats();
    if (a == null) return "";
    return " agc=${a.enabled} agc_frames=${a.frames} "
        "agc_gain=${a.gainDb.toStringAsFixed(1)}dB "
        "agc_speech=${a.speechLevelDbfs.toStringAsFixed(1)}dBFS "
        "agc_confident=${a.confident} "
        "agc_noise=${a.noiseDbfs.toStringAsFixed(1)}dBFS "
        "agc_headroom=${a.headroomDb.toStringAsFixed(1)}dB";
  }
}
