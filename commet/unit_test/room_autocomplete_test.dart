// Vommet issue 1223: drive the public search including its final ranking pass.
import 'package:commet/client/client.dart';
import 'package:commet/client/components/emoticon/emoji_pack.dart';
import 'package:commet/client/components/emoticon/emoticon_component.dart';
import 'package:commet/client/components/room_component.dart';
import 'package:commet/client/member.dart';
import 'package:commet/client/permissions.dart';
import 'package:commet/utils/autofill_utils.dart';
import 'package:commet/utils/emoji/unicode_emoji.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;

import 'helpers/room_autocomplete_fixtures.dart';

void main() {
  late AutocompleteSetup setup;
  setUp(() => setup = AutocompleteSetup());
  List<String> search(String text, {bool dm = false}) =>
      AutofillUtils.search(text, setup.client,
              room: dm ? setup.dm : setup.current)
          .map((r) => r.slug)
          .toList();

  test('compatibility: user names and everyone stay searchable', () {
    final room = _OtherAutocompleteRoom(setup.client);
    for (final query in ['@alce', '@alice']) {
      expect(AutofillUtils.search(query, setup.client, room: room).first.slug,
          '@alice:example.org');
    }
    expect(
        AutofillUtils.search('@everyone', setup.client, room: room).first.slug,
        '@room');
  });
  test('compatibility: emoji keep their result type and insertion slug', () {
    final results = AutofillUtils.search(':fire', setup.client,
        room: _OtherAutocompleteRoom(setup.client));
    expect(results.single, isA<AutofillSearchResultEmoticon>());
    expect(results.single.slug, '🔥');
  });

  test('DM and standalone room find all joined addressed rooms and spaces', () {
    final expected = [
      '#general:example.org',
      '#garden:example.org',
      '#notes:example.org',
      '#community:example.org'
    ];
    expect(search('#', dm: true), unorderedEquals(expected));
    setup.parent.rooms.clear();
    expect(search('#'), unorderedEquals(expected));
  });

  test('related rooms beat exact unrelated matches through final fuzzy ranking',
      () {
    // A foreign wrapper sharing our room ID must not promote our global room.
    setup.parent.rooms.add(AutocompleteRoom(
        setup.otherAccount, setup.outside.identifier, 'Foreign Garden'));
    for (final query in ['#garden', '#gardan']) {
      final results = search(query);
      expect(
          results,
          containsAll([
            '#notes:example.org',
            '#community:example.org',
            '#garden:example.org'
          ]));
      expect(results.indexOf('#notes:example.org'),
          lessThan(results.indexOf('#garden:example.org')));
      expect(results.indexOf('#community:example.org'),
          lessThan(results.indexOf('#garden:example.org')));
    }
  });

  test('canonical and alternative alias queries insert the preferred address',
      () {
    expect(search('#seasonal-announcements'), ['#garden:example.org']);
    expect(search('#flowers:example.org'), contains('#garden:example.org'));
    expect(search('#garden:example.org'), contains('#garden:example.org'));
    final fallback = AutocompleteRoom(
        setup.client, '!fallback:example.org', 'Orchard',
        alias: '', alternatives: [null, '', 'invalid', '#fruit:example.org']);
    setup.client.rooms.add(fallback);
    expect(search('#fruit'), contains('#fruit:example.org'));
  });

  test(
      'exclude retained bans, non-joins, foreign accounts and unusable aliases',
      () {
    setup.parent.rooms.clear();
    for (final membership
        in matrix.Membership.values.where((m) => m != matrix.Membership.join)) {
      setup.client.rooms.add(AutocompleteRoom(
          setup.client, '!${membership.name}:example.org', 'Hidden',
          alias: '#${membership.name}:example.org', membership: membership));
      setup.client.spaces.add(AutocompleteSpace(
          setup.client, '!s${membership.name}:example.org', 'Hidden',
          alias: '#s${membership.name}:example.org', membership: membership));
    }
    setup.client.rooms.addAll([
      AutocompleteRoom(setup.otherAccount, '!foreign:example.org', 'Hidden',
          alias: '#foreign:example.org'),
      AutocompleteRoom(setup.client, '!empty:example.org', 'Hidden', alias: ''),
      AutocompleteRoom(setup.client, '!bad:example.org', 'Hidden',
          alias: '#bad address:example.org'),
    ]);
    setup.client.spaces.add(AutocompleteSpace(
        setup.otherAccount, '!foreignspace:example.org', 'Hidden',
        alias: '#foreignspace:example.org'));
    expect(
        search('#'),
        unorderedEquals([
          '#general:example.org',
          '#garden:example.org',
          '#notes:example.org',
          '#community:example.org'
        ]));
    expect(AutofillUtils.search('#', setup.otherAccount, room: setup.current),
        isEmpty);
    setup.otherAccount.rooms.add(AutocompleteRoom(
        setup.otherAccount, setup.outside.identifier, 'Private account name',
        alias: '#private:example.org'));
    expect(
        AutofillUtils.search('#', setup.otherAccount,
                room: setup.otherAccount.rooms.single)
            .map((r) => r.slug),
        ['#private:example.org']);
  });

  test(
      'multiple parents, ancestors and duplicate rooms keep one related result',
      () {
    final ancestor = AutocompleteSpace(
        setup.client, '!ancestor:example.org', 'Garden hub',
        alias: '#hub:example.org');
    ancestor.subspaces.add(setup.parent);
    setup.parent.subspaces.add(ancestor); // Invalid cycle must terminate.
    final second = AutocompleteSpace(
        setup.client, '!second:example.org', 'Second',
        alias: '#second:example.org');
    second.rooms.addAll([setup.current, setup.sibling, setup.sibling]);
    setup.client.spaces.addAll([ancestor, second]);
    setup.client.rooms.add(setup.sibling);
    final result = search('#garden');
    expect(result, contains('#hub:example.org'));
    expect(result.where((r) => r == '#notes:example.org'), hasLength(1));
    expect(result.last, '#garden:example.org');
  });

  test('all unaddressed rooms and spaces produce no room-ID suggestions', () {
    for (final room in setup.client.rooms.cast<AutocompleteRoom>()) {
      setLoadedAliases(room.matrixRoom, null);
    }
    setLoadedAliases(setup.parent.matrixRoom, {});
    expect(search('#'), isEmpty);
    setup.client.rooms.clear();
    setup.client.spaces.clear();
    expect(search('#'), isEmpty);
  });

  test(
      'malformed alias state admits only usable canonical or alternative addresses',
      () {
    final malformed =
        AutocompleteRoom(setup.client, '!malformed:example.org', 'Malformed');
    final alternative =
        AutocompleteRoom(setup.client, '!alternate:example.org', 'Alternate');
    setup.client.rooms.addAll([malformed, alternative]);
    setLoadedAliases(malformed.matrixRoom,
        {'alias': 42, 'alt_aliases': '#not-a-list:example.org'});
    setLoadedAliases(alternative.matrixRoom, {
      'alias': '#broken',
      'alt_aliases': [
        42,
        null,
        '',
        '#missing-server:',
        '#bad address:example.org',
        '#alternate:example.org',
        '#alternate:example.org'
      ]
    });
    expect(
        search('#'),
        unorderedEquals([
          '#general:example.org',
          '#garden:example.org',
          '#notes:example.org',
          '#community:example.org',
          '#alternate:example.org'
        ]));
    setLoadedAliases(alternative.matrixRoom,
        {'alias': '#canonical:example.org', 'alt_aliases': {}});
    expect(search('#'), contains('#canonical:example.org'));
    expect(search('#'), isNot(contains('#alternate:example.org')));
  });

  test(
      'space alternative aliases fall back then prefer the usable canonical address',
      () {
    final space = AutocompleteSpace(
        setup.client, '!observatory:example.org', 'Observatory',
        alias: '', alternatives: [null, '', '#observatory-news:example.org']);
    setup.client.spaces.add(space);
    expect(search('#observatory-news'), ['#observatory-news:example.org']);
    setLoadedAliases(space.matrixRoom, {
      'alias': '#preferred-hub:example.org',
      'alt_aliases': ['#observatory-news:example.org']
    });
    expect(search('#observatory-news'), ['#preferred-hub:example.org']);
  });

  test('loaded alias and membership changes are reflected by the next search',
      () {
    expect(search('#'), contains('#garden:example.org'));
    setLoadedAliases(
        setup.outside.matrixRoom, {'alias': '#new-address:example.org'});
    expect(search('#'), contains('#new-address:example.org'));
    expect(search('#'), isNot(contains('#garden:example.org')));
    setup.outside.matrixRoom.membership = matrix.Membership.leave;
    expect(search('#'), isNot(contains('#new-address:example.org')));
    setup.outside.matrixRoom.membership = matrix.Membership.join;
    expect(search('#'), contains('#new-address:example.org'));
    setup.parent.matrixRoom.membership = matrix.Membership.ban;
    expect(search('#'), isNot(contains('#community:example.org')));
    expect(search('#'), contains('#notes:example.org'));
  });

  test('compatibility: no match and no composing room keep empty results', () {
    expect(search('#zzzzzzzzzzzzzzzzzzzz'), isEmpty);
    expect(AutofillUtils.search('#', setup.client), isEmpty);
  });

  test('apply result limit after related ranking and deduplication', () {
    for (var i = 0; i < 30; i++) {
      setup.client.rooms.insert(
          0,
          AutocompleteRoom(setup.client, '!extra$i:example.org', 'Garden $i',
              alias: '#garden$i:example.org'));
    }
    final result = search('#');
    expect(result, hasLength(20));
    expect(
        result.take(3),
        unorderedEquals([
          '#general:example.org',
          '#notes:example.org',
          '#community:example.org'
        ]));
  });
}

class _Member extends Fake implements Member {
  @override
  String get identifier => '@alice:example.org';
  @override
  String get displayName => 'Alice';
  @override
  ImageProvider? get avatar => null;
  @override
  Color get defaultColor => Colors.blue;
}

class _Permissions extends Permissions {
  @override
  bool get canMentionRoom => true;
}

class _Pack extends Fake implements EmoticonPack {
  @override
  final emoji = [UnicodeEmoticon('🔥', shortcode: 'fire')];
}

class _Emoticons extends Fake implements RoomEmoticonComponent {
  @override
  final availableEmoji = <EmoticonPack>[_Pack()];
}

class _OtherAutocompleteRoom extends AutocompleteRoom {
  _OtherAutocompleteRoom(AutocompleteClient client)
      : super(client, '!other:example.org', 'Other');
  @override
  Timeline? get timeline => null;
  @override
  Iterable<String> get memberIds => ['@alice:example.org'];
  @override
  Member getMemberOrFallback(String id) => _Member();
  @override
  Permissions get permissions => _Permissions();
  @override
  T? getComponent<T extends RoomComponent>() {
    final component = _Emoticons();
    return component is T ? component as T : null;
  }
}
