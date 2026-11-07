import 'dart:async';

import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/call_timer_text.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:commet/ui/molecules/call_card.dart';
import 'package:commet/ui/molecules/talk_button.dart';
import 'package:commet/utils/call_duration.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: a one-line stand-in for the call view while the keyboard is open
/// on a phone. The full call view and the chat shared what was left above
/// the keyboard, so typing during a call left no room for the messages.
class CompactCallStrip extends StatefulWidget {
  const CompactCallStrip(this.session,
      {this.desktop = false, this.onExpand, super.key});
  final VoipSession session;

  // Vommet: richer desktop bar (Vommet issue 1211); phone stays unchanged.
  final bool desktop;
  final VoidCallback? onExpand;

  static String get expandLabel => Intl.message('Expand call panel',
      name: 'expandDmCallPanel',
      desc: 'Restore the previous call panel height');

  static String get labelInCall => Intl.message("In call",
      desc: "Shown in the slim call bar above the chat while typing",
      name: "labelInCall");

  static String labelInCallCount(int count) => Intl.message("In call · $count",
      args: [count],
      name: "labelInCallCount",
      desc:
          "Shown in the slim call bar above the chat while typing, with the number of people in the call");

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
    if (widget.desktop) return desktopBar(context);
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
                      : CompactCallStrip.labelInCallCount(people.length),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Vommet issue 422: with push to talk on, the mic button
              // would do nothing useful; hold to talk instead.
              if (preferences.voipPushToTalk.value)
                TalkButton(widget.session, height: 32)
              else
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: muted
                      ? CallControlStrings.callControlUnmute
                      : CallControlStrings.callControlMute,
                  icon: Icon(muted ? Icons.mic_off : Icons.mic,
                      color: muted ? scheme.error : null),
                  onPressed: toggleMute,
                ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: CallControlStrings.callControlLeaveCall,
                icon: Icon(Icons.call_end, color: scheme.error),
                onPressed: () => widget.session.hangUpCall(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget desktopBar(BuildContext context) {
    final session = widget.session;
    final scheme = Theme.of(context).colorScheme;
    final room = session.client.getRoom(session.roomId);
    final self = session.client.self?.identifier;
    final remote = session.remoteUserId ??
        (room == null
            ? null
            : session.client
                .getComponent<DirectMessagesComponent>()
                ?.getDirectMessagePartnerId(room)) ??
        session.streams
            .map((s) => s.streamUserId)
            .where((id) => id != self)
            .firstOrNull;
    final ids = {if (self != null) self, if (remote != null) remote};
    final redaction = RedactionScope.of(context);
    final since = CallDuration.connectedSince(session);
    return Material(
      color: scheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 4,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              for (final id in ids)
                Builder(builder: (context) {
                  final member = room?.getMemberOrFallback(id);
                  final name = redaction.name(member?.displayName ?? id, id);
                  return Tooltip(
                    message: name,
                    child: tiamat.Avatar(
                      radius: 14,
                      image: member?.avatar,
                      placeholderText: name,
                      placeholderColor: redaction.nameColor(
                          member?.defaultColor ?? scheme.primary, id),
                      redactionKey: id,
                    ),
                  );
                }),
              const SizedBox(width: 8),
              if (since != null) CallTimerText(since: since),
            ]),
            Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: CompactCallStrip.expandLabel,
                constraints:
                    const BoxConstraints.tightFor(width: 48, height: 48),
                onPressed: widget.onExpand,
                icon: const Icon(Icons.expand_more),
              ),
              if (preferences.voipPushToTalk.value)
                SizedBox(width: 48, child: TalkButton(session, compact: true))
              else
                IconButton(
                  constraints:
                      const BoxConstraints.tightFor(width: 48, height: 48),
                  tooltip: session.isMicrophoneMuted
                      ? CallControlStrings.callControlUnmute
                      : CallControlStrings.callControlMute,
                  onPressed: toggleMute,
                  icon: Icon(
                      session.isMicrophoneMuted ? Icons.mic_off : Icons.mic),
                ),
              IconButton(
                constraints:
                    const BoxConstraints.tightFor(width: 48, height: 48),
                tooltip: CallControlStrings.callControlLeaveCall,
                onPressed: session.hangUpCall,
                icon: Icon(Icons.call_end, color: scheme.error),
              ),
            ]),
          ],
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
