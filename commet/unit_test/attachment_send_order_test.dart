import 'dart:async';
import 'dart:typed_data';
import 'package:commet/client/attachment.dart';
import 'package:commet/client/matrix/matrix_attachment.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:shared_preferences/shared_preferences.dart';

class _Database implements matrix.DatabaseApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Client implements MatrixClient {
  _Client(this.sdk);
  final matrix.Client sdk;
  @override
  matrix.Client getMatrixClient() => sdk;
  @override
  matrix.Client get matrixClient => sdk;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      invocation.memberName == #spaces ? const <Never>[] : null;
}

class _SdkRoom extends matrix.Room {
  _SdkRoom(matrix.Client client)
      : super(id: '!fixture:example.org', client: client);
  final started = <String>[];
  final finished = <String>[];
  final gates = <String, Completer<void>>{};
  final metadata = <Map<String, dynamic>?>[];
  final threads = <String?>[];
  final textEvents = <Map<String, dynamic>>[];
  @override
  Future<String?> sendEvent(
    Map<String, dynamic> content, {
    String type = matrix.EventTypes.Message,
    String? txid,
    matrix.Event? inReplyTo,
    String? editEventId,
    String? threadRootEventId,
    String? threadLastEventId,
    bool displayPendingEvent = true,
  }) async {
    textEvents.add(content);
    return null;
  }

  @override
  Future<String?> sendFileEvent(
    matrix.MatrixFile file, {
    String? txid,
    matrix.Event? inReplyTo,
    String? editEventId,
    int? shrinkImageMaxDimension,
    matrix.MatrixImageFile? thumbnail,
    Map<String, dynamic>? extraContent,
    String? threadRootEventId,
    String? threadLastEventId,
    bool displayPendingEvent = true,
  }) async {
    started.add(file.name);
    metadata.add(extraContent);
    threads.add(threadRootEventId);
    await gates[file.name]?.future;
    finished.add(file.name);
    return null;
  }
}

class _ProcessingRoom extends MatrixRoom {
  _ProcessingRoom(super.client, super.room, super.matrixClient);
  final processing = <String, Completer<MatrixProcessedAttachment?>>{};
  @override
  Future<MatrixProcessedAttachment?> processAttachment(
          PendingFileAttachment attachment) =>
      processing[attachment.name]!.future;
}

