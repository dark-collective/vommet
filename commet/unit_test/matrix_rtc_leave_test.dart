import 'dart:async';

import 'package:commet/client/matrix/components/voip_room/matrix_rtc_leave.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    MatrixRtcLeave.retryDelays = const [Duration(milliseconds: 10)];
    MatrixRtcLeave.giveUpAfter = const Duration(minutes: 10);
  });

  test('a clear that lands completes at once', () async {
    var sends = 0;
    await MatrixRtcLeave.clear("!a", "_me_D_m.call", () async => sends++);
    expect(sends, 1);
  });

  test('a failing clear retries until it lands', () async {
    var sends = 0;
    await MatrixRtcLeave.clear("!b", "_me_D_m.call", () async {
      sends++;
      if (sends < 3) throw TimeoutException("slow homeserver");
    });
    expect(sends, 3);
  });

  test('a slow clear lets the caller move on and still lands', () async {
    final server = Completer<void>();
    var landed = false;
    final clear = MatrixRtcLeave.clear("!c", "_me_D_m.call", () async {
      await server.future;
      landed = true;
    });

    var timedOut = false;
    await clear.timeout(const Duration(milliseconds: 20),
        onTimeout: () => timedOut = true);
    expect(timedOut, isTrue);
    expect(landed, isFalse);

    server.complete();
    await clear;
    expect(landed, isTrue);
  });

  test('hanging up twice sends one clear', () async {
    final server = Completer<void>();
    var sends = 0;
    Future<void> send() async {
      sends++;
      await server.future;
    }

    final first = MatrixRtcLeave.clear("!d", "_me_D_m.call", send);
    final second = MatrixRtcLeave.clear("!d", "_me_D_m.call", send);
    server.complete();
    await Future.wait([first, second]);
    expect(sends, 1);
  });

  test('rejoining waits for the clear in flight and stops the retries',
      () async {
    final server = Completer<void>();
    var sends = 0;
    final events = <String>[];
    final clear = MatrixRtcLeave.clear("!e", "_me_D_m.call", () async {
      sends++;
      await server.future;
      events.add("clear landed");
      throw TimeoutException("lost the response");
    });

    final join = MatrixRtcLeave.settle("!e", "_me_D_m.call")
        .then((_) => events.add("join posted"));
    await Future.delayed(const Duration(milliseconds: 5));
    expect(events, isEmpty);

    server.complete();
    await join;
    await clear;
    await Future.delayed(const Duration(milliseconds: 50));
    expect(events, ["clear landed", "join posted"]);
    expect(sends, 1);
  });

  test('settling with nothing pending returns at once', () async {
    await MatrixRtcLeave.settle("!f", "_me_D_m.call");
  });
}
