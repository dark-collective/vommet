import 'package:commet/main.dart';
import 'package:commet/utils/links/link_utils.dart';
import 'package:commet/utils/page_reload.dart';
import 'package:commet/utils/release_notice.dart';
import 'package:commet/utils/release_update.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Vommet: a quiet bar along the bottom of the app when a newer release is
/// out, with a close button. It sits below the app rather than over it, so
/// it never covers the message box or call controls. Closing it hides it
/// until the next launch, or until Settings › About's "Check for updates"
/// finds the release again (Vommet issue 670). Since Vommet issue 593 its button gets this
/// install's file, checks it and hands it to the system (ReleaseUpdate);
/// package-manager installs get their update command instead.
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

  String get promptUpdateNewVersion => Intl.message("Update",
      name: "promptUpdateNewVersion",
      desc: "Button on the new-version bar that downloads this install's "
          "file for the new release");

  String promptDownloadingNewVersion(String version, String progress) =>
      Intl.message("Downloading $version · $progress",
          args: [version, progress],
          name: "promptDownloadingNewVersion",
          desc: "New-version bar while the new release downloads, with the "
              "release's name and how much has arrived (e.g. 64 of 198 MB)");

  String progressMegabytes(String received, String total) =>
      Intl.message("$received of $total MB",
          args: [received, total],
          name: "progressMegabytes",
          desc: "How much of a download has arrived, in megabytes");

  String get promptCancelUpdate => Intl.message("Cancel",
      name: "promptCancelUpdate",
      desc: "Button on the new-version bar that stops the download");

  String promptUpdateReady(String version) =>
      Intl.message("$version is downloaded and verified",
          args: [version],
          name: "promptUpdateReady",
          desc: "New-version bar once the new release's file has downloaded "
              "and matched the release's signed checksums");

  String promptUpdateReadyCommand(String version) =>
      Intl.message("$version is downloaded and verified · install it with",
          args: [version],
          name: "promptUpdateReadyCommand",
          desc: "New-version bar for a Flatpak once the update has downloaded "
              "and matched the release's signed checksums; the flatpak "
              "install command follows");

  String get promptInstallUpdate => Intl.message("Install",
      name: "promptInstallUpdate",
      desc: "Button that opens the downloaded update in the system installer");

  String get promptRestartUpdate => Intl.message("Restart now",
      name: "promptRestartUpdate",
      desc: "Button that restarts Vommet into the updated AppImage");

  String get promptRestartToUpdate => Intl.message("Restart to update",
      name: "promptRestartToUpdate",
      desc: "Button that closes Vommet on Windows, installs the downloaded "
          "update and starts Vommet again");

  String get promptShowUpdateFile => Intl.message("Show file",
      name: "promptShowUpdateFile",
      desc: "Button that shows the downloaded update in the file manager");

  String promptUpdateCommand(String version) =>
      Intl.message("$version is out · update with",
          args: [version],
          name: "promptUpdateCommand",
          desc: "New-version bar for installs a package manager owns (Nix, "
              "Guix); the update command follows");

  String get promptCopyUpdateCommand => Intl.message("Copy",
      name: "promptCopyUpdateCommand",
      desc: "Button that copies the package manager's update command, or "
          "the command that installs a downloaded Flatpak update");

  String get promptReloadNewVersion => Intl.message("Reload",
      name: "promptReloadNewVersion",
      desc: "Button on the web app's new-version bar that reloads the page");

  String get promptUpdateVerifyFailed => Intl.message(
      "The download didn't match its signature. Nothing was installed.",
      name: "promptUpdateVerifyFailed",
      desc: "New-version bar when the downloaded file failed its check");

  String get promptUpdateDownloadFailed =>
      Intl.message("The update couldn't be downloaded.",
          name: "promptUpdateDownloadFailed",
          desc: "New-version bar when the download failed");

  String get promptUpdateInstallFailed =>
      Intl.message("The update couldn't be opened.",
          name: "promptUpdateInstallFailed",
          desc: "New-version bar when the system installer couldn't be opened");

  String get promptDownloadPage => Intl.message("Download page",
      name: "promptDownloadPage",
      desc: "Button that opens the download page in the browser");

  String get promptUpdateDialogTitle => Intl.message("Update Vommet?",
      name: "promptUpdateDialogTitle",
      desc: "Title of the dialog asked before the first update download");

  String promptUpdateDialogBody(String file, String size) => Intl.message(
      "$file · $size MB. Vommet checks it against the release's signed checksums before it installs anything.",
      args: [file, size],
      name: "promptUpdateDialogBody",
      desc: "Body of the dialog asked before the first update download, with "
          "the file's name and size");

  String get promptUpdateAlwaysDownload =>
      Intl.message("Always download new releases",
          name: "promptUpdateAlwaysDownload",
          desc: "Checkbox in the update dialog: download from now on without "
              "asking");

  String get promptUpdateAlwaysDownloadHint =>
      Intl.message("You can change this in Settings › General",
          name: "promptUpdateAlwaysDownloadHint",
          desc: "Hint under the 'Always download new releases' checkbox");

  String get promptUpdateDialogDownload => Intl.message("Download",
      name: "promptUpdateDialogDownload",
      desc: "Confirm button of the update dialog");

  String get promptCloseNewVersion => Intl.message("Close",
      name: "promptCloseNewVersion",
      desc: "Accessibility label of the button that hides the new-version bar");

  @override
  void initState() {
    super.initState();
    if (!_checked) {
      _checked = true;
      ReleaseNotice.check();
    }
    ReleaseNotice.reopen.addListener(_reopen);
  }

  @override
  void dispose() {
    ReleaseNotice.reopen.removeListener(_reopen);
    super.dispose();
  }

  void _reopen() {
    if (closed && mounted) setState(() => closed = false);
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
            ValueListenableBuilder<UpdateState>(
              valueListenable: ReleaseUpdate.state,
              builder: (context, update, _) =>
                  buildBar(context, version, update),
            ),
          ],
        );
      },
    );
  }

  static String _mb(int bytes) => (bytes / (1024 * 1024)).round().toString();

  void _openPage() =>
      // Our own page: no "open this link?" prompt (the bar sits above the
      // navigator, so it couldn't show one anyway).
      LinkUtils.open(ReleaseNotice.downloadUrl, bypassConfirmation: true);

  Future<void> _update() async {
    final release = ReleaseNotice.newerRelease;
    if (release == null) return;
    if (!preferences.releaseUpdateAsked.value) {
      // The bar sits above the navigator: the dialog goes in its overlay.
      final dialogContext = navigator.currentContext;
      if (dialogContext == null) return;
      final asset = ReleaseUpdate.assetFor(ReleaseUpdate.kind,
          ReleaseUpdate.arch, release["assets"] as List<dynamic>)!;
      final always = ValueNotifier(false);
      final go = await showDialog<bool>(
        context: dialogContext,
        builder: (context) => AlertDialog(
          title: Text(promptUpdateDialogTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(promptUpdateDialogBody(
                  asset["name"] as String, _mb(asset["size"] as int? ?? 0))),
              const SizedBox(height: 12),
              ValueListenableBuilder<bool>(
                valueListenable: always,
                builder: (context, value, _) => CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: value,
                  onChanged: (v) => always.value = v ?? false,
                  title: Text(promptUpdateAlwaysDownload),
                  subtitle: Text(promptUpdateAlwaysDownloadHint),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(promptCancelUpdate)),
            FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(promptUpdateDialogDownload)),
          ],
        ),
      );
      if (go != true) return;
      await preferences.releaseUpdateAsked.set(true);
      if (always.value) await preferences.releaseAutoDownload.set(true);
    }
    await ReleaseUpdate.download(release);
  }

  Widget _command(ColorScheme colors, String command) => Padding(
        padding: const EdgeInsets.only(left: 6),
        child: SelectableText(command,
            maxLines: 1,
            style: TextStyle(fontFamily: "monospace", color: colors.onSurface)),
      );

  Widget _copy(String command) => TextButton(
      onPressed: () => Clipboard.setData(ClipboardData(text: command)),
      child: Text(promptCopyUpdateCommand));

  Widget buildBar(BuildContext context, String version, UpdateState update) {
    final colors = ColorScheme.of(context);
    final narrow = MediaQuery.sizeOf(context).width < 500;
    final action = ReleaseUpdate.action;

    String text;
    Widget? extra;
    IconData icon = Icons.system_update_alt;
    final buttons = <Widget>[];
    switch (update.phase) {
      case UpdatePhase.downloading:
        final total = update.total;
        text = promptDownloadingNewVersion(
            version,
            total == null
                ? "${_mb(update.received)} MB"
                : progressMegabytes(_mb(update.received), _mb(total)));
        buttons.add(TextButton(
            onPressed: ReleaseUpdate.cancel, child: Text(promptCancelUpdate)));
      case UpdatePhase.ready:
        text = promptUpdateReady(version);
        icon = Icons.check_circle_outline;
        final install = ReleaseUpdate.installCommand;
        if (install != null) {
          text = promptUpdateReadyCommand(version);
          extra = _command(colors, install);
          buttons.add(_copy(install));
          break;
        }
        buttons.add(TextButton(
            onPressed: ReleaseUpdate.apply,
            child: Text(switch (action) {
              UpdateAction.replace => promptRestartUpdate,
              UpdateAction.reveal => promptShowUpdateFile,
              UpdateAction.runInstaller
                  when ReleaseUpdate.kind == InstallKind.windowsInstalled =>
                promptRestartToUpdate,
              _ => promptInstallUpdate,
            })));
      case UpdatePhase.failed:
        text = switch (update.error) {
          UpdateError.verify => promptUpdateVerifyFailed,
          UpdateError.install => promptUpdateInstallFailed,
          _ => promptUpdateDownloadFailed,
        };
        icon = Icons.error_outline;
        buttons.add(
            TextButton(onPressed: _openPage, child: Text(promptDownloadPage)));
      case UpdatePhase.idle:
        text = narrow ? promptNewVersionShort : promptNewVersion(version);
        final command = ReleaseUpdate.commandFor(ReleaseUpdate.kind);
        if (action == UpdateAction.command && command != null) {
          text = promptUpdateCommand(version);
          extra = _command(colors, command);
          buttons.add(_copy(command));
        } else if (action == UpdateAction.reload) {
          buttons.add(TextButton(
              onPressed: reloadPage, child: Text(promptReloadNewVersion)));
        } else if (ReleaseUpdate.canDownload(ReleaseNotice.newerRelease)) {
          buttons.add(TextButton(
              onPressed: _update, child: Text(promptUpdateNewVersion)));
        } else {
          buttons.add(TextButton(
              onPressed: _openPage, child: Text(promptDownloadNewVersion)));
        }
    }

    return Material(
      color: colors.surfaceContainerHigh,
      child: Container(
        decoration: BoxDecoration(
            border: Border(top: BorderSide(color: colors.outlineVariant))),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 2, 4, 2),
                child: Row(
                  children: [
                    Icon(icon, size: 18, color: colors.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              text,
                              style: TextStyle(color: colors.onSurfaceVariant),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (extra != null) Flexible(child: extra),
                        ],
                      ),
                    ),
                    ...buttons,
                    // No tooltip: the bar sits above the navigator, so there
                    // is no Overlay to show one in, and hovering threw and
                    // blanked the whole app (white screen).
                    IconButton(
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.close,
                          color: colors.onSurfaceVariant,
                          semanticLabel: promptCloseNewVersion),
                      onPressed: () => setState(() => closed = true),
                    ),
                  ],
                ),
              ),
              if (update.phase == UpdatePhase.downloading)
                LinearProgressIndicator(
                    minHeight: 2,
                    value: update.total == null || update.total == 0
                        ? null
                        : update.received / update.total!),
            ],
          ),
        ),
      ),
    );
  }
}
