// Vommet issue 727: the Settings › Privacy panel for privacy-friendly
// frontends, the small marker shown after a link that opens on one, and
// their strings. The rewriting itself is in alt_frontends.dart.

import 'dart:async';

import 'package:commet/config/build_config.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/pages/settings/categories/app/boolean_preference_toggle.dart';
import 'package:commet/utils/links/alt_frontends.dart';
import 'package:commet/utils/links/link_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// The marker after a link that opens on a frontend: the frontend's name,
/// a tooltip saying so, and a menu to open or copy the original link.
class AltFrontendMarker extends StatelessWidget {
  const AltFrontendMarker(
      {required this.service,
      required this.original,
      this.clientId,
      super.key});

  final AltFrontendService service;
  final Uri original;
  final String? clientId;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    return Tooltip(
      message: altFrontendMarkerTooltip(service.frontend),
      child: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Material(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTapDown: (details) => _showMenu(context, details.globalPosition),
            onTap: () {},
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              child: Text("↪ ${service.frontend}",
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: scheme.onPrimaryContainer)),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showMenu(BuildContext context, Offset position) async {
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx, position.dy),
      items: [
        PopupMenuItem(value: "open", child: Text(altFrontendOpenOriginal)),
        PopupMenuItem(value: "copy", child: Text(altFrontendCopyOriginal)),
      ],
    );
    if (!context.mounted) return;
    switch (choice) {
      case "open":
        LinkUtils.open(original,
            clientId: clientId, context: context, useAltFrontends: false);
      case "copy":
        Clipboard.setData(ClipboardData(text: original.toString()));
    }
  }
}

/// Settings › Privacy › Privacy-friendly frontends.
class AltFrontendsPanel extends StatefulWidget {
  const AltFrontendsPanel({super.key});

  @override
  State<AltFrontendsPanel> createState() => _AltFrontendsPanelState();
}

class _AltFrontendsPanelState extends State<AltFrontendsPanel> {
  final List<StreamSubscription> subscriptions = [];

  @override
  void initState() {
    super.initState();
    for (final stream in [
      preferences.altFrontendsEnabled.onChanged,
      preferences.altFrontendsServices.onChanged,
      preferences.altFrontendsInstances.onChanged,
      preferences.altFrontendsCustomInstances.onChanged,
    ]) {
      subscriptions.add(stream.listen((_) {
        if (mounted) setState(() {});
      }));
    }
  }

  @override
  void dispose() {
    for (final s in subscriptions) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: tiamat.Panel(
        header: altFrontendsHeader,
        mode: tiamat.TileType.surfaceContainerLow,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BooleanPreferenceToggle(
              preference: preferences.altFrontendsEnabled,
              title: altFrontendsToggleTitle,
              description: altFrontendsToggleDescription,
            ),
            if (AltFrontends.enabled) ...[
              const SizedBox(height: 8),
              for (final service in AltFrontends.services)
                _serviceRow(context, service),
              const SizedBox(height: 8),
              tiamat.Text.labelLow(altFrontendsInstanceListNote),
            ],
          ],
        ),
      ),
    );
  }

  Widget _serviceRow(BuildContext context, AltFrontendService service) {
    final on = AltFrontends.isServiceOn(service);
    final selected = AltFrontends.selectedInstances(service);
    final instanceLabel = selected.isEmpty
        ? altFrontendsPickInstance
        : selected.length == 1
            ? selected.first
            : altFrontendsRandomInstance(selected.length);
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                tiamat.Text.label(service.name),
                tiamat.Text.labelLow(service.frontend),
              ],
            ),
          ),
          Flexible(
            child: OutlinedButton(
              onPressed: () => _pickInstances(context, service),
              child: Text(instanceLabel, overflow: TextOverflow.ellipsis),
            ),
          ),
          const SizedBox(width: 8),
          tiamat.Switch(
            state: on && selected.isNotEmpty,
            onChanged: (value) async {
              if (value && selected.isEmpty) {
                final picked = await _pickInstances(context, service);
                if (picked == null || picked.isEmpty) return;
              }
              await AltFrontends.setServiceOn(service, value);
            },
          ),
        ],
      ),
    );
    // Vommet issue 175: YouTube videos play inside Vommet via Invidious.
    if (service.id != "youtube" || !on || selected.isEmpty || BuildConfig.WEB) {
      return row;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row,
        Padding(
          padding: const EdgeInsets.only(left: 16),
          child: BooleanPreferenceToggle(
            preference: preferences.altFrontendsYoutubePlayback,
            title: altFrontendsPlaybackTitle,
            description: altFrontendsPlaybackDescription,
          ),
        ),
      ],
    );
  }

  Future<List<String>?> _pickInstances(
      BuildContext context, AltFrontendService service) async {
    final picked = await AdaptiveDialog.show<List<String>>(context,
        title: altFrontendsPickerTitle(service.name, service.frontend),
        builder: (context) => _InstancePicker(service: service));
    if (picked == null) return null;
    await AltFrontends.setSelectedInstances(service, picked);
    if (picked.isEmpty) await AltFrontends.setServiceOn(service, false);
    return picked;
  }
}

