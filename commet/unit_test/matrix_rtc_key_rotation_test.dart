import 'package:commet/client/matrix/components/voip_room/matrix_rtc_key_rotation.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> member({int? created}) => {
      "application": "m.call",
      "call_id": "",
      "scope": "m.room",
      if (created != null) "created_ts": created,
    };

void main() {
  test('a refresh of a known membership keeps the key', () {
    final r = MatrixRtcKeyRotation();
    r.seed("_@a:x_A_m.call", member(), 1000);
    // The refresh inherits created_ts from the first post's server time.
    expect(r.needsRotation("_@a:x_A_m.call", member(created: 1000), 5000),
        isFalse);
    expect(r.needsRotation("_@a:x_A_m.call", member(created: 1000), 9000),
        isFalse);
  });

  test('a new member, a rejoin and a leave rotate', () {
    final r = MatrixRtcKeyRotation();
    expect(r.needsRotation("_@b:x_B_m.call", member(), 2000), isTrue);
    expect(r.needsRotation("_@b:x_B_m.call", member(created: 2000), 3000),
        isFalse);
    expect(r.needsRotation("_@b:x_B_m.call", {}, 4000), isTrue);
    expect(r.needsRotation("_@b:x_B_m.call", member(), 5000), isTrue);
  });

  test('a client without created_ts rotates on each post, as before', () {
    final r = MatrixRtcKeyRotation();
    expect(r.needsRotation("_@c:x_C_m.call", member(), 1000), isTrue);
    expect(r.needsRotation("_@c:x_C_m.call", member(), 2000), isTrue);
  });
}
