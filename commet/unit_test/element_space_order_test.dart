import 'package:commet/client/matrix/components/sidebar_entries/matrix_sidebar_entries_component.dart';
import 'package:flutter_test/flutter_test.dart';

String order(String roomId, Object? elementOrder) =>
    MatrixSidebarEntriesComponent.defaultOrderFor("c", roomId, elementOrder);

List<String> sorted(Map<String, Object?> spaces) {
  var entries = spaces.entries.toList()
    ..sort((a, b) => order(a.key, a.value).compareTo(order(b.key, b.value)));
  return entries.map((e) => e.key).toList();
}

void main() {
  test("ordered spaces come first, by their Element order", () {
    expect(
        sorted({
          "!a:x": null,
          "!b:x": "b",
          "!c:x": "a",
          "!d:x": null,
        }),
        ["!c:x", "!b:x", "!a:x", "!d:x"]);
  });

  test("a shorter order sorts before a longer one it prefixes", () {
    expect(sorted({"!a:x": "ab", "!b:x": "a"}), ["!b:x", "!a:x"]);
  });

  test("equal orders fall back to room id", () {
    expect(sorted({"!b:x": "m", "!a:x": "m"}), ["!a:x", "!b:x"]);
  });

  test("invalid orders are ignored", () {
    for (var invalid in [
      "x" * 51,
      "café",
      "tab\there",
      5,
      {"order": "a"},
    ]) {
      expect(order("!a:x", invalid), "__c_!a:x", reason: "$invalid");
    }
    expect(order("!a:x", "x" * 50), startsWith("__c_\u0001"));
    // Valid in Element too, and sorts first.
    expect(sorted({"!a:x": "a", "!b:x": ""}), ["!b:x", "!a:x"]);
  });

  test("defaults keep the generated-order prefix", () {
    expect(order("!a:x", "a"), startsWith("__"));
    expect(order("!a:x", null), startsWith("__"));
  });
}
