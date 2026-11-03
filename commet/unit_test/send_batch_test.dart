import 'package:commet/client/matrix/forwarding/forward_content.dart';
import 'package:commet/client/matrix/send_batch.dart';
import 'package:test/test.dart';

void main() {
  test("send ids are 16 lowercase letters or digits and differ", () {
    final a = SendBatch.newId();
    final b = SendBatch.newId();
    expect(a, matches(RegExp(r"^[0-9a-z]{16}$")));
    expect(a, isNot(b));
  });

  test("a forward doesn't carry the original's send id", () {
    final out = ForwardContent.build({
      "msgtype": "m.image",
      "body": "cat.png",
      "url": "mxc://example.org/cat",
      SendBatch.key: "abc123",
    }, showSender: false);

    expect(out.containsKey(SendBatch.key), isFalse);
    expect(out["url"], "mxc://example.org/cat");
  });
}
