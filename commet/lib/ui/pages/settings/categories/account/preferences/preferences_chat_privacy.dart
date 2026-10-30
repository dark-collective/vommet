import 'package:commet/client/client.dart';
import 'package:commet/client/components/invitation/invitation_component.dart';
import 'package:commet/client/components/user_presence/user_presence_component.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/organisms/invitation_view/invite_strings.dart';
import 'package:commet/ui/pages/settings/categories/app/boolean_toggle.dart';
import 'package:commet/utils/error_utils.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class ChatPrivacyPreferences<T extends Client> extends StatefulWidget {
  const ChatPrivacyPreferences({required this.client, super.key});
  final T client;

  @override
  State<ChatPrivacyPreferences> createState() => _ChatPrivacyPreferences();
}

class _ChatPrivacyPreferences extends State<ChatPrivacyPreferences> {
  UserPresenceComponent get userPresenceComponent =>
      widget.client.getComponent<UserPresenceComponent>()!;

  InvitationComponent get invitationsComponent =>
      widget.client.getComponent<InvitationComponent>()!;

  String get labelChatPrivacyTitle => Intl.message("Chat Privacy",
      desc: "Header for the chat privacy section in settings",
      name: "labelChatPrivacyTitle");

  String get labelPublicReadReceiptsToggle => Intl.message("Read receipts",
      desc:
          "Label for the toggle for enabling and disabling sending read receipts",
      name: "labelPublicReadReceiptsToggle");

  String get labelPublicReadReceiptsDescription => Intl.message(
      "Let other members of a room know when you have read their messages.",
      desc:
          "description for the toggle for enabling and disabling sending read receipts",
      name: "labelPublicReadReceiptsDescription");

  String get labelTypingIndicatorsToggle => Intl.message("Typing indicator",
      desc:
          "Label for the toggle for enabling and disabling sending typing indicator",
      name: "labelTypingIndicatorsToggle");

  String get labelPublicTypingIndicatorDescription => Intl.message(
      "Let other members of a room know when you are typing a message.",
      desc:
          "description for the toggle for enabling and disabling sending typing indicator",
      name: "labelPublicTypingIndicatorDescription");

  String get labelAllowInvitationsToggle => Intl.message("Allow invitations",
      desc:
          "Label for the toggle for enabling and disabling the automatic blocking of invitations",
      name: "labelAllowInvitationsToggle");

  String get labelAllowInvitationsDescription => Intl.message(
      "Allow other users to invite you to rooms.",
      desc:
          "description for the toggle for enabling and disabling the automatic blocking of invitations",
      name: "labelAllowInvitationsDescription");

  String get labelGhostModeToggle => Intl.message("Ghost mode",
      desc:
          "Label for the switch that turns off read receipts and the typing indicator in every room",
      name: "labelGhostModeToggle");

  String get labelGhostModeDescription => Intl.message(
      "Read messages without anyone knowing: no read receipts and no typing indicator, in every room.",
      desc: "Description for the ghost mode switch",
      name: "labelGhostModeDescription");

  String get labelOffWhileGhostMode => Intl.message(
      "Off while Ghost mode is on.",
      desc:
          "Shown under the read receipt and typing switches while ghost mode overrides them",
      name: "labelOffWhileGhostMode");

  String get labelCleanSentLinksToggle => Intl.message("Clean links I send",
      desc:
          "Label for the switch that removes tracking parameters from links in sent messages",
      name: "labelCleanSentLinksToggle");

  String get labelCleanSentLinksDescription => Intl.message(
      "Removes tracking parts (utm_source, fbclid, si=…) from links before they are sent.",
      desc: "Description for the clean links I send switch",
      name: "labelCleanSentLinksDescription");

  late bool ghostMode;

  @override
  void initState() {
    ghostMode = userPresenceComponent.ghostMode;
    super.initState();
  }

  /// Vommet: the separate switches stay, grayed out while ghost mode
  /// overrides them.
  Widget overriddenByGhost(Widget child) {
    if (!ghostMode) return child;
    return IgnorePointer(child: Opacity(opacity: 0.5, child: child));
  }

  @override
  Widget build(BuildContext context) {
    return tiamat.Panel(
      header: labelChatPrivacyTitle,
      mode: tiamat.TileType.surfaceContainerLow,
      child: Column(children: [
        BooleanToggle(
          setValue: (value) async {
            await ErrorUtils.tryRun(context, () async {
              await userPresenceComponent.setGhostMode(value);
            });
            if (mounted) setState(() => ghostMode = value);
          },
          getValue: () => userPresenceComponent.ghostMode,
          title: labelGhostModeToggle,
          description: labelGhostModeDescription,
        ),
        overriddenByGhost(BooleanToggle(
          key: ValueKey("read_receipts_$ghostMode"),
          setValue: (value) async {
            await ErrorUtils.tryRun(context, () async {
              await userPresenceComponent.setUsePublicReadReceipts(value);
            });
          },
          getValue: () =>
              !ghostMode && userPresenceComponent.usePublicReadReceipts,
          title: labelPublicReadReceiptsToggle,
          description: ghostMode
              ? labelOffWhileGhostMode
              : labelPublicReadReceiptsDescription,
        )),
        overriddenByGhost(BooleanToggle(
          key: ValueKey("typing_$ghostMode"),
          setValue: (value) async {
            await ErrorUtils.tryRun(context, () async {
              await userPresenceComponent.setTypingIndicatorEnabled(value);
            });
          },
          getValue: () =>
              !ghostMode && userPresenceComponent.typingIndicatorEnabled,
          title: labelTypingIndicatorsToggle,
          description: ghostMode
              ? labelOffWhileGhostMode
              : labelPublicTypingIndicatorDescription,
        )),
        BooleanToggle(
          setValue: (value) async {
            await preferences.cleanSentLinks.set(value);
          },
          getValue: () => preferences.cleanSentLinks.value,
          title: labelCleanSentLinksToggle,
          description: labelCleanSentLinksDescription,
        ),
        BooleanToggle(
          setValue: (value) async {
            await ErrorUtils.tryRun(context, () async {
              await invitationsComponent.setInvitationsAllowed(value);
            });
          },
          getValue: () => invitationsComponent.allowInvitations,
          title: labelAllowInvitationsToggle,
          description: labelAllowInvitationsDescription,
        ),
        // Vommet: the rest of the invite settings live on their own page.
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: tiamat.Text.labelLow(inviteSettingsPointer),
          ),
        ),
      ]),
    );
  }
}
