import 'dart:async';
import 'dart:math';

import 'package:commet/telemetry/telemetry.dart';
import 'package:commet/client/attachment.dart';
import 'package:commet/utils/voice_message.dart';
import 'package:commet/client/client.dart';
import 'package:commet/client/components/account_switch_prefix/account_switch_prefix.dart';
import 'package:commet/client/components/command/command_component.dart';
import 'package:commet/client/components/emoticon/emoticon.dart';
import 'package:commet/client/components/emoticon/emoticon_component.dart';
import 'package:commet/client/components/gif/gif_component.dart';
import 'package:commet/client/components/gif/gif_search_result.dart';
import 'package:commet/client/components/read_receipts/read_receipt_component.dart';
import 'package:commet/client/components/threads/thread_component.dart';
import 'package:commet/client/components/typing_indicators/typing_indicator_component.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:commet/client/timeline_events/timeline_event_sticker.dart';

import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/organisms/add_widget_dialog/add_widget_dialog.dart';
import 'package:commet/ui/organisms/attachment_processor/attachment_processor.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/organisms/chat/chat_view.dart';
import 'package:commet/utils/custom_uri.dart';
import 'package:commet/utils/debounce.dart';
import 'package:commet/utils/error_utils.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:commet/utils/message_drafts.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:exif/exif.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:tiamat/tiamat.dart' as tiamat;

class Chat extends StatefulWidget {
  const Chat(this.room, {this.threadId, this.isBubble = false, super.key});
  final Room room;
  final String? threadId;
  final bool isBubble;
  @override
  State<Chat> createState() => ChatState();
}

enum EventInteractionType {
  reply,
  edit,
}

class ChatState extends State<Chat> {
  Room get room => widget.room;
  Timeline? _timeline;

  Timeline? get timeline => _timeline;

  ThreadsComponent? threadsComponent;

  String get labelChatPageFileTooLarge => Intl.message(
      "This file is too large to upload!",
      desc:
          "Text that is shown when the user attempts to upload a file that is greater than the allowed size",
      name: "labelChatPageFileTooLarge");

  String get labelChatPageFileTooLargeTitle => Intl.message(
      "Max file size exceeded",
      desc:
          "Title for the dialog that is shown when the user attempts to upload a file that is greater than the allowed size",
      name: "labelChatPageFileTooLargeTitle");

  bool processing = false;
  List<PendingFileAttachment> attachments = List.empty(growable: true);

  EventInteractionType? interactionType;
  TimelineEvent? interactingEvent;

  StreamController<void> onFocusMessageInput = StreamController();
  StreamController<String> setMessageInputText = StreamController();

  StreamSubscription? onLinkedSubscription;
  StreamSubscription? onFileDroppedSubscription;

  GifComponent? gifs;
  RoomEmoticonComponent? emoticons;
  ReadReceiptComponent? receipts;
  TypingIndicatorComponent? typingIndicators;

  Debouncer typingStatusDebouncer =
      Debouncer(delay: const Duration(seconds: 5));
  DateTime lastSetTyping = DateTime.fromMicrosecondsSinceEpoch(0);

  static final MessageDrafts<TimelineEvent> drafts = MessageDrafts();

  String get draftKey =>
      MessageDrafts.keyFor(room.client.identifier, room.identifier,
          threadId: widget.threadId);

  /// What the message box held when this chat was opened, restored from the
  /// room's draft.
  String? initialInputText;
  String inputText = "";

  bool get isThread => widget.threadId != null;

  String? get threadId => widget.threadId;

  bool get isBubble => widget.isBubble;

