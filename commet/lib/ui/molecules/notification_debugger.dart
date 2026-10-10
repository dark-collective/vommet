import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/push_notification/android/android_notifier.dart';
import 'package:commet/client/components/push_notification/android/firebase_push_notifier.dart';
import 'package:commet/client/components/push_notification/android/unified_push_notifier.dart';
import 'package:commet/client/components/push_notification/notification_manager.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/config/build_config.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/notifying_list_builder.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:commet/utils/notifying_list.dart';
import 'package:commet/utils/stream_utils.dart';
import 'package:flutter/material.dart';

import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:unifiedpush/unifiedpush.dart';
import 'package:window_manager/window_manager.dart';

import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' as matrix;

class NotificationDebugger extends StatefulWidget {
  const NotificationDebugger(
      {this.event, this.room, required this.client, super.key});
  final TimelineEvent? event;
  final Client client;
  final Room? room;
  @override
  State<NotificationDebugger> createState() => _NotificationDebuggerState();
}

class _NotificationDebugStep {
  String name;
  String description;
  bool? passed;

  _NotificationDebugStep(
      {required this.name, required this.description, required this.passed});
}

class _NotificationDebuggerState extends State<NotificationDebugger> {
  NotifyingList<_NotificationDebugStep> steps =
      NotifyingList.empty(growable: true);
  bool running = true;

  @override
  void initState() {
    runTests();
    super.initState();
  }

  bool get usesDesktopNotification =>
      PlatformUtils.isLinux || PlatformUtils.isWindows;

  Future<void> runTests() async {
    if (usesDesktopNotification) {
      await Future.delayed(Duration(seconds: 5));
      await windowManager.minimize();
    }

    if (PlatformUtils.isAndroid) {
      EventBus.openHomeScreen.add(null);
    }

    await Future.delayed(Duration(seconds: 1));

    try {
      if (widget.event case MatrixTimelineEvent event) {
        if (usesDesktopNotification) {
          await shouldNotifyTest(event);
          await handleNotificationTest(event);
        } else {
          await checkPermissions();
          await pushRulesTest(event, widget.room as MatrixRoom);
          await checkPushGateway(event, widget.room as MatrixRoom);
        }
      }
    } catch (e) {
      steps.add(_NotificationDebugStep(
          name: "Tests failed",
          description: "An error occured while running tests: ${e}",
          passed: false));
    }
    setState(() {
      running = false;
    });
  }

  Future<void> pushRulesTest(MatrixTimelineEvent event, MatrixRoom room) async {
    var evaluator = room.matrixRoom.client.pushruleEvaluator;
    var match = evaluator.match(event.event);

    // Vommet: say why the rules don't notify, and what to change; a bare
    // red mark left testers stuck ("I don't know how to fix this").
    var reason = match.notify ? null : pushRulesReason(event.event, room);
    if (reason != null) {
      final deciding = decidingRule(event.event, room);
      if (deciding != null) reason = "$reason\n\nDeciding rule: $deciding";
    }
    steps.add(_NotificationDebugStep(
        name: "Push Rules",
        description: reason == null
            ? "Check if the event matches your account's defined push rules"
            : "Your account's rules say not to notify for this message. $reason",
        passed: match.notify));
  }

  /// Vommet: which of the account's push rules decides for [event], as
  /// "<rule id> (<kind>): <actions>", or null if none matches. The SDK's
  /// evaluator only returns actions, so each enabled rule is evaluated on its
  /// own with a marker tweak to tell "matched" from "no match", in the
  /// evaluator's order: override, room, sender, content, underride.
  static String? decidingRule(matrix.Event event, MatrixRoom room) {
    final rules = room.matrixRoom.client.globalPushRules;
    if (rules == null) return null;
    const marker = "__vommet_probe__";

    matrix.PushRule probe(matrix.PushRule r) => matrix.PushRule(
          actions: [
            "notify",
            {"set_tweak": "sound", "value": marker}
          ],
          conditions: r.conditions,
          default$: r.default$,
          enabled: true,
          pattern: r.pattern,
          ruleId: r.ruleId,
        );

    bool matches(matrix.PushRuleSet set) {
      try {
        return matrix.PushruleEvaluator.fromRuleset(set).match(event).sound ==
            marker;
      } catch (_) {
        return false;
      }
    }

    String describe(matrix.PushRule r, String kind) =>
        "${r.ruleId} ($kind): ${r.actions.isEmpty ? "don't notify" : jsonEncode(r.actions)}";

    for (final r in rules.override ?? const <matrix.PushRule>[]) {
      if (r.enabled && matches(matrix.PushRuleSet(override: [probe(r)]))) {
        return describe(r, "override");
      }
    }
    for (final r in rules.room ?? const <matrix.PushRule>[]) {
      if (r.enabled && r.ruleId == event.room.id) return describe(r, "room");
    }
    for (final r in rules.sender ?? const <matrix.PushRule>[]) {
      if (r.enabled && r.ruleId == event.senderId) return describe(r, "sender");
    }
    for (final r in rules.content ?? const <matrix.PushRule>[]) {
      if (r.enabled && matches(matrix.PushRuleSet(content: [probe(r)]))) {
        return describe(r, "content");
      }
    }
    for (final r in rules.underride ?? const <matrix.PushRule>[]) {
      if (r.enabled && matches(matrix.PushRuleSet(underride: [probe(r)]))) {
        return describe(r, "underride");
      }
    }
    return "none of your rules matched this message";
  }

