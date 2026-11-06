import 'dart:async';

import 'package:commet/main.dart';

/// Vommet: push to talk. Each thing that can hold the microphone open (the
/// push to talk key, the call bar's talk button) is a source; the microphone
/// sends while any source is held, and for the release delay after the last
/// one lets go (so the end of a word isn't cut off).
///
/// The calls' microphones follow [talking] (see CallManager); mute still
/// wins, so holding the key while muted sends nothing.
class PushToTalk {
  PushToTalk(this.onChanged);

  final void Function(bool talking) onChanged;

  final Set<Object> _held = {};
  Timer? _release;
  bool _talking = false;

  /// Whether the microphone is sending (held, or within the release delay).
  bool get talking => _talking;

  /// Whether push to talk is the input mode (Voice settings).
  bool get isOn => preferences.voipPushToTalk.value;

  void press(Object source) {
    if (!isOn) return;
    _held.add(source);
    _release?.cancel();
    _release = null;
    _set(true);
  }

  void release(Object source) {
    if (!_held.remove(source) || _held.isNotEmpty) return;
    _release?.cancel();
    final delay = preferences.voipPushToTalkReleaseDelay.value.clamp(0.0, 2.0);
    if (delay <= 0) {
      _release = null;
      _set(false);
      return;
    }
    _release = Timer(Duration(milliseconds: (delay * 1000).round()), () {
      _release = null;
      _set(false);
    });
  }

  /// Lets go of everything at once (push to talk was turned off or on).
  void reset() {
    _held.clear();
    _release?.cancel();
    _release = null;
    _set(false);
  }

  void _set(bool talking) {
    if (_talking == talking) return;
    _talking = talking;
    onChanged(talking);
  }
}
