// Vommet: real shared-server lost-update regressions (Vommet issue 1171).
import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/isolate.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_dart_sdk_drift_db/database.dart';
import 'package:matrix_dart_sdk_drift_db/matrix_dart_sdk_drift_db.dart';

// Synthetic session material stays out of assertion output and SQL logs.
String _session(int generation, String field) => String.fromCharCodes(
      List.generate(24, (i) => 65 + (generation + field.length + i) % 26),
    );

Future<void> _insert(MatrixSdkDriftDatabase db, int generation) =>
    db.insertClient(
      'ownership',
      'https://example.invalid',
      _session(generation, 'access'),
      DateTime.utc(2030, 1, generation + 1),
      _session(generation, 'refresh'),
      '@synthetic:example.invalid',
      'DEVICE',
      'Synthetic',
      'initial-position',
      'initial-pickle',
      'synthetic-oidc',
    );

Future<void> _rotate(MatrixSdkDriftDatabase db, int generation) =>
    db.updateClient(
      'https://example.invalid',
      _session(generation, 'access'),
      DateTime.utc(2030, 1, generation + 1),
      _session(generation, 'refresh'),
      '@synthetic:example.invalid',
      'DEVICE',
      'Synthetic',
      'stale-position',
      'stale-pickle',
      'synthetic-oidc',
    );

void _expectSession(ClientDataData row, int generation) {
  expect(
    row.token == _session(generation, 'access'),
    isTrue,
    reason: 'persisted access session generation',
  );
  expect(
    row.refreshToken == _session(generation, 'refresh'),
    isTrue,
    reason: 'persisted refresh session generation',
  );
  expect(row.tokenExpiresAt, DateTime.utc(2030, 1, generation + 1));
  expect(row.oidcClientId, 'synthetic-oidc');
}

// Hold the write after any old whole-row SELECT has returned, but before
// sending it to the shared server. The fixed UPDATE reaches the same gate
// without a SELECT. Never record SQL arguments (they contain sessions).
class _WriteGate extends QueryInterceptor {
  Completer<void>? reached;
  Completer<void>? release;
  int reads = 0;
  int writes = 0;

  void arm() {
    reads = writes = 0;
    reached = Completer<void>();
    release = Completer<void>();
  }

  Future<void> _hold(String sql) async {
    if (!sql.contains('client_data')) return;
    writes++;
    final gate = release;
    if (gate != null) {
      reached!.complete();
      await gate.future;
      release = null;
    }
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (statement.contains('client_data')) reads++;
    return executor.runSelect(statement, args);
  }

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    await _hold(statement);
    return executor.runInsert(statement, args);
  }

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    await _hold(statement);
    return executor.runUpdate(statement, args);
  }
}

void main() {
  // Separate executors connected to one serialized Drift server are intentional.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late DriftIsolate server;
  late MatrixSdkDriftDatabase app;
  late MatrixSdkDriftDatabase notification;
  late _WriteGate gate;

  setUp(() async {
    server = DriftIsolate.inCurrent(
      () => NativeDatabase.memory(),
      serialize: true,
    );
    gate = _WriteGate();
    app = await MatrixSdkDriftDatabase.init(
      await server.connect(),
      'ownership',
    );
    notification = await MatrixSdkDriftDatabase.init(
      (await server.connect()).interceptWith(gate),
      'ownership',
    );
    // Finish schema/open work before arming the gate.
    await app.getClient('ownership');
    await notification.getClient('ownership');
  });

  tearDown(() async {
    gate.release?.complete();
    await notification.close();
    await app.close();
    await server.shutdownAll();
  });

  for (final field in ['prevBatch', 'olmAccount', 'syncFilterId']) {
    test('$field write preserves a concurrently rotated session', () async {
      await _insert(app, 0);
      gate.arm();
      final pending = switch (field) {
        'prevBatch' => notification.storePrevBatch('new-position'),
        'olmAccount' => notification.updateClientKeys('new-pickle'),
        _ => notification.storeSyncFilterId('new-filter'),
      };
      await gate.reached!.future;
      await _rotate(app, 1);
      gate.release!.complete();
      await pending;
      final row = await app.db.select(app.db.clientData).getSingle();
      printOnFailure(
        'client_data steps: ${gate.reads} reads, ${gate.writes} writes',
      );
      _expectSession(row, 1);
      expect(
        switch (field) {
          'prevBatch' => row.prevBatch,
          'olmAccount' => row.olmAccount,
          _ => row.syncFilterId,
        },
        switch (field) {
          'prevBatch' => 'new-position',
          'olmAccount' => 'new-pickle',
          _ => 'new-filter',
        },
      );
      expect(gate.reads, 0, reason: 'no stale whole-row read');
      expect(gate.writes, 1, reason: 'one bounded column update');
    });
  }

  for (final field in ['prevBatch', 'olmAccount']) {
    test('updateClient preserves newer $field and filter fields', () async {
      await _insert(app, 0);
      gate.arm();
      final pending = _rotate(notification, 1);
      await gate.reached!.future;
      if (field == 'prevBatch') {
        await app.storePrevBatch('new-position');
      } else {
        await app.updateClientKeys('new-pickle');
      }
      await app.storeSyncFilterId('new-filter');
      gate.release!.complete();
      await pending;
      final row = await app.db.select(app.db.clientData).getSingle();
      printOnFailure(
        'client_data steps: ${gate.reads} reads, ${gate.writes} writes',
      );
      _expectSession(row, 1);
      // Expose this case's ownership regression before checking its controls.
      if (field == 'olmAccount') {
        expect(row.olmAccount, 'new-pickle');
        expect(row.prevBatch, 'initial-position');
      } else {
        expect(row.prevBatch, 'new-position');
        expect(row.olmAccount, 'initial-pickle');
      }
      expect(row.syncFilterId, 'new-filter');
      expect(row.name, 'ownership');
      expect(gate.reads, 0);
      expect(gate.writes, 1);
    });
  }

  test(
    'first insert and explicit initialization upsert keep their fields',
    () async {
      await _insert(app, 0);
      var row = await app.db.select(app.db.clientData).getSingle();
      _expectSession(row, 0);
      expect(row.prevBatch, 'initial-position');
      expect(row.olmAccount, 'initial-pickle');
      await app.storeSyncFilterId('new-filter');
      await _insert(notification, 1);
      row = await app.db.select(app.db.clientData).getSingle();
      _expectSession(row, 1);
      expect(row.prevBatch, 'initial-position');
      expect(row.olmAccount, 'initial-pickle');
      expect(row.syncFilterId, 'new-filter');
    },
  );

  test('missing-row writers preserve no-op and error behavior', () async {
    await app.storePrevBatch('new-position');
    await _rotate(app, 1);
    await expectLater(app.updateClientKeys('new-pickle'), throwsStateError);
    await expectLater(app.storeSyncFilterId('new-filter'), throwsStateError);
    expect(await app.getClient('ownership'), isNull);
    await _insert(app, 0);
    expect(await app.getClient('ownership'), isNotNull);
  });
}
