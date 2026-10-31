// Vommet (New Home cards, round 4): the Text card. Your own words with the
// composer's Markdown (headings, bold, lists, links), images uploaded to
// your homeserver, and up to three buttons that open a link, a room or a
// Vommet screen. Vommet's own Text cards (a "preset", content shipped in the
// app) are read-only with "Make a copy". The content model:
// new_home_text_model.dart.
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_mxc_image_provider.dart';
import 'package:commet/ui/atoms/rich_text/matrix_html_parser.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/navigation/navigation_utils.dart';
import 'package:commet/ui/organisms/new_home/new_home.dart';
import 'package:commet/ui/organisms/new_home/new_home_cards.dart';
import 'package:commet/ui/organisms/new_home/new_home_layout.dart';
import 'package:commet/ui/organisms/new_home/new_home_text_model.dart';
import 'package:commet/ui/pages/guides/getting_started.dart';
import 'package:commet/ui/pages/guides/guides.dart';
import 'package:commet/ui/pages/settings/app_settings_page.dart';
import 'package:commet/ui/pages/setup/menus/whats_new_setup.dart';
import 'package:commet/utils/links/link_utils.dart';
import 'package:commet/utils/org_italics.dart';
import 'package:commet/utils/picker_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Vommet's own Text cards, from assets/data/home_text_cards.json, loaded
/// once.
class HomeTextPresets {
  static const String asset = "assets/data/home_text_cards.json";
  static Map<String, TextPreset>? _cache;
  static Future<Map<String, TextPreset>>? _loading;

  /// The presets once loaded (empty before), for synchronous titles.
  static Map<String, TextPreset> get loaded => _cache ?? const {};

  static Future<Map<String, TextPreset>> load({AssetBundle? bundle}) =>
      _loading ??= (bundle ?? rootBundle)
          .loadString(asset)
          .then(parseTextPresets, onError: (_) => <String, TextPreset>{})
          .then((presets) => _cache = presets);
}

/// The Text card's content: its own, or its preset's.
({String title, String body, List<TextButtonTarget> buttons})? textContentOf(
    HomeCard card) {
  final id = card.preset;
  if (id == null) {
    return (
      title: card.name ?? "Text",
      body: card.body ?? "",
      buttons: card.buttons
    );
  }
  final preset = HomeTextPresets.loaded[id];
  if (preset == null) return null;
  return (title: preset.title, body: preset.body, buttons: preset.buttons);
}

/// The account a Text card's images live on (the one Home's layout is
/// saved on).
MatrixClient? textCardClient(ClientManager manager) =>
    HomeLayoutStore.instance.account.value ??
    manager.clients.whereType<MatrixClient>().firstOrNull;

/// The Text card on Home: title in the card's header, body, buttons.
class NewHomeTextCardBody extends StatefulWidget {
  const NewHomeTextCardBody(
      {super.key, required this.clientManager, required this.card});
  final ClientManager clientManager;
  final HomeCard card;

  @override
  State<NewHomeTextCardBody> createState() => _NewHomeTextCardBodyState();
}

class _NewHomeTextCardBodyState extends State<NewHomeTextCardBody> {
  bool expanded = false;

  @override
  void initState() {
    super.initState();
    if (widget.card.preset != null && HomeTextPresets._cache == null) {
      HomeTextPresets.load().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final content = textContentOf(widget.card);
    final client = textCardClient(widget.clientManager);
    if (content == null || client == null) return const SizedBox.shrink();
    final collapses = textCollapses(content.body);
    final body = TextCardContent(body: content.body, client: client);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.card.preset != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
            child: Text("From Vommet · updated with the app",
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary)),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: collapses && !expanded
              ? ClipRect(
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(
                          maxHeight: textCollapsedLines * 21.0),
                      child: SingleChildScrollView(
                          physics: const NeverScrollableScrollPhysics(),
                          child: body)))
              : body,
        ),
        if (collapses)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: ValueKey("NewHomeTextMore-${widget.card.id}"),
              onPressed: () => setState(() => expanded = !expanded),
              child: Text(expanded ? "Show less" : "Show more"),
            ),
          ),
        if (content.buttons.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (i, b) in content.buttons.indexed)
                if (i == 0)
                  FilledButton(
                    key: ValueKey("NewHomeTextButton-${widget.card.id}-$i"),
                    onPressed: () => openTextButton(context, client, b),
                    child: Text(b.label),
                  )
                else
                  FilledButton.tonal(
                    key: ValueKey("NewHomeTextButton-${widget.card.id}-$i"),
                    onPressed: () => openTextButton(context, client, b),
                    child: Text(b.label),
                  ),
            ]),
          ),
      ],
    );
  }
}

