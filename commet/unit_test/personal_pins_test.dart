import 'package:commet/client/components/personal_pins/personal_pins.dart';
import 'package:test/test.dart';

void main() {
  test("personal pins read from room account data, tolerating junk", () {
    expect(
        PersonalPins.parse({
          "pinned": [r"$a", r"$b"]
        }),
        [r"$a", r"$b"]);
    expect(
        PersonalPins.parse({
          "pinned": [r"$a", 3, null, r"$a", r"$c"]
        }),
        [r"$a", r"$c"]);
    expect(PersonalPins.parse({"pinned": "nope"}), isEmpty);
    expect(PersonalPins.parse({}), isEmpty);
    expect(PersonalPins.parse(null), isEmpty);
  });
}
