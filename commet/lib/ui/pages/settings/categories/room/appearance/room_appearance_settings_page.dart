import 'dart:async';
import 'dart:typed_data';

import 'package:commet/client/components/room_banner/room_banner_component.dart';
import 'package:commet/client/room.dart';
import 'package:commet/ui/molecules/image_select_dialog.dart';
import 'package:commet/ui/pages/settings/categories/room/appearance/room_appearance_settings_view.dart';
import 'package:commet/utils/picker_utils.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class RoomAppearanceSettingsPage extends StatefulWidget {
  const RoomAppearanceSettingsPage({super.key, required this.room});
  final Room room;
  @override
  State<RoomAppearanceSettingsPage> createState() =>
      _RoomAppearanceSettingsPageState();
}

class _RoomAppearanceSettingsPageState
    extends State<RoomAppearanceSettingsPage> {
  late StreamSubscription _sub;
  StreamSubscription? _bannerSub;
  bool uploadingBanner = false;

  RoomBannerComponent? get bannerComponent =>
      widget.room.getComponent<RoomBannerComponent>();

  @override
  void initState() {
    super.initState();
    _sub = widget.room.onUpdate.listen((_) {
      if (mounted) setState(() {});
    });
    _bannerSub = bannerComponent?.onBannerChanged.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    _bannerSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        appearance(),
        if (bannerComponent?.canEditBanner == true) ...[
          const SizedBox(height: 12),
          const tiamat.Text.labelLow("Set Banner:"),
          bannerEditor(context),
        ],
      ],
    );
  }

  Widget bannerEditor(BuildContext context) {
    final image = uploadingBanner ? null : bannerComponent?.banner;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            image: image != null
                ? DecorationImage(image: image, fit: BoxFit.cover)
                : null),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => editBanner(context, image),
            child: SizedBox(
              width: double.infinity,
              height: 250,
              child: uploadingBanner
                  ? const Center(
                      child: SizedBox(
                          width: 30,
                          height: 30,
                          child: CircularProgressIndicator()))
                  : null,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> editBanner(BuildContext context, ImageProvider? image) async {
    final action = await ImageSelectDialog.show(context, image: image);
    if (!context.mounted) return;

    if (action == ImageEditAction.remove) {
      setState(() => uploadingBanner = true);
      await bannerComponent?.removeBanner();
      if (mounted) setState(() => uploadingBanner = false);
      return;
    }
    if (action != ImageEditAction.pick) return;

    final result =
        await PickerUtils.pickImageAndCrop(context, aspectRatio: 16 / 9);
    if (result == null) return;

    setState(() => uploadingBanner = true);
    await bannerComponent?.setBanner(result);
    if (mounted) setState(() => uploadingBanner = false);
  }

  Widget appearance() {
    return RoomAppearanceSettingsView(
      client: widget.room.client,
      avatar: widget.room.avatar,
      displayName: widget.room.displayName,
      identifier: widget.room.identifier,
      color: widget.room.defaultColor,
      canEditName: widget.room.permissions.canEditName,
      canEditAvatar: widget.room.permissions.canEditAvatar,
      canEditTopic: widget.room.permissions.canEditTopic,
      topic: widget.room.topic,
      setTopic: widget.room.setTopic,
      onImagePicked: setRoomAvatar,
      onNameChanged: setRoomName,
    );
  }

  void setRoomAvatar(Uint8List bytes, String? mimeType) {
    widget.room.setRoomAvatar(bytes, mimeType);
  }

  void setRoomName(String name) {
    widget.room.setDisplayName(name);
  }
}
