import 'package:commet/utils/primary_selection.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Vommet: Linux primary selection for a text field. Text selected in it goes
/// to the primary selection, and a middle-click pastes the primary selection
/// where the pointer is, as in other Linux apps. Elsewhere it only returns
/// [child].
class PrimarySelectionField extends StatefulWidget {
  const PrimarySelectionField(
      {required this.controller,
      required this.child,
      this.enabled = true,
      this.onChanged,
      super.key});

  final TextEditingController controller;
  final Widget child;

  /// False while the field is read-only: nothing gets pasted then.
  final bool enabled;

  /// Called with the new text after a middle-click paste, like
  /// TextField.onChanged (which doesn't fire for programmatic edits).
  final ValueChanged<String>? onChanged;

  /// [value] with [pasted] inserted at [offset], and the cursor after it.
  static TextEditingValue insert(
      TextEditingValue value, int offset, String pasted) {
    final text = value.text;
    final at = offset.clamp(0, text.length);
    return TextEditingValue(
      text: text.replaceRange(at, at, pasted),
      selection: TextSelection.collapsed(offset: at + pasted.length),
    );
  }

  @override
  State<PrimarySelectionField> createState() => _PrimarySelectionFieldState();
}

class _PrimarySelectionFieldState extends State<PrimarySelectionField> {
  @override
  void initState() {
    super.initState();
    if (PrimarySelection.supported) {
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void didUpdateWidget(covariant PrimarySelectionField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (PrimarySelection.supported &&
        oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    final value = widget.controller.value;
    final selection = value.selection;
    if (!selection.isValid || selection.isCollapsed) return;
    if (selection.end > value.text.length) return;
    PrimarySelection.set(selection.textInside(value.text));
  }

  RenderEditable? _findEditable() {
    RenderEditable? found;
    void visit(RenderObject child) {
      if (found != null) return;
      if (child is RenderEditable) {
        found = child;
        return;
      }
      child.visitChildren(visit);
    }

    final root = context.findRenderObject();
    if (root != null) visit(root);
    return found;
  }

  Future<void> _onPointerDown(PointerDownEvent event) async {
    if (event.buttons != kMiddleMouseButton || !widget.enabled) return;
    final editable = _findEditable();
    final offset = editable?.getPositionForPoint(event.position).offset ??
        widget.controller.selection.baseOffset;

    final pasted = await PrimarySelection.read();
    if (pasted == null || pasted.isEmpty || !mounted) return;

    widget.controller.value =
        PrimarySelectionField.insert(widget.controller.value, offset, pasted);
    widget.onChanged?.call(widget.controller.text);
  }

  @override
  Widget build(BuildContext context) {
    if (!PrimarySelection.supported) return widget.child;
    return Listener(onPointerDown: _onPointerDown, child: widget.child);
  }
}
