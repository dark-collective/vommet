import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: one choice in the forward picker's space filter (Vommet issue 252).
class ForwardPickerChip {
  const ForwardPickerChip(
      {required this.id,
      required this.name,
      this.avatar,
      this.color,
      this.icon});

  final String id;
  final String name;
  final ImageProvider? avatar;
  final Color? color;

  /// Shown instead of an avatar ("All", "Direct messages").
  final IconData? icon;
}

/// Vommet: one row of the forward picker: a room to forward to, or a
/// subspace to open.
class ForwardPickerRow {
  const ForwardPickerRow(
      {required this.title,
      required this.onTap,
      this.subtitle,
      this.avatar,
      this.color,
      this.isSpace = false,
      this.selected,
      this.onLongPress})
      : isHeader = false;

  /// Vommet issue 803: a section label between rows, e.g. "Selected · 2".
  const ForwardPickerRow.header(this.title)
      : onTap = _none,
        subtitle = null,
        avatar = null,
        color = null,
        isSpace = false,
        selected = null,
        onLongPress = null,
        isHeader = true;

  static void _none() {}

  final String title;

  /// Where the room sits, e.g. "Games › Minecraft".
  final String? subtitle;
  final ImageProvider? avatar;
  final Color? color;
  final bool isSpace;
  final VoidCallback onTap;

  /// Vommet issue 803: whether the room is ticked, shown as a tickbox while
  /// several rooms are being picked; null outside that mode.
  final bool? selected;

  /// Vommet issue 803: long-press starts picking several rooms.
  final VoidCallback? onLongPress;
  final bool isHeader;
}

/// Vommet: the forward picker's layout: search, a row of space filters, a
/// breadcrumb while inside a space, and the rooms (Vommet issue 252).
class ForwardPickerView extends StatelessWidget {
  const ForwardPickerView({
    required this.chips,
    required this.selectedChip,
    required this.onChipSelected,
    required this.breadcrumb,
    required this.onBreadcrumbSelected,
    required this.rows,
    required this.emptyText,
    required this.searchHint,
    this.onQueryChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  /// The filters; none hides the filter row.
  final List<ForwardPickerChip> chips;
  final String selectedChip;
  final void Function(String id) onChipSelected;

  /// Names from the chosen top-level space down to the open subspace; empty
  /// unless a subspace is open.
  final List<String> breadcrumb;

  /// Called with the index in [breadcrumb] to go back up to.
  final void Function(int index) onBreadcrumbSelected;

  final List<ForwardPickerRow> rows;
  final String emptyText;
  final String searchHint;
  final void Function(String query)? onQueryChanged;
  final void Function(String query)? onSubmitted;
  final bool autofocus;

  /// Vommet issue 803: a button under the rooms, e.g. "Forward to 3 rooms";
  /// hidden while null.
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: TextField(
            decoration: InputDecoration(
                icon: const Icon(Icons.search), hintText: searchHint),
            maxLines: 1,
            autofocus: autofocus,
            onChanged: onQueryChanged,
            onSubmitted: onSubmitted,
          ),
        ),
        if (chips.isNotEmpty) buildChips(context),
        if (breadcrumb.length > 1) buildBreadcrumb(context),
        Expanded(
          child: rows.isEmpty
              ? Center(child: tiamat.Text.labelLow(emptyText))
              : ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, index) =>
                      buildRow(context, rows[index]),
                ),
        ),
        if (actionLabel != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.send),
                label: Text(actionLabel!),
                onPressed: onAction,
              ),
            ),
          ),
      ],
    );
  }

  Widget buildChips(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final chip = chips[index];
          return Center(
            child: ChoiceChip(
              mouseCursor: WidgetStateMouseCursor.clickable,
              selected: chip.id == selectedChip,
              showCheckmark: false,
              avatar: chip.icon != null
                  ? Icon(chip.icon, size: 18)
                  : tiamat.Avatar(
                      radius: 10,
                      image: chip.avatar,
                      placeholderText: chip.name,
                      placeholderColor: chip.color),
              label: Text(chip.name, overflow: TextOverflow.ellipsis),
              onSelected: (_) => onChipSelected(chip.id),
            ),
          );
        },
      ),
    );
  }

  Widget buildBreadcrumb(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          reverse: true,
          child: Row(
            children: [
              for (var i = 0; i < breadcrumb.length; i++) ...[
                if (i > 0) Icon(Icons.chevron_right, size: 18, color: color),
                TextButton(
                  onPressed: i == breadcrumb.length - 1
                      ? null
                      : () => onBreadcrumbSelected(i),
                  child: Text(breadcrumb[i]),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget buildRow(BuildContext context, ForwardPickerRow row) {
    if (row.isHeader) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
        child: tiamat.Text.labelLow(row.title),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(2.0),
      child: Material(
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(8),
        color: Colors.transparent,
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          onTap: row.onTap,
          onLongPress: row.onLongPress,
          child: Padding(
            padding: const EdgeInsets.all(6.0),
            child: Row(
              children: [
                tiamat.Avatar(
                    image: row.avatar,
                    placeholderText: row.title,
                    placeholderColor: row.color),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      tiamat.Text.label(row.title,
                          overflow: TextOverflow.ellipsis),
                      if (row.subtitle != null)
                        tiamat.Text.tiny(row.subtitle!,
                            overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                if (row.isSpace) const Icon(Icons.chevron_right),
                if (row.selected != null)
                  Checkbox(
                      value: row.selected,
                      onChanged: (_) => row.onTap(),
                      mouseCursor: WidgetStateMouseCursor.clickable),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
