import 'package:flutter/material.dart';

/// The modal viewer needs its own snackbar surface: feedback and Undo on
/// the chat's scaffold would be covered by the viewer and its barrier.
class LightboxFeedback extends StatelessWidget {
  const LightboxFeedback({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) => ScaffoldMessenger(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          resizeToAvoidBottomInset: false,
          body: child,
        ),
      );
}
