import 'package:commet/client/components/space_color_scheme/space_color_scheme_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_space.dart';
import 'package:commet/utils/image/image_seed_color.dart';
import 'package:commet/utils/image/lod_image.dart';
import 'package:commet/utils/task_scheduler.dart';
import 'package:flutter/src/material/color_scheme.dart';

class MatrixSpaceColorSchemeComponent
    implements SpaceColorSchemeComponent<MatrixClient, MatrixSpace> {
  @override
  MatrixClient client;

  // Vommet: the fallback scheme is made on first use, not for every space
  // while they are created at startup (the tonal palettes are a few ms each
  // on a slow device).
  @override
  ColorScheme get scheme =>
      _scheme ??= ColorScheme.fromSeed(seedColor: space.color);

  @override
  MatrixSpace space;

  static TaskScheduler scheduler = OneAtATimeScheduler();

  MatrixSpaceColorSchemeComponent(this.client, this.space) {
    // Vommet: after startup, not during it. Deriving a scheme from the
    // avatar is synchronous image work on the UI isolate; for 23 spaces it
    // was ~15% of a 237-room account's first 8 s (startup CPU profile).
    Future.delayed(_startupDelay, () {
      _started = true;
      MatrixSpaceColorSchemeComponent.scheduler.enqueue(updateColorScheme);
    });

    space.onUpdate.listen((_) {
      if (!_started) return;
      MatrixSpaceColorSchemeComponent.scheduler.enqueue(updateColorScheme);
    });
  }

  static const _startupDelay = Duration(seconds: 5);
  bool _started = false;

  ColorScheme? _scheme;

  /// Vommet: the avatar the scheme was derived from. A space updates for
  /// many reasons (state loading, unread counts); only a new avatar needs
  /// a new scheme.
  Uri? _schemeAvatar;

  Future<void> updateColorScheme() async {
    final avatarUrl = space.matrixRoom.avatar;
    if (avatarUrl == _schemeAvatar) return;
    _schemeAvatar = avatarUrl;

    if (space.avatar case LODImageProvider img) {
      await img.fetchThumbnail();
    }

    if (space.avatar != null) {
      // Vommet: the seed colour is worked out in a background isolate (see
      // ImageSeedColor); the same scheme fromImageProvider gave, without its
      // ~40 ms of UI-isolate work per space.
      final seed = await ImageSeedColor.fromProvider(space.avatar!);
      if (seed == null) return;
      _scheme = ColorScheme.fromSeed(
          seedColor: seed,
          dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot);
    }
  }
}
