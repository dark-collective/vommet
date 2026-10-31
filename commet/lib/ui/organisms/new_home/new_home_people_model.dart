// Vommet (New Home step 2): the People page's logic, kept free of the SDK
// and of widgets so it can be unit tested: how contacts sort, which invites
// count as received and sent, and what Active Now shows.
import 'package:commet/client/components/user_presence/user_presence_component.dart';

/// The People page's chips.
enum PeopleTab {
  contacts("Contacts"),
  invites("Invites"),
  blocked("Blocked");

  const PeopleTab(this.label);
  final String label;
}

class PeopleModel {
  /// Contacts sort online first, then away, then everyone else. Offline and
  /// unknown share the last group: homeservers that don't share presence
  /// (matrix.org among them) report people as offline or not at all, so
  /// neither tells you anything.
  static int presenceRank(UserPresenceStatus status) => switch (status) {
        UserPresenceStatus.online => 0,
        UserPresenceStatus.unavailable => 1,
        UserPresenceStatus.offline || UserPresenceStatus.unknown => 2,
      };

  /// Orders contacts by [presenceRank], then by name (case-insensitive),
  /// then by Matrix ID so equal names keep a stable order.
  static int compareContacts(UserPresenceStatus a, String aName, String aId,
      UserPresenceStatus b, String bName, String bId) {
    final rank = presenceRank(a).compareTo(presenceRank(b));
    if (rank != 0) return rank;
    final name = aName.toLowerCase().compareTo(bName.toLowerCase());
    if (name != 0) return name;
    return aId.compareTo(bId);
  }

  /// Whether a contact row shows a presence dot: only for online and away.
  /// Unknown never shows as offline, and a homeserver without presence
  /// reports everyone offline, so offline gets no dot either.
  static bool showsPresenceDot(UserPresenceStatus status) =>
      status == UserPresenceStatus.online ||
      status == UserPresenceStatus.unavailable;

  /// A contact row's muted second line: the status message when there is
  /// one, else "Online" or "Away", else nothing.
  static String? contactSubtitle(UserPresenceStatus status, String? message) {
    final m = message?.trim();
    if (m != null && m.isNotEmpty) return m;
    return switch (status) {
      UserPresenceStatus.online => "Online",
      UserPresenceStatus.unavailable => "Away",
      _ => null,
    };
  }

  /// Whether [query] (already trimmed) matches a person by name or ID.
  static bool matchesPerson(String query, String name, String userId) {
    final q = query.toLowerCase();
    if (q.isEmpty) return true;
    return name.toLowerCase().contains(q) || userId.toLowerCase().contains(q);
  }

  /// The received DM invites among [invites], newest first. Invites that
  /// aren't marked as direct messages (rooms, spaces) stay out: they're not
  /// about people. [contacts] tags each one: an invite from someone who
  /// isn't a contact gets the "Not a contact" tag and a Block action.
  static List<ReceivedInvite> receivedInvites(
      Iterable<InviteFacts> invites, Set<String> contacts, String? selfId) {
    final result = <ReceivedInvite>[
      for (final i in invites)
        if (i.isDirect && i.inviterId != selfId)
          ReceivedInvite(i,
              fromContact:
                  i.inviterId != null && contacts.contains(i.inviterId))
    ];
    result.sort(_newestFirst);
    return result;
  }

  /// The DM invites you sent that haven't been answered: one per person
  /// still invited (by you) to a direct message you're in, newest first.
  static List<SentInvite> sentInvites(
      Iterable<DmMembershipFacts> rooms, String? selfId) {
    final result = <SentInvite>[];
    for (final room in rooms) {
      if (!room.selfJoined) continue;
      for (final m in room.members) {
        if (m.userId == selfId) continue;
        if (m.membership != "invite" || m.invitedBy != selfId) continue;
        final others = room.members
            .where((o) => o.userId != selfId && o.userId != m.userId)
            .where((o) => o.membership == "join" || o.membership == "invite")
            .length;
        result.add(SentInvite(room.roomId, m.userId,
            groupName: room.groupName,
            invitedAt: m.at,
            // Nobody else is in or invited: cancelling leaves an empty
            // room, so Cancel also leaves and forgets it.
            leaveOnCancel: others == 0));
      }
    }
    result.sort((a, b) => _compareTimes(a.invitedAt, b.invitedAt));
    return result;
  }