MatrixProcessedAttachment file(String name) => MatrixProcessedAttachment(
    matrix.MatrixFile(bytes: Uint8List.fromList([1, 2]), name: name));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late matrix.Client sdk;
  late _SdkRoom sdkRoom;
  late _Client client;
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    sdk = matrix.Client('attachment-order-fixture', database: _Database());
    sdkRoom = _SdkRoom(sdk);
    client = _Client(sdk);
  });
  tearDown(() async {
    await sdk.dispose(closeDatabase: false);
  });

  test('a later small file cannot overtake the first SDK upload', () async {
    final room = MatrixRoom(client, sdkRoom, sdk);
    sdkRoom.gates['first.mp4'] = Completer<void>();
    sdkRoom.gates['second.png'] = Completer<void>();
    final sending = room.sendMessage(processedAttachments: [
      file('first.mp4'),
      file('second.png'),
      file('third.pdf')
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(sdkRoom.started, ['first.mp4']);
    // The second upload can finish immediately once called, but must wait its turn.
    sdkRoom.gates['second.png']!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(sdkRoom.finished, isEmpty);
    sdkRoom.gates['first.mp4']!.complete();
    await sending;
    await Future<void>.delayed(Duration.zero);
    expect(sdkRoom.finished, ['first.mp4', 'second.png', 'third.pdf']);
  });

  test('a failed SDK send retains existing later-file behavior in order',
      () async {
    final room = MatrixRoom(client, sdkRoom, sdk);
    final first = sdkRoom.gates['first.mp4'] = Completer<void>();
    final sending = room.sendMessage(
        processedAttachments: [file('first.mp4'), file('second.pdf')]);
    await Future<void>.delayed(Duration.zero);
    expect(sdkRoom.started, ['first.mp4']);
    first.completeError(StateError('fixture upload failure'));
    await sending;
    await Future<void>.delayed(Duration.zero);
    expect(sdkRoom.started, ['first.mp4', 'second.pdf']);
    expect(sdkRoom.finished, ['second.pdf']);
  });

  test('caption retains its existing separate send while ordered uploads wait',
      () async {
    final room = MatrixRoom(client, sdkRoom, sdk);
    sdkRoom.gates['first.mp4'] = Completer<void>();
    await room.sendMessage(message: 'My caption', processedAttachments: [
      file('first.mp4'),
      file('second.pdf')
    ]).timeout(const Duration(seconds: 2));
    expect(sdkRoom.started, ['first.mp4']);
    expect(sdkRoom.finished, isEmpty);
    expect(sdkRoom.textEvents.single['body'], 'My caption');
    sdkRoom.gates['first.mp4']!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(sdkRoom.finished, ['first.mp4', 'second.pdf']);
    expect(sdkRoom.metadata.first!['im.vommet.send_batch'],
        sdkRoom.textEvents.single['im.vommet.send_batch']);
  });

  test('thread and spoiler metadata remain with each ordered file', () async {
    final room = MatrixRoom(client, sdkRoom, sdk);
    final first = file('first.png')
      ..spoiler = true
      ..spoilerReason = 'Plot';
    await room.sendMessage(
        processedAttachments: [first, file('second.pdf')],
        threadRootEventId: r'$thread');
    await Future<void>.delayed(Duration.zero);
    expect(sdkRoom.started, ['first.png', 'second.pdf']);
    expect(sdkRoom.threads, [r'$thread', r'$thread']);
    expect(
        sdkRoom.metadata.first!.keys.any((k) => k.contains('spoiler')), isTrue);
    expect(
        sdkRoom.metadata.last!.keys.any((k) => k.contains('spoiler')), isFalse);
    expect(sdkRoom.metadata.first!['im.vommet.send_batch'],
        sdkRoom.metadata.last!['im.vommet.send_batch']);
  });

  test('processing finishing in reverse order preserves input order', () async {
    final room = _ProcessingRoom(client, sdkRoom, sdk);
    final inputs = [
      for (final name in ['first.png', 'second.pdf', 'third.mp4'])
        PendingFileAttachment(name: name, data: Uint8List(0))
    ];
    for (final f in inputs) {
      room.processing[f.name!] = Completer<MatrixProcessedAttachment?>();
    }
    final future = room.processAttachments(inputs);
    for (final f in inputs.reversed) {
      room.processing[f.name!]!.complete(file(f.name!));
    }
    final result = await future;
    expect(result.cast<MatrixProcessedAttachment>().map((f) => f.file.name),
        inputs.map((f) => f.name));
  });

  test(
      'send snapshot keeps edits/options when the pending file is edited later',
      () {
    final original = PendingFileAttachment(
        name: 'same.png', data: Uint8List.fromList([1]), mimeType: 'image/png')
      ..thumbnailFile = Uint8List.fromList([2])
      ..spoiler = true
      ..spoilerReason = 'Plot'
      ..removeHiddenInfo = true
      ..shrinkLongestEdge = 960;
    final snapshot = original.snapshotForSend();
    original.data = Uint8List.fromList([3]);
    original.name = 'changed.png';
    original.spoiler = false;
    original.shrinkLongestEdge = null;
    expect(snapshot.data, [1]);
    expect(snapshot.name, 'same.png');
    expect(snapshot.thumbnailFile, [2]);
    expect(snapshot.spoiler, isTrue);
    expect(snapshot.spoilerReason, 'Plot');
    expect(snapshot.removeHiddenInfo, isTrue);
    expect(snapshot.shrinkLongestEdge, 960);
  });
}
