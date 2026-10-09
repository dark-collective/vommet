import 'dart:async';

import 'package:commet/config/build_config.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/pages/setup/setup_menu.dart';
import 'package:commet/utils/first_time_setup.dart';
import 'package:commet/utils/whats_new.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: after an update, lists what changed in every build since the one
/// the user last opened (testers often skip several builds). Shown with the
/// other post-login setup pages; never on a fresh install.
class WhatsNewSetup implements SetupMenu {
  final List<ChangelogEntry> entries;

  WhatsNewSetup(this.entries);

  static String get title => intl.Intl.message("What's new in Vommet",
      name: "whatsNewTitle",
      desc: "Title of the list of changes shown after an update");

  /// Registers the page when this start is an update with something to show.
  static Future<void> registerIfUpdated() async {
    final build = BuildConfig.BUILD_DATE;
    // Local/dev builds have no build date.
    if (build.millisecondsSinceEpoch == 0) return;

    final seenMs = int.tryParse(preferences.whatsNewSeenBuild.value ?? "");
    final firstStart = preferences.lastOpenedVersion.value == null;
    final signedIn = clientManager?.isLoggedIn() == true;

    if (firstStart || !signedIn) {
      // A fresh install: the welcome screen covers it, nothing to catch up on.
      await markSeen();
      return;
    }

    final lastSeen =
        seenMs == null ? null : DateTime.fromMillisecondsSinceEpoch(seenMs);
    if (lastSeen != null && !build.isAfter(lastSeen)) return;

    final entries = WhatsNew.since(await WhatsNew.load(), lastSeen, build);
    if (entries.isEmpty) {
      await markSeen();
      return;
    }
    FirstTimeSetup.registerPostLoginSetup(WhatsNewSetup(entries));
  }

  static Future<void> markSeen() => preferences.whatsNewSeenBuild
      .set(BuildConfig.BUILD_DATE.millisecondsSinceEpoch.toString());

  /// The full changelog, from Settings › About.
  static Future<void> showAll(BuildContext context) async {
    final all = await WhatsNew.load();
    if (!context.mounted) return;
    await AdaptiveDialog.show(context,
        title: title, builder: (_) => WhatsNewList(all));
  }

  final StreamController<SetupMenuState> controller = StreamController();

  @override
  Widget builder(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        tiamat.Text.largeTitle(title),
        const SizedBox(height: 8),
        WhatsNewList(entries),
      ],
    );
  }

  @override
  Stream<SetupMenuState> get onStateChanged => controller.stream;

  @override
  SetupMenuState state = SetupMenuState.canProgress;

  @override
  Future<void> submit() => markSeen();
}

/// Entries grouped by build date, newest first, as bullet lists.
class WhatsNewList extends StatelessWidget {
  const WhatsNewList(this.entries, {super.key});
  final List<ChangelogEntry> entries;

  String get labelNothing => intl.Intl.message("Nothing listed yet.",
      name: "whatsNewNothing", desc: "Shown when the changelog is empty");

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return tiamat.Text.labelLow(labelNothing);
    final dateFormat = intl.DateFormat.yMMMMd();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
            child: tiamat.Text.labelEmphasised(
                dateFormat.format(entry.date.toLocal())),
          ),
          for (final change in entry.changes)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 2, 0, 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const tiamat.Text.label("•  "),
                  Expanded(child: tiamat.Text.label(change)),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
