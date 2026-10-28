// Vommet: in-app guides. Short help pages about one part of the app each,
// opened from the thing they explain (an item on its right-click or
// long-press menu), from Settings › Help & guides, or from the Getting
// started walkthrough. The text lives in assets/guides/<language>/<id>.md so
// it can be translated and mirrored to the wiki; the pictures are drawn from
// the app's theme (guide_pictures.dart), so they match whatever theme is on.
import 'package:commet/config/preferences/bool_preference.dart';
import 'package:commet/config/preferences/string_list_preference.dart';
import 'package:commet/client/client.dart';
import 'package:commet/client/components/voip_room/voip_room_component.dart';
import 'package:commet/ui/navigation/navigation_utils.dart';
import 'package:commet/ui/pages/guides/guide_page.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// The experiment: help items on menus, "What's this?" on right-click or
/// long-press of the main areas, and Getting started after the first sign-in.
/// Settings › Help & guides is always there.
final BoolPreference experimentGuides =
    BoolPreference("vommet_experiment_guides", defaultValue: false);

/// Guides the user has opened, for the check marks in Settings.
final StringListPreference guidesRead =
    StringListPreference("vommet_guides_read", defaultValue: const []);

/// Set once Getting started was finished or skipped.
final BoolPreference gettingStartedDone =
    BoolPreference("vommet_getting_started_done", defaultValue: false);

class Guide {
  const Guide({
    required this.id,
    required this.icon,
    required this.title,
    required this.question,
    required this.summary,
    this.keywords = const [],
  });

  /// Also the file name under assets/guides/<language>/.
  final String id;
  final IconData icon;
  final String title;

  /// The menu item that opens this guide, e.g. "What's a space?".
  final String question;
  final String summary;

  /// Extra words the Settings filter matches, e.g. "server" for spaces.
  final List<String> keywords;

  bool get read => guidesRead.value.contains(id);
}

class Guides {
  static const spaces = "spaces";
  static const rooms = "rooms";
  static const messages = "messages";
  static const voice = "voice";
  static const directMessages = "direct-messages";
  static const encryption = "encryption";
  static const accounts = "accounts";

  /// Every guide, in the order Settings lists them.
  static List<Guide> get all => [
        Guide(
          id: spaces,
          icon: Icons.grid_view_rounded,
          title: guideSpacesTitle,
          question: guideSpacesQuestion,
          summary: guideSpacesSummary,
          keywords: const [
            "server",
            "guild",
            "discord",
            "community",
            "subspace",
            "folder",
            "create",
            "make",
          ],
        ),
        Guide(
          id: rooms,
          icon: Icons.tag,
          title: guideRoomsTitle,
          question: guideRoomsQuestion,
          summary: guideRoomsSummary,
          keywords: const [
            "channel",
            "join",
            "leave",
            "browse",
            "empty",
            "favorite",
            "unread",
          ],
        ),
        Guide(
          id: messages,
          icon: Icons.chat_bubble_outline,
          title: guideMessagesTitle,
          question: guideMessagesQuestion,
          summary: guideMessagesSummary,
          keywords: const [
            "reply",
            "react",
            "reaction",
            "emoji",
            "edit",
            "delete",
            "thread",
            "mention",
            "sticker",
            "gif",
            "formatting",
          ],
        ),
        Guide(
          id: voice,
          icon: Icons.volume_up_outlined,
          title: guideVoiceTitle,
          question: guideVoiceQuestion,
          summary: guideVoiceSummary,
          keywords: const [
            "call",
            "video",
            "camera",
            "screen share",
            "stream",
            "go live",
            "mute",
            "microphone",
            "element call",
          ],
        ),
        Guide(
          id: directMessages,
          icon: Icons.mail_outline,
          title: guideDirectMessagesTitle,
          question: guideDirectMessagesQuestion,
          summary: guideDirectMessagesSummary,
          keywords: const ["dm", "private", "home", "friend", "invite"],
        ),
        Guide(
          id: encryption,
          icon: Icons.lock_outline,
          title: guideEncryptionTitle,
          question: guideEncryptionQuestion,
          summary: guideEncryptionSummary,
          keywords: const [
            "e2ee",
            "encrypted",
            "recovery key",
            "verify",
            "device",
            "session",
            "shield",
            "unable to decrypt",
            "security",
          ],
        ),
        Guide(
          id: accounts,
          icon: Icons.dns_outlined,
          title: guideAccountsTitle,
          question: guideAccountsQuestion,
          summary: guideAccountsSummary,
          keywords: const [
            "matrix",
            "homeserver",
            "server",
            "federation",
            "username",
            "sign in",
            "account",
          ],
        ),
      ];

