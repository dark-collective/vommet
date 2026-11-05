import 'package:commet/client/client.dart';
import 'package:commet/client/tasks/client_connection_status_task.dart';
import 'package:commet/utils/background_tasks/background_task_manager.dart';
import 'package:commet/utils/stored_stream_controller.dart';
import 'package:test/test.dart';

class _FakeClient implements Client {
  @override
  final StoredStreamController<ClientConnectionStatusUpdate>
      connectionStatusChanged = StoredStreamController();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ClientConnectionStatusUpdate _update(ClientConnectionStatus status) =>
    ClientConnectionStatusUpdate(status);

void main() {
  test('clicking a "disconnected" badge removes it and reports it', () async {
    final client = _FakeClient();
    var dismissed = 0;
    final manager = BackgroundTaskManager();
    final task = ClientConnectionStatusTask(
        client, _update(ClientConnectionStatus.disconnected),
        onDismissed: () => dismissed++);
    manager.addTask(task);

    expect(task.canCallAction, isTrue);
    task.action!.call();
    // A retry arriving before the manager drops the badge doesn't revive it.
    client.connectionStatusChanged
        .add(_update(ClientConnectionStatus.connecting));
    await Future<void>.delayed(Duration.zero);

    expect(manager.tasks, isEmpty);
    expect(dismissed, 1);
  });

  test('clicking a "connected" badge removes it without suppressing', () async {
    final client = _FakeClient();
    var dismissed = 0;
    final manager = BackgroundTaskManager();
    final task = ClientConnectionStatusTask(
        client, _update(ClientConnectionStatus.connected),
        onDismissed: () => dismissed++);
    manager.addTask(task);

    task.action!.call();
    await Future<void>.delayed(Duration.zero);

    expect(manager.tasks, isEmpty);
    expect(dismissed, 0);
  });
}
