// Vommet: one guide, with the list of guides beside it on wide screens.
// A guide's text is Markdown, plus `[[picture: <name>]]` lines for the
// pictures in guide_pictures.dart; links to `guide:<id>` open another guide.
import 'package:commet/config/layout_config.dart';
import 'package:commet/ui/atoms/scaled_safe_area.dart';
import 'package:commet/ui/pages/guides/guide_pictures.dart';
import 'package:commet/ui/pages/guides/guides.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class GuidePage extends StatefulWidget {
  const GuidePage({required this.initialGuide, super.key});

  final String initialGuide;

  @override
  State<GuidePage> createState() => _GuidePageState();
}

class _GuidePageState extends State<GuidePage> {
  late String current = widget.initialGuide;
  final ScrollController scroll = ScrollController();

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  void show(String id) {
    if (Guides.byId(id) == null) return;
    guidesRead.add(id);
    setState(() => current = id);
    if (scroll.hasClients) scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final desktop = MediaQuery.of(context).desktop;
    final guide = Guides.byId(current);
    return Material(
      child: tiamat.Tile(
        child: ScaledSafeArea(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (desktop)
                SizedBox(
                  width: 230,
                  child: tiamat.Tile.low(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(8, 70, 8, 8),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                          child: tiamat.Text.labelEmphasised(guidesHeader),
                        ),
                        for (final g in Guides.all)
                          tiamat.TextButton(
                            g.title,
                            icon: g.icon,
                            highlighted: g.id == current,
                            onTap: () => show(g.id),
                          ),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: Stack(
                  children: [
                    ListView(
                      controller: scroll,
                      padding: const EdgeInsets.fromLTRB(20, 70, 20, 32),
                      children: [
                        if (guide != null)
                          Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 680),
                              child: GuideBody(
                                key: ValueKey(guide.id),
                                guide: guide,
                                onOpenGuide: show,
                              ),
                            ),
                          ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: tiamat.CircleButton(
                        radius: 25,
                        icon: Icons.arrow_back,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A guide's title and text.
class GuideBody extends StatefulWidget {
  const GuideBody(
      {required this.guide, required this.onOpenGuide, this.text, super.key});

  final Guide guide;
  final void Function(String id) onOpenGuide;

  /// The text, for tests; loaded from the assets when null.
  final String? text;

  @override
  State<GuideBody> createState() => _GuideBodyState();
}

class _GuideBodyState extends State<GuideBody> {
  String? text;

  @override
  void initState() {
    super.initState();
    text = widget.text;
    if (text == null) {
      Guides.load(widget.guide.id).then((t) {
        if (mounted) setState(() => text = t);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: theme.textTheme.bodyLarge,
      h2: theme.textTheme.titleLarge,
      h2Padding: const EdgeInsets.only(top: 12),
      tableBorder: TableBorder.all(color: theme.colorScheme.outlineVariant),
      tableCellsPadding: const EdgeInsets.all(8),
      tableHead: theme.textTheme.labelLarge,
      tableBody: theme.textTheme.bodyMedium,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        tiamat.Text.label(guidesHeader),
        tiamat.Text.largeTitle(widget.guide.question),
        if (text != null)
          for (final part in GuideText.parts(text!))
            if (part.picture != null)
              GuidePicture(part.picture!)
            else
              MarkdownBody(
                data: part.markdown!,
                styleSheet: style,
                onTapLink: (_, href, __) {
                  final id = GuideText.guideLink(href);
                  if (id != null) widget.onOpenGuide(id);
                },
              ),
      ],
    );
  }
}

class GuideTextPart {
  const GuideTextPart({this.markdown, this.picture});
  final String? markdown;
  final String? picture;
}

class GuideText {
  static final _picture = RegExp(r"^\[\[picture:\s*([a-z-]+)\s*\]\]\s*$");

  /// Splits a guide's text into Markdown runs and pictures.
  static List<GuideTextPart> parts(String text) {
    final result = <GuideTextPart>[];
    final buffer = <String>[];
    void flush() {
      final md = buffer.join("\n").trim();
      if (md.isNotEmpty) result.add(GuideTextPart(markdown: md));
      buffer.clear();
    }

    for (final line in text.split("\n")) {
      final match = _picture.firstMatch(line.trim());
      if (match != null) {
        flush();
        result.add(GuideTextPart(picture: match.group(1)));
      } else {
        buffer.add(line);
      }
    }
    flush();
    return result;
  }

  /// The guide a `guide:<id>` link points at.
  static String? guideLink(String? href) {
    if (href == null || !href.startsWith("guide:")) return null;
    return href.substring("guide:".length);
  }
}

String get guidesHeader => Intl.message("Help and guides",
    name: "guidesHeader",
    desc: "Header above the list of guides, and the Settings tab with them");
