import 'dart:async';

import 'package:commet/config/build_config.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/composer_formatting/format_actions.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet issue 54: formatting for the message composer.
///
/// - Desktop: a small bar floats above selected text (Discord style), and
///   keyboard shortcuts work with or without it.
/// - Phone: the selection menu gains a Format item, and an Aa button next
///   to the emoji button opens a row of format buttons above the composer.
/// - Pasting a URL over selected text turns the selection into a link.
///
/// It attaches to the composer's controller and focus node instead of
/// wrapping the text field, so the composer needs only a few hook calls.
class ComposerFormatting {
  ComposerFormatting({required this.controller, required this.focusNode}) {
    _last = controller.value;
    controller.addListener(_onChanged);
    focusNode.addListener(_onFocusChanged);
  }

  final TextEditingController controller;
  final FocusNode focusNode;

  final LayerLink _toggleLink = LayerLink();
  final GlobalKey _toggleKey = GlobalKey();
  final ValueNotifier<bool> _stripOpen = ValueNotifier(false);
  final ValueNotifier<int> _revision = ValueNotifier(0);

  OverlayEntry? _popup;
  OverlayEntry? _strip;
  Timer? _popupDelay;
  late TextEditingValue _last;
  bool _applying = false;

  static String get labelBold => Intl.message("Bold",
      name: "labelFormatBold", desc: "Composer formatting button: bold");
  static String get labelItalic => Intl.message("Italic",
      name: "labelFormatItalic", desc: "Composer formatting button: italic");
  static String get labelUnderline => Intl.message("Underline",
      name: "labelFormatUnderline",
      desc: "Composer formatting button: underline");
  static String get labelStrike => Intl.message("Strikethrough",
      name: "labelFormatStrike",
      desc: "Composer formatting button: strikethrough");
  static String get labelSpoiler => Intl.message("Spoiler",
      name: "labelFormatSpoiler", desc: "Composer formatting button: spoiler");
  static String get labelCode => Intl.message("Code",
      name: "labelFormatCode", desc: "Composer formatting button: code");
  static String get labelQuote => Intl.message("Quote",
      name: "labelFormatQuote", desc: "Composer formatting button: quote");
  static String get labelLink => Intl.message("Link",
      name: "labelFormatLink", desc: "Composer formatting button: link");
  static String get labelFormat => Intl.message("Format",
      name: "labelFormatMenu",
      desc: "Item in the text selection menu that shows formatting buttons");
  static String get labelFormattingButtons => Intl.message("Formatting",
      name: "labelFormattingButtons",
      desc: "Tooltip for the composer button that shows formatting buttons");
  static String get labelLinkText => Intl.message("Text",
      name: "labelFormatLinkText", desc: "Link dialog: the link's text");
  static String get labelLinkUrl => Intl.message("Link",
      name: "labelFormatLinkUrl", desc: "Link dialog: the URL");
  static String get labelAddLink => Intl.message("Add link",
      name: "labelFormatAddLink", desc: "Link dialog: confirm button");

  static final List<(ComposerFormat, IconData)> buttons = [
    (ComposerFormat.bold, Icons.format_bold),
    (ComposerFormat.italic, Icons.format_italic),
    (ComposerFormat.underline, Icons.format_underlined),
    (ComposerFormat.strike, Icons.format_strikethrough),
    (ComposerFormat.spoiler, Icons.visibility_off),
    (ComposerFormat.code, Icons.code),
    (ComposerFormat.quote, Icons.format_quote),
    (ComposerFormat.link, Icons.link),
  ];

  /// Buttons followed by a divider in the desktop bar.
  static const _groupEnds = {ComposerFormat.strike, ComposerFormat.quote};

  static String label(ComposerFormat f) => switch (f) {
        ComposerFormat.bold => labelBold,
        ComposerFormat.italic => labelItalic,
        ComposerFormat.underline => labelUnderline,
        ComposerFormat.strike => labelStrike,
        ComposerFormat.spoiler => labelSpoiler,
        ComposerFormat.code => labelCode,
        ComposerFormat.quote => labelQuote,
        ComposerFormat.link => labelLink,
      };

  static String? shortcut(ComposerFormat f) {
    var mod = _isMac ? "⌘" : "Ctrl+";
    return switch (f) {
      ComposerFormat.bold => "${mod}B",
      ComposerFormat.italic => "${mod}I",
      ComposerFormat.underline => "${mod}U",
      ComposerFormat.strike => "${mod}Shift+X",
      ComposerFormat.spoiler => "${mod}Shift+S",
      ComposerFormat.code => "${mod}E",
      ComposerFormat.quote => "${mod}Shift+.",
      ComposerFormat.link => null,
    };
  }

  static bool get _isMac => defaultTargetPlatform == TargetPlatform.macOS;

