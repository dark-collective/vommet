import 'package:commet/client/components/donation_awards/donation_awards_component.dart';
import 'package:commet/ui/atoms/adaptive_context_menu.dart';
import 'package:commet/ui/atoms/scaled_safe_area.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/pages/settings/donation_rewards_confirmation.dart';
import 'package:commet/ui/pages/settings/search/settings_search.dart';
import 'package:commet/ui/pages/settings/search/settings_search_entries.dart';
import 'package:commet/ui/pages/settings/settings_button.dart';
import 'package:commet/ui/pages/settings/settings_category.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart' as m;
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';

import 'package:tiamat/tiamat.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class DesktopSettingsPage extends StatefulWidget {
  const DesktopSettingsPage(
      {required this.settings,
      this.buttons,
      this.onDonateButtonTapped,
      this.showDonateButton = false,
      this.initialTab,
      this.initialCategory,
      this.initialHighlight,
      super.key});
  final List<SettingsCategory> settings;

  /// Vommet: label of the tab to select first.
  final String? initialTab;

  /// Vommet: title of the category [initialTab] is in (null: the first tab
  /// with that label). Labels repeat: account and app both have Privacy.
  final String? initialCategory;

  /// Vommet: a setting on that tab to scroll to and flash (its
  /// SettingsSearchTarget id).
  final String? initialHighlight;
  final List<SettingsButton>? buttons;
  final bool showDonateButton;
  final Function(BuildContext context)? onDonateButtonTapped;
  @override
  State<DesktopSettingsPage> createState() => DesktopSettingsPageState();
}

class DesktopSettingsPageState extends State<DesktopSettingsPage> {
  late List<SettingsCategory> categories;
  int selectedCategoryIndex = 0;
  int selectedTabIndex = 0;

  static ValueKey backButtonKey =
      const ValueKey("DESKTOP_SETTINGS_PAGE_BACK_BUTTON");

  // Vommet: below this width the tab list shrinks to an icon rail beside the
  // open tab (Vommet issue 677); tab names show as tooltips.
  static const double railWidth = 560;

  // Vommet: below this width the page goes single-column (Vommet issue 614):
  // the tab list fills the page, and a tab opens full-width with a back
  // arrow and a "Settings › tab" breadcrumb (Vommet issue 677).
  static const double singleColumnWidth = 400;
  static ValueKey tabBackButtonKey =
      const ValueKey("DESKTOP_SETTINGS_PAGE_TAB_BACK_BUTTON");
  static ValueKey railSearchButtonKey =
      const ValueKey("DESKTOP_SETTINGS_PAGE_RAIL_SEARCH_BUTTON");
  bool singleColumn = false;
  bool rail = false;

  /// Rail only: the search box shows above the tab.
  bool railSearchOpen = false;

  /// No slide on the page's first layout, only on later switches.
  bool laidOut = false;

  /// Single-column only: a tab is open (otherwise the tab list shows).
  bool showingTab = false;

  // Vommet: settings search (app settings only).
  late final bool searchable = isAppSettings(widget.settings);
  final TextEditingController searchController = TextEditingController();
  String searchQuery = "";
  List<SettingsSearchHit> searchHits = const [];
  String? highlightId;
  int highlightSerial = 0;

  bool get searching => searchQuery.trim().isNotEmpty;

  void onSearchChanged(String query) {
    setState(() {
      searchQuery = query;
      searchHits = searchAppSettings(query, categories);
    });
  }