/// A Text card's body: Markdown as the composer renders it, and images.
class TextCardContent extends StatelessWidget {
  const TextCardContent({super.key, required this.body, required this.client});
  final String body;
  final MatrixClient client;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 6,
      children: [
        for (final block in textBlocks(body))
          if (block.isImage)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: Image(
                  image: MatrixMxcImage(
                      Uri.parse(block.image!), client.matrixClient,
                      scaledThumbnail: true),
                  semanticLabel: block.alt,
                  fit: BoxFit.contain,
                  errorBuilder: (context, _, __) => Text(block.alt ?? "Image",
                      style: TextStyle(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                ),
              ),
            )
          else
            MatrixHtmlParser.parse(markdown(block.text), client, null,
                mentionsRoom: false),
      ],
    );
  }
}

/// A button's tap: its link, its room, or its Vommet screen.
Future<void> openTextButton(
    BuildContext context, MatrixClient client, TextButtonTarget b) async {
  switch (b.kind) {
    case TextButtonTarget.link:
      await LinkUtils.open(Uri.parse(b.target.trim()), context: context);
    case TextButtonTarget.room:
      await LinkUtils.open(Uri.parse("https://matrix.to/#/${b.target.trim()}"),
          clientId: client.identifier, context: context);
    case TextButtonTarget.screen:
      switch (b.target) {
        case "settings":
          await NavigationUtils.navigateTo(context, const AppSettingsPage());
        case "whats_new":
          await WhatsNewSetup.showAll(context);
        case "guides":
          final first = Guides.all.firstOrNull;
          if (first != null) await Guides.open(context, first.id);
        case "getting_started":
          await GettingStarted.open(context);
      }
  }
}

/// "Make a copy" of one of Vommet's Text cards: your own Text card with its
/// content, right after it.
Future<void> copyTextPreset(HomeCard card) async {
  final content = textContentOf(card);
  if (content == null) return;
  final store = HomeLayoutStore.instance;
  final layout = store.layout.value;
  final copy = layout.newCard(HomeLayout.textCard).copyWith(
      name: content.title, body: content.body, buttons: content.buttons);
  final at = layout.visible.indexWhere((c) => c.id == card.id);
  await store.save(layout.insert(copy, gap: at < 0 ? null : at + 1));
}

/// The Text card's editor: [card] edited, or a new card when [editing] is
/// false. Returns the card, or null when cancelled.
Future<HomeCard?> showTextCardEditor(
    BuildContext context, ClientManager manager,
    {required HomeCard card, bool editing = false}) {
  return showDialog<HomeCard>(
    context: context,
    builder: (context) =>
        TextCardEditor(manager: manager, card: card, editing: editing),
  );
}

/// Edits a Text card in place (⋯ Settings…).
Future<void> editTextCard(
    BuildContext context, ClientManager manager, HomeCard card) async {
  final next =
      await showTextCardEditor(context, manager, card: card, editing: true);
  if (next == null) return;
  final store = HomeLayoutStore.instance;
  await store.save(store.layout.value.replace(next));
}

class TextCardEditor extends StatefulWidget {
  const TextCardEditor(
      {super.key,
      required this.manager,
      required this.card,
      this.editing = false});
  final ClientManager manager;
  final HomeCard card;
  final bool editing;

  @override
  State<TextCardEditor> createState() => _TextCardEditorState();
}

class _TextCardEditorState extends State<TextCardEditor> {
  late final title = TextEditingController(text: widget.card.name ?? "");
  late final body = TextEditingController(text: widget.card.body ?? "");
  late List<TextButtonTarget> buttons = List.of(widget.card.buttons);
  bool preview = false;
  bool uploading = false;

  @override
  void dispose() {
    title.dispose();
    body.dispose();
    super.dispose();
  }

  void apply(TextEdit edit) {
    body.value = TextEditingValue(
        text: edit.text,
        selection:
            TextSelection(baseOffset: edit.start, extentOffset: edit.end));
    setState(() {});
  }

