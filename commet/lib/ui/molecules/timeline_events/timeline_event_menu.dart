import 'package:commet/telemetry/telemetry.dart';
import 'package:commet/client/components/emoticon/dynamic_emoticon_pack.dart';
import 'package:commet/client/components/emoticon/emoticon.dart';
import 'package:commet/client/components/emoticon/emoji_pack.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/client/components/emoticon/emoticon_component.dart';
import 'package:commet/client/components/emoticon_recent/recent_emoticon_component.dart';
import 'package:commet/client/components/gif/gif_component.dart';
import 'package:commet/client/components/message_effects/message_effect_component.dart';
import 'package:commet/client/components/photo_album_room/photo_album_room_component.dart';
import 'package:commet/client/components/pinned_messages/pinned_messages_component.dart';
import 'package:commet/client/components/polls/poll_component.dart';
import 'package:commet/client/components/push_notification/notification_content.dart';
import 'package:commet/client/components/push_notification/notification_manager.dart';
import 'package:commet/client/matrix/forwarding/matrix_forwarding.dart';
import 'package:commet/client/matrix/matrix_permalink.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:commet/client/timeline.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event_emote.dart';
import 'package:commet/client/timeline_events/timeline_event_encrypted.dart';
import 'package:commet/client/timeline_events/timeline_event_feature_forwarded.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:commet/client/timeline_events/timeline_event_sticker.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/code_block.dart';
import 'package:commet/ui/atoms/emoji_widget.dart';
import 'package:commet/ui/molecules/emoji_picker.dart';
import 'package:commet/ui/molecules/my_gifs.dart';
import 'package:commet/ui/molecules/timeline_events/message_translation_fold.dart';
import 'package:commet/ui/molecules/timeline_events/quick_reply_menu.dart';
import 'package:commet/ui/molecules/timeline_events/personal_pin_menu.dart';
import 'package:commet/ui/molecules/timeline_events/bookmark_menu.dart';
import 'package:commet/ui/molecules/notification_debugger.dart';
import 'package:commet/ui/molecules/timeline_events/message_text_selection.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/organisms/forward_message/forward_message_dialog.dart';
import 'package:commet/ui/organisms/forward_message/pending_forward.dart';
import 'package:commet/ui/organisms/message_selection/message_selection.dart';
import 'package:commet/utils/autofill_utils.dart';
import 'package:commet/client/attachment.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:commet/utils/image_clipboard.dart';
import 'package:commet/utils/download_utils.dart';
import 'package:commet/utils/error_utils.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:commet/utils/translation/message_translation.dart';
import 'package:commet/utils/translation/room_translation.dart';
import 'package:commet/ui/molecules/timeline_events/chat_navigation_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class TimelineEventMenu {
  final Timeline timeline;
  final TimelineEvent event;

  /// Vommet issue 699: the events Delete removes along with [event] when
  /// this is a whole message's menu (not one picture's in a mosaic): the
  /// mosaic's pictures and whatever was sent together with them. Null for
  /// just [event].
  final List<TimelineEvent>? deleteTogether;

  /// Vommet: every picture of the mosaic this whole message's menu was
  /// opened on, oldest first (not set for one picture's own menu). With two
  /// or more, "Forward all N" and "Save all N" act on all of them.
  final List<TimelineEvent>? mosaicEvents;

  /// Vommet issue 741: which picture of a mosaic a reaction goes on ("picture
  /// 2 of 3"), shown above the emoji picker; null outside a mosaic.
  final (int, int)? reactionTarget;

  /// Called with true when the emoji picker opens and false when it closes,
  /// so a mosaic can mark the picture being reacted to.
  final ValueChanged<bool>? onReactionPicking;

  late final List<TimelineEventMenuEntry> primaryActions;
  late final List<TimelineEventMenuEntry> secondaryActions;

  /// Vommet: "Hide Translate in this room", first in [secondaryActions]
  /// while the message shows a Translate pill ([showsTranslatePill]).
  late final TimelineEventMenuEntry hideTranslate;

  /// Whether the message shows a Translate pill now; a menu built ahead
  /// (desktop right-click) asks again when it opens.
  bool showsTranslatePill() => eventShowsTranslatePill(timeline, event,
      translation: translation, rooms: rooms);

  /// Default to [MessageTranslation.instance], [RoomTranslation.instance].
  final MessageTranslation? translation;
  final RoomTranslation? rooms;
  late final List<Emoticon> recentReactions;
  TimelineEventMenuEntry? addReactionAction;

  /// Vommet: Forward, for the desktop hover bar on a picture, video or file
  /// (it stays in [secondaryActions] too); null on other messages.
  TimelineEventMenuEntry? hoverForwardAction;

  final Function(TimelineEvent event)? setEditingEvent;
  final Function(TimelineEvent event)? setReplyingEvent;
  final Function()? onActionFinished;

  final bool isThreadTimeline;

  /// Vommet: the room view's message selection, for "Select". Found from
  /// [context] when not given.
  final MessageSelection? selection;

  /// Vommet: what "Select" ticks: a media mosaic's pictures, which tick as
  /// one row; just [event] when null.
  final List<String>? selectTogether;

  String promptForwardAllPictures(int count) => Intl.message(
        "Forward all $count",
        args: [count],
        desc:
            "Menu option on a picture mosaic: forwards all its pictures (count = how many)",
        name: "promptForwardAllPictures",
      );

  String promptSaveAllPictures(int count) => Intl.message(
        "Save all $count…",
        args: [count],
        desc:
            "Menu option on a picture mosaic: saves all its pictures (count = how many); on a computer it asks for a folder",
        name: "promptSaveAllPictures",
      );

  String get promptPinMessage => Intl.message(
        "Pin for everyone",
        desc: "Label for the menu option to pin a message",
        name: "promptPinMessage",
      );

  String get promptUnpinMessage => Intl.message(
        "Unpin for everyone",
        desc: "Label for the menu option to unpin a message",
        name: "promptUnpinMessage",
      );

  String get promptReplyInThread => Intl.message(
        "Reply In Thread",
        desc: "Label for the menu option to reply to a message inside a thread",
        name: "promptReplyInThread",
      );

  String get promptShowSource => Intl.message(
        "Show Source",
        desc: "Label for the menu option to view the JSON source of an event",
        name: "promptShowSource",
      );

  String get promptCopyMessageLink => Intl.message(
        "Copy message link",
        desc: "Label for the menu option to copy a matrix.to link to a message",
        name: "promptCopyMessageLink",
      );

  /// The context menu's row of recent reactions and the emoji picker
  /// button; null when this event takes no reactions.
  tiamat.ContextMenuItem? reactionContextMenuItem() {
    if (addReactionAction == null) return null;
    return tiamat.ContextMenuItem(
      text: "Add Reaction",
      customBuilder: (context, onClick, {closeMenu}) => Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            for (var i = 0; i < 3 && i < recentReactions.length; i++)
              InkWell(
                  mouseCursor: WidgetStateMouseCursor.clickable,
                  onTap: () {
                    timeline.room.addReaction(event, recentReactions[i]);
                    onClick();
                  },
                  child: recentReactions[i].image == null
                      ? ConstrainedBox(
                          // Text reactions get up to 75 px (Vommet
                          // issue 643).
                          constraints: const BoxConstraints(
                              minWidth: 30,
                              maxWidth: 75,
                              minHeight: 30,
                              maxHeight: 30),
                          child: EmojiWidget(recentReactions[i], maxWidth: 75))
                      : SizedBox(
                          height: 30,
                          width: 30,
                          child: EmojiWidget(recentReactions[i]))),
            tiamat.IconButton(
              icon: Icons.add_reaction,
              size: 24,
              onPressed: () {
                onClick();

                AdaptiveDialog.show(
                  context,
                  builder: (newContext) {
                    return SizedBox(
                        width: 500,
                        height: 500,
                        child: addReactionAction!.secondaryMenuBuilder!.call(
                          newContext,
                          () {
                            Navigator.of(newContext).pop();
                          },
                        ));
                  },
                );
                addReactionAction?.action?.call(context);
              },
            )
          ],
        ),
      ),
    );
  }

  static String reactToPicture(int position, int count) => Intl.message(
      "React to picture $position of $count",
      desc:
          "Above the emoji picker when reacting to one picture of a picture mosaic",
      name: "reactToPicture",
      args: [position, count]);

  String get promptReplayMessageEffect => Intl.message(
        "Replay Effect",
        desc:
            "If a message was sent with an effect, this prompts to replay the effect",
        name: "promptReplayMessageEffect",
      );

  String get promptCancelEventSend => Intl.message(
        "Cancel",
        desc:
            "When a message failed to send, this prompts to cancel sending the event",
        name: "promptCancelEventSend",
      );

  String get promptRetryEventSend => Intl.message(
        "Retry",
        desc:
            "When a message failed to send, this prompts to retry sending the event",
        name: "promptRetryEventSend",
      );

  String get promptEndPoll => Intl.message(
        "End Poll",
        desc: "Prompt the user to end a poll",
        name: "promptEndPoll",
      );

  String get promptFavoriteGif => Intl.message(
        "Favorite GIF",
        desc: "Prompt the user to mark a gif as a favorite",
        name: "promptFavoriteGif",
      );

  /// Deletes [event] and [deleteTogether] (each one the user may delete).
  void deleteEvents() {
    final events = deleteTogether ?? [event];
    for (final e in events.contains(event) ? events : [event, ...events]) {
      if (e.status == TimelineEventStatus.synced &&
          timeline.canDeleteEvent(e)) {
        timeline.deleteEvent(e);
      }
    }
  }

  TimelineEventMenu({
    required this.timeline,
    required this.event,
    this.deleteTogether,
    this.reactionTarget,
    this.onReactionPicking,
    this.setEditingEvent,
    this.setReplyingEvent,
    this.onActionFinished,
    this.isThreadTimeline = false,
    this.selection,
    this.selectTogether,
    this.mosaicEvents,
    this.translation,
    this.rooms,
    required BuildContext context,
  }) {
    bool canEditEvent = false;
    bool canSaveAttachment = false;
    // Vommet: the first image in the message, for "Copy image".
    ImageAttachment? copyableImage;
    bool canAddReaction = false;
    bool canReplyInThread = false;
    bool canCopy = false;
    bool canEditPinState = false;
    bool canPin = false;
    bool canUnpin = false;
    bool hasEffect = false;
    bool canReply = false;
    bool canDeleteEvent = false;
    bool canEndPoll = false;
    bool canForward = false;

    bool canRetrySend = event.status != TimelineEventStatus.synced;
    bool canCancelSend = event.status != TimelineEventStatus.synced;
    bool canFavoriteGif = false;
    bool canUnfavoriteGif = false;

    var effects = timeline.room.client.getComponent<MessageEffectComponent>();
    var emoticons = timeline.room.getComponent<RoomEmoticonComponent>();
    var pins = timeline.room.getComponent<PinnedMessagesComponent>();
    var photos = timeline.room.getComponent<PhotoAlbumRoom>();
    var polls = timeline.client.getComponent<PollComponent>();
    var gifs = timeline.client.getComponent<GifComponent>();

    List<Uri>? links;

    if (event.status == TimelineEventStatus.synced) {
      canEditEvent =
          (event is TimelineEventMessage || event is TimelineEventEmote) &&
              timeline.room.permissions.canUserEditMessages &&
              event.senderId == timeline.room.client.self!.identifier &&
              setEditingEvent != null;

      canDeleteEvent = timeline.canDeleteEvent(event) &&
          event.status == TimelineEventStatus.synced;

      canReply = event is TimelineEventMessage ||
          event is TimelineEventSticker ||
          event is TimelineEventEmote;

      canFavoriteGif =
          gifs?.isGif(event) == true && gifs?.isFavoriteGif(event) == false;
      canUnfavoriteGif =
          gifs?.isGif(event) == true && gifs?.isFavoriteGif(event) == true;

      if (photos != null) {
        canReply = false;
        canEditEvent = false;
      }

      if (event is TimelineEventMessage) {
        canSaveAttachment =
            (event as TimelineEventMessage).attachments?.isNotEmpty == true;

        links = (event as TimelineEventMessage).getLinks(timeline: timeline);
        if (ImageClipboard.supported) {
          copyableImage = (event as TimelineEventMessage)
              .attachments
              ?.whereType<ImageAttachment>()
              .firstOrNull;
        }
      }

      canAddReaction =
          (event is TimelineEventMessage || event is TimelineEventSticker) &&
              emoticons != null;

      canReplyInThread = !isThreadTimeline && event is TimelineEventMessage;

      // Vommet: no reply actions where the user can't post; the composer is
      // disabled there (Vommet issue 429).
      if (!timeline.room.permissions.canSendMessage) {
        canReply = false;
        canReplyInThread = false;
      }

      canCopy = event is TimelineEventMessage;
      // Vommet: on a picture or file whose text is just its file name, "Copy"
      // copied only the name; leave it out there (captions still copy).
      if (event case TimelineEventMessage message) {
        final names = message.attachments?.map((a) => a.name).toSet() ?? {};
        // (body, not plainTextBody: a spoiler's preview text is not its name)
        if (names.isNotEmpty && names.contains(message.body)) {
          canCopy = false;
        }
      }

      canForward =
          (event is TimelineEventMessage || event is TimelineEventSticker) &&
              MatrixForwarding.canForward(event);

      // Forwards can't be edited (MSC4553).
      if (event is TimelineEventFeatureForwarded &&
          (event as TimelineEventFeatureForwarded).forwardedFrom != null) {
        canEditEvent = false;
      }

      if (polls?.isPollEvent(event) == true &&
          polls?.canEndPoll(timeline.room, event, timeline) == true) {
        canEndPoll = true;
      }

      canEditPinState = pins?.canPinMessages == true &&
          (event is TimelineEventMessage ||
              event is TimelineEventSticker ||
              event is TimelineEventEmote);

      bool isPinned = pins?.isMessagePinned(event.eventId) == true;

      canPin = canEditPinState && !isPinned;
      canUnpin = canEditPinState && isPinned;

      hasEffect = effects?.hasEffect(event) == true;
    }

    var reactions =
        timeline.room.client.getComponent<RecentEmoticonComponent>();
    if (reactions != null && canAddReaction) {
      recentReactions = reactions.getRecentReactionEmoticon(timeline.room);
    } else {
      recentReactions = List.empty();
    }

    if (canAddReaction) {
      // Vommet issue 718: loaded when the picker opens, not here. Every
      // message row on desktop builds this menu for its right-click menu, and
      // parsing every emoji pack per row made opening a room or loading
      // history stutter.
      List<EmoticonPack>? availableEmoji;
      List<EmoticonPack> loadAvailableEmoji() {
        // Vommet: a pack that fails to load (a broken emoji pack in a space or
        // on another homeserver) used to throw here and take the whole message
        // menu, and so reacting, down with it; fall back to what loads.
        List<EmoticonPack> packs;
        try {
          packs = emoticons!.availableEmoji;
        } catch (e, st) {
          Log.e("Could not load the emoji for reactions: $e\n$st");
          packs = [];
        }

        if (recentReactions.isNotEmpty) {
          packs.insert(
              0,
              DynamicEmoticonPack(
                  identifier: "dynamic_pack_frequently_used_reactions",
                  displayName: "Frequently Used",
                  icon: Icons.schedule,
                  emoticons: recentReactions,
                  usage: EmoticonUsage.all));
        }
        return packs;
      }

      addReactionAction = TimelineEventMenuEntry(
        name: CommonStrings.promptAddReaction,
        icon: Icons.add_reaction,
        secondaryMenuBuilder: (context, dismissSecondaryMenu) {
          final picker = EmojiPicker(availableEmoji ??= loadAvailableEmoji(),
              searchDelegate: (search) => AutofillUtils.searchEmoticon(search,
                      client: timeline.client, room: timeline.room, limit: 50)
                  .whereType<AutofillSearchResultEmoticon>()
                  .toList(),
              preferredTooltipDirection: AxisDirection.left,
              onEmoticonPressed: (emote) async {
                timeline.room.addReaction(event, emote);
                await Future.delayed(const Duration(milliseconds: 100));
                dismissSecondaryMenu();
              });
          final target = reactionTarget;
          return _ReactionPickerScope(
            onPicking: onReactionPicking,
            child: target == null
                ? picker
                : Column(children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                      child: Row(children: [
                        const Icon(Icons.photo_outlined, size: 18),
                        const SizedBox(width: 8),
                        Flexible(
                            child: tiamat.Text.labelLow(
                                reactToPicture(target.$1, target.$2))),
                      ]),
                    ),
                    Expanded(child: picker),
                  ]),
          );
        },
      );
    }

    // Vommet: "Forward all N" / "Save all N" on a mosaic's message menu;
    // null unless at least two of its pictures can be forwarded / saved.
    final mosaic = mosaicEvents ?? const <TimelineEvent>[];
    final forwardable = canForward
        ? mosaic.where(MatrixForwarding.canForward).toList()
        : const <TimelineEvent>[];
    final forwardAll = forwardable.length > 1 ? forwardable : null;
    final savable = [
      for (final e in mosaic)
        if (e is TimelineEventMessage)
          if (e.attachments?.firstOrNull case final a?) a
    ];
    final saveAll = canSaveAttachment && savable.length > 1 ? savable : null;

    primaryActions = [
      if (canEndPoll)
        TimelineEventMenuEntry(
          name: promptEndPoll,
          icon: Icons.poll,
          action: (context) async {
            if (await AdaptiveDialog.confirmation(context,
                    title: promptEndPoll,
                    prompt: "Are you sure you want to end the poll?") ==
                true) polls?.endPoll(timeline.room, event);

            onActionFinished?.call();
          },
        ),
      if (event is TimelineEventEncrypted)
        TimelineEventMenuEntry(
          name: "Retry Decrypt",
          icon: Icons.lock_open,
          action: (context) {
            var mx = (event as MatrixTimelineEvent).event;

            ErrorUtils.tryRun(context, () async {
              // Vommet: opt-in diagnostics "key_request" (outcome only).
              Object? error;
              try {
                await mx.requestKey();
              } catch (e) {
                error = e;
                rethrow;
              } finally {
                Telemetry.record("key_request", {
                  "source": "manual",
                  ...Telemetry.errorFields(error, withType: false),
                });
              }
            });

            onActionFinished?.call();
          },
        ),
      if (canRetrySend)
        TimelineEventMenuEntry(
          name: promptRetryEventSend,
          icon: Icons.refresh,
          action: (BuildContext context) {
            timeline.room.retrySend(event);
            onActionFinished?.call();
          },
        ),
      if (canCancelSend)
        TimelineEventMenuEntry(
          name: promptCancelEventSend,
          icon: Icons.cancel,
          action: (BuildContext context) {
            timeline.room.cancelSend(event);
            onActionFinished?.call();
          },
        ),
      if (hasEffect)
        TimelineEventMenuEntry(
          name: promptReplayMessageEffect,
          icon: Icons.celebration,
          action: (BuildContext context) {
            effects?.doEffect(event);
            onActionFinished?.call();
          },
        ),
      if (canEditEvent)
        TimelineEventMenuEntry(
          name: CommonStrings.promptEdit,
          icon: Icons.edit,
          action: (BuildContext context) {
            setEditingEvent?.call(event);
            onActionFinished?.call();
          },
        ),
      if (canReply)
        TimelineEventMenuEntry(
          name: CommonStrings.promptReply,
          icon: Icons.reply,
          action: (BuildContext context) {
            setReplyingEvent?.call(event);
            onActionFinished?.call();
          },
        ),
      if (copyableImage != null)
        TimelineEventMenuEntry(
            name: CommonStrings.promptCopyImage,
            icon: Icons.copy,
            action: (BuildContext context) {
              ImageClipboard.copy(copyableImage!.image);
              onActionFinished?.call();
            }),
      if (canSaveAttachment)
        TimelineEventMenuEntry(
            // Vommet: it opens a save dialog, so say so.
            name: CommonStrings.promptSaveAs,
            icon: Icons.save_alt,
            action: (BuildContext context) {
              var attachment =
                  (event as TimelineEventMessage).attachments?.firstOrNull;
              if (attachment != null) {
                DownloadUtils.downloadAttachment(attachment);
              }
              onActionFinished?.call();
            }),
      if (saveAll != null)
        TimelineEventMenuEntry(
            name: promptSaveAllPictures(saveAll.length),
            icon: Icons.save_alt,
            action: (BuildContext context) {
              DownloadUtils.downloadAttachments(saveAll);
              onActionFinished?.call();
            }),
      if (canDeleteEvent)
        TimelineEventMenuEntry(
          name: CommonStrings.promptDelete,
          icon: Icons.delete,
          action: (BuildContext context) {
            if (preferences.askBeforeDeletingMessageEnabled.value) {
              AdaptiveDialog.confirmation(context).then((value) {
                if (value == true) {
                  deleteEvents();
                }
                onActionFinished?.call();
              });
            } else {
              deleteEvents();
              onActionFinished?.call();
            }
          },
        ),
    ];

    // Vommet: start selecting several messages, this one ticked.
    final selection = this.selection ?? MessageSelectionScope.maybeOf(context);
    final canSelect = MessageSelection.enabled &&
        selection != null &&
        MessageSelection.canTick(event, timeline);

    final forward = canForward
        ? TimelineEventMenuEntry(
            name: ForwardMessageDialog.promptForwardMessage,
            icon: Icons.shortcut,
            action: (BuildContext context) async {
              onActionFinished?.call();
              var rooms = await ForwardMessageDialog.pickRooms(
                  context, timeline.client);
              if (rooms != null) {
                PendingForwards.startInAll(
                    rooms, PendingForward(event: event, timeline: timeline));
              }
            },
          )
        : null;
    if (canSaveAttachment) hoverForwardAction = forward;

    // Vommet: hides the Translate pills in this room (Vommet issue 680).
    hideTranslate = TimelineEventMenuEntry(
      name: "Hide Translate in this room",
      icon: Icons.translate,
      action: (BuildContext context) {
        onActionFinished?.call();
        hideTranslatePills(context, timeline.room.identifier, rooms: rooms);
      },
    );

    secondaryActions = [
      if (showsTranslatePill()) hideTranslate,
      // Vommet (chat navigation): when a direct message was read.
      if (ChatNavigationMenu.readAtEntry(
              context, timeline, event, onActionFinished)
          case final readAt?)
        readAt,
      if (canSelect)
        TimelineEventMenuEntry(
          name: MessageSelection.promptSelectMessage,
          icon: Icons.check_circle_outline,
          action: (BuildContext context) {
            onActionFinished?.call();
            final ids = selectTogether ?? [event.eventId];
            if (selection.active) {
              if (!selection.isTicked(ids)) {
                selection.toggle(ids);
              }
            } else {
              selection.start(ids);
            }
          },
        ),
      if (canReplyInThread)
        TimelineEventMenuEntry(
          name: promptReplyInThread,
          icon: Icons.message_rounded,
          action: (context) {
            EventBus.replyInThread.add(event.eventId);
            EventBus.openThread.add((
              timeline.client.identifier,
              timeline.room.identifier,
              event.eventId,
            ));
            onActionFinished?.call();
          },
        ),
      if (canPin)
        TimelineEventMenuEntry(
          name: promptPinMessage,
          icon: Icons.push_pin,
          action: (context) {
            pins!.pinMessage(event.eventId);
            onActionFinished?.call();
          },
        ),
      // Vommet: a pin only you see.
      if (PersonalPinMenu.entry(timeline.room, event, onActionFinished)
          case final personalPin?)
        personalPin,
      // Vommet: saved messages, across rooms, with tags.
      ...BookmarkMenu.entries(timeline.room, event, onActionFinished),
      if (canUnpin)
        TimelineEventMenuEntry(
          name: promptUnpinMessage,
          icon: Icons.push_pin,
          action: (context) {
            pins!.unpinMessage(event.eventId);
            onActionFinished?.call();
          },
        ),
      if (forward != null) forward,
      if (forwardAll != null)
        TimelineEventMenuEntry(
          name: promptForwardAllPictures(forwardAll.length),
          icon: Icons.shortcut,
          action: (BuildContext context) async {
            onActionFinished?.call();
            var rooms =
                await ForwardMessageDialog.pickRooms(context, timeline.client);
            if (rooms != null) {
              PendingForwards.startInAll(rooms,
                  PendingForward.many(events: forwardAll, timeline: timeline));
            }
          },
        ),
      // Vommet: on every platform, for any GIF (see MyGifs).
      if (canFavoriteGif || canUnfavoriteGif)
        MyGifs.menuEntry(gifs!, event,
            saved: canUnfavoriteGif, onActionFinished: onActionFinished),
      // Vommet issue 731: right under it.
      if (canFavoriteGif || canUnfavoriteGif)
        MyGifs.folderMenuEntry(gifs!, event,
            onActionFinished: onActionFinished),
      if (ChatNavigationMenu.editHistoryEntry(timeline, event, onActionFinished)
          case final editHistory?)
        editHistory,
      // Vommet: keep your own message as a /name quick reply.
      if (QuickReplyMenu.entry(timeline.room, event, onActionFinished)
          case final quickReply?)
        quickReply,
      if (canCopy)
        TimelineEventMenuEntry(
            name: CommonStrings.promptCopy,
            icon: Icons.copy,
            action: (context) {
              Clipboard.setData(ClipboardData(
                text: (event as TimelineEventMessage).plainTextBody,
              ));
            }),
      if (canCopy && MediaQuery.of(context).mobile)
        TimelineEventMenuEntry(
            name: MessageTextSelection.promptSelectText,
            icon: Icons.text_fields,
            action: (context) {
              onActionFinished?.call();
              MessageTextSelection.start(event.eventId);
            }),
      if (links?.isNotEmpty == true)
        TimelineEventMenuEntry(
            name: "Copy Link",
            icon: Icons.link,
            action: (context) async {
              if (links!.length > 1) {
                var selected = await AdaptiveDialog.pickOne(
                  context,
                  items: links,
                  itemBuilder: (context, item, callback) => SizedBox(
                    height: 50,
                    child: tiamat.TextButton(
                      item.toString(),
                      icon: Icons.link,
                      onTap: () {
                        callback();

                        if (MediaQuery.of(context).layout ==
                            LayoutType.mobile) {
                          Navigator.of(context).pop();
                        }
                      },
                    ),
                  ),
                );

                if (selected != null) {
                  Clipboard.setData(ClipboardData(
                    text: selected.toString(),
                  ));
                }
              } else {
                Clipboard.setData(ClipboardData(
                  text: links.first.toString(),
                ));
              }
            }),
      // Vommet issue 665: a matrix.to link to this message, like Element's.
      if (event is MatrixTimelineEvent && event.eventId.startsWith("\$"))
        TimelineEventMenuEntry(
            name: promptCopyMessageLink,
            icon: Icons.share,
            action: (context) {
              onActionFinished?.call();
              ErrorUtils.tryRun(context, () async {
                final link = await MatrixPermalink.forEvent(
                    (event as MatrixTimelineEvent).event.room, event.eventId);
                await Clipboard.setData(ClipboardData(text: link));
              });
            }),
      TimelineEventMenuEntry(
        name: promptShowSource,
        icon: Icons.code,
        action: (BuildContext context) {
          onActionFinished?.call();

          AdaptiveDialog.show(
            context,
            title: "Source",
            builder: (context) {
              return SizedBox(
                width: 1000,
                child: SelectionArea(
                  child: ExpandableCodeBlock(
                      expanded: true, text: event.source, language: "json"),
                ),
              );
            },
          );
        },
      ),
      if (preferences.developerMode.value &&
          (event is TimelineEventMessage || event is TimelineEventSticker))
        TimelineEventMenuEntry(
          name: "Show Notification",
          icon: Icons.notification_add,
          action: (BuildContext context) async {
            var room = timeline.room;

            var content = await MessageNotificationContent.fromEvent(
              event,
              room,
            );
            if (content != null) {
              NotificationManager.notify(content, forceShow: true);
            }

            onActionFinished?.call();
          },
        ),
      if (preferences.developerMode.value)
        TimelineEventMenuEntry(
          name: "Diagnose Notification",
          icon: Icons.notification_important,
          action: (BuildContext context) async {
            AdaptiveDialog.show(context,
                builder: (context) => NotificationDebugger(
                      event: event,
                      client: timeline.client,
                      room: timeline.room,
                    ));
          },
        ),
    ];
  }
}

/// Tells [onPicking] while the emoji picker is shown, however it was opened
/// (the hover bar, a context menu's dialog or the phone menu's sheet).
class _ReactionPickerScope extends StatefulWidget {
  const _ReactionPickerScope({required this.child, this.onPicking});

  final Widget child;
  final ValueChanged<bool>? onPicking;

  @override
  State<_ReactionPickerScope> createState() => _ReactionPickerScopeState();
}

class _ReactionPickerScopeState extends State<_ReactionPickerScope> {
  // After the frame: the listeners rebuild the mosaic, which they can't
  // while this is being built or taken down.
  void _tell(bool picking) {
    final onPicking = widget.onPicking;
    if (onPicking == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => onPicking(picking));
  }

  @override
  void initState() {
    super.initState();
    _tell(true);
  }

  @override
  void dispose() {
    _tell(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class TimelineEventMenuEntry {
  final String name;
  final Function(BuildContext context)? action;
  final IconData icon;

  final Widget Function(BuildContext context, Function() dismissMenu)?
      secondaryMenuBuilder;

  TimelineEventMenuEntry({
    required this.name,
    required this.icon,
    this.action,
    this.secondaryMenuBuilder,
  });
}
