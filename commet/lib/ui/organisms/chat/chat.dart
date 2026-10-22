import 'dart:async';
import 'package:commet/utils/relistenable_stream_controller.dart';
import 'dart:math';

import 'package:commet/telemetry/telemetry.dart';
import 'package:commet/client/attachment.dart';
import 'package:commet/utils/voice_message.dart';
import 'package:commet/client/client.dart';
import 'package:commet/client/components/account_switch_prefix/account_switch_prefix.dart';
import 'package:commet/client/components/command/command_component.dart';
import 'package:commet/client/components/photo_album_room/photo_album_room_component.dart';
import 'package:commet/utils/reply_navigation.dart';
import 'package:commet/client/components/emoticon/emoticon.dart';
import 'package:commet/client/components/emoticon/emoticon_component.dart';
import 'package:commet/client/components/gif/gif_component.dart';
import 'package:commet/client/components/gif/gif_search_result.dart';
import 'package:commet/client/components/read_receipts/read_receipt_component.dart';
import 'package:commet/client/components/threads/thread_component.dart';
import 'package:commet/ui/molecules/room_timeline_widget/timeline_keyboard_scroll.dart';
import 'package:commet/client/components/typing_indicators/typing_indicator_component.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event_emote.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:commet/client/timeline_events/timeline_event_sticker.dart';

import 'package:commet/debug/log.dart';
import 'package:commet/utils/file_transfer.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/organisms/add_widget_dialog/add_widget_dialog.dart';
import 'package:commet/ui/organisms/attachment_processor/attachment_processor.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/utils/text_utils.dart';
import 'package:commet/utils/upload_size_limit.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/organisms/chat/chat_view.dart';
import 'package:commet/ui/organisms/chat/prefixed_sends.dart';
import 'package:commet/utils/share_intake.dart';
import 'package:commet/utils/custom_uri.dart';
import 'package:commet/utils/debounce.dart';
import 'package:commet/utils/error_utils.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:commet/client/matrix/forwarding/matrix_forwarding.dart';
import 'package:commet/ui/organisms/forward_message/pending_forward.dart';
import 'package:commet/utils/message_drafts.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:exif/exif.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:tiamat/tiamat.dart' as tiamat;

class Chat extends StatefulWidget {
  const Chat(this.room,
      {this.threadId,
      this.isBubble = false,
      this.focusMessageInput = false,
      super.key});
  final Room room;
  final String? threadId;
  final bool isBubble;

  /// Vommet issue 322: focus the message box once it's shown, whatever the
  /// "Autofocus Message Input" setting (used by "Reply in Thread").
  final bool focusMessageInput;
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

  // Vommet: "Jump to latest" can replace this room's timeline with a live
  // one; show that one from here on (selection, image viewer, read marking).
  StreamSubscription<Timeline>? liveTimelineSubscription;

  // Cancelled here rather than in dispose (always preceded by deactivate),
  // resumed if the chat is moved in the tree.
  @override
  void deactivate() {
    liveTimelineSubscription?.cancel();
    liveTimelineSubscription = null;
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    liveTimelineSubscription ??=
        EventBus.liveTimelineLoaded.stream.listen(onLiveTimelineLoaded);
  }

  void onLiveTimelineLoaded(Timeline timeline) {
    if (isThread || timeline.room != room || timeline == _timeline) return;
    setState(() {
      _timeline = timeline;
    });
  }

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

  String labelChatPageFileTooLargeNamed(
          String file, String size, String server, String limit) =>
      Intl.message("$file is $size. $server accepts files up to $limit.",
          args: [file, size, server, limit],
          desc:
              "Shown when the user attempts to upload a file that is greater than the homeserver's upload limit: the file's name and size, the homeserver's name and its limit",
          name: "labelChatPageFileTooLargeNamed");

