import 'dart:async';

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

  String get title => Intl.message("Welcome to Vommet",
      name: "welcomeSetupTitle",
      desc: "Title of the welcome screen shown after the first sign-in");

  String get body => Intl.message(
      "Vommet is an early development build, so expect rough edges. "
      "Feedback is welcome and looked at promptly: if you suggest something "
      "that needs fixing, it might be fixed within the day.",
      name: "welcomeSetupBody",
      desc: "Body of the welcome screen shown after the first sign-in");

  String get joinPrompt => Intl.message(
      "Come say hi, ask questions or report problems in the Vommet room.",
      name: "welcomeSetupJoinPrompt",
      desc: "Explains the feedback room on the welcome screen");

  @override
  Widget builder(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        tiamat.Text.largeTitle(title),
        tiamat.Text.label(body),
        const SizedBox(height: 8),
        tiamat.Text.label(joinPrompt),
        const _JoinFeedbackRoomButton(),
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

class _JoinFeedbackRoomButton extends StatefulWidget {
  const _JoinFeedbackRoomButton();

  @override
  State<_JoinFeedbackRoomButton> createState() =>
      _JoinFeedbackRoomButtonState();
}

class _JoinFeedbackRoomButtonState extends State<_JoinFeedbackRoomButton> {
  _JoinState joinState = _JoinState.idle;

  String get promptJoin => Intl.message("Join #vommet:nether.im",
      name: "welcomeSetupPromptJoin",
      desc: "Button that joins the Vommet feedback room");

  String get labelJoined => Intl.message(
      "Joined! You'll find it in your room list.",
      name: "welcomeSetupJoined",
      desc: "Shown after joining the feedback room from the welcome screen");

  String get labelFailed => Intl.message(
      "Couldn't join right now. You can join #vommet:nether.im any time later.",
      name: "welcomeSetupJoinFailed",
      desc:
          "Shown when joining the feedback room from the welcome screen fails");

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
    return switch (joinState) {
      _JoinState.joined => tiamat.Text.label(labelJoined),
      _JoinState.failed => tiamat.Text.label(labelFailed),
      _ => Align(
          alignment: Alignment.centerLeft,
          child: tiamat.Button(
            text: promptJoin,
            isLoading: joinState == _JoinState.joining,
            onTap: joinState == _JoinState.joining ? null : join,
          ),
        ),
    };
  }
}
