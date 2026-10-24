// Vommet: the profile card's "Add contact" button (New Home only). Sits
// under Message; once the person is a contact it turns into a quieter
// "Contact" button whose menu removes them or opens Home › People. The list
// is your private account data (FriendsComponent): nobody is notified.
import 'dart:async';

import 'package:commet/client/components/friends/friends_component.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/organisms/new_home/new_home.dart';
import 'package:commet/ui/organisms/new_home/new_home_layout.dart';
import 'package:commet/ui/organisms/new_home/new_home_shortcuts.dart';
import 'package:commet/ui/pages/main/main_page.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

String get profileAddContact => Intl.message("Add contact",
    name: "profileAddContact",
    desc: "Profile card button under Message that adds the person to your "
        "contacts (Home › People)");

String get profileContactButton => Intl.message("Contact",
    name: "profileContactButton",
    desc: "Profile card button shown instead of Add contact once the person "
        "is one of your contacts; it opens a menu");

String get profileRemoveFromContacts => Intl.message("Remove from contacts",
    name: "profileRemoveFromContacts",
    desc: "Menu item of the profile card's Contact button");

String get profileOpenPeople => Intl.message("Open People",
    name: "profileOpenPeople",
    desc: "Menu item of the profile card's Contact button that opens "
        "Home › People");

String profileAddedToContacts(String name) =>
    Intl.message("Added $name to your contacts.",
        args: [name],
        name: "profileAddedToContacts",
        desc: "Toast after Add contact on a profile card; name is their "
            "display name or user ID");

String get profileContactUndo => Intl.message("Undo",
    name: "profileContactUndo",
    desc: "Action on the toast after adding a contact from a profile card");

String get profileContactsFailed => Intl.message(
    "Couldn't update your contacts.",
    name: "profileContactsFailed",
    desc: "Toast when adding or removing a contact from a profile card fails");

class ProfileContactButton extends StatefulWidget {
  const ProfileContactButton(
      {required this.friends,
      required this.userId,
      required this.displayName,
      this.onOpenPeople,
      super.key});

  final FriendsComponent friends;
  final String userId;
  final String displayName;

  /// "Open People"; null closes the profile and opens Home › People.
  final void Function(BuildContext context)? onOpenPeople;

  static const addKey = ValueKey("ProfileAddContact");
  static const contactKey = ValueKey("ProfileContactMenu");
  static const removeKey = ValueKey("ProfileRemoveContact");
  static const openPeopleKey = ValueKey("ProfileOpenPeople");
  static const undoKey = ValueKey("ProfileContactUndo");

  @override
  State<ProfileContactButton> createState() => _ProfileContactButtonState();
}

class _ProfileContactButtonState extends State<ProfileContactButton> {
  late List<StreamSubscription> subs;

  @override
  void initState() {
    super.initState();
    subs = [
      widget.friends.onFriendsChanged.listen((_) => rebuild()),
      experimentNewHome.onChanged.listen((_) => rebuild()),
    ];
  }

