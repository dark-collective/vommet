// Vommet issue 313: an emote whose name two packs share must send the one
// that was picked.
import 'package:commet/client/matrix/components/emoticon/matrix_emoticon_pack.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/src/utils/markdown.dart' as mx_markdown;

void main() {
  test('pack keys fit the emote syntax and tell packs apart', () {
    final a = MatrixEmoticonPack.flatKeyOf("My Cats!", "!a:x.org", "");
    final b = MatrixEmoticonPack.flatKeyOf("My Cats!", "!b:x.org", "");
    final c = MatrixEmoticonPack.flatKeyOf("My Cats!", "!a:x.org", "two");

    for (final key in [a, b, c]) {
      expect(RegExp(r'^[-\w]+$').hasMatch(key), isTrue, reason: key);
      expect(key, startsWith("My_Cats-"));
    }
    expect({a, b, c}.length, 3);
    expect(MatrixEmoticonPack.flatKeyOf("My Cats!", "!a:x.org", ""), a);
    expect(
        RegExp(r'^[0-9a-f]{8}$')
            .hasMatch(MatrixEmoticonPack.flatKeyOf("🐱", "!a:x.org", "")),
        isTrue);
  });

  final packs = {
    "cats-00000001": {"blep": "mxc://x.org/cat"},
    "dogs-00000002": {"blep": "mxc://x.org/dog"},
  };

  test('a pack-qualified slug sends that pack\'s emote', () {
    final cat = mx_markdown.markdown(":cats-00000001~blep:",
        getEmotePacks: () => packs);
    final dog = mx_markdown.markdown(":dogs-00000002~blep:",
        getEmotePacks: () => packs);

    expect(cat, contains('src="mxc://x.org/cat"'));
    expect(dog, contains('src="mxc://x.org/dog"'));
    expect(dog, contains('alt=":blep:"'));
  });

  test('the plain body drops known pack names only', () {
    expect(
        MatrixEmoticonPack.unqualifySlugs(
            "hi :dogs-00000002~blep: :other~blep: :blep:", packs),
        "hi :blep: :other~blep: :blep:");
  });
}