  @override
  void initState() {
    Log.i(
        "Initializing room timeline for: ${widget.room.displayName} ${widget.threadId ?? ""}");

    onFileDroppedSubscription =
        EventBus.onFileDropped.stream.listen(onFileDropped);

    gifs = room.client.getComponent<GifComponent>();
    emoticons = room.getComponent<RoomEmoticonComponent>();
    threadsComponent = room.client.getComponent<ThreadsComponent>();
    receipts = room.getComponent<ReadReceiptComponent>();
    typingIndicators = room.getComponent<TypingIndicatorComponent>();

    onLinkedSubscription = CustomURI.onLinked.listen(onLinked);

    var draft =
        preferences.experimentMessageDrafts.value ? drafts.get(draftKey) : null;
    if (draft != null) {
      initialInputText = draft.text;
      inputText = draft.text;
      if (draft.relation case EventInteractionType type) {
        interactingEvent = draft.relatedEvent;
        interactionType = interactingEvent != null ? type : null;
      }
    }

    if (widget.threadId != null && threadsComponent != null) {
      loadThreadTimeline();
    } else {
      if (room.timeline != null) {
        _timeline = room.timeline;
      } else {
        loadTimeline();
      }
    }

    super.initState();
  }

  String? get initialEventId =>
      preferences.openRoomsAtLastReadMessage.value ? room.lastRead : null;

  Future<void> loadTimeline() async {
    ErrorUtils.tryRun(context, () async {
      var t = await room.getTimeline(contextEventId: initialEventId);
      // Vommet: the room may have closed while its timeline loaded.
      if (!mounted) return;
      setState(() {
        _timeline = t;
      });
    }, title: "Error loading timeline");
  }

  Future<void> loadThreadTimeline() async {
    ErrorUtils.tryRun(context, () async {
      Timeline? timeline = room.timeline;
      timeline ??= await room.getTimeline(contextEventId: initialEventId);

      var threadTimeline = await threadsComponent!.getThreadTimeline(
          roomTimeline: timeline, threadRootEventId: widget.threadId!);
      if (!mounted) return;
      setState(() {
        _timeline = threadTimeline;
      });
    }, title: "Error loading thread timeline");
  }

  void saveDraft() {
    if (preferences.experimentMessageDrafts.value) {
      drafts.set(
          draftKey,
          MessageDraft(inputText,
              relatedEvent: interactingEvent, relation: interactionType));
    } else {
      drafts.clear(draftKey);
    }
  }

  @override
  void dispose() {
    saveDraft();

    Log.i(
        "Disposing room timeline for: ${widget.room.displayName} ${widget.threadId ?? ""}");

    onLinkedSubscription?.cancel();
    onFileDroppedSubscription?.cancel();
    _timeline?.endVisit();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChatView(this);
  }

  void addAttachment(PendingFileAttachment attachment) {
    if (room.client.maxFileSize != null) {
      if (attachment.size != null &&
          attachment.size! > room.client.maxFileSize!) {
        AdaptiveDialog.show(context, builder: (_) {
          return SizedBox(
              height: 100,
              child:
                  Center(child: tiamat.Text.label(labelChatPageFileTooLarge)));
        }, title: labelChatPageFileTooLargeTitle);

        return;
      }
    }

    setState(() {
      attachments.add(attachment);
    });
  }

  void removeAttachment(PendingFileAttachment attachment) {
    setState(() {
      attachments.remove(attachment);
    });
  }

  /// Sends a recorded voice message to this room (or thread), as a reply
  /// when replying. Returns false if sending failed.
  Future<bool> sendVoiceMessage(VoiceRecording recording,
      {Client? overrideClient}) async {
    var targetRoom = room;
    if (overrideClient != null) {
      final newRoom = overrideClient.getRoom(targetRoom.identifier);
      if (newRoom == null) {
        Log.e(
            "Failed to find room for override client; voice message not sent");
        return false;
      }
      targetRoom = newRoom;
    }

    final replyTo =
        interactionType == EventInteractionType.reply ? interactingEvent : null;
    setInteractingEvent(null);

    try {
      await targetRoom.sendVoiceMessage(recording,
          inReplyTo: replyTo,
          threadRootEventId: isThread ? widget.threadId : null);
      return true;
    } catch (e, s) {
      Log.onError(e, s, content: "Failed to send voice message");
      return false;
    }
  }