  /// How Cancel takes back a sent invite. Matrix revokes an invite by
  /// kicking the invited user, which needs a higher power level than
  /// theirs. A direct message made with the trusted_private_chat preset
  /// (the SDK's default, as in Element) gives the invitee the creator's
  /// level, so the kick is refused; when nobody else is in the room,
  /// leaving it withdraws the DM instead.
  static CancelPlan cancelPlan(
      {required bool canKick,
      required int ownPowerLevel,
      required int theirPowerLevel,
      required bool leaveOnCancel}) {
    final kick = canKick && theirPowerLevel < ownPowerLevel;
    if (kick) return leaveOnCancel ? CancelPlan.kickAndLeave : CancelPlan.kick;
    return leaveOnCancel ? CancelPlan.leave : CancelPlan.notAllowed;
  }

  static int _newestFirst(ReceivedInvite a, ReceivedInvite b) =>
      _compareTimes(a.facts.invitedAt, b.facts.invitedAt);

  /// Newest first; unknown times last.
  static int _compareTimes(DateTime? a, DateTime? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return b.compareTo(a);
  }

  /// The count on the rail, the People row and the Invites chip: received
  /// invites only. Invites you sent never badge.
  static int badgeCount(List<ReceivedInvite> received) => received.length;

  /// The line under an invite: "Invited you to a direct message · 2h ago".
  static String receivedLine(ReceivedInvite invite, DateTime now) {
    final what = invite.facts.groupName != null
        ? "Invited you to a group DM “${invite.facts.groupName}”"
        : "Invited you to a direct message";
    return _withTime(what, invite.facts.invitedAt, now);
  }

  static String sentLine(SentInvite invite, DateTime now) {
    final what = invite.groupName != null
        ? "You invited them to a group DM “${invite.groupName}”"
        : "You invited them to a DM";
    return _withTime(what, invite.invitedAt, now);
  }

  static String _withTime(String what, DateTime? at, DateTime now) {
    if (at == null) return what;
    return "$what · ${relativeTime(at, now)}";
  }

  /// "just now", "5 min ago", "2h ago", "yesterday", "3 days ago",
  /// "last week", "2 weeks ago", then a date.
  static String relativeTime(DateTime at, DateTime now) {
    final d = now.difference(at);
    if (d.inMinutes < 1) return "just now";
    if (d.inHours < 1) return "${d.inMinutes} min ago";
    if (d.inHours < 24) return "${d.inHours}h ago";
    if (d.inDays < 2) return "yesterday";
    if (d.inDays < 7) return "${d.inDays} days ago";
    if (d.inDays < 14) return "last week";
    if (d.inDays < 35) return "${d.inDays ~/ 7} weeks ago";
    const months = [
      "Jan", "Feb", "Mar", "Apr", "May", "Jun", //
      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
    ];
    final date = "${months[at.month - 1]} ${at.day}";
    return at.year == now.year ? date : "$date, ${at.year}";
  }

  /// Active Now's cards: a card per call with a contact in it, then a card
  /// per online or away contact who isn't in one of those calls. Empty
  /// when nobody is online or in a call, so the panel hides.
  static List<ActiveNowEntry> activeNow(
      List<CallFacts> calls, List<ContactFacts> contacts) {
    final entries = <ActiveNowEntry>[];
    final inCall = <String>{};
    final sortedCalls = List.of(calls)
      ..sort((a, b) => b.participants.length.compareTo(a.participants.length));
    for (final call in sortedCalls) {
      if (call.contactsIn.isEmpty) continue;
      inCall.addAll(call.contactsIn);
      entries.add(ActiveNowEntry(call.contactsIn,
          activity: VoiceActivity(call.roomName, call.roomKey,
              others: call.participants.length - call.contactsIn.length),
          since: call.lastJoined));
    }
    final online = contacts
        .where((c) => showsPresenceDot(c.status) && !inCall.contains(c.userId))
        .toList()
      ..sort((a, b) => compareContacts(
          a.status, a.name, a.userId, b.status, b.name, b.userId));
    for (final c in online) {
      final message = c.statusMessage?.trim();
      entries.add(ActiveNowEntry([c.userId],
          activity: message != null && message.isNotEmpty
              ? StatusActivity(message)
              : PresenceActivity(c.status)));
    }
    return entries;
  }

  /// [entries] with the most recent activity first: a call's latest join,
  /// else a contact's [lastActive] time (by "account|user" key). Entries
  /// without a time keep their order, after the rest. The Overview's Active
  /// Now row uses this.
  static List<ActiveNowEntry> mostRecentFirst(
      List<ActiveNowEntry> entries, DateTime? Function(String key) lastActive) {
    DateTime? timeOf(ActiveNowEntry e) =>
        e.activity is VoiceActivity || e.userIds.isEmpty
            ? e.since
            : lastActive(e.userIds.first);
    final indexed = entries.indexed.toList()
      ..sort((a, b) {
        final byTime = _compareTimes(timeOf(a.$2), timeOf(b.$2));
        return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
      });
    return [for (final (_, e) in indexed) e];
  }

