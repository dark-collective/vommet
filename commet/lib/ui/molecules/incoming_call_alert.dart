// Vommet: persistent desktop incoming-call controls (Vommet issue 1098).
import 'dart:async';

import 'package:commet/client/call_manager.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/matrix/components/room_call/matrix_room_call_invite.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

typedef _CallKey = (String, String);
_CallKey _key(VoipSession s) => (s.client.identifier, s.sessionId);

/// An app-owned card, not an OS window or an incoming-call delivery service.
/// Native notifiers and the call manager retain notification/audio ownership.
class IncomingCallAlertHost extends StatefulWidget {
  const IncomingCallAlertHost(
      {required this.calls, required this.child, super.key});
  final CallManager calls;
  final Widget child;

  @override
  State<IncomingCallAlertHost> createState() => _IncomingCallAlertHostState();
}

class _IncomingCallAlertHostState extends State<IncomingCallAlertHost> {
  final _listeners = Map<VoipSession, List<StreamSubscription>>.identity();
  final _pending = <_CallKey>{};
  final _handled = <_CallKey>{};
  final _subscriptions = <StreamSubscription>[];
  List<VoipSession> _queue = [];
  int _index = 0;
  int _generation = 0;
  String? _failure;

  static String get _title => Intl.message('Incoming call',
      name: 'incomingCallAlertTitle', desc: 'Desktop incoming call card title');
  static String _account(String account) => Intl.message('To $account',
      name: 'incomingCallAlertAccount',
      args: [account],
      desc: 'Receiving account on an incoming call card');
  static String _count(int count) => Intl.message('$count incoming calls',
      name: 'incomingCallAlertCount',
      args: [count],
      desc: 'Number of incoming calls waiting for an answer');
  static String get _next => Intl.message('Next call',
      name: 'incomingCallAlertNext', desc: 'Switch to the next ringing call');
  static String get _accept => Intl.message('Accept',
      name: 'incomingCallAlertAccept', desc: 'Answer an incoming call');
  static String get _decline => Intl.message('Decline',
      name: 'incomingCallAlertDecline', desc: 'Decline an incoming call');
  static String get _failed =>
      Intl.message('The call action failed. Open the room to check the call.',
          name: 'incomingCallAlertFailed', desc: 'Incoming call action failed');
  static String get _dismiss => Intl.message('Dismiss',
      name: 'incomingCallAlertDismiss',
      desc: 'Dismiss a failed call action notice');

  bool get _desktop =>
      !kIsWeb &&
      switch (defaultTargetPlatform) {
        TargetPlatform.linux ||
        TargetPlatform.windows ||
        TargetPlatform.macOS =>
          true,
        _ => false,
      };

  @override
  void initState() {
    super.initState();
    _attach();
  }

  void _attach() {
    if (!_desktop) return;
    _subscriptions.addAll([
      widget.calls.currentSessions.onListUpdated.listen((_) => _refresh()),
      widget.calls.clientManager.clients.onListUpdated
          .listen((_) => _refresh()),
      preferences.enableNotifications.onChanged.listen((_) {
        if (mounted) setState(() {});
      }),
    ]);
    _refresh(rebuild: false);
  }

