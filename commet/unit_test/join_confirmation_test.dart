// Vommet issue 799: accepting an invite gives up instead of loading forever.
import 'dart:async';

import 'package:commet/client/components/invitation/join_confirmation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const short = Duration(milliseconds: 50);

  test('returns once a sync shows the room joined', () async {
    var joined = false;
    final syncs = StreamController<Object?>.broadcast();
    final done = joinWithConfirmation(
        request: () async {},
        joined: () => joined,
        syncs: syncs.stream,
        confirmLimit: const Duration(seconds: 5));
    await Future<void>.delayed(Duration.zero);
    syncs.add(null); // a sync without the join
    joined = true;
    syncs.add(null);
    await done;
    await syncs.close();
  });

  test('returns straight away when already joined', () async {
    await joinWithConfirmation(
        request: () async {},
        joined: () => true,
        syncs: const Stream.empty(),
        confirmLimit: short);
  });

  test('a /join that never answers ends in JoinNotConfirmed', () async {
    await expectLater(
        joinWithConfirmation(
            request: () => Completer<void>().future,
            joined: () => false,
            syncs: const Stream.empty(),
            requestLimit: short),
        throwsA(isA<JoinNotConfirmed>()));
  });

  test('a join sync never shows ends in JoinNotConfirmed', () async {
    final syncs = StreamController<Object?>.broadcast();
    await expectLater(
        joinWithConfirmation(
            request: () async {},
            joined: () => false,
            syncs: syncs.stream,
            confirmLimit: short),
        throwsA(isA<JoinNotConfirmed>()));
    await syncs.close();
  });

  test('a refused join passes the server error through', () async {
    await expectLater(
        joinWithConfirmation(
            request: () async => throw StateError('forbidden'),
            joined: () => false,
            syncs: const Stream.empty()),
        throwsA(isA<StateError>()));
  });

  test('the error reads as the user-facing message', () {
    expect(const JoinNotConfirmed().toString(),
        startsWith("Couldn't confirm you joined."));
  });
}