  /// Active Now's title for an entry: "Juni", "Juni and Mossy", "Juni and
  /// 2 others" (others counts everyone else in the call, contacts or not).
  static String activeNowTitle(List<String> names, int othersInCall) {
    if (names.isEmpty) return "";
    final extra = names.length - 1 + othersInCall;
    if (extra == 0) return names.first;
    if (names.length == 2 && othersInCall == 0) {
      return "${names[0]} and ${names[1]}";
    }
    return "${names.first} and $extra ${extra == 1 ? "other" : "others"}";
  }
}

/// What the SDK tells us about one invite you received.
class InviteFacts {
  const InviteFacts(
      {required this.clientKey,
      required this.roomId,
      required this.inviterId,
      required this.isDirect,
      this.groupName,
      this.invitedAt});
  final String clientKey;
  final String roomId;
  final String? inviterId;
  final bool isDirect;

  /// The room's own name, set for group DMs ("Plant swap").
  final String? groupName;
  final DateTime? invitedAt;
}

class ReceivedInvite {
  const ReceivedInvite(this.facts, {required this.fromContact});
  final InviteFacts facts;
  final bool fromContact;

  /// The "Not a contact" tag and the Block action.
  bool get notAContact => !fromContact;
}

/// One member of a direct message you're in.
class MemberFacts {
  const MemberFacts(this.userId, this.membership, {this.invitedBy, this.at});
  final String userId;

  /// "join", "invite", "leave", "ban" or "knock".
  final String membership;

  /// Who sent the invite, for "invite".
  final String? invitedBy;
  final DateTime? at;
}

/// One direct message you're in, with its members.
class DmMembershipFacts {
  const DmMembershipFacts(
      {required this.roomId,
      required this.selfJoined,
      required this.members,
      this.groupName});
  final String roomId;
  final bool selfJoined;
  final List<MemberFacts> members;
  final String? groupName;
}

class SentInvite {
  const SentInvite(this.roomId, this.userId,
      {this.groupName, this.invitedAt, required this.leaveOnCancel});
  final String roomId;
  final String userId;
  final String? groupName;
  final DateTime? invitedAt;

  /// Cancel also leaves and forgets the room, since nobody else is in it
  /// ([PeopleModel.cancelPlan]).
  final bool leaveOnCancel;
}

/// What Cancel does to a sent invite ([PeopleModel.cancelPlan]).
enum CancelPlan {
  /// Kick them; others stay in the room.
  kick,

  /// Kick them, then leave and forget the room nobody else is in.
  kickAndLeave,

  /// They can't be kicked (same power level); leave and forget the room.
  leave,

  /// They can't be kicked and others are still in the room.
  notAllowed,
}

/// A call (MatrixRTC session) in a room you share.
class CallFacts {
  const CallFacts(
      {required this.roomKey,
      required this.roomName,
      required this.participants,
      required this.contactsIn,
      this.lastJoined});
  final String roomKey;
  final String roomName;

  /// When the contact who joined last joined, if known.
  final DateTime? lastJoined;

  /// Everyone in the call but you.
  final List<String> participants;
  final List<String> contactsIn;
}

class ContactFacts {
  const ContactFacts(this.userId, this.name, this.status, {this.statusMessage});
  final String userId;
  final String name;
  final UserPresenceStatus status;
  final String? statusMessage;
}

/// One Active Now card: who, and what they're doing.
class ActiveNowEntry {
  const ActiveNowEntry(this.userIds, {required this.activity, this.since});
  final List<String> userIds;
  final ContactActivity activity;

  /// For a call, when the contact who joined last joined. Null when
  /// unknown and for contacts (see [PeopleModel.mostRecentFirst]).
  final DateTime? since;
}

/// What a contact is doing, for Active Now's activity line. Rich presence
/// (an app or game someone shares, opt-in) would be one more subclass here
/// with its own line; nothing fills it yet.
sealed class ContactActivity {
  const ContactActivity();
}

/// In a call: "In voice · Game Night", with a Join button.
class VoiceActivity extends ContactActivity {
  const VoiceActivity(this.roomName, this.roomKey, {this.others = 0});
  final String roomName;
  final String roomKey;
  final int others;
}

/// Their status message.
class StatusActivity extends ContactActivity {
  const StatusActivity(this.message);
  final String message;
}

/// Online or away, without a status message.
class PresenceActivity extends ContactActivity {
  const PresenceActivity(this.status);
  final UserPresenceStatus status;
}
