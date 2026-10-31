// Vommet: Getting started, a short walkthrough with a picture on each page.
// Offered once after the first sign-in on a fresh install, after the
// onboarding pages and the welcome screen; always in Settings › Help and
// guides. Its last page teaches the right-click (press and hold) help.
import 'dart:math' as math;

import 'package:commet/config/preferences/bool_preference.dart';
import 'package:commet/ui/navigation/navigation_utils.dart';
import 'package:commet/ui/pages/guides/guide_pictures.dart';
import 'package:commet/ui/pages/guides/guides.dart';
import 'package:commet/ui/pages/setup/onboarding/onboarding_setup.dart';
import 'package:commet/ui/pages/setup/setup_page.dart';
import 'package:commet/utils/first_time_setup.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Set once Getting started was offered, so it shows once per install.
final BoolPreference gettingStartedOffered =
    BoolPreference("vommet_getting_started_offered", defaultValue: false);

class GettingStarted {
  static List<GettingStartedMenu> menus() => [
        GettingStartedMenu(
            gettingStartedWelcomeTitle, gettingStartedWelcomeBody, "overview"),
        GettingStartedMenu(
            gettingStartedSpacesTitle, gettingStartedSpacesBody, "spaces"),
        GettingStartedMenu(
            gettingStartedRoomsTitle, gettingStartedRoomsBody, "rooms"),
        GettingStartedMenu(
            gettingStartedChatTitle, gettingStartedChatBody, "chat"),
        GettingStartedMenu(
            gettingStartedVoiceTitle, gettingStartedVoiceBody, "voice"),
        GettingStartedMenu(
            gettingStartedHomeTitle, gettingStartedHomeBody, "home"),
        GettingStartedMenu(
            gettingStartedHelpTitle, gettingStartedHelpBody, "menu"),
      ];

  /// Queues the walkthrough in the first-run setup, once per install, while
  /// the guides experiment is on.
  static void registerIfNew() {
    if (!experimentGuides.value || gettingStartedOffered.value) return;
    gettingStartedOffered.set(true);
    menus().forEach(FirstTimeSetup.registerPostLoginSetup);
  }

  static Future<void> open(BuildContext context) =>
      NavigationUtils.navigateTo(context, SetupPage(menus()));
}

/// One page of Getting started. It is an onboarding page, so the setup page
/// gives it Back and Skip.
class GettingStartedMenu extends OnboardingMenu {
  GettingStartedMenu(this.title, this.body, this.picture);

  @override
  final String title;

  @override
  final String body;

  final String picture;

  /// The picture fills the page's width, up to about half the window's
  /// height so Back and Next stay in view; never smaller than it used to be.
  @override
  Widget content(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final byWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth / 2
              : _minPictureHeight;
          final byWindow = MediaQuery.sizeOf(context).height * 0.5;
          final height =
              math.max(_minPictureHeight, math.min(byWidth, byWindow));
          return GuidePicture(picture, height: height);
        },
      );

  static const _minPictureHeight = 200.0;

  @override
  String? get skipLabel => gettingStartedSkip;
}

String get gettingStartedSkip => Intl.message("Skip",
    name: "gettingStartedSkip",
    desc: "Button on the Getting started pages that skips the rest of them");

String get gettingStartedWelcomeTitle => Intl.message("Welcome to Vommet",
    name: "gettingStartedWelcomeTitle",
    desc: "Title of the first Getting started page");
String get gettingStartedWelcomeBody => Intl.message(
    "Vommet is a chat app for Matrix, an open network that anyone can run a server on. Here's a quick look around: about two minutes.",
    name: "gettingStartedWelcomeBody",
    desc: "Text of the first Getting started page");

String get gettingStartedSpacesTitle => Intl.message("Spaces are communities",
    name: "gettingStartedSpacesTitle",
    desc: "Title of the Getting started page about spaces");
String get gettingStartedSpacesBody => Intl.message(
    "The icons down the left are your spaces. A space works like a Discord server, but anyone can make one with the + below them.",
    name: "gettingStartedSpacesBody",
    desc: "Text of the Getting started page about spaces");

String get gettingStartedRoomsTitle => Intl.message("Pick the rooms you want",
    name: "gettingStartedRoomsTitle",
    desc: "Title of the Getting started page about joining rooms");
String get gettingStartedRoomsBody => Intl.message(
    "Joining a space doesn't join all of its rooms, so a new space can look empty. Right-click the space's icon (or press and hold it) and pick Browse rooms to join the others.",
    name: "gettingStartedRoomsBody",
    desc: "Text of the Getting started page about joining rooms");

String get gettingStartedChatTitle => Intl.message("Chatting",
    name: "gettingStartedChatTitle",
    desc: "Title of the Getting started page about messages");
String get gettingStartedChatBody => Intl.message(
    "Hover over a message (or press and hold it on a phone) to reply, react or start a thread. Your own messages can be edited or deleted the same way.",
    name: "gettingStartedChatBody",
    desc: "Text of the Getting started page about messages");

String get gettingStartedVoiceTitle => Intl.message("Voice rooms",
    name: "gettingStartedVoiceTitle",
    desc: "Title of the Getting started page about voice rooms");
String get gettingStartedVoiceBody => Intl.message(
    "Click a voice room to join it and start talking. Nobody gets rung; people drop in and out. You can turn on your camera or share your screen from there.",
    name: "gettingStartedVoiceBody",
    desc: "Text of the Getting started page about voice rooms");

String get gettingStartedHomeTitle => Intl.message("Home and direct messages",
    name: "gettingStartedHomeTitle",
    desc: "Title of the Getting started page about Home");
String get gettingStartedHomeBody => Intl.message(
    "The house icon at the top is Home. It has your direct messages: private chats with one person or a small group.",
    name: "gettingStartedHomeBody",
    desc: "Text of the Getting started page about Home");

String get gettingStartedHelpTitle => Intl.message("Help is a right-click away",
    name: "gettingStartedHelpTitle",
    desc: "Title of the last Getting started page, about the help menus");
String get gettingStartedHelpBody => Intl.message(
    "Not sure what something is? Right-click it, or press and hold on a phone, and pick the question at the bottom of the menu. Every guide, and this walkthrough, is also in Settings › Help and guides.",
    name: "gettingStartedHelpBody",
    desc: "Text of the last Getting started page, about the help menus");
