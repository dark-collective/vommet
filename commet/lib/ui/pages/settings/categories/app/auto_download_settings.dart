import 'package:commet/ui/navigation/navigation_utils.dart';
import 'package:commet/ui/pages/settings/mobile_settings_page.dart';
import 'package:commet/utils/media_auto_download.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Vommet: Data and storage › Automatic media download (Vommet issue 75):
/// whether pictures, GIFs and stickers, and video preview pictures download
/// by themselves on mobile data and on Wi-Fi. Phones only.
class AutoDownloadCard extends StatefulWidget {
  const AutoDownloadCard({super.key});

  @override
  State<AutoDownloadCard> createState() => _AutoDownloadCardState();
}

String get labelAutoDownloadMobile => Intl.message("When using mobile data",
    desc: "Automatic media download choice for mobile data",
    name: "labelAutoDownloadMobile");

String get labelAutoDownloadWifi => Intl.message("When connected to Wi-Fi",
    desc: "Automatic media download choice for Wi-Fi",
    name: "labelAutoDownloadWifi");

String _labelNetwork(MediaNetwork network) => switch (network) {
      MediaNetwork.mobile => labelAutoDownloadMobile,
      MediaNetwork.wifi => labelAutoDownloadWifi,
    };

String get labelAutoDownloadPhotos => Intl.message("Photos",
    desc: "Automatic download of pictures", name: "labelAutoDownloadPhotos");

String get labelAutoDownloadGifs => Intl.message("GIFs and stickers",
    desc: "Automatic download of GIFs and stickers",
    name: "labelAutoDownloadGifs");

String get labelAutoDownloadVideoPreviews => Intl.message("Video previews",
    desc: "Automatic download of video preview pictures",
    name: "labelAutoDownloadVideoPreviews");

String get labelAutoDownloadOff => Intl.message("Off: tap media to load it",
    desc: "Summary when automatic media download is off",
    name: "labelAutoDownloadOff");

/// "Photos, GIFs and stickers, video previews", or what happens when off.
String autoDownloadSummary(AutoDownloadPolicy policy) {
  final off = labelAutoDownloadOff;
  if (!policy.enabled) return off;
  final kinds = [
    if (policy.photos) labelAutoDownloadPhotos,
    if (policy.gifs) labelAutoDownloadGifs,
    if (policy.videoPreviews) labelAutoDownloadVideoPreviews.toLowerCase(),
  ];
  return kinds.isEmpty ? off : kinds.join(", ");
}

class _AutoDownloadCardState extends State<AutoDownloadCard> {
  String get labelAutoDownloadTitle => Intl.message("Automatic media download",
      desc: "Header for the automatic media download settings",
      name: "labelAutoDownloadTitle");

  String get labelAutoDownloadReset => Intl.message(
      "Reset auto-download settings",
      desc: "Puts the automatic media download settings back to the defaults",
      name: "labelAutoDownloadReset");

  String get labelAutoDownloadNote => Intl.message(
      "Avatars, emoji and your own uploads always load. Videos and files only download when you play or open them; roaming counts as mobile data.",
      desc: "Explains what automatic media download covers",
      name: "labelAutoDownloadNote");

  Future<void> open(MediaNetwork network) async {
    await NavigationUtils.navigateTo(
        context,
        SettingsSubPage(
            builder: (_) => AutoDownloadNetworkPage(network: network)));
    if (mounted) setState(() {});
  }

  Future<void> toggle(MediaNetwork network, bool enabled) async {
    final policy = MediaAutoDownload.policyFor(network);
    await MediaAutoDownload.setPolicy(
        network, policy.copyWith(enabled: enabled));
    if (mounted) setState(() {});
  }

