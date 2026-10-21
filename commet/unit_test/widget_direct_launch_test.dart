import 'package:commet/client/matrix/components/widgets/runners/direct/matrix_widget_direct_launch.dart';
import 'package:commet/ui/organisms/room_widgets/widget_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

const _drawpile = "vommet.app/widgets/drawpile/play/?server=pub.drawpile.net";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('only https widget URLs open directly', () {
    expect(
        MatrixWidgetDirectLaunch.openableUri("https://$_drawpile"), isNotNull);
    expect(
        MatrixWidgetDirectLaunch.openableUri("HTTPS://$_drawpile"), isNotNull);
    for (final url in [
      "http://$_drawpile",
      "someapp://$_drawpile",
      "file:///etc/passwd",
      "javascript:alert(1)",
      "https:///no-host",
      "",
    ]) {
      expect(MatrixWidgetDirectLaunch.openableUri(url), isNull, reason: url);
    }
  });

  test('a catalog entry only matches with the same scheme', () async {
    await WidgetCatalog.load();
    expect(WidgetCatalog.match("https://$_drawpile")?.direct, isTrue);
    expect(WidgetCatalog.match("someapp://$_drawpile"), isNull);
    expect(await WidgetCatalog.opensDirectly("someapp://$_drawpile"), isFalse);
  });
}
