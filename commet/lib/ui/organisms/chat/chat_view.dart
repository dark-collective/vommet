import 'package:commet/client/components/account_switch_prefix/account_switch_prefix.dart';
import 'package:commet/client/components/push_notification/notification_manager.dart';
import 'package:commet/ui/molecules/blocked_dm_notice.dart';
import 'package:commet/client/room.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/ui/atoms/encryption_marker.dart';
import 'package:commet/ui/molecules/dm_trust_banner.dart';
import 'package:commet/ui/molecules/message_input.dart';
import 'package:commet/ui/molecules/room_timeline_widget/room_timeline_widget.dart';
import 'package:commet/ui/molecules/typing_indicators_widget.dart';
import 'package:commet/ui/organisms/chat/chat.dart';
import 'package:commet/ui/organisms/particle_player/particle_player.dart';
import 'package:commet/utils/autofill_utils.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:commet/ui/organisms/forward_message/forward_bar.dart';
import 'package:commet/ui/organisms/message_selection/message_selection_host.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:commet/ui/molecules/composer_notice.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/utils/common_strings.dart';

class ChatView extends StatelessWidget {
  const ChatView(this.state, {super.key});
  final ChatState state;

  String get sendEncryptedMessagePrompt =>
      Intl.message("Send an encrypted message",
          name: "sendEncryptedMessagePrompt",
          desc: "Placeholder text for message input in an encrypted room");

  String get sendUnencryptedMessagePrompt => Intl.message("Send a message",
      name: "sendUnencryptedMessagePrompt",
      desc: "Placeholder text for message input in an unencrypted room");

  // Vommet: with encryption markers on, unencrypted rooms say so.
  String get sendUnencryptedMessageExplicitPrompt => Intl.message(
      "Send an unencrypted message",
      name: "sendUnencryptedMessageExplicitPrompt",
      desc:
          "Placeholder text for message input in an unencrypted room, when the room's encryption is shown explicitly");

  String get cantSentMessagePrompt => Intl.message(
      "You do not have permission to send a message in this room",
      name: "cantSentMessagePrompt",
      desc: "Text that explains the user cannot send a message in this room");

  String get bannedFromRoomNotice => Intl.message(
      "You were banned from this room.",
      name: "bannedFromRoomNotice",
      desc: "Shown in place of the message input after the user was banned");

  String bannedFromRoomReason(String reason) => Intl.message("Reason: $reason",
      args: [reason],
      name: "bannedFromRoomReason",
      desc: "The reason a moderator gave for banning the user from a room");

  String get dismissBannedRoom => Intl.message("Dismiss",
      name: "dismissBannedRoom",
      desc: "Button that removes a room the user was banned from");

  String dismissBannedRoomPrompt(String room) => Intl.message(
      "Remove $room from your room list? You won't be able to read it again.",
      args: [room],
      name: "dismissBannedRoomPrompt",
      desc: "Confirmation before forgetting a room the user was banned from");

  String? get relatedEventSenderName => state.interactingEvent == null
      ? null
      : state.room
          .getMemberOrFallback(state.interactingEvent!.senderId)
          .displayName;

