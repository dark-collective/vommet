import 'dart:async';

import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/main.dart';
import 'package:flutter/material.dart';

/// Vommet: push to talk's hold-to-talk pill, in the call bar where the mic
/// button was. Green while sending; while muted it says so, and a tap
/// unmutes (mute wins over push to talk).
class TalkButton extends StatefulWidget {
  const TalkButton(this.session, {this.height = 48, super.key});

  final VoipSession session;
  final double height;

  @override
  State<TalkButton> createState() => _TalkButtonState();
}

class _TalkButtonState extends State<TalkButton> {
  late final StreamSubscription _sub;

  /// This button's own hold, apart from the key's.
  final Object _source = Object();
  bool _held = false;

  @override
  void initState() {
    super.initState();
    _sub = clientManager!.callManager.onSelfAudioChanged
        .listen((_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _sub.cancel();
    if (_held) clientManager?.callManager.pushToTalk.release(_source);
    super.dispose();
  }

  void _down() {
    _held = true;
    clientManager!.callManager.pushToTalk.press(_source);
  }

  void _up() {
    if (!_held) return;
    _held = false;
    clientManager!.callManager.pushToTalk.release(_source);
  }

  @override
  Widget build(BuildContext context) {
    final callManager = clientManager!.callManager;
    final scheme = Theme.of(context).colorScheme;
    final muted = callManager.isMutedIn(widget.session);
    final talking = callManager.isTalkingIn(widget.session);
    const green = Color(0xff23a55a);

    final Color fill;
    final Color ink;
    final IconData icon;
    final String label;
    if (muted) {
      fill = scheme.error;
      ink = scheme.onError;
      icon = Icons.mic_off;
      label = "Muted";
    } else if (talking) {
      fill = green;
      ink = Colors.white;
      icon = Icons.mic;
      label = "Talking";
    } else {
      fill = scheme.secondaryContainer;
      ink = scheme.secondary;
      icon = Icons.mic_none;
      label = "Hold to talk";
    }

    final pill = AnimatedContainer(
      duration: const Duration(milliseconds: 100),
      height: widget.height,
      padding: EdgeInsets.symmetric(horizontal: widget.height * 0.42),
      decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(widget.height / 2),
          boxShadow: talking
              ? [
                  BoxShadow(
                      color: green.withAlpha(110),
                      blurRadius: 16,
                      spreadRadius: 2)
                ]
              : null),
      child: Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
        Icon(icon, color: ink, size: widget.height * 0.46),
        Text(label,
            style: TextStyle(
                color: ink,
                fontSize: widget.height * 0.31,
                fontWeight: FontWeight.w700)),
      ]),
    );

    return Tooltip(
      message: muted ? "Unmute" : "Hold to talk",
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: muted
            ? GestureDetector(
                onTap: () => callManager.setMutedIn(widget.session, false),
                child: pill)
            : Listener(
                onPointerDown: (_) => _down(),
                onPointerUp: (_) => _up(),
                onPointerCancel: (_) => _up(),
                child: pill),
      ),
    );
  }
}
