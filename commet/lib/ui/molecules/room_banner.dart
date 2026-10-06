import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/room_banner/room_banner_component.dart';
import 'package:flutter/material.dart';

/// The room's banner as a strip, or nothing when the room has none.
class RoomBanner extends StatefulWidget {
  const RoomBanner(this.room, {this.height = 120, super.key});
  final Room room;
  final double height;

  @override
  State<RoomBanner> createState() => _RoomBannerState();
}

class _RoomBannerState extends State<RoomBanner> {
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.room
        .getComponent<RoomBannerComponent>()
        ?.onBannerChanged
        .listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = widget.room.getComponent<RoomBannerComponent>()?.banner;
    if (image == null) return const SizedBox.shrink();

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: double.infinity,
        height: widget.height,
        child: Image(
          image: image,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
        ),
      ),
    );
  }
}
