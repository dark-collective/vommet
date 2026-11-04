// Vommet (Deep Search, stage 2): the ways into Deep Search. The sidebar's
// last row and Shift+Enter, a chat's "Search messages here", the 611
// in-chat search's "Search all chats", the card, and the shortcuts
// (Ctrl+Shift+F anywhere, "/" when no text field has focus, Ctrl+G /
// Ctrl+Shift+G for the next / previous result).
import 'package:commet/client/client.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/organisms/new_home/deep_search/deep_search_handoff.dart';
import 'package:commet/ui/organisms/new_home/deep_search/deep_search_page.dart';
import 'package:commet/ui/organisms/new_home/deep_search/deep_search_query.dart';
import 'package:commet/ui/organisms/new_home/deep_search/deep_search_results.dart';
import 'package:commet/ui/organisms/new_home/deep_search/deep_search_session.dart';
import 'package:commet/ui/organisms/new_home/deep_search/deep_search_strings.dart';
import 'package:commet/ui/organisms/new_home/new_home_search.dart';
import 'package:commet/ui/pages/main/main_page.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DeepSearchEntry {
  static const color = Color(0xff9b84ee);

  static DeepSearchSession get session => DeepSearchSession.instance;

  /// Points the session at the app's accounts and the account filter.
  static void attach(BuildContext context) {
    final main = _main(context);
    final manager = main?.clientManager ?? clientManager;
    if (manager == null) return;
    session.attach(manager, main?.filterClient);
  }

  /// The sidebar search's last row (Mockup 2A): always last, also when
  /// no name matched.
  static Widget? sidebarRow(
      BuildContext context, String query, SearchScope<Space>? scope) {
    final handoff = DeepSearchHandoff.of<Space>(query, scope: scope);
    if (handoff == null) return null;
    return ListTile(
      key: const ValueKey(DeepSearchHandoff.rowKey),
      dense: true,
      leading: const Icon(Icons.search_rounded, size: 20, color: color),
      title: Text(handoff.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      onTap: () => show(context, query: handoff.query),
    );
  }

  /// Shift+Enter in the sidebar search.
  static void openHandoff(
      BuildContext context, String text, SearchScope<Space>? scope) {
    final handoff = DeepSearchHandoff.of<Space>(text, scope: scope);
    if (handoff == null) return;
    show(context, query: handoff.query);
  }

  /// A chat's "Search messages here": Deep Search scoped to it.
  static void openInRoom(BuildContext context, Room room) {
    attach(context);
    show(context,
        query: DeepSearchQuery<Space>(
            tokens: [DeepSearchToken.scope(session.roomScope(room))]));
  }

  /// The 611 in-chat search's "Search all chats", carrying its text.
  /// The `in:` chip keeps the chat; one Backspace widens it to all.
  static void openFromInChat(BuildContext context, Room room, String text) {
    attach(context);
    show(context,
        query: DeepSearchQuery<Space>(
            tokens: [DeepSearchToken.scope(session.roomScope(room))],
            text: text.trim()));
  }

  /// Opens Deep Search: the phone pushes its page; the desktop shows it
  /// in Home's main area, keeping the side list.
  static void show(BuildContext context,
      {DeepSearchQuery<Space>? query, bool focus = true}) {
    attach(context);
    final phone = MediaQuery.of(context).mobile;
    if (phone) {
      session.show(q: query, focus: focus, page: false);
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const DeepSearchPage(phone: true),
          settings: const RouteSettings(name: DeepSearchPage.routeName)));
      return;
    }
    final main = _main(context);
    EventBus.openHomeScreen.add(null);
    main?.selectHome();
    session.show(q: query, focus: focus);
  }

  /// "‹ Results" on the results bar: the list as it was left.
  static void backToResults(BuildContext context) {
    show(context, focus: false);
  }

  /// Opens a result. False (with "You left this room") when its room is
  /// gone.
  static bool openResult(BuildContext context, DeepSearchResult r) {
    final ok = session.open(r);
    if (!ok) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(DeepSearchStrings.youLeft)));
    }
    return ok;
  }

  /// Steps the results bar; a gone room shows "You left this room".
  static void step(BuildContext context, int delta) {
    if (session.openList.isEmpty) return;
    final before = session.openIndex;
    final ok = session.step(delta);
    if (!ok && session.openIndex != before) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(DeepSearchStrings.youLeft)));
    }
  }

  /// The global shortcuts, from MainPageState's keyboard handler. True
  /// when the key was used.
  static bool handleKey(KeyEvent event, BuildContext context) {
    if (event is! KeyDownEvent) return false;
    final keyboard = HardwareKeyboard.instance;
    final ctrl = keyboard.isControlPressed || keyboard.isMetaPressed;
    final key = event.logicalKey;

    if (ctrl && keyboard.isShiftPressed && key == LogicalKeyboardKey.keyF) {
      show(context);
      return true;
    }
    if (ctrl && key == LogicalKeyboardKey.keyG && session.openList.isNotEmpty) {
      step(context, keyboard.isShiftPressed ? -1 : 1);
      return true;
    }
    // "/" never steals typing: only when no text field has the focus.
    if (!ctrl &&
        !keyboard.isAltPressed &&
        event.character == "/" &&
        !_textFieldFocused()) {
      show(context);
      return true;
    }
    return false;
  }

  /// The main page: [context]'s own (the keyboard handler's) or an
  /// ancestor's.
  static MainPageState? _main(BuildContext context) {
    if (context is StatefulElement && context.state is MainPageState) {
      return context.state as MainPageState;
    }
    return context.findAncestorStateOfType<MainPageState>();
  }

  static bool _textFieldFocused() {
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null) return false;
    if (focused.widget is EditableText) return true;
    return focused.findAncestorWidgetOfExactType<EditableText>() != null;
  }
}
