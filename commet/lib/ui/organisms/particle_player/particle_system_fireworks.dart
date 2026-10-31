import 'dart:math';
import 'dart:typed_data';

import 'package:commet/client/components/message_effects/message_effect_particles.dart';
import 'package:commet/ui/organisms/particle_player/particle_sprite_drawn.dart';
import 'package:flutter/material.dart';
import 'package:starfield/starfield.dart';

/// Vommet: Element's fireworks (`nic.custom.fireworks`) — a few colored
/// bursts, one after another, at different spots over the chat.
class MessageEffectFireworks implements MessageEffectParticles {
  @override
  EcsParticleSystem? system;

  @override
  Future<void> init() async {
    final sprite = await DrawnParticleSprite.spark();
    system = ParticleSystemFireworks(sprite: sprite);
    system!.setSize(ParticleSystemFireworks.bursts *
        ParticleSystemFireworks.sparksPerBurst);
  }
}

class ParticleSystemFireworks extends EcsParticleSystem {
  static const int bursts = 6;
  static const int sparksPerBurst = 90;

  /// Seconds between one burst and the next.
  static const double burstGap = 0.45;

  /// Seconds a spark stays visible.
  static const double sparkLife = 1.6;

  static const List<int> burstColors = [
    0xFFFF5252,
    0xFFFFD740,
    0xFF69F0AE,
    0xFF40C4FF,
    0xFFE040FB,
    0xFFFFAB40,
  ];

  ParticleSystemFireworks({super.sprite}) : super(alignment: Alignment.topLeft);

  late Float32List _startVelocities;
  final List<Offset> _centers = [];

  int burstOf(int index) => index ~/ sparksPerBurst;

  double burstStart(int burst) => burst * burstGap;

  @override
  void setSize(int particleCount) {
    super.setSize(particleCount);
    _startVelocities = Float32List(particleCount * 2);
  }

  @override
  void init() {
    final size = currentSize ?? const Size(800, 600);
    _centers.clear();
    for (int b = 0; b < bursts; b++) {
      _centers.add(Offset(
        size.width * (0.15 + r.nextDouble() * 0.7),
        size.height * (0.15 + r.nextDouble() * 0.4),
      ));
    }
    super.init();
  }

  @override
  void setDefaultSpriteProperties(int index) {
    setScale(index, 0);
    setRotation(index, 0);
    setColor(index, 0);
    rects[index * 4 + 0] = 0;
    rects[index * 4 + 1] = 0;
    rects[index * 4 + 2] = sprite!.width.toDouble();
    rects[index * 4 + 3] = sprite!.height.toDouble();
  }

  @override
  void setDefaultProperties(int index) {
    final center = _centers[burstOf(index)];
    setPositionX(index, center.dx);
    setPositionY(index, center.dy);

    final angle = r.nextDouble() * 2 * pi;
    final speed = 120 + r.nextDouble() * 260;
    _startVelocities[indexToPosXIndex(index)] = cos(angle) * speed;
    _startVelocities[indexToPosYIndex(index)] = sin(angle) * speed;
  }

  @override
  void processVelocities(double delta) {
    for (int i = 0; i < numParticles; i++) {
      final age = time - burstStart(burstOf(i));
      if (age < 0) continue;
      if (age - delta < 0) {
        // This burst just went off.
        setVelocityX(i, _startVelocities[indexToPosXIndex(i)]);
        setVelocityY(i, _startVelocities[indexToPosYIndex(i)]);
        continue;
      }
      setVelocityX(i, getVelocityX(i) * 0.97);
      setVelocityY(i, getVelocityY(i) * 0.97 + 4);
    }
  }

  @override
  void processAngularVelocities(double delta) {}

  @override
  void processRotations(double delta) {
    // Sparks don't spin; fade them out instead.
    for (int i = 0; i < numParticles; i++) {
      final burst = burstOf(i);
      final age = time - burstStart(burst);
      if (age < 0 || age > sparkLife) {
        setColor(i, 0);
        setScale(i, 0);
        continue;
      }
      final fade = 1 - age / sparkLife;
      final alpha = (fade * 255).round().clamp(0, 255);
      setColor(i,
          (alpha << 24) | (burstColors[burst % burstColors.length] & 0xFFFFFF));
      setScale(i, 0.25 + 0.35 * fade);
    }
  }

  @override
  bool shouldStop() => time > burstStart(bursts - 1) + sparkLife;
}
