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

/// Hidden entirely when the account is already in the feedback room.
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
  bool alreadyMember = false;

  @override
  void initState() {
    super.initState();
    final client = clientManager?.clients.firstOrNull;
    if (client == null) return;

    alreadyMember = isMember(client);
    if (alreadyMember) return;

    // Right after a fresh sign-in the first sync may still be running, so
    // the room can show up while this screen is open.
    roomAdded = client.onRoomAdded.listen((_) => recheck(client));
    resolveFeedbackRoomId(client);
  }

  @override
  void dispose() {
    roomAdded?.cancel();
    super.dispose();
  }

  bool isMember(Client client) {
    if (client.getRoomByAlias(WelcomeSetup.feedbackRoom) != null) return true;
    final id = feedbackRoomId;
    return id != null && client.hasRoom(id);
  }

  void recheck(Client client) {
    if (!mounted || alreadyMember || !isMember(client)) return;
    setState(() => alreadyMember = true);
    roomAdded?.cancel();
  }

  // The canonical alias state can be missing locally, so also match the
  // room id the alias resolves to.
  Future<void> resolveFeedbackRoomId(Client client) async {
    if (client is! MatrixClient) return;
    try {
      final response = await client
          .getMatrixClient()
          .getRoomIdByAlias(WelcomeSetup.feedbackRoom);
      feedbackRoomId = response.roomId;
      recheck(client);
    } catch (e) {
      Log.w("Resolving ${WelcomeSetup.feedbackRoom} failed: $e");
    }
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
    if (alreadyMember && joinState == _JoinState.idle) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        const SizedBox(height: 8),
        tiamat.Text.label(widget.prompt),
        joinAction(),
      ],
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
