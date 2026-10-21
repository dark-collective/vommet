import 'package:commet/config/build_config.dart';
import 'package:commet/ui/atoms/scaled_safe_area.dart';
import 'package:commet/ui/pages/setup/onboarding/onboarding_setup.dart';
import 'package:commet/ui/pages/setup/setup_menu.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/material.dart' as material;
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class SetupPage extends StatefulWidget {
  const SetupPage(this.menus, {super.key});
  final List<SetupMenu> menus;

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  int currentMenuIndex = 0;
  late SetupMenu currentMenu;

  @override
  void initState() {
    super.initState();
    currentMenu = widget.menus[currentMenuIndex];
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      child: Tile.surfaceContainer(
        child: Padding(
          padding: const EdgeInsets.all(BuildConfig.MOBILE ? 10 : 50.0),
          child: ScaledSafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.max,
              children: [
                Flexible(
                  child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Tile.low(
                          child: Column(
                        mainAxisSize: MainAxisSize.max,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: SingleChildScrollView(
                                  child: currentMenu.builder(context)),
                            ),
                          ),
                          Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: buttons(),
                              ),
                              TweenAnimationBuilder(
                                  tween: Tween<double>(
                                      begin: 0,
                                      end: currentMenuIndex /
                                          widget.menus.length),
                                  duration: const Duration(milliseconds: 200),
                                  curve: Curves.easeOutCubic,
                                  builder: (context, value, _) {
                                    return LinearProgressIndicator(
                                      value: value,
                                    );
                                  })
                            ],
                          ),
                        ],
                      ))),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Next on the right; on the onboarding pages (Vommet issue 524) also
  /// Back and "Skip setup", which moves below the others when narrow.
  Widget buttons() {
    final next = tiamat.Button(
      text: CommonStrings.promptNext,
      onTap: goNextMenu,
    );
    final back = canGoBack
        ? tiamat.Button.secondary(
            text: CommonStrings.promptBack,
            onTap: goPreviousMenu,
          )
        : null;
    final skip = currentMenu is OnboardingMenu
        ? material.TextButton(
            key: const ValueKey("onboarding-skip-button"),
            onPressed: skipOnboarding,
            child: material.Text(promptSkipOnboarding),
          )
        : null;

    return LayoutBuilder(builder: (context, constraints) {
      if (skip != null && constraints.maxWidth < 420) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [if (back != null) back, const Spacer(), next]),
            Align(alignment: Alignment.center, child: skip),
          ],
        );
      }
      return Row(
        spacing: 8,
        children: [
          if (back != null) back,
          if (skip != null) skip,
          const Spacer(),
          next,
        ],
      );
    });
  }

  void goNextMenu() {
    currentMenu.submit();
    goToMenu(currentMenuIndex + 1);
  }

  void goToMenu(int newIndex) {
    setState(() {
      currentMenuIndex = newIndex;
    });

    if (newIndex >= widget.menus.length) {
      Navigator.pop(context);
    } else {
      setState(() {
        currentMenuIndex = newIndex;
        currentMenu = widget.menus[currentMenuIndex];
      });
    }
  }

  /// Vommet: back to the previous page, among the onboarding pages only (the
  /// other setup pages act when you leave them).
  bool get canGoBack =>
      currentMenu is OnboardingMenu &&
      currentMenuIndex > 0 &&
      widget.menus[currentMenuIndex - 1] is OnboardingMenu;

  void goPreviousMenu() => goToMenu(currentMenuIndex - 1);

  /// Vommet: past the remaining onboarding pages; what was picked so far
  /// stays, the rest keeps its defaults.
  void skipOnboarding() {
    OnboardingSetup.markShown();
    var next = currentMenuIndex;
    while (next < widget.menus.length && widget.menus[next] is OnboardingMenu) {
      next++;
    }
    goToMenu(next);
  }

  String get promptSkipOnboarding => Intl.message("Skip setup",
      name: "promptSkipOnboarding",
      desc:
          "Button on the first-run onboarding pages that skips the remaining pages");
}