  void sendMessage(String message, {Client? overrideClient}) async {
    inputText = "";
    drafts.clear(draftKey);

    setState(() {
      processing = true;
    });

    for (var file in attachments) {
      file.telemetryMs["_start"] = Telemetry.sinceStart;
      var clock = Stopwatch()..start();
      await file.resolve();
      file.telemetryMs["resolve_ms"] = clock.elapsedMilliseconds;
      clock.reset();
      var exif = await readExifFromBytes(file.data!);
      file.telemetryMs["exif_ms"] = clock.elapsedMilliseconds;

      if (exif.keys.any((e) => e.toLowerCase().contains("gps"))) {
        // ignore: use_build_context_synchronously
        var confirmation = await AdaptiveDialog.confirmation(context,
            title: file.name ?? "File",
            confirmationText: "Send File",
            cancelText: "Don't send file",
            dangerous: true,
            prompt:
                "Location data was detected in file '${file.name}', are you sure you want to send?");

        if (confirmation != true) {
          setState(() {
            processing = false;
          });
          return;
        }
      }
    }

    var targetRoom = room;
    var targetThread = threadsComponent;

    if (overrideClient != null) {
      var newRoom = overrideClient.getRoom(targetRoom.identifier);
      if (newRoom != null) {
        targetRoom = newRoom;
        targetThread = targetRoom.client.getComponent<ThreadsComponent>();
        Log.d("Overriding room for client: ${overrideClient}");
      } else {
        Log.e(
            "Failed to find correct room to send event for override client. Cancelling");

        return;
      }
    }

    var processedAttachments = await targetRoom.processAttachments(attachments);

    setState(() {
      processing = false;
    });

    var component = targetRoom.client.getComponent<CommandComponent>();

    if (component?.isExecutable(message) == true) {
      doCommand(component, message);
    } else if (isThread) {
      targetThread!.sendMessage(
          threadRootEventId: widget.threadId!,
          room: targetRoom,
          message: message,
          inReplyTo: interactionType == EventInteractionType.reply
              ? interactingEvent
              : null,
          replaceEvent: interactionType == EventInteractionType.edit
              ? interactingEvent
              : null,
          processedAttachments: processedAttachments);
    } else {
      targetRoom.sendMessage(
          message: message,
          inReplyTo: interactionType == EventInteractionType.reply
              ? interactingEvent
              : null,
          replaceEvent: interactionType == EventInteractionType.edit
              ? interactingEvent
              : null,
          processedAttachments: processedAttachments);
    }

    typingIndicators?.setTypingStatus(false);
    setInteractingEvent(null);
    clearAttachments();
    setMessageInputText.add("");
  }

  Future<void> doCommand(
      CommandComponent<Client>? component, String message) async {
    try {
      await component?.executeCommand(message, room,
          interactingEvent: interactingEvent, type: interactionType);
    } catch (error, trace) {
      Log.onError(error, trace);
      if (mounted)
        AdaptiveDialog.show(context,
            builder: (context) => tiamat.Text.label("$error"));
    }
  }

  void setInteractingEvent(TimelineEvent? event, {EventInteractionType? type}) {
    if (event == null) {
      setState(() {
        interactingEvent = null;
        interactionType = null;
      });
      return;
    }

    if (event is! TimelineEventMessage && event is! TimelineEventSticker) {
      return;
    }

    setState(() {
      interactingEvent = event;
      interactionType = type;

      switch (type) {
        case EventInteractionType.reply:
          onFocusMessageInput.add(null);
          break;
        case EventInteractionType.edit:
          if (event case TimelineEventMessage m) if (timeline != null) {
            setMessageInputText.add(m.getPlaintextBody(timeline!));
          }

          onFocusMessageInput.add(null);
          break;
        default:
      }
    });
  }

