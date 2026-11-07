import 'dart:async';

import 'package:commet/client/alert.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_list_view.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_source.dart';
import 'package:flutter/material.dart';

/// Vommet: the app's alerts on New Home, which has no Alerts panel: one
/// banner each atop the main area, on every tab (the same [AlertBanner]
/// Telegram and Custom mix show above their chat list). Closing one hides
/// it for this session in every layout; an alert with its own close action
/// (the encryption offer: Not now) still gets it.
class NewHomeAlerts extends StatefulWidget {
  const NewHomeAlerts({super.key, required this.manager});

  final AlertManager manager;

  @override
  State<NewHomeAlerts> createState() => _NewHomeAlertsState();
}

class _NewHomeAlertsState extends State<NewHomeAlerts> {
  late List<StreamSubscription> _subs;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(NewHomeAlerts old) {
    super.didUpdateWidget(old);
    if (old.manager != widget.manager) {
      _cancel();
      _listen();
    }
  }

  void _listen() {
    _subs = [
      widget.manager.onAlertAdded.listen(_changed),
      widget.manager.onAlertRemoved.listen(_changed),
    ];
  }

  void _cancel() {
    for (final sub in _subs) {
      sub.cancel();
    }
  }

  void _changed(Object? _) {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final alerts = UnifiedChatSource.visibleAlerts(widget.manager);
    if (alerts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final alert in alerts)
            AlertBanner(alert, onDismiss: () {
              UnifiedChatSource.dismissForSession(alert);
              _changed(null);
            }),
        ],
      ),
    );
  }
}
