import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/diagnostic/diagnostics.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/scaled_safe_area.dart';
import 'package:commet/ui/layout/tab_swipe.dart';
import 'package:commet/ui/organisms/home_screen/home_screen.dart';
import 'package:commet/ui/organisms/invitation_view/invite_preview_page.dart';
import 'package:commet/ui/organisms/new_home/new_home.dart';
import 'package:commet/ui/organisms/new_home/new_home_cards.dart';
import 'package:commet/ui/organisms/new_home/new_home_editor.dart';
import 'package:commet/ui/organisms/new_home/new_home_overview.dart';
import 'package:commet/ui/organisms/new_home/new_home_tabs.dart';
import 'package:commet/ui/pages/main/main_page.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_gate.dart';
import 'package:commet/utils/update_checker.dart';
import 'package:flutter/material.dart';

/// Vommet: Home's main area with the New Home experiment on: the main page
/// of the tab the column's rows picked. On phones it is the main panel, so
/// swiping right shows the column again, as from a room.
/// [home] is the old Home ([HomeScreen]); only its burger callback is used.
class NewHomeMain extends StatefulWidget {
  const NewHomeMain({super.key, required this.home, required this.phone});

  final Widget home;
  final bool phone;

  @override
  State<NewHomeMain> createState() => _NewHomeMainState();
}

class _NewHomeMainState extends State<NewHomeMain> {
  static bool _reportedRoomListOnScreen = false;

  @override
  void initState() {
    super.initState();
    // The old Home checked for updates when it opened; it isn't built now.
    if (preferences.checkForUpdates.value == true) {
      UpdateChecker.checkForUpdates();
    }
    // The old Home's startup timer, same name, so app_ready reports it
    // either way: the room list on screen (from the local cache).
    if (!_reportedRoomListOnScreen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_reportedRoomListOnScreen) return;
        final manager = clientManager;
        if (manager == null || manager.rooms.isEmpty) return;
        _reportedRoomListOnScreen = true;
        Diagnostics.general.addResult(
            "Startup: room list on screen (since launch)",
            startupClock.elapsed);
      });
    }
  }

  @override
  void dispose() {
    // Customize mode ends with the page that showed it (not while the
    // tree is locked).
    Future.microtask(() => newHomeCustomizing.value = false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final main = context.findAncestorStateOfType<MainPageState>();
    final manager = main?.clientManager ?? clientManager;
    if (manager == null) return const SizedBox.shrink();
    HomeLayoutStore.instance.attach(manager);
    final filter = main?.filterClient;
    // The shown tab: which one, and its name, icon and contents.
    final shown = Listenable.merge(
        [newHomeTab, HomeLayoutStore.instance.tabs, newHomeViews]);

    if (widget.phone) {
      final home = widget.home;
      final burger = home is HomeScreen ? home.onBurgerMenuTap : null;
      return ListenableBuilder(
        listenable: shown,
        builder: (context, _) {
          final tab = HomeLayoutStore.instance.current;
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ScaledSafeArea(
                  bottom: false,
                  child: NewHomeHeader(
                    key: ValueKey("NewHomeHeader-${tab.id}"),
                    tab: tab,
                    phone: true,
                    leading: burger == null
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.menu), onPressed: burger),
                  ),
                ),
                // Like the old Home: "Your messages aren't backed up".
                const SecureSetupBanner(),
                Expanded(child: pageContent(tab, manager, filter, phone: true)),
              ]);
        },
      );
    }

    // Like the old Home: an invite opened from Home fills this pane, under
    // the backup banner.
    return ScaledSafeArea(
      child: InvitePreviewHost(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SecureSetupBanner(),
          Expanded(
            child: ListenableBuilder(
              listenable: shown,
              builder: (context, _) => ValueListenableBuilder(
                valueListenable: newHomeCustomizing,
                builder: (context, customizing, _) {
                  final tab = HomeLayoutStore.instance.current;
                  final body = pageBody(tab, manager, filter, phone: false);
                  if (!customizing) return body;
                  // Customize Home: the editor beside the live Home.
                  return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // The part not being edited dims.
                        Expanded(
                          child: ValueListenableBuilder(
                            valueListenable: newHomeEditPart,
                            builder: (context, part, _) => AnimatedOpacity(
                                duration: const Duration(milliseconds: 150),
                                opacity: part == HomeEditPart.side ? 0.4 : 1,
                                child: body),
                          ),
                        ),
                        NewHomeEditorPanel(clientManager: manager),
                      ]);
                },
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// A tab's main page, without its header: its shown view, under a bar of
/// its views when it has more than one (swipe or tap to switch). Keyed by
/// tab and view, so switching starts the page afresh. With every tab
/// removed, a note pointing to Customize.
Widget pageContent(HomeTab tab, ClientManager manager, Client? filter,
    {required bool phone}) {
  final store = HomeLayoutStore.instance;
  if (store.isEmpty) return NewHomeEmpty(phone: phone, clientManager: manager);
  final views = tab.views;
  if (views.length < 2) {
    return NewHomeOverview(
        key: ValueKey("NewHomeMainPage-${tab.id}"),
        clientManager: manager,
        filterClient: filter,
        phone: phone);
  }
  final shown = store.currentView;
  final index = views.indexWhere((v) => v.id == shown.id);
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    NewHomeViewBar(tab: tab, shown: shown.id, phone: phone),
    Expanded(
      child: TabSwipeDetector(
        canSwipe: (direction) =>
            index + direction >= 0 && index + direction < views.length,
        onSwipe: (direction) =>
            store.showView(tab.id, views[index + direction].id),
        child: NewHomeOverview(
            key: ValueKey("NewHomeMainPage-${tab.id}-${shown.id}"),
            clientManager: manager,
            filterClient: filter,
            phone: phone),
      ),
    ),
  ]);
}

/// A tab's views by name, the shown one underlined (Vommet issue 674).
class NewHomeViewBar extends StatelessWidget {
  const NewHomeViewBar(
      {super.key, required this.tab, required this.shown, required this.phone});

  final HomeTab tab;
  final String shown;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 42,
      decoration: BoxDecoration(
          color: phone ? scheme.surfaceContainerLow : null,
          border: Border(
              bottom: BorderSide(color: scheme.surfaceContainerHighest))),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: phone ? 4 : 12),
        children: [
          for (final view in tab.views)
            _ViewName(
                key: ValueKey("NewHomeView-${view.id}"),
                name: view.name,
                selected: view.id == shown,
                onTap: () =>
                    HomeLayoutStore.instance.showView(tab.id, view.id)),
        ],
      ),
    );
  }
}