  @override
  void didUpdateWidget(IncomingCallAlertHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.calls == widget.calls) return;
    _generation++;
    _detach();
    _queue = [];
    _handled.clear();
    _pending.clear();
    _failure = null;
    _attach();
  }

  void _detach() {
    for (final sub in [
      ..._subscriptions,
      ..._listeners.values.expand((s) => s)
    ]) {
      sub.cancel();
    }
    _subscriptions.clear();
    _listeners.clear();
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  bool _valid(VoipSession s) =>
      s.state == VoipState.incoming &&
      widget.calls.clientManager.clients.any((c) => identical(c, s.client)) &&
      widget.calls.currentSessions.any((c) => identical(c, s));

  void _refresh({bool rebuild = true}) {
    final sessions = Set<VoipSession>.identity()
      ..addAll(widget.calls.currentSessions);
    for (final s in _listeners.keys.toList()) {
      if (!sessions.contains(s)) {
        for (final sub in _listeners.remove(s)!) {
          sub.cancel();
        }
      }
    }
    for (final s in sessions) {
      _listeners.putIfAbsent(
          s,
          () => [
                s.onStateChanged.listen((_) => _refresh()),
                s.onConnectionStateChanged.listen((_) => _refresh()),
              ]);
    }
    _handled.removeWhere((key) => !sessions.any((s) => _key(s) == key));
    final seen = <_CallKey>{};
    final next = [
      for (final s in widget.calls.currentSessions)
        if (_valid(s) && !_handled.contains(_key(s)) && seen.add(_key(s))) s
    ];
    if (_queue.length == next.length &&
        Iterable.generate(next.length)
            .every((i) => identical(_queue[i], next[i]))) {
      return;
    }
    final selected = _queue.isEmpty ? null : _queue[_index];
    _queue = next;
    _index =
        selected == null ? 0 : _queue.indexWhere((s) => identical(s, selected));
    if (_index < 0) _index = 0;
    if (rebuild && mounted) setState(() {});
  }

  bool _isCurrent(CallManager calls, int generation) =>
      mounted && identical(widget.calls, calls) && generation == _generation;

  Future<void> _act(VoipSession session, bool accept) async {
    final calls = widget.calls;
    final generation = _generation;
    final key = _key(session);
    if (_pending.contains(key) ||
        _handled.contains(key) ||
        !_valid(session) ||
        !preferences.enableNotifications.value) return;
    setState(() {
      _pending.add(key);
      _failure = null;
    });
    try {
      if (accept) {
        // This adapter historically logs join failures for its other callers.
        // The card needs the result so it never silently claims success.
        if (session is MatrixRoomCallInvite) {
          await session.acceptCallWithResult();
        } else {
          await session.acceptCall(withMicrophone: true);
        }
        if (_isCurrent(calls, generation) &&
            calls.clientManager.clients.contains(session.client)) {
          EventBus.doOpenRoom(session.roomId,
              clientId: session.client.identifier);
        }
      } else {
        await session.declineCall();
      }
      if (_isCurrent(calls, generation)) _handled.add(key);
    } catch (_) {
      if (_isCurrent(calls, generation)) _failure = _failed;
    } finally {
      if (_isCurrent(calls, generation)) {
        _pending.remove(key);
        _refresh(rebuild: false);
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_desktop) return widget.child;
    final visible = preferences.enableNotifications.value &&
        (_queue.isNotEmpty || _failure != null);
    final session = _queue.isEmpty ? null : _queue[_index];
    final redaction = RedactionScope.of(context);
    final callerId = session?.remoteUserId ?? session?.roomId ?? '';
    final colors = Theme.of(context).colorScheme;
    return Stack(fit: StackFit.expand, children: [
      widget.child,
      if (visible)
        Positioned.fill(
            child: SafeArea(
                child: Align(
          alignment: Alignment.topRight,
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 390),
                child: SingleChildScrollView(
                    child: FocusTraversalGroup(
                        child: Semantics(
                            liveRegion: true,
                            child: Material(
                              elevation: 8,
                              color: colors.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(16),
                              child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(children: [
                                          Icon(Icons.call,
                                              color: colors.primary),
                                          const SizedBox(width: 12),
                                          Expanded(
                                              child: Text(_title,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleMedium))
                                        ]),
                                        if (session != null) ...[
                                          const SizedBox(height: 20),
                                          Text(
                                              redaction.name(
                                                  session.remoteUserName ??
                                                      session.remoteUserId ??
                                                      session.roomName,
                                                  callerId),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleLarge),
                                          const SizedBox(height: 6),
                                          Text(
                                              redaction.roomName(
                                                  session.roomName,
                                                  session.roomId,
                                                  dmPartnerId: callerId),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis),
                                          const SizedBox(height: 16),
                                          Text(
                                              _account(redaction.name(
                                                  session.client.self
                                                          ?.identifier ??
                                                      session.client.identifier,
                                                  session.client.self
                                                          ?.identifier ??
                                                      session
                                                          .client.identifier)),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis),
                                          const SizedBox(height: 20),
                                          Wrap(
                                              spacing: 12,
                                              runSpacing: 8,
                                              children: [
                                                OutlinedButton.icon(
                                                    style: OutlinedButton
                                                        .styleFrom(
                                                            foregroundColor:
                                                                colors
                                                                    .onSurface),
                                                    onPressed: _pending
                                                            .contains(_key(
                                                                session))
                                                        ? null
                                                        : () => _act(
                                                            session, false),
                                                    icon: const Icon(
                                                        Icons.call_end),
                                                    label: Text(_decline)),
                                                FilledButton.icon(
                                                    onPressed: _pending
                                                            .contains(
                                                                _key(session))
                                                        ? null
                                                        : () =>
                                                            _act(session, true),
                                                    icon:
                                                        const Icon(Icons.call),
                                                    label: Text(_accept)),
                                              ]),
                                          if (_queue.length > 1) ...[
                                            const SizedBox(height: 12),
                                            Text(_count(_queue.length)),
                                            TextButton(
                                                onPressed: () => setState(() {
                                                      _index = (_index + 1) %
                                                          _queue.length;
                                                    }),
                                                child: Text(_next)),
                                          ],
                                        ],
                                        if (_failure != null) ...[
                                          const SizedBox(height: 12),
                                          Text(_failure!,
                                              style: TextStyle(
                                                  color: colors.error)),
                                          TextButton(
                                              onPressed: () => setState(
                                                  () => _failure = null),
                                              child: Text(_dismiss)),
                                        ],
                                      ])),
                            )))),
              )),
        ))),
    ]);
  }
}