  bool get _popupEnabled =>
      !BuildConfig.MOBILE && preferences.formattingPopup.value;

  void dispose() {
    _popupDelay?.cancel();
    _hidePopup();
    _hideStrip();
    controller.removeListener(_onChanged);
    focusNode.removeListener(_onFocusChanged);
    _stripOpen.dispose();
    _revision.dispose();
  }

  void apply(ComposerFormat format, BuildContext context) {
    if (format == ComposerFormat.link) {
      // The bar or menu that was pressed may close; open the dialog from
      // the composer instead.
      var composer = focusNode.context;
      _openLinkDialog(
          composer != null && composer.mounted ? composer : context);
      return;
    }
    _set(toggleFormat(controller.value, format));
  }

  void _set(TextEditingValue value) {
    _applying = true;
    controller.value = value;
    _applying = false;
    _last = value;
  }

  void _onChanged() {
    var value = controller.value;
    if (!_applying) {
      var link = linkFromPaste(_last, value);
      if (link != null) {
        _set(link);
        value = link;
      }
    }
    _last = value;
    _revision.value++;
    _schedulePopup();
  }

  void _onFocusChanged() {
    if (!focusNode.hasFocus) {
      _popupDelay?.cancel();
      _hidePopup();
    } else {
      _schedulePopup();
    }
  }

  /// Handles the formatting shortcuts. Returns true when [event] was one.
  bool handleKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    var keyboard = HardwareKeyboard.instance;
    var modifier = _isMac ? keyboard.isMetaPressed : keyboard.isControlPressed;

    if (event.logicalKey == LogicalKeyboardKey.escape && _popup != null) {
      _hidePopup();
      return true;
    }
    if (!modifier || keyboard.isAltPressed) return false;

    var shift = keyboard.isShiftPressed;
    var key = event.logicalKey;
    ComposerFormat? format;
    if (!shift && key == LogicalKeyboardKey.keyB) format = ComposerFormat.bold;
    if (!shift && key == LogicalKeyboardKey.keyI)
      format = ComposerFormat.italic;
    if (!shift && key == LogicalKeyboardKey.keyU) {
      format = ComposerFormat.underline;
    }
    if (!shift && key == LogicalKeyboardKey.keyE) format = ComposerFormat.code;
    if (shift && key == LogicalKeyboardKey.keyX) format = ComposerFormat.strike;
    if (shift && key == LogicalKeyboardKey.keyS)
      format = ComposerFormat.spoiler;
    if (shift &&
        (key == LogicalKeyboardKey.period ||
            key == LogicalKeyboardKey.greater)) {
      format = ComposerFormat.quote;
    }
    if (format == null) return false;

