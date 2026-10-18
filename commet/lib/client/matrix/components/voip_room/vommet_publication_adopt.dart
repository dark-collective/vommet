import 'package:commet/client/components/voip/voip_stream.dart';
import 'package:commet/client/matrix/components/voip_room/matrix_livekit_voip_stream.dart';
import 'package:commet/debug/log.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

/// Vommet: keep each tile on the room's current publication object.
///
/// livekit_client can replace a remote publication with a new object that has
/// the same sid (seen when a sharer stops and starts sharing again). Tiles
/// were matched by sid but kept the first object, whose track stays null: the
/// tile spun forever, no renderer asked for the video, adaptive stream turned
/// it off (enabled=false) and the SFU never forwarded it, while the share's
/// audio played. Every event carrying a publication now hands the newer
/// object to the matching tiles.
///
/// Returns whether any tile has this sid (callers use it as their
/// "already have a tile" check).
bool vommetAdoptPublication(List<VoipStream> streams, lk.TrackPublication p) {
  var found = false;
  for (final s in streams.whereType<MatrixLivekitVoipStream>()) {
    if (s.publication.sid != p.sid) continue;
    found = true;
    if (identical(s.publication, p)) continue;
    Log.i("Call diag: tile adopted the current publication object "
        "sid=${p.sid} source=${p.source.name} track=${p.track != null}");
    s.publication = p;
    s.onTrackSubscribed();
  }
  return found;
}