  /// The guide for [room]: voice rooms have their own.
  static String forRoom(Room room) =>
      room.getComponent<VoipRoomComponent>() != null ? voice : rooms;

  static Guide? byId(String id) => all.where((g) => g.id == id).firstOrNull;

  /// Guides whose title, summary, keywords or text contain every word of
  /// [query]. [texts] maps guide ids to their loaded text, when known.
  static List<Guide> filter(String query,
      {Map<String, String> texts = const {}}) {
    final words = query
        .toLowerCase()
        .split(RegExp(r"\s+"))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return all;
    return all.where((g) {
      final haystack = [
        g.title,
        g.question,
        g.summary,
        ...g.keywords,
        texts[g.id] ?? "",
      ].join(" ").toLowerCase();
      return words.every(haystack.contains);
    }).toList();
  }

  /// The guide's text in the app's language, else English.
  static Future<String> load(String id, {AssetBundle? bundle}) async {
    final b = bundle ?? rootBundle;
    final language = Intl.getCurrentLocale().split(RegExp("[_-]")).first;
    for (final lang in {language, "en"}) {
      try {
        return await b.loadString("assets/guides/$lang/$id.md");
      } catch (_) {
        continue;
      }
    }
    return "";
  }

  /// Every guide's text, for the Settings filter.
  static Future<Map<String, String>> loadAll({AssetBundle? bundle}) async {
    final entries = await Future.wait(
        all.map((g) async => MapEntry(g.id, await load(g.id, bundle: bundle))));
    return Map.fromEntries(entries);
  }

  static Future<void> open(BuildContext context, String id) {
    guidesRead.add(id);
    return NavigationUtils.navigateTo(context, GuidePage(initialGuide: id));
  }

  /// The help item for a menu, e.g. "What's a space?". Null while the
  /// experiment is off, so callers can write `if (item != null) item`.
  static tiamat.ContextMenuItem? menuItem(BuildContext context, String id) {
    if (!experimentGuides.value) return null;
    final guide = byId(id);
    if (guide == null) return null;
    return tiamat.ContextMenuItem(
      text: guide.question,
      icon: Icons.help_outline,
      onPressed: () => open(context, id),
    );
  }
}

/// Right-click (or, on touch screens, press and hold with two fingers)
/// anywhere in [child] for its guide. Menus inside [child] win, so this only
/// answers where nothing else has a menu.
class GuideArea extends StatefulWidget {
  const GuideArea({required this.guide, required this.child, super.key});

  final String guide;
  final Widget child;

  /// Vommet issue 689: a finger resting on an empty part of a chat counts as
  /// press and hold, so on a touch screen a single finger opened the menu by
  /// accident. There it takes two fingers held down; a mouse is unchanged.
  static bool menuAllowed({required bool touch, required int fingersDown}) =>
      !touch || fingersDown >= 2;

  @override
  State<GuideArea> createState() => _GuideAreaState();
}

class _GuideAreaState extends State<GuideArea> {
  final Set<int> _fingers = {};
  bool _touch = false;

  static bool _isTouch(PointerEvent event) =>
      event.kind == PointerDeviceKind.touch ||
      event.kind == PointerDeviceKind.stylus ||
      event.kind == PointerDeviceKind.invertedStylus;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: _GuidesExperiment.instance,
      child: widget.child,
      builder: (context, on, child) {
        final item = on ? Guides.menuItem(context, widget.guide) : null;
        if (item == null) return child!;
        // A small menu where the pointer or finger is, on phones too, and
        // no ripple over the whole area.
        return Listener(
          onPointerDown: (event) {
            _touch = _isTouch(event);
            if (_touch) _fingers.add(event.pointer);
          },
          onPointerUp: (event) => _fingers.remove(event.pointer),
          onPointerCancel: (event) => _fingers.remove(event.pointer),
          child: tiamat.ContextMenu(
            items: [item],
            // True = handled: the long press opens nothing.
            onLongPress: () => !GuideArea.menuAllowed(
                touch: _touch, fingersDown: _fingers.length),
            child: child!,
          ),
        );
      },
    );
  }
}

