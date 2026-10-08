import 'dart:async';

import 'package:commet/client/components/push_notification/android/unified_push_notifier.dart';
import 'package:commet/client/components/push_notification/notification_manager.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/pages/setup/setup_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';

import 'package:tiamat/tiamat.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:unifiedpush/unifiedpush.dart';

class UnifiedPushSetup implements SetupMenu {
  StreamController<SetupMenuState> controller = StreamController();
  GlobalKey key = GlobalKey();
  @override
  Widget builder(BuildContext context) {
    return UnifiedPushSetupView(key: key);
  }

  @override
  Stream<SetupMenuState> get onStateChanged => controller.stream;

  @override
  SetupMenuState state = SetupMenuState.canProgress;

  @override
  Future<void> submit() async {
    NotificationManager.init();
    if (preferences.unifiedPushEnabled.value == null) {
      preferences.unifiedPushEnabled.set(false);
    }
  }
}

class UnifiedPushSetupView extends StatefulWidget {
  const UnifiedPushSetupView({super.key, this.onToggled});
  final Function(bool enabled)? onToggled;

  @override
  State<UnifiedPushSetupView> createState() => UnifiedPushSetupViewState();
}

class UnifiedPushSetupViewState extends State<UnifiedPushSetupView> {
  bool unifiedPushEnabled = false;
  bool loading = true;
  bool wasUnifiedPushAlreadyConfigured = false;
  UnifiedPushNotifier? notifier;

  String? endpoint;

  // Vommet: distributor apps found on the device, and the one in use.
  List<String>? distributors;
  String? distributor;

  String get unifiedPushExplainer => Intl.message("""
# Unified Push
This version of Vommet was built without Google Play Services. In order to receive push notifications, you will need to use [Unified Push](https://unifiedpush.org/). 

If you already have a Unified Push compatible distributor app installed, you can configure it below
""",
      name: "unifiedPushExplainer",
      desc: "Explains the need for unified push. Supports markdown");

  String get labelEnableUnifiedPush => Intl.message("Enable Unified Push",
      name: "labelEnableUnifiedPush",
      desc: "Label for the toggle to enable Unified Push");

  String get labelEnableUnifiedPushEndpoint => Intl.message("Endpoint",
      name: "labelEnableUnifiedPushEndpoint",
      desc: "Label for the Unified Push endpoint");

  String get labelUnifiedPushNoEndpointFound => Intl.message(
      "No endpoint found, something went wrong :(",
      name: "labelUnifiedPushNoEndpointFound",
      desc: "Message for when a unified push endpoint could not be registered");

  String get labelDistributor => Intl.message("Distributor",
      name: "labelUnifiedPushDistributor",
      desc: "Label for the UnifiedPush distributor app in use");

  String get labelNoDistributor => Intl.message(
      "No UnifiedPush distributor app found on this device. Install one, "
      "for example ntfy or Sunup, then tap Check again.",
      name: "labelUnifiedPushNoDistributor",
      desc: "Shown when no UnifiedPush distributor app is installed");

  String get promptCheckAgain => Intl.message("Check again",
      name: "promptUnifiedPushCheckAgain",
      desc: "Button to look for UnifiedPush distributor apps again");

  String get promptChangeDistributor => Intl.message("Change",
      name: "promptUnifiedPushChangeDistributor",
      desc: "Button to pick a different UnifiedPush distributor app");

  String get labelPickDistributor => Intl.message("Pick a distributor",
      name: "labelUnifiedPushPickDistributor",
      desc: "Title of the list of UnifiedPush distributor apps");

  /// Friendly names for common distributors; others show their package name.
  static const knownDistributors = {
    "io.heckel.ntfy": "ntfy",
    "org.unifiedpush.distributor.sunup": "Sunup",
    "org.unifiedpush.distributor.nextpush": "NextPush",
    "org.unifiedpush.distributor.fcm": "FCM distributor",
    "com.github.gotify": "Gotify",
  };

  static String distributorName(String package) =>
      knownDistributors[package] ?? package;

  @override
  void initState() {
    wasUnifiedPushAlreadyConfigured =
        preferences.unifiedPushEnabled.value != null;
    notifier = NotificationManager.notifier as UnifiedPushNotifier?;
    notifier?.onEndpointChanged.stream.listen((event) => onEndpointChanged());
    unifiedPushEnabled = preferences.unifiedPushEnabled.value == true;

    getInitialToken();
    if (unifiedPushEnabled) refreshDistributors();

    if (wasUnifiedPushAlreadyConfigured) {
      loading = false;
    }

    super.initState();
  }

