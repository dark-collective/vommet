import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/message_effects/message_effect_component.dart';
import 'package:commet/client/components/message_effects/message_effect_particles.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/ui/atoms/reaction_burst.dart';
import 'package:commet/ui/organisms/particle_player/particle_system_confetti.dart';
import 'package:commet/ui/organisms/particle_player/particle_system_eyes.dart';
import 'package:commet/ui/organisms/particle_player/particle_system_fireworks.dart';
import 'package:commet/ui/organisms/particle_player/particle_system_hearts.dart';
import 'package:commet/ui/organisms/particle_player/particle_system_hug.dart';
import 'package:commet/ui/organisms/particle_player/particle_system_rainfall.dart';
import 'package:commet/ui/organisms/particle_player/particle_system_snow.dart';
import 'package:commet/ui/organisms/particle_player/particle_system_space_invaders.dart';
import 'package:commet/utils/event_bus.dart';

import 'package:matrix/matrix.dart' as matrix;

class MatrixMessageEffectsComponent
    implements MessageEffectComponent<MatrixClient> {
  @override
  final MatrixClient client;

  static const effectTypeSnowfall = "io.element.effect.snowfall";
  static const effectTypeConfetti = "nic.custom.confetti";
  static const effectTypeSpaceInvaders = "io.element.effects.space_invaders";
  static const effectTypeCuteEvent = "im.fluffychat.cute_event";
  static const effectTypeGoogly = "googly_eyes";
  static const effectTypeHug = "hug";
  static const effectTypeCuddle = "cuddle";

  // Vommet: Element's other effects.
  static const effectTypeFireworks = "nic.custom.fireworks";
  static const effectTypeRainfall = "io.element.effect.rainfall";
  static const effectTypeHearts = "io.element.effect.hearts";

  MatrixMessageEffectsComponent(this.client) {
    var mx = client.getMatrixClient();

    mx.addCommand(
        "snowfall",
        (args, _) =>
            sendWithMsgType(args, msgType: effectTypeSnowfall, fallback: "❄️"));

    mx.addCommand(
        "confetti",
        (args, _) =>
            sendWithMsgType(args, msgType: effectTypeConfetti, fallback: "🎉"));

    mx.addCommand(
        "spaceinvaders",
        (args, _) => sendWithMsgType(args,
            msgType: effectTypeSpaceInvaders, fallback: "👾"));

    mx.addCommand(
        "fireworks",
        (args, _) => sendWithMsgType(args,
            msgType: effectTypeFireworks, fallback: "🎆"));

    mx.addCommand(
        "rainfall",
        (args, _) => sendWithMsgType(args,
            msgType: effectTypeRainfall, fallback: "🌧️"));

    mx.addCommand(
        "hearts",
        (args, _) =>
            sendWithMsgType(args, msgType: effectTypeHearts, fallback: "💝"));

    // Vommet: the SDK's /hug, /cuddle and /googly drop what you typed; these
    // keep it as the body (the emoji when nothing was typed).
    mx.addCommand(
        "hug",
        (args, _) => sendWithMsgType(args,
            msgType: effectTypeCuteEvent,
            fallback: "🤗",
            extra: {"cute_type": effectTypeHug}));

    mx.addCommand(
        "cuddle",
        (args, _) => sendWithMsgType(args,
            msgType: effectTypeCuteEvent,
            fallback: "😊",
            extra: {"cute_type": effectTypeCuddle}));

    mx.addCommand(
        "googly",
        (args, _) => sendWithMsgType(args,
            msgType: effectTypeCuteEvent,
            fallback: "👀",
            extra: {"cute_type": effectTypeGoogly}));

    // Vommet: tell reaction chips which reactions just arrived (yours
    // included, via their local echo), for reaction bursts.
    mx.onTimelineEvent.stream.listen((event) {
      if (event.type != matrix.EventTypes.Reaction) return;
      final key = event.content
          .tryGetMap<String, Object?>("m.relates_to")
          ?.tryGet<String>("key");
      if (key == null) return;
      ReactionBurstSignal.noteLive(key, sentAt: event.originServerTs);
    });
  }

  static const Set<String> knownEffectTypes = {
    effectTypeSnowfall,
    effectTypeConfetti,
    effectTypeSpaceInvaders,
    effectTypeCuteEvent,
    effectTypeFireworks,
    effectTypeRainfall,
    effectTypeHearts,
  };

  String? getEffectType(TimelineEvent event) {
    if (!hasEffect(event)) {
      return null;
    }

    var mxevent = (event as MatrixTimelineEvent).event;
    var type = mxevent.content["msgtype"] as String;

    if (type == "im.fluffychat.cute_event") {
      type = mxevent.content['cute_type'] as String;
    }

    return type;
  }

  @override
  void doEffect(TimelineEvent event) async {
    if (!hasEffect(event)) {
      return;
    }
    final type = getEffectType(event);
    if (type == null) {
      return;
    }

    final effect = createEffect(type);

    if (effect == null) {
      return;
    }

    await effect.init();
    EventBus.doMessageEffect.add(effect);
  }

  MessageEffectParticles? createEffect(String type) {
    switch (type) {
      case effectTypeConfetti:
        return MessageEffectConfetti();
      case effectTypeSnowfall:
        return MessageEffectSnow();
      case effectTypeSpaceInvaders:
        return MessageEffectSpaceInvaders();
      case effectTypeGoogly:
        return MessageEffectEyes(numParticles: 100);
      case effectTypeHug:
        return MessageEffectHug();
      case effectTypeCuddle:
        return MessageEffectHug();
      case effectTypeFireworks:
        return MessageEffectFireworks();
      case effectTypeRainfall:
        return MessageEffectRainfall();
      case effectTypeHearts:
        return MessageEffectHearts();
    }

    return null;
  }

  FutureOr<String?> sendWithMsgType(matrix.CommandArgs args,
      {required String msgType,
      required String fallback,
      Map<String, dynamic> extra = const {}}) async {
    // Vommet: keep the reply (and edit) the command was sent with.
    return await args.room?.sendEvent(
      {
        "msgtype": msgType,
        ...extra,
        "body": args.msg.trim().isEmpty ? fallback : args.msg,
      },
      inReplyTo: args.inReplyTo,
      editEventId: args.editEventId,
      txid: args.txid,
    );
  }

  @override
  bool hasEffect(TimelineEvent<Client> event) {
    if (event is! MatrixTimelineEvent) {
      return false;
    }

    final mxEvent = event.event;
    if (mxEvent.type != matrix.EventTypes.Message) {
      return false;
    }

    final type = mxEvent.content["msgtype"];
    if (type == null || type is! String) {
      return false;
    }

    return knownEffectTypes.contains(type);
  }
}
