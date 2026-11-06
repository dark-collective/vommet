import 'package:commet/client/client.dart';
import 'package:commet/client/components/room_component.dart';
import 'package:commet/config/preferences/bool_preference.dart';

/// Discovery metadata, not evidence that a media track is available.
abstract class ScreenShareStatus<R extends Client, T extends Room>
    implements RoomComponent<R, T> {
  static final experiment = BoolPreference(
      'vommet_experiment_prejoin_screen_share',
      defaultValue: false);

  /// Sender user IDs mapped to their current report deadlines (ms).
  /// Multiple devices belonging to one person count once.
  Map<String, int> get screenShares;
  Stream<void> get onScreenSharesChanged;
}