    _set(toggleFormat(controller.value, format));
    return true;
  }

  // ---- Desktop: floating bar above the selection ----

  void _schedulePopup() {
    if (!_popupEnabled) return;
    var sel = controller.selection;
    if (!focusNode.hasFocus || !sel.isValid || sel.isCollapsed) {
      _popupDelay?.cancel();
      _hidePopup();
      return;
    }
    if (_popup != null) {
      _popup!.markNeedsBuild();
      return;
    }
    // Wait for a mouse drag to settle before showing the bar.
    _popupDelay?.cancel();
    _popupDelay = Timer(const Duration(milliseconds: 180), _showPopup);
  }

  EditableTextState? get _editable =>
      focusNode.context?.findAncestorStateOfType<EditableTextState>();

  void _showPopup() {
    var context = focusNode.context;
    if (context == null || !context.mounted || _popup != null) return;
    var sel = controller.selection;
    if (!focusNode.hasFocus || !sel.isValid || sel.isCollapsed) return;
    var overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    _popup = OverlayEntry(builder: (overlayContext) {
      var anchor = _selectionAnchor(overlay);
      if (anchor == null) return const SizedBox.shrink();
      return CustomSingleChildLayout(
        delegate: _AboveSelectionLayout(anchor),
        child: TextFieldTapRegion(
          child: ValueListenableBuilder(
            valueListenable: _revision,
            builder: (context, _, __) => _DesktopFormatBar(
              value: controller.value,
              onPressed: (f) => apply(f, overlayContext),
            ),
          ),
        ),
      );
    });
    overlay.insert(_popup!);
  }

  /// Top-left of the selection's first line, in the overlay's coordinates.
  Offset? _selectionAnchor(OverlayState overlay) {
    var editable = _editable;
    var overlayBox = overlay.context.findRenderObject() as RenderBox?;
    if (editable == null || overlayBox == null) return null;
    var render = editable.renderEditable;
    if (!render.attached) return null;
    var boxes = render.getBoxesForSelection(controller.selection);
    if (boxes.isEmpty) return null;
    var top = boxes.map((b) => b.top).reduce((a, b) => a < b ? a : b);
    var first = boxes.firstWhere((b) => b.top == top);
    var global = render.localToGlobal(Offset(first.left, top));
    return overlayBox.globalToLocal(global);
  }

  void _hidePopup() {
    _popup?.remove();
    _popup = null;
  }

  // ---- Phone: Format item in the selection menu ----

  /// The selection menu with a Format item, on touch platforms when text is
  /// selected; null otherwise so the composer builds its usual menu.
  Widget? mobileContextMenu(EditableTextState state) {
    if (!BuildConfig.MOBILE) return null;
    var sel = state.textEditingValue.selection;
    if (!sel.isValid || sel.isCollapsed) return null;
    var items = state.contextMenuButtonItems
        .where((i) =>
            i.type != ContextMenuButtonType.liveTextInput &&
            i.type != ContextMenuButtonType.lookUp &&
            i.type != ContextMenuButtonType.searchWeb &&
            i.type != ContextMenuButtonType.share)
        .toList();
    return _MobileSelectionMenu(
      anchors: state.contextMenuAnchors,
      items: items,
      formatting: this,
    );
  }

  // ---- Phone: Aa button and format row ----

  /// [emojiButton] with the Aa button in front of it (phone layout).
  Widget mobileToggle(BuildContext context, Widget emojiButton) {
    if (!preferences.formattingPopup.value) return emojiButton;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      CompositedTransformTarget(
        link: _toggleLink,
        child: ValueListenableBuilder(
          valueListenable: _stripOpen,
          builder: (context, open, _) => SizedBox(
            key: _toggleKey,
            width: 36,
            height: 36,
            child: tiamat.IconButton(
              icon: Icons.text_format,
              size: 22,
              iconColor: open ? Theme.of(context).colorScheme.primary : null,
              onPressed: () => _toggleStrip(context),
            ),
          ),
        ),
      ),
      emojiButton,
    ]);
  }

  void _toggleStrip(BuildContext context) {
    if (_strip != null) {
      _hideStrip();
      return;
    }
    var overlay = Overlay.maybeOf(context, rootOverlay: true);
    var toggleBox = _toggleKey.currentContext?.findRenderObject() as RenderBox?;
    if (overlay == null || toggleBox == null) return;
    var left = toggleBox.localToGlobal(Offset.zero).dx;

    _strip = OverlayEntry(builder: (overlayContext) {
      var width = MediaQuery.of(overlayContext).size.width - 16;
      return Positioned(
        width: width,
        child: CompositedTransformFollower(
          link: _toggleLink,
          showWhenUnlinked: false,
          targetAnchor: Alignment.topLeft,
          followerAnchor: Alignment.bottomLeft,
          offset: Offset(8 - left, -6),
          child: TextFieldTapRegion(
            child: ValueListenableBuilder(
              valueListenable: _revision,
              builder: (context, _, __) => _MobileFormatRow(
                value: controller.value,
                onPressed: (f) => apply(f, overlayContext),
              ),
            ),
          ),
        ),
      );
    });
    overlay.insert(_strip!);
    _stripOpen.value = true;
  }

  void _hideStrip() {
    _strip?.remove();
    _strip = null;
    _stripOpen.value = false;
  }

  // ---- Link dialog ----

  Future<void> _openLinkDialog(BuildContext context) async {
    var before = controller.value;
    var sel = before.selection;
    var selected = sel.isValid ? before.text.substring(sel.start, sel.end) : "";
    var isUrl = looksLikeUrl(selected);

    var result = await AdaptiveDialog.show<(String, String)>(
      context,
      title: labelLink,
      builder: (context) => _LinkDialog(
        initialText: isUrl ? "" : selected,
        initialUrl: isUrl ? selected.trim() : "",
      ),
    );
    if (result == null) return;
    var (text, url) = result;
    if (url.trim().isEmpty) return;
    _set(insertLink(controller.value.copyWith(selection: sel), text, url));
    focusNode.requestFocus();
  }
}

class _AboveSelectionLayout extends SingleChildLayoutDelegate {
  _AboveSelectionLayout(this.anchor);
  final Offset anchor;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    var x = (anchor.dx - 12).clamp(8.0, size.width - childSize.width - 8);
    var y = anchor.dy - childSize.height - 8;
    if (y < 8) y = 8;
    return Offset(x.toDouble(), y);
  }

  @override
  bool shouldRelayout(_AboveSelectionLayout old) => old.anchor != anchor;
}

class _DesktopFormatBar extends StatelessWidget {
  const _DesktopFormatBar({required this.value, required this.onPressed});
  final TextEditingValue value;
  final void Function(ComposerFormat) onPressed;

