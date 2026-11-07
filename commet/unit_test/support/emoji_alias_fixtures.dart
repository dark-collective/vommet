// Vommet issue 1137: fakes only at the client/pack boundary; search and the
// stock packs use the real bundled data in both unit and composer tests.
import 'package:commet/client/client.dart';
import 'package:commet/client/components/component.dart';
import 'package:commet/client/components/emoticon/emoticon.dart';
import 'package:commet/client/components/emoticon/emoticon_component.dart';
import 'package:commet/client/components/emoticon/emoji_pack.dart';
import 'package:commet/utils/emoji/unicode_emoji.dart';
import 'package:flutter_test/flutter_test.dart';

class EmojiAliasClient extends Fake implements Client {
  EmojiAliasClient(List<EmoticonPack> packs)
      : component = _EmojiComponent(packs);
  final EmoticonComponent component;

  @override
  T? getComponent<T extends Component>() =>
      component is T ? component as T : null;
}

class _EmojiComponent extends Fake implements EmoticonComponent {
  _EmojiComponent(this.availablePacks);
  @override
  final List<EmoticonPack> availablePacks;
}

Emoticon stockEmoji(String shortcode) => UnicodeEmojis.packs!
    .expand((pack) => pack.emoji)
    .firstWhere((emoji) => emoji.shortcode == shortcode);
