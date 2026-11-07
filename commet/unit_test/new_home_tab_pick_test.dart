import 'package:commet/ui/organisms/new_home/new_home_column.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phones: picking another Home tab keeps the side list on screen (switched
/// to that tab); only picking the tab Home already shows opens its page.
void main() {
  test("another tab only switches the side list", () {
    expect(
        pickOpensPage(
            onHome: true, roomOpen: false, shown: "overview", picked: "people"),
        isFalse);
  });

  test("the shown tab opens its page", () {
    expect(
        pickOpensPage(
            onHome: true, roomOpen: false, shown: "people", picked: "people"),
        isTrue);
  });

  test("from a room or a space, the shown tab stays on the side list", () {
    expect(
        pickOpensPage(
            onHome: true, roomOpen: true, shown: "people", picked: "people"),
        isFalse);
    expect(
        pickOpensPage(
            onHome: false, roomOpen: false, shown: "people", picked: "people"),
        isFalse);
  });
}