  int get start =>
      body.selection.isValid ? body.selection.start : body.text.length;
  int get end => body.selection.isValid ? body.selection.end : body.text.length;

  Future<void> addImage() async {
    final client = textCardClient(widget.manager);
    if (client == null) return;
    final picked = await PickerUtils.pickImage();
    if (picked == null || !mounted) return;
    setState(() => uploading = true);
    try {
      final bytes = await picked.readAsBytes();
      final uri = await client.matrixClient.uploadContent(bytes,
          filename: picked.name, contentType: picked.mimeType);
      final alt = picked.name.replaceAll(RegExp(r"[\[\]]"), "");
      apply(
          insertSnippet(body.text, start, end, "![$alt]($uri)", ownLine: true));
    } catch (e, s) {
      if (mounted) await AdaptiveDialog.showError(context, e, s);
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  bool get valid =>
      title.text.trim().isNotEmpty &&
      body.text.length <= maxTextBody &&
      buttons.every((b) => b.valid);

  HomeCard get result => widget.card
      .copyWith(name: title.text.trim(), body: body.text, buttons: buttons);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final client = textCardClient(widget.manager);
    TextStyle heading() => TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w800,
        color: scheme.onSurfaceVariant);
    Widget tool(String key, IconData icon, String tip, VoidCallback onTap) =>
        IconButton(
          key: ValueKey("NewHomeTextTool-$key"),
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          icon: Icon(icon, size: 20),
          onPressed: preview ? null : onTap,
        );
    return Dialog(
      backgroundColor: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 820),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(spacing: 10, children: [
                const CardIcon(HomeLayout.textCard, size: 28),
                Expanded(
                    child: Text(
                        widget.editing ? "Edit text card" : "Add a text card",
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800))),
                IconButton(
                    tooltip: "Close",
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop()),
              ]),
              const SizedBox(height: 8),
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  TextField(
                    key: const ValueKey("NewHomeTextTitle"),
                    controller: title,
                    maxLength: 80,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                        labelText: "Title",
                        counterText: "",
                        border: OutlineInputBorder(),
                        isDense: true),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        tool(
                            "bold",
                            Icons.format_bold_rounded,
                            "Bold",
                            () => apply(
                                wrapSelection(body.text, start, end, "**"))),
                        tool(
                            "italic",
                            Icons.format_italic_rounded,
                            "Italic",
                            () => apply(
                                wrapSelection(body.text, start, end, "_"))),
                        tool(
                            "heading",
                            Icons.title_rounded,
                            "Heading",
                            () => apply(
                                prefixLines(body.text, start, end, "## "))),
                        tool(
                            "list",
                            Icons.format_list_bulleted_rounded,
                            "List",
                            () => apply(
                                prefixLines(body.text, start, end, "- "))),
                        tool(
                            "numbered",
                            Icons.format_list_numbered_rounded,
                            "Numbered list",
                            () => apply(prefixLines(body.text, start, end, "",
                                numbered: true))),
                        tool("link", Icons.link_rounded, "Link", () {
                          final s = start, e = end;
                          final text = body.text.substring(s, e);
                          apply(insertSnippet(body.text, s, e,
                              "[${text.isEmpty ? "link text" : text}](https://)"));
                        }),
                        uploading
                            ? const Padding(
                                padding: EdgeInsets.all(10),
                                child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2)))
                            : tool("image", Icons.image_outlined, "Image",
                                addImage),
                        const SizedBox(width: 8),
                        FilterChip(
                          mouseCursor: WidgetStateMouseCursor.clickable,
                          key: const ValueKey("NewHomeTextPreview"),
                          label: const Text("Preview"),
                          selected: preview,
                          onSelected: (v) => setState(() => preview = v),
                        ),
                      ]),
                  const SizedBox(height: 6),
                  if (preview && client != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          border: Border.all(color: scheme.outlineVariant),
                          borderRadius: BorderRadius.circular(6)),
                      child: TextCardContent(body: body.text, client: client),
                    )
                  else
                    TextField(
                      key: const ValueKey("NewHomeTextBody"),
                      controller: body,
                      minLines: 8,
                      maxLines: 16,
                      maxLength: maxTextBody,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(
                          fontFamily: "monospace", fontSize: 13),
                      decoration: const InputDecoration(
                          hintText: "Write here. Markdown works, like in "
                              "messages: **bold**, _italic_, ## headings, "
                              "- lists, [links](https://example.org).",
                          border: OutlineInputBorder()),
                    ),
                  const SizedBox(height: 12),
                  Text("BUTTONS (OPTIONAL, UP TO $maxTextButtons)",
                      style: heading()),
                  const SizedBox(height: 6),
                  for (final (i, b) in buttons.indexed)
                    _ButtonRow(
                      key: ValueKey("NewHomeTextButtonRow-$i"),
                      button: b,
                      manager: widget.manager,
                      onChanged: (next) => setState(() => buttons[i] = next),
                      onRemove: () => setState(() => buttons.removeAt(i)),
                    ),
                  if (buttons.length < maxTextButtons)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        key: const ValueKey("NewHomeTextAddButton"),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text("Add a button"),
                        onPressed: () => setState(() => buttons.add(
                            const TextButtonTarget("",
                                kind: TextButtonTarget.link, target: ""))),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 8,
                      children: [
                        Icon(Icons.info_outline_rounded,
                            size: 16, color: scheme.onSurfaceVariant),
                        Expanded(
                          child: Text(
                              "Images are uploaded to your homeserver without "
                              "encryption, like a room avatar. Anyone with the "
                              "link can see them.",
                              style: TextStyle(
                                  fontSize: 12.5,
                                  color: scheme.onSurfaceVariant)),
                        ),
                      ]),
                ]),
              ),
              const SizedBox(height: 14),
              Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  spacing: 8,
                  children: [
                    TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text("Cancel")),
                    FilledButton(
                      key: const ValueKey("NewHomeTextSave"),
                      onPressed: valid && !uploading
                          ? () => Navigator.of(context).pop(result)
                          : null,
                      child: Text(widget.editing ? "Save" : "Add card"),
                    ),
                  ]),
            ],
          ),
        ),
      ),
    );
  }
}

