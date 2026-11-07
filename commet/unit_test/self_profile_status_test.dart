import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:commet/client/components/component.dart';
import 'package:commet/client/matrix/matrix_server_features.dart';
import 'package:commet/main.dart' as app;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/self_status_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await app.preferences.init();
  });

  testWidgets(
      'self profile revalidates persisted SDK status, shares and bounds reads',
      (tester) async {
    await tester.runAsync(() async {
      final f = SelfStatusFixture();
      await f.init();
      try {
        final profiles = await Future.wait([f.profile(), f.profile()]);
        expect(profiles.map(profileStatus), everyElement('SERVER B'));
        final requests = f.presenceGets;
        expect(requests, 2,
            reason: 'one capability probe plus one shared self refresh');
        expect(profileStatus(await f.profile()), 'SERVER B');
        expect(f.presenceGets, requests);
      } finally {
        await f.close();
      }
    });
  });

  for (final message in <String?>[null, '']) {
    testWidgets(
        'successful ${message == null ? 'missing' : 'empty'} status never revives legacy text',
        (tester) async {
      await tester.runAsync(() async {
        final f = SelfStatusFixture()..serverStatus = message;
        await f.init();
        try {
          expect(profileStatus(await f.profile()), isNull);
          expect(profileStatus(await f.profile(refresh: false)), isNull);
          expect(profileStatus(f.account.profile.cachedProfile(selfStatusId)!),
              isNull);
        } finally {
          await f.close();
        }
      });
    });
  }

  testWidgets('denied self presence does not disclose legacy fallback',
      (tester) async {
    await tester.runAsync(() async {
      final f = SelfStatusFixture()..errorStatus = 403;
      await f.init();
      try {
        expect(profileStatus(await f.profile()), isNull);
        final requests = f.presenceGets;
        await f.profile();
        expect(f.presenceGets, requests);
      } finally {
        await f.close();
      }
    });
  });

  testWidgets(
      'local clear writes standard empty status without dual-writing profile',
      (tester) async {
    await tester.runAsync(() async {
      final f = SelfStatusFixture();
      await f.init();
      try {
        await f.profile();
        await f.account.profile.setStatus(null);
        expect(f.serverStatus, '');
        expect(
            f.requests.where((r) =>
                r.method == 'DELETE' ||
                (r.method == 'PUT' && r.url.path.contains('/profile/'))),
            isEmpty);
        expect(profileStatus(await f.profile(refresh: false)), isNull);
      } finally {
        await f.close();
      }
    });
  });

  testWidgets(
      'overlapping save then clear preserves write order and clear barrier',
      (tester) async {
    await tester.runAsync(() async {
      final f = SelfStatusFixture();
      await f.init();
      final release = Completer<void>();
      Future<void>? save, clear;
      try {
        expect(profileStatus(await f.profile()), 'SERVER B');
        f.delayedWrite = release;
        save = f.account.profile.setStatus('OLDER SAVE');
        await f.delayedWriteStarted.future;
        clear = f.account.profile.setStatus(null);
        await Future<void>(() {});
        expect(profileStatus(await f.profile(refresh: false)), isNull);
        expect(f.requests.where((r) => r.method == 'PUT'), hasLength(1),
            reason: 'later clear waits for the older transport write');
        release.complete();
        await Future.wait([save, clear]);
        expect(f.serverStatus, '');
        expect(profileStatus(await f.profile(refresh: false)), isNull);
      } finally {
        if (!release.isCompleted) release.complete();
        if (save != null) await save;
        if (clear != null) await clear;
        await f.close();
      }
    });
  });

  testWidgets('late direct response cannot overwrite newer self sync',
      (tester) async {
    await tester.runAsync(() async {
      final f = SelfStatusFixture();
      await f.init();
      try {
        // Resolve capability probing before delaying the dedicated refresh.
        await MatrixServerFeatures.of(f.account);
        f.delayedPresence = Completer<http.Response>();
        final lookup = f.profile();
        // The base returns its stale cache; the fix starts the direct read.
        await Future.any<void>(
            [f.delayedReadStarted.future, lookup.then<void>((_) {})]);
        await f.sync('SYNC NEW');
        f.delayedPresence!.complete(
            http.Response('{"presence":"online","status_msg":"OLD"}', 200));
        expect(profileStatus(await lookup), 'SYNC NEW');
      } finally {
        await f.close();
      }
    });
  });
  testWidgets('explicit unsupported presence retains profile-only mode',
      (tester) async {
    await tester.runAsync(() async {
      final f = SelfStatusFixture()
        ..errorStatus = 404
        ..errorCode = 'M_UNRECOGNIZED';
      await f.init();
      try {
        expect(profileStatus(await f.profile()), legacyStatus);
        await f.sync('UNRELATED STANDARD');
        expect(profileStatus(await f.profile(refresh: false)), legacyStatus);
        await f.account.profile.setStatus('PROFILE ONLY');
        expect(profileStatus(await f.profile(refresh: false)), 'PROFILE ONLY');
        expect(
            f.requests.where(
                (r) => r.method == 'PUT' && r.url.path.contains('/profile/')),
            hasLength(1));
        expect(
            f.requests.where(
                (r) => r.method == 'PUT' && r.url.path.contains('/presence/')),
            isEmpty);
      } finally {
        await f.close();
      }
    });
  });

  for (final failure in <Object>[
    const SocketException('Synthetic offline'),
    TimeoutException('Synthetic timeout'),
  ]) {
    testWidgets(
        'unavailable lookup suppresses stale and legacy text: ${failure.runtimeType}',
        (tester) async {
      await tester.runAsync(() async {
        final f = SelfStatusFixture()..presenceFailure = failure;
        await f.init();
        try {
          expect(profileStatus(await f.profile()), isNull);
          final gets = f.presenceGets;
          await f.profile();
          expect(f.presenceGets, gets);
        } finally {
          await f.close();
        }
      });
    });
  }

  testWidgets('failed clear cannot revive previous text', (tester) async {
    await tester.runAsync(() async {
      final f = SelfStatusFixture();
      await f.init();
      try {
        await f.profile();
        f.failWrite = true;
        await expectLater(f.account.profile.setStatus(null), throwsStateError);
        expect(profileStatus(await f.profile(refresh: false)), isNull);
      } finally {
        await f.close();
      }
    });
  });

  testWidgets('status writes preserve pinned invisible mode', (tester) async {
    await tester.runAsync(() async {
      final f = SelfStatusFixture();
      await f.init();
      try {
        await app.preferences.experimentQuickProfileControls.set(true);
        await app.preferences
            .setPresenceMode(f.account.identifier, 'invisible');
        await f.account.profile.setStatus('NEW');
        final writes = f.requests.where((r) => r.method == 'PUT').toList();
        expect(writes, hasLength(1));
        expect(writes.single.url.path, contains('/presence/'));
        expect(jsonDecode(writes.single.body),
            {'presence': 'offline', 'status_msg': 'NEW'});
      } finally {
        await f.close();
      }
    });
  });

  testWidgets('closed profile ignores a late direct response', (tester) async {
    await tester.runAsync(() async {
      final f = SelfStatusFixture();
      await f.init();
      try {
        await MatrixServerFeatures.of(f.account);
        f.delayedPresence = Completer<http.Response>();
        final lookup = f.profile();
        await Future.any<void>(
            [f.delayedReadStarted.future, lookup.then<void>((_) {})]);
        final Object component = f.account.profile;
        if (component is NeedsCloseOnClientClose) {
          await component.onClientClosed();
        }
        f.delayedPresence!.complete(
            http.Response('{"presence":"online","status_msg":"OLD"}', 200));
        expect(profileStatus(await lookup), isNull);
      } finally {
        await f.close();
      }
    });
  });
  testWidgets('local clear beats an already pending direct read',
      (tester) async {
    await tester.runAsync(() async {
      final f = SelfStatusFixture();
      await f.init();
      try {
        await MatrixServerFeatures.of(f.account);
        f.delayedPresence = Completer<http.Response>();
        final lookup = f.profile();
        await Future.any<void>(
            [f.delayedReadStarted.future, lookup.then<void>((_) {})]);
        final clear = f.account.profile.setStatus(null);
        await Future<void>(() {});
        f.delayedPresence!.complete(
            http.Response('{"presence":"online","status_msg":"OLD"}', 200));
        await clear;
        expect(profileStatus(await lookup), isNull);
        expect(profileStatus(await f.profile(refresh: false)), isNull);
      } finally {
        await f.close();
      }
    });
  });
}
