import 'dart:convert';

import 'package:commet/config/build_config.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/utils/download_utils.dart';
import 'package:commet/utils/text_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

// Vommet: export the log page's entries (what the search and level filter
// currently show) as plain text — copied to the clipboard or saved as a file,
// so a whole stretch of logs can be shared instead of screenshots.
//
// Uses the same redacted content the page shows; colour codes are stripped.
final _ansi = RegExp(r'\x1b\[[0-9;]*m');

String vommetLogText(List<LogEntry> entries, {String? filter, DateTime? now}) {
  final at = (now ?? DateTime.now()).toLocal();
  final offset = at.timeZoneOffset;
  final sign = offset.isNegative ? "-" : "+";
  final hh = offset.inHours.abs().toString().padLeft(2, "0");
  final mm = (offset.inMinutes.abs() % 60).toString().padLeft(2, "0");
  final stamp = DateFormat("yyyy-MM-dd HH:mm:ss.SSS");
  final out = StringBuffer()
    ..writeln("Vommet log export")
    ..writeln("Version: ${BuildConfig.VERSION_TAG} (${BuildConfig.GIT_HASH})")
    ..writeln("Platform: ${BuildConfig.PLATFORM} ${BuildConfig.BUILD_DETAIL}")
    ..writeln("Exported: ${stamp.format(at)} (UTC$sign$hh:$mm)")
    ..writeln("Entries: ${entries.length}"
        "${filter != null && filter.isNotEmpty ? " (filter: $filter)" : ""}")
    ..writeln();
  for (final e in entries) {
    final count = e.count > 1 ? " x${e.count}" : "";
    final text = e.content.replaceAll(_ansi, "").trim();
    out.writeln(
        "${stamp.format(e.time.toLocal())} [${e.type.name}$count] $text");
    if (e is LogEntryException && e.trace != null) {
      final trace =
          TextUtils.redactSensitiveInfo(e.trace.toString()).trimRight();
      for (final line in const LineSplitter().convert(trace)) {
        out.writeln("    $line");
      }
    }
  }
  return out.toString();
}

String vommetLogFileName(DateTime now) =>
    "vommet-log-${DateFormat("yyyyMMdd-HHmmss").format(now.toLocal())}.txt";

/// Copy and Save buttons for the log page's filter bar. [entries] returns the
/// entries currently shown, oldest first; [filter] describes the active filter.
List<Widget> vommetLogExportButtons(BuildContext context,
    List<LogEntry> Function() entries, String Function() filter) {
  // Looked up before any await (the context may be gone afterwards).
  final messenger = ScaffoldMessenger.maybeOf(context);
  void notify(String message) =>
      messenger?.showSnackBar(SnackBar(content: Text(message)));

  return [
    IconButton(
      visualDensity: VisualDensity.compact,
      icon: const Icon(Icons.copy, size: 18),
      tooltip: "Copy shown logs",
      onPressed: () async {
        final list = entries();
        await Clipboard.setData(
            ClipboardData(text: vommetLogText(list, filter: filter())));
        notify("Copied ${list.length} log entries");
      },
    ),
    IconButton(
      visualDensity: VisualDensity.compact,
      icon: const Icon(Icons.save_alt, size: 18),
      tooltip: "Save shown logs as a text file",
      onPressed: () async {
        final list = entries();
        final now = DateTime.now();
        final bytes = Uint8List.fromList(
            utf8.encode(vommetLogText(list, filter: filter(), now: now)));
        try {
          if (await DownloadUtils.saveBytes(bytes, vommetLogFileName(now))) {
            notify("Saved ${list.length} log entries");
          }
        } catch (e, t) {
          Log.onError(e, t, content: "Saving the log export failed");
          notify("Could not save the logs");
        }
      },
    ),
  ];
}
