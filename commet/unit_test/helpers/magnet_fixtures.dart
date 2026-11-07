// Vommet issue 1139: drive real Matrix message renderers, not a hand-made
// link span or consent stub. This file also runs unchanged against the base.
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/components/profile/profile_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event_emote.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event_message.dart';
import 'package:commet/client/member.dart';
import 'package:commet/client/room.dart';
import 'package:commet/utils/notifying_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

const magnet =
    'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&dn=Linux.iso&tr=https%3A%2F%2Fa.example%2Fa&tr=udp%3A%2F%2Fb.example%3A80';
const me = '@lee:example.org';
const sender = '@alex:example.net';

class _Self extends Fake implements Profile {
  @override
  String get identifier => me;
}

class _Member extends Fake implements Member {
  @override
  String get displayName => 'Alex';
}

class _Room extends Fake implements MatrixRoom {
  @override
  Member getMemberOrFallback(String id) => _Member();
}

class _Client extends Fake implements MatrixClient {
  @override
  String get identifier => 'account';
  @override
  Profile get self => _Self();
  @override
  Room getRoom(String id) => _Room();
}

class MagnetTestManager extends Fake implements ClientManager {
  bool present = true;
  @override
  final clients = NotifyingList<MatrixClient>.empty();
  @override
  MatrixClient? getClient(String id) =>
      present && id == 'account' ? _Client() : null;
}

class _SdkRoom extends Fake implements matrix.Room {
  @override
  String get id => '!linux:example.org';
}

class MagnetTestLauncher extends UrlLauncherPlatform {
  @override
  LinkDelegate? get linkDelegate => null;
  final launched = <String>[];
  bool accepted = true;
  bool throws = false;
  Future<bool>? response;
  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    if (throws) throw PlatformException(code: 'denied');
    return response ?? Future.value(accepted);
  }
}

Widget message(
    {bool formatted = false, bool emote = false, String target = magnet}) {
  final event = matrix.Event(
      type: matrix.EventTypes.Message,
      eventId: r'$magnet',
      senderId: sender,
      originServerTs: DateTime(2026, 11, 4),
      room: _SdkRoom(),
      content: {
        'msgtype': emote ? 'm.emote' : 'm.text',
        'body': target,
        if (formatted) ...{
          'format': 'org.matrix.custom.html',
          'formatted_body':
              '<a href="${target.replaceAll('&', '&amp;')}">Linux ISO</a>'
        }
      });
  if (emote) {
    return MatrixTimelineEventEmote(event, client: _Client())
        .buildFormattedContent();
  }
  return MatrixTimelineEventMessage(event, client: _Client())
      .buildFormattedContent()!;
}
