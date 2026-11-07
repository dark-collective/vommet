// ignore_for_file: avoid_print
// Vommet issue 1137: characterization of the reported send symptom with
// actual assets, the real MatrixRoom and SDK, and a stub HTTP boundary.
import 'dart:convert';

import 'package:commet/client/matrix/components/profile/matrix_profile_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/autofill_utils.dart';
import 'package:commet/utils/emoji/emoji_shortcodes.dart';
import 'package:commet/utils/emoji/unicode_emoji.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' as matrix;
import 'package:shared_preferences/shared_preferences.dart';

import 'roomlist_fixture.dart';
import 'support/emoji_alias_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const roomId = '!aliases:example.com';
  late MatrixClient client;
  final sent = <Map<String, dynamic>>[];
  var serial = 0;
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await UnicodeEmojis.load();
    client = await signedInClient('emoji-alias-${serial++}');
    client.self = MatrixProfile(client, matrix.Profile(userId: me));
    await sync(client, join: {
      roomId: matrix.JoinedRoomUpdate(state: roomState(roomId)),
    });
    sent.clear();
    stubResponse = (request) {
      if (!request.url.path.contains('/send/')) return null;
      sent.add(jsonDecode(request.body) as Map<String, dynamic>);
      return http.Response(
          jsonEncode({'event_id': '\$alias-${sent.length}'}), 200,
          headers: {'content-type': 'application/json'});
    };
  });
  tearDown(() async {
    stubResponse = null;
    await client.getMatrixClient().dispose(closeDatabase: true);
  });

  test('real room autocomplete offers the stock alias exactly once', () {
    final results =
        AutofillUtils.search(':thumbsup', client, room: client.getRoom(roomId));
    expect(results.where((r) => r.slug == stockEmoji('+1').slug), hasLength(1));
  });

  test('bundled thumbsup sends Unicode through MatrixRoom and SDK', () async {
    final target = stockEmoji('+1').slug;
    final watch = Stopwatch()..start();
    await client.getRoom(roomId)!.sendMessage(message: ':thumbsup:');
    print('Vommet issue 1137 stub HTTP send: ${watch.elapsedMicroseconds} us');
    expect(sent.single['body'], target);
  });

  test('thread text uses the same asset-backed replacement', () async {
    await (client.getRoom(roomId)! as MatrixRoom)
        .sendMessage(message: ':thumbsup:', threadRootEventId: '\$root');
    expect(sent.single['body'], stockEmoji('+1').slug);
    expect(sent.single['m.relates_to']['event_id'], '\$root');
  });

  test('actual asset honors custom collisions and Markdown exclusions',
      () async {
    final result = await EmojiShortcodes.replaceInMessage(
      ':thumbsup: :sob: `:thumbsup:` https://example.test/:thumbsup: \\:thumbsup:',
      customPacks: {
        'custom': {'thumbsup': 'mxc://example.test/custom'}
      },
    );
    expect(result,
        ':thumbsup: ${stockEmoji('loudly_crying_face').slug} `:thumbsup:` https://example.test/:thumbsup: \\:thumbsup:');
  });
}
