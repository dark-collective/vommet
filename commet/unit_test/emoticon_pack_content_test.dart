import 'package:commet/client/matrix/components/emoticon/matrix_emoticon_component.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final names = ["wave", "nod", "shrug"];

  test('a failed upload leaves only that image out', () {
    final uris = [
      Uri.parse("mxc://example.org/wave"),
      null,
      Uri.parse("mxc://example.org/shrug"),
    ];
    final content =
        MatrixEmoticonComponent.packContent("Pebble", uris, 0, names, null);
    final images = content["images"] as Map<String, dynamic>;

    expect(images.keys, ["wave", "shrug"]);
    expect(images["wave"]["url"], "mxc://example.org/wave");
    expect(images["shrug"]["url"], "mxc://example.org/shrug");
    expect(content["pack"]["avatar_url"], "mxc://example.org/wave");
  });

  test('the avatar falls back to the first uploaded image', () {
    final uris = [null, Uri.parse("mxc://example.org/nod"), null];
    final content =
        MatrixEmoticonComponent.packContent("Pebble", uris, 0, names, null);

    expect(content["pack"]["avatar_url"], "mxc://example.org/nod");
    expect((content["images"] as Map).keys, ["nod"]);
  });

  test('no avatar when nothing uploaded', () {
    final content = MatrixEmoticonComponent.packContent(
        "Pebble", [null, null, null], 2, names, null);

    expect((content["pack"] as Map).containsKey("avatar_url"), isFalse);
    expect(content["images"], isEmpty);
  });
}
