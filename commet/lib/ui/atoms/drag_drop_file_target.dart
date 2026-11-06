import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class DragDropFileTarget extends StatefulWidget {
  const DragDropFileTarget({super.key, this.onDropComplete});
  final Function(DropDoneDetails details)? onDropComplete;

  /// Vommet issue 1066: files are being dragged over the window (the
  /// desktop tray shows where they will land).
  static final ValueNotifier<bool> filesHovering = ValueNotifier(false);
  @override
  State<DragDropFileTarget> createState() => _DragDropFileTargetState();
}

class _DragDropFileTargetState extends State<DragDropFileTarget> {
  bool isFileHovered = false;

  String get fileDragDropPrompt => Intl.message("Drop a file to upload...",
      name: "fileDragDropPrompt",
      desc: "Text that is shown when a user is dragging a file");

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DropTarget(
          onDragEntered: (ev) {
            print(ev);
            setState(() {
              isFileHovered = true;
            });
            DragDropFileTarget.filesHovering.value = true;
          },
          onDragExited: (_) {
            setState(() {
              isFileHovered = false;
            });
            DragDropFileTarget.filesHovering.value = false;
          },
          onDragDone: (detail) {
            DragDropFileTarget.filesHovering.value = false;
            widget.onDropComplete?.call(detail);
          },
          child: Stack(
            children: [
              AnimatedOpacity(
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutExpo,
                opacity: isFileHovered ? 0.5 : 0,
                child: Container(color: Colors.black),
              ),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutExpo,
                opacity: isFileHovered ? 1 : 0,
                child: Align(
                    alignment: Alignment.center,
                    child: tiamat.Text.largeTitle(fileDragDropPrompt)),
              ),
            ],
          )),
    );
  }
}
