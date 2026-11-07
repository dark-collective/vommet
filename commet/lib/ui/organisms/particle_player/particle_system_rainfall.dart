import 'package:commet/client/components/message_effects/message_effect_particles.dart';
import 'package:commet/ui/organisms/particle_player/particle_sprite_drawn.dart';
import 'package:starfield/starfield.dart';

/// Vommet: Element's rainfall (`io.element.effect.rainfall`) — blue streaks
/// falling over the chat.
class MessageEffectRainfall implements MessageEffectParticles {
  @override
  EcsParticleSystem? system;

  @override
  Future<void> init() async {
    final sprite = await DrawnParticleSprite.drop();
    system = ParticleSystemRainfall(
        sprite: sprite, spriteSize: 1, gravity: 40, height: 900);
    system!.setSize(400);
  }
}

class ParticleSystemRainfall extends ParticleSystemRain {
  ParticleSystemRainfall({
    super.sprite,
    super.spriteSize = 1,
    super.gravity = 40,
    super.height = 900,
  });

  @override
  void setDefaultSpriteProperties(int index) {
    // Light blue, a little see-through, all upright.
    setColor(index, 0xB39FD3FF);
    setScale(index, 0.5 + (index % 100) / 200 * spriteSize);
    setRotation(index, 0);
    rects[index * 4 + 0] = 0;
    rects[index * 4 + 1] = 0;
    rects[index * 4 + 2] = sprite!.width.toDouble();
    rects[index * 4 + 3] = sprite!.height.toDouble();
  }

  @override
  void processRotations(double delta) {}
}
