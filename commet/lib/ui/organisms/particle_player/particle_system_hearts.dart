import 'dart:ui';

import 'dart:ui' as ui;
import 'package:commet/client/components/message_effects/message_effect_particles.dart';
import 'package:commet/ui/organisms/particle_player/particle_system_hug.dart';
import 'package:starfield/starfield.dart';

/// Vommet: Element's hearts (`io.element.effect.hearts`) — hearts rising up
/// from the bottom of the chat.
class MessageEffectHearts implements MessageEffectParticles {
  @override
  EcsParticleSystem? system;

  @override
  Future<void> init() async {
    var data = await ImmutableBuffer.fromAsset(
        "assets/images/effects/particles/fluentui-emoji-heart-with-ribbon.webp");
    var codec = await ui.instantiateImageCodecFromBuffer(data);
    var sprite = ParticleSprite();

    // One frame, as a sheet, so the shared motion below gets its draw rects.
    await sprite.init(
        codec: codec,
        spriteSheet: SpriteSheetInfo(
            frames: 1, frameWidth: 128, frameHeight: 128, framesPerSecond: 1));

    // Same rise-and-sway motion as the hug effect.
    system = ParticleSystemEyes(
        sprite: sprite, spriteSize: 0.4, gravity: -10, height: 500);
    system!.setSize(120);
  }
}
