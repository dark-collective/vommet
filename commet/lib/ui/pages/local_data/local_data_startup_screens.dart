// Vommet: the start-up screens of local data encryption
// (LOCAL-DATA-ENCRYPTION.md, phase 6): the keyring is locked, the key is
// missing or can't be reached, or an account's stored messages don't open.
// They show before the app's translations and theme are loaded (the key is
// needed before anything opens), so they are a small app of their own.
import 'dart:async';
import 'dart:io';

import 'package:commet/security/local_data_keys.dart';
import 'package:commet/security/local_data_strings.dart';
import 'package:commet/telemetry/local_data_telemetry.dart';
import 'package:commet/telemetry/telemetry.dart';
import 'package:commet/utils/text_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shows the start-up screens until the encrypted data can be opened (or
/// the user quits). Set by appMain; tests leave it unset.
class LocalDataStartupUi {
  LocalDataStartupUi({required this.show, this.onShown, this.onHidden});

  /// Puts a widget on screen (runApp).
  final void Function(Widget) show;

  /// Called when a screen comes up / is done (the slow-start watchdog).
  final void Function()? onShown;
  final void Function()? onHidden;

  /// How long the locked screen waits before saying the keyring is still
  /// locked.
  static Duration lockedWait = const Duration(minutes: 2);

  /// Returns once the key is there (or not needed).
  Future<void> resolveKeyProblems() async {
    final problem = await LocalDataKeys.startupProblem();
    if (problem == null) return;
    onShown?.call();
    final done = Completer<void>();
    show(_StartupApp(
        child: _KeyProblemFlow(initial: problem, onDone: done.complete)));
    await done.future;
    onHidden?.call();
  }

  /// Returns once every account's stored messages open, or were left out
  /// for this run, or reset.
  Future<void> resolveDamagedData() async {
    var damaged = await LocalDataKeys.checkDatabases();
    if (damaged.isEmpty) return;
    onShown?.call();
    while (damaged.isNotEmpty) {
      final account = damaged.first;
      final done = Completer<void>();
      show(_StartupApp(
          child: _DamagedScreen(account: account, onDone: done.complete)));
      await done.future;
      damaged = (await LocalDataKeys.checkDatabases())
          .where((a) => !LocalDataKeys.skippedAccounts.contains(a.account))
          .toList();
    }
    onHidden?.call();
  }
}

Future<Never> _quit() async {
  try {
    await Telemetry.flush();
  } catch (_) {}
  exit(0);
}

class _StartupApp extends StatelessWidget {
  const _StartupApp({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF6B4FD8), brightness: Brightness.dark),
      ),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Title, body paragraphs, then whatever follows.
class _ScreenText extends StatelessWidget {
  const _ScreenText({required this.icon, required this.title, this.children});
  final IconData icon;
  final String title;
  final List<Widget>? children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 36, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text(title, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 12),
        ...?children,
      ],
    );
  }
}

Widget _paragraph(BuildContext context, String text, {bool bold = false}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: bold ? FontWeight.w700 : null, height: 1.4)),
    );

/// Buttons in a row, stacked on phones.
class _Buttons extends StatelessWidget {
  const _Buttons(this.buttons);
  final List<Widget> buttons;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 480;
    if (narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: buttons,
      );
    }
    return Wrap(spacing: 8, runSpacing: 8, children: buttons);
  }
}

/// The Details box: lines, then Copy details.
class _DetailsBox extends StatelessWidget {
  const _DetailsBox(this.lines);
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: SelectableText(line,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontFamily: "monospace")),
            ),
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: () =>
                Clipboard.setData(ClipboardData(text: lines.join("\n"))),
            icon: const Icon(Icons.copy, size: 16),
            label: Text(localDataCopyDetails),
          ),
        ],
      ),
    );
  }
}

