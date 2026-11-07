import 'package:commet/client/matrix/components/profile/matrix_self_status.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/self_status_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('retry jitter and cap have no timer-driven requests', () async {
    final f = SelfStatusFixture()..errorStatus = 503;
    await f.init();
    final c = SelfStatusClock(f.sdk,
        build: (now) => MatrixSelfStatus(f.sdk, now: now, random: () => 0.5));
    try {
      await c.read();
      c.elapse(const Duration(seconds: 67));
      await c.read();
      expect(f.presenceGets, 1, reason: '60s +12.5% =67.5s');
      c.elapse(const Duration(milliseconds: 500));
      expect(f.presenceGets, 1, reason: 'no automatic retry');
      await c.read();
      expect(f.presenceGets, 2);
      var count = 2;
      for (final delay in [135, 270, 540, 900, 900]) {
        c.elapse(Duration(seconds: delay - 1));
        await c.read();
        expect(f.presenceGets, count);
        c.elapse(const Duration(seconds: 1));
        await c.read();
        expect(f.presenceGets, ++count);
      }
    } finally {
      await c.close();
      await f.close();
    }
  });
}
