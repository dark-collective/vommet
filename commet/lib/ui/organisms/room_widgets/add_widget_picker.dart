// Vommet: "Add a widget": the catalog from vommet.app (bundled), a field for
// any other widget's address, and a link to "What are widgets?".
import 'package:commet/client/room.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/organisms/add_widget_dialog/add_widget_dialog.dart';
import 'package:commet/ui/organisms/room_widgets/widget_catalog.dart';
import 'package:commet/utils/custom_uri.dart';
import 'package:commet/utils/links/link_utils.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class AddWidgetPicker {
  static Future<void> show(BuildContext context, Room room) {
    return AdaptiveDialog.show(context,
        title: "Add a widget",
        builder: (dialogContext) => AddWidgetPickerView(
              onPick: (uri, {iconAsset}) async {
                Navigator.of(dialogContext).pop();
                await AdaptiveDialog.show(context,
                    title: 'Add "${uri.widgetName ?? "Custom"}"?',
                    builder: (_) => AddWidgetDialog(
                        widgetUri: uri, room: room, iconAsset: iconAsset));
              },
              onOpenLink: (url) =>
                  LinkUtils.open(Uri.parse(url), context: context),
            ));
  }
}

class AddWidgetPickerView extends StatefulWidget {
  const AddWidgetPickerView(
      {required this.onPick,
      required this.onOpenLink,
      this.catalog,
      super.key});

  final void Function(AddWidgetURI uri, {String? iconAsset}) onPick;
  final void Function(String url) onOpenLink;

  /// For previews and tests; otherwise the bundled catalog is loaded.
  final List<CatalogWidget>? catalog;

  @override
  State<AddWidgetPickerView> createState() => _AddWidgetPickerViewState();
}

class _AddWidgetPickerViewState extends State<AddWidgetPickerView> {
  List<CatalogWidget>? catalog;
  final link = TextEditingController();
  String? linkError;

  @override
  void initState() {
    super.initState();
    catalog = widget.catalog;
    if (catalog == null) {
      WidgetCatalog.load().then((c) {
        if (mounted) setState(() => catalog = c);
      });
    }
  }

  @override
  void dispose() {
    link.dispose();
    super.dispose();
  }

  void pick(CatalogWidget w) {
    widget.onPick(
        AddWidgetURI(
            widgetUrl: w.url,
            widgetName: w.name,
            widgetType: w.type,
            widgetAvatarMxc: w.avatarMxc,
            previewMxc: w.previewMxc),
        iconAsset: w.avatarMxc == null ? w.iconAsset : null);
  }

  void addLink() {
    final text = link.text.trim();
    final custom = CustomURI.parse(text);
    if (custom is AddWidgetURI) {
      widget.onPick(custom);
      return;
    }
    final uri = Uri.tryParse(text);
    if (uri == null || uri.scheme != "https" || uri.host.isEmpty) {
      setState(() =>
          linkError = "Paste the widget's address, starting with https://");
      return;
    }
    widget.onPick(AddWidgetURI(widgetUrl: text, widgetName: uri.host));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    return SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          tiamat.Text.labelLow(
              "Little apps for this room, like games and whiteboards. "
              "Everyone here will be able to open the one you add."),
          const SizedBox(height: 10),
          if (catalog == null)
            const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()))
          else
            for (final w in catalog!)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Material(
                  color: scheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(12),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => pick(w),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(spacing: 12, children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                              color: w.tint,
                              borderRadius: BorderRadius.circular(12)),
                          alignment: Alignment.center,
                          child: w.buildIcon(),
                        ),
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(spacing: 6, children: [
                                  Flexible(child: tiamat.Text.label(w.name)),
                                  if (w.tags.contains("new"))
                                    _Badge("New", scheme.primary,
                                        scheme.onPrimary),
                                  if (w.tags.contains("alpha"))
                                    _Badge(
                                        "Alpha",
                                        scheme.surfaceContainerHighest,
                                        scheme.onSurfaceVariant),
                                ]),
                                tiamat.Text.labelLow(
                                    "by ${w.by} · ${w.summary}",
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis),
                              ]),
                        ),
                        Icon(Icons.add_circle_outline, color: scheme.primary),
                      ]),
                    ),
                  ),
                ),
              ),
          const SizedBox(height: 14),
          tiamat.Text.label("Got a link to another widget?"),
          const SizedBox(height: 6),
          Row(spacing: 8, children: [
            Expanded(
              child: tiamat.TextInput(
                placeholder: "https://…",
                controller: link,
                onSubmitted: (_) => addLink(),
              ),
            ),
            tiamat.Button.secondary(text: "Add", onTap: addLink),
          ]),
          if (linkError != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: tiamat.Text.error(linkError!),
            ),
          const SizedBox(height: 10),
          Wrap(spacing: 4, children: [
            TextButton.icon(
                onPressed: () => widget.onOpenLink(WidgetCatalog.helpUrl),
                icon: const Icon(Icons.help_outline, size: 18),
                label: const Text("What are widgets?")),
            TextButton.icon(
                onPressed: () => widget.onOpenLink(WidgetCatalog.browseUrl),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text("More on vommet.app")),
          ]),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, this.bg, this.fg);
  final String text;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
        child: Text(text,
            style: TextStyle(
                color: fg, fontSize: 11, fontWeight: FontWeight.w700)),
      );
}
