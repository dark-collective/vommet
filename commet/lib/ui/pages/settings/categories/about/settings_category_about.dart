import 'package:commet/config/build_config.dart';
import 'package:commet/config/subplatforms/subplatforms.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/pages/settings/categories/developer/log_page.dart';
import 'package:commet/ui/pages/guides/guide_page.dart';
import 'package:commet/ui/pages/guides/guides_settings_page.dart';
import 'package:commet/ui/pages/settings/settings_category.dart';
import 'package:commet/ui/pages/settings/settings_tab.dart';
import 'package:commet/ui/pages/setup/menus/whats_new_setup.dart';
import 'package:commet/utils/links/link_utils.dart';
import 'package:commet/utils/release_notice.dart';
import 'package:commet/utils/system_info.dart';
import 'package:commet/utils/whats_new.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';

import 'package:flutter/material.dart' as m;
import 'package:tiamat/tiamat.dart' as tiamat;

import 'package:vodozemac/vodozemac.dart' as vod;
import 'package:intl/intl.dart' as intl;

class SettingsCategoryAbout implements SettingsCategory {
  String get labelSettingsAppLogs => Intl.message("Logs",
      name: "labelSettingsAppLogs",
      desc:
          "Label for the logs settings page, usually hidden unless developer mode is turned on");

  String get labelSettingsAppInfo => Intl.message("About",
      name: "labelSettingsAppInfo",
      desc: "Label for the app info settings page");

  @override
  List<SettingsTab> get tabs => List.from([
        // Vommet: in-app guides and Getting started.
        SettingsTab(
            label: guidesHeader,
            icon: Icons.help_outline,
            pageBuilder: (context) => const GuidesSettingsPage()),
        SettingsTab(
            label: labelSettingsAppInfo,
            icon: Icons.info_outline,
            makeScrollable: false,
            pageBuilder: (context) {
              return const _AppInfo();
            }),
        if (preferences.developerMode.value)
          SettingsTab(
            label: labelSettingsAppLogs,
            icon: m.Icons.text_snippet,
            makeScrollable: false,
            pageBuilder: (context) {
              return LogPage(Log.log);
            },
          )
      ]);

  static Widget info(BuildContext context) {
    return SizedBox(
      child: Wrap(
        alignment: WrapAlignment.center,
        children: [
          const tiamat.Text.label(BuildConfig.VERSION_TAG),
          const tiamat.Text.label(" · "),
          tiamat.Text.label(BuildConfig.GIT_HASH.substring(0, 7)),
          const tiamat.Text.label(" · "),
          Text.rich(
            TextSpan(
                style: const TextStyle(decoration: TextDecoration.underline),
                text: "Source Code",
                recognizer: TapGestureRecognizer()
                  ..onTap = () => LinkUtils.open(
                      Uri.parse(BuildConfig.sourceUrl),
                      context: context)),
          ),
          const tiamat.Text.label(" · "),
          Text.rich(
            TextSpan(
                style: const TextStyle(decoration: TextDecoration.underline),
                text: "License",
                recognizer: TapGestureRecognizer()
                  ..onTap = () => LinkUtils.open(
                      Uri.parse(BuildConfig.licenseUrl),
                      context: context)),
          ),
          const tiamat.Text.label(" · "),
          // Vommet: the full changelog.
          Text.rich(
            TextSpan(
                style: const TextStyle(decoration: TextDecoration.underline),
                text: "What's New",
                recognizer: TapGestureRecognizer()
                  ..onTap = () => WhatsNewSetup.showAll(context)),
          ),
          const tiamat.Text.label(" · "),
          Text.rich(
            TextSpan(
                style: const TextStyle(decoration: TextDecoration.underline),
                text: "Open Source Licenses",
                recognizer: TapGestureRecognizer()
                  ..onTap = () {
                    showLicensePage(context: context);
                  }),
          ),
        ],
      ),
    );
  }

  @override
  String? get title => null;
}

class _AppInfo extends StatefulWidget {
  const _AppInfo();

  @override
  State<_AppInfo> createState() => _AppInfoState();
}

class _AppInfoState extends State<_AppInfo> {
  SystemInfo? systemInfo;

  /// Vommet issue 798: the changelog while "Recent updates" is open.
  Future<List<ChangelogEntry>>? recentUpdates;

  String get labelRecentUpdates => Intl.message("Recent updates",
      name: "labelRecentUpdates",
      desc: "Expandable section in Settings › About that shows the "
          "changelog, newest first");

  void toggleRecentUpdates() => setState(() {
        recentUpdates = recentUpdates == null ? WhatsNew.load() : null;
      });
  @override
  void initState() {
    super.initState();
    loadDeviceInfo();
  }

