import 'package:commet/main.dart';

/// Vommet: what the member list shows under a member's name
/// (Settings › Appearance › Member list).
enum MemberListSubtitle {
  homeserverOrStatus("Homeserver, replaced by status",
      "A status takes the homeserver's place. The full ID is on the profile."),
  homeserverAndStatus("Homeserver and status",
      "The homeserver, then the status after it on the same line."),
  statusOff("Status off", "Only the homeserver. Statuses are hidden.");

  const MemberListSubtitle(this.label, this.description);
  final String label;
  final String description;

  static MemberListSubtitle parse(String value) =>
      MemberListSubtitle.values.firstWhere((m) => m.name == value,
          orElse: () => MemberListSubtitle.homeserverOrStatus);

  static MemberListSubtitle get current =>
      parse(preferences.memberListSubtitle.value);
}

/// Vommet: a homeserver name for the member list's "server · status" line,
/// at most [max] characters. Longer names lose their start, cut at a dot or
/// hyphen, because the end is what identifies the server:
/// "matrix.some-university.ac.uk" becomes "…university.ac.uk".
String shortServerName(String server, {int max = 20}) {
  if (server.length <= max) return server;
  // Room for the "…".
  final from = server.length - (max - 1);
  for (var i = from; i < server.length - 1; i++) {
    final c = server[i];
    if (c == "." || c == "-") return "…${server.substring(i + 1)}";
  }
  return "…${server.substring(from)}";
}