  void openSearchHit(SettingsSearchHit hit) {
    setState(() {
      selectedCategoryIndex = hit.categoryIndex;
      selectedTabIndex = hit.tabIndex;
      highlightId = hit.isPage ? null : hit.entry.targetId;
      highlightSerial++;
      showingTab = true;
      railSearchOpen = false;
      searchController.clear();
      searchQuery = "";
      searchHits = const [];
    });
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    categories = widget.settings;
    for (var c = 0; c < categories.length; c++) {
      if (widget.initialCategory != null &&
          categories[c].title != widget.initialCategory) {
        continue;
      }
      final t =
          categories[c].tabs.indexWhere((t) => t.label == widget.initialTab);
      if (t >= 0) {
        selectedCategoryIndex = c;
        selectedTabIndex = t;
        showingTab = true;
        break;
      }
    }
    if (widget.initialHighlight != null) {
      highlightId = widget.initialHighlight;
      highlightSerial++;
    }
    super.initState();
  }

  // Vommet: Esc clears an active search first, then (single-column) goes
  // back from a tab to the tab list, otherwise closes the page.
  void onEscape() {
    if (searchController.text.isNotEmpty) {
      searchController.clear();
      onSearchChanged("");
      return;
    }
    if (rail && railSearchOpen) {
      setState(() => railSearchOpen = false);
      return;
    }
    if (singleColumn && showingTab) {
      setState(() => showingTab = false);
      return;
    }
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): onEscape,
      },
      child: Focus(autofocus: true, child: buildPage(context)),
    );
  }

  Widget buildPage(BuildContext context) {
    return m.Material(
      color: m.Theme.of(context).colorScheme.surface,
      child: Foundation(
        child: LayoutBuilder(builder: (context, constraints) {
          singleColumn = constraints.maxWidth < singleColumnWidth;
          rail = !singleColumn && constraints.maxWidth < railWidth;
          final animate = laidOut && !MediaQuery.of(context).disableAnimations;
          laidOut = true;
          // Vommet issue 677: the wide layout always shows the selected tab,
          // so shrinking the window into single-column keeps it open (with
          // the back arrow) instead of dropping to the tab list.
          if (!singleColumn) showingTab = true;
          if (!singleColumn) return buildColumns(context);
          // Vommet issue 677: the tab slides in from the right, the list from
          // the left, so the switch reads as moving, not vanishing.
          if (showingTab && !searching) {
            return _SlideIn(
                key: const ValueKey("tab"),
                fromRight: true,
                animate: animate,
                child: buildSingleTab(context));
          }
          return _SlideIn(
              key: const ValueKey("list"),
              fromRight: false,
              animate: animate,
              child: tabSelector(context));
        }),
      ),
    );
  }

  // Vommet: single-column tab view, a back arrow to the tab list above it.
  Widget buildSingleTab(BuildContext context) {
    final tab = categories[selectedCategoryIndex].tabs[selectedTabIndex];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Tile.surfaceContainer(
          child: ScaledSafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(children: [
                CircleButton(
                  key: tabBackButtonKey,
                  radius: 25,
                  icon: m.Icons.arrow_back,
                  onPressed: () => setState(() => showingTab = false),
                ),
                const SizedBox(width: 8),
                // Vommet issue 677: say where the back arrow goes.
                tiamat.Text.labelLow(CommonStrings.promptSettings),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: m.Icon(m.Icons.chevron_right,
                      size: 18,
                      color: m.ColorScheme.of(context).onSurfaceVariant),
                ),
                Flexible(child: tiamat.Text.labelEmphasised(tab.label)),
              ]),
            ),
          ),
        ),
        Expanded(
          child: SettingsHighlight(
            targetId: highlightId,
            serial: highlightSerial,
            child: buildContent(scrollable: tab.makeScrollable),
          ),
        ),
      ],
    );
  }

  Widget buildColumns(BuildContext context) {
    final showRailSearch = rail && searchable && (railSearchOpen || searching);
    return Row(
      mainAxisSize: MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        rail ? buildRail(context) : tabSelector(context),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showRailSearch)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: SettingsSearchField(
                      controller: searchController,
                      onChanged: onSearchChanged,
                      autofocus: true),
                ),
              // Keyed so the open tab keeps its state when the rail's search
              // box appears above it, or the sidebar turns into the rail.
              Expanded(
                key: const ValueKey("content"),
                child: searching
                    ? buildSearchResults()
                    : SettingsHighlight(
                        targetId: highlightId,
                        serial: highlightSerial,
                        child: buildContent(
                            scrollable: categories[selectedCategoryIndex]
                                .tabs[selectedTabIndex]
                                .makeScrollable),
                      ),
              ),
            ],
          ),
        )
      ],
    );
  }

  // Vommet: the tab list as icons (Vommet issue 677), between railWidth and
  // singleColumnWidth. Names show as tooltips on hover and long-press.
  Widget buildRail(BuildContext context) {
    return Tile.surfaceContainer(
      caulkPadRight: true,
      caulkPadTop: true,
      caulkPadBottom: true,
      caulkClipTopRight: true,
      caulkClipBottomRight: true,
      caulkBorderRight: true,
      child: ScaledSafeArea(
        child: SizedBox(
          width: 64,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
                child: CircleButton(
                  key: backButtonKey,
                  radius: 20,
                  icon: m.Icons.arrow_back,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              if (searchable)
                railButton(
                    key: railSearchButtonKey,
                    icon: m.Icons.search,
                    label: SettingsSearchField.promptSearchSettings,
                    highlighted: railSearchOpen || searching,
                    onTap: () => setState(() {
                          railSearchOpen = !railSearchOpen;
                          if (!railSearchOpen) {
                            searchController.clear();
                            searchQuery = "";
                            searchHits = const [];
                          }
                        })),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(top: 4),
                  children: [
                    for (var c = 0; c < categories.length; c++) ...[
                      if (c != 0) const tiamat.Seperator(),
                      for (var t = 0; t < categories[c].tabs.length; t++)
                        railButton(
                            icon: categories[c].tabs[t].icon ??
                                m.Icons.circle_outlined,
                            label: categories[c].tabs[t].label,
                            highlighted: !searching &&
                                c == selectedCategoryIndex &&
                                t == selectedTabIndex,
                            color: searching &&
                                    !SettingsSearch.tabHasHit(searchHits, c, t)
                                ? m.ColorScheme.of(context)
                                    .onSurface
                                    .withValues(alpha: 0.38)
                                : null,
                            onTap: () => selectTab(c, t)),
                    ],
                    if (widget.buttons != null) const tiamat.Seperator(),
                    if (widget.buttons != null)
                      for (final b in widget.buttons!)
                        railButton(
                            key: b.key,
                            icon: b.icon ?? m.Icons.circle_outlined,
                            label: b.label,
                            color: b.color,
                            onTap: b.onPress),
                  ],
                ),
              ),
              if (widget.showDonateButton)
                railButton(
                    icon: m.Icons.favorite,
                    label: promptDonate,
                    onTap: () => widget.onDonateButtonTapped?.call(context)),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget railButton(
      {Key? key,
      required IconData icon,
      required String label,
      bool highlighted = false,
      Color? color,
      Function()? onTap}) {
    final scheme = m.ColorScheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Center(
        child: m.Tooltip(
          message: label,
          child: SizedBox(
            width: 44,
            height: 40,
            child: m.Material(
              key: key,
              color: highlighted
                  ? scheme.secondaryContainer
                  : m.Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              clipBehavior: Clip.antiAlias,
              child: m.InkWell(
                mouseCursor: m.WidgetStateMouseCursor.clickable,
                onTap: onTap,
                child: m.Icon(icon,
                    size: 20,
                    color: color ??
                        (highlighted
                            ? scheme.onSecondaryContainer
                            : scheme.onSurfaceVariant)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void selectTab(int categoryIndex, int tabIndex) {
    setState(() {
      selectedCategoryIndex = categoryIndex;
      selectedTabIndex = tabIndex;
      showingTab = true;
      highlightId = null;
      railSearchOpen = false;
      searchController.clear();
      searchQuery = "";
      searchHits = const [];
    });
  }

  Widget buildSearchResults() {
    return fullHeight(Tile(
      caulkPadTop: true,
      caulkPadBottom: true,
      caulkClipTopLeft: true,
      caulkClipBottomLeft: true,
      child: ScaledSafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: SettingsSearchResults(
                query: searchQuery, hits: searchHits, onOpen: openSearchHit),
          ),
        ),
      ),
    ));
  }

  // Vommet: the panel always fills the full height, and the scroll view sits
  // inside it. Before, the Row's loose height (crossAxisAlignment.start) and
  // the scroll view around the Tile shrank the panel to its content, so the
  // theme's foundation (e.g. a background image) showed below short tabs.
  Widget fullHeight(Widget panel) =>
      SizedBox(height: double.infinity, child: panel);

  Widget buildContent({bool scrollable = false}) {
    Widget content = selectedCategoryIndex < categories.length &&
            selectedTabIndex < categories[selectedCategoryIndex].tabs.length
        ? settingsTab(categories[selectedCategoryIndex]
            .tabs[selectedTabIndex]
            .pageBuilder)
        : Container();
    return fullHeight(Tile(
      caulkPadTop: true,
      caulkPadBottom: true,
      caulkClipTopLeft: true,
      caulkClipBottomLeft: true,
      key: ValueKey(selectedTabIndex),
      child: ScaledSafeArea(
          child: scrollable ? SingleChildScrollView(child: content) : content),
    ));
  }

  Widget tabSelector(BuildContext context) {
    return Tile.surfaceContainer(
      caulkPadRight: true,
      caulkPadTop: true,
      caulkPadBottom: true,
      caulkClipTopRight: true,
      caulkClipBottomRight: true,
      caulkBorderRight: true,
      child: ScaledSafeArea(
        child: SizedBox(
          width: singleColumn ? double.infinity : 240,
          child: Column(
            children: [
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Align(
                            alignment: Alignment.centerLeft,
                            child: CircleButton(
                              key: backButtonKey,
                              radius: 25,
                              icon: m.Icons.arrow_back,
                              onPressed: () => Navigator.of(context).pop(),
                            )),
                      ),
                      if (searchable)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                          child: SettingsSearchField(
                              controller: searchController,
                              onChanged: onSearchChanged),
                        ),
                      if (singleColumn && searching)
                        Flexible(
                          child: SingleChildScrollView(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: SettingsSearchResults(
                                  query: searchQuery,
                                  hits: searchHits,
                                  onOpen: openSearchHit),
                            ),
                          ),
                        )
                      else
                        Flexible(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                            child: ListView(children: [
                              ListView.builder(
                                physics: const NeverScrollableScrollPhysics(),
                                shrinkWrap: true,
                                itemCount: categories.length,
                                itemBuilder: (context, categoryIndex) {
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      if (categoryIndex != 0)
                                        const tiamat.Seperator(),
                                      if (categories[categoryIndex].title !=
                                          null)
                                        tiamat.Text.labelLow(
                                            categories[categoryIndex].title!),
                                      tabListBuilder(categoryIndex)
                                    ],
                                  );
                                },
                              ),
                              if (widget.buttons != null) const Seperator(),
                              if (widget.buttons != null)
                                ListView.builder(
                                  physics: const NeverScrollableScrollPhysics(),
                                  shrinkWrap: true,
                                  itemCount: widget.buttons!.length,
                                  itemBuilder: (context, index) {
                                    return button(
                                        key: widget.buttons![index].key,
                                        label: widget.buttons![index].label,
                                        icon: widget.buttons![index].icon,
                                        onTap: widget.buttons![index].onPress,
                                        color: widget.buttons![index].color);
                                  },
                                ),
                            ]),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (widget.showDonateButton)
                buildDonateButton(context,
                    onTap: () => widget.onDonateButtonTapped?.call(context))
            ],
          ),
        ),
      ),
    );
  }

  static String get promptDonate => Intl.message("Donate",
      name: "promptDonate", desc: "Prompt the user to donate to the project");

  static String get promptDonationsRefreshAwards => Intl.message(
      "Refresh Awards",
      name: "promptDonationsRefreshAwards",
      desc:
          "Prompt the user to refresh any awards they may have received for donating to the project");

  static Widget buildDonateButton(BuildContext context, {Function()? onTap}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 2),
      child: AdaptiveContextMenu(
        items: [
          ContextMenuItem(
              text: promptDonationsRefreshAwards,
              icon: m.Icons.refresh,
              onPressed: () async {
                var client = await AdaptiveDialog.pickClient(context);

                if (client != null) {
                  var identifier = await client
                      .getComponent<DonationAwardsComponent>()
                      ?.getClientSecret();
                  if (identifier != null) {
                    AdaptiveDialog.show(
                      context,
                      builder: (context) {
                        return DonationRewardsConfirmation(
                          client: client,
                          identifier: identifier,
                          didOpenDonationWindow: false,
                          since: null,
                        );
                      },
                    );
                  }
                }
              }),
        ],
        child: m.Material(
          clipBehavior: Clip.antiAlias,
          color: m.ColorScheme.of(context).surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          child: m.InkWell(
            mouseCursor: m.WidgetStateMouseCursor.clickable,
            onTap: onTap,
            child: SizedBox(
              width: double.infinity,
              child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: m.Icon(
                          m.Icons.favorite,
                          color: m.ColorScheme.of(context).onSurfaceVariant,
                        ),
                      ),
                      tiamat.Text(
                        promptDonate,
                        color: m.ColorScheme.of(context).onSurface,
                      ),
                    ],
                  )),
            ),
          ),
        ),
      ),
    );
  }

  ListView tabListBuilder(int categoryIndex) {
    return ListView.builder(
      // Vommet: scroll with the whole sidebar, not as its own list.
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemBuilder: (context, tabIndex) {
        return button(
            label: categories[categoryIndex].tabs[tabIndex].label,
            icon: categories[categoryIndex].tabs[tabIndex].icon,
            highlighted: !searching &&
                categoryIndex == selectedCategoryIndex &&
                tabIndex == selectedTabIndex,
            // Vommet: while searching, grey out pages with no match.
            color: searching &&
                    !SettingsSearch.tabHasHit(
                        searchHits, categoryIndex, tabIndex)
                ? m.ColorScheme.of(context).onSurface.withValues(alpha: 0.38)
                : null,
            onTap: () => selectTab(categoryIndex, tabIndex));
      },
      itemCount: categories[categoryIndex].tabs.length,
    );
  }

  Widget button(
      {Key? key,
      required String label,
      IconData? icon,
      bool highlighted = false,
      Color? color,
      Function()? onTap}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 2, 0, 2),
      child: SizedBox(
          key: key,
          height: 40,
          width: singleColumn ? double.infinity : 200,
          child: TextButton(
            label,
            icon: icon,
            highlighted: highlighted,
            onTap: onTap,
            textColor: color,
            iconColor: color,
          )),
    );
  }

  Widget settingsTab(Widget Function(BuildContext context) builder) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: builder(context),
    );
  }
}

// Vommet: slides [child] in from the right (or left) and fades it in once,
// when it replaces the other single-column view (Vommet issue 677).
class _SlideIn extends StatefulWidget {
  const _SlideIn(
      {required this.fromRight,
      required this.animate,
      required this.child,
      super.key});
  final bool fromRight;
  final bool animate;
  final Widget child;

  @override
  State<_SlideIn> createState() => _SlideInState();
}

class _SlideInState extends State<_SlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: widget.animate ? 0 : 1);
  late final Animation<double> curve =
      CurvedAnimation(parent: controller, curve: m.Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    if (widget.animate) controller.forward();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween(
                begin: Offset(widget.fromRight ? 0.25 : -0.25, 0),
                end: Offset.zero)
            .animate(curve),
        child: widget.child,
      ),
    );
  }
}