String localDataPlaceName(LocalDataKeyPlace place) => switch (place) {
      LocalDataKeyPlace.keyring => localDataPlaceKeyring,
      LocalDataKeyPlace.portal => localDataPlaceKeyring,
      LocalDataKeyPlace.windows => localDataPlaceWindows,
      LocalDataKeyPlace.android => localDataPlaceAndroid,
      LocalDataKeyPlace.ios => localDataPlaceDevice,
      LocalDataKeyPlace.mac => localDataPlaceMac,
      LocalDataKeyPlace.file => localDataPlaceFile,
    };

/// The locked → still locked / missing / unreachable screens, until the
/// key is there.
class _KeyProblemFlow extends StatefulWidget {
  const _KeyProblemFlow({required this.initial, required this.onDone});
  final LocalDataStartupProblem initial;
  final VoidCallback onDone;

  @override
  State<_KeyProblemFlow> createState() => _KeyProblemFlowState();
}

class _KeyProblemFlowState extends State<_KeyProblemFlow> {
  late LocalDataStartupProblem _problem = widget.initial;
  final Stopwatch _clock = Stopwatch()..start();

  /// The locked screen gave up waiting (Try again · Quit).
  bool _stillLocked = false;
  bool _working = false;
  bool _details = false;
  bool _finished = false;
  Timer? _lockedTimer;

  /// The screen the user was shown first (for telemetry).
  late final String _firstScreen = widget.initial.screen.name;

  @override
  void initState() {
    super.initState();
    if (_problem.screen == LocalDataStartupScreen.locked) _waitForUnlock();
  }

  @override
  void dispose() {
    _lockedTimer?.cancel();
    super.dispose();
  }

  String get _screenName =>
      _stillLocked ? LocalDataStartupScreen.locked.name : _problem.screen.name;

  void _finish(String result, {bool? keptCopy}) {
    if (_finished) return;
    _finished = true;
    _lockedTimer?.cancel();
    LocalDataTelemetry.unlock(
        screen: result == "unlocked" ? _firstScreen : _screenName,
        result: result,
        wait: _clock.elapsed,
        keptCopy: keptCopy);
    widget.onDone();
  }

  /// The locked screen: the system's unlock prompt is up; it goes on by
  /// itself once unlocked, or says it's still locked after two minutes.
  Future<void> _waitForUnlock() async {
    _lockedTimer?.cancel();
    _lockedTimer = Timer(LocalDataStartupUi.lockedWait, () {
      if (!mounted || _finished) return;
      LocalDataTelemetry.unlock(
          screen: LocalDataStartupScreen.locked.name,
          result: "still_locked",
          wait: _clock.elapsed);
      setState(() => _stillLocked = true);
    });
    final problem = await LocalDataKeys.retryUnlock();
    if (!mounted || _finished) return;
    if (problem == null) return _finish("unlocked");
    _lockedTimer?.cancel();
    setState(() {
      _problem = problem;
      // The prompt was closed without unlocking.
      _stillLocked = problem.screen == LocalDataStartupScreen.locked;
    });
  }

  Future<void> _tryAgain() async {
    setState(() => _working = true);
    final problem = await LocalDataKeys.retryUnlock();
    if (!mounted || _finished) return;
    if (problem == null) return _finish("recovered");
    setState(() {
      _working = false;
      _problem = problem;
      _stillLocked = problem.screen == LocalDataStartupScreen.locked;
    });
  }

  Future<void> _quitPressed() async {
    _finish("quit");
    await _quit();
  }

  Future<void> _startOver() async {
    final keepCopy = await showDialog<bool>(
        context: context,
        builder: (_) => RemoveLocalDataDialog(
            title: localDataStartOverTitle,
            body: localDataStartOverBody,
            confirm: localDataStartOver));
    if (keepCopy == null || !mounted) return;
    setState(() => _working = true);
    await LocalDataKeys.startOver(keepCopy: keepCopy);
    _finish("start_over", keptCopy: keepCopy);
  }

  @override
  Widget build(BuildContext context) {
    if (_problem.screen == LocalDataStartupScreen.locked && !_stillLocked) {
      return _locked(context);
    }
    if (_stillLocked) return _stillLockedScreen(context);
    return _keyMissing(context);
  }

