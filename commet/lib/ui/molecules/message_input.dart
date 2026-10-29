import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:commet/client/components/sticker_shelf/sticker_shelf_component.dart';
import 'package:commet/client/client.dart';
import 'package:commet/ui/molecules/voice_message/voice_recording_bar.dart';
import 'package:commet/utils/voice_message.dart';
import 'package:commet/utils/voice_recorder.dart';
import 'package:commet/client/components/emoticon/dynamic_emoticon_pack.dart';
import 'package:commet/client/components/emoticon_recent/recent_emoticon_component.dart';
import 'package:commet/client/components/gif/gif_component.dart';
import 'package:commet/client/components/polls/poll_component.dart';
import 'package:commet/config/build_config.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/emoji_widget.dart';
import 'package:commet/ui/atoms/keyboard_adaptor.dart';
import 'package:commet/ui/molecules/message_effect_picker.dart';
import 'package:commet/ui/atoms/random_emoji_button.dart';
import 'package:commet/ui/atoms/reply_quote.dart';
import 'package:commet/ui/atoms/rich_text_field.dart';
import 'package:commet/ui/molecules/attachment_icon.dart';
import 'package:commet/client/components/scheduled_messages/scheduled_messages.dart';
import 'package:commet/config/layout_style.dart';
import 'package:commet/ui/organisms/scheduled_messages/scheduled_messages_view.dart';
import 'package:commet/client/components/command/command_component.dart';
import 'package:commet/ui/molecules/composer_formatting/composer_formatting.dart';
import 'package:commet/ui/molecules/composer_expand.dart';
import 'package:commet/ui/molecules/composer_plus_menu.dart';
import 'package:commet/ui/molecules/composer_ring_colors.dart';
import 'package:commet/ui/molecules/composer_translation.dart';
import 'package:commet/ui/molecules/overlapping_panels.dart';
import 'package:commet/ui/molecules/poll_creator.dart';
import 'package:commet/ui/organisms/attachment_processor/attachment_processor.dart';
import 'package:commet/ui/organisms/media_send_sheet/media_send_sheet.dart';
import 'package:commet/ui/molecules/emoji_picker.dart';
import 'package:commet/ui/molecules/emoticon_picker.dart';
import 'package:commet/client/components/emoticon/emoticon_component.dart';
import 'package:commet/ui/pages/settings/categories/room/emoji_packs/import_destinations.dart';
import 'package:commet/ui/pages/library/library_page.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/organisms/chat/chat.dart';
import 'package:commet/client/components/emoticon/emoji_pack.dart';
import 'package:commet/client/components/gif/gif_search_result.dart';
import 'package:commet/utils/app_focus_util.dart';
import 'package:commet/utils/autofill_utils.dart';
import 'package:commet/utils/file_transfer.dart';
import 'package:commet/utils/debounce.dart';
import 'package:commet/utils/image_clipboard.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:commet/utils/recovery_key_guard.dart';
import 'package:commet/utils/translation/message_translation.dart';
import 'package:commet/utils/translation/model_spec.dart';
import 'package:commet/utils/translation/paragraph_translation.dart';
import 'package:commet/utils/translation/reply_quote_translation.dart';
import 'package:commet/utils/translation/room_translation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_the_tooltip/just_the_tooltip.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:commet/utils/web_paste.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:commet/ui/atoms/touch_selection_normalizer.dart';
import 'package:commet/ui/atoms/primary_selection_field.dart';
import '../../client/attachment.dart';
import '../../client/components/emoticon/emoticon.dart';
import 'package:intl/intl.dart';
import 'package:commet/ui/molecules/spellcheck_context_menu.dart';
import 'package:commet/utils/spellcheck/spellcheck.dart';

enum MessageInputSendResult { success, unhandled }

class MessageInput extends StatefulWidget {
  const MessageInput(
      {super.key,
      required this.client,
      this.room,
      this.maxHeight = 200,
      this.onSendMessage,
      this.isRoomE2EE = false,
      this.onFocusChanged,
      this.readIndicator,
      this.relatedEventBody,
      this.relatedEventThumbnail,
      this.relatedEventTranslationId,
      this.relatedEventSenderColor,
      this.relatedEventSenderName,
      this.interactionType,
      this.forwardBar,
      this.linkPreviewBar,
      this.hasPendingForward = false,
      this.expanded,
      this.focusKeyboard,
      this.setInputText,
      this.isProcessing = false,
      this.initialText,
      this.enabled = true,
      this.editLastMessage,
      this.stepReplyTarget,
      this.hintText,
      this.hintIcon,
      this.attachments,
      this.addAttachment,
      this.checkAttachment,
      this.onTextUpdated,
      this.removeAttachment,
      this.typingIndicatorWidget,
      this.availibleEmoticons,
      this.availibleStickers,
      this.compact = false,
      this.gifComponent,
      this.enableKeyboardAdapter = true,
      this.onReadReceiptsClicked,
      this.findOverrideClient,
      this.onTapOverrideClient,
      this.disableEnterToSend = false,
      this.canSchedule = false,
      this.sendGif,
      this.sendFavoriteGif,
      this.showGifSearch = true,
      this.size = 35,
      this.showMessageEffects = true,
      this.iconScale = 0.5,
      this.showAttachmentButton = true,
      this.sendSticker,
      this.processAutofill,
      this.onSendVoiceMessage,
      this.isDirectMessage = false,
      this.recentTextsFromOthers,
      this.cancelReply});

  /// Sends a recorded voice message; shows the microphone button when set.
  /// Returns false when sending failed.
  final Future<bool> Function(VoiceRecording recording,
      {Client? overrideClient})? onSendVoiceMessage;
  final double maxHeight;
  final double size;
  final double iconScale;

  /// Vommet: the "Send with effect" picker on the Send button. Off in
  /// threads (effect commands post to the main timeline).
  final bool showMessageEffects;
  final bool isRoomE2EE;
  final bool disableEnterToSend;

  /// Vommet: offers Schedule message (MSC4140 delayed events) for this room.
  final bool canSchedule;
  final MessageInputSendResult Function(String message,
      {Client? overrideClient})? onSendMessage;
  final Widget? readIndicator;
  final String? relatedEventBody;

  /// Vommet issue 894: the replied-to picture or video, in the reply strip.
  final Widget? relatedEventThumbnail;

  /// Vommet: the replied-to message's id when "Translate this room" may
  /// translate its quote ([relatedEventBody]); null shows it as it is.
  final String? relatedEventTranslationId;
  final String? relatedEventSenderName;
  final String? hintText;

  /// Vommet: small icon in front of the hint (the room's encryption state).
  final IconData? hintIcon;
  final String? initialText;
  final bool showAttachmentButton;
  final bool compact;
  final bool enableKeyboardAdapter;
  final Color? relatedEventSenderColor;
  final List<PendingFileAttachment>? attachments;
  final EventInteractionType? interactionType;
  final Stream<void>? focusKeyboard;
  final bool showGifSearch;
  final Stream<String>? setInputText;
  final bool isProcessing;
  final bool enabled;
  final Room? room;
  final Client client;
  final Widget? typingIndicatorWidget;
  final List<EmoticonPack>? availibleEmoticons;
  final List<EmoticonPack>? availibleStickers;
  final GifComponent? gifComponent;
  final void Function()? onReadReceiptsClicked;
  final void Function(Emoticon sticker)? sendSticker;
  final Future<void> Function(GifSearchResult gif)? sendGif;
  final Future<void> Function(FavoriteGif gif)? sendFavoriteGif;
  final void Function(bool focused)? onFocusChanged;
  final Function(String currentText)? onTextUpdated;
  final void Function()? cancelReply;

  /// Vommet: shown above the input while a message waits to be forwarded;
  /// the message can then be sent with no text.
  final Widget? forwardBar;

  /// Vommet issue 676: the link preview that sending will attach.
  final Widget? linkPreviewBar;
  final bool hasPendingForward;

  /// Vommet composer round 6 (phones): whether the box fills the chat; the
  /// chat lays itself out by it (`composer_expand.dart`). Null = the box
  /// never expands.
  final ValueNotifier<bool>? expanded;
  final void Function()? editLastMessage;

  // Vommet: Ctrl+↑ / Ctrl+↓ pick the message to reply to (Vommet issue 37)
  final void Function({required bool older})? stepReplyTarget;
  final Client? Function(String input)? findOverrideClient;
  final void Function(Client overrideClient)? onTapOverrideClient;
  final Future<void> Function(PendingFileAttachment attachment)? addAttachment;

  /// Vommet issue 410: false when the file can't be attached (too large); asked
  /// before the attachment dialog opens.
  final Future<bool> Function(PendingFileAttachment attachment)?
      checkAttachment;
  final void Function(PendingFileAttachment attachment)? removeAttachment;
  final List<AutofillSearchResult> Function(String text)? processAutofill;

  /// Vommet issue 680 phase 2: whether this is a DM. (The translate button
  /// shows in every room since the phone composer round 3.)
  final bool isDirectMessage;
  final Iterable<String> Function()? recentTextsFromOthers;

  @override
  State<MessageInput> createState() => MessageInputState();
}

class MessageInputState extends State<MessageInput> {
  String get recoveryKeyPasteTitle => Intl.message(
      "That looks like a recovery key",
      name: "recoveryKeyPasteTitle",
      desc:
          "Message box: title of the dialog shown when the user is about to send what looks like their recovery key");

  String get recoveryKeyPasteBody => Intl.message(
      "With a recovery key, someone can read your message history and impersonate you, and everyone in this chat would have it forever. Nobody needs your recovery key to help you, not even your server's admins.",
      name: "recoveryKeyPasteBody",
      desc: "Message box: body of the recovery key warning dialog");

  String get recoveryKeyPasteDontSend => Intl.message("Don't send it",
      name: "recoveryKeyPasteDontSend",
      desc:
          "Message box: recovery key warning dialog, button that cancels sending");

  String get recoveryKeyPasteSendAnyway => Intl.message(
      "It's not mine, send anyway",
      name: "recoveryKeyPasteSendAnyway",
      desc:
          "Message box: recovery key warning dialog, button that sends the message anyway");

  String get voiceMessageHintNoMicrophone => Intl.message(
      "Can't record: microphone unavailable or not allowed.",
      name: "voiceMessageHintNoMicrophone",
      desc:
          "Message box: short hint shown when a voice message can't be recorded");

  String get voiceMessageHintNothingRecorded => Intl.message(
      "Nothing was recorded.",
      name: "voiceMessageHintNothingRecorded",
      desc: "Message box: short hint shown when a voice recording was empty");

  String get voiceMessageHintHoldToRecord => Intl.message(
      "Hold the microphone to record, release to send.",
      name: "voiceMessageHintHoldToRecord",
      desc:
          "Message box: short hint shown after a quick tap on the microphone button");

  String get voiceMessageHintSendFailed => Intl.message(
      "Voice message could not be sent.",
      name: "voiceMessageHintSendFailed",
      desc:
          "Message box: short hint shown when sending a voice message failed");

  late FocusNode textFocus;
  late ComposerFormatting formatting;
  FocusNode emojiSearchFocus = FocusNode();
  FocusNode stickerSearchFocus = FocusNode();
  FocusNode gifSearchFocus = FocusNode();

  late TextEditingController controller;
  late JustTheController emojiOverlayController = JustTheController();
  StreamSubscription? keyboardFocusSubscription;
  StreamSubscription? setInputTextSubscription;
  StreamSubscription? onScopePopInvoked;
  OverlayEntry? entry;
  final layerLink = LayerLink();
  bool showEmotePicker = false;
  bool emotePickerActive = false;
  bool hasEmotePickerOpened = false;
  List<AutofillSearchResult>? autoFillResults;
  Client? senderOverride;

