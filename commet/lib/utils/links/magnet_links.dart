// Vommet issue 1139: consent for magnet links belongs to the receiving
// account and actual event sender. Never consult web-domain trust/bypass.
import 'package:commet/main.dart';
import 'package:commet/utils/links/magnet_uri.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:url_launcher/url_launcher.dart';

class MessageLinkOrigin {
  const MessageLinkOrigin(this.clientId, this.accountId, this.senderId);
  // Capture the authenticated account when the real message builds; never
  // substitute the active account when the link is later tapped.
  factory MessageLinkOrigin.fromMessage(String clientId, String senderId) =>
      MessageLinkOrigin(clientId,
          clientManager?.getClient(clientId)?.self?.identifier, senderId);

  final String clientId;
  final String? accountId;
  final String senderId;

  bool get isCurrent =>
      accountId?.startsWith('@') == true &&
      accountId!.contains(':') &&
      senderId.startsWith('@') &&
      senderId.indexOf(':') > 1 &&
      clientManager?.getClient(clientId)?.self?.identifier == accountId;

  String get key =>
      [clientId, accountId ?? '', senderId].map(Uri.encodeComponent).join('|');

  static MessageLinkOrigin? fromKey(String key) {
    try {
      final parts = key.split('|').map(Uri.decodeComponent).toList();
      if (parts.length != 3 || parts.any((part) => part.isEmpty)) return null;
      return MessageLinkOrigin(parts[0], parts[1], parts[2]);
    } on FormatException {
      return null;
    } on ArgumentError {
      // Uri.decodeComponent uses ArgumentError for malformed percent escapes.
      return null;
    }
  }
}

class MagnetSenderTrust {
  static List<MessageLinkOrigin> get entries =>
      preferences.trustedMagnetSenders.value
          .map(MessageLinkOrigin.fromKey)
          .nonNulls
          .toList();

  static bool contains(MessageLinkOrigin origin) =>
      origin.isCurrent &&
      preferences.trustedMagnetSenders.value.contains(origin.key);

  static Future<void> remember(MessageLinkOrigin origin) async {
    if (!origin.isCurrent || contains(origin)) return;
    await preferences.trustedMagnetSenders
        .set([...preferences.trustedMagnetSenders.value, origin.key]);
  }

  static Future<void> remove(MessageLinkOrigin origin) async {
    final remaining = preferences.trustedMagnetSenders.value
        .where((key) => key != origin.key)
        .toList();
    if (remaining.isEmpty) {
      await preferences.trustedMagnetSenders.reset();
    } else {
      await preferences.trustedMagnetSenders.set(remaining);
    }
  }
}

class MagnetLinks {
  static final _pending = <BuildContext>{};

  static Future<void> open(Uri uri,
      {BuildContext? context, MessageLinkOrigin? origin}) async {
    if (context == null || !context.mounted || !_pending.add(context)) return;
    try {
      if (!MagnetUri.isValid(uri)) {
        await _failure(context, uri, invalid: true);
        return;
      }
      var remember = false;
      if (kIsWeb || origin == null || !MagnetSenderTrust.contains(origin)) {
        final choice = await showDialog<bool>(
            context: context,
            builder: (_) => MagnetLinkConfirmation(uri: uri, origin: origin));
        if (choice == null || !context.mounted) return;
        remember = choice;
      }
      if (kIsWeb) {
        await Clipboard.setData(ClipboardData(text: uri.toString()));
        return;
      }
      // Revalidate the binding after the dialog; a removed/replaced account
      // cannot inherit a permission or create one. Unknown origin stays once.
      if (origin != null && !origin.isCurrent) remember = false;
      bool accepted;
      try {
        accepted = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        accepted = false;
      }
      if (!accepted) {
        if (context.mounted) await _failure(context, uri);
      } else if (remember && origin != null) {
        await MagnetSenderTrust.remember(origin);
      }
    } finally {
      _pending.remove(context);
    }
  }

  static Future<void> _failure(BuildContext context, Uri uri,
          {bool invalid = false}) =>
      showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
                scrollable: true,
                title: Text(invalid ? MagnetText.invalid : MagnetText.failed),
                content: SizedBox(
                    width: 480,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(invalid
                              ? MagnetText.invalidBody
                              : MagnetText.failedBody),
                          const SizedBox(height: 12),
                          SelectableText(uri.toString())
                        ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(MagnetText.close)),
                  TextButton(
                      onPressed: () async {
                        await Clipboard.setData(
                            ClipboardData(text: uri.toString()));
                        if (context.mounted) Navigator.pop(context);
                      },
                      child: Text(MagnetText.copy))
                ],
              ));
}

class MagnetLinkConfirmation extends StatefulWidget {
  const MagnetLinkConfirmation({required this.uri, this.origin, super.key});
  final Uri uri;
  final MessageLinkOrigin? origin;

  @override
  State<MagnetLinkConfirmation> createState() => _MagnetLinkConfirmationState();
}

