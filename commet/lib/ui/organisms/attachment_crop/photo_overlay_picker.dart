// Vommet: select, never send, an existing pack item for a photo (issue 1056).
import 'dart:ui' as ui;

import 'package:commet/client/components/emoticon/emoji_pack.dart';
import 'package:commet/client/components/emoticon/emoticon.dart';
import 'package:commet/client/components/emoticon/emoticon_component.dart';
import 'package:commet/client/room.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/ui/molecules/emoji_picker.dart';
import 'package:commet/ui/organisms/attachment_crop/photo_overlay_asset.dart';
import 'package:commet/utils/autofill_utils.dart';
import 'package:commet/utils/emoji/unicode_emoji.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class PhotoOverlayPicker extends StatefulWidget {
  const PhotoOverlayPicker(
      {this.room, this.loadAsset = PhotoOverlayAsset.load, super.key});
  final Future<ui.Image> Function(Emoticon) loadAsset;
  final Room? room;
  static String get add => Intl.message('Add', name: 'photoOverlayAdd');
  static String get stickers =>
      Intl.message('Stickers', name: 'photoOverlayStickers');
  static String get emoji => Intl.message('Emoji', name: 'photoOverlayEmoji');
  static String get empty => Intl.message(
      'No sticker packs available. Choose Emoji or manage packs in the Library.',
      name: 'photoOverlayEmpty');
  @override
  State<PhotoOverlayPicker> createState() => _PhotoOverlayPickerState();
}

class _PhotoOverlayPickerState extends State<PhotoOverlayPicker> {
  bool loading = false;
  String? error;
  Emoticon? last;
  Future<void> load(Emoticon e) async {
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
      last = e;
    });
    try {
      final ui.Image image = await widget.loadAsset(e);
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) {
        image.dispose();
        if (mounted) setState(() => loading = false);
        return;
      }
      Navigator.of(context).pop(image);
    } catch (e) {
      if (mounted)
        setState(() {
          loading = false;
          error = e is FormatException ? e.message : PhotoOverlayAsset.failed;
        });
    }
  }

  late final unicode = UnicodeEmojis.packs == null
      ? UnicodeEmojis.load()
      : Future.value(UnicodeEmojis.packs!);
  @override
  Widget build(BuildContext context) => FutureBuilder<
          List<UnicodeEmoticonPack>>(
      future: unicode,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Text(PhotoOverlayAsset.failed);
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final narrow = MediaQuery.of(context).mobile ||
            MediaQuery.sizeOf(context).width < 600;
        final component = widget.room?.getComponent<RoomEmoticonComponent>();
        final stickers = component?.availableStickers ?? <EmoticonPack>[];
        final emoji = [...?component?.availableEmoji];
        for (final pack in snapshot.data!) {
          if (!emoji.any((p) => p.identifier == pack.identifier))
            emoji.add(pack);
        }
        Widget picker(List<EmoticonPack> packs, bool sticker) =>
            EmojiPicker(packs,
                size: narrow ? 48 : 42,
                packButtonSize: narrow ? 48 : 42,
                onlyStickers: sticker,
                onlyEmoji: !sticker,
                packListAxis: narrow ? Axis.horizontal : Axis.vertical,
                sendLabel: PhotoOverlayPicker.add,
                onEmoticonPressed: load,
                searchDelegate: (text) => [
                      for (final p in packs)
                        for (final e in sticker ? p.stickers : p.emoji)
                          if ((e.shortcode ?? e.slug)
                              .toLowerCase()
                              .contains(text.toLowerCase()))
                            AutofillSearchResultEmoticon(
                                e.shortcode ?? e.slug, e.slug, e)
                    ]);
        return DefaultTabController(
            length: 2,
            child: Column(children: [
              TabBar(tabs: [
                Tab(text: PhotoOverlayPicker.stickers),
                Tab(text: PhotoOverlayPicker.emoji)
              ]),
              if (loading) const LinearProgressIndicator(),
              if (error != null)
                Text(error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              if (error != null && last != null)
                TextButton(
                    onPressed: () => load(last!),
                    child:
                        Text(Intl.message('Retry', name: 'photoOverlayRetry'))),
              Expanded(
                  child: IgnorePointer(
                      ignoring: loading,
                      child: TabBarView(children: [
                        stickers.isEmpty
                            ? Center(
                                child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Text(PhotoOverlayPicker.empty)))
                            : picker(stickers, true),
                        picker(emoji, false),
                      ]))),
              TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child:
                      Text(Intl.message('Cancel', name: 'photoOverlayCancel'))),
            ]));
      });
}
