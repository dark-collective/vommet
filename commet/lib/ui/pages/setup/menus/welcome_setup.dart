import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/room.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/pages/setup/setup_menu.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: shown once, after the first sign-in on a fresh install (not on
/// upgrades, not when adding another account). Says this is an early
/// development build and offers to join the feedback room.
class WelcomeSetup implements SetupMenu {
  static const feedbackRoom = "#vommet:nether.im";

  StreamController<SetupMenuState> controller = StreamController();

  String get welcomeSetupTitle => Intl.message("Welcome to Vommet",
      name: "welcomeSetupTitle",
      desc: "Title of the welcome screen shown after the first sign-in");

  String get welcomeSetupBody => Intl.message(
      "Vommet is an early development build, so expect rough edges. "
      "Feedback is welcome and looked at promptly: if you suggest something "
      "that needs fixing, it might be fixed within the day.",
      name: "welcomeSetupBody",
      desc: "Body of the welcome screen shown after the first sign-in");

  String get welcomeSetupJoinPrompt => Intl.message(
      "Come say hi, ask questions, or report problems in the Vommet room.",
      name: "welcomeSetupJoinPrompt",
      desc: "Explains the feedback room on the welcome screen");

  @override
  Widget builder(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        tiamat.Text.largeTitle(welcomeSetupTitle),
        tiamat.Text.label(welcomeSetupBody),
        _JoinFeedbackRoomButton(prompt: welcomeSetupJoinPrompt),
      ],
    );
  }

  @override
  Stream<SetupMenuState> get onStateChanged => controller.stream;

  @override
  SetupMenuState state = SetupMenuState.canProgress;

  @override
  Future<void> submit() async {
    preferences.welcomeShown.set(true);
  }
}

enum _JoinState { idle, joining, joined, failed }

enum FeedbackRoomMembership { unknown, member, notMember }

/// Whether the account is in the feedback room. [locallyJoined] checks the
/// rooms this device already knows about (by alias, or by the room id once
/// it is known). Right after a fresh sign-in the first sync may not have
/// delivered the room yet, so the answer otherwise comes from the server:
/// the room id the alias resolves to, checked against /joined_rooms. Any
/// failure or timeout gives [FeedbackRoomMembership.unknown], and the offer
/// is not shown then.
Future<FeedbackRoomMembership> checkFeedbackRoomMembership({
  required bool Function(String? roomId) locallyJoined,
  required Future<String?> Function() resolveAlias,
  required Future<List<String>> Function() joinedRoomIds,
  Duration timeout = const Duration(seconds: 10),
}) async {
  if (locallyJoined(null)) return FeedbackRoomMembership.member;
  try {
    final (roomId, joined) =
        await (resolveAlias(), joinedRoomIds()).wait.timeout(timeout);
    if (roomId == null) return FeedbackRoomMembership.unknown;
    if (locallyJoined(roomId) || joined.contains(roomId)) {
      return FeedbackRoomMembership.member;
    }
    return FeedbackRoomMembership.notMember;
  } catch (e) {
    Log.w("Checking membership of ${WelcomeSetup.feedbackRoom} failed: $e");
    return FeedbackRoomMembership.unknown;
  }
}

/// Shown only once the account is known not to be in the feedback room, so
/// it never flashes up for members (it fades in when it does show).
class _JoinFeedbackRoomButton extends StatefulWidget {
  const _JoinFeedbackRoomButton({required this.prompt});

  final String prompt;

  @override
  State<_JoinFeedbackRoomButton> createState() =>
      _JoinFeedbackRoomButtonState();
}

class _JoinFeedbackRoomButtonState extends State<_JoinFeedbackRoomButton> {
  _JoinState joinState = _JoinState.idle;

  String get welcomeSetupPromptJoin => Intl.message("Join #vommet:nether.im",
      name: "welcomeSetupPromptJoin",
      desc: "Button that joins the Vommet feedback room");

