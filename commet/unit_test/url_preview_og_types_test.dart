import 'package:commet/client/matrix/components/url_preview/matrix_url_preview_component.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet: Synapse sends every Open Graph field as a string; Tuwunel sends
// numbers as JSON numbers. Both must parse, or the preview card never leaves
// its loading shimmer.
void main() {
  test("og strings pass through, numbers and bools become text", () {
    expect(MatrixUrlPreviewComponent.ogString("A title"), "A title");
    expect(MatrixUrlPreviewComponent.ogString(1280), "1280");
    expect(MatrixUrlPreviewComponent.ogString(true), "true");
    expect(MatrixUrlPreviewComponent.ogString(null), isNull);
    expect(MatrixUrlPreviewComponent.ogString(["x"]), isNull);
  });

  test("og ints accept JSON numbers and numeric strings", () {
    expect(MatrixUrlPreviewComponent.ogInt(1280), 1280);
    expect(MatrixUrlPreviewComponent.ogInt(720.0), 720);
    expect(MatrixUrlPreviewComponent.ogInt("1280"), 1280);
    expect(MatrixUrlPreviewComponent.ogInt(" 720 "), 720);
    expect(MatrixUrlPreviewComponent.ogInt("wide"), isNull);
    expect(MatrixUrlPreviewComponent.ogInt(null), isNull);
  });
}