  void clearAttachments() {
    setState(() {
      attachments.clear();
    });
  }

  void addReaction(TimelineEvent event, Emoticon emote) {
    room.addReaction(event, emote);
  }

  void sendSticker(Emoticon sticker) {
    emoticons?.sendSticker(
        sticker,
        interactionType == EventInteractionType.reply
            ? interactingEvent
            : null);

    if (interactionType == EventInteractionType.reply) {
      setInteractingEvent(null);
    }
  }

  Future<void> sendGif(GifSearchResult gif) async {
    await gifs?.sendGif(
        room,
        gif,
        interactionType == EventInteractionType.reply
            ? interactingEvent
            : null);

    if (interactionType == EventInteractionType.reply) {
      setInteractingEvent(null);
    }
  }

  void editLastMessage() {
    if (!room.permissions.canUserEditMessages) return;
    if (interactionType != null) return;

    for (int i = 0; i < min(20, room.timeline!.events.length); i++) {
      var event = room.timeline!.events[i];

      if (event.senderId != room.client.self!.identifier) continue;

      if (!(event is TimelineEventMessage)) continue;

      setInteractingEvent(event, type: EventInteractionType.edit);
      break;
    }
  }

  void onInputTextUpdated(String currentText) {
    inputText = currentText;

    if (isThread) {
      return;
    }

    var component = room.client.getComponent<CommandComponent>();
    if (component?.isPossiblyCommand(currentText) == true) {
      return;
    }

    var prefixComp = room.client.getComponent<AccountSwitchPrefix>();
    if (prefixComp?.isPossiblyUsingPrefix(currentText) == true) {
      return;
    }

    if (currentText.isEmpty) {
      stopTyping();
      typingStatusDebouncer.cancel();
      lastSetTyping = DateTime.fromMicrosecondsSinceEpoch(0);
    } else {
      if ((DateTime.now().difference(lastSetTyping)).inSeconds > 3) {
        typingIndicators?.setTypingStatus(true);
        lastSetTyping = DateTime.now();
      }
      typingStatusDebouncer.run(stopTyping);
    }
  }

  void stopTyping() {
    typingIndicators?.setTypingStatus(false);
  }

  void onFileDropped(DropDoneDetails event) async {
    var path = event.rawText;

    print(path);
    if (path != null) {
      var custom = CustomURI.parse(path);

      if (custom case AddWidgetURI widgetUri) {
        AdaptiveDialog.show(context, builder: (dialogContext) {
          return AddWidgetDialog(widgetUri: widgetUri, room: widget.room);
        }, title: 'Add "${widgetUri.widgetName ?? "Custom"}"?');
      }
    }

    for (var file in event.files) {
      var size = await file.length();
      Uint8List? data;
      if (size < 50000000) {
        data = await file.readAsBytes();
      }

      if (mounted) {
        var attachment = PendingFileAttachment(
            name: file.name, path: file.path, size: size, data: data);

        var processedAttachment =
            await AdaptiveDialog.show<PendingFileAttachment>(context,
                scrollable: false,
                builder: (context) => AttachmentProcessor(
                      attachment: attachment,
                    ));

        if (processedAttachment != null) {
          setState(() {
            attachments.add(processedAttachment);
          });
        }
      }
    }
  }

  Future<void> sendFavoriteGif(FavoriteGif gif) async {
    await room.client.getComponent<GifComponent>()?.sendFavoriteGif(
        room,
        gif,
        interactionType == EventInteractionType.reply
            ? interactingEvent
            : null);
  }

  void onLinked(Uri event) {
    var custom = CustomURI.parse(event.toString());

    if (custom case AddWidgetURI widgetUri) {
      AdaptiveDialog.show(context, builder: (dialogContext) {
        return AddWidgetDialog(widgetUri: widgetUri, room: widget.room);
      }, title: 'Add "${widgetUri.widgetName ?? "Custom"}"?');
    }
  }
}