  Color? get relatedEventSenderColor => state.interactingEvent == null
      ? null
      : state.room.getColorOfUser(state.interactingEvent!.senderId);

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Expanded(
          child: Stack(
        fit: StackFit.expand,
        children: [timeline(), const ParticlePlayer()],
      )),
      // Vommet: identity-changed / not-set-up warning in direct messages.
      DmTrustBanner(state.room,
          onLetThemKnow: (text) => state.setMessageInputText.add(text)),
      input(context),
    ]);
  }

  Widget timeline() {
    return state.timeline == null
        ? const Center(
            child: CircularProgressIndicator(),
          )
        // Vommet: selecting several messages (experiment
        // vommet_experiment_select_messages), in the room's own timeline.
        : MessageSelectionHost(
            room: state.room,
            timeline: state.timeline!,
            enabled: !state.isThread && !state.isBubble,
            child: RoomTimelineWidget(
              key: ValueKey("${state.room.identifier}-timeline"),
              timeline: state.timeline!,
              setReplyingEvent: (event) => state.setInteractingEvent(event,
                  type: EventInteractionType.reply),
              setEditingEvent: (event) => state.setInteractingEvent(event,
                  type: EventInteractionType.edit),
              isThreadTimeline: state.isThread,
              clearNotifications: clearNotifications,
            ),
          );
  }

  Widget bannedNotice(BuildContext context) {
    final reason = state.room.banReason;
    return ComposerNotice(
      icon: Icons.block,
      title: bannedFromRoomNotice,
      subtitle: reason == null ? null : bannedFromRoomReason(reason),
      actionLabel: dismissBannedRoom,
      destructiveAction: true,
      onAction: () async {
        final confirmed = await AdaptiveDialog.confirmation(context,
            prompt: dismissBannedRoomPrompt(state.room.displayName),
            confirmationText: dismissBannedRoom,
            cancelText: CommonStrings.promptCancel,
            dangerous: true);
        if (confirmed == true) await state.room.dismissBan();
      },
    );
  }

  void handleMarkAsRead(TimelineEvent event) async {
    // Dont update read receipts if in background
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }

    // Vommet: the server rejects receipts from a banned user
    if (state.room.isBanned) return;

    state.room.timeline!.markAsRead(event);
  }

  void clearNotifications(Room room) {
    // if we clear notifications when opening bubble, the bubble disappears
    if (state.isBubble) {
      return;
    }

    NotificationManager.clearNotifications(room);
  }

  /// Vommet: a banned room stays readable, but its composer becomes the
  /// banned footer, swapped in as soon as the ban arrives.
  Widget input(BuildContext context) {
    return StreamBuilder(
        stream: state.room.onUpdate,
        builder: (context, _) =>
            state.room.isBanned ? bannedNotice(context) : composer(context));
  }

  Widget composer(BuildContext context) {
    String? interactingEventBody = state.interactingEvent?.plainTextBody;

    if (state.interactingEvent case TimelineEventMessage m) {
      if (state.timeline != null) {
        interactingEventBody = m.getPlaintextBody(state.timeline!);
      }
    }

    final messageInput = ClipRRect(
      child: MessageInput(
        client: state.room.client,
        room: state.room,
        isRoomE2EE: state.room.isE2EE,
        hasPendingForward: state.pendingForward != null,
        forwardBar: state.pendingForward != null
            ? ForwardBar(room: state.room, forward: state.pendingForward!)
            : null,
        initialText: state.initialInputText,
        focusKeyboard: state.onFocusMessageInput.stream,
        attachments: state.attachments,
        interactionType: state.interactionType,
        gifComponent: state.gifs,
        onSendVoiceMessage: state.sendVoiceMessage,
        onSendMessage: (message, {overrideClient}) {
          if (overrideClient != null) {
            final processedText = state.room.client
                .getComponent<AccountSwitchPrefix>()
                ?.removePrefix(message, state.room);

            if (processedText != null) {
              message = processedText;
            }
          }
          state.sendMessage(message, overrideClient: overrideClient);
          return MessageInputSendResult.success;
        },
        onTextUpdated: state.onInputTextUpdated,
        addAttachment: state.addAttachment,
        removeAttachment: state.removeAttachment,
        size: MediaQuery.of(context).mobile ? 40 : 35,
        iconScale: MediaQuery.of(context).mobile ? 0.6 : 0.5,
        isProcessing: state.processing,
        enabled: state.room.permissions.canSendMessage,
        relatedEventBody: interactingEventBody,
        relatedEventSenderName: relatedEventSenderName,
        relatedEventSenderColor: relatedEventSenderColor,
        setInputText: state.setMessageInputText.stream,
        availibleEmoticons: state.emoticons?.availableEmoji,
        availibleStickers: state.emoticons?.availableStickers,
        sendSticker: state.sendSticker,
        sendGif: state.sendGif,
        sendFavoriteGif: state.sendFavoriteGif,
        findOverrideClient: (input) => state.room.client
            .getComponent<AccountSwitchPrefix>()
            ?.getPrefixedAccount(input, state.room)
            ?.$1,
        onTapOverrideClient: (overrideClient) {
          EventBus.doOpenRoom(state.room.identifier,
              clientId: overrideClient.identifier);

          if (state.isThread) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              EventBus.openThread.add((
                overrideClient.identifier,
                state.room.identifier,
                state.threadId!
              ));
            });
          }
        },
        editLastMessage: state.editLastMessage,
        hintText: state.room.permissions.canSendMessage
            ? state.room.isE2EE
                ? sendEncryptedMessagePrompt
                : EncryptionMarker.enabled
                    ? sendUnencryptedMessageExplicitPrompt
                    : sendUnencryptedMessagePrompt
            : cantSentMessagePrompt,
        hintIcon:
            EncryptionMarker.enabled && state.room.permissions.canSendMessage
                ? state.room.isE2EE
                    ? Icons.lock
                    : Icons.no_encryption_outlined
                : null,
        cancelReply: () {
          state.setInteractingEvent(null);
        },
        typingIndicatorWidget: state.typingIndicators != null
            ? TypingIndicatorsWidget(
                component: state.typingIndicators!,
                key: ValueKey(
                    "room_typing_indicators_key_${state.room.identifier}"),
              )
            : null,
        processAutofill: (text) =>
            AutofillUtils.search(text, state.room.client, room: state.room),
      ),
    );
    // Vommet: a DM with someone you blocked gets a footer instead.
    return BlockedDmGate(room: state.room, child: messageInput);
  }
}