/// One button in the editor: label, what it opens, and its target.
class _ButtonRow extends StatelessWidget {
  const _ButtonRow(
      {super.key,
      required this.button,
      required this.manager,
      required this.onChanged,
      required this.onRemove});
  final TextButtonTarget button;
  final ClientManager manager;
  final ValueChanged<TextButtonTarget> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final target = switch (button.kind) {
      TextButtonTarget.screen => DropdownButton<String>(
          mouseCursor: WidgetStateMouseCursor.clickable,
          dropdownMenuItemMouseCursor: WidgetStateMouseCursor.clickable,
          key: const ValueKey("NewHomeTextButtonScreen"),
          isExpanded: true,
          hint: const Text("Pick a screen"),
          value: TextButtonTarget.screens.containsKey(button.target)
              ? button.target
              : null,
          items: [
            for (final e in TextButtonTarget.screens.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: (v) => onChanged(button.copyWith(target: v ?? "")),
        ),
      _ => TextFormField(
          key: ValueKey("NewHomeTextButtonTarget-${button.kind}"),
          initialValue: button.target,
          onChanged: (v) => onChanged(button.copyWith(target: v)),
          decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              hintText: button.kind == TextButtonTarget.room
                  ? "#room:example.org"
                  : "https://example.org"),
        ),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(spacing: 8, children: [
        Expanded(
          flex: 3,
          child: TextFormField(
            key: const ValueKey("NewHomeTextButtonLabel"),
            initialValue: button.label,
            maxLength: 40,
            onChanged: (v) => onChanged(button.copyWith(label: v)),
            decoration: const InputDecoration(
                isDense: true,
                counterText: "",
                border: OutlineInputBorder(),
                hintText: "Label"),
          ),
        ),
        DropdownButton<String>(
          mouseCursor: WidgetStateMouseCursor.clickable,
          dropdownMenuItemMouseCursor: WidgetStateMouseCursor.clickable,
          key: const ValueKey("NewHomeTextButtonKind"),
          value: button.kind,
          items: const [
            DropdownMenuItem(value: TextButtonTarget.link, child: Text("Link")),
            DropdownMenuItem(value: TextButtonTarget.room, child: Text("Room")),
            DropdownMenuItem(
                value: TextButtonTarget.screen, child: Text("Vommet screen")),
          ],
          onChanged: (v) => onChanged(button.copyWith(kind: v, target: "")),
        ),
        Expanded(flex: 4, child: target),
        IconButton(
            tooltip: "Remove button",
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: onRemove),
      ]),
    );
  }
}
