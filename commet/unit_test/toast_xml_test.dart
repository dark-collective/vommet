import 'package:commet/client/components/push_notification/windows/toast_xml.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Names and message text go into Windows toast XML.
  test("markup in a message stays text", () {
    const evil = 'hi</text></binding></visual><actions><action '
        'activationType="protocol" arguments="https://example.org"/>';
    final safe = ToastXml.text(evil);
    expect(safe, isNot(contains("<")));
    expect(safe, isNot(contains(">")));
    expect(safe, isNot(contains('"')));
    expect(safe, startsWith("hi&lt;"));
  });

  test("ampersands and quotes are escaped", () {
    expect(ToastXml.text("Tom & Jerry"), "Tom &amp; Jerry");
    expect(ToastXml.text("it's \"fine\""), "it&#39;s &quot;fine&quot;");
  });

  test("characters XML can't hold are dropped", () {
    expect(ToastXml.text("a\u0000b\u0007c\u001Fd"), "abcd");
    // Tabs and newlines are fine.
    expect(ToastXml.text("line\none\tok\r"), "line\none\tok\r");
  });

  test("missing values are empty", () {
    expect(ToastXml.text(null), "");
  });

  test("plain text and emoji are unchanged", () {
    expect(ToastXml.text("Juniper 🦆 says hi"), "Juniper 🦆 says hi");
  });
}
