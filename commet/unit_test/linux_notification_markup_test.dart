import 'package:commet/client/components/push_notification/linux/linux_notification_markup.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Message text and names go into the body of Linux desktop notifications.
  test("markup in a message stays text", () {
    const evil = '<b>hi</b> <a href="https://example.org">click</a>';
    final safe = LinuxNotificationMarkup.text(evil);
    expect(safe, isNot(contains("<")));
    expect(safe, isNot(contains(">")));
    expect(safe,
        "&lt;b&gt;hi&lt;/b&gt; &lt;a href=\"https://example.org\"&gt;click&lt;/a&gt;");
  });

  test("ampersands are escaped, quotes in text are left alone", () {
    expect(LinuxNotificationMarkup.text("Tom & Jerry"), "Tom &amp; Jerry");
    expect(LinuxNotificationMarkup.text("it's \"fine\""), "it's \"fine\"");
    expect(LinuxNotificationMarkup.text("&amp;"), "&amp;amp;");
  });

  test("attributes can't be broken out of", () {
    const evil = 'https://example.org/" onclick="x';
    final safe = LinuxNotificationMarkup.attribute(evil);
    expect(safe, isNot(contains('"')));
    expect(safe, "https://example.org/&quot; onclick=&quot;x");
    expect(LinuxNotificationMarkup.attribute("a<b>&c"), "a&lt;b&gt;&amp;c");
  });

  test("characters XML can't hold are dropped", () {
    expect(LinuxNotificationMarkup.text("a\u0000b\u0007c\u001Fd"), "abcd");
    expect(LinuxNotificationMarkup.text("line\none\tok\r"), "line\none\tok\r");
  });

  test("missing values are empty", () {
    expect(LinuxNotificationMarkup.text(null), "");
    expect(LinuxNotificationMarkup.attribute(null), "");
    expect(LinuxNotificationMarkup.body(null, markup: true), "");
    expect(LinuxNotificationMarkup.body(null, markup: false), "");
  });

  test("body is escaped only for daemons that read markup", () {
    const message = "<i>Tom</i> & Jerry";
    expect(LinuxNotificationMarkup.body(message, markup: true),
        "&lt;i&gt;Tom&lt;/i&gt; &amp; Jerry");
    expect(LinuxNotificationMarkup.body(message, markup: false), message);
  });
}
