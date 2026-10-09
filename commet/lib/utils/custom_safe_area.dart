import 'dart:async';

import 'package:commet/main.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/material.dart';

class CustomSafeArea extends StatefulWidget {
  const CustomSafeArea({required this.child, super.key});
  final Widget child;

  @override
  State<CustomSafeArea> createState() => _CustomSafeAreaState();
}

class _CustomSafeAreaState extends State<CustomSafeArea> {
  bool isTextFieldFocused = false;
  // Vommet: keep the subscription and cancel it, or the bus calls setState on
  // a disposed state (and keeps it alive) after the widget leaves the tree.
  StreamSubscription<bool>? focusSubscription;

  @override
  void initState() {
    focusSubscription =
        EventBus.onTextFieldFocused.stream.listen(onTextFieldFocused);
    super.initState();
  }

  @override
  void dispose() {
    focusSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (preferences.customOnscreenKeyboardViewOffset.value == 0) {
      return widget.child;
    }

    var query = MediaQuery.of(context);

    return MediaQuery(
        data: query.copyWith(
            viewPadding: EdgeInsets.fromLTRB(
                0,
                0,
                0,
                isTextFieldFocused
                    ? preferences.customOnscreenKeyboardViewOffset.value
                    : 0)),
        child: widget.child);
  }

  void onTextFieldFocused(bool event) {
    if (event != isTextFieldFocused) {
      setState(() {
        isTextFieldFocused = event;
      });
    }
  }
}
