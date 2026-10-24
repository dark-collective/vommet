import 'package:commet/client/matrix/components/event_search/matrix_event_search_component.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;

class _FakeDatabase implements matrix.DatabaseApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final room = matrix.Room(
      id: '!room:example.org',
      client: matrix.Client('search-test', database: _FakeDatabase()));

  matrix.Event message(String body, {String sender = '@alice:example.org'}) =>
      matrix.Event(
        content: {'msgtype': 'm.text', 'body': body},
        type: matrix.EventTypes.Message,
        eventId: '\$${body.hashCode}',
        senderId: sender,
        originServerTs: DateTime(2026),
        room: room,
      );

  bool matches(String query, matrix.Event event) =>
      MatrixEncryptedRoomEventSearchSession.searchFunc(
          MatrixSearchParameters.parse(query), event);

  group('encrypted room search', () {
    test('matches regardless of the case of the search words', () {
      final event = message('see you at the Meeting tomorrow');
      expect(matches('meeting', event), isTrue);
      expect(matches('Meeting', event), isTrue);
      expect(matches('MEETING', event), isTrue);
      expect(matches('Tomorrow meeting', event), isTrue);
    });

    test('a trailing or double space does not match every message', () {
      final event = message('nothing to see here');
      expect(matches('meeting ', event), isFalse);
      expect(matches('meeting  ', event), isFalse);
      expect(matches(' meeting', event), isFalse);
      expect(matches('Meeting ', message('the meeting')), isTrue);
    });

    test('words still need a majority to match', () {
      final event = message('lunch at noon');
      expect(matches('lunch dinner', event), isTrue);
      expect(matches('lunch dinner breakfast', event), isFalse);
    });

    test('from: filters by sender, also when capitalised', () {
      final event = message('hello', sender: '@bob:example.org');
      expect(matches('from:@bob:example.org hello', event), isTrue);
      expect(matches('From:@bob:example.org hello', event), isTrue);
      expect(matches('from:@alice:example.org hello', event), isFalse);
    });

    test('has:link is recognised when capitalised', () {
      expect(matches('Has:link', message('see https://example.org')), isTrue);
      expect(matches('Has:link', message('no link here')), isFalse);
    });
  });

  group('MatrixSearchParameters.parse', () {
    test('drops empty words and filter keywords', () {
      final params =
          MatrixSearchParameters.parse('  Hello   world has:link From:@a:b ');
      expect(params.words, ['Hello', 'world']);
      expect(params.requireUrl, isTrue);
      expect(params.requiredSender, '@a:b');
    });

    test('filters only leave no words', () {
      final params = MatrixSearchParameters.parse('has:image ');
      expect(params.words, isEmpty);
      expect(params.requireImage, isTrue);
    });

    test('type: keeps its value as typed', () {
      final params = MatrixSearchParameters.parse('Type:m.image');
      expect(params.requiredType, 'm.image');
      expect(params.words, isEmpty);
    });
  });

  group('unencrypted room search with only filters (Vommet issue 601)', () {
    test('a from: query alone scans the timeline locally', () {
      expect(
          MatrixServerEventSearchSession.needsLocalScan(
              MatrixSearchParameters.parse('from:@bob:example.org')),
          isTrue);
      expect(
          MatrixServerEventSearchSession.needsLocalScan(
              MatrixSearchParameters.parse('From:@bob:example.org ')),
          isTrue);
    });

    test('a query with words still uses the server search', () {
      expect(
          MatrixServerEventSearchSession.needsLocalScan(
              MatrixSearchParameters.parse('hello from:@bob:example.org')),
          isFalse);
    });

    test('the local scan lists only that sender\'s messages', () {
      expect(
          matches('from:@bob:example.org',
              message('hi there', sender: '@bob:example.org')),
          isTrue);
      expect(matches('from:@bob:example.org', message('hi there')), isFalse);
    });
  });
}