  void getInitialToken() async {
    var token = await notifier?.getToken();
    setState(() {
      endpoint = token;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (!wasUnifiedPushAlreadyConfigured)
          MarkdownBody(data: unifiedPushExplainer),
        if (!wasUnifiedPushAlreadyConfigured) const Seperator(),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            tiamat.Text.label(labelEnableUnifiedPush),
            tiamat.Switch(
              state: unifiedPushEnabled,
              onChanged: (value) {
                widget.onToggled?.call(value);

                setState(() {
                  unifiedPushEnabled = value;
                });

                if (value) {
                  enableUnifiedPush();
                } else {
                  disableUnifiedPush();
                }
              },
            ),
          ],
        ),
        if (unifiedPushEnabled)
          Align(
              alignment: Alignment.centerLeft, child: buildUnifiedPushDetails())
      ],
    );
  }

  Widget buildUnifiedPushDetails() {
    if (loading) {
      return const CircularProgressIndicator();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8.0, 0, 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          ...buildDistributorDetails(),
          const SizedBox(height: 8),
          tiamat.Text.label(labelEnableUnifiedPushEndpoint + ":"),
          tiamat.Text.labelLow(
              endpoint == null ? labelUnifiedPushNoEndpointFound : endpoint!),
        ],
      ),
    );
  }

  void onEndpointChanged() async {
    setState(() {
      endpoint = notifier?.endpoint;
    });
  }

  // Vommet: our own distributor flow instead of the deprecated
  // registerAppWithDialog, which (1) never offered a choice again once any
  // distributor had been saved, even one since uninstalled, and (2) went
  // silent for good after its "no distributor" dialog was dismissed once.
  // Either looked like "Vommet doesn't recognise my distributor".
  List<Widget> buildDistributorDetails() {
    final found = distributors;
    if (found == null) return const [];
    if (found.isEmpty) {
      return [
        tiamat.Text.labelLow(labelNoDistributor),
        const SizedBox(height: 4),
        tiamat.Button.secondary(
            text: promptCheckAgain, onTap: () => pickAndRegister()),
      ];
    }
    return [
      tiamat.Text.label("$labelDistributor:"),
      Row(spacing: 8, children: [
        Flexible(
          child: tiamat.Text.labelLow(distributor == null
              ? "—"
              : "${distributorName(distributor!)} ($distributor)"),
        ),
        tiamat.Button.secondary(
            text: promptChangeDistributor,
            onTap: () => pickAndRegister(forcePick: true)),
      ]),
    ];
  }

  Future<void> refreshDistributors() async {
    try {
      final found = await UnifiedPush.getDistributors([]);
      final current = await UnifiedPush.getDistributor();
      Log.i("UnifiedPush distributors found: ${found.join(", ")}; "
          "current: $current");
      if (mounted) {
        setState(() {
          distributors = found;
          distributor = current;
        });
      }
    } catch (e, s) {
      Log.onError(e, s, content: "Could not list UnifiedPush distributors");
    }
  }

  /// Lists the distributors on the device, keeps the current one if it's
  /// still installed (unless [forcePick]), otherwise uses the only one or
  /// asks, then registers with it.
  Future<void> pickAndRegister({bool forcePick = false}) async {
    await refreshDistributors();
    final found = distributors ?? const [];
    if (found.isEmpty) return;

    String? pick;
    if (!forcePick && distributor != null && found.contains(distributor)) {
      pick = distributor;
    } else if (found.length == 1) {
      pick = found.single;
    } else if (mounted) {
      pick = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: tiamat.Text.largeTitle(labelPickDistributor),
          children: [
            for (final d in found)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, d),
                child: tiamat.Text.label("${distributorName(d)}  ($d)"),
              ),
          ],
        ),
      );
    }
    if (pick == null) return;

    await UnifiedPush.saveDistributor(pick);
    await UnifiedPush.registerApp();
    if (mounted) setState(() => distributor = pick);
  }

  void enableUnifiedPush() async {
    preferences.unifiedPushEnabled.set(true);
    await notifier?.init();

    await pickAndRegister();

    if (!mounted) return;
    setState(() {
      loading = false;
      endpoint = notifier?.endpoint;
    });
  }

  void disableUnifiedPush() async {
    await notifier?.unregister();
    setState(() {
      loading = false;
      endpoint = null;
    });
  }
}
