// ignore_for_file: avoid_print
// Vommet issue 1137: actual assets through both search entry points, not a
// synthetic shortcode fixture that already happens to contain thumbsup.
import 'package:commet/client/components/emoticon/dynamic_emoticon_pack.dart';
import 'package:commet/client/components/emoticon/emoticon.dart';
import 'package:commet/client/matrix/components/emoticon/matrix_emoticon.dart';
import 'package:commet/utils/autofill_utils.dart';
import 'package:commet/utils/emoji/unicode_emoji.dart';
import 'package:commet/utils/emoji/unicode_emoji_data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;

import 'support/emoji_alias_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late EmojiAliasClient client;
  setUp(() async {
    final clock = Stopwatch()..start();
    await UnicodeEmojis.loadShortcodeData();
    client = EmojiAliasClient(await UnicodeEmojis.load());
    print('Vommet issue 1137 asset/pack load: ${clock.elapsedMicroseconds} us');
  });

  for (final entry in {
    'thumbsup': '+1',
    'thumbsdown': '-1',
    'smile': 'grinning_face_with_closed_eyes',
    'sob': 'loudly_crying_face',
    'tada': 'party',
  }.entries) {
    test('${entry.key} reaches its stock emoji in composer and picker search',
        () {
      final target = stockEmoji(entry.value);
      final clock = Stopwatch()..start();
      final composer = AutofillUtils.search(':${entry.key}', client);
      final composerUs = clock.elapsedMicroseconds;
      clock.reset();
      final picker =
          AutofillUtils.searchEmoticon(entry.key, client: client, limit: 50);
      print('Vommet issue 1137 ${entry.key}: composer=${composerUs}us '
          'picker=${clock.elapsedMicroseconds}us '
          'composer_target=${composer.where((r) => r.slug == target.slug).length} '
          'picker_target=${picker.where((r) => r.slug == target.slug).length}');
      for (final results in [composer, picker]) {
        final matches = results.where((r) => r.slug == target.slug).toList();
        expect(matches, hasLength(1));
        expect(matches.single.result, entry.value);
      }
    });
  }

  test('every existing alias looks up the same stock object without extra rows',
      () async {
    final namesByPrimary = {
      for (final value in UnicodeEmojis.shortcodeData!.values)
        (value is List ? value.first : value): value is List ? value : [value],
    };
    for (final pack in UnicodeEmojis.packs!) {
      for (final emoji in pack.emoji) {
        for (final name in namesByPrimary[emoji.shortcode]!) {
          expect(pack.getByShortcode(name as String), same(emoji),
              reason: name);
        }
      }
    }
    expect(UnicodeEmojis.packs!.expand((p) => p.emoji), hasLength(1914));
    expect(AutofillUtils.searchEmoticon('hankey', client: client), isEmpty);

    // Exercise the real loader's primary-before-alias collision rule with
    // controlled group metadata; the alias names still come from the asset.
    final collisionPack = UnicodeEmoticonPack(
        dataPacks: [
          [
            UnicodeEmojiData(unicode: stockEmoji('+1').slug, shortcode: '+1'),
            const UnicodeEmojiData(unicode: '🧪', shortcode: 'thumbsup'),
          ]
        ],
        getLocalisedName: () => 'Collision fixture',
        identifier: 'collision-fixture');
    await collisionPack.load();
    expect(collisionPack.getByShortcode('thumbsup'),
        same(collisionPack.emoji.last));
    expect(collisionPack.getByShortcode('+1'), same(collisionPack.emoji.first));
    expect(collisionPack.getShortcodes(), contains('thumbsup'));
  });

  test('aliases deduplicate across stock packs before limits and custom ties',
      () {
    final target = stockEmoji('party');
    final sdk = _SdkClient();
    final custom = MatrixEmoticon(Uri.parse('mxc://example.test/party'), sdk,
        packUsage: EmoticonUsage.emoji,
        shortcode: 'party',
        usage: EmoticonUsage.emoji,
        packKey: 'custom');
    final customPack = DynamicEmoticonPack(
        emoticons: [custom],
        displayName: 'Custom',
        identifier: 'custom',
        usage: EmoticonUsage.emoji);
    final stock =
        UnicodeEmojis.packs!.firstWhere((p) => p.emoji.contains(target));
    final thumb = MatrixEmoticon(Uri.parse('mxc://example.test/thumb'), sdk,
        packUsage: EmoticonUsage.emoji,
        shortcode: 'thumbsup',
        usage: EmoticonUsage.emoji,
        packKey: 'custom');
    customPack.emoticons.add(thumb);
    // An unnamed entry must not hide valid stock/custom search matches.
    customPack.emoticons.add(UnicodeEmoticon('🧪'));
    final mixed =
        EmojiAliasClient([stock, stock, ...UnicodeEmojis.packs!, customPack]);
    final all = AutofillUtils.search(':party', mixed);
    expect(all.where((r) => r.slug == target.slug), hasLength(1));
    expect(all.where((r) => r.slug == custom.slug), hasLength(1));
    expect(all.first.slug, ':custom~party:');
    expect(
        AutofillUtils.searchEmoticon('party', client: mixed, limit: 1)
            .single
            .slug,
        custom.slug);
    expect(AutofillUtils.searchEmoticon('party', client: mixed, limit: 0),
        isEmpty);
    expect(AutofillUtils.searchEmoticon('party', client: mixed, limit: -1),
        isEmpty);
    final thumbs = AutofillUtils.search(':thumbsup', mixed);
    expect(thumbs.first.slug, thumb.slug);
    expect(thumbs.where((r) => r.slug == stockEmoji('+1').slug), hasLength(1));
  });

  test('a later pack exact alias survives earlier fuzzy results and a limit',
      () {
    final results = AutofillUtils.searchEmoticon('thumbsup',
        client: client, limit: 1, threshold: 0.6);
    expect(results.single.slug, stockEmoji('+1').slug);
  });

  test('unknown names and a client with no packs have no results', () {
    expect(AutofillUtils.search(':zzzzzzzzzz', client), isEmpty);
    expect(AutofillUtils.search(':thumbsup', EmojiAliasClient([])), isEmpty);
  });
}

class _SdkClient extends Fake implements matrix.Client {}
