// Vommet issue 569: editing a message turned links with their own text
// ("[here](https://...)") into plain text, so the edit (and every later
// forward of the message) lost those links.

import 'package:commet/client/matrix/timeline_events/matrix_edit_text.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;

class _FakeSdkRoom extends Fake implements matrix.Room {
  @override
  final String id = "!room:example.org";
}

matrix.Event _message(Map<String, dynamic> content) => matrix.Event(
      content: content,
      type: matrix.EventTypes.Message,
      eventId: "\$event",
      senderId: "@alice:example.org",
      originServerTs: DateTime.fromMillisecondsSinceEpoch(0),
      room: _FakeSdkRoom(),
    );

matrix.Event _html(String html, {String msgtype = "m.text"}) => _message({
      "msgtype": msgtype,
      "body": "plain",
      "format": "org.matrix.custom.html",
      "formatted_body": html,
    });

void main() {
  test("named links come back as markdown links", () {
    final e = _html('the <a href="https://vommet.app">vommet</a> client and '
        '<a href="https://nether.im">nether.im</a>, find them '
        '<a href="https://vommet.app/design/plan/">here</a>.');
    expect(
        MatrixEditText.markdownOf(e),
        "the [vommet](https://vommet.app) client and nether.im, find them "
        "[here](https://vommet.app/design/plan/).");
  });

  test("formatting inside and around a link is kept", () {
    final e = _html('<strong>see <a href="https://a.example/x">'
        '<em>this</em> page</a></strong>');
    expect(MatrixEditText.markdownOf(e),
        "**see [*this* page](https://a.example/x)**");
  });

  test("brackets in the text and parentheses in the address are escaped", () {
    final e = _html('<a href="https://a.example/wiki/A_(b)">[x] wiki</a> done');
    expect(MatrixEditText.markdownOf(e),
        r"[\[x\] wiki](https://a.example/wiki/A_%28b%29) done");
  });

  test("messages without named links keep the plain text path", () {
    expect(
        MatrixEditText.markdownOf(_html(
            '<a href="https://nether.im/">https://nether.im</a> and <b>x</b>')),
        isNull);
    expect(
        MatrixEditText.markdownOf(
            _html('<a href="https://matrix.to/#/@bob:example.org">Bob</a> hi')),
        isNull);
    expect(
        MatrixEditText.markdownOf(
            _message({"msgtype": "m.text", "body": "[a](https://a.example)"})),
        isNull);
  });

  test("captions are left alone", () {
    expect(
        MatrixEditText.markdownOf(
            _html('<a href="https://a.example">a</a>', msgtype: "m.image")),
        isNull);
  });

  test("notices are handled like text", () {
    expect(
        MatrixEditText.markdownOf(
            _html('<a href="https://a.example">a</a>', msgtype: "m.notice")),
        "[a](https://a.example)");
  });
}
