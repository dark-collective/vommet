import 'package:commet/utils/notifying_list.dart';
import 'package:flutter/widgets.dart';

enum AlertType { info, warning, critical }

class Alert {
  late String Function() _messageGetter;
  late String Function() _titleGetter;
  late Function(BuildContext context)? action;
  AlertType type;

  /// Vommet: a button for [action] (otherwise the whole alert is tapped).
  final String Function()? actionLabel;

  /// Vommet: the alert has a close button that does this (dismissed for
  /// good, not only for this session).
  final void Function()? onDismiss;

  /// Vommet: an icon instead of the type's.
  final IconData? icon;

  String get title => _titleGetter();
  String get message => _messageGetter();

  Alert(this.type,
      {required String Function() messageGetter,
      required String Function() titleGetter,
      this.action,
      this.actionLabel,
      this.onDismiss,
      this.icon}) {
    _messageGetter = messageGetter;
    _titleGetter = titleGetter;
  }
}

class AlertManager {
  final NotifyingList<Alert> _alerts = NotifyingList.empty(growable: true);

  Stream<Alert> get onAlertAdded => _alerts.onAdd;

  Stream<Alert> get onAlertRemoved => _alerts.onRemove;

  List<Alert> get alerts => _alerts;

  void addAlert(Alert alert) {
    _alerts.add(alert);
  }

  void clearAlert(Alert alert) {
    _alerts.remove(alert);
  }
}