  Widget _locked(BuildContext context) {
    return _ScreenText(
      icon: Icons.lock_outline,
      title: localDataLockedTitle,
      children: [
        _paragraph(context, localDataLockedBody),
        const SizedBox(height: 8),
        Row(children: [
          const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 12),
          Flexible(child: Text(localDataLockedWaiting)),
        ]),
        const SizedBox(height: 16),
        _paragraph(context, localDataLockedTip),
        const SizedBox(height: 8),
        _Buttons([
          OutlinedButton(onPressed: _quitPressed, child: Text(localDataQuit)),
        ]),
      ],
    );
  }

  Widget _stillLockedScreen(BuildContext context) {
    return _ScreenText(
      icon: Icons.lock_outline,
      title: localDataStillLockedTitle,
      children: [
        _paragraph(context, localDataStillLockedBody),
        const SizedBox(height: 8),
        _Buttons([
          FilledButton(
              onPressed: _working ? null : _tryAgain,
              child: Text(localDataTryAgain)),
          OutlinedButton(onPressed: _quitPressed, child: Text(localDataQuit)),
        ]),
      ],
    );
  }

  Widget _keyMissing(BuildContext context) {
    final unreachable = _problem.screen == LocalDataStartupScreen.unreachable;
    final body = unreachable
        ? localDataUnreachableBody
        : switch (_problem.cause) {
            LocalDataMissingCause.fileGone => localDataMissingFileBody,
            LocalDataMissingCause.recordGone => localDataMissingRecordBody,
            _ => localDataMissingKeyringBody,
          };
    final what = unreachable
        ? localDataWhatUnreachable
        : switch (_problem.cause) {
            LocalDataMissingCause.fileGone => localDataWhatFileGone,
            LocalDataMissingCause.recordGone => localDataWhatRecordGone,
            _ => localDataWhatNoKey,
          };
    final place = _problem.place;
    final critical = Theme.of(context).colorScheme.error;
    return _ScreenText(
      icon: unreachable ? Icons.key_off_outlined : Icons.key_off,
      title: unreachable ? localDataUnreachableTitle : localDataMissingTitle,
      children: [
        _paragraph(context, body),
        _paragraph(context, localDataNothingDeleted, bold: true),
        if (!unreachable) _paragraph(context, localDataNeverNewKey),
        const SizedBox(height: 8),
        _Buttons([
          FilledButton(
              onPressed: _working ? null : _tryAgain,
              child: Text(localDataTryAgain)),
          OutlinedButton(
              onPressed: () => setState(() => _details = !_details),
              child: Text(_details ? localDataHideDetails : localDataDetails)),
          // Unreachable: the key may still be there (a broken keyring), so
          // removing the data isn't offered.
          if (!unreachable)
            OutlinedButton(
                style: OutlinedButton.styleFrom(
                    foregroundColor: critical,
                    side: BorderSide(color: critical.withAlpha(128))),
                onPressed: _working ? null : _startOver,
                child: Text(localDataStartOverButton)),
        ]),
        if (_details)
          _DetailsBox([
            if (place != null) localDataDetailWhere(localDataPlaceName(place)),
            localDataDetailWhat(what),
            localDataDetailFolder(_problem.dataFolder),
          ]),
      ],
    );
  }
}

/// Start over / Reset? Returns whether to keep a copy (on by default), or
/// null (Cancel).
class RemoveLocalDataDialog extends StatefulWidget {
  const RemoveLocalDataDialog(
      {super.key,
      required this.title,
      required this.body,
      required this.confirm});
  final String title;
  final String body;
  final String confirm;

  @override
  State<RemoveLocalDataDialog> createState() => _RemoveLocalDataDialogState();
}

class _RemoveLocalDataDialogState extends State<RemoveLocalDataDialog> {
  bool _keepCopy = true;

  @override
  Widget build(BuildContext context) {
    final critical = Theme.of(context).colorScheme.error;
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _paragraph(context, widget.body),
            _paragraph(context, localDataRecoveryKeyLine),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _keepCopy,
              onChanged: (v) => setState(() => _keepCopy = v ?? true),
              title: Text(localDataKeepCopy),
              subtitle: Text(
                  localDataKeepCopyDescription(LocalDataKeys.oldFolderName())),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(localDataCancel)),
        FilledButton(
            style: FilledButton.styleFrom(backgroundColor: critical),
            onPressed: () => Navigator.of(context).pop(_keepCopy),
            child: Text(widget.confirm)),
      ],
    );
  }
}