  String labelChatPageFileTooLargeUnnamed(
          String size, String server, String limit) =>
      Intl.message("This file is $size. $server accepts files up to $limit.",
          args: [size, server, limit],
          desc:
              "Shown when the user attempts to upload a file without a name that is greater than the homeserver's upload limit: the file's size, the homeserver's name and its limit",
          name: "labelChatPageFileTooLargeUnnamed");

  bool processing = false;

  late final PrefixedSends prefixedSends =
      PrefixedSends((eventId) => _timeline?.tryGetEvent(eventId) != null);
  List<PendingFileAttachment> attachments = List.empty(growable: true);

  EventInteractionType? interactionType;
  TimelineEvent? interactingEvent;

  // Vommet issue 322: while the message box listens, "Reply in Thread" on
  // this open thread focuses it too.
  // Vommet issue 485: both can be listened to again by a new message box.
  late final RelistenableStreamController<void> onFocusMessageInput = () {
    StreamSubscription? replies;
    late final RelistenableStreamController<void> requests;
    requests = RelistenableStreamController<void>(
        onListen: () => replies = EventBus.replyInThread.stream
            .where((rootEventId) => isThread && rootEventId == threadId)
            .listen((_) => requests.add(null)),
        onCancel: () => replies?.cancel());
    return requests;
  }();
  final RelistenableStreamController<String> setMessageInputText =
      RelistenableStreamController();

  StreamSubscription? onLinkedSubscription;
  StreamSubscription? onFileDroppedSubscription;
  StreamSubscription? onShareDeliveredSubscription;

  /// A message waiting in this room's message box to be forwarded.
  PendingForward? pendingForward;
  StreamSubscription? pendingForwardSubscription;

  GifComponent? gifs;
  RoomEmoticonComponent? emoticons;
  ReadReceiptComponent? receipts;
  TypingIndicatorComponent? typingIndicators;
  List<StreamSubscription> emoticonSubscriptions = [];

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

  /// Vommet: the composer's emoji and sticker lists are read when the chat
  /// builds, so rebuild when this room's packs or your account's packs
  /// (favourites, sticker rooms) change. Upstream only picked up new packs
  /// after a restart.
  void listenForEmoticonChanges() {
    final account = room.client.getComponent<EmoticonComponent>();
    for (final stream in [emoticons?.onStateChanged, account?.onStateChanged]) {
      if (stream == null) continue;
      emoticonSubscriptions.add(stream.listen((_) {
        if (mounted) setState(() {});
      }));
    }
  }