  void rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final sub in subs) {
      sub.cancel();
    }
    super.dispose();
  }

  bool get isContact => widget.friends.friends.contains(widget.userId);

  Future<void> attempt(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      Log.w("Profile: couldn't update the contacts: $e");
      if (mounted) ProfileContactToast.show(context, profileContactsFailed);
    }
  }

  Future<void> add() async {
    final friends = widget.friends;
    final userId = widget.userId;
    final name = widget.displayName;
    final toastContext = context;
    try {
      await friends.addFriends([userId]);
    } catch (e) {
      Log.w("Profile: couldn't add the contact: $e");
      if (mounted) ProfileContactToast.show(context, profileContactsFailed);
      return;
    }
    if (!toastContext.mounted) return;
    ProfileContactToast.show(toastContext, profileAddedToContacts(name),
        action: profileContactUndo, onAction: () async {
      try {
        await friends.removeFriend(userId);
      } catch (e) {
        Log.w("Profile: couldn't undo adding the contact: $e");
      }
    });
  }

  void openPeople() {
    final open = widget.onOpenPeople ?? openHomePeople;
    open(context);
  }

  /// Closes the profile popup or sheet, then opens Home › People the way the
  /// rail's People button does.
  static void openHomePeople(BuildContext context) {
    final main = context.findAncestorStateOfType<MainPageState>() ??
        _findMainPage(navigator.currentContext);
    Navigator.of(context).maybePop();
    if (main == null || !main.mounted) {
      HomeLayoutStore.instance.showTabHolding(HomeLayout.peoplePage);
      EventBus.openHomeScreen.add(null);
      return;
    }
    openHomeBlock(main, HomeLayout.peoplePage);
  }

  // The profile is a dialog or sheet route, so the main page isn't one of
  // its ancestors: look it up under the app's navigator.
  static MainPageState? _findMainPage(BuildContext? root) {
    if (root == null) return null;
    MainPageState? found;
    void visit(Element e) {
      if (found != null) return;
      if (e is StatefulElement && e.state is MainPageState) {
        found = e.state as MainPageState;
        return;
      }
      e.visitChildren(visit);
    }

    (root as Element).visitChildren(visit);
    return found;
  }

  ButtonStyle style(BuildContext context, {required bool quiet}) {
    final scheme = Theme.of(context).colorScheme;
    final color = quiet ? scheme.onSurfaceVariant : scheme.primary;
    final border = quiet ? scheme.outlineVariant : scheme.primary;
    final base =
        Theme.of(context).elevatedButtonTheme.style ?? const ButtonStyle();
    return base.copyWith(
      foregroundColor: WidgetStatePropertyAll(color),
      iconColor: WidgetStatePropertyAll(color),
      backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
      shadowColor: const WidgetStatePropertyAll(Colors.transparent),
      elevation: const WidgetStatePropertyAll(0),
      side: WidgetStatePropertyAll(BorderSide(color: border, width: 1)),
    );
  }

  // The Message button's inner padding, so both are the same height.
  Widget label(IconData icon, String text, {bool dropdown = false}) => Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            Icon(icon, size: 18),
            Flexible(child: Text(text, overflow: TextOverflow.ellipsis)),
            if (dropdown) const Icon(Icons.arrow_drop_down, size: 20),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (!newHomeEnabled) return const SizedBox.shrink();

    final Widget button;
    if (!isContact) {
      button = ElevatedButton(
        key: ProfileContactButton.addKey,
        style: style(context, quiet: false),
        onPressed: add,
        child: label(Icons.person_add, profileAddContact),
      );
    } else {
      button = MenuAnchor(
        menuChildren: [
          MenuItemButton(
            key: ProfileContactButton.removeKey,
            leadingIcon: const Icon(Icons.person_remove_rounded),
            onPressed: () =>
                attempt(() => widget.friends.removeFriend(widget.userId)),
            child: Text(profileRemoveFromContacts),
          ),
          MenuItemButton(
            key: ProfileContactButton.openPeopleKey,
            leadingIcon: const Icon(Icons.people_alt_rounded),
            onPressed: openPeople,
            child: Text(profileOpenPeople),
          ),
        ],
        builder: (context, controller, _) => ElevatedButton(
          key: ProfileContactButton.contactKey,
          style: style(context, quiet: true),
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
          child: label(Icons.how_to_reg_rounded, profileContactButton,
              dropdown: true),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: SizedBox(width: double.infinity, child: button),
    );
  }
}

/// A snackbar-like toast in the app's top overlay, so it shows (and its
/// action can be tapped) above the profile popup or sheet too.
class ProfileContactToast {
  static OverlayEntry? _entry;
  static Timer? _timer;

  static const duration = Duration(seconds: 4);

  static void show(BuildContext context, String message,
      {String? action, Future<void> Function()? onAction}) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    hide();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final entry = OverlayEntry(
      builder: (context) => Positioned(
        left: 16,
        right: 16,
        bottom: 24 + MediaQuery.viewPaddingOf(context).bottom,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Material(
              color: scheme.inverseSurface,
              elevation: 6,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                child: Row(children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(message,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: scheme.onInverseSurface)),
                    ),
                  ),
                  if (action != null)
                    TextButton(
                      key: ProfileContactButton.undoKey,
                      style: TextButton.styleFrom(
                          foregroundColor: scheme.inversePrimary),
                      onPressed: () {
                        hide();
                        onAction?.call();
                      },
                      child: Text(action),
                    ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
    _entry = entry;
    overlay.insert(entry);
    _timer = Timer(duration, hide);
  }

  static void hide() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
  }
}
