import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/utils/background_tasks/background_task_manager.dart';

class ClientConnectionStatusTask extends BackgroundTaskWithOptionalProgress {
  Client client;

  StreamController<void> controller = StreamController.broadcast();

  StreamSubscription? sub;

  /// Vommet: clicking the badge hides it, so it no longer covers the
  /// controls under it.
  @override
  bool get canCallAction => true;

  @override
  void Function()? action;

  /// Called when the user dismisses the badge while it isn't showing
  /// "connected".
  final void Function()? onDismissed;

  bool _dismissed = false;

  @override
  double? progress;

  @override
  String get label => client.self == null
      ? switch (status) {
          BackgroundTaskStatus.running => "Connecting...",
          BackgroundTaskStatus.failed => "Disconnected",
          BackgroundTaskStatus.completed => "Connected",
        }
      : switch (status) {
          BackgroundTaskStatus.running =>
            "${client.self!.displayName} connecting...",
          BackgroundTaskStatus.failed =>
            "${client.self!.displayName} disconnected",
          BackgroundTaskStatus.completed =>
            "${client.self!.displayName} connected",
        };

  @override
  Stream<void> get statusChanged => controller.stream;

  @override
  BackgroundTaskStatus status = BackgroundTaskStatus.running;

  @override
  bool shouldRemoveTask = false;

  @override
  void dispose() {
    sub?.cancel();
  }

  ClientConnectionStatusTask(
      this.client, ClientConnectionStatusUpdate initialStatus,
      {this.onDismissed}) {
    action = dismiss;
    sub = client.connectionStatusChanged.stream.listen(onStatusUpdate);
    onStatusUpdate(initialStatus);
  }

  Timer? timer;

  void dismiss() {
    if (_dismissed) return;
    _dismissed = true;
    timer?.cancel();
    timer = null;
    shouldRemoveTask = true;
    if (status != BackgroundTaskStatus.completed) onDismissed?.call();
    controller.add(null);
  }

  void onStatusUpdate(ClientConnectionStatusUpdate event) {
    // The status stream can deliver once more before the manager drops a
    // dismissed badge; don't let that undo the removal.
    if (_dismissed) return;

    status = switch (event.status) {
      ClientConnectionStatus.unknown => BackgroundTaskStatus.running,
      ClientConnectionStatus.connected => BackgroundTaskStatus.completed,
      ClientConnectionStatus.connecting => BackgroundTaskStatus.running,
      ClientConnectionStatus.disconnected => BackgroundTaskStatus.failed,
    };
    progress = event.progress;

    if (event.status != ClientConnectionStatus.connected) {
      shouldRemoveTask = false;
      timer?.cancel();
      timer = null;
    }

    if (event.status == ClientConnectionStatus.connected && timer == null) {
      timer = Timer(const Duration(seconds: 5), () {
        shouldRemoveTask = true;
        controller.add(null);
      });
    }

    controller.add(null);
  }
}
