import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/components/voip/voip_stream.dart';
import 'package:commet/config/preferences/bool_preference.dart';
import 'package:intl/intl.dart';

/// Vommet: Discord-style stream watching. Other people's screen shares
/// aren't played until you choose to watch them; until then the call shows
/// a card for each (with a small live preview when the sharer's app sends a
/// low-quality layer). Implemented by call sessions that can pause a stream
/// (room calls over LiveKit); in others every stream simply plays.
abstract class VoipStreamWatching {
  static final Expando<VoipStreamWatching> _bySession = Expando();

  /// "Let others see when I'm watching" (Settings › Voice & video): the
  /// call learns whose streams you watch, for their "3 watching".
  static final BoolPreference showWatching =
      BoolPreference("vommet_show_watching", defaultValue: true);

  static String get labelShowWatching => Intl.message(
      "Let others see when I'm watching",
      name: "labelShowWatching",
      desc:
          "Settings, voice and video: switch that lets people in a call see that you watch their screen share");

  static String get labelShowWatchingDescription => Intl.message(
      "People sharing their screen, and others in the call, see you among those watching their stream",
      name: "labelShowWatchingDescription",
      desc:
          "Settings, voice and video: description of the switch that lets people see that you watch their screen share");

  /// The stream watching of [session], or null when the call doesn't use it
  /// (then every stream plays, as before).
  static VoipStreamWatching? of(VoipSession session) => _bySession[session];

  static void register(VoipSession session, VoipStreamWatching watching) =>
      _bySession[session] = watching;

  /// Whether [stream] is playing for you. Always true for your own streams,
  /// cameras and microphones; for a screen share (and its audio), true once
  /// you chose to watch it.
  bool isWatching(VoipStream stream);

  /// Whether an unwatched screen share can show a small live preview: the
  /// sharer's app sends a low-quality layer (simulcast).
  bool hasPreview(VoipStream stream);

  /// Starts or stops watching the screen share [stream] belongs to. Stopping
  /// pauses its video and drops its audio, so nothing is downloaded. A
  /// sharer who switches what they share stays watched.
  Future<void> setWatching(VoipStream stream, bool watching);

  /// Whether the audio of the screen share [stream] belongs to is muted for
  /// you (only for this call; the volume you set is kept). Muted audio isn't
  /// downloaded either.
  bool isStreamAudioMuted(VoipStream stream);

  Future<void> setStreamAudioMuted(VoipStream stream, bool muted);

  /// Asks the call view to show the screen share [stream] big, from outside
  /// it (the sidebar's Watch). Kept until the call view takes it, so it
  /// works when the call view opens only afterwards.
  void requestFocus(VoipStream stream);

  /// The stream [requestFocus] asked for, once: taking it clears it.
  VoipStream? takeFocusRequest();

  /// Fires after [requestFocus].
  Stream<void> get onFocusRequest;

  /// Who watches the screen share [stream] belongs to (Matrix user ids, you
  /// first when you do). Vommet viewers tell the call unless they turned
  /// "Let others see when I'm watching" off; other apps don't, so it can be
  /// fewer than really watch.
  List<String> viewersOf(VoipStream stream);
}
