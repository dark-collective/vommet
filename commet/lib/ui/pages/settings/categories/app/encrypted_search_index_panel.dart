// Vommet (issues 602, 611): Settings › Privacy › Search: "Index encrypted
// chats" Off / Wi-Fi only / Always, the progress over every account, and
// Clear index.
import 'dart:async';

import 'package:commet/client/matrix/components/encrypted_search_index/matrix_encrypted_search_index_component.dart';
import 'package:commet/config/encrypted_search_index_setting.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/pages/settings/search/settings_search.dart';
import 'package:commet/utils/text_utils.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class EncryptedSearchIndexPanel extends StatefulWidget {
  const EncryptedSearchIndexPanel({super.key});

  @override
  State<EncryptedSearchIndexPanel> createState() =>
      _EncryptedSearchIndexPanelState();
}

class _EncryptedSearchIndexPanelState extends State<EncryptedSearchIndexPanel> {
  late final List<MatrixEncryptedSearchIndexComponent> _indexes = [
    for (final client in clientManager?.clients ?? const [])
      if (client.getComponent<MatrixEncryptedSearchIndexComponent>()
          case final index?)
        index
  ];
  StreamSubscription? _modeSub;
  bool _clearing = false;
  int? _sizeBytes;
  DateTime? _sizeReadAt;

  @override
  void initState() {
    super.initState();
    for (final index in _indexes) {
      index.progress.addListener(_changed);
    }
    _modeSub = encryptedIndexModePreference.onChanged.listen((_) => _changed());
    _readSize(force: true);
  }

  @override
  void dispose() {
    for (final index in _indexes) {
      index.progress.removeListener(_changed);
    }
    _modeSub?.cancel();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
    _readSize();
  }

  /// Vommet Deep Search: the index's size on disk, re-read at most every
  /// 10 seconds while the panel is open.
  Future<void> _readSize({bool force = false}) async {
    final now = DateTime.now();
    if (!force &&
        _sizeReadAt != null &&
        now.difference(_sizeReadAt!) < const Duration(seconds: 10)) {
      return;
    }
    _sizeReadAt = now;
    var size = 0;
    for (final index in _indexes) {
      size += await index.indexSizeBytes();
    }
    if (mounted) setState(() => _sizeBytes = size);
  }

  EncryptedIndexProgress get _progress {
    var indexed = 0;
    var total = 0;
    final states = <EncryptedIndexState>{};
    for (final index in _indexes) {
      final p = index.progress.value;
      indexed += p.indexed;
      total += p.total;
      states.add(p.state);
    }
    final state = _indexes.isEmpty || _indexes.every((i) => !i.available)
        ? EncryptedIndexState.unavailable
        : states.contains(EncryptedIndexState.running)
            ? EncryptedIndexState.running
            : states.contains(EncryptedIndexState.pausedForBattery)
                ? EncryptedIndexState.pausedForBattery
                : states.contains(EncryptedIndexState.waitingForWifi)
                    ? EncryptedIndexState.waitingForWifi
                    : states.contains(EncryptedIndexState.off)
                        ? EncryptedIndexState.off
                        : states.contains(EncryptedIndexState.unavailable) &&
                                !states.contains(EncryptedIndexState.done)
                            ? EncryptedIndexState.unavailable
                            : EncryptedIndexState.done;
    return EncryptedIndexProgress(indexed: indexed, total: total, state: state);
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    final unavailable = progress.state == EncryptedIndexState.unavailable;
    return SettingsSearchTarget(
      ids: [encryptedIndexModePreference.key],
      child: tiamat.Panel(
        header: searchSettingsHeader,
        mode: tiamat.TileType.surfaceContainerLow,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            tiamat.Text.label(indexEncryptedChatsTitle),
            const SizedBox(height: 4),
            tiamat.Text.labelLow(indexEncryptedChatsDescription),
            const SizedBox(height: 10),
            SegmentedButton<EncryptedIndexMode>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                    value: EncryptedIndexMode.off, label: Text(indexModeOff)),
                ButtonSegment(
                    value: EncryptedIndexMode.wifiOnly,
                    label: Text(indexModeWifiOnly)),
                ButtonSegment(
                    value: EncryptedIndexMode.always,
                    label: Text(indexModeAlways)),
              ],
              selected: {encryptedIndexMode},
              onSelectionChanged: unavailable
                  ? null
                  : (s) => encryptedIndexModePreference.set(s.first.key),
            ),
            if (!unavailable) ...[
              const SizedBox(height: 14),
              tiamat.Text.labelLow(
                  indexProgress(progress.indexed, progress.total)),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                    value: progress.fraction, minHeight: 6),
              ),
            ],
            const SizedBox(height: 6),
            tiamat.Text.labelLow(switch (progress.state) {
              EncryptedIndexState.unavailable => indexStateUnavailable,
              EncryptedIndexState.off => indexStateOff,
              EncryptedIndexState.waitingForWifi => indexStateWaitingForWifi,
              EncryptedIndexState.pausedForBattery =>
                indexStatePausedForBattery,
              EncryptedIndexState.running => indexStateRunning,
              EncryptedIndexState.done => indexStateDone,
            }),
            if (!unavailable && _sizeBytes != null) ...[
              const SizedBox(height: 6),
              tiamat.Text.labelLow(
                  indexSize(TextUtils.readableFileSize(_sizeBytes!))),
            ],
            if (!unavailable) ...[
              const SizedBox(height: 10),
              tiamat.Button.danger(
                text: indexClear,
                isLoading: _clearing,
                onTap: _clear,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _clear() async {
    final ok = await AdaptiveDialog.confirmation(context,
        title: indexClear,
        prompt: indexClearPrompt,
        confirmationText: indexClear,
        dangerous: true);
    if (ok != true) return;
    setState(() => _clearing = true);
    for (final index in _indexes) {
      await index.clear();
    }
    _readSize(force: true);
    if (!mounted) return;
    setState(() => _clearing = false);
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(indexCleared)));
  }
}
