// Vommet issue 1066: the desktop tray of waiting files.
import 'dart:typed_data';

import 'package:commet/client/attachment.dart';
import 'package:commet/config/layout_style.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/drag_drop_file_target.dart';
import 'package:commet/ui/molecules/attachment_icon.dart';
import 'package:commet/ui/molecules/desktop_attachment_tray.dart';
import 'package:commet/ui/molecules/message_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

PendingFileAttachment _file(String name) =>
    PendingFileAttachment(name: name, path: '/pictures/$name');

void main() {
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await preferences.sendSmallerPictures.set('never');
  });

  test('every file goes to the tray on desktop', () {
    expect(DesktopAttachmentTray.platform, isTrue);
    for (final name in ['hike.png', 'hike.jpg', 'hike.mp4', 'notes.pdf']) {
      expect(DesktopAttachmentTray.handles(_file(name)), isTrue);
    }
    expect(DesktopAttachmentTray.isPicture(_file('hike.mp4')), isFalse);
    expect(DesktopAttachmentTray.canSpoiler(_file('hike.mp4')), isTrue);
    expect(DesktopAttachmentTray.canSpoiler(_file('notes.pdf')), isFalse);
  });

  test('a pasted picture gets a name from its type', () {
    final pasted =
        PendingFileAttachment(mimeType: 'image/png', data: Uint8List(8));
    DesktopAttachmentTray.nameAnonymous(pasted);
    expect(pasted.name, 'image.png');
  });

  test('new pictures take the defaults, then the tray settings', () async {
    final first = _file('a.png');
    await DesktopAttachmentTray.applySettings(first, const []);
    expect(first.removeHiddenInfo, isTrue);
    expect(first.shrinkLongestEdge, isNull);

    first.removeHiddenInfo = false;
    first.shrinkLongestEdge = 1280;
    final second = _file('b.png');
    await DesktopAttachmentTray.applySettings(second, [first]);
    expect(second.removeHiddenInfo, isFalse);
    expect(second.shrinkLongestEdge, 1280);

    await preferences.sendSmallerPictures.set('always');
    final alone = _file('c.png');
    await DesktopAttachmentTray.applySettings(alone, [_file('d.pdf')]);
    expect(alone.shrinkLongestEdge, DesktopAttachmentTray.longestEdge);

    final pdf = _file('e.pdf');
    await DesktopAttachmentTray.applySettings(pdf, [alone]);
    expect(pdf.removeHiddenInfo, isFalse);
    expect(pdf.shrinkLongestEdge, isNull);
  });

  Future<void> pumpTray(WidgetTester tester, List<PendingFileAttachment> files,
      {Future<void> Function(PendingFileAttachment)? onOpen}) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: DesktopAttachmentTray(
                files: files,
                onRemove: (_) {},
                onMove: (_, __) {},
                onOpen: onOpen))));
    expect(tester.takeException(), isNull);
  }

  double radius(WidgetTester tester) {
    final box = tester
        .widget<Container>(
            find.byKey(const ValueKey('desktop-attachment-tray')))
        .decoration as BoxDecoration;
    return (box.borderRadius as BorderRadius).topLeft.x;
  }

  testWidgets('the tray takes the composer shape of the layout style',
      (tester) async {
    await LayoutOptions.discord.save();
    await pumpTray(tester, [_file('a.png')]);
    expect(currentLayoutStyle, LayoutStyle.discord);
    expect(radius(tester), 8);

    await LayoutOptions.telegram.save();
    await pumpTray(tester, [_file('b.png')]);
    expect(currentLayoutStyle, LayoutStyle.telegram);
    expect(radius(tester), 20);

    await layoutStyleCustomPicked.set(true);
    await pumpTray(tester, [_file('c.png')]);
    expect(radius(tester), 20);
  });

  testWidgets('dragging files over the window shows a drop slot',
      (tester) async {
    addTearDown(() => DragDropFileTarget.filesHovering.value = false);
    await pumpTray(tester, [_file('a.png')]);
    const slot = ValueKey('desktop-tray-drop-slot');
    expect(find.byKey(slot), findsNothing);
    DragDropFileTarget.filesHovering.value = true;
    await tester.pump();
    expect(find.byKey(slot), findsOneWidget);
    expect(find.text(DesktopAttachmentTray.labelDropHere), findsOneWidget);
    DragDropFileTarget.filesHovering.value = false;
    await tester.pump();
    expect(find.byKey(slot), findsNothing);
  });

  testWidgets('videos and other files are tiles with their name',
      (tester) async {
    final files = [_file('a.png'), _file('clip.mp4'), _file('notes.pdf')];
    final opened = <PendingFileAttachment>[];
    await pumpTray(tester, files, onOpen: (f) async => opened.add(f));
    expect(find.text('clip.mp4'), findsOneWidget);
    expect(find.text('notes.pdf'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('desktop-tray-spoiler-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('desktop-tray-spoiler-2')), findsNothing);
    await tester.tap(find.byType(AttachmentIcon).at(2));
    await tester.pump();
    expect(opened, [files[2]]);
  });

  testWidgets('a picture opens big, with crop and spoiler', (tester) async {
    final picture = _file('a.png');
    await pumpTray(tester, [picture]);
    await tester.tap(find.byType(AttachmentIcon));
    await tester.pumpAndSettle();
    const preview = ValueKey('desktop-tray-preview');
    expect(find.byKey(preview), findsOneWidget);

    // The tools show on hover, or on a tap without a mouse.
    await tester.tapAt(tester.getCenter(find.byKey(preview)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('desktop-preview-crop')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('desktop-preview-spoiler')));
    await tester.pumpAndSettle();
    expect(picture.spoiler, isTrue);

    await tester.tap(find.byKey(const ValueKey('desktop-preview-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(preview), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switches apply to every picture; spoiler; clear all',
      (tester) async {
    final files = [_file('a.png'), _file('b.png')];
    for (final f in files) {
      await DesktopAttachmentTray.applySettings(f, const []);
    }
    final removed = <PendingFileAttachment>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: DesktopAttachmentTray(
                files: files, onRemove: removed.add, onMove: (_, __) {}))));
    expect(tester.takeException(), isNull);
    expect(find.text(DesktopAttachmentTray.labelCount(2)), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('desktop-tray-send-smaller')));
    await tester.pump();
    expect(files.every((f) => f.shrinkLongestEdge != null), isTrue);

    await tester.tap(find.byKey(const ValueKey('desktop-tray-hidden-info')));
    await tester.pump();
    expect(files.every((f) => !f.removeHiddenInfo), isTrue);

    await tester.tap(find.byKey(const ValueKey('desktop-tray-spoiler-1')));
    await tester.pump();
    expect(files[1].spoiler, isTrue);
    expect(files[0].spoiler, isFalse);

    await tester.tap(find.byKey(const ValueKey('desktop-tray-clear-all')));
    expect(removed, files);
  });

  group('a tile opened and changed takes its place', () {
    // Like Chat: add runs the size check and may refuse the file.
    Future<List<PendingFileAttachment>> replace(PendingFileAttachment processed,
        {required bool fits}) async {
      final list = [_file('a.png'), _file('clip.mp4'), _file('b.png')];
      final video = list[1];
      // ignore: invalid_use_of_visible_for_testing_member
      await MessageInputState.replaceInTray(
          file: video,
          processed: processed,
          attachments: () => list,
          add: (f) async {
            if (fits) list.add(f);
          },
          remove: list.remove,
          move: (f, i) {
            list.remove(f);
            list.insert(i, f);
          });
      return list;
    }

    test('same position', () async {
      final gif = _file('clip.gif');
      final list = await replace(gif, fits: true);
      expect(list.map((f) => f.name), ['a.png', 'clip.gif', 'b.png']);
    });

    test('a result over the upload limit leaves the original', () async {
      final list = await replace(_file('clip.gif'), fits: false);
      expect(list.map((f) => f.name), ['a.png', 'clip.mp4', 'b.png']);
    });
  });
}
