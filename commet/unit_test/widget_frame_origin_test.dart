import 'package:commet/client/matrix/components/widgets/runners/web_frame/widget_frame_origin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a widget URL has the origin browsers report for its page', () {
    expect(WidgetFrameOrigin.of("https://widgets.example.org/app?x=1#/a"),
        "https://widgets.example.org");
    expect(WidgetFrameOrigin.of("https://widgets.example.org:443/"),
        "https://widgets.example.org");
    expect(WidgetFrameOrigin.of("https://Widgets.Example.org:8443/a"),
        "https://widgets.example.org:8443");
    expect(WidgetFrameOrigin.of("http://127.0.0.1:8766/widget.html"),
        "http://127.0.0.1:8766");
    for (final url in [
      "javascript:alert(1)",
      "data:text/html,<p>hi",
      "file:///etc/passwd",
      "commet://widget",
      "https:///no-host",
      "",
    ]) {
      expect(WidgetFrameOrigin.of(url), isNull, reason: url);
    }
  });

  test('only messages from the frame with the widget origin are taken', () {
    const widget = "https://widgets.example.org";
    expect(
        WidgetFrameOrigin.accepts(
            fromFrame: true, origin: widget, widgetOrigin: widget),
        isTrue);
    // Another frame or tab, even one on the widget's origin.
    expect(
        WidgetFrameOrigin.accepts(
            fromFrame: false, origin: widget, widgetOrigin: widget),
        isFalse);
    // The frame after it navigated somewhere else, or a sandboxed page.
    for (final origin in [
      "https://evil.example.org",
      "http://widgets.example.org",
      "https://widgets.example.org:8443",
      "null",
      "",
      null,
    ]) {
      expect(
          WidgetFrameOrigin.accepts(
              fromFrame: true, origin: origin, widgetOrigin: widget),
          isFalse,
          reason: "$origin");
    }
    expect(
        WidgetFrameOrigin.accepts(
            fromFrame: true, origin: "null", widgetOrigin: null),
        isFalse);
  });
}
