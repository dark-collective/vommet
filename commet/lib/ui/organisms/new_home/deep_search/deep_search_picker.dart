// Vommet (Deep Search follow-ups): the in: / from: pickers. The same
// entries (from the ranked name search) show under the field while an
// in: / from: word is typed, and in a popover anchored to the From ▾ /
// In ▾ chip on desktop. A pick adds the token exactly as typing would.
import 'package:commet/ui/organisms/new_home/deep_search/deep_search_entry.dart';
import 'package:commet/ui/organisms/new_home/deep_search/deep_search_query.dart';
import 'package:commet/ui/organisms/new_home/deep_search/deep_search_strings.dart';
import 'package:flutter/material.dart';

/// One row of a picker: the token it adds and how it shows.
class DeepSearchPickerEntry<S> {
  const DeepSearchPickerEntry(
      {required this.token, required this.title, this.subtitle, this.leading});

  final DeepSearchToken<S> token;
  final String title;
  final String? subtitle;
  final Widget? leading;
}

/// The entries for the value typed after `key:` ("in", "from", "has").
typedef DeepSearchPickerSource<S> = List<DeepSearchPickerEntry<S>> Function(
    String value);

/// A picker row, the same under the field and in the popover.
class DeepSearchPickerTile<S> extends StatelessWidget {
  const DeepSearchPickerTile(this.entry, {required this.onTap, super.key});

  final DeepSearchPickerEntry<S> entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final subtitle = entry.subtitle;
    return ListTile(
        dense: true,
        leading: entry.leading,
        title: Text(entry.title),
        subtitle:
            subtitle == null || subtitle.isEmpty || subtitle == entry.title
                ? null
                : Text(subtitle, maxLines: 1),
        onTap: onTap);
  }
}

/// A filter chip of the chips row (Mockup 3); [dropdown] adds the ▾.
class DeepSearchFilterChip extends StatelessWidget {
  const DeepSearchFilterChip(this.label,
      {required this.selected,
      required this.onTap,
      this.dropdown = false,
      super.key});

  final String label;
  final bool selected;
  final bool dropdown;

  /// Gets the chip's own context, to anchor a popover to it.
  final void Function(BuildContext chipContext) onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Semantics(
        button: true,
        selected: selected,
        child: FilterChip(
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          showCheckmark: false,
          selected: selected,
          selectedColor: DeepSearchEntry.color.withAlpha(60),
          label: dropdown
              ? Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(label, style: const TextStyle(fontSize: 13)),
                  const Icon(Icons.arrow_drop_down_rounded, size: 18),
                ])
              : Text(label, style: const TextStyle(fontSize: 13)),
          onSelected: (_) => onTap(context),
        ),
      ),
    );
  }
}

/// From ▾ / In ▾: on desktop a popover anchored to the chip, with a field
/// to narrow the picker; on the phone [onPhoneTap] (it types the key, so
/// the picker shows under the field as when typed).
class DeepSearchPickerChip<S> extends StatelessWidget {
  const DeepSearchPickerChip(this.label,
      {required this.pickerKey,
      required this.entries,
      required this.onPicked,
      required this.selected,
      this.phone = false,
      this.onPhoneTap,
      super.key});

  final String label;

  /// "from" or "in".
  final String pickerKey;
  final DeepSearchPickerSource<S> entries;
  final ValueChanged<DeepSearchToken<S>> onPicked;
  final bool selected;
  final bool phone;
  final VoidCallback? onPhoneTap;

  @override
  Widget build(BuildContext context) {
    return DeepSearchFilterChip(label,
        dropdown: true, selected: selected, onTap: _open);
  }

  Future<void> _open(BuildContext chipContext) async {
    final phoneTap = onPhoneTap;
    if (phone && phoneTap != null) {
      phoneTap();
      return;
    }
    final picked = await showDeepSearchPicker<S>(chipContext,
        entries: entries,
        hint: pickerKey == "from"
            ? DeepSearchStrings.pickerFromHint
            : DeepSearchStrings.pickerInHint);
    if (picked != null) onPicked(picked);
  }
}

