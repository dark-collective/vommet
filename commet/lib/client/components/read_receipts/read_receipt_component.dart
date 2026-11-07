import 'package:commet/client/client.dart';
import 'package:commet/client/components/room_component.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';

abstract class ReadReceiptComponent<R extends Client, T extends Room>
    implements RoomComponent<R, T> {
  Stream<String> get onReadReceiptsUpdated;
  bool? get usePublicReadReceiptsForRoom;
  Future<void> setUsePublicReadReceiptsForRoom(bool? value);

  List<String>? getReceipts(TimelineEvent event);

  /// Vommet: the event [userId]'s latest read receipt is on, and when it was
  /// sent.
  ({String eventId, DateTime time})? latestReceiptOf(String userId);
}