  // Vommet issue 597: only the sender can edit a message, so an edit is never
  // sent from another account.
  bool get _editing => widget.interactionType == EventInteractionType.edit;
  JustTheController emojiTooltipController = JustTheController();

  KeyboardAdaptorController keyboardAdaptorController =
      KeyboardAdaptorController();

  int? autoFillSelection;
  (int, int)? autoFillRange;
  ScrollController autofillScrollController = ScrollController();

  // Vommet: on phones, autocomplete floats over the timeline above the box.
  final autofillLink = LayerLink();
  final autofillPortal = OverlayPortalController();

  void unfocus() {
    textFocus.unfocus();
  }

  @override
  void didUpdateWidget(covariant MessageInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room != widget.room) {
      autoFillResults = null;
      autoFillSelection = null;
      autoFillRange = null;
    }
    if (oldWidget.expanded != widget.expanded) {
      oldWidget.expanded?.removeListener(onExpandedChanged);
      widget.expanded?.addListener(onExpandedChanged);
    }

    // Vommet: the text field is read-only while attachments upload. On the
    // web, the browser's text input stays dead when it turns editable again,
    // so typing did nothing until another room was opened (Vommet issue
    // 608). Focus it afresh to reconnect it.
    if (PlatformUtils.isWeb &&
        oldWidget.isProcessing &&
        !widget.isProcessing &&
        textFocus.hasFocus) {
      textFocus.unfocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) textFocus.requestFocus();
      });
    }
  }

  void onKeyboardFocusRequested() {
    textFocus.requestFocus();
  }

  /// Vommet issue 680 phase 2; null where translation can't run.
  ComposerTranslation? composerTranslation;

  void onComposerTranslationChanged() {
    if (mounted) setState(() {});
  }

  /// 文A: sets the target of the paragraph under the caret (or opens its
  /// menu when it has one).
  Future<void> onTranslateChipTap() async {
    final t = composerTranslation;
    if (t == null || t.busy) return;
    final caret = controller.selection.isValid
        ? controller.selection.extentOffset
        : controller.text.length;
    final text = await t.tapChip(context, controller.text, caret);
    if (text == null || !mounted) return;
    onSetInputText(text);
  }

  /// A paragraph's menu: from its tag ([line]), or 文A long-pressed (the
  /// paragraph under the caret).
  Future<void> openParagraphMenu([int? line]) async {
    final t = composerTranslation;
    if (t == null || t.busy) return;
    final draft = controller.text;
    final caret = controller.selection.isValid
        ? controller.selection.extentOffset
        : draft.length;
    final text = await t.paragraphMenu(
        context, draft, line ?? paragraphAt(draft, caret));
    if (text == null || !mounted) return;
    onSetInputText(text);
  }

  void undoTranslation() {
    final original = composerTranslation?.undo();
    if (original != null) onSetInputText(original);
  }

  void onSetInputText(String newText) {
    controller.text = newText;
    controller.selection =
        TextSelection(baseOffset: newText.length, extentOffset: newText.length);

    onTextfieldUpdated(newText);
  }

  @override
  void dispose() {
    widget.expanded?.removeListener(onExpandedChanged);
    controller.removeListener(measureDraftSoon);
    // A banned / replaced room swaps the box out; the chat goes back to
    // normal after this frame.
    if (widget.expanded case final expanded? when expanded.value) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => expanded.value = false);
    }
    hideVoiceHint();
    voiceTicker?.cancel();
    voiceLevelSub?.cancel();
    voiceRecorder?.dispose();
    keyboardFocusSubscription?.cancel();
    appFocusSubscription?.cancel();
    refocusTimer?.cancel();
    setInputTextSubscription?.cancel();
    preferencesSubscription?.cancel();
    Spellcheck.instance.removeListener(onSpellcheckChanged);
    stopWebPaste?.call();
    formatting.dispose();
    textScroll.dispose();
    onScopePopInvoked?.cancel();
    // Vommet: a pending debounce outlived the composer and called setState on
    // a disposed keyboard adaptor when the room closed within a second.
    removeHeightOverrideDebouncer.cancel();
    composerTranslation?.removeListener(onComposerTranslationChanged);
    composerTranslation?.dispose();
    super.dispose();
  }

  StreamSubscription? preferencesSubscription;
  StreamSubscription? appFocusSubscription;
  Timer? refocusTimer;
  bool wasAppFocused = AppFocus.focused;

  // Desktop: when the window regains focus while this chat is open, put the
  // cursor back in the message input (part of "Autofocus Message Input").
  void onAppFocusChanged(void _) {
    final focused = AppFocus.focused;
    final regained = focused && !wasAppFocused;
    wasAppFocused = focused;

    if (!regained) {
      refocusTimer?.cancel();
      return;
    }

    if (!BuildConfig.DESKTOP || !preferences.autoFocusMessageTextBox.value) {
      return;
    }

    // Give the click that brought the window back time to land, so it can
    // keep any focus it gives to something else (a field, a message).
    refocusTimer?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final focusBeforeClick = FocusManager.instance.primaryFocus;
      refocusTimer?.cancel();
      refocusTimer = Timer(const Duration(milliseconds: 150),
          () => refocusAfterAppResumed(focusBeforeClick));
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void refocusAfterAppResumed(FocusNode? focusBeforeClick) {
    if (!mounted || textFocus.hasFocus || !AppFocus.focused) return;

    // The click that brought the window back focused something else.
    final focus = FocusManager.instance.primaryFocus;
    if (focus != focusBeforeClick) return;

    // A dialog, menu or another page is on top of this chat.
    if (ModalRoute.of(context)?.isCurrent == false) return;
    if (!TickerMode.of(context)) return;

    // Another text field (search, a thread's input, ...) kept its focus.
    if (focusIsOnTextField(focus)) return;

    textFocus.requestFocus();
  }

  @override
  void initState() {
    autofillPortal.show();
    controller = RichTextEditingController(
        client: widget.client, room: widget.room, text: widget.initialText);
    if (widget.initialText?.isNotEmpty == true) {
      controller.selection =
          TextSelection.collapsed(offset: widget.initialText!.length);
    }
    controller.addListener(controllerListener);
    controller.addListener(measureDraftSoon);
    widget.expanded?.addListener(onExpandedChanged);
    composerEmpty = controller.text.isEmpty;
    controller.addListener(onComposerTextChanged);
    keyboardFocusSubscription =
        widget.focusKeyboard?.listen((_) => onKeyboardFocusRequested());
    appFocusSubscription = AppFocus.focusStateChanged.listen(onAppFocusChanged);

    setInputTextSubscription = widget.setInputText?.listen(onSetInputText);
    onScopePopInvoked = EventBus.onPopInvoked.stream.listen(onPopped);

    // Vommet: on the web, pasted pictures arrive as DOM paste events.
    if (kIsWeb) {
      stopWebPaste = WebPaste.listenForImages((data) {
        if (!mounted || !textFocus.hasFocus) return;
        attachPastedImage(data);
      });
    }

    textFocus = FocusNode(onKeyEvent: onKey);
    textFocus.addListener(onTextFocusChanged);
    formatting =
        ComposerFormatting(controller: controller, focusNode: textFocus);

    preferencesSubscription =
        preferences.onSettingChanged.listen((_) => setState(() {}));

    // Vommet: spellcheck underline follows dictionary and word-list changes.
    if (Spellcheck.supported) {
      Spellcheck.instance.ensureInit();
      Spellcheck.instance.addListener(onSpellcheckChanged);
    }

    if (widget.room != null && MessageTranslation.instance.supported) {
      composerTranslation = ComposerTranslation(
          roomId: widget.room!.identifier,
          recentTextsFromOthers: widget.recentTextsFromOthers ?? () => const [])
        ..addListener(onComposerTranslationChanged);
    }

    if (preferences.autoFocusMessageTextBox.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        textFocus.requestFocus();
      });
    }

    super.initState();
  }

  String? lastSearchText;
  void onTextfieldUpdated(String value) {
    widget.onTextUpdated?.call(controller.text);
    if (value.trim().isEmpty) composerTranslation?.refreshDetected();
    composerTranslation?.onDraftChanged(controller.text);
    var range = getAutofillTextRange();

    setState(() {
      senderOverride = widget.findOverrideClient?.call(controller.text);
    });

    if (range.$1 == -1 || range.$2 == -1) {
      return;
    }

    var text = value.substring(range.$1, range.$2);

    if (text == "") {
      setState(() {
        autoFillResults = null;
        autoFillSelection = null;
        autoFillRange = null;
      });
    }

    if (text == lastSearchText) {
      return;
    }

    if (text.isEmpty) {
      setState(() {
        autoFillResults = [];
        autoFillSelection = null;
        updateAutofillScroll();
      });

      return;
    }

    var result = widget.processAutofill?.call(text);
    autoFillRange = range;

    setState(() {
      autoFillResults = result;

      if (MediaQuery.of(context).desktop &&
          result?.isNotEmpty == true &&
          preferences.selectAutoCompleteSuggestion.value) {
        autoFillSelection = 0;
      } else {
        autoFillSelection = null;
      }
      updateAutofillScroll();
    });
  }

  (int, int) getAutofillTextRange({int? cursorPosition}) {
    var cursor = controller.selection.base.offset;

    if (controller.text == "") {
      return (0, 0);
    }

    int start = cursorPosition ?? cursor;
    int end = controller.text.length;

    if (start > 0) {
      start -= 1;
      if (controller.text[start] == ' ') {
        return (0, 0);
      }
    }

    for (int i = start; i >= 0; i--) {
      var char = controller.text[i];
      if (char == ' ') {
        if (i == controller.text.length) {
          start = controller.text.length - 1;
        } else {
          start = i + 1;
        }

        break;
      }

      if (i <= 0) {
        start = 0;
      }
    }

    for (var i = start + 1; i < controller.text.length; i++) {
      var char = controller.text[i];
      if (char == ' ') {
        end = i;
        break;
      }
    }

    return (start, end);
  }

  Debouncer sendDebouncer = Debouncer(delay: Duration(milliseconds: 20));
  // Vommet: set once the user confirmed sending text that looks like a
  // recovery key, so the retried send goes through.
  bool _recoveryKeyConfirmed = false;

  void sendMessage() {
    sendDebouncer.run(() async {
      if ((widget.attachments == null || widget.attachments!.isEmpty) &&
          !widget.hasPendingForward) {
        if (controller.text.isEmpty) return;
        if (controller.text.trim().isEmpty) return;
      }

      if (blockedByRecoveryKeyGuard()) return;

      var message = controller.text.trim();

      // Vommet: paragraphs with a target language go out translated (or
      // nothing goes, saying which paragraph couldn't be).
      final translation = composerTranslation;
      if (translation != null && senderOverride == null && message.isNotEmpty) {
        final outgoing =
            await translation.prepareSend(context, controller.text);
        if (outgoing == null || !mounted) return;
        message = outgoing.trim();
      }

      // Vommet composer round 5: the effect picked in + rides on this one
      // message. A scheduled send can't carry it (the effect command sends
      // right away), so it then stays picked for the next message.
      final effect =
          ScheduledMessages.currentRequest == null ? activeEffect : null;
      var result = widget.onSendMessage?.call(
          effect == null ? message : effect.commandText(message),
          overrideClient: _editing ? null : senderOverride);

      if (result == MessageInputSendResult.success) {
        controller.text = "";
        setExpanded(false);
        if (effect != null) pickEffect(null);
        composerTranslation?.onSent(message);
      }
    });
  }

  /// Vommet: never let someone paste their own recovery key into a chat
  /// without stopping them first. Returns true when the send must wait for
  /// the user's answer; sending again after "send anyway" goes through.
  bool blockedByRecoveryKeyGuard() {
    if (_recoveryKeyConfirmed) {
      _recoveryKeyConfirmed = false;
      return false;
    }
    if (!preferences.experimentDmTrustWarnings.value ||
        !RecoveryKeyGuard.containsRecoveryKey(controller.text)) {
      return false;
    }
    confirmSendRecoveryKey().then((send) {
      if (send == true && mounted) {
        _recoveryKeyConfirmed = true;
        sendMessage();
      }
    });
    return true;
  }

  Future<bool?> confirmSendRecoveryKey() {
    return AdaptiveDialog.show<bool>(context,
        title: recoveryKeyPasteTitle,
        builder: (context) => ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(recoveryKeyPasteBody),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Text(recoveryKeyPasteDontSend),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: Text(recoveryKeyPasteSendAnyway),
                    ),
                  ],
                ),
              ),
            ));
  }

  void showMoreAttachmentOptions() {}

  // This duration is to try and hide the transition from keyboard popup animation
  Debouncer removeHeightOverrideDebouncer =
      Debouncer(delay: Duration(seconds: 1));

  bool get isInEmojiPicker => showEmotePicker && !textFocus.hasFocus;

  Future<void> toggleEmojiOverlay() async {
    var keyboardOpen = await isKeyboardOpen();
    print("Keyboard open: $keyboardOpen");

    setState(() {
      if (MediaQuery.of(context).mobile) {
        if (showEmotePicker && !keyboardOpen) {
          // STUPID: since we use android api to dismiss keyboard,
          // requesting focus normally doesnt work, but if we do this
          // we can get the onscreen keyboard back
          unfocus();
          Future.delayed(Duration(milliseconds: 100)).then((_) {
            textFocus.requestFocus();
          });
          emotePickerActive = false;
          clearKeyboardOverride();
        } else {
          showEmotePicker = true;
          emotePickerActive = true;
          keyboardAdaptorController.keepCurrentSize?.call();
          removeHeightOverrideDebouncer.cancel();
          if (textFocus.hasFocus) {
            dismissKeyboard();
          }
        }
      }

      if (MediaQuery.of(context).desktop) {
        showEmotePicker = !showEmotePicker;
        emotePickerActive = showEmotePicker;
        emojiTooltipController.showTooltip(autoClose: false);
      }

      if (showEmotePicker) {
        hasEmotePickerOpened = true;
      }
    });
  }

  void clearKeyboardOverride({bool debounce = true}) {
    final func = () {
      if (showEmotePicker) {
        showEmotePicker = false;
        emotePickerActive = false;
      }

      if (!showEmotePicker) {
        keyboardAdaptorController.clearOverride?.call();
      }
    };

    if (!debounce) {
      removeHeightOverrideDebouncer.cancel();
      func();
    }

    setState(() {
      emotePickerActive = false;
    });

    removeHeightOverrideDebouncer.run(func);
  }

  /// Vommet composer round 5: the effect picked under + for the next
  /// message (shown as a chip above the box and a badge on Send).
  MessageEffectOption? pendingEffect;

  void pickEffect(MessageEffectOption? effect) {
    if (mounted) setState(() => pendingEffect = effect);
  }

  /// Whether an effect can go out right now: effects on, not editing, no
  /// attachments or forward, not another account's prefix (the effect
  /// commands handle none of these).
  bool get effectsAvailable =>
      widget.showMessageEffects &&
      preferences.messageEffectsEnabled.value &&
      widget.interactionType != EventInteractionType.edit &&
      widget.attachments?.isNotEmpty != true &&
      !widget.hasPendingForward &&
      senderOverride == null;

  List<MessageEffectOption> get availableEffects => effectsAvailable
      ? MessageEffectPicker.available(widget.room?.client)
      : const [];

  /// The picked effect, when it can go out with the next message.
  MessageEffectOption? get activeEffect =>
      effectsAvailable ? pendingEffect : null;

  void dismissKeyboard() {
    if (BuildConfig.ANDROID) {
      const platform = const MethodChannel('chat.commet.commetapp/utils');
      platform.invokeMethod("dismissKeyboard");
    }
  }

  Future<bool> isKeyboardOpen() async {
    if (BuildConfig.ANDROID) {
      const platform = const MethodChannel('chat.commet.commetapp/utils');
      var result = await platform.invokeMethod<bool>("isKeyboardOpen");
      return result!;
    } else {
      return textFocus.hasFocus;
    }
  }

  void onTextFocusChanged() {
    if (textFocus.hasFocus) {
      clearKeyboardOverride();
    }
  }

  void updateAutofillScroll() {
    if (!autofillScrollController.hasClients) {
      return;
    }
    if (autoFillSelection == null) {
      autofillScrollController.jumpTo(0);
      return;
    }

    int totalChars = 0;
    int selectionChars = 0;
    for (int i = 0; i < autoFillResults!.length; i++) {
      totalChars += autoFillResults![i].result.length;

      if (autoFillSelection! > i) {
        selectionChars += autoFillResults![i].result.length;
      }
    }

    var maxOffset = autofillScrollController.position.maxScrollExtent;

    var amount = selectionChars.toDouble() / totalChars.toDouble();
    var offset = (maxOffset * amount) - 50;

    if (offset < 0) {
      offset = 0;
    }

    var distance = (offset - autofillScrollController.offset).abs();
    var maxDistance =
        autofillScrollController.position.viewportDimension * 0.25;

    if (distance > maxDistance) {
      autofillScrollController.animateTo(offset,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOutExpo);
    }
  }

  bool isKnownAutofillMatch(String text) {
    if (text.startsWith("@") || text.startsWith("!")) {
      return text.isValidMatrixId;
    }

    if (text.startsWith(":") && text.endsWith(":")) {
      return true;
    } else {
      return false;
    }
  }

  // Vommet: the send button (and the voice button) depend on whether the
  // composer is empty, but only typing rebuilt them via onChanged. Emoji
  // picks, autofill completions and edit cancels change the controller
  // directly, so the button stayed as the poll menu after an emoji.
  bool composerEmpty = true;
  void onSpellcheckChanged() {
    if (mounted) setState(() {});
  }

  void onComposerTextChanged() {
    if (!mounted || controller.text.isEmpty == composerEmpty) return;
    setState(() => composerEmpty = controller.text.isEmpty);
  }

  TextSelection? prevSelection;

  void controllerListener() {
    if (PlatformUtils.isAndroid) {
      return;
    }

    if (preferences.disableTextCursorManagement.value) {
      return;
    }

    var startFill =
        getAutofillTextRange(cursorPosition: controller.selection.baseOffset);

    var endFill =
        getAutofillTextRange(cursorPosition: controller.selection.extentOffset);

    var len = controller.selection.start - controller.selection.end;

    var baseOffset = controller.selection.baseOffset;
    var extentOffset = controller.selection.extentOffset;

    if (baseOffset == -1 || extentOffset == -1) {
      return;
    }

    var text = controller.text.substring(startFill.$1, startFill.$2);
    var endText = controller.text.substring(endFill.$1, endFill.$2);
    if (isKnownAutofillMatch(text)) {
      // go forward
      if ((prevSelection != null &&
          prevSelection!.baseOffset < controller.selection.baseOffset)) {
        baseOffset = startFill.$2;
      } else {
        // go backward
        if (baseOffset > startFill.$1 && baseOffset != startFill.$2) {
          baseOffset = startFill.$1;
        }
      }
    }

    if (isKnownAutofillMatch(endText) && len != 0) {
      // go forward
      if ((prevSelection != null &&
          prevSelection!.extentOffset < controller.selection.extentOffset)) {
        extentOffset = endFill.$2;
      } else {
        // go backward
        if (extentOffset > endFill.$1) {
          extentOffset = endFill.$1;
        }
      }
    }

    if (len == 0) {
      extentOffset = baseOffset;
    }
    controller.selection =
        TextSelection(baseOffset: baseOffset, extentOffset: extentOffset);

    prevSelection = controller.selection;
  }

  KeyEventResult onKey(FocusNode node, KeyEvent event) {
    if (formatting.handleKey(event)) return KeyEventResult.handled;
    if (BuildConfig.MOBILE) return KeyEventResult.ignored;

    if (!preferences.disableTextCursorManagement.value) {
      if (HardwareKeyboard.instance
          .isLogicalKeyPressed(LogicalKeyboardKey.backspace)) {
        var selection = controller.selection.baseOffset;
        var selectionEnd = controller.selection.extentOffset;

        var range = getAutofillTextRange();

        if (range.$1 < selection) {
          selection = range.$1;
        }

        if (range.$2 > selectionEnd) {
          selectionEnd = range.$2;
        }

        var text = controller.text.substring(range.$1, range.$2);

        if (isKnownAutofillMatch(text)) {
          controller.text =
              controller.text.replaceRange(selection, selectionEnd, "");
          onTextfieldUpdated(controller.text);
          return KeyEventResult.handled;
        }
      }
    }

    if (HardwareKeyboard.instance
        .isLogicalKeyPressed(LogicalKeyboardKey.keyV)) {
      if (ClipboardFiles.isPasteModifier(
          control: HardwareKeyboard.instance.isControlPressed,
          meta: HardwareKeyboard.instance.isMetaPressed)) {
        if (ClipboardFiles.supported &&
            event is! KeyUpEvent &&
            event.logicalKey == LogicalKeyboardKey.keyV) {
          // Copied files usually come with their paths as text too; attach
          // them instead of pasting the paths (Vommet issue 328).
          pasteFromKeyboard();
          return KeyEventResult.handled;
        }
        readImageFromClipboard();
        return KeyEventResult.ignored;
      }
    }

    if (HardwareKeyboard.instance.isLogicalKeyPressed(LogicalKeyboardKey.tab)) {
      if (autoFillResults == null || autoFillResults!.isEmpty) {
        autoFillSelection = null;
        return KeyEventResult.ignored;
      } else {
        if (autoFillSelection == null) {
          setState(() {
            autoFillSelection = 0;
            updateAutofillScroll();
          });
        } else {
          setState(() {
            autoFillSelection = (autoFillSelection! + 1);
            if (autoFillSelection! >= autoFillResults!.length) {
              autoFillSelection = 0;
            }

            updateAutofillScroll();
          });
        }

        return KeyEventResult.handled;
      }
    }

    if (widget.disableEnterToSend != true) {
      // Vommet: act on the Enter key's own key-down only. Checking whether
      // Enter is held also matched repeats, key-ups and other keys typed
      // while it was still down, which sent the message twice (Vommet
      // issue 333).
      if (event.logicalKey == LogicalKeyboardKey.enter) {
        // Vommet: Ctrl+Enter adds a line break like Shift+Enter (Vommet
        // issue 487). The text field doesn't insert one for it, so do it
        // here.
        if (HardwareKeyboard.instance.isControlPressed &&
            !HardwareKeyboard.instance.isShiftPressed) {
          if (event is! KeyUpEvent) insertNewline();
          return KeyEventResult.handled;
        }

        if (event is! KeyDownEvent) {
          return HardwareKeyboard.instance.isShiftPressed
              ? KeyEventResult.ignored
              : KeyEventResult.handled;
        }

        if (autoFillSelection != null && autoFillRange != null) {
          applyAutoFill(autoFillResults![autoFillSelection!]);
          return KeyEventResult.handled;
        }

        if (HardwareKeyboard.instance.isShiftPressed) {
          return KeyEventResult.ignored;
        }

        sendMessage();
        return KeyEventResult.handled;
      }
    }

    if (HardwareKeyboard.instance
        .isLogicalKeyPressed(LogicalKeyboardKey.escape)) {
      doCancelInteraction();
      return KeyEventResult.handled;
    }

    // Vommet: Ctrl+↑ / Ctrl+↓ reply to an earlier / later message, as in
    // Telegram Desktop (Vommet issue 37).
    if (event is! KeyUpEvent &&
        widget.stepReplyTarget != null &&
        HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isAltPressed &&
        !HardwareKeyboard.instance.isShiftPressed &&
        (event.logicalKey == LogicalKeyboardKey.arrowUp ||
            event.logicalKey == LogicalKeyboardKey.arrowDown)) {
      widget.stepReplyTarget!(
          older: event.logicalKey == LogicalKeyboardKey.arrowUp);
      return KeyEventResult.handled;
    }

    if (HardwareKeyboard.instance
            .isLogicalKeyPressed(LogicalKeyboardKey.arrowUp) &&
        // Vommet: Alt+Up switches rooms (Vommet issues 290/499).
        !HardwareKeyboard.instance.isAltPressed &&
        controller.text.isEmpty) {
      widget.editLastMessage?.call();
      // Handled so the platform text input doesn't write its stale empty
      // value back over the edit text (Vommet issue 898).
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void insertNewline() {
    final value = controller.value;
    final selection = value.selection;
    if (!selection.isValid) {
      controller.text += "\n";
    } else {
      controller.value = value.replaced(selection, "\n");
    }
    onTextfieldUpdated(controller.text);
  }

  void applyAutoFill(AutofillSearchResult result) {
    var replacement = result.slug;

    var checkWhitespaceAt = autoFillRange!.$2;

    if (checkWhitespaceAt < controller.text.length) {
      if (controller.text[checkWhitespaceAt] != " ") {
        replacement = "$replacement ";
      }
    } else {
      replacement = "$replacement ";
    }

    controller.text = controller.text
        .replaceRange(autoFillRange!.$1, autoFillRange!.$2, replacement);
    setState(() {
      autoFillSelection = null;
      autoFillResults = null;
      autoFillRange = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Vommet composer round 6: expanded only where the chat gives the box
    // a height to fill.
    return LayoutBuilder(builder: (context, constraints) {
      expandedLayout =
          expandable && widget.expanded!.value && constraints.hasBoundedHeight;
      return buildComposer(context);
    });
  }

  Widget buildComposer(BuildContext context) {
    var padding = const EdgeInsets.fromLTRB(0, 0, 0, 0);

    return Material(
      color: Colors.transparent,
      child: TextFieldTapRegion(
        child: IgnorePointer(
          ignoring: widget.isProcessing,
          child: Opacity(
            opacity: widget.isProcessing ? 0.5 : 1,
            child: KeyboardAdaptor(
              enabled: widget.enableKeyboardAdapter,
              paddingContent: (MediaQuery.of(context).mobile && showEmotePicker)
                  ? buildEmojiPicker()
                  : Container(),
              shouldPushContent: () {
                if (emojiSearchFocus.hasFocus) {
                  return true;
                }

                if (stickerSearchFocus.hasFocus) {
                  return true;
                }

                if (gifSearchFocus.hasFocus) {
                  return true;
                }

                return false;
              },
              controller: keyboardAdaptorController,
              expandChild: expandedLayout,
              child: Column(
                mainAxisSize:
                    expandedLayout ? MainAxisSize.max : MainAxisSize.min,
                children: [
                  if (widget.typingIndicatorWidget != null)
                    widget.typingIndicatorWidget!,
                  if (widget.interactionType != null) interactionText(),
                  if (widget.forwardBar != null) widget.forwardBar!,
                  if (widget.linkPreviewBar != null) widget.linkPreviewBar!,
                  ...translationLines(),
                  if (widget.attachments != null &&
                      widget.attachments!.isNotEmpty)
                    displayAttachments(),
                  // Vommet: messages waiting to be sent in this room.
                  if (widget.canSchedule && widget.room != null)
                    ScheduledMessagesBar(
                        room: widget.room!,
                        onEdit: (text) {
                          controller.text = text;
                          controller.selection =
                              TextSelection.collapsed(offset: text.length);
                        }),
                  // No bottom row on phones: the "sending as" chip and
                  // the format row go above the box.
                  if (MediaQuery.of(context).mobile &&
                      !widget.compact &&
                      senderOverride != null &&
                      !_editing)
                    senderOverrideView(),
                  if (MediaQuery.of(context).mobile)
                    formatting.mobileRow(context),
                  // Vommet composer round 5: the effect picked for the
                  // next message.
                  if (activeEffect case final effect? when !voiceRecording)
                    ComposerEffectChip(
                        effect: effect, onClear: () => pickEffect(null)),
                  // Zero-height anchor at the box's top edge.
                  if (!widget.compact && MediaQuery.of(context).mobile)
                    phoneAutofillAnchor(),
                  Flexible(
                    flex: expandedLayout ? 1 : 0,
                    fit: FlexFit.tight,
                    child: ConstrainedBox(
                      constraints: expandedLayout
                          ? const BoxConstraints()
                          : const BoxConstraints(maxHeight: 200),
                      child: Padding(
                        padding: padding,
                        child: Row(
                            crossAxisAlignment: expandedLayout
                                ? CrossAxisAlignment.stretch
                                : CrossAxisAlignment.center,
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Vommet composer round 5: one bar. + on the
                              // left and record (Send while there's text) on
                              // the right sit inside the box.
                              Flexible(
                                key: const ValueKey("composer-input"),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(
                                      currentLayoutStyle == LayoutStyle.discord
                                          ? 8
                                          : widget.size / 2 + 2),
                                  child: Container(
                                    decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .surfaceContainerLow),
                                    child: Stack(
                                        fit: StackFit.passthrough,
                                        children: [
                                          Row(
                                            // Round 6: a tall box keeps + and
                                            // Send at the bottom, beside the text.
                                            crossAxisAlignment: tallBox
                                                ? CrossAxisAlignment.end
                                                : CrossAxisAlignment.center,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (widget.enabled &&
                                                  widget.showAttachmentButton &&
                                                  !voiceRecording)
                                                KeyedSubtree(
                                                    key: const ValueKey(
                                                        "composer-attach"),
                                                    child:
                                                        addAttachmentButton()),
                                              Flexible(
                                                key: const ValueKey(
                                                    "composer-input-field"),
                                                child: voiceRecording
                                                    ? VoiceRecordingBar(
                                                        elapsed: voiceRecorder
                                                                ?.elapsed ??
                                                            Duration.zero,
                                                        levels: voiceLevels,
                                                        holdMode: voiceHoldMode,
                                                        dragDx: voiceDragDx,
                                                        cancelDistance:
                                                            voiceCancelDistance,
                                                        onCancel:
                                                            cancelVoiceRecording,
                                                      )
                                                    : fieldWithButtons(context),
                                              ),
                                              // Keyed: starting a recording swaps
                                              // the buttons around. Unkeyed, the
                                              // mic button would be matched to
                                              // another button's old element and
                                              // rebuilt mid-press, dropping the
                                              // long-press (no slide-to-cancel, no
                                              // release-to-send).
                                              if (showVoiceButton)
                                                KeyedSubtree(
                                                    key: const ValueKey(
                                                        "composer-voice"),
                                                    child: voiceMessageButton())
                                              else if (widget.enabled &&
                                                  !voiceRecording)
                                                KeyedSubtree(
                                                    key: const ValueKey(
                                                        "composer-send"),
                                                    child: sendMessageButton()),
                                            ],
                                          ),
                                          if (showExpandButton)
                                            Positioned(
                                              top: 2,
                                              right: 2,
                                              child: ComposerExpandButton(
                                                  expanded: expandedLayout,
                                                  onTap: () => setExpanded(
                                                      !expandedLayout)),
                                            ),
                                        ]),
                                  ),
                                ),
                              ),
                            ]),
                      ),
                    ),
                  ),
                  if (!widget.compact && !MediaQuery.of(context).mobile)
                    SizedBox(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(0, 2, 0, 0),
                        child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const SizedBox(height: 30),
                              if (senderOverride != null && !_editing)
                                senderOverrideView(),
                              if (autoFillResults != null)
                                autofillResultsList(),
                              if (autoFillResults == null)
                                const Expanded(child: SizedBox()),
                            ]),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget senderOverrideView() {
    final profile = senderOverride?.self;
    if (profile == null) {
      return Container();
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        height: 30,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 2, 2, 2),
          child: Material(
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.hardEdge,
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: InkWell(
              mouseCursor: WidgetStateMouseCursor.clickable,
              onTap: () {
                widget.onTapOverrideClient?.call(senderOverride!);
              },
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Row(
                  children: [
                    SizedBox(
                      width: 5,
                    ),
                    tiamat.Avatar(
                        radius: 10,
                        image: profile.avatar,
                        placeholderColor: profile.defaultColor,
                        placeholderText: profile.displayName),
                    SizedBox(
                      width: 10,
                    ),
                    tiamat.Text.labelLow("Sending as: ${profile.displayName}"),
                    SizedBox(
                      width: 5,
                    )
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Vommet: on phones, autocomplete results float over the timeline as a
  // vertical card right above the box, without moving anything.
  // The anchor is a zero-height, full-width strip on the box's top edge, so
  // the card gets the box's width from the link. In the expanded composer
  // the box fills the chat, so the card hangs inside it, under its top edge.
  Widget phoneAutofillAnchor() {
    return OverlayPortal(
      controller: autofillPortal,
      overlayChildBuilder: phoneAutofillCard,
      child: CompositedTransformTarget(
        link: autofillLink,
        child: const SizedBox(width: double.infinity, height: 0),
      ),
    );
  }

  Widget phoneAutofillCard(BuildContext context) {
    final results = autoFillResults;
    if (results == null || results.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final width = autofillLink.leaderSize?.width ?? double.infinity;
    const rowHeight = 46.0;

    return Align(
      alignment: Alignment.topLeft,
      child: CompositedTransformFollower(
        link: autofillLink,
        showWhenUnlinked: false,
        targetAnchor: Alignment.topLeft,
        followerAnchor:
            expandedLayout ? Alignment.topLeft : Alignment.bottomLeft,
        offset: Offset(0, expandedLayout ? 5 : -5),
        child: TextFieldTapRegion(
          child: SizedBox(
            key: const ValueKey("composer-autofill-card"),
            width: width,
            child: Material(
              color: scheme.surfaceContainer,
              elevation: 2,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: rowHeight * 4),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: results.length,
                  itemExtent: rowHeight,
                  itemBuilder: (context, index) {
                    final data = results[index];
                    final selected = autoFillSelection != null &&
                        autoFillSelection! < results.length &&
                        data == results[autoFillSelection!];
                    return Material(
                      color: selected
                          ? scheme.secondaryContainer
                          : Colors.transparent,
                      child: InkWell(
                        onTap: () => applyAutoFill(data),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            children: [
                              if (data is AutofillSearchResultEmoticon)
                                SizedBox(
                                  width: 30,
                                  height: 30,
                                  child: EmojiWidget(data.emoticon),
                                ),
                              if (data is AutofillSearchResultAvatar)
                                tiamat.Avatar(
                                  image: data.image,
                                  radius: 15,
                                  placeholderColor: data.fallbackColor,
                                  placeholderText: data.result,
                                ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  data.result,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(color: scheme.onSurface),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Expanded autofillResultsList() {
    return Expanded(
      child: ShaderMask(
        shaderCallback: (rect) {
          return const LinearGradient(
            begin: Alignment.centerRight,
            end: Alignment.center,
            colors: [
              Colors.purple,
              Colors.transparent,
            ],
            stops: [
              0.0,
              0.1,
            ],
          ).createShader(rect);
        },
        blendMode: BlendMode.dstOut,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 0),
          child: SizedBox(
            height: 30,
            child: Listener(
              onPointerSignal: (event) {
                if (!MediaQuery.of(context).desktop) return;
                if (event is PointerScrollEvent) {
                  final offset = event.scrollDelta.dy;

                  autofillScrollController.jumpTo(
                      (autofillScrollController.offset + offset).clamp(0,
                          autofillScrollController.position.maxScrollExtent));
                }
              },
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(0, 0, 300, 0),
                itemCount: autoFillResults!.length,
                controller: autofillScrollController,
                shrinkWrap: true,
                itemBuilder: (context, index) {
                  bool selected = false;
                  var data = autoFillResults![index];
                  if (autoFillSelection != null) {
                    selected = data == autoFillResults![autoFillSelection!];
                  }

                  return ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: Material(
                      color: selected
                          ? Theme.of(context).colorScheme.secondary
                          : Colors.transparent,
                      child: InkWell(
                        mouseCursor: WidgetStateMouseCursor.clickable,
                        onTap: () => applyAutoFill(data),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(4, 1, 4, 1),
                          child: Row(
                            children: [
                              if (data is AutofillSearchResultEmoticon)
                                EmojiWidget(data.emoticon),
                              if (data is AutofillSearchResultAvatar)
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(0, 0, 3, 0),
                                  child: tiamat.Avatar(
                                      image: data.image,
                                      radius: 10,
                                      placeholderColor: data.fallbackColor,
                                      placeholderText: data.result),
                                ),
                              tiamat.Text.labelLow(
                                data.result,
                                color: selected
                                    ? Theme.of(context).colorScheme.onSecondary
                                    : Theme.of(context).colorScheme.secondary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- voice messages ------------------------------------------------------

  static const double voiceCancelDistance = 80;
  static const Duration voiceMinDuration = Duration(milliseconds: 600);

  /// Replaced in widget tests, which have no microphone.
  static VoiceRecorder Function() createVoiceRecorder = VoiceRecorder.new;

  VoiceRecorder? voiceRecorder;
  bool voiceRecording = false;
  bool voiceStarting = false;
  bool voiceHoldMode = false;
  bool voiceReleasedWhileStarting = false;
  bool voiceSending = false;
  double voiceDragDx = 0;
  List<double> voiceLevels = const [];
  Timer? voiceTicker;
  StreamSubscription<double>? voiceLevelSub;

  bool get showVoiceButton {
    if (widget.onSendVoiceMessage == null || !widget.enabled) return false;
    if (voiceRecording || voiceStarting || voiceSending) return true;
    return controller.text.isEmpty &&
        widget.attachments?.isNotEmpty != true &&
        !widget.hasPendingForward;
  }

  OverlayEntry? voiceHintEntry;
  Timer? voiceHintTimer;

  void showVoiceHint(String text) {
    // A SnackBar only shows under a Scaffold, and the desktop chat layout
    // has none (Vommet issue 558: the hint never appeared on Windows). Fall
    // back to a short-lived pill just above the message box.
    if (Scaffold.maybeOf(context) != null) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(text)));
      return;
    }
    final overlay = Overlay.maybeOf(context);
    final box = context.findRenderObject() as RenderBox?;
    if (overlay == null || box == null || !box.hasSize) return;
    hideVoiceHint();
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    final top = box.localToGlobal(Offset.zero, ancestor: overlayBox);
    final bottom = (overlayBox?.size.height ?? top.dy) - top.dy + 8;
    final left = top.dx;
    final width = box.size.width;
    final scheme = Theme.of(context).colorScheme;
    voiceHintEntry = OverlayEntry(
        builder: (_) => Positioned(
              left: left,
              width: width,
              bottom: bottom,
              child: IgnorePointer(
                child: Center(
                  child: Material(
                    color: scheme.inverseSurface,
                    borderRadius: BorderRadius.circular(8),
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      child: Text(text,
                          style: TextStyle(color: scheme.onInverseSurface)),
                    ),
                  ),
                ),
              ),
            ));
    overlay.insert(voiceHintEntry!);
    voiceHintTimer = Timer(const Duration(seconds: 4), hideVoiceHint);
  }

  void hideVoiceHint() {
    voiceHintTimer?.cancel();
    voiceHintTimer = null;
    voiceHintEntry?.remove();
    voiceHintEntry = null;
  }

  Future<void> startVoiceRecording({required bool hold}) async {
    if (voiceRecording || voiceStarting || voiceSending) return;
    voiceStarting = true;
    voiceReleasedWhileStarting = false;
    voiceRecorder ??= createVoiceRecorder();
    final ok = await voiceRecorder!.start();
    voiceStarting = false;
    if (!mounted) return;
    if (!ok) {
      showVoiceHint(voiceMessageHintNoMicrophone);
      return;
    }
    setState(() {
      voiceRecording = true;
      voiceHoldMode = hold;
      voiceDragDx = 0;
      voiceLevels = const [];
    });
    voiceLevelSub = voiceRecorder!.levels.listen((level) {
      if (!mounted) return;
      setState(() {
        final next = List<double>.of(voiceLevels)..add(level);
        voiceLevels =
            next.length > 120 ? next.sublist(next.length - 120) : next;
      });
    });
    voiceTicker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() {});
    });
    // Released the button before the recorder had started: treat as a tap
    // that was too short.
    if (hold && voiceReleasedWhileStarting) {
      await finishVoiceRecording();
    }
  }

  void stopVoiceUi() {
    voiceTicker?.cancel();
    voiceTicker = null;
    voiceLevelSub?.cancel();
    voiceLevelSub = null;
    if (mounted) {
      setState(() {
        voiceRecording = false;
        voiceDragDx = 0;
      });
    }
  }

  Future<void> cancelVoiceRecording() async {
    if (!voiceRecording) return;
    stopVoiceUi();
    await voiceRecorder?.cancel();
  }

  Future<void> finishVoiceRecording() async {
    if (!voiceRecording) return;
    final wasHold = voiceHoldMode;
    stopVoiceUi();
    final recording = await voiceRecorder?.stop();
    if (!mounted) return;
    if (recording == null) {
      showVoiceHint(voiceMessageHintNothingRecorded);
      return;
    }
    if (recording.duration < voiceMinDuration) {
      if (wasHold) showVoiceHint(voiceMessageHintHoldToRecord);
      return;
    }
    setState(() => voiceSending = true);
    final ok = await widget.onSendVoiceMessage!(recording,
        overrideClient: senderOverride);
    if (!mounted) return;
    setState(() => voiceSending = false);
    if (!ok) showVoiceHint(voiceMessageHintSendFailed);
  }

  Widget voiceMessageButton() {
    final scheme = Theme.of(context).colorScheme;
    final handsFree = voiceRecording && !voiceHoldMode;
    final active = voiceRecording;
    // Vommet composer round 5: inside the box, on the right. Tap starts
    // hands-free recording, hold records while held. (Tap is meant to
    // switch voice/video once video messages exist.)
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 4, 0),
      child: GestureDetector(
        onLongPressStart: (voiceRecording || voiceSending)
            ? null
            : (_) => startVoiceRecording(hold: true),
        onLongPressMoveUpdate: (details) {
          if (!voiceRecording || !voiceHoldMode) return;
          final dx = details.offsetFromOrigin.dx;
          if (dx < -voiceCancelDistance) {
            cancelVoiceRecording();
          } else {
            setState(() => voiceDragDx = dx);
          }
        },
        onLongPressEnd: (_) {
          if (voiceStarting) {
            voiceReleasedWhileStarting = true;
          } else if (voiceRecording && voiceHoldMode) {
            finishVoiceRecording();
          }
        },
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: voiceSending
              ? const Padding(
                  padding: EdgeInsets.all(8),
                  child: CircularProgressIndicator(strokeWidth: 2))
              : tiamat.CircleButton(
                  icon: handsFree ? Icons.send : Icons.mic,
                  radius: widget.size * widget.iconScale,
                  color: active ? scheme.primary : null,
                  iconColor: active ? scheme.onPrimary : scheme.secondary,
                  onPressed: () {
                    if (!voiceRecording) {
                      startVoiceRecording(hold: false);
                    } else if (!voiceHoldMode) {
                      finishVoiceRecording();
                    }
                  },
                ),
        ),
      ),
    );
  }

  // Vommet: scheduled send (MSC4140 delayed events), under "Schedule…" in
  // the composer's + (every layout style). Grayed out, with an explanation,
  // when the homeserver can't hold messages; there is no local queue.
  bool get scheduleGrayed =>
      widget.room == null ||
      ScheduledMessages.supportedCached(widget.room!.client) != true;

  /// Only a new text message: not an edit, files, a forward or a command.
  bool get canScheduleWhatIsTyped =>
      !_editing &&
      senderOverride == null &&
      widget.attachments?.isNotEmpty != true &&
      !widget.hasPendingForward &&
      controller.text.trim().isNotEmpty &&
      widget.room?.client
              .getComponent<CommandComponent>()
              ?.isExecutable(controller.text) !=
          true;

  Future<void> scheduleMessage() async {
    final room = widget.room;
    if (room == null) return;
    var supported = ScheduledMessages.supportedCached(room.client);
    if (supported != true) {
      supported = await ScheduledMessages.supported(room.client);
    }
    if (!mounted) return;
    if (supported != true) {
      await SchedulePicker.explainUnsupported(context);
      return;
    }
    if (!canScheduleWhatIsTyped) {
      await SchedulePicker.explainNotHere(context);
      return;
    }
    final text = controller.text;
    final sendAt = await SchedulePicker.show(context);
    if (sendAt == null || !mounted) return;

    final request = ScheduleRequest(sendAt);
    ScheduledMessages.runScheduled(request, sendMessage);
    try {
      await request.done.future.timeout(const Duration(seconds: 60));
      if (mounted) {
        showVoiceHint(ScheduleStrings.scheduledFor(
            SchedulePicker.whenLabel(context, sendAt)));
      }
    } on TimeoutException {
      // Still waiting for the user (a confirmation) or never sent.
    } catch (error) {
      if (!mounted) return;
      // The chat emptied the box; give the text back.
      if (controller.text.isEmpty) {
        controller.text = text;
        controller.selection = TextSelection.collapsed(offset: text.length);
      }
      await SchedulePicker.showError(context, error);
    }
  }

  /// Vommet composer round 5: Send, in the box where record sits while it's
  /// empty. No menu: polls, effects and scheduling live in +. A picked
  /// effect shows as a small badge on it.
  Widget sendMessageButton() {
    bool canSend = controller.text.isNotEmpty ||
        widget.attachments?.isNotEmpty == true ||
        widget.hasPendingForward;
    final effect = activeEffect;
    final scheme = Theme.of(context).colorScheme;

    double targetValue = canSend ? 1 : 0;
    return Padding(
        padding: const EdgeInsets.fromLTRB(2, 0, 4, 0),
        child: TweenAnimationBuilder(
          tween: Tween<double>(begin: 0, end: targetValue),
          duration: Durations.medium1,
          builder: (context, value, child) {
            return GestureDetector(
              // Vommet: long-press send shows what will be sent when
              // paragraphs get translated.
              onLongPress: canSend && willTranslate ? showWillSend : null,
              child: SizedBox(
                width: widget.size,
                height: widget.size,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: tiamat.CircleButton(
                        icon: Icons.send,
                        radius: widget.size * widget.iconScale,
                        onPressed: canSend ? sendMessage : null,
                        color: Color.lerp(
                            scheme.primary.withAlpha(0), scheme.primary, value),
                        iconColor: Color.lerp(
                            scheme.secondary, scheme.onPrimary, value),
                      ),
                    ),
                    if (effect != null)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: IgnorePointer(
                          child: Container(
                            key: const ValueKey("composer-send-effect-badge"),
                            padding: const EdgeInsets.all(1),
                            decoration: BoxDecoration(
                                color: scheme.surfaceContainerHighest,
                                shape: BoxShape.circle),
                            child: Text(effect.emoji,
                                style: const TextStyle(fontSize: 10)),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ));
  }

  /// Whether sending translates some paragraphs.
  bool get willTranslate =>
      composerTranslation?.translatedRuns.isNotEmpty == true &&
      senderOverride == null;

  /// Long-press send: "Will send" with each block in its language; Send
  /// sends exactly that.
  Future<void> showWillSend() async {
    final t = composerTranslation;
    if (t == null) return;
    final blocks = await t.previewSend(context, controller.text);
    if (blocks == null || !mounted) return;
    final send = await showWillSendSheet(context, blocks);
    if (send == true && mounted) sendMessage();
  }

  /// The text field and its own buttons (文A, emoji).
  ///
  /// Vommet: the text wraps before the buttons, as upstream. Phones used to
  /// drop the buttons under a wrapping draft, back when the box also held Aa
  /// and an always-on translate chip; with only emoji left that cost a row.
  Widget fieldWithButtons(BuildContext context) {
    final showChip = widget.enabled &&
        composerTranslation?.showChip(controller.text) == true;
    return Row(
      crossAxisAlignment:
          tallBox ? CrossAxisAlignment.end : CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        textInput(context),
        if (showChip) translateChip(),
        // Vommet composer round 5: faint reminders of what + has on.
        if (!showChip && widget.enabled && controller.text.isEmpty)
          if (ringStates case final states when states.isNotEmpty)
            ComposerStatePills(
                states: states,
                language: plusTranslation?.language,
                writingLanguage: plusTranslation?.writingLanguage,
                compact: MediaQuery.of(context).mobile,
                colors: ringColors(states),
                onTap: () => openPlusMenu(atRoom: true)),
        if (widget.enabled) toggleEmojiButton(),
      ],
    );
  }

  Widget toggleEmojiButton() {
    var button = SizedBox(
        width: widget.size,
        height: widget.size,
        child: RandomEmojiButton(
            size: widget.size,
            onTap: toggleEmojiOverlay,
            toggled: MediaQuery.of(context).mobile
                ? (emojiTooltipController.value == TooltipStatus.isShowing ||
                    (emotePickerActive == true))
                : false));

    if (MediaQuery.of(context).mobile) return button;

    return Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, 2, 0),
        child: JustTheTooltip(
          isModal: true,
          preferredDirection: AxisDirection.up,
          controller: emojiTooltipController,
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
          onDismiss: () {
            if (MediaQuery.of(context).desktop) {
              textFocus.requestFocus();
            }
          },
          content: ClipRRect(
            borderRadius: BorderRadiusGeometry.circular(8),
            child: Material(
              child: Container(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                child: SizedBox(
                  height: 500,
                  width: 500,
                  child: buildEmojiPicker(skipIfNeverOpened: false),
                ),
              ),
            ),
          ),
          child: button,
        ));
  }

  Expanded textInput(BuildContext context) {
    var height = Theme.of(context).textTheme.bodyMedium!.fontSize!;
    var padding = widget.size - height;
    var hintStyle = TextTheme.of(context).bodyMedium;
    hintStyle = hintStyle?.copyWith(color: hintStyle.color?.withAlpha(120));
    final runs = composerTranslation?.translatedRuns ?? const [];
    final scheme = Theme.of(context).colorScheme;
    final rich = controller is RichTextEditingController
        ? controller as RichTextEditingController
        : null;
    if (rich != null) {
      final ranges = paragraphRanges(controller.text);
      rich.paragraphTint = paragraphTintColor(scheme);
      rich.paragraphTintRanges = [
        for (final r in runs)
          if (r.last < ranges.length)
            TextRange(start: ranges[r.first].start, end: ranges[r.last].end)
      ];
    }
    return Expanded(
      child: Stack(
        children: [
          TapRegion(
            onTapInside: (event) => onTextFocusChanged(),
            child: TouchSelectionNormalizer(
              controller: controller,
              child: PrimarySelectionField(
                controller: controller,
                enabled: widget.enabled && !widget.isProcessing,
                onChanged: onTextfieldUpdated,
                child: TextField(
                  focusNode: textFocus,
                  onChanged: onTextfieldUpdated,
                  controller: controller,
                  scrollController: textScroll,
                  readOnly: !widget.enabled || widget.isProcessing,
                  textAlignVertical: expandedLayout
                      ? TextAlignVertical.top
                      : TextAlignVertical.center,
                  style: Theme.of(context).textTheme.bodyMedium!,
                  maxLines: null,
                  // Round 6: the expanded box scrolls its text inside.
                  expands: expandedLayout,
                  contextMenuBuilder: contextMenuBuilder,
                  // Vommet: images from the keyboard (Gboard's clipboard strip,
                  // keyboard GIFs and stickers) open the attachment preview.
                  contentInsertionConfiguration: ContentInsertionConfiguration(
                    allowedMimeTypes: keyboardImageMimeTypes,
                    onContentInserted: onKeyboardContentInserted,
                  ),
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                      contentPadding: EdgeInsets.fromLTRB(8, padding / 2,
                          4 + paragraphTagsReserve, padding / 2),
                      border: InputBorder.none,
                      isDense: true,
                      hintStyle: hintStyle,
                      hintText:
                          widget.hintIcon == null ? widget.hintText : null,
                      hint: widget.hintIcon == null || widget.hintText == null
                          ? null
                          : Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(widget.hintIcon,
                                  size: (hintStyle?.fontSize ?? 14) + 2,
                                  color: hintStyle?.color),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(widget.hintText!,
                                    style: hintStyle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              ),
                            ])),
                ),
              ),
            ),
          ),
          if (runs.isNotEmpty)
            Positioned.fill(
              child: ComposerParagraphMarks(
                text: controller.text,
                runs: runs,
                editable: () => textFocus.context
                    ?.findAncestorStateOfType<EditableTextState>(),
                scrollController: textScroll,
                onTapTag: openParagraphMenu,
              ),
            ),
        ],
      ),
    );
  }

  /// Vommet composer round 6: set each build, from [widget.expanded] and
  /// whether the box has a height to fill.
  bool expandedLayout = false;

  /// The draft takes [composerExpandMinLines] or more lines on screen.
  bool draftIsLong = false;

  /// Phones, in a chat that lays out around the expanded box.
  bool get expandable =>
      widget.expanded != null && MediaQuery.of(context).mobile;

  bool get showExpandButton =>
      expandable && !voiceRecording && (expandedLayout || draftIsLong);

  /// + and Send sit at the bottom, and ⤢ above Send.
  bool get tallBox => showExpandButton;

  void setExpanded(bool value) {
    final expanded = widget.expanded;
    if (expanded == null || expanded.value == value) return;
    expanded.value = value;
  }

  void onExpandedChanged() {
    if (!mounted) return;
    setState(() {});
    // Back to the box's own size: count its lines again.
    measureDraftSoon();
  }

  bool _measureScheduled = false;

  /// Counts the draft's lines on screen after the next layout.
  void measureDraftSoon() {
    if (_measureScheduled || widget.expanded == null) return;
    _measureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      if (!mounted || expandedLayout) return;
      final editable = textFocus.context
          ?.findAncestorStateOfType<EditableTextState>()
          ?.renderEditable;
      if (editable == null || !editable.hasSize) return;
      final long = composerLineCount(
              editable.size.height, editable.preferredLineHeight) >=
          composerExpandMinLines;
      if (long != draftIsLong) setState(() => draftIsLong = long);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// Vommet: the message box's scroll, so the paragraph marks follow it.
  final ScrollController textScroll = ScrollController();

  /// Room at the right of the text for the "→ Spanish" tags.
  double get paragraphTagsReserve {
    final runs = composerTranslation?.translatedRuns ?? const [];
    if (runs.isEmpty) return 0;
    return paragraphTagsWidth(context, runs.map((r) => r.to));
  }

  /// Vommet composer round 5: anchors the desktop + menu.
  final GlobalKey plusKey = GlobalKey();

  Widget addAttachmentButton() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      key: plusKey,
      padding: const EdgeInsets.fromLTRB(4, 0, 2, 0),
      child: ComposerPlusButton(
        size: widget.size,
        ring: composerRing(
            ringStates, scheme.primary, scheme.surfaceContainerLow),
        onPressed: openPlusMenu,
      ),
    );
  }

  /// What the ring on + (and the empty box's pills) show as on.
  List<ComposerRingState> get ringStates {
    final t = composerTranslation;
    if (t == null || widget.room == null) return const [];
    return [
      if (t.roomMode) ComposerRingState.reading,
      if (t.writeMode) ComposerRingState.writing,
    ];
  }

  /// The ring's color for each of [states], for the phone's pill icons.
  List<Color> ringColors(List<ComposerRingState> states) {
    final scheme = Theme.of(context).colorScheme;
    return [
      for (final s in states)
        ringColor(s.homeHue, scheme.primary, scheme.surfaceContainerLow)
    ];
  }

  /// The + sheet's translation rows for this room; null where translation
  /// can't run or is turned off (Vommet issue 820).
  ComposerPlusRoomTranslation? get plusTranslation {
    final room = widget.room;
    final composer = composerTranslation;
    if (room == null || composer == null || !composer.rooms.supported) {
      return null;
    }
    return _PlusRoomTranslation(room.identifier, composer);
  }

  double get emotePickerHeight =>
      (MediaQuery.of(context).size.height / (BuildConfig.MOBILE ? 2.5 : 3)) /
      preferences.appScale.value;

  Widget buildEmojiPicker({bool skipIfNeverOpened = true}) {
    var recent = widget.client
        .getComponent<RecentEmoticonComponent>()
        ?.getRecentTypedEmoticon(widget.room);

    var availableEmoji = widget.availibleEmoticons!.toList();

    if (recent != null && recent.isNotEmpty) {
      availableEmoji.insert(
          0,
          DynamicEmoticonPack(
              identifier: "dynamic_pack_frequently_used_typing",
              displayName: "Frequently Used",
              icon: Icons.schedule,
              emoticons: recent,
              usage: EmoticonUsage.all));
    }

    final shelf = widget.client.getComponent<StickerShelfComponent>();

    return (!hasEmotePickerOpened && skipIfNeverOpened)
        ? Container()
        // Vommet issue 890: rebuild when Favorites or Recent change.
        : StreamBuilder<void>(
            stream: shelf?.onChanged,
            builder: (context, _) => EmoticonPicker(
                emoji: availableEmoji,
                emojiSearchFocus: emojiSearchFocus,
                stickerSearchFocus: stickerSearchFocus,
                gifSearchFocus: gifSearchFocus,
                searchDelegate: (search) => AutofillUtils.searchEmoticon(search,
                        client: widget.client, room: widget.room, limit: 50)
                    .whereType<AutofillSearchResultEmoticon>()
                    .toList(),
                stickers: stickerPacks(shelf),
                stickerMenuActions: shelf == null
                    ? null
                    : (sticker) => stickerMenu(shelf, sticker),
                onEmojiPressed: insertEmoticon,
                packListAxis:
                    BuildConfig.DESKTOP ? Axis.vertical : Axis.horizontal,
                onImportPressed: () {
                  // The desktop picker is a modal tooltip; close it first or its
                  // barrier stays above the pushed page and eats every click
                  // (Vommet issue 876).
                  emojiTooltipController.hideTooltip();
                  final account =
                      widget.client.getComponent<EmoticonComponent>();
                  if (account == null) return;
                  EmoticonImportDestinations.show(context, account,
                      room: widget.room);
                },
                // Vommet issue 731. Vommet issue 876: on a computer the picker
                // closes first, so it isn't still open on return.
                onManagePressed: () {
                  if (emojiTooltipController.value == TooltipStatus.isShowing) {
                    emojiTooltipController.hideTooltip(immediately: true);
                  }
                  LibraryPage.open(context, widget.client);
                },
                manageTooltip: LibraryPage.promptManage,
                allowGifSearch: widget.showGifSearch &&
                    preferences.tenorGifSearchEnabled.value,
                showGifs: widget.showGifSearch,
                gifComponent: widget.gifComponent,
                onStickerPressed: (emoticon) {
                  widget.sendSticker?.call(emoticon);
                  setState(() {
                    clearKeyboardOverride(debounce: false);
                  });
                },
                onFavoritePicked: (gif) async {
                  await widget.sendFavoriteGif?.call(gif);
                  setState(() {
                    clearKeyboardOverride(debounce: false);
                  });
                },
                onGifPressed: (gif) async {
                  await widget.sendGif?.call(gif);
                  setState(() {
                    clearKeyboardOverride(debounce: false);
                  });
                }));
  }

  /// Vommet issue 890: Favorites, then Recent, then the packs.
  List<EmoticonPack> stickerPacks(StickerShelfComponent? shelf) {
    final packs = (widget.availibleStickers ?? []).toList();
    if (shelf == null) return packs;
    final favorites = shelf.favorites;
    final recent = shelf.recent;
    return [
      if (favorites.isNotEmpty)
        DynamicEmoticonPack(
            identifier: "dynamic_pack_favorite_stickers",
            displayName: EmoticonPicker.labelStickerFavorites,
            icon: Icons.star_rounded,
            emoticons: favorites,
            usage: EmoticonUsage.sticker),
      if (recent.isNotEmpty)
        DynamicEmoticonPack(
            identifier: "dynamic_pack_recent_stickers",
            displayName: EmoticonPicker.labelStickerRecent,
            icon: Icons.schedule,
            emoticons: recent,
            usage: EmoticonUsage.sticker),
      ...packs,
    ];
  }

  /// Vommet issue 890: a sticker's menu items after Send.
  List<EmoticonMenuAction> stickerMenu(
      StickerShelfComponent shelf, Emoticon sticker) {
    final favorite = shelf.isFavorite(sticker);
    final full = shelf.favorites.length >= StickerShelfComponent.maxFavorites;
    return [
      EmoticonMenuAction(
          favorite
              ? EmoticonPicker.promptRemoveStickerFavorite
              : full
                  ? EmoticonPicker.promptAddStickerFavoriteReplacing
                  : EmoticonPicker.promptAddStickerFavorite,
          favorite ? Icons.star_outline_rounded : Icons.star_rounded,
          () => shelf.setFavorite(sticker, !favorite)),
      if (shelf.isRecent(sticker))
        EmoticonMenuAction(EmoticonPicker.promptRemoveStickerRecent,
            Icons.close, () => shelf.removeRecent(sticker)),
    ];
  }

  /// Vommet: what the keyboard may insert (Android's Commit Content API).
  /// Images only; everything goes through the attachment preview.
  static const keyboardImageMimeTypes = [
    "image/png",
    "image/jpeg",
    "image/webp",
    "image/gif",
  ];

  Future<void> onKeyboardContentInserted(
      KeyboardInsertedContent content) async {
    final data = content.data;
    if (data == null || data.isEmpty) return;
    if (!keyboardImageMimeTypes.contains(content.mimeType)) return;

    final attachment = PendingFileAttachment(
        name: "image.${content.mimeType.split("/").last}",
        mimeType: content.mimeType,
        size: data.lengthInBytes,
        data: data);
    if (useMediaSendSheet) {
      await openMediaSendSheet(await checkedAttachments([attachment]));
      return;
    }
    await handlePickedAttachment(attachment);
  }

  /// Vommet issue 838: on a phone, photos and videos from the library, the
  /// camera and the keyboard open one send screen (MediaSendSheet) instead
  /// of a dialog per file. Desktop, drag and drop, and paste keep the
  /// dialog; so does editing a message (it can't take files).
  bool get useMediaSendSheet =>
      !PlatformUtils.isWeb &&
      (PlatformUtils.isAndroid || PlatformUtils.isIOS) &&
      !_editing &&
      widget.addAttachment != null;

  /// [files] that pass the room's size check (which says why one doesn't).
  Future<List<PendingFileAttachment>> checkedAttachments(
      List<PendingFileAttachment> files) async {
    final checked = <PendingFileAttachment>[];
    for (final file in files) {
      if (await widget.checkAttachment?.call(file) == false) continue;
      checked.add(file);
    }
    return checked;
  }

  /// Shows [files] on the send screen; Send adds them and sends them with
  /// the caption right away (processing and upload show in the timeline).
  /// Closing it keeps the caption in the composer.
  Future<void> openMediaSendSheet(List<PendingFileAttachment> files) async {
    if (files.isEmpty || !mounted) return;
    final result = await MediaSendSheet.show(context,
        files: files,
        caption: controller.text,
        pickMore: () async => checkedAttachments(await Future.wait(
            (await ImagePicker().pickMultipleMedia())
                .map(attachmentFromXFile))));
    if (result == null || !mounted) return;
    controller.value = TextEditingValue(
        text: result.caption,
        selection: TextSelection.collapsed(offset: result.caption.length));
    if (!result.send) return;

    for (final file in result.files) {
      await widget.addAttachment?.call(file);
    }
    if (!mounted) return;
    // The files reach widget.attachments with the next build.
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) sendMessage();
  }

  Future<void> handlePickedAttachment(PendingFileAttachment attachment) async {
    if (await widget.checkAttachment?.call(attachment) == false) return;

    if (mounted) {
      var processedFile = await AdaptiveDialog.show<PendingFileAttachment>(
        scrollable: false,
        context,
        builder: (context) {
          return AttachmentProcessor(
            attachment: attachment,
          );
        },
      );

      if (processedFile != null) {
        widget.addAttachment?.call(processedFile);
      }
    }
  }

  /// Vommet composer round 5: + opens one sheet (phones) or menu
  /// (desktop): SEND, IN THIS ROOM, THIS MESSAGE. [atRoom]: opened from a
  /// pill, at IN THIS ROOM.
  Future<void> openPlusMenu({bool atRoom = false}) async {
    final room = widget.room;
    final phoneOs = !PlatformUtils.isWeb &&
        (PlatformUtils.isAndroid || PlatformUtils.isIOS);
    final pollComponent = room?.client.getComponent<PollComponent>();
    final send = [
      ComposerPlusAction(
          icon: Icons.photo_library_outlined,
          label: "Photo or video",
          onTap: phoneOs
              ? pickFromPhotoLibrary
              : () => pickFiles(type: FileType.media)),
      if (phoneOs)
        ComposerPlusAction(
            icon: Icons.photo_camera_outlined,
            label: "Camera",
            onTap: PlatformUtils.isIOS
                ? chooseCameraCapture
                : () => captureFromCamera(video: false)),
      ComposerPlusAction(
          icon: Icons.attach_file, label: "File", onTap: pickFiles),
      if (pollComponent != null && room != null)
        ComposerPlusAction(
            icon: Icons.poll_outlined,
            label: "Poll",
            onTap: () async {
              final createArgs = await AdaptiveDialog.show<PollCreateArgs>(
                  context,
                  title: "Create Poll",
                  builder: (context) => PollCreator());
              if (createArgs != null) {
                await pollComponent.createPoll(room, createArgs);
              }
            }),
    ];
    final canSchedule = widget.canSchedule && room != null;
    final translation = plusTranslation;
    final effects = availableEffects;

    await showComposerPlusMenu(context,
        anchor: plusKey.currentContext,
        builder: (context, phone) => ComposerPlusMenu(
              send: send,
              translation: translation,
              showFormattingToolbar: phone,
              onSchedule: canSchedule ? scheduleMessage : null,
              scheduleGrayed: scheduleGrayed || !canScheduleWhatIsTyped,
              effects: effects,
              effect: activeEffect,
              onEffect: pickEffect,
              phone: phone,
              startAtRoom: atRoom,
            ));
    if (mounted) setState(() {});
  }

  /// Picks files of [type] and adds each as an attachment.
  Future<void> pickFiles({FileType type = FileType.any}) async {
    // Vommet issue 410: read files after the size check, not all of
    // them up front (a 1 GB video could take the app down first).
    // Web has no paths, so it still gets the bytes from the picker.
    FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: type, withData: PlatformUtils.isWeb, allowMultiple: true);
    if (result == null) return;

    for (var file in result.files) {
      final path = PlatformUtils.isWeb ? null : file.path;
      if (path == null && file.bytes == null) continue;

      var attachment = PendingFileAttachment(
          name: file.name, path: path, data: file.bytes, size: file.size);

      if (await widget.checkAttachment?.call(attachment) == false) {
        continue;
      }
      // Like dropped files: big ones stay on disk until they're sent.
      if (attachment.data == null && file.size < 50000000) {
        final mimeType = attachment.mimeType;
        await attachment.resolve();
        attachment.mimeType ??= mimeType;
      }

      await handlePickedAttachment(attachment);
    }
  }

  Future<void> pickFromPhotoLibrary() async {
    final files = await ImagePicker().pickMultipleMedia();
    if (useMediaSendSheet) {
      await openMediaSendSheet(await checkedAttachments(
          await Future.wait(files.map(attachmentFromXFile))));
      return;
    }
    for (final file in files) {
      await handlePickedXFile(file);
    }
  }

  static const String labelTakePhoto = "Take photo";
  static const String labelRecordVideo = "Record video";

  /// iOS: Camera takes a photo or records a video (as the Vommet issue 615
  /// sheet did).
  Future<void> chooseCameraCapture() async {
    final video = await AdaptiveDialog.pickOne<bool>(context,
        title: "Camera",
        items: const [false, true],
        scrollable: false,
        itemBuilder: (context, video, onTapped) => SizedBox(
              key:
                  ValueKey(video ? "camera-record-video" : "camera-take-photo"),
              height: 44,
              child: tiamat.TextButton(
                  video ? labelRecordVideo : labelTakePhoto,
                  icon: video ? Icons.videocam_outlined : Icons.photo_camera,
                  onTap: onTapped),
            ));
    if (video == null || !mounted) return;
    await captureFromCamera(video: video);
  }

  Future<void> captureFromCamera({required bool video}) async {
    final picker = ImagePicker();
    final file = video
        ? await picker.pickVideo(source: ImageSource.camera)
        : await picker.pickImage(source: ImageSource.camera);
    if (file == null) return;

    if (useMediaSendSheet) {
      await openMediaSendSheet(
          await checkedAttachments([await attachmentFromXFile(file)]));
      return;
    }
    await handlePickedXFile(file);
  }

  Future<PendingFileAttachment> attachmentFromXFile(XFile file) async {
    // Like dropped files: big ones (long videos) stay on disk until sent.
    final size = await file.length();
    final data = size < 50000000 ? await file.readAsBytes() : null;

    return PendingFileAttachment(
        name: file.name,
        path: file.path,
        mimeType: file.mimeType,
        size: size,
        data: data);
  }

  Future<void> handlePickedXFile(XFile file) async {
    await handlePickedAttachment(await attachmentFromXFile(file));
  }

  void doCancelInteraction() {
    if (widget.interactionType == EventInteractionType.edit) {
      controller.clear();
    }

    widget.cancelReply?.call();
  }

  void insertEmoticon(Emoticon emote) {
    if (widget.room != null) {
      var recents = widget.client.getComponent<RecentEmoticonComponent>();
      recents?.typedEmoticon(widget.room!, emote);
    }

    var text = controller.text;
    var selection = controller.selection;
    int start = selection.start;
    int end = selection.end;
    String slug = emote.slug;

    // Vommet issue 483: no forced spaces around custom emoji, so they can sit
    // inside a word; typed shortcodes are replaced there on send as well.
    if (start == -1 && end == -1) {
      controller.text = text + slug;
      return;
    }

    controller.text = text.replaceRange(start, end, slug);
    var newOffset = start + slug.length;
    controller.selection =
        TextSelection(baseOffset: newOffset, extentOffset: newOffset);
  }

  Widget translateChip() {
    final t = composerTranslation!;
    final caret = controller.selection.isValid
        ? controller.selection.extentOffset
        : controller.text.length;
    final line = paragraphAt(controller.text, caret);
    final here = line < t.resolved.length ? t.resolved[line] : null;
    return ComposerTranslateChip(
      language: here ?? t.target,
      busy: t.busy,
      active: here != null,
      onTap: onTranslateChipTap,
      onPickLanguage: openParagraphMenu,
    );
  }

  List<Widget> translationLines() {
    final t = composerTranslation;
    if (t == null) return const [];
    final suggested = widget.enabled ? t.suggestedLanguage : null;
    return [
      if (suggested != null)
        ComposerTranslationSuggestion(
          language: suggested,
          onTranslate: t.acceptSuggestion,
          onDismiss: t.dismissSuggestion,
        ),
      if (t.error != null) ComposerTranslationError(t.error!),
      if (t.translated case (:final original, :final to, targets: _))
        ComposerTranslatedLine(
          to: to,
          original: original,
          onHide: t.hideLine,
          onUndo: undoTranslation,
        ),
    ];
  }

  Widget interactionText() {
    // Vommet: with the quote and card reply styles the strip matches them.
    if (widget.interactionType == EventInteractionType.reply &&
        ReplyStyle.current.inline) {
      return replyStrip();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 0, 4),
      child: SizedBox(
        height: 24,
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: tiamat.IconButton(
                icon: Icons.cancel_outlined,
                size: 16,
                onPressed: doCancelInteraction,
              ),
            ),
            Icon(widget.interactionType == EventInteractionType.reply
                ? Icons.keyboard_arrow_right_rounded
                : widget.interactionType == EventInteractionType.edit
                    ? Icons.edit
                    : null),
            tiamat.Text.name(
              widget.relatedEventSenderName!,
              color: widget.relatedEventSenderColor,
            ),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
                child: _ComposerQuoteText(
                  roomId: widget.room?.identifier,
                  eventId: widget.interactionType == EventInteractionType.reply
                      ? widget.relatedEventTranslationId
                      : null,
                  text: widget.relatedEventBody ?? "Unknown",
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  /// Vommet: "Reply to <name>" over the quoted text, with a bar in their
  /// colour and an X to stop replying.
  Widget replyStrip() {
    final scheme = Theme.of(context).colorScheme;
    final color = tiamat.Text.adjustColor(
        context, widget.relatedEventSenderColor ?? scheme.primary);
    return Padding(
      key: const ValueKey("composer-reply-strip"),
      padding: const EdgeInsets.fromLTRB(8, 0, 4, 6),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(Icons.reply, size: 20, color: scheme.primary),
            ),
            Container(
              width: 3,
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 8),
            if (widget.relatedEventThumbnail case final thumbnail?)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Center(child: thumbnail),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  tiamat.Text.name(
                    replyStripTitle(widget.relatedEventSenderName ?? ""),
                    color: widget.relatedEventSenderColor,
                  ),
                  _ComposerQuoteText(
                    roomId: widget.room?.identifier,
                    eventId: widget.relatedEventTranslationId,
                    text: widget.relatedEventBody ?? "",
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
            Center(
              child: SizedBox(
                width: 32,
                height: 32,
                child: tiamat.IconButton(
                  icon: Icons.close,
                  size: 18,
                  onPressed: doCancelInteraction,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String replyStripTitle(String name) => Intl.message("Reply to $name",
      name: "replyStripTitle",
      args: [name],
      desc:
          "Above the message box while writing a reply: who you are replying to");

  Widget displayAttachments() {
    // Vommet issue 838: bigger tiles and badges on phones, scrolling when
    // there are more than fit.
    final phone = !PlatformUtils.isWeb &&
        (PlatformUtils.isAndroid || PlatformUtils.isIOS);
    final tile = phone ? 56.0 : 40.0;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: widget.attachments!.map((e) {
          return Padding(
            padding: const EdgeInsets.all(2.0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: GestureDetector(
                onTap: () {},
                child: SizedBox(
                  height: tile,
                  width: tile,
                  child: AttachmentIcon(
                    e,
                    badgeSize: phone ? 26 : 18,
                    removeAttachment: () => widget.removeAttachment?.call(e),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget contextMenuBuilder(
      BuildContext buildContext, EditableTextState editableTextState) {
    var formatMenu = formatting.mobileContextMenu(editableTextState);
    if (formatMenu != null) return formatMenu;

    final toolbar = AdaptiveTextSelectionToolbar.editable(
      anchors: editableTextState.contextMenuAnchors,
      clipboardStatus: ClipboardStatus.pasteable,
      // to apply the normal behavior when click on copy (copy in clipboard close toolbar)
      // use an empty function `() {}` to hide this option from the toolbar
      onCopy: () =>
          editableTextState.copySelection(SelectionChangedCause.toolbar),
      // to apply the normal behavior when click on cut
      onCut: () =>
          editableTextState.cutSelection(SelectionChangedCause.toolbar),
      onPaste: () async {
        if (await attachFilesFromClipboard()) {
          editableTextState.hideToolbar();
          return;
        }

        var clipboard = await Clipboard.getData("text/plain");

        if (clipboard != null) {
          return editableTextState.pasteText(SelectionChangedCause.toolbar);
        }

        editableTextState.hideToolbar();

        // Vommet: Android too ("Copy image", or an image copied in
        // another app).
        if (BuildConfig.DESKTOP || PlatformUtils.isAndroid) {
          await readImageFromClipboard();
        }
      },
      // to apply the normal behavior when click on select all
      onSelectAll: () =>
          editableTextState.selectAll(SelectionChangedCause.toolbar),
      onLiveTextInput: null, onLookUp: null, onSearchWeb: null,
      onShare: null,
    );

    // Vommet: spellcheck suggestions above the edit actions.
    return SpellcheckContextMenu.wrap(
        editableTextState, controller as RichTextEditingController, toolbar);
  }

  /// Ctrl+V: copied files become attachments; anything else pastes as
  /// before (text into the field, an image as an attachment).
  Future<void> pasteFromKeyboard() async {
    if (await attachFilesFromClipboard()) return;

    final focus = textFocus.context;
    if (focus != null && focus.mounted) {
      Actions.maybeInvoke(
          focus, const PasteTextIntent(SelectionChangedCause.keyboard));
    }
    await readImageFromClipboard();
  }

  /// Attaches files copied in a file manager. False when there were none.
  Future<bool> attachFilesFromClipboard() async {
    final paths = await ClipboardFiles.read();
    if (paths.isEmpty) return false;

    final loaded = await FileTransfer.loadPaths(paths);
    for (final attachment in loaded.files) {
      await handlePickedAttachment(attachment);
    }
    if (mounted) FileTransfer.showUnreadable(context, loaded.unreadable);
    return true;
  }

  /// Vommet: set on the web, where pasting is a DOM event (see [WebPaste]).
  void Function()? stopWebPaste;

  Future<void> readImageFromClipboard() async {
    // The web gets pasted pictures from the paste event instead.
    if (kIsWeb) return;

    var image = await ImageClipboard.read();
    if (image == null) {
      return;
    }

    await attachPastedImage(image);
  }

  Future<void> attachPastedImage(Uint8List image) async {
    var processedAttachment =
        await AdaptiveDialog.show<PendingFileAttachment>(context,
            scrollable: false,
            builder: (context) => AttachmentProcessor(
                  attachment:
                      PendingFileAttachment(data: image, size: image.length),
                ));

    if (processedAttachment != null) {
      setState(() {
        widget.addAttachment?.call(processedAttachment);
      });
    }
  }

  void onPopped(ScopePopped event) {
    if (event.handled) {
      return;
    }

    if (event.currentMobileSide == RevealSide.left) {
      return;
    }

    if (showEmotePicker) {
      clearKeyboardOverride(debounce: false);
      event.handled = true;
    }
  }
}

/// The + sheet's view of this room's translation settings.
class _PlusRoomTranslation implements ComposerPlusRoomTranslation {
  _PlusRoomTranslation(this.roomId, this.composer);

  final String roomId;
  final ComposerTranslation composer;

  RoomTranslation get rooms => composer.rooms;

  @override
  void addListener(VoidCallback listener) => rooms.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => rooms.removeListener(listener);

  @override
  bool get readingOn => rooms.isOn(roomId);

  @override
  bool get writingOn => composer.writeMode;

  @override
  String? get writingLanguage => composer.writingTarget;

  @override
  Future<void> setWritingLanguage(String code) =>
      composer.prefs.setTarget(roomId, code);

  @override
  String? get language => rooms.roomLanguage(roomId,
      () => composer.prefs.targetFor(roomId) ?? composer.detectedTarget);

  @override
  Future<void> setReading(bool on) => rooms.setOn(roomId, on);

  @override
  Future<void> setWriting(bool on) => rooms.setTranslateWriting(roomId, on);

  @override
  Future<void> setLanguage(String code) => rooms.setFrom(roomId, code);

  @override
  Future<List<String>> shortList() async {
    final translation = rooms.translation;
    final target = translation.targetLanguage;
    final reachable = {
      for (final code in translationLanguageNames.keys)
        if (code != target && translation.route(code, target) != null) code
    };
    final downloaded = <String>{};
    for (final spec in (await translation.downloadedModels()).keys) {
      downloaded
        ..add(spec.from)
        ..add(spec.to);
    }
    downloaded.remove(target);
    return composerLanguageShortList(
        current: language,
        recent: composer.prefs.recentLanguages,
        downloaded: downloaded,
        reachable: reachable);
  }

  @override
  Future<String?> pickMore(BuildContext context, {String? title}) {
    final translation = rooms.translation;
    final target = translation.targetLanguage;
    final codes = [
      for (final code in translationLanguageNames.keys)
        if (code != target && translation.route(code, target) != null) code
    ]..sort((a, b) =>
        translationLanguageName(a).compareTo(translationLanguageName(b)));
    return AdaptiveDialog.pickOne<String>(context,
        title: title ?? "Messages here are in",
        items: codes,
        itemBuilder: (context, code, onTapped) => SizedBox(
              height: 44,
              child: tiamat.TextButton(translationLanguageName(code),
                  onTap: onTapped),
            ));
  }
}

/// Vommet: the quoted text above the message box, translated like the
/// timeline's reply quotes when "Translate this room" is on, with the same
/// translated mark.
class _ComposerQuoteText extends StatefulWidget {
  const _ComposerQuoteText(
      {required this.roomId,
      required this.eventId,
      required this.text,
      required this.color});

  final String? roomId;
  final String? eventId;
  final String text;
  final Color color;

  @override
  State<_ComposerQuoteText> createState() => _ComposerQuoteTextState();
}

class _ComposerQuoteTextState extends State<_ComposerQuoteText> {
  final ReplyQuoteTranslation translation = ReplyQuoteTranslation();

  @override
  void initState() {
    super.initState();
    translation.addListener(onTranslationChanged);
    follow();
  }

  @override
  void didUpdateWidget(covariant _ComposerQuoteText oldWidget) {
    super.didUpdateWidget(oldWidget);
    follow();
  }

  void follow() {
    final roomId = widget.roomId, eventId = widget.eventId;
    if (roomId == null || eventId == null) {
      translation.clear();
    } else {
      translation.show(roomId: roomId, eventId: eventId, text: widget.text);
    }
  }

  void onTranslationChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    translation.removeListener(onTranslationChanged);
    translation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final translated = translation.translated;
    final text = tiamat.Text(
      translated ?? widget.text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      color: widget.color,
    );
    if (translated == null) return text;
    return Row(
      key: const ValueKey("composer-reply-translated"),
      children: [
        const Padding(
          padding: EdgeInsets.only(right: 4),
          child: ReplyQuoteTranslatedMark(),
        ),
        Flexible(child: text),
      ],
    );
  }
}
