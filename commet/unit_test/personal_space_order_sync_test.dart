import 'dart:convert';

import 'package:commet/client/components/personal_space_order.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_space.dart';
import 'package:commet/main.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:shared_preferences/shared_preferences.dart';

import 'roomlist_fixture.dart';

const parent = '!space:example.com';
const siblingParent = '!other:example.com';
const a = '!a:example.com';
const b = '!b:example.com';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late MatrixClient client;
  late MatrixSpace space;
  late List<http.Request> writes;
  var n = 0;
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    client = await signedInClient('personal-child-order-${n++}');
    await sync(client, join: {
      parent: joined(parent, children: [a, b], name: 'Space'),
      siblingParent: joined(siblingParent, children: [a, b]),
      a: joined(a, name: 'A'),
      b: joined(b, name: 'B'),
    });
    space = client.getSpace(parent) as MatrixSpace;
    writes = [];
    final previous = client.getMatrixClient().httpClient;
    client.getMatrixClient().httpClient = MockClient((request) async {
      if (request.method == 'PUT') {
        writes.add(request);
        return http.Response('{}', 200,
            headers: {'content-type': 'application/json'});
      }
      return previous.send(request).then(http.Response.fromStream);
    });
  });
  tearDown(() => client.getMatrixClient().dispose(closeDatabase: true));

  test(
      'personal save writes only this account and parent; shared state unchanged',
      () async {
    final mx = client.getMatrixClient();
    expect(space.personalOrderAccountId, me);
    final before = space.allChildren.map((c) => c.id).toList();
    space.matrixRoom.roomAccountData[PersonalSpaceOrdering.type] =
        matrix.BasicEvent(type: PersonalSpaceOrdering.type, content: {
      'future': {'keep': true}
    });
    mx.accountData['chat.commet.sidebar_ordering'] =
        matrix.BasicEvent(type: 'chat.commet.sidebar_ordering', content: {
      'spaces': {
        'top': {'order': 'a'}
      }
    });
    await space.savePersonalChildOrder([b, a]);
    expect(writes, hasLength(1));
    expect(
        Uri.decodeComponent(writes.single.url.path),
        endsWith(
            '/user/$me/rooms/$parent/account_data/${PersonalSpaceOrdering.type}'));
    expect(jsonDecode(writes.single.body), {
      'future': {'keep': true},
      'order': [b, a]
    });
    expect(space.childrenForMe.map((c) => c.id), [b, a]);
    expect(space.allChildren.map((c) => c.id), before);
    expect((client.getSpace(siblingParent) as MatrixSpace).personalChildOrder,
        isNull);
    expect(mx.accountData['chat.commet.sidebar_ordering']!.content['spaces'], {
      'top': {'order': 'a'}
    });
    await space.savePersonalChildOrder(null);
    expect(jsonDecode(writes.last.body), {
      'future': {'keep': true}
    });
    expect(space.personalChildOrder, isNull);
    expect(writes.every((r) => r.url.path.contains('/account_data/')), isTrue);
  });
  test(
      'a sync from another device refreshes hierarchy order and notifies views',
      () async {
    var changed = 0;
    final sub = space.onUpdate.listen((_) => changed++);
    await sync(client, join: {
      parent: matrix.JoinedRoomUpdate(accountData: [
        matrix.BasicEvent(type: PersonalSpaceOrdering.type, content: {
          'order': [b, a]
        })
      ])
    });
    expect(space.personalChildOrder, [b, a]);
    expect(space.childrenForMe.map((c) => c.id), [b, a]);
    expect(changed, greaterThan(0));
    final previous = changed;
    await sync(client, join: {
      parent: matrix.JoinedRoomUpdate(accountData: [
        matrix.BasicEvent(type: PersonalSpaceOrdering.type, content: {
          'order': [b, a]
        })
      ])
    });
    expect(changed, previous, reason: 'Identical order must not notify again');
    await sub.cancel();
    expect(writes, isEmpty);
  });
  test('another account has an independent order for the same parent',
      () async {
    final other = await signedInClient('personal-child-other-${n++}',
        userId: '@other:example.com');
    try {
      await sync(other, join: {
        parent: joined(parent, children: [a, b]),
        a: joined(a),
        b: joined(b)
      });
      expect((other.getSpace(parent) as MatrixSpace).personalOrderAccountId,
          '@other:example.com');
      await space.savePersonalChildOrder([b, a]);
      expect(space.childrenForMe.map((c) => c.id), [b, a]);
      expect(
          (other.getSpace(parent) as MatrixSpace).personalChildOrder, isNull);
    } finally {
      await other.getMatrixClient().dispose(closeDatabase: true);
    }
  });
}
