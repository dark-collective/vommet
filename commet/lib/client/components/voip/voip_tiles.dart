// Vommet: which streams the call view draws a tile for. Shared by the call
// view and the call_stats tiles_shown count, so the two can't drift apart.
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/components/voip/voip_stream.dart';
import 'package:commet/client/components/voip/voip_stream_watching.dart';

/// The streams of [session] the call view draws a tile for, before ordering:
/// never screen share audio, and no voice tile for someone whose camera has a
/// tile, or (without stream watching, where they keep it while sharing) whose
/// screen share has one. A screen share by person, not device: a share
/// published from another of their devices doesn't add their picture again.
List<VoipStream> callTileStreams(VoipSession session) {
  final streams = session.streams;
  final keepWhileSharing = VoipStreamWatching.of(session) != null;
  bool hidden(VoipStream audio) => streams.any((i) =>
      (i.participantId == audio.participantId &&
          i.type == VoipStreamType.video) ||
      (!keepWhileSharing &&
          i.streamUserId == audio.streamUserId &&
          i.type == VoipStreamType.screenshare));
  return streams
      .where((s) => s.type != VoipStreamType.screenshareAudio)
      .where((s) => s.type != VoipStreamType.audio || !hidden(s))
      .toList();
}
