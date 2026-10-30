import 'package:commet/config/layout_config.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/navigation/navigation_utils.dart';
import 'package:commet/ui/organisms/new_home/notifications_feed.dart';
import 'package:commet/ui/pages/main/main_page.dart';
import 'package:commet/utils/notification_debug_collect.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet issue 949: Settings › Notifications › Copy notification debug.
/// Shows what every badge counts, per room, as numbers only, and copies it
/// only when the user taps Copy. Nothing is sent anywhere.
class NotificationDebugEntry extends StatelessWidget {
  const NotificationDebugEntry({super.key});

  static const header = "Notification debug";
  static const title = "Copy notification debug";
  static const subtitle = "When badges look wrong: see what each one counts, "
      "per room, as numbers only. You see it before you copy it.";

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.bug_report_outlined),
      title: const Text(title),
      subtitle: const Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => NotificationDebugView.open(context),
    );
  }
}

class NotificationDebugView extends StatefulWidget {
  const NotificationDebugView({super.key, this.page = false});

  /// A full page with an app bar (phones), else a dialog's content.
  final bool page;

  static const title = "Notification debug";
  static const lead = "Only numbers: no room names, no messages, no user "
      "IDs, no servers. Rooms are #1, #2… in a new random order each time. "
      "Nothing is sent anywhere: copy it only if you're OK with what you see.";

  static Future<void> open(BuildContext context) {
    if (MediaQuery.of(context).desktop) {
      return showDialog(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
          child: const SizedBox(width: 640, child: NotificationDebugView()),
        ),
      );
    }
    return NavigationUtils.navigateTo(
        context, const NotificationDebugView(page: true));
  }

  @override
  State<NotificationDebugView> createState() => _NotificationDebugViewState();
}

class _NotificationDebugViewState extends State<NotificationDebugView> {
  NotificationsFeed? feed;
  String text = "";
  bool cardLoaded = false;
  bool copied = false;

  @override
  void initState() {
    super.initState();
    final manager = clientManager;
    if (manager == null) return;
    collect();
    // The Notifications card's list loads while someone watches it; take
    // the dump again once, when it has.
    feed = NotificationsFeed.of(manager, _main()?.filterClient)
      ..addListener(onFeed);
  }

  @override
  void dispose() {
    feed?.removeListener(onFeed);
    super.dispose();
  }

  void onFeed() {
    if (!cardLoaded && feed?.loading == false && mounted) setState(collect);
  }

  void collect() {
    final snapshot = collectNotificationDebug(clientManager!, main: _main());
    cardLoaded = snapshot.totals.cardLoaded;
    text = snapshot.text();
    copied = false;
  }

  // Settings is its own route, so the main page isn't an ancestor.
  static MainPageState? _main() {
    MainPageState? found;
    void visit(Element e) {
      if (found != null) return;
      if (e is StatefulElement && e.state is MainPageState) {
        found = e.state as MainPageState;
        return;
      }
      e.visitChildren(visit);
    }

    (navigator.currentContext as Element?)?.visitChildren(visit);
    return found;
  }

  void copy() {
    Clipboard.setData(ClipboardData(text: text));
    setState(() => copied = true);
  }

  Widget dumpBox(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: scheme.outlineVariant)),
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        child: SelectableText(text,
            style: TextStyle(
                fontFamily: "Code",
                fontSize: 12,
                height: 1.4,
                color: scheme.onSurface)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lead = Text(NotificationDebugView.lead,
        style: TextStyle(color: scheme.onSurfaceVariant));
    final copyButton = FilledButton.icon(
        onPressed: text.isEmpty ? null : copy,
        icon: const Icon(Icons.copy_rounded, size: 18),
        label: Text(copied ? "Copied" : "Copy"));
    if (widget.page) {
      return Scaffold(
        backgroundColor: scheme.surface,
        appBar: AppBar(
          backgroundColor: scheme.surfaceContainer,
          title: const Text(NotificationDebugView.title),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 10,
                children: [
                  lead,
                  Expanded(child: dumpBox(context)),
                  SizedBox(width: double.infinity, child: copyButton),
                ]),
          ),
        ),
      );
    }
    final height = MediaQuery.of(context).size.height;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 12,
          children: [
            const tiamat.Text.largeTitle(NotificationDebugView.title),
            lead,
            SizedBox(
                height: (height - 260).clamp(200, 520),
                child: dumpBox(context)),
            Row(
                mainAxisAlignment: MainAxisAlignment.end,
                spacing: 8,
                children: [
                  TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text("Close")),
                  copyButton,
                ]),
          ]),
    );
  }
}