  Future<void> reset() async {
    for (final network in MediaNetwork.values) {
      await MediaAutoDownload.setPolicy(network, const AutoDownloadPolicy());
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget divider() => Divider(
        height: 1,
        indent: 16,
        color: theme.colorScheme.outlineVariant.withAlpha(90));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AutoDownloadSettingsCard(
          title: labelAutoDownloadTitle,
          children: [
            for (final network in [MediaNetwork.mobile, MediaNetwork.wifi]) ...[
              _NetworkRow(
                title: _labelNetwork(network),
                summary:
                    autoDownloadSummary(MediaAutoDownload.policyFor(network)),
                enabled: MediaAutoDownload.policyFor(network).enabled,
                onTap: () => open(network),
                onChanged: (v) => toggle(network, v),
              ),
              divider(),
            ],
            InkWell(
              onTap: reset,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Text(labelAutoDownloadReset,
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(color: theme.colorScheme.error)),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 14),
          child: Text(labelAutoDownloadNote,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
      ],
    );
  }
}

/// Vommet: one network's automatic media download choices.
class AutoDownloadNetworkPage extends StatefulWidget {
  const AutoDownloadNetworkPage({required this.network, super.key});
  final MediaNetwork network;

  @override
  State<AutoDownloadNetworkPage> createState() =>
      _AutoDownloadNetworkPageState();
}

class _AutoDownloadNetworkPageState extends State<AutoDownloadNetworkPage> {
  String get labelAutoDownloadMaster =>
      Intl.message("Download media automatically",
          desc: "Turns automatic media download on or off for one network",
          name: "labelAutoDownloadMaster");

  String get labelAutoDownloadTypes => Intl.message("Types of media",
      desc: "Header for the kinds of media downloaded automatically",
      name: "labelAutoDownloadTypes");

  String get labelAutoDownloadOn =>
      Intl.message("On", desc: "A setting is on", name: "labelAutoDownloadOn");

  String get labelAutoDownloadOffShort => Intl.message("Off",
      desc: "A setting is off", name: "labelAutoDownloadOffShort");

  String get labelAutoDownloadPageNote => Intl.message(
      "Media that isn't downloaded shows a blurred preview with its size; tap it to load it.",
      desc: "Explains what happens to media that isn't downloaded",
      name: "labelAutoDownloadPageNote");

  late AutoDownloadPolicy policy = MediaAutoDownload.policyFor(widget.network);

  Future<void> update(AutoDownloadPolicy next) async {
    setState(() => policy = next);
    await MediaAutoDownload.setPolicy(widget.network, next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget divider() => Divider(
        height: 1,
        indent: 16,
        color: theme.colorScheme.outlineVariant.withAlpha(90));

    Widget typeRow(IconData icon, String label, bool value,
            void Function(bool) onChanged) =>
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
          child: Row(children: [
            Icon(icon, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: theme.colorScheme.onSurface)),
            ),
            Switch(
                value: value && policy.enabled,
                onChanged: policy.enabled ? onChanged : null),
          ]),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(_labelNetwork(widget.network),
              style: theme.textTheme.titleLarge?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w600)),
        ),
        AutoDownloadSettingsCard(children: [
          _NetworkRow(
            title: labelAutoDownloadMaster,
            summary: policy.enabled
                ? labelAutoDownloadOn
                : labelAutoDownloadOffShort,
            enabled: policy.enabled,
            onChanged: (v) => update(policy.copyWith(enabled: v)),
          ),
        ]),
        AutoDownloadSettingsCard(title: labelAutoDownloadTypes, children: [
          typeRow(Icons.image_outlined, labelAutoDownloadPhotos, policy.photos,
              (v) => update(policy.copyWith(photos: v))),
          divider(),
          typeRow(Icons.gif_box_outlined, labelAutoDownloadGifs, policy.gifs,
              (v) => update(policy.copyWith(gifs: v))),
          divider(),
          typeRow(
              Icons.movie_outlined,
              labelAutoDownloadVideoPreviews,
              policy.videoPreviews,
              (v) => update(policy.copyWith(videoPreviews: v))),
        ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 14),
          child: Text(labelAutoDownloadPageNote,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
      ],
    );
  }
}

/// A row with a title, a summary under it and a switch; tapping the text
/// opens [onTap] (behind a separator, like Telegram) when given.
class _NetworkRow extends StatelessWidget {
  const _NetworkRow({
    required this.title,
    required this.summary,
    required this.enabled,
    required this.onChanged,
    this.onTap,
  });

  final String title;
  final String summary;
  final bool enabled;
  final void Function(bool) onChanged;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: theme.colorScheme.onSurface)),
              const SizedBox(height: 2),
              Text(summary,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ]),
          ),
          if (onTap != null)
            Container(
                width: 1,
                height: 32,
                margin: const EdgeInsets.only(right: 8),
                color: theme.colorScheme.outlineVariant),
          Switch(value: enabled, onChanged: onChanged),
        ]),
      ),
    );
  }
}

/// A rounded settings card with an optional coloured header, matching the
/// Data and storage page.
class AutoDownloadSettingsCard extends StatelessWidget {
  const AutoDownloadSettingsCard(
      {this.title, required this.children, super.key});
  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Text(title!,
                  style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600)),
            ),
          ...children,
        ]),
      ),
    );
  }
}