  /// Vommet: the likeliest reason the account's push rules don't notify for
  /// [event]. The SDK only says yes or no, so check the usual causes in turn.
  static String pushRulesReason(matrix.Event event, MatrixRoom room) {
    final mx = room.matrixRoom;
    final client = mx.client;

    if (event.senderId == client.userID) {
      return "It's your own message, and nobody is notified about their own "
          "messages. Run the test on a message someone else sent.";
    }

    final master = client.globalPushRules?.override
        ?.firstWhereOrNull((r) => r.ruleId == ".m.rule.master");
    if (master?.enabled == true) {
      return "All notifications are switched off for your account (the "
          "\"master\" rule, which some apps turn on for Do Not Disturb). Turn "
          "notifications back on in the app that switched them off, e.g. "
          "Element: Settings › Notifications › \"Enable notifications for this "
          "account\".";
    }

    switch (mx.pushRuleState) {
      case matrix.PushRuleState.dontNotify:
        return "This room is muted. Change it in the room's notification "
            "settings (here or in another app).";
      case matrix.PushRuleState.mentionsOnly:
        return "This room only notifies for mentions and keywords, and this "
            "message has neither. Change the room's notification setting, or "
            "test with a message that mentions you.";
      case matrix.PushRuleState.notify:
        break;
    }

    final relType = event.relationshipType;
    if (relType == matrix.RelationshipTypes.edit) {
      return "It's an edit; edits don't notify by default.";
    }
    if (event.type == matrix.EventTypes.Reaction) {
      return "It's a reaction; reactions don't notify by default.";
    }
    if (event.content["msgtype"] == "m.notice") {
      return "It's a bot notice (m.notice); those don't notify by default.";
    }
    if (event.type != matrix.EventTypes.Message &&
        event.type != matrix.EventTypes.Encrypted &&
        event.type != matrix.EventTypes.Sticker) {
      return "It's a \"${event.type}\" event, which your rules don't notify "
          "for. Test with an ordinary message.";
    }

    return "No rule asks to notify for it. Check the room's notification "
        "setting and your account's keyword and default rules, e.g. in "
        "Element under Settings › Notifications.";
  }

  Future<void> checkPermissions() async {
    final notifier = NotificationManager.notifier;
    var permission = false;

    if (notifier is UnifiedPushNotifier) {
      permission = await notifier.notifier.checkPermission();
    } else if (notifier is FirebasePushNotifier) {
      permission = await notifier.notifier.checkPermission();
    } else if (notifier is AndroidNotifier) {
      permission = await notifier.checkPermission();
    }

    var step = _NotificationDebugStep(
        name: "Check permissions",
        description:
            "Tests if we have permission from the system to display a notification",
        passed: permission);

    steps.add(step);
  }

  Future<void> shouldNotifyTest(MatrixTimelineEvent event) async {
    final shouldNotify = (widget.room as MatrixRoom).shouldNotify(
      event,
      onNotificationRejected: (reason) {
        var step = _NotificationDebugStep(
            name: "Notification rejected",
            description: "$reason",
            passed: false);

        steps.add(step);
      },
    );

    var step = _NotificationDebugStep(
        name: "Should Notify",
        description:
            "Tests whether the given event should trigger a notification",
        passed: shouldNotify);

    steps.add(step);
  }

