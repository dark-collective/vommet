import 'package:commet/client/components/hidden_messages/hidden_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("parse keeps unique string ids and ignores junk", () {
    expect(HiddenMessages.parse(null), isEmpty);
    expect(HiddenMessages.parse({"hidden": "nope"}), isEmpty);
    expect(
        HiddenMessages.parse({
          "hidden": ["\$a", 3, "\$b", "\$a"]
        }),
        ["\$a", "\$b"]);
  });

  test("added appends new hides last without duplicates", () {
    expect(HiddenMessages.added(["\$a", "\$b"], ["\$b", "\$c"]),
        ["\$a", "\$b", "\$c"]);
  });

  test("added drops the oldest hides past the cap", () {
    final current = [
      for (var i = 0; i < HiddenMessages.max; i++) "\$old$i",
    ];
    final result = HiddenMessages.added(current, ["\$new"]);
    expect(result.length, HiddenMessages.max);
    expect(result.first, "\$old1");
    expect(result.last, "\$new");
  });
}
