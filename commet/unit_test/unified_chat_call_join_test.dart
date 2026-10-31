// Vommet issue 625: a voice room in the unified chat list moves up when
// someone joins its call, not when they leave or refresh their membership.
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_source.dart';
import 'package:flutter_test/flutter_test.dart';

final _sent = DateTime.utc(2026, 10, 23, 12);
final _created = DateTime.utc(2026, 10, 23, 9);

void main() {
  test("a leave (empty content) is no join", () {
    expect(callJoinedAt({}, _sent), isNull);
    expect(callJoinedAt({"memberships": []}, _sent), isNull);
  });

  test("a new membership joins when it was sent", () {
    expect(callJoinedAt({"application": "m.call", "device_id": "PHONE"}, _sent),
        _sent);
  });

  test("a refreshed membership keeps its original join time", () {
    final content = {
      "application": "m.call",
      "device_id": "PHONE",
      "created_ts": _created.millisecondsSinceEpoch,
    };
    expect(callJoinedAt(content, _sent)!.isAtSameMomentAs(_created), isTrue);
  });

  test("legacy memberships use their created_ts", () {
    final content = {
      "memberships": [
        {"device_id": "PHONE", "created_ts": _created.millisecondsSinceEpoch},
      ],
    };
    expect(callJoinedAt(content, _sent)!.isAtSameMomentAs(_created), isTrue);
  });
}
