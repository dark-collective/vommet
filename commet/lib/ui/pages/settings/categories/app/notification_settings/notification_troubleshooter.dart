import 'package:commet/client/client.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/navigation/navigation_utils.dart';
import 'package:commet/ui/pages/settings/categories/app/settings_category_app.dart';
import 'package:commet/ui/pages/settings/settings_navigation.dart';
import 'package:commet/utils/current_account.dart';
import 'package:commet/utils/notification_diagnostics/diagnostic_check.dart';
import 'package:commet/utils/notification_diagnostics/notification_diagnostic_reader.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class NotificationTroubleshooterEntry extends StatelessWidget {
  const NotificationTroubleshooterEntry({super.key});
  @override
  Widget build(BuildContext context) => ListTile(
      leading: const Icon(Icons.fact_check_outlined),
      title: Text(S.title),
      subtitle: Text(S.entry),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => NavigationUtils.navigateTo(
          context, const NotificationTroubleshooterPage()));
}

class NotificationTroubleshooterPage extends StatefulWidget {
  const NotificationTroubleshooterPage({super.key});
  static String get title => S.title;
  @override
  State<NotificationTroubleshooterPage> createState() => _PageState();
}

class _PageState extends State<NotificationTroubleshooterPage> {
  late final accounts = List<Client>.of(clientManager?.clients ?? []);
  late Client? selected =
      currentAccount(accounts, preferences.filterClient.value);
  @override
  Widget build(BuildContext context) => NotificationDiagnosticView(
      key: ObjectKey(selected),
      createReader: () => AppNotificationDiagnosticReader.forClient(selected),
      accountSelector: accounts.length < 2
          ? null
          : DiagnosticAccountPicker<Client>(accounts: {
              for (final c in accounts)
                c: (c.self?.displayName ?? c.identifier, c.self?.detail)
            }, value: selected, onChanged: (c) => setState(() => selected = c)),
      onAction: (a) async {
        if (a == DiagnosticAction.androidSettings) return openAppSettings();
        SettingsNavigation.open(context,
            tab: SettingsCategoryApp().labelSettingsAppNotifications,
            category: SettingsNavigation.appCategory);
        return true;
      });
}

/// Intrinsic row heights and one-line identity fields support large text and
/// long IDs without changing the application's other account-selection flows.
class DiagnosticAccountPicker<T> extends StatelessWidget {
  const DiagnosticAccountPicker(
      {required this.accounts,
      required this.value,
      required this.onChanged,
      super.key});
  final Map<T, (String, String?)> accounts;
  final T? value;
  final ValueChanged<T?> onChanged;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(S.account),
        DropdownButton<T>(
            isExpanded: true,
            itemHeight: null,
            value: value,
            onChanged: onChanged,
            items: [
              for (final e in accounts.entries)
                DropdownMenuItem(
                    value: e.key,
                    child: Tooltip(
                        message: e.value.$2 ?? e.value.$1,
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(e.value.$1,
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              if (e.value.$2 != null)
                                Text(e.value.$2!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        Theme.of(context).textTheme.labelSmall),
                            ])))
            ])
      ]);
}

class NotificationDiagnosticView extends StatefulWidget {
  const NotificationDiagnosticView(
      {required this.createReader,
      required this.onAction,
      this.accountSelector,
      this.timeout = const Duration(seconds: 15),
      super.key});
  final NotificationDiagnosticReader Function() createReader;
  final Future<bool> Function(DiagnosticAction) onAction;
  final Widget? accountSelector;
  final Duration timeout;
  @override
  State<NotificationDiagnosticView> createState() => _ViewState();
}

class _ViewState extends State<NotificationDiagnosticView>
    with WidgetsBindingObserver {
  late final controller = NotificationDiagnosticController(widget.createReader,
      timeout: widget.timeout);
  bool actionRunning = false;
  @override
  void initState() {
    super.initState();
    controller.run();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) controller.invalidate();
  }

  Future<void> action(DiagnosticAction a) async {
    if (actionRunning) return;
    controller.invalidate();
    setState(() => actionRunning = true);
    var opened = false;
    try {
      opened = await widget.onAction(a);
    } catch (_) {/* Never display raw OS errors. */}
    if (!mounted) return;
    setState(() => actionRunning = false);
    if (!opened)
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(S.openFailed)));
  }

  Widget panel(String title, Iterable<DiagnosticResult> rows) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: tiamat.Panel(
          header: title,
          mode: tiamat.TileType.surfaceContainerLow,
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: rows.map(row).toList())));
  Widget row(DiagnosticResult r) {
    final icon = switch (r.status) {
      DiagnosticStatus.passed => Icons.check_circle_outline,
      DiagnosticStatus.failed => Icons.error_outline,
      DiagnosticStatus.attention => Icons.warning_amber_rounded,
      DiagnosticStatus.checking => Icons.hourglass_top,
      _ => Icons.help_outline
    };
    return ListTile(
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        leading: ExcludeSemantics(child: Icon(icon)),
        title: tiamat.Text.labelEmphasised(r.title),
        subtitle:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(S.result(r.status.label, r.detail)),
          if (r.action != null)
            OutlinedButton(
                onPressed: actionRunning ? null : () => action(r.action!),
                child: Text(r.action == DiagnosticAction.androidSettings
                    ? S.androidSettings
                    : S.providerSettings))
        ]));
  }

  List<Widget> content() => [
        tiamat.Text.largeTitle(S.title),
        const SizedBox(height: 12),
        Text(S.lead),
        const SizedBox(height: 16),
        if (widget.accountSelector != null) widget.accountSelector!,
        if (controller.notice != null)
          Semantics(liveRegion: true, child: Text(controller.notice!)),
        panel(S.configuration, controller.results.expand((r) => r)),
        panel(S.delivery, [
          DiagnosticResult(S.local, DiagnosticStatus.notChecked, S.localLimit),
          DiagnosticResult(
              S.remote, DiagnosticStatus.unavailable, S.remoteLimit)
        ]),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton(
              onPressed: actionRunning
                  ? null
                  : controller.running
                      ? controller.cancel
                      : controller.run,
              child: Text(controller.running ? S.cancel : S.again)),
          OutlinedButton(
              onPressed: actionRunning
                  ? null
                  : () => action(DiagnosticAction.notificationSettings),
              child: Text(S.settings))
        ]),
        const SizedBox(height: 12),
        Text(S.limits)
      ];

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(S.notifications)),
      body: SafeArea(
          child: AnimatedBuilder(
              animation: controller,
              builder: (context, _) => SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                      child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 720),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: content())))))));
}
