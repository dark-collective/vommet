import 'dart:async';

import 'package:commet/utils/notification_diagnostics/diagnostic_strings.dart';
import 'package:flutter/foundation.dart';

enum DiagnosticStatus {
  notChecked,
  checking,
  passed,
  failed,
  attention,
  unknown,
  unavailable;

  String get label => switch (this) {
        notChecked => DiagnosticStrings.notChecked,
        checking => DiagnosticStrings.checking,
        passed => DiagnosticStrings.passed,
        failed => DiagnosticStrings.failed,
        attention => DiagnosticStrings.attention,
        unknown => DiagnosticStrings.unknown,
        unavailable => DiagnosticStrings.unavailable,
      };
}

enum DiagnosticAction { androidSettings, notificationSettings }

/// Display data never contains keys, endpoints, SDK responses or exceptions.
class DiagnosticResult {
  const DiagnosticResult(this.title, this.status, this.detail, {this.action});
  final String title, detail;
  final DiagnosticStatus status;
  final DiagnosticAction? action;
}

List<DiagnosticResult> one(String title, DiagnosticStatus state, String detail,
        [DiagnosticAction? action]) =>
    [DiagnosticResult(title, state, detail, action: action)];

class DiagnosticCheck {
  const DiagnosticCheck(this.title, this.read);
  final String title;
  final Future<List<DiagnosticResult>> Function() read;
}

abstract interface class NotificationDiagnosticReader {
  List<DiagnosticCheck> get checks;
  bool get isCurrent;
}

/// One bounded run. Cancellation ignores late completions; it cannot abort an
/// SDK request already sent. There are no timers or listeners after disposal.
class NotificationDiagnosticController extends ChangeNotifier {
  NotificationDiagnosticController(this.createReader,
      {this.timeout = const Duration(seconds: 15)});
  final NotificationDiagnosticReader Function() createReader;
  final Duration timeout;
  List<List<DiagnosticResult>> results = [];
  bool running = false;
  String? notice;
  int _generation = 0;
  Future<void> run() async {
    if (running) return;
    final generation = ++_generation;
    late NotificationDiagnosticReader reader;
    try {
      reader = createReader();
    } catch (_) {
      results = [
        one(DiagnosticStrings.configuration, DiagnosticStatus.unknown,
            DiagnosticStrings.setupError)
      ];
      notifyListeners();
      return;
    }
    final checks = reader.checks;
    running = true;
    notice = null;
    results = [
      for (final c in checks)
        one(c.title, DiagnosticStatus.notChecked, DiagnosticStrings.waiting)
    ];
    notifyListeners();
    for (var i = 0; i < checks.length; i++) {
      if (generation != _generation) return;
      results[i] = one(checks[i].title, DiagnosticStatus.checking,
          DiagnosticStrings.reading);
      notifyListeners();
      List<DiagnosticResult> next;
      try {
        next = await checks[i].read().timeout(timeout);
      } on TimeoutException {
        next = one(checks[i].title, DiagnosticStatus.unknown,
            DiagnosticStrings.timeout);
      } catch (_) {
        next = one(checks[i].title, DiagnosticStatus.unknown,
            DiagnosticStrings.readError);
      }
      if (generation != _generation) return;
      bool current;
      try {
        current = reader.isCurrent;
      } catch (_) {
        current = false;
      }
      if (!current) {
        invalidate();
        return;
      }
      results[i] = next;
      notifyListeners();
    }
    running = false;
    notifyListeners();
  }

  void cancel() => invalidate(DiagnosticStrings.canceled);
  void invalidate([String? message]) {
    ++_generation;
    running = false;
    results = [];
    notice = message ?? DiagnosticStrings.changed;
    notifyListeners();
  }

  @override
  void dispose() {
    ++_generation;
    super.dispose();
  }
}