class _MagnetLinkConfirmationState extends State<MagnetLinkConfirmation> {
  bool remember = false;

  @override
  Widget build(BuildContext context) {
    final origin = widget.origin;
    final known = origin?.isCurrent == true;
    return AlertDialog(
      scrollable: true,
      title: Text(MagnetText.title),
      content: SizedBox(
          width: 480,
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SelectableText(known
                    ? MagnetText.from(origin!.senderId)
                    : MagnetText.unknown),
                if (known)
                  SelectableText(MagnetText.account(origin!.accountId!)),
                const SizedBox(height: 16),
                Text(kIsWeb ? MagnetText.web : MagnetText.handoff),
                const SizedBox(height: 12),
                ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 144),
                    child: SingleChildScrollView(
                        child: SelectableText(widget.uri.toString()))),
                if (known && !kIsWeb) ...[
                  CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: remember,
                      title: Text(MagnetText.remember),
                      onChanged: (value) =>
                          setState(() => remember = value ?? false)),
                  Text(MagnetText.scope,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ])),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(MagnetText.cancel)),
        FilledButton(
            onPressed: () => Navigator.pop(context, remember),
            child: Text(kIsWeb
                ? MagnetText.copy
                : remember
                    ? MagnetText.openRemember
                    : MagnetText.openOnce)),
      ],
    );
  }
}

class TrustedMagnetSendersPanel extends StatelessWidget {
  const TrustedMagnetSendersPanel({super.key});

  @override
  Widget build(BuildContext context) => StreamBuilder(
      stream: preferences.trustedMagnetSenders.onChanged,
      builder: (context, _) {
        final entries = MagnetSenderTrust.entries;
        final accounts =
            entries.map((entry) => entry.accountId!).toSet().toList()..sort();
        return Padding(
            padding: const EdgeInsets.only(top: 10),
            child: tiamat.Panel(
                header: MagnetText.settings,
                mode: tiamat.TileType.surfaceContainerLow,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(entries.isEmpty
                          ? MagnetText.empty
                          : MagnetText.settingsBody),
                      for (final account in accounts) ...[
                        const SizedBox(height: 12),
                        SelectableText(account),
                        for (final entry in entries
                            .where((entry) => entry.accountId == account))
                          Row(children: [
                            Expanded(child: SelectableText(entry.senderId)),
                            IconButton(
                                tooltip: MagnetText.remove,
                                icon: const Icon(Icons.close),
                                onPressed: () =>
                                    MagnetSenderTrust.remove(entry))
                          ]),
                      ],
                    ])));
      });
}

// All user-visible wording is localized, including fallback and copy actions.
class MagnetText {
  static String get title =>
      Intl.message('Open magnet link?', name: 'magnetTitle');
  static String from(String sender) =>
      Intl.message('From $sender', name: 'magnetFrom', args: [sender]);
  static String account(String account) =>
      Intl.message('Using $account', name: 'magnetAccount', args: [account]);
  static String get unknown =>
      Intl.message('Sender unavailable', name: 'magnetUnknown');
  static String get handoff => Intl.message(
      'Your device will choose an app for this magnet link. The app may start a download or contact torrent peers.',
      name: 'magnetHandoff');
  static String get web => Intl.message(
      'Copy this magnet link and open it in an app that handles torrents. Browser handoff is not supported here.',
      name: 'magnetWeb');
  static String get remember =>
      Intl.message('Remember for magnet links from this sender',
          name: 'magnetRemember');
  static String get scope => Intl.message(
      'This account · all rooms · this device. Change in Settings › Privacy.',
      name: 'magnetScope');
  static String get cancel => Intl.message('Cancel', name: 'magnetCancel');
  static String get openOnce =>
      Intl.message('Open once', name: 'magnetOpenOnce');
  static String get openRemember =>
      Intl.message('Open & remember', name: 'magnetOpenRemember');
  static String get copy => Intl.message('Copy link', name: 'magnetCopy');
  static String get close => Intl.message('Close', name: 'magnetClose');
  static String get failed =>
      Intl.message('Couldn’t open magnet link', name: 'magnetFailed');
  static String get failedBody => Intl.message(
      'Your device did not accept the request. Set up an app that handles magnet links, or copy the link and open it yourself. No new sender trust was saved.',
      name: 'magnetFailedBody');
  static String get invalid =>
      Intl.message('Invalid magnet link', name: 'magnetInvalid');
  static String get invalidBody => Intl.message(
      'This link does not contain a supported torrent identifier. It was not opened.',
      name: 'magnetInvalidBody');
  static String get settings =>
      Intl.message('Trusted magnet senders', name: 'magnetSettings');
  static String get empty =>
      Intl.message('No trusted magnet senders', name: 'magnetEmpty');
  static String get settingsBody => Intl.message(
      'Magnet links from these senders open without asking after you tap them. Applies to the listed account, in all rooms, on this device.',
      name: 'magnetSettingsBody');
  static String get remove =>
      Intl.message('Remove magnet trust', name: 'magnetRemove');
}
