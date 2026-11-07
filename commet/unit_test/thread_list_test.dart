import 'package:commet/client/matrix/components/threads/matrix_thread_timeline.dart';
import 'package:commet/client/matrix/components/threads/matrix_threads_component.dart';
import 'package:test/test.dart';

void main() {
  group("threadHasUnread", () {
    bool unread(
            {String sender = "@bob:x",
            int ts = 100,
            List<int?> receipts = const []}) =>
        MatrixThreadsComponent.threadHasUnread(
            ownUserId: "@me:x",
            latestSenderId: sender,
            latestTs: ts,
            receiptTimestamps: receipts);

    test("no receipts: someone else's reply is unread", () {
      expect(unread(), isTrue);
    });

    test("your own newest reply is never unread", () {
      expect(unread(sender: "@me:x"), isFalse);
    });

    test("a receipt after the reply marks it read", () {
      expect(unread(ts: 100, receipts: [150]), isFalse);
    });

    test("a reply after every receipt is unread", () {
      expect(unread(ts: 200, receipts: [150, null, 120]), isTrue);
    });

    test("the newest receipt wins, threaded or not", () {
      expect(unread(ts: 200, receipts: [null, 250]), isFalse);
      expect(unread(ts: 200, receipts: [250, null]), isFalse);
    });
  });

  group("threadAggregation", () {
    test("reads the bundled m.thread summary", () {
      final info = MatrixThreadsComponent.threadAggregation({
        "m.relations": {
          "m.thread": {"count": 3, "current_user_participated": true}
        }
      });
      expect(info?["count"], 3);
    });

    test("missing or malformed relations give null", () {
      expect(MatrixThreadsComponent.threadAggregation(null), isNull);
      expect(MatrixThreadsComponent.threadAggregation({}), isNull);
      expect(MatrixThreadsComponent.threadAggregation({"m.relations": "x"}),
          isNull);
      expect(
          MatrixThreadsComponent.threadAggregation({
            "m.relations": {"m.thread": 5}
          }),
          isNull);
    });
  });

  group("insertIndexNewestFirst", () {
    DateTime t(int m) => DateTime.utc(2026, 10, 12, 17, m);
    int at(List<int> minutes, int m) =>
        MatrixThreadTimeline.insertIndexNewestFirst(
            minutes.map(t).toList(), t(m));

    test("newest goes first", () {
      expect(at([17, 10, 9], 18), 0);
    });

    test("a reply between others keeps time order, root stays last", () {
      expect(at([17, 12, 10, 9], 11), 2);
    });

    test("older than everything goes last", () {
      expect(at([17, 10], 5), 2);
      expect(at([], 5), 0);
    });

    test("a tie counts as the newer arrival", () {
      expect(at([17, 17, 10], 17), 0);
    });
  });
}