/// Rebuilds the guide areas when the experiment is switched.
class _GuidesExperiment extends ValueNotifier<bool> {
  _GuidesExperiment() : super(experimentGuides.value) {
    experimentGuides.onChanged.listen((v) => value = v);
  }

  static final instance = _GuidesExperiment();
}

String get guideSpacesTitle => Intl.message("Spaces",
    name: "guideSpacesTitle", desc: "Title of the guide about spaces");
String get guideSpacesQuestion => Intl.message("What's a space?",
    name: "guideSpacesQuestion",
    desc: "Menu item on a space that opens the guide about spaces");
String get guideSpacesSummary =>
    Intl.message("Like a Discord server, but anyone can make one",
        name: "guideSpacesSummary",
        desc: "One-line summary of the spaces guide in Settings");

String get guideRoomsTitle => Intl.message("Rooms and joining",
    name: "guideRoomsTitle", desc: "Title of the guide about rooms");
String get guideRoomsQuestion => Intl.message("How do rooms work?",
    name: "guideRoomsQuestion",
    desc: "Menu item on a room or the room list that opens the rooms guide");
String get guideRoomsSummary => Intl.message("Why a new space can look empty",
    name: "guideRoomsSummary",
    desc: "One-line summary of the rooms guide in Settings");

String get guideMessagesTitle => Intl.message("Chatting",
    name: "guideMessagesTitle",
    desc: "Title of the guide about sending messages, replies and reactions");
String get guideMessagesQuestion =>
    Intl.message("How do I reply, react and edit?",
        name: "guideMessagesQuestion",
        desc: "Menu item in a chat that opens the guide about messages");
String get guideMessagesSummary =>
    Intl.message("Replies, reactions, threads and editing",
        name: "guideMessagesSummary",
        desc: "One-line summary of the chatting guide in Settings");

String get guideVoiceTitle => Intl.message("Voice rooms and calls",
    name: "guideVoiceTitle", desc: "Title of the guide about voice rooms");
String get guideVoiceQuestion => Intl.message("How do voice rooms work?",
    name: "guideVoiceQuestion",
    desc: "Menu item in a voice room that opens the voice guide");
String get guideVoiceSummary =>
    Intl.message("Click to join, talk, share your screen",
        name: "guideVoiceSummary",
        desc: "One-line summary of the voice guide in Settings");

String get guideDirectMessagesTitle => Intl.message("Direct messages",
    name: "guideDirectMessagesTitle",
    desc: "Title of the guide about direct messages");
String get guideDirectMessagesQuestion =>
    Intl.message("How do direct messages work?",
        name: "guideDirectMessagesQuestion",
        desc: "Menu item on Home that opens the direct messages guide");
String get guideDirectMessagesSummary =>
    Intl.message("Private chats, and what's on Home",
        name: "guideDirectMessagesSummary",
        desc: "One-line summary of the direct messages guide in Settings");

String get guideEncryptionTitle => Intl.message("Encryption and your devices",
    name: "guideEncryptionTitle",
    desc: "Title of the guide about encryption, recovery keys and verifying");
String get guideEncryptionQuestion => Intl.message("How does encryption work?",
    name: "guideEncryptionQuestion",
    desc: "Menu item that opens the encryption guide");
String get guideEncryptionSummary =>
    Intl.message("Recovery key, verifying and the lock icons",
        name: "guideEncryptionSummary",
        desc: "One-line summary of the encryption guide in Settings");

String get guideAccountsTitle => Intl.message("Matrix accounts",
    name: "guideAccountsTitle",
    desc: "Title of the guide about Matrix accounts and homeservers");
String get guideAccountsQuestion => Intl.message("How do Matrix accounts work?",
    name: "guideAccountsQuestion",
    desc: "Menu item that opens the Matrix accounts guide");
String get guideAccountsSummary =>
    Intl.message("Your account lives on a homeserver",
        name: "guideAccountsSummary",
        desc: "One-line summary of the Matrix accounts guide in Settings");