/// One account's stored messages don't open with their key.
class _DamagedScreen extends StatefulWidget {
  const _DamagedScreen({required this.account, required this.onDone});
  final LocalDataDamagedAccount account;
  final VoidCallback onDone;

  @override
  State<_DamagedScreen> createState() => _DamagedScreenState();
}

class _DamagedScreenState extends State<_DamagedScreen> {
  final Stopwatch _clock = Stopwatch()..start();
  bool _details = false;
  bool _working = false;
  bool _finished = false;

  LocalDataDamagedAccount get _account => widget.account;

  String get _name =>
      _account.displayName ?? _account.userId ?? localDataThisAccount;

  void _finish(String? result, {bool? keptCopy}) {
    if (_finished) return;
    _finished = true;
    if (result != null) {
      LocalDataTelemetry.unlock(
          screen: "damaged",
          result: result,
          wait: _clock.elapsed,
          keptCopy: keptCopy);
    }
    widget.onDone();
  }

  Future<void> _tryAgain() async {
    setState(() => _working = true);
    final left = await LocalDataKeys.checkDatabases(only: _account.account);
    if (!mounted) return;
    if (left.isEmpty) return _finish("recovered");
    setState(() => _working = false);
  }

  void _continueWithout() {
    LocalDataKeys.skippedAccounts.add(_account.account);
    _finish("continued_without");
  }

  Future<void> _reset() async {
    final keepCopy = await showDialog<bool>(
        context: context,
        builder: (_) => RemoveLocalDataDialog(
            title: localDataResetTitle(_name),
            body: localDataResetBody(_name),
            confirm: localDataResetConfirm));
    if (keepCopy == null || !mounted) return;
    setState(() => _working = true);
    await LocalDataKeys.resetAccount(_account.account, keepCopy: keepCopy);
    _finish("reset_account", keptCopy: keepCopy);
  }

  @override
  Widget build(BuildContext context) {
    final critical = Theme.of(context).colorScheme.error;
    final size = _account.size;
    // Continue without needs another account to continue with.
    final others = LocalDataKeys.registeredAccounts
        .where((a) =>
            a != _account.account && !LocalDataKeys.skippedAccounts.contains(a))
        .isNotEmpty;
    return _ScreenText(
      icon: Icons.report_problem_outlined,
      title: localDataDamagedTitle,
      children: [
        _paragraph(context, localDataDamagedBody(_name)),
        _paragraph(context, localDataDamagedSafe),
        const SizedBox(height: 8),
        _Buttons([
          FilledButton(
              onPressed: _working ? null : _tryAgain,
              child: Text(localDataTryAgain)),
          if (others)
            OutlinedButton(
                onPressed: _working ? null : _continueWithout,
                child: Text(localDataContinueWithout(_name))),
          OutlinedButton(
              onPressed: () => setState(() => _details = !_details),
              child: Text(_details ? localDataHideDetails : localDataDetails)),
          // Only a file that is really damaged (or has no key) can be
          // reset; one that failed for another reason (busy, out of
          // memory) is only tried again.
          if (_account.corrupt || _account.noKey)
            OutlinedButton(
                style: OutlinedButton.styleFrom(
                    foregroundColor: critical,
                    side: BorderSide(color: critical.withAlpha(128))),
                onPressed: _working ? null : _reset,
                child: Text(localDataResetAccountButton(_name))),
        ]),
        if (_details)
          _DetailsBox([
            localDataDetailAccount(_account.userId ?? _account.account),
            localDataDetailFile(_account.filePath,
                size == null ? "?" : TextUtils.readableFileSize(size)),
            localDataDetailWhat(
                _account.noKey ? localDataWhatNoFileKey : localDataWhatDamaged),
          ]),
      ],
    );
  }
}
