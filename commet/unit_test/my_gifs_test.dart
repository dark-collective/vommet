// Vommet: My GIFs. Any GIF in a chat can be saved (not only stickers from
// the GIF picker), and a saved encrypted or bridged GIF is sent back as the
// same kind of message.
import 'package:commet/client/matrix/components/gif/matrix_gif_component.dart';
import 'package:commet/ui/molecules/gif_picker.dart';
import 'package:commet/ui/molecules/my_gifs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/config/style/theme_dark.dart';
import 'package:matrix/matrix.dart' as matrix;

class _FakeDatabase implements matrix.DatabaseApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final room = matrix.Room(
      id: '!room:example.org',
      client: matrix.Client('my-gifs-test', database: _FakeDatabase()));

  matrix.Event event(Map<String, Object?> content,
          {String type = matrix.EventTypes.Message}) =>
      matrix.Event(
        content: content,
        type: type,
        eventId: '\$${content.hashCode}',
        senderId: '@alice:example.org',
        originServerTs: DateTime(2026),
        room: room,
      );

  const encryptedFile = {
    'url': 'mxc://example.org/enc',
    'key': {
      'k': 'abc',
      'key_ops': ['encrypt', 'decrypt']
    },
    'iv': 'iv',
    'hashes': {'sha256': 'hash'},
    'v': 'v2',
  };

  test('a sticker GIF from the GIF picker counts, as before', () {
    expect(
        MatrixGifComponent.isGifEvent(event({
          'body': 'party',
          'url': 'mxc://example.org/a',
          'info': {'mimetype': 'image/gif', 'chat.commet.animated': true},
        }, type: matrix.EventTypes.Sticker)),
        isTrue);
  });

  test('an uploaded .gif picture counts, a still picture does not', () {
    expect(
        MatrixGifComponent.isGifEvent(event({
          'msgtype': 'm.image',
          'body': 'cat.gif',
          'url': 'mxc://example.org/b',
          'info': {'mimetype': 'image/gif'},
        })),
        isTrue);
    expect(
        MatrixGifComponent.isGifEvent(event({
          'msgtype': 'm.image',
          'body': 'cat.png',
          'url': 'mxc://example.org/c',
          'info': {'mimetype': 'image/png'},
        })),
        isFalse);
  });

  test('a bridged GIF video counts, an ordinary video does not', () {
    expect(
        MatrixGifComponent.isGifEvent(event({
          'msgtype': 'm.video',
          'body': 'video.mp4',
          'url': 'mxc://example.org/d',
          'info': {'mimetype': 'video/mp4', 'fi.mau.gif': true},
        })),
        isTrue);
    expect(
        MatrixGifComponent.isGifEvent(event({
          'msgtype': 'm.video',
          'body': 'holiday.mp4',
          'url': 'mxc://example.org/e',
          'info': {'mimetype': 'video/mp4'},
        })),
        isFalse);
  });

  test('a GIF from an encrypted room keeps its key and is identified by it',
      () {
    final entry = MatrixGifComponent.favoriteEntry(event({
      'msgtype': 'm.image',
      'body': 'cat.gif',
      'file': encryptedFile,
      'info': {'mimetype': 'image/gif'},
    }))!;
    expect(entry['url'], 'mxc://example.org/enc');
    expect(entry['file'], encryptedFile);
    expect(entry.containsKey('msgtype'), isFalse);

    final content = MatrixGifComponent.messageContent(entry);
    expect(content['msgtype'], 'm.image');
    expect(content['file'], encryptedFile);
    expect(content.containsKey('url'), isFalse);
  });

  test('a saved bridged GIF is sent back as a GIF video', () {
    final info = {'mimetype': 'video/mp4', 'fi.mau.gif': true};
    final entry = MatrixGifComponent.favoriteEntry(event({
      'msgtype': 'm.video',
      'body': 'video.mp4',
      'url': 'mxc://example.org/d',
      'info': info,
    }))!;
    expect(entry['msgtype'], 'm.video');

    final content = MatrixGifComponent.messageContent(entry);
    expect(content['msgtype'], 'm.video');
    expect(content['url'], 'mxc://example.org/d');
    expect(content['info'], info);
  });

  test('a sticker GIF keeps the upstream entry shape', () {
    final entry = MatrixGifComponent.favoriteEntry(event({
      'body': 'party',
      'url': 'mxc://example.org/a',
      'info': {'mimetype': 'image/gif', 'chat.commet.animated': true},
    }, type: matrix.EventTypes.Sticker))!;
    expect(entry.keys.toSet(), {'info', 'body', 'url'});
  });

  testWidgets('with search off, the GIF tab explains My GIFs and offers search',
      (tester) async {
    var turnedOn = false;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeDark.theme,
      home: Scaffold(
        body: GifPicker(
          searchEnabled: false,
          onTurnOnSearch: () async => turnedOn = true,
        ),
      ),
    ));
    expect(find.text(MyGifs.emptyTitle), findsOneWidget);
    expect(find.text(MyGifs.searchOff), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.text(MyGifs.promptTurnOnSearch));
    // The search box takes focus, so its cursor blinks and never settles.
    await tester.pump();
    await tester.pump();
    expect(turnedOn, isTrue);
    expect(find.byType(TextField), findsOneWidget);
  });
}