/// Opens the picker in a popover under [anchorContext]'s widget. Null when
/// it was closed without a pick.
Future<DeepSearchToken<S>?> showDeepSearchPicker<S>(BuildContext anchorContext,
    {required DeepSearchPickerSource<S> entries, required String hint}) {
  final navigator = Navigator.of(anchorContext);
  final box = anchorContext.findRenderObject();
  final overlay = navigator.overlay?.context.findRenderObject();
  var anchor = Rect.zero;
  if (box is RenderBox && overlay is RenderBox && box.hasSize) {
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    anchor = topLeft & box.size;
  }
  return navigator.push(_DeepSearchPickerRoute<S>(
      anchor: anchor,
      entries: entries,
      hint: hint,
      barrierLabel:
          MaterialLocalizations.of(anchorContext).modalBarrierDismissLabel));
}

class _DeepSearchPickerRoute<S> extends PopupRoute<DeepSearchToken<S>> {
  _DeepSearchPickerRoute(
      {required this.anchor,
      required this.entries,
      required this.hint,
      required this.barrierLabel});

  final Rect anchor;
  final DeepSearchPickerSource<S> entries;
  final String hint;

  @override
  final String barrierLabel;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 120);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation) {
    return CustomSingleChildLayout(
      delegate: _PopoverLayout(anchor, MediaQuery.paddingOf(context)),
      child: FadeTransition(
        opacity: animation,
        child: _DeepSearchPickerPopover<S>(entries: entries, hint: hint),
      ),
    );
  }
}

/// Below the anchor, left-aligned with it; above it when there's no room
/// below; kept inside the screen.
class _PopoverLayout extends SingleChildLayoutDelegate {
  _PopoverLayout(this.anchor, this.padding);

  final Rect anchor;
  final EdgeInsets padding;

  static const width = 320.0;
  static const maxHeight = 360.0;
  static const gap = 4.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final room = constraints.maxHeight - padding.vertical - gap * 2;
    return BoxConstraints(
        maxWidth: (constraints.maxWidth - 16).clamp(0, width),
        maxHeight: room.clamp(0, maxHeight));
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    var x = anchor.left;
    if (x + childSize.width > size.width - 8) {
      x = size.width - 8 - childSize.width;
    }
    if (x < 8) x = 8;
    var y = anchor.bottom + gap;
    final bottom = size.height - padding.bottom;
    if (y + childSize.height > bottom && anchor.top - gap > childSize.height) {
      y = anchor.top - gap - childSize.height;
    } else if (y + childSize.height > bottom) {
      y = bottom - childSize.height;
    }
    if (y < padding.top) y = padding.top;
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_PopoverLayout old) =>
      old.anchor != anchor || old.padding != padding;
}

class _DeepSearchPickerPopover<S> extends StatefulWidget {
  const _DeepSearchPickerPopover({required this.entries, required this.hint});

  final DeepSearchPickerSource<S> entries;
  final String hint;

  @override
  State<_DeepSearchPickerPopover<S>> createState() =>
      _DeepSearchPickerPopoverState<S>();
}

class _DeepSearchPickerPopoverState<S>
    extends State<_DeepSearchPickerPopover<S>> {
  final TextEditingController field = TextEditingController();

  @override
  void dispose() {
    field.dispose();
    super.dispose();
  }

  void _pick(DeepSearchToken<S> token) => Navigator.of(context).pop(token);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final found = widget.entries(field.text);
    return Material(
      elevation: 2,
      color: scheme.surfaceContainer,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.outlineVariant)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: TextField(
              controller: field,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                final first = found.isEmpty ? null : found.first;
                if (first != null) _pick(first.token);
              },
              decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  prefixIconConstraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  border: InputBorder.none,
                  hintText: widget.hint),
            ),
          ),
          const Divider(height: 1),
          if (found.isEmpty && field.text.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(DeepSearchStrings.pickerNoMatches,
                  style:
                      TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                children: [
                  for (final e in found)
                    DeepSearchPickerTile<S>(e, onTap: () => _pick(e.token)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
