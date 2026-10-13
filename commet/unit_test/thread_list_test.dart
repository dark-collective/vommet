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
}