  @override
  Widget build(BuildContext context) {
    var scheme = Theme.of(context).colorScheme;
    var children = <Widget>[];
    for (var (format, icon) in ComposerFormatting.buttons) {
      var active = isFormatActive(value, format);
      var shortcut = ComposerFormatting.shortcut(format);
      children.add(Tooltip(
        message: shortcut == null
            ? ComposerFormatting.label(format)
            : "${ComposerFormatting.label(format)}  $shortcut",
        waitDuration: const Duration(milliseconds: 300),
        child: _BarButton(
          icon: icon,
          active: active,
          onPressed: () => onPressed(format),
        ),
      ));
      if (ComposerFormatting._groupEnds.contains(format)) {
        children.add(Container(
            width: 1,
            height: 20,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            color: scheme.outlineVariant));
      }
    }
    return Material(
      color: scheme.surfaceContainerHighest,
      elevation: 6,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}

class _BarButton extends StatefulWidget {
  const _BarButton(
      {required this.icon,
      required this.active,
      required this.onPressed,
      this.size = 30});
  final IconData icon;
  final bool active;
  final VoidCallback onPressed;
  final double size;

  @override
  State<_BarButton> createState() => _BarButtonState();
}

class _BarButtonState extends State<_BarButton> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    var scheme = Theme.of(context).colorScheme;
    // A plain gesture detector, not a focusable button, so pressing it
    // leaves keyboard focus (and the selection) in the composer.
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
              color: widget.active
                  ? scheme.primary.withAlpha(60)
                  : hovered
                      ? scheme.onSurface.withAlpha(25)
                      : null,
              borderRadius: BorderRadius.circular(5)),
          child: Icon(widget.icon,
              size: widget.size * 0.63,
              color: widget.active ? scheme.primary : scheme.onSurface),
        ),
      ),
    );
  }
}

class _MobileFormatRow extends StatelessWidget {
  const _MobileFormatRow({required this.value, required this.onPressed});
  final TextEditingValue value;
  final void Function(ComposerFormat) onPressed;

  @override
  Widget build(BuildContext context) {
    var scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      elevation: 4,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var (format, icon) in ComposerFormatting.buttons)
              Semantics(
                button: true,
                label: ComposerFormatting.label(format),
                child: _BarButton(
                  icon: icon,
                  size: 38,
                  active: isFormatActive(value, format),
                  onPressed: () => onPressed(format),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MobileSelectionMenu extends StatefulWidget {
  const _MobileSelectionMenu(
      {required this.anchors, required this.items, required this.formatting});
  final TextSelectionToolbarAnchors anchors;
  final List<ContextMenuButtonItem> items;
  final ComposerFormatting formatting;

  @override
  State<_MobileSelectionMenu> createState() => _MobileSelectionMenuState();
}

class _MobileSelectionMenuState extends State<_MobileSelectionMenu> {
  bool formatting = false;

  @override
  Widget build(BuildContext context) {
    if (!formatting) {
      return AdaptiveTextSelectionToolbar.buttonItems(
        anchors: widget.anchors,
        buttonItems: [
          ...widget.items,
          ContextMenuButtonItem(
            label: ComposerFormatting.labelFormat,
            onPressed: () => setState(() => formatting = true),
          ),
        ],
      );
    }

    var scheme = Theme.of(context).colorScheme;
    Widget button(IconData icon, String label, VoidCallback onPressed) =>
        IconButton(
          tooltip: label,
          visualDensity: VisualDensity.compact,
          icon: Icon(icon, size: 21, color: scheme.onSurface),
          onPressed: onPressed,
        );

    return AdaptiveTextSelectionToolbar(
      anchors: widget.anchors,
      children: [
        button(
            Icons.arrow_back,
            MaterialLocalizations.of(context).backButtonTooltip,
            () => setState(() => formatting = false)),
        for (var (format, icon) in ComposerFormatting.buttons)
          button(icon, ComposerFormatting.label(format),
              () => widget.formatting.apply(format, context)),
      ],
    );
  }
}

class _LinkDialog extends StatefulWidget {
  const _LinkDialog({required this.initialText, required this.initialUrl});
  final String initialText;
  final String initialUrl;

  @override
  State<_LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<_LinkDialog> {
  late final TextEditingController text =
      TextEditingController(text: widget.initialText);
  late final TextEditingController url =
      TextEditingController(text: widget.initialUrl);

  @override
  void dispose() {
    text.dispose();
    url.dispose();
    super.dispose();
  }

  void submit() => Navigator.of(context).pop((text.text, url.text));

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: text,
            autofocus: widget.initialText.isEmpty,
            decoration:
                InputDecoration(labelText: ComposerFormatting.labelLinkText),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: url,
            autofocus: widget.initialText.isNotEmpty,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration:
                InputDecoration(labelText: ComposerFormatting.labelLinkUrl),
            onSubmitted: (_) => submit(),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: tiamat.Button(
              text: ComposerFormatting.labelAddLink,
              onTap: submit,
            ),
          ),
        ],
      ),
    );
  }
}
