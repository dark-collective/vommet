import 'dart:async';

import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/main.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: a one-line stand-in for the call view while the keyboard is open
/// on a phone. The full call view and the chat shared what was left above
/// the keyboard, so typing during a call left no room for the messages.
class CompactCallStrip extends StatefulWidget {
  const CompactCallStrip(this.session, {super.key});
  final VoipSession session;

  static String get labelInCall => Intl.message("In call",
      desc: "Shown in the slim call bar above the chat while typing",
      name: "labelInCall");

  @override
  State<CompactCallStrip> createState() => _CompactCallStripState();
}

class _CompactCallStripState extends State<CompactCallStrip> {
  StreamSubscription? sub;

  @override
  void initState() {
    super.initState();
    sub = widget.session.onStateChanged.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    sub?.cancel();
    super.dispose();
  }

  Future<void> toggleMute() async {
    final mute = !widget.session.isMicrophoneMuted;
    if (mute) {
      clientManager?.callManager.playMuteSound();
    } else {
      clientManager?.callManager.playUnmuteSound();
    }
    await widget.session.setMicrophoneMute(mute);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = widget.session.isMicrophoneMuted;
    final people = widget.session.streams.map((s) => s.streamUserId).toSet();
    return Material(
      color: scheme.surfaceContainer,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
          child: Row(
            spacing: 8,
            children: [
              Icon(Icons.call, size: 18, color: scheme.primary),
              Expanded(
                child: tiamat.Text.label(
                  people.isEmpty
                      ? CompactCallStrip.labelInCall
                      : "${CompactCallStrip.labelInCall} · ${people.length}",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: muted ? "Unmute" : "Mute",
                icon: Icon(muted ? Icons.mic_off : Icons.mic,
                    color: muted ? scheme.error : null),
                onPressed: toggleMute,
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: "Leave call",
                icon: Icon(Icons.call_end, color: scheme.error),
                onPressed: () => widget.session.hangUpCall(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Vommet: rebuilds when the on-screen keyboard opens or closes. The
/// Scaffold strips viewInsets from its body's MediaQuery, so widgets below
/// it aren't rebuilt for the keyboard; this listens to the window instead.
class KeyboardOpenBuilder extends StatefulWidget {
  const KeyboardOpenBuilder({required this.builder, super.key});
  final Widget Function(BuildContext context, bool keyboardOpen) builder;

  @override
  State<KeyboardOpenBuilder> createState() => _KeyboardOpenBuilderState();
}

class _KeyboardOpenBuilderState extends State<KeyboardOpenBuilder>
    with WidgetsBindingObserver {
  bool open = false;

  bool _read() =>
      MediaQueryData.fromView(View.of(context)).viewInsets.bottom > 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    open = _read();
  }

  @override
  void didChangeMetrics() {
    final now = _read();
    if (now != open && mounted) setState(() => open = now);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, open);
}
