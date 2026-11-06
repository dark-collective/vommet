import 'dart:typed_data';

import 'package:commet/client/client.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_mxc_image_provider.dart';
import 'package:commet/client/matrix/nicknames/matrix_nicknames.dart';
import 'package:commet/client/matrix/nicknames/nickname_rules.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/utils/picker_utils.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: your picture in this room / space, under the nickname panel
/// (identity per place). Pass [space] for a space's settings; otherwise it
/// edits the room's own picture.
class PlacePictureSettings extends StatefulWidget {
  const PlacePictureSettings(
      {super.key, required this.client, required this.roomId, this.space});

  final MatrixClient client;
  final String roomId;
  final Space? space;

  @override
  State<PlacePictureSettings> createState() => _PlacePictureSettingsState();
}

class _PlacePictureSettingsState extends State<PlacePictureSettings> {
  bool busy = false;
  (int, int)? progress;
  String? error;

  MatrixNicknames get nicknames => MatrixNicknames.of(widget.client);
  bool get isSpace => widget.space != null;

  String get placePictureTitle => Intl.message("Picture",
      name: "placePictureTitle",
      desc: "Label of your own per-room or per-space picture setting");

  String get placePictureSourceRoom => Intl.message("Used in this room only",
      name: "placePictureSourceRoom",
      desc: "Where your picture here comes from: set for this room");

  String get placePictureSourceThisSpace =>
      Intl.message("Used across this space",
          name: "placePictureSourceThisSpace",
          desc: "Where your picture here comes from: set for this space");

  String placePictureSourceParentSpace(String space) =>
      Intl.message("From the space $space",
          args: [space],
          name: "placePictureSourceParentSpace",
          desc: "Where your picture here comes from: a space the room is in");

  String get placePictureSourceGlobal => Intl.message("Your global picture",
      name: "placePictureSourceGlobal",
      desc: "Where your picture here comes from: your account's picture");

  String get placePictureChoose => Intl.message("Choose",
      name: "placePictureChoose", desc: "Button: pick a picture for here");

  String get placePictureReset => Intl.message("Reset",
      name: "placePictureReset",
      desc: "Button: stop using a picture of its own here");

  String placePictureUpdating(int done, int total) =>
      Intl.message("Updating rooms: $done / $total",
          args: [done, total],
          name: "placePictureUpdating",
          desc: "Progress while your picture is written into a space's rooms");

  String placePictureRoomsFailed(int count) => Intl.plural(count,
      one: "Couldn't update $count room.",
      other: "Couldn't update $count rooms.",
      args: [count],
      name: "placePictureRoomsFailed",
      desc: "Some rooms of a space didn't take your new picture");

  String get placePictureSaveFailed =>
      Intl.message("Couldn't save your picture. Try again later.",
          name: "placePictureSaveFailed",
          desc: "Saving your picture for a room or space failed");

  /// The picture shown here, and where it comes from.
  (ImageProvider?, String) status() {
    final (mxc, source, from) = nicknames.effectiveAvatar(widget.roomId);
    if (mxc == null || source == NicknameSource.global) {
      return (widget.client.self?.avatar, placePictureSourceGlobal);
    }
    final image = MatrixMxcImage(
        Uri.parse(mxc), widget.client.getMatrixClient(),
        doFullres: false);
    if (source == NicknameSource.room) return (image, placePictureSourceRoom);
    final spaceName = widget.client.getSpace(from!)?.displayName ?? from;
    return (
      image,
      from == widget.roomId
          ? placePictureSourceThisSpace
          : placePictureSourceParentSpace(spaceName)
    );
  }

  bool get hasOwnPicture {
    final rules = nicknames.avatarRules;
    return (isSpace ? rules.spaces : rules.rooms).containsKey(widget.roomId);
  }

  Future<void> pick() async {
    final bytes = await PickerUtils.pickImageAndCrop(context, aspectRatio: 1);
    if (bytes == null) return;
    await save(bytes);
  }

  /// Uploads [bytes] and uses it here, or with null goes back to the space's
  /// picture or your global one.
  Future<void> save(Uint8List? bytes) async {
    setState(() {
      busy = true;
      error = null;
      progress = null;
    });
    try {
      final mxc =
          bytes == null ? null : await nicknames.uploadPicture(bytes, null);
      if (isSpace) {
        final failed = await nicknames.setSpaceAvatar(widget.space!, mxc,
            onProgress: (done, total) {
          if (mounted) setState(() => progress = (done, total));
        });
        if (failed.isNotEmpty) error = placePictureRoomsFailed(failed.length);
      } else {
        await nicknames.setRoomAvatar(widget.roomId, mxc);
      }
    } catch (e) {
      Log.w("Nicknames: couldn't save picture: $e");
      error = placePictureSaveFailed;
    }
    if (mounted) {
      setState(() {
        busy = false;
        progress = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final (image, source) = status();
    final (done, total) = progress ?? (null, null);
    final line = done != null && total != null && total > 0
        ? placePictureUpdating(done, total)
        : error ?? source;
    return Row(
      children: [
        tiamat.Avatar(
          radius: 20,
          image: image,
          placeholderText: widget.client.self?.displayName,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              tiamat.Text.label(placePictureTitle),
              tiamat.Text.labelLow(line),
            ],
          ),
        ),
        if (hasOwnPicture) ...[
          tiamat.Button.secondary(
            text: placePictureReset,
            onTap: busy ? null : () => save(null),
          ),
          const SizedBox(width: 8),
        ],
        tiamat.Button.secondary(
          text: placePictureChoose,
          isLoading: busy,
          onTap: busy ? null : pick,
        ),
      ],
    );
  }
}