class _ViewName extends StatelessWidget {
  const _ViewName(
      {super.key,
      required this.name,
      required this.selected,
      required this.onTap});

  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(
                      width: 3,
                      color: selected ? scheme.primary : Colors.transparent))),
          child: Text(name,
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color:
                      selected ? scheme.onSurface : scheme.onSurfaceVariant)),
        ),
      ),
    );
  }
}

/// Home with every tab removed: says so and offers Customize, where New tab
/// and Reset Home to default are.
class NewHomeEmpty extends StatelessWidget {
  const NewHomeEmpty(
      {super.key, required this.phone, required this.clientManager});

  final bool phone;
  final ClientManager clientManager;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      key: const ValueKey("NewHomeEmpty"),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, spacing: 10, children: [
          Icon(Icons.dashboard_customize_outlined,
              size: 40, color: scheme.onSurfaceVariant),
          Text("Your Home is empty",
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface)),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Text(
                "Every tab was removed. Add a tab, or bring back the "
                "default tabs with Reset Home to default, in Customize.",
                textAlign: TextAlign.center,
                style:
                    TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant)),
          ),
          const SizedBox(height: 4),
          FilledButton.icon(
            key: const ValueKey("NewHomeEmptyCustomize"),
            onPressed: () => customizeOverview(context,
                phone: phone, clientManager: clientManager),
            icon: const Icon(Icons.dashboard_customize_rounded, size: 18),
            label: const Text("Customize"),
          ),
        ]),
      ),
    );
  }
}

/// A tab's main page under its header.
Widget pageBody(HomeTab tab, ClientManager manager, Client? filter,
    {required bool phone, Widget? leading}) {
  final body = pageContent(tab, manager, filter, phone: phone);
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    NewHomeHeader(
        key: ValueKey("NewHomeHeader-${tab.id}"),
        tab: tab,
        phone: phone,
        leading: leading),
    Expanded(child: body),
  ]);
}

/// The tab's title bar: icon and name, the Customize button (and a back or
/// menu button on phones).
class NewHomeHeader extends StatelessWidget {
  const NewHomeHeader(
      {super.key, required this.tab, required this.phone, this.leading});

  final HomeTab tab;
  final bool phone;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 52,
      padding: EdgeInsets.symmetric(horizontal: phone ? 8 : 20),
      decoration: BoxDecoration(
          color: phone ? scheme.surfaceContainerLow : null,
          border: phone
              ? null
              : Border(
                  bottom: BorderSide(color: scheme.surfaceContainerHighest))),
      child: Row(spacing: 10, children: [
        if (leading != null) leading!,
        Icon(homeTabIcon(tab.icon),
            size: phone ? 18 : 20, color: scheme.onSurfaceVariant),
        // The name takes the room left, so Customize sits at the right
        // edge (a Flexible name and an Expanded button area split the
        // width, leaving Customize mid-header on wide windows).
        Expanded(
          child: Text(tab.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface)),
        ),
        _OverviewHeaderActions(phone: phone),
      ]),
    );
  }
}

/// Overview's header: a "Customize" button (customize mode on desktop, the
/// customize screen on phones), or, in customize mode, a "Customizing" tag
/// and how it works.
class _OverviewHeaderActions extends StatelessWidget {
  const _OverviewHeaderActions({required this.phone});
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder(
      valueListenable: newHomeCustomizing,
      builder: (context, customizing, _) {
        if (customizing && !phone) {
          return Expanded(
              flex: 3,
              child: Row(spacing: 10, children: [
                Container(
                  key: const ValueKey("NewHomeCustomizingTag"),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: scheme.primary.withAlpha(40),
                      borderRadius: BorderRadius.circular(6)),
                  child: Text("Customizing",
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: scheme.primary)),
                ),
                Expanded(
                  child: Text(
                      "Drag to reorder · drag back to the library to remove",
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13, color: scheme.onSurfaceVariant)),
                ),
              ]));
        }
        return OutlinedButton.icon(
          key: const ValueKey("NewHomeCustomizeButton"),
          style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor: scheme.onSurface,
              side: BorderSide(color: scheme.outlineVariant),
              padding: const EdgeInsets.symmetric(horizontal: 12)),
          onPressed: () {
            final manager = clientManager;
            if (manager == null) return;
            customizeOverview(context, phone: phone, clientManager: manager);
          },
          icon: const Icon(Icons.dashboard_customize_rounded, size: 18),
          label: const Text("Customize",
              style: TextStyle(fontWeight: FontWeight.w700)),
        );
      },
    );
  }
}