  Future<void> checkPushGateway(
      MatrixTimelineEvent event, MatrixRoom room) async {
    var matrixClient = (widget.client as MatrixClient).getMatrixClient();
    var pushers = await matrixClient.getPushers();

    if (BuildConfig.ENABLE_GOOGLE_SERVICES == false) {
      steps.add(_NotificationDebugStep(
          name: "Unified Push Configuration",
          description: "Checks the current config for unified push",
          passed: preferences.unifiedPushEnabled.value == true &&
              preferences.unifiedPushEndpoint.value != null));

      if (preferences.unifiedPushEnabled.value == true) {
        var distributor = await UnifiedPush.getDistributor();

        steps.add(_NotificationDebugStep(
            name: "Unified Push Distributor",
            description: "distributor for unified push: $distributor",
            passed: distributor != null));
      }
    } else {
      steps.add(_NotificationDebugStep(
          name: "Google Services Configuration",
          description:
              "Checks the current config for Google services notifications: ${preferences.fcmKey.value == null ? "null" : preferences.fcmKey.value!.substring(0, 10) + "..."}",
          passed: preferences.fcmKey.value != null));
    }

    String? pushKey = BuildConfig.ENABLE_GOOGLE_SERVICES
        ? preferences.fcmKey.value
        : preferences.unifiedPushEndpoint.value;

    var pusher = pushers
        ?.where((i) =>
            i.deviceDisplayName == matrixClient.clientName &&
            i.pushkey == pushKey)
        .firstOrNull;

    var step = _NotificationDebugStep(
        name: "Has Registered Pusher",
        description:
            "Tests if the client has registered a push notification service with the homeserver: ${pusher?.data.url?.host}",
        passed: pusher != null);

    steps.add(step);

    if (pusher != null) {
      if (BuildConfig.ENABLE_GOOGLE_SERVICES &&
          pusher.data.additionalProperties["type"] == "fcm") {
        steps.add(_NotificationDebugStep(
            name: "Pusher configuration",
            description:
                "Checks the pusher is configured to use Google services",
            passed: true));
      }

      final url = pusher.data.url!.replace(path: "/_matrix/push/v1/notify");

      final content = {
        "notification": {
          "devices": [
            {
              "app_id": pusher.appId,
              "data": {
                ...pusher.data.additionalProperties,
              },
              "pushkey": pusher.pushkey,
            },
          ],
          "event_id": event.eventId,
          "prio": "high",
          "room_id": room.identifier
        }
      };

      Log.i("Sending to: $url");
      Log.i(
        "Sending test notification: ${content}",
      );

      var startTime = DateTime.now();

      var nextData =
          EventBus.onReceivedPushNotificationData.stream.nextItemAsFuture();

      var result = await http.post(url, body: jsonEncode(content), headers: {
        'Content-Type': 'application/json; charset=UTF-8',
      });

      var step = _NotificationDebugStep(
          name: "Send test notification",
          description:
              "Tests if sending a notification to the registered pusher is accepted",
          passed: result.statusCode == 200);

      steps.add(step);
      try {
        final result = await nextData.timeout(Duration(seconds: 20));
        var endTime = DateTime.now();
        var length = endTime.difference(startTime);
        var step = _NotificationDebugStep(
            name: "Receive notification",
            description:
                "Received data back from push service in ${length.inMilliseconds}ms: $result",
            passed: true);

        steps.add(step);
      } catch (e) {
        if (e is TimeoutException) {
          var step = _NotificationDebugStep(
              name: "Receive notification",
              description:
                  "Did not receive any data back from push service after waiting 20 seconds",
              passed: false);

          steps.add(step);
        } else {
          var step = _NotificationDebugStep(
              name: "Receive notification",
              description:
                  "Unknown error occured waiting for notification data: $e",
              passed: false);

          steps.add(step);
        }
      }
    }
  }

  Future<void> handleNotificationTest(MatrixTimelineEvent event) async {
    final f = (widget.room as MatrixRoom).handleNotification(
      event,
      onNotificationRejected: (reason) {
        var step = _NotificationDebugStep(
            name: "Notification rejected",
            description: "$reason",
            passed: false);

        steps.add(step);
      },
    );

    await f;

    var step = _NotificationDebugStep(
        name: "Handle Notification",
        description: "If you saw a notification, this test passed.",
        passed: null);

    steps.add(step);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 500,
      height: 500,
      child: Column(
        children: [
          if (running)
            Column(
              children: [
                if (usesDesktopNotification)
                  tiamat.Text.labelLow(
                      "The app may be minimized while testing. if minimized, wait for atleast 5 seconds before re-opening"),
                CircularProgressIndicator(),
              ],
            ),
          if (!running)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: tiamat.Text.label("Test complete"),
            ),
          Flexible(
            child: NotifyingListBuilder(
              list: steps,
              itemBuilder: (context, value) {
                return Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    spacing: 8,
                    children: [
                      Icon(
                        value.passed == null
                            ? Icons.question_mark
                            : value.passed!
                                ? Icons.check
                                : Icons.error,
                        color: value.passed == null
                            ? null
                            : value.passed!
                                ? Colors.green
                                : Colors.red,
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            tiamat.Text(value.name),
                            tiamat.Text.labelLow(
                              value.description,
                            )
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