class _InstancePicker extends StatefulWidget {
  const _InstancePicker({required this.service});

  final AltFrontendService service;

  @override
  State<_InstancePicker> createState() => _InstancePickerState();
}

class _InstancePickerState extends State<_InstancePicker> {
  late final Set<String> selected =
      AltFrontends.selectedInstances(widget.service).toSet();

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final custom = AltFrontends.customInstances(service);
    return SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          tiamat.Text.labelLow(altFrontendsPickerDescription),
          const SizedBox(height: 8),
          for (final host in AltFrontends.allInstances(service))
            Row(children: [
              Checkbox(
                value: selected.contains(host),
                onChanged: (value) => setState(() =>
                    value == true ? selected.add(host) : selected.remove(host)),
              ),
              Expanded(child: Text(host)),
              if (custom.contains(host) && !service.instances.contains(host))
                IconButton(
                  tooltip: altFrontendsRemoveInstance,
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () async {
                    await AltFrontends.removeCustomInstance(service, host);
                    setState(() => selected.remove(host));
                  },
                ),
            ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: tiamat.Button.secondary(
                text: altFrontendsAddInstance,
                onTap: () => _addInstance(context),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: tiamat.Button(
                text: altFrontendsDone,
                onTap: () => Navigator.of(context).pop(selected.toList()),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Future<void> _addInstance(BuildContext context) async {
    final text = await AdaptiveDialog.textPrompt(context,
        title: altFrontendsAddInstance,
        submitText: altFrontendsAdd,
        hintText: "https://");
    if (text == null) return;
    final host = AltFrontends.normalizeInstance(text);
    if (host == null) return;
    await AltFrontends.addCustomInstance(widget.service, host);
    setState(() => selected.add(host));
  }
}

String get altFrontendsHeader => Intl.message("Privacy-friendly frontends",
    name: "altFrontendsHeader",
    desc: "Header of the privacy settings panel that opens links to services "
        "like YouTube on alternative frontends like Invidious");

String get altFrontendsToggleTitle =>
    Intl.message("Open links on alternative frontends",
        name: "altFrontendsToggleTitle",
        desc: "Switch that turns on opening links on alternative frontends");

String get altFrontendsToggleDescription => Intl.message(
    "Only on this device and only for you: messages, and links you send, stay as written. The original link is always one tap away.",
    name: "altFrontendsToggleDescription",
    desc: "Explanation under the alternative frontends switch");

String get altFrontendsInstanceListNote => Intl.message(
    "The list of instances comes with Vommet; nothing is looked up online.",
    name: "altFrontendsInstanceListNote",
    desc: "Note under the list of services with alternative frontends");

String get altFrontendsPickInstance => Intl.message("Pick an instance",
    name: "altFrontendsPickInstance",
    desc: "Button on a service's row when no frontend instance is picked yet");

String altFrontendsRandomInstance(int count) =>
    Intl.message("Random from $count instances",
        name: "altFrontendsRandomInstance",
        args: [count],
        desc: "Button on a service's row when several instances are picked; "
            "one is chosen at random for each link",
        examples: const {"count": 3});

String altFrontendsPickerTitle(String service, String frontend) =>
    Intl.message("$service on $frontend",
        name: "altFrontendsPickerTitle",
        args: [service, frontend],
        desc: "Title of the dialog that picks frontend instances for a service",
        examples: const {"service": "YouTube", "frontend": "Invidious"});

String get altFrontendsPickerDescription => Intl.message(
    "Pick one instance, or several to use a random one for each link.",
    name: "altFrontendsPickerDescription",
    desc: "Explanation at the top of the frontend instance picker");

String get altFrontendsAddInstance => Intl.message("Add your own instance",
    name: "altFrontendsAddInstance",
    desc: "Button in the instance picker that adds a frontend instance by URL");

String get altFrontendsAdd => Intl.message("Add",
    name: "altFrontendsAdd",
    desc: "Submit button of the dialog that adds a frontend instance");

String get altFrontendsRemoveInstance => Intl.message("Remove",
    name: "altFrontendsRemoveInstance",
    desc: "Tooltip of the button that removes an instance the user added");

String get altFrontendsDone => Intl.message("Done",
    name: "altFrontendsDone",
    desc: "Button that closes the frontend instance picker");

String altFrontendMarkerTooltip(String frontend) =>
    Intl.message("Opens on $frontend, only for you",
        name: "altFrontendMarkerTooltip",
        args: [frontend],
        desc: "Tooltip of the marker after a link that opens on an "
            "alternative frontend",
        examples: const {"frontend": "Invidious"});

String get altFrontendOpenOriginal => Intl.message("Open Original Link",
    name: "altFrontendOpenOriginal",
    desc: "Button or menu item that opens a link on its original site "
        "instead of the alternative frontend");

String get altFrontendCopyOriginal => Intl.message("Copy Original Link",
    name: "altFrontendCopyOriginal",
    desc: "Menu item that copies a link's original address");

String altFrontendOpenTitle(String frontend) =>
    Intl.message("Open on $frontend?",
        name: "altFrontendOpenTitle",
        args: [frontend],
        desc: "Title of the prompt before opening a link on an alternative "
            "frontend",
        examples: const {"frontend": "Invidious"});

String altFrontendOpenButton(String frontend) =>
    Intl.message("Open on $frontend",
        name: "altFrontendOpenButton",
        args: [frontend],
        desc: "Button that opens a link on the alternative frontend",
        examples: const {"frontend": "Invidious"});

String altFrontendOpenPrompt(String service, String instance, String url) =>
    Intl.message(
        "Your frontend setting opens this $service link on $instance (trackers removed too):\n`$url`",
        name: "altFrontendOpenPrompt",
        args: [service, instance, url],
        desc: "Prompt before opening a link on an alternative frontend",
        examples: const {
          "service": "YouTube",
          "instance": "inv.example.org",
          "url": "https://inv.example.org/watch?v=abc"
        });

String get altFrontendsPlaybackTitle => Intl.message(
    "Play videos inside Vommet",
    name: "altFrontendsPlaybackTitle",
    desc: "Switch under YouTube in the alternative frontends settings: "
        "YouTube links play in the chat through the picked Invidious instance");

String get altFrontendsPlaybackDescription => Intl.message(
    "Link previews get a player that streams from your Invidious instance when you press play, with fullscreen. Nothing loads before that.",
    name: "altFrontendsPlaybackDescription",
    desc: "Explanation under the Play videos inside Vommet switch");
