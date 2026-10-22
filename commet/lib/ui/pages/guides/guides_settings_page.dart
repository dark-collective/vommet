// Vommet: Settings › Help and guides. Getting started on top, then every
// guide, with a filter that also searches the guides' text.
import 'package:commet/ui/pages/guides/getting_started.dart';
import 'package:commet/ui/pages/guides/guide_pictures.dart';
import 'package:commet/ui/pages/guides/guides.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class GuidesSettingsPage extends StatefulWidget {
  const GuidesSettingsPage({super.key, this.texts});

  /// Guide texts for the filter, for tests; loaded from the assets if null.
  final Map<String, String>? texts;

  @override
  State<GuidesSettingsPage> createState() => _GuidesSettingsPageState();
}

class _GuidesSettingsPageState extends State<GuidesSettingsPage> {
  final TextEditingController filter = TextEditingController();
  Map<String, String> texts = const {};

  @override
  void initState() {
    super.initState();
    if (widget.texts != null) {
      texts = widget.texts!;
    } else {
      Guides.loadAll().then((t) {
        if (mounted) setState(() => texts = t);
      });
    }
    filter.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    filter.dispose();
    super.dispose();
  }

  Future<void> openGuide(String id) async {
    await Guides.open(context, id);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final query = filter.text.trim();
    final matches = Guides.filter(query, texts: texts);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        TextField(
          key: const ValueKey("guides-filter"),
          controller: filter,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: guidesFilterHint,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
        if (query.isEmpty) const _GettingStartedCard(),
        if (query.isNotEmpty)
          tiamat.Text.labelLow(guidesFilterCount(matches.length, query)),
        for (final guide in matches)
          tiamat.Panel(
            mode: tiamat.TileType.surfaceContainerLow,
            padding: 0,
            mainAxisSize: MainAxisSize.min,
            child: ListTile(
              leading: Icon(guide.icon),
              title: Text(guide.title),
              subtitle: Text(guide.summary),
              trailing: guide.read
                  ? Tooltip(
                      message: guidesReadLabel,
                      child: Icon(Icons.check,
                          color: Theme.of(context).colorScheme.primary),
                    )
                  : null,
              onTap: () => openGuide(guide.id),
            ),
          ),
      ],
    );
  }
}

class _GettingStartedCard extends StatelessWidget {
  const _GettingStartedCard();

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Material(
      color: c.primaryContainer,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => GettingStarted.open(context),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            spacing: 14,
            children: [
              const GuidePicture("overview", height: 64),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(gettingStartedCardTitle,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                                color: c.onPrimaryContainer,
                                fontWeight: FontWeight.w700)),
                    Text(gettingStartedCardBody,
                        style: TextStyle(color: c.onPrimaryContainer)),
                  ],
                ),
              ),
              Icon(Icons.play_arrow_rounded, color: c.onPrimaryContainer),
            ],
          ),
        ),
      ),
    );
  }
}

String get guidesFilterHint => Intl.message("Search the guides",
    name: "guidesFilterHint",
    desc: "Hint in the filter box above the list of guides in Settings");

String guidesFilterCount(int count, String query) => Intl.plural(count,
    zero: "No guides match \"$query\"",
    one: "1 guide matches \"$query\"",
    other: "$count guides match \"$query\"",
    args: [count, query],
    name: "guidesFilterCount",
    desc: "Shown above the filtered list of guides");

String get guidesReadLabel => Intl.message("Read",
    name: "guidesReadLabel",
    desc: "Tooltip on the check mark next to a guide the user has opened");

String get gettingStartedCardTitle => Intl.message("Getting started",
    name: "gettingStartedCardTitle",
    desc: "Title of the card in Settings that starts the walkthrough");

String get gettingStartedCardBody => Intl.message(
    "A quick look around Vommet, with pictures. About two minutes.",
    name: "gettingStartedCardBody",
    desc: "Text of the card in Settings that starts the walkthrough");