  @override
  void initState() {
    Log.i(
        "Initializing room timeline for: ${widget.room.displayName} ${widget.threadId ?? ""}");

    onFileDroppedSubscription =
        EventBus.onFileDropped.stream.listen(onFileDropped);

    if (widget.focusMessageInput) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) onFocusMessageInput.add(null);
      });
    }

    gifs = room.client.getComponent<GifComponent>();
    emoticons = room.getComponent<RoomEmoticonComponent>();
    threadsComponent = room.client.getComponent<ThreadsComponent>();
    receipts = room.getComponent<ReadReceiptComponent>();
    typingIndicators = room.getComponent<TypingIndicatorComponent>();
    listenForEmoticonChanges();

    onLinkedSubscription = CustomURI.onLinked.listen(onLinked);
    liveTimelineSubscription =
        EventBus.liveTimelineLoaded.stream.listen(onLiveTimelineLoaded);

    if (!isThread) {
      pendingForward = PendingForwards.get(room);
      pendingForwardSubscription =
          PendingForwards.onChanged.listen(onPendingForwardChanged);
    }

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

    // Vommet: content shared from another app (Android share sheet).
    if (widget.threadId == null && !widget.isBubble) {
      onShareDeliveredSubscription = ShareIntake.onDelivered.listen((r) {
        if (r.identifier == room.identifier) claimShare();
      });
      claimShare();
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
      // Vommet: the thread's first page loads before its view listens for
      // new events, so opening it marks it read here (a no-op unless "Read
      // state per thread" is on).
      final newest = threadTimeline?.events.firstOrNull;
      if (newest != null &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        threadTimeline!.markAsRead(newest);
      }
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
    pendingForwardSubscription?.cancel();
    prefixedSends.dispose();
    saveDraft();

    Log.i(
        "Disposing room timeline for: ${widget.room.displayName} ${widget.threadId ?? ""}");
    for (final sub in emoticonSubscriptions) {
      sub.cancel();
    }

    onLinkedSubscription?.cancel();
    onShareDeliveredSubscription?.cancel();
    onFileDroppedSubscription?.cancel();
    _timeline?.endVisit();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Vommet: Page Up/Down, Home/End scroll the timeline (Vommet issue 481).
    return TimelineKeyboardScroll(child: ChatView(this));
  }

  void addAttachment(PendingFileAttachment attachment) async {
    if (!await checkAttachmentSize(attachment) || !mounted) return;

    setState(() {
      attachments.add(attachment);
    });
  }

  /// Vommet issue 410: false (after telling the user, with the file's size and
  /// the homeserver's limit) when [attachment] is over the upload limit.
  Future<bool> checkAttachmentSize(PendingFileAttachment attachment) async {
    final client = room.client;
    final limit = client is MatrixClient
        ? await client.fetchMaxFileSize()
        : client.maxFileSize;
    if (!UploadSizeLimit.exceeds(attachment.size, limit)) return true;
    if (!mounted) return false;

    final size = TextUtils.readableFileSize(attachment.size!);
    final max = TextUtils.readableFileSize(limit!);
    final server = UploadSizeLimit.serverOf(room.client.self?.identifier);
    final name = attachment.name;
    final text = server == null
        ? labelChatPageFileTooLarge
        : name == null || name.isEmpty
            ? labelChatPageFileTooLargeUnnamed(size, server, max)
            : labelChatPageFileTooLargeNamed(name, size, server, max);

    AdaptiveDialog.show(context, builder: (_) {
      return SizedBox(
          height: 100, child: Center(child: tiamat.Text.label(text)));
    }, title: labelChatPageFileTooLargeTitle);
    return false;
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

        setState(() {
          processing = false;
        });
        return;
      }
    }

    var processedAttachments = await targetRoom.processAttachments(attachments);

    setState(() {
      processing = false;
    });

    var component = targetRoom.client.getComponent<CommandComponent>();
    Future<Object?>? sent;

    final inReplyTo =
        interactionType == EventInteractionType.reply ? interactingEvent : null;
    final replaceEvent =
        interactionType == EventInteractionType.edit ? interactingEvent : null;

    Future<TimelineEvent?> send(List<ProcessedAttachment> files) => isThread
        ? targetThread!.sendMessage(
            threadRootEventId: widget.threadId!,
            room: targetRoom,
            message: message,
            inReplyTo: inReplyTo,
            replaceEvent: replaceEvent,
            processedAttachments: files)
        : targetRoom.sendMessage(
            message: message,
            inReplyTo: inReplyTo,
            replaceEvent: replaceEvent,
            processedAttachments: files);

    if (component?.isExecutable(message) == true) {
      doCommand(component, message);
    } else {
      final sending = send(processedAttachments);
      if (!isThread) sent = sending;

      // Vommet issue 565: sent from another account, the local echo only
      // shows in that account's timeline, so say it is on its way.
      if (overrideClient != null &&
          targetRoom != room &&
          message.trim().isNotEmpty) {
        prefixedSends.track(
            overrideClient.self?.identifier ?? overrideClient.identifier,
            sending,
            // Attachments are sent separately; only retry the text.
            retry: () => send(const []),
            awaitArrival: replaceEvent == null);
      }
    }

    typingIndicators?.setTypingStatus(false);
    setInteractingEvent(null);
    clearAttachments();
    setMessageInputText.add("");
    sendPendingForward(after: sent);
  }

  void onPendingForwardChanged(String key) {
    if (key != PendingForwards.keyFor(room) || !mounted) return;
    setState(() => pendingForward = PendingForwards.get(room));
  }

  /// Sends the pending forward, after the text typed with it (Telegram order).
  Future<void> sendPendingForward({Future<Object?>? after}) async {
    var forward = pendingForward;
    if (forward == null || isThread) return;
    PendingForwards.clear(room);

    try {
      await after;
      await MatrixForwarding.forward(forward.event, forward.timeline, room,
          showSender: forward.showSender, hideCaption: forward.hideCaption);
    } catch (error, trace) {
      Log.onError(error, trace, content: "Failed to forward message");
      // Put it back in the message box so it can be sent again.
      PendingForwards.set(room, forward);
      if (mounted) {
        AdaptiveDialog.show(context,
            builder: (context) => tiamat.Text.label("$error"));
      }
    }
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

    if (event is! TimelineEventMessage &&
        event is! TimelineEventSticker &&
        event is! TimelineEventEmote) {
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
          if (timeline != null) {
            if (event case TimelineEventMessage m) {
              setMessageInputText.add(m.getPlaintextBody(timeline!));
            } else if (event case TimelineEventEmote e) {
              setMessageInputText.add(e.getPlaintextBody(timeline!));
            }
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

      if (event is! TimelineEventMessage && event is! TimelineEventEmote) {
        continue;
      }

      setInteractingEvent(event, type: EventInteractionType.edit);
      break;
    }
  }

  /// Vommet: Ctrl+↑ / Ctrl+↓ step the reply target through the timeline
  /// (Vommet issue 37).
  void stepReplyTarget({required bool older}) {
    if (interactionType == EventInteractionType.edit) return;
    if (room.getComponent<PhotoAlbumRoom>() != null) return;
    final events = timeline?.events;
    if (events == null) return;

    final current =
        interactionType == EventInteractionType.reply ? interactingEvent : null;
    final next = ReplyNavigation.step<TimelineEvent>(events, current,
        older: older,
        canReply: (event) =>
            event.status == TimelineEventStatus.synced &&
            (event is TimelineEventMessage || event is TimelineEventSticker),
        id: (event) => event.eventId);

    if (identical(next, current)) return;
    setInteractingEvent(next,
        type: next == null ? null : EventInteractionType.reply);
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

    await attachFiles(event.files.map((f) => (path: f.path, name: f.name)));
  }

  /// Adds dropped files, one attachment dialog each. Files that can't be read
  /// are named in one message instead of being skipped silently (Vommet issue
  /// 328).
  Future<void> attachFiles(Iterable<({String path, String name})> files) async {
    var loaded = await FileTransfer.load(files);
    for (var attachment in loaded.files) {
      if (!mounted) return;
      var processedAttachment =
          await AdaptiveDialog.show<PendingFileAttachment>(context,
              scrollable: false,
              builder: (context) => AttachmentProcessor(
                    attachment: attachment,
                  ));

      if (processedAttachment != null && mounted) {
        addAttachment(processedAttachment);
      }
    }

    if (mounted) FileTransfer.showUnreadable(context, loaded.unreadable);
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

  /// Vommet: takes a share meant for this room. Text goes into the message
  /// box; each file goes through the attachment dialog like a dropped file.
  void claimShare() {
    final payload = ShareIntake.claim(room);
    if (payload == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final text = payload.text?.trim();
      if (text != null && text.isNotEmpty) setMessageInputText.add(text);

      for (final file in payload.files) {
        if (!mounted) return;
        final (size, data) = await file.read();
        if (!mounted) return;

        var processed =
            await AdaptiveDialog.show<PendingFileAttachment>(context,
                scrollable: false,
                builder: (context) => AttachmentProcessor(
                      attachment: PendingFileAttachment(
                          name: file.name,
                          path: file.path,
                          size: size,
                          data: data,
                          mimeType: file.mimeType),
                    ));

        if (processed != null && mounted) addAttachment(processed);
      }
    });
  }
}
