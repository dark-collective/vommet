import 'package:commet/config/platform_utils.dart';
import 'package:commet/rust/api/transcribe.dart' as rust;
import 'package:commet/rust/frb_generated.dart';
import 'package:commet/utils/transcription_android_abi.dart';

/// The compiled capability, with an ABI fallback while the library is unloaded.
class TranscriptionRuntime {
  TranscriptionRuntime({
    bool Function()? initialized,
    bool Function()? compiledSupport,
    bool Function()? isAndroid,
    bool Function()? androidCanRetry,
    Future<void> Function()? initialize,
  })  : _initialized = initialized ?? (() => RustLib.instance.initialized),
        _compiledSupport = compiledSupport ?? rust.transcriptionSupported,
        _isAndroid = isAndroid ?? (() => PlatformUtils.isAndroid),
        _androidCanRetry =
            androidCanRetry ?? (() => canRetryAndroidTranscription),
        _initialize = initialize ?? RustLib.init;

  final bool Function() _initialized;
  final bool Function() _compiledSupport;
  final bool Function() _isAndroid;
  final bool Function() _androidCanRetry;
  final Future<void> Function() _initialize;
  Future<void>? _loading;

  bool get available {
    if (_initialized()) return _compiledSupport();
    if (!_isAndroid()) return true;
    // A failed Android load remains retryable only in a 64-bit process.
    return _androidCanRetry();
  }

  Future<void> prepare() async {
    if (_initialized()) return;
    await (_loading ??= _initialize().whenComplete(() => _loading = null));
  }
}
