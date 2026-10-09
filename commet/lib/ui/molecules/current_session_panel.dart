import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/profile/profile_component.dart';
import 'package:commet/client/components/user_presence/user_presence_component.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/components/widgets/widget_component.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/adaptive_context_menu.dart';
import 'package:commet/ui/molecules/call_sessions_panel.dart';
import 'package:commet/ui/molecules/profile_quick_card.dart';
import 'package:commet/ui/molecules/self_voice_controls.dart';
import 'package:commet/ui/molecules/user_panel.dart' show UserPanelView;
import 'package:commet/ui/molecules/user_panel_settings.dart';
import 'package:commet/ui/molecules/widget_sessions_panel.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/material.dart';

import 'package:tiamat/tiamat.dart' as tiamat;

class CurrentSessionPanel extends StatefulWidget {
  const CurrentSessionPanel({this.currentUser, super.key});
  final Profile? currentUser;

  @override
  State<CurrentSessionPanel> createState() => _CurrentSessionPanelState();
}

class _CurrentSessionPanelState extends State<CurrentSessionPanel> {
  double get profileHeight => MediaQuery.of(context).mobile ? 60 : 50;

  Profile? currentUser;

  late List<StreamSubscription> subs;

  @override
  void initState() {
    currentUser = widget.currentUser;
    subs = [
      WidgetComponent.currentSessions.onListUpdated.listen((_) {
        setState(() {});
      }),
      clientManager!.callManager.currentSessions.onListUpdated.listen((_) {
        setState(() {});
      }),
      preferences.experimentQuickProfileControls.onChanged
          .listen((_) => setState(() {})),
    ];
    super.initState();
  }

  @override
  void dispose() {
    for (var sub in subs) {
      sub.cancel();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CurrentSessionPanel oldWidget) {
    setState(() {
      currentUser = widget.currentUser;
    });

    super.didUpdateWidget(oldWidget);
  }

  @override
  Widget build(BuildContext context) {
    Profile? current = widget.currentUser;

    if (clientManager!.clients.length == 1) {
      current = clientManager!.clients.first.self;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 0, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (WidgetComponent.currentSessions.isNotEmpty)
            Padding(
                padding: EdgeInsetsGeometry.fromLTRB(4, 4, 4, 0),
                child: SizedBox(
                    height: 40,
                    child: WidgetSessionsPanel(
                      height: 40,
                    ))),
          if (clientManager!.callManager.currentSessions.isNotEmpty)
            Padding(
              padding: EdgeInsetsGeometry.fromLTRB(4, 4, 4, 0),
              child: CallSessionsPanel(
                height: 40,
              ),
            ),
          Material(
            color: Colors.transparent,
            child: Container(
                child: AdaptiveContextMenu(
              modal: true,
              items: [
                if (clientManager!.clients.length > 1)
                  tiamat.ContextMenuItem(
                      text: "Mix Accounts",
                      onPressed: () {
                        EventBus.setFilterClient.add(null);
                        preferences.filterClient.set(null);
                      }),
                if (clientManager!.clients.length > 1)
                  ...clientManager!.clients
                      .map((i) => tiamat.ContextMenuItem(
                          text: i.self!.identifier,
                          onPressed: () {
                            print("Setting filter client");
                            EventBus.setFilterClient.add(i);
                            preferences.filterClient.set(i.identifier);
                          }))
                      .toList()
              ],
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  spacing: 4,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Builder(
                          builder: (rowContext) => InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: quickProfile
                                    ? () => openProfileCard(rowContext, current)
                                    : null,
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 2),
                                  child: profileSummary(context, current),
                                ),
                              )),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SelfVoiceControls(size: profileHeight * 0.6),
                        UserPanelSettings(
                          height: profileHeight,
                        ),
                      ],
                    )
                  ],
                ),
              ),
            )),
          ),
        ],
      ),
    );
  }

  /// Vommet: the account the profile card is for: the one shown, or the
  /// first when several are mixed.
  Client? clientFor(Profile? profile) {
    final clients = clientManager!.clients;
    return clients
            .where((c) => c.self?.identifier == profile?.identifier)
            .firstOrNull ??
        clients.firstOrNull;
  }

  /// The profile card, presence and status sit behind an experiment.
  bool get quickProfile => preferences.experimentQuickProfileControls.value;

  Future<void> openProfileCard(BuildContext context, Profile? profile) async {
    final client = clientFor(profile);
    if (client == null) return;
    await ProfileQuickCard.show(context, client: client);
    if (mounted) setState(() {});
  }

  UserPresenceStatus presenceOf(Profile? profile) {
    final mode =
        clientFor(profile)?.getComponent<UserPresenceComponent>()?.presenceMode;
    return switch (mode) {
      "idle" => UserPresenceStatus.unavailable,
      "invisible" => UserPresenceStatus.offline,
      _ => UserPresenceStatus.online,
    };
  }

  Widget avatarWithPresence(Profile profile, double radius) {
    return Stack(
      alignment: Alignment.bottomRight,
      clipBehavior: Clip.none,
      children: [
        tiamat.Avatar(
          radius: radius,
          image: profile.avatar,
          placeholderColor: profile.defaultColor,
          placeholderText: profile.displayName,
        ),
        if (quickProfile)
          Positioned(
            right: -1,
            bottom: -1,
            child:
                UserPanelView.createPresenceIcon(context, presenceOf(profile)),
          ),
      ],
    );
  }

  // Vommet: avatar with presence, name, and "In voice" or the presence
  // underneath, as in Discord's user panel.
  Widget profileSummary(BuildContext context, Profile? current) {
    if (current == null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: clientManager!.clients
            .where((i) => i.self != null)
            .map((i) => avatarWithPresence(i.self!, 12))
            .toList(),
      );
    }

    final inVoice = clientManager!.callManager.currentSessions.any(
        (s) => s.state != VoipState.incoming && s.state != VoipState.ended);
    final presence = presenceOf(current);
    final subtitle = inVoice
        ? "In voice"
        : !quickProfile
            ? current.identifier
            : switch (presence) {
                UserPresenceStatus.unavailable => "Idle",
                UserPresenceStatus.offline => "Invisible",
                _ => "Online",
              };

    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        avatarWithPresence(current, 14),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              tiamat.Text.name(
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  color: current.defaultColor,
                  current.displayName),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 11,
                    color: inVoice
                        ? UserPresenceStatus.online.getColor()
                        : Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