  String get welcomeSetupJoined => Intl.message(
      "Joined! You'll find it in your room list.",
      name: "welcomeSetupJoined",
      desc: "Shown after joining the feedback room from the welcome screen");

  String get welcomeSetupJoinFailed => Intl.message(
      "Couldn't join right now. You can join #vommet:nether.im any time later.",
      name: "welcomeSetupJoinFailed",
      desc:
          "Shown when joining the feedback room from the welcome screen fails");

  StreamSubscription<Room>? roomAdded;
  String? feedbackRoomId;
  FeedbackRoomMembership membership = FeedbackRoomMembership.unknown;

  @override
  void initState() {
    super.initState();
    final client = clientManager?.clients.firstOrNull;
    if (client == null) return;

    if (isMember(client, null)) {
      membership = FeedbackRoomMembership.member;
      return;
    }

    // The first sync may still be running, so the room can also show up
    // while this screen is open (even after the offer is shown).
    roomAdded = client.onRoomAdded.listen((_) => recheck(client));
    checkMembership(client);
  }

  @override
  void dispose() {
    roomAdded?.cancel();
    super.dispose();
  }

  bool isMember(Client client, String? roomId) {
    if (client.getRoomByAlias(WelcomeSetup.feedbackRoom) != null) return true;
    final id = roomId ?? feedbackRoomId;
    return id != null && client.hasRoom(id);
  }

  void recheck(Client client) {
    if (!mounted || membership == FeedbackRoomMembership.member) return;
    if (!isMember(client, null)) return;
    setState(() => membership = FeedbackRoomMembership.member);
    roomAdded?.cancel();
  }

  Future<void> checkMembership(Client client) async {
    if (client is! MatrixClient) return;
    final matrix = client.getMatrixClient();
    final result = await checkFeedbackRoomMembership(
      locallyJoined: (id) => isMember(client, id),
      resolveAlias: () async {
        final id =
            (await matrix.getRoomIdByAlias(WelcomeSetup.feedbackRoom)).roomId;
        feedbackRoomId = id;
        return id;
      },
      joinedRoomIds: matrix.getJoinedRooms,
    );
    if (!mounted || membership == FeedbackRoomMembership.member) return;
    // The room may have arrived with the sync while the check ran.
    final now = isMember(client, null) ? FeedbackRoomMembership.member : result;
    setState(() => membership = now);
    if (now != FeedbackRoomMembership.notMember) roomAdded?.cancel();
  }

  Future<void> join() async {
    final client = clientManager?.clients.firstOrNull;
    if (client == null) return;

    setState(() => joinState = _JoinState.joining);
    try {
      await client.joinRoom(WelcomeSetup.feedbackRoom);
      if (mounted) setState(() => joinState = _JoinState.joined);
    } catch (e, s) {
      Log.onError(e, s, content: "Joining ${WelcomeSetup.feedbackRoom} failed");
      if (mounted) setState(() => joinState = _JoinState.failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final show = membership == FeedbackRoomMembership.notMember ||
        joinState != _JoinState.idle;

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      alignment: Alignment.topLeft,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topLeft,
          children: [...previous, if (current != null) current],
        ),
        child: show
            ? Column(
                key: const ValueKey("welcome-join-offer"),
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 8,
                children: [
                  const SizedBox(height: 8),
                  tiamat.Text.label(widget.prompt),
                  joinAction(),
                ],
              )
            : const SizedBox.shrink(),
      ),
    );
  }

  Widget joinAction() {
    return switch (joinState) {
      _JoinState.joined => tiamat.Text.label(welcomeSetupJoined),
      _JoinState.failed => tiamat.Text.label(welcomeSetupJoinFailed),
      _ => Align(
          alignment: Alignment.centerLeft,
          child: tiamat.Button(
            text: welcomeSetupPromptJoin,
            isLoading: joinState == _JoinState.joining,
            onTap: joinState == _JoinState.joining ? null : join,
          ),
        ),
    };
  }
}
