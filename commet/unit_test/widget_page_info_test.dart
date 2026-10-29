import 'package:commet/utils/widget_page_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final base = Uri.parse(
      "https://watch.example.org/widget/?widgetId=\$matrix_widget_id");

  test('reads the title and prefers a raster touch icon', () {
    final info = WidgetPageInfo.parse("""
<html><head><title>  Watch
 Together </title>
<link rel="icon" href="icon.svg" type="image/svg+xml">
<link rel="apple-touch-icon" href="icon-180.png">
</head></html>""", base);
    expect(info.title, "Watch Together");
    expect(info.iconUrl.toString(),
        "https://watch.example.org/widget/icon-180.png");
  });

  test('falls back to a raster icon and skips SVG', () {
    final info = WidgetPageInfo.parse(
        '<title>Chess</title><link rel="icon" href="/a.svg">'
        '<link rel="shortcut icon" href="/fav.png">',
        base);
    expect(info.iconUrl.toString(), "https://watch.example.org/fav.png");
  });

  test('no title or icon', () {
    final info = WidgetPageInfo.parse("<html><body>hi</body></html>", base);
    expect(info.title, isNull);
    expect(info.iconUrl, isNull);
  });

  test('ignores icons that are not https', () {
    final info = WidgetPageInfo.parse(
        '<title>X</title><link rel="icon" href="http://evil.example/i.png">',
        base);
    expect(info.iconUrl, isNull);
  });
}
