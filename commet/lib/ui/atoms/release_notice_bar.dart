import 'package:commet/utils/links/link_utils.dart';
import 'package:commet/utils/release_notice.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Vommet: a quiet bar along the bottom of the app when a newer release is
/// out, with a Download link and a close button. It sits below the app
/// rather than over it, so it never covers the message box or call
/// controls. Closing it hides it until the next launch.
class ReleaseNoticeBar extends StatefulWidget {
  const ReleaseNoticeBar({required this.child, super.key});
  final Widget? child;

  @override
  State<ReleaseNoticeBar> createState() => _ReleaseNoticeBarState();
}

class _ReleaseNoticeBarState extends State<ReleaseNoticeBar> {
  static bool _checked = false;
  bool closed = false;

  String promptNewVersion(String version) =>
      Intl.message("A new version of Vommet is out ($version)",
          args: [version],
          name: "promptNewVersion",
          desc: "Text of the bar at the bottom of the app when a newer "
              "release is out, with the release's name");

  String get promptNewVersionShort => Intl.message("A new version is out",
      name: "promptNewVersionShort",
      desc: "Shorter text of the new-version bar, for narrow screens");

  String get promptDownloadNewVersion => Intl.message("Download",
      name: "promptDownloadNewVersion",
      desc: "Link on the new-version bar that opens the download page");

  String get promptCloseNewVersion => Intl.message("Close",
      name: "promptCloseNewVersion",
      desc: "Tooltip of the button that hides the new-version bar");

  @override
  void initState() {
    super.initState();
    if (!_checked) {
      _checked = true;
      ReleaseNotice.check();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: ReleaseNotice.newer,
      builder: (context, version, _) {
        final child = widget.child ?? const SizedBox();
        if (version == null || closed) return child;
        return Column(
          children: [
            // The bar takes the bottom inset (phone navigation bar).
            Expanded(
              child: MediaQuery.removePadding(
                  context: context, removeBottom: true, child: child),
            ),
            buildBar(context, version),
          ],
        );
      },
    );
  }

  Widget buildBar(BuildContext context, String version) {
    final colors = ColorScheme.of(context);
    final narrow = MediaQuery.sizeOf(context).width < 500;
    return Material(
      color: colors.surfaceContainerHigh,
      child: Container(
        decoration: BoxDecoration(
            border: Border(top: BorderSide(color: colors.outlineVariant))),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 4, 2),
            child: Row(
              children: [
                Icon(Icons.system_update_alt,
                    size: 18, color: colors.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    narrow ? promptNewVersionShort : promptNewVersion(version),
                    style: TextStyle(color: colors.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  // Our own page: no "open this link?" prompt (the bar sits
                  // above the navigator, so it couldn't show one anyway).
                  onPressed: () => LinkUtils.open(ReleaseNotice.downloadUrl,
                      bypassConfirmation: true),
                  child: Text(promptDownloadNewVersion),
                ),
                IconButton(
                  tooltip: promptCloseNewVersion,
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close, color: colors.onSurfaceVariant),
                  onPressed: () => setState(() => closed = true),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
