import 'package:commet/client/alert.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class AlertView extends StatelessWidget {
  final Alert alert;

  /// Vommet: whether the alert's own close button ([Alert.onDismiss]) is
  /// shown here (a banner with a close button of its own passes false).
  final bool showDismiss;
  const AlertView(this.alert, {super.key, this.showDismiss = true});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        onTap: alert.action == null || alert.actionLabel != null
            ? null
            : () => alert.action?.call(context),
        child: Row(children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Icon(
              getIcon(),
              color: getColor(context),
            ),
          ),
          Flexible(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                tiamat.Text.labelEmphasised(alert.title),
                tiamat.Text.labelLow(alert.message),
                if (alert.actionLabel != null && alert.action != null)
                  TextButton(
                    style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 0),
                        visualDensity: VisualDensity.compact),
                    onPressed: () => alert.action?.call(context),
                    child: Text(alert.actionLabel!()),
                  ),
              ],
            ),
          ),
          if (showDismiss && alert.onDismiss != null)
            IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: alert.onDismiss,
                icon: const Icon(Icons.close, size: 18)),
        ]),
      ),
    );
  }

  IconData getIcon() {
    if (alert.icon != null) return alert.icon!;
    switch (alert.type) {
      case AlertType.info:
        return Icons.info;
      case AlertType.warning:
        return Icons.warning;
      case AlertType.critical:
        return Icons.dangerous;
    }
  }

  Color? getColor(BuildContext context) {
    switch (alert.type) {
      case AlertType.warning:
        return Colors.amber;
      case AlertType.critical:
        return Theme.of(context).colorScheme.error;
      default:
        return null;
    }
  }
}
