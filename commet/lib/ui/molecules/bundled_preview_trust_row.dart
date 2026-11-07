import 'package:commet/client/client.dart';
import 'package:commet/client/components/url_preview/url_preview_component.dart';
import 'package:commet/client/components/url_preview/url_preview_room_policy.dart';
import 'package:commet/debug/log.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet issue 676: on someone's profile, whether the link previews their
/// app attaches show: Ask (each chat's setting), Always or Never. Saved in
/// the Always/Never lists of the account's data.
class BundledPreviewTrustRow extends StatefulWidget {
  const BundledPreviewTrustRow(
      {required this.client,
      required this.userId,
      required this.name,
      super.key});

  final Client client;
  final String userId;

  /// Their display name, for the labels.
  final String name;

  static String labelTitle(String name) =>
      Intl.message("Link previews from $name",
          args: [name],
          name: "labelProfileBundledPreviewsTitle",
          desc: "Profile row: whether link previews this person's app "
              "attaches show");

  static String labelCaption(String name) => Intl.message(
      "Previews $name’s app attaches to links. “Ask” follows each chat’s setting.",
      args: [name],
      name: "labelProfileBundledPreviewsCaption",
      desc: "Under the Ask/Always/Never choice for a person's link previews");

  static String get labelAsk => Intl.message("Ask",
      name: "labelProfileBundledPreviewsAsk",
      desc: "Choice: link previews from this person follow each chat's "
          "setting");

  static String get labelAlways => Intl.message("Always",
      name: "labelProfileBundledPreviewsAlways",
      desc: "Choice: always show link previews from this person");

  static String get labelNever => Intl.message("Never",
      name: "labelProfileBundledPreviewsNever",
      desc: "Choice: never show link previews from this person");

  @override
  State<BundledPreviewTrustRow> createState() => _BundledPreviewTrustRowState();
}

enum _Choice { ask, always, never }

class _BundledPreviewTrustRowState extends State<BundledPreviewTrustRow> {
  BundledUrlPreviewConsent? consent;

  @override
  void initState() {
    super.initState();
    if (widget.client.getComponent<UrlPreviewComponent>()
        case BundledUrlPreviewConsent component) {
      consent = component;
      component.bundledConsentChanges.addListener(_changed);
    }
  }

  @override
  void dispose() {
    consent?.bundledConsentChanges.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> choose(_Choice choice) async {
    try {
      await consent?.setBundledPreviewTrust(
          widget.userId,
          switch (choice) {
            _Choice.ask => null,
            _Choice.always => BundledPreviewPersonTrust.always,
            _Choice.never => BundledPreviewPersonTrust.never,
          });
    } catch (e) {
      Log.w("Couldn't save the link preview choice for a person: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final consent = this.consent;
    if (consent == null) return const SizedBox.shrink();

    final current =
        switch (consent.bundledPreviewPeople.trustOf(widget.userId)) {
      null => _Choice.ask,
      BundledPreviewPersonTrust.always => _Choice.always,
      BundledPreviewPersonTrust.never => _Choice.never,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.link,
                  size: 20, color: Theme.of(context).colorScheme.secondary),
              const SizedBox(width: 8),
              Flexible(
                child: tiamat.Text.labelEmphasised(
                    BundledPreviewTrustRow.labelTitle(widget.name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SegmentedButton<_Choice>(
            key: const ValueKey("profile-bundled-previews"),
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                  value: _Choice.ask,
                  label: Text(BundledPreviewTrustRow.labelAsk)),
              ButtonSegment(
                  value: _Choice.always,
                  label: Text(BundledPreviewTrustRow.labelAlways)),
              ButtonSegment(
                  value: _Choice.never,
                  label: Text(BundledPreviewTrustRow.labelNever)),
            ],
            selected: {current},
            onSelectionChanged: (selection) => choose(selection.first),
          ),
          const SizedBox(height: 6),
          tiamat.Text.labelLow(
              BundledPreviewTrustRow.labelCaption(widget.name)),
        ],
      ),
    );
  }
}