  Future<void> loadDeviceInfo() async {
    var info = await SystemInfo.load();
    if (!mounted) return;
    setState(() {
      systemInfo = info;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            SizedBox(
              width: 100,
              height: 100,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: SvgPicture.asset(
                  "assets/images/app_icon/icon.svg",
                  theme: SvgTheme(
                      currentColor: Theme.of(context).colorScheme.onSurface),
                ),
              ),
            ),
            Flexible(
              child: Row(
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const tiamat.Text.largeTitle(BuildConfig.appName),
                      const tiamat.Text.labelEmphasised(
                          BuildConfig.VERSION_TAG),
                      tiamat.Text.labelLow(
                          "${BuildConfig.GIT_HASH.substring(0, 7)} ${BuildConfig.BUILD_DETAIL}"),
                      tiamat.Text.labelLow("Built: " +
                          intl.DateFormat(intl.DateFormat.YEAR_MONTH_DAY)
                              .format(BuildConfig.BUILD_DATE)),
                      if (systemInfo != null)
                        Row(
                          spacing: 10,
                          children: [
                            if (systemInfo!.name != null)
                              tiamat.Text.labelLow(systemInfo!.name!),
                            if (systemInfo!.version != null)
                              tiamat.Text.labelLow(systemInfo!.version!),
                            if (systemInfo!.displayServer != null)
                              tiamat.Text.labelLow(systemInfo!.displayServer!),
                            if (systemInfo!.desktopEnvironment != null)
                              tiamat.Text.labelLow(
                                  systemInfo!.desktopEnvironment!)
                          ],
                        ),
                      if (Subplatforms.subplatform != null)
                        tiamat.Text.labelLow(Subplatforms.subplatform!.name),
                      if (preferences.developerMode.value)
                        tiamat.Text.labelLow(getEncryptionInfo()),
                      if (preferences.developerMode.value)
                        tiamat.Text.labelLow(commandLineArgs.join(" "))
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: tiamat.IconButton(
                      icon: Icons.copy,
                      onPressed: copySystemInfo,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        // Vommet issue 670: run the release check by hand (release builds
        // only; other builds have no release to compare with).
        if (ReleaseNotice.canCheck)
          const Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: _UpdateCheck(),
            ),
          ),
        // Vommet issue 798: the changelog inline, newest first; it scrolls
        // for older updates. The "What's New" link below stays.
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: toggleRecentUpdates,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(recentUpdates == null
                        ? Icons.expand_more
                        : Icons.expand_less),
                    const SizedBox(width: 6),
                    tiamat.Text.labelEmphasised(labelRecentUpdates),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (recentUpdates != null)
          Expanded(
            child: FutureBuilder<List<ChangelogEntry>>(
              future: recentUpdates,
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox.shrink();
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: WhatsNewList(snapshot.data!),
                  ),
                );
              },
            ),
          )
        else
          const Spacer(),
        SettingsCategoryAbout.info(context)
      ],
    );
  }

  String getEncryptionInfo() {
    var info = getVodozemacVersion();
    info ??= "No encryption library found";
    return info;
  }

  String? getVodozemacVersion() {
    try {
      var initialized = vod.isInitialized();
      if (initialized) {
        return "Vodozemac Initialized";
      }

      return null;
    } catch (exception) {
      return null;
    }
  }

  void copySystemInfo() {
    var data = """
<details open>
<summary>Device Information</summary>
<br>

**Device**
Platform: `${BuildConfig.PLATFORM}`
Version: `${BuildConfig.VERSION_TAG}`
Git Hash: `${BuildConfig.GIT_HASH}`
Detail: `${BuildConfig.BUILD_DETAIL}`
Build Timestamp: `${BuildConfig.BUILD_DATE.millisecondsSinceEpoch} (${intl.DateFormat(intl.DateFormat.YEAR_MONTH_DAY).format(BuildConfig.BUILD_DATE)})`

**System Info**
${systemInfo?.toMarkdown() ?? ""}
${Subplatforms.subplatform != null ? "Subplatform: `${Subplatforms.subplatform!.name}`" : ""}
</details>
""";

    Clipboard.setData(ClipboardData(text: data));
  }
}

/// Vommet issue 670: Settings › About's "Check for updates". A newer release
/// shows the usual new-version bar (re-opened if it was closed); otherwise a
/// short line says so here.
class _UpdateCheck extends StatefulWidget {
  const _UpdateCheck();

  @override
  State<_UpdateCheck> createState() => _UpdateCheckState();
}

class _UpdateCheckState extends State<_UpdateCheck> {
  bool checking = false;
  String? message;

  String get labelCheckForUpdates => Intl.message("Check for updates",
      name: "labelCheckForUpdates",
      desc: "Button in Settings › About that checks for a newer release");

  String get messageUpToDate =>
      Intl.message("You're on the latest version of Vommet.",
          name: "messageUpToDate",
          desc: "Shown in Settings › About when the update check finds no "
              "newer release");

  String messageUpdateFound(String version) =>
      Intl.message("$version is out. See the bar at the bottom of the app.",
          args: [version],
          name: "messageUpdateFound",
          desc: "Shown in Settings › About when the update check finds a "
              "newer release, with the release's name; the new-version bar "
              "at the bottom of the app has its update actions");

  String get messageUpdateCheckFailed =>
      Intl.message("Couldn't check for updates. Try again later.",
          name: "messageUpdateCheckFailed",
          desc: "Shown in Settings › About when the update check couldn't "
              "reach the release list");

  Future<void> check() async {
    setState(() {
      checking = true;
      message = null;
    });
    final result = await ReleaseNotice.check(manual: true);
    if (!mounted) return;
    setState(() {
      checking = false;
      message = switch (result) {
        ReleaseCheckResult.newer =>
          messageUpdateFound(ReleaseNotice.newer.value ?? ""),
        ReleaseCheckResult.upToDate => messageUpToDate,
        ReleaseCheckResult.failed => messageUpdateCheckFailed,
        ReleaseCheckResult.notReleaseBuild ||
        ReleaseCheckResult.disabled =>
          null,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        tiamat.Button.secondary(
          text: labelCheckForUpdates,
          isLoading: checking,
          onTap: checking ? null : check,
        ),
        if (message != null) tiamat.Text.labelLow(message!),
      ],
    );
  }
}
