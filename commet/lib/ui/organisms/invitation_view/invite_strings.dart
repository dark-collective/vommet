// Vommet: strings for the invite page, the "Decline and block" sheet and
// Settings › Invitations, ready for translation (Intl.message).
import 'package:intl/intl.dart';

String get invitePageTitle => Intl.message("Invitation",
    name: "invitePageTitle", desc: "Title of the page showing one invitation");

String get inviteMessageRequestTitle => Intl.message("Message request",
    name: "inviteMessageRequestTitle",
    desc: "Title of the page showing an invitation to a direct message");

String inviteRowInvitedYou(String user) => Intl.message("$user invited you",
    args: [user],
    name: "inviteRowInvitedYou",
    desc: "Second line of an invitation in the Home list; user is a Matrix ID");

String inviteRowWantsToMessage(String user) => Intl.message(
    "$user wants to message you",
    args: [user],
    name: "inviteRowWantsToMessage",
    desc:
        "Second line of a direct message invitation in the Home list; user is a Matrix ID");

String get inviteWantsDm =>
    Intl.message("wants to start a direct message with you",
        name: "inviteWantsDm",
        desc: "Under the person's name on a direct message invitation");

String get inviteChipSpace => Intl.message("Space",
    name: "inviteChipSpace", desc: "Chip on an invitation: this is a space");

String inviteChipMembers(int count) => Intl.plural(count,
    one: "$count member",
    other: "$count members",
    args: [count],
    name: "inviteChipMembers",
    desc: "Chip on an invitation: how many people joined the room");

String get inviteChipEncrypted => Intl.message("Encrypted",
    name: "inviteChipEncrypted",
    desc: "Chip on an invitation: the room is end-to-end encrypted");

String get inviteChipNotEncrypted => Intl.message("Not encrypted",
    name: "inviteChipNotEncrypted",
    desc: "Chip on an invitation: the room is not end-to-end encrypted");

String get inviteChipInviteOnly => Intl.message("Invite only",
    name: "inviteChipInviteOnly",
    desc: "Chip on an invitation: people can only join when invited");

String get inviteChipPublic => Intl.message("Public",
    name: "inviteChipPublic",
    desc: "Chip on an invitation: anyone can join the room");

String get inviteChipAskToJoin => Intl.message("Ask to join",
    name: "inviteChipAskToJoin",
    desc: "Chip on an invitation: people can ask to join (knock)");

String get inviteChipSpaceMembers => Intl.message("Space members",
    name: "inviteChipSpaceMembers",
    desc:
        "Chip on an invitation: members of a space can join (restricted join rule)");

String get inviteInvitedBy => Intl.message("Invited by ",
    name: "inviteInvitedBy",
    desc:
        "Before the inviter's name on an invitation (followed by the name, note the space)");

String inviteSharedRooms(int count, String names) => Intl.plural(count,
    one: "You're both in $names",
    other: "You're both in $count rooms: $names",
    args: [count, names],
    name: "inviteSharedRooms",
    desc:
        "Rooms you share with the inviter; names is a comma separated list of room names");

String get inviteNoSharedRooms =>
    Intl.message("You don't share any rooms with them",
        name: "inviteNoSharedRooms",
        desc: "Warning on an invitation from someone you share no rooms with");

String inviteInsideRooms(int count) => Intl.plural(count,
    one: "Inside · $count room",
    other: "Inside · $count rooms",
    args: [count],
    name: "inviteInsideRooms",
    desc: "Header of the list of rooms in a space you're invited to");

String get inviteInside => Intl.message("Inside",
    name: "inviteInside",
    desc:
        "Header of the list of rooms in a space you're invited to, when the server didn't list them all");

String inviteMoreRooms(int count) => Intl.message("+$count more",
    args: [count],
    name: "inviteMoreRooms",
    desc: "Below the first few rooms of a space: how many more there are");

String get inviteNothingShared =>
    Intl.message("Nothing is shared with the room until you accept.",
        name: "inviteNothingShared",
        desc: "Note at the bottom of an invitation");

String get inviteWhatYouKnow => Intl.message("What you know about them",
    name: "inviteWhatYouKnow",
    desc:
        "Header of the facts about the person on a direct message invitation");

String get inviteNeverMessaged => Intl.message("You've never messaged before",
    name: "inviteNeverMessaged",
    desc:
        "On a direct message invitation: you have no other direct chat with this person");

String get inviteHadChatBefore => Intl.message(
    "You've had a direct chat with them before",
    name: "inviteHadChatBefore",
    desc:
        "On a direct message invitation: you had a direct chat with this person that you left");

String get inviteHaveChat => Intl.message(
    "You already have a direct chat with them",
    name: "inviteHaveChat",
    desc:
        "On a direct message invitation: you already have a direct chat with this person");

String get inviteVerified => Intl.message("Verified",
    name: "inviteVerified",
    desc: "On a direct message invitation: you verified this person");

String get inviteNotVerified => Intl.message("Not verified",
    name: "inviteNotVerified",
    desc: "On a direct message invitation: you haven't verified this person");

String get inviteDmHiddenNote => Intl.message(
    "Their messages stay hidden until you accept. They can't see whether you've read this.",
    name: "inviteDmHiddenNote",
    desc: "Note on a direct message invitation");

String get inviteDecline => Intl.message("Decline",
    name: "inviteDecline", desc: "Button: decline an invitation");

String get inviteAccept => Intl.message("Accept",
    name: "inviteAccept", desc: "Button: accept an invitation");

String get inviteJoinSpace => Intl.message("Join space",
    name: "inviteJoinSpace", desc: "Button: accept an invitation to a space");

String get inviteDeclineAndBlockLink => Intl.message("Decline and block…",
    name: "inviteDeclineAndBlockLink",
    desc:
        "Red link under an invitation that opens the decline and block options");

String get inviteDeclineAndBlockTitle => Intl.message("Decline and block",
    name: "inviteDeclineAndBlockTitle",
    desc: "Title of the decline and block options, and its confirm button");

String inviteDeclineAndBlockIntro(String room) => Intl.message(
    "Declines “$room”. Pick what else to stop:",
    args: [room],
    name: "inviteDeclineAndBlockIntro",
    desc: "Intro of the decline and block options; room is the room's name");

String inviteBlockUser(String user) => Intl.message("Block $user",
    args: [user],
    name: "inviteBlockUser",
    desc: "Decline and block option; user is a Matrix ID");

String get inviteBlockUserExplain => Intl.message(
    "Their invites, messages and calls are hidden everywhere. Same list as Settings › Invitations › Blocked users.",
    name: "inviteBlockUserExplain",
    desc: "Explains the block person option");

String inviteBlockServer(String server) =>
    Intl.message("Block invites from $server",
        args: [server],
        name: "inviteBlockServer",
        desc: "Decline and block option; server is a server name");

String inviteBlockServerExplain(String server) => Intl.message(
    "Nobody on $server can invite you. Messages in rooms you already share still show.",
    args: [server],
    name: "inviteBlockServerExplain",
    desc: "Explains the block server option");

String get inviteReportRoom => Intl.message("Report this room",
    name: "inviteReportRoom", desc: "Decline and block option");

String inviteReportRoomExplain(String server) =>
    Intl.message("Sends the room to your server's admins ($server).",
        args: [server],
        name: "inviteReportRoomExplain",
        desc: "Explains the report room option; server is your homeserver");

String inviteReportReason(String inviter) =>
    Intl.message("Unwanted invite from $inviter",
        args: [inviter],
        name: "inviteReportReason",
        desc: "Reason sent to the server admins with a room report");

String get inviteCancel => Intl.message("Cancel",
    name: "inviteCancel",
    desc: "Cancel button of the decline and block options");

String get inviteSomethingFailed => Intl.message("Not everything worked",
    name: "inviteSomethingFailed",
    desc: "Title of the dialog when part of decline and block failed");

String get inviteReportFailed => Intl.message(
    "Your server didn't take the report. It can only take reports for rooms someone on it has joined.",
    name: "inviteReportFailed",
    desc: "The room report failed");

String get inviteBlockFailed => Intl.message(
    "Your server didn't accept the block. Try again from Settings › Invitations.",
    name: "inviteBlockFailed",
    desc: "Blocking the person or server failed");

String get inviteDeclineFailed =>
    Intl.message("The invitation couldn't be declined. Try again.",
        name: "inviteDeclineFailed", desc: "Declining failed");

// ------------------------------------------------------------ settings

String get inviteSettingsTab => Intl.message("Invitations",
    name: "inviteSettingsTab", desc: "Label of the Invitations settings page");

String get inviteSettingsWhoCanInvite => Intl.message("Who can invite you",
    name: "inviteSettingsWhoCanInvite",
    desc: "Header of the who can invite you setting");

String get inviteSettingsAnyone => Intl.message("Anyone",
    name: "inviteSettingsAnyone", desc: "Who can invite you: anyone");

String get inviteSettingsAnyoneExplain =>
    Intl.message("Except the people and servers below",
        name: "inviteSettingsAnyoneExplain",
        desc: "Explains who can invite you: anyone");

String get inviteSettingsNobody => Intl.message("Nobody",
    name: "inviteSettingsNobody", desc: "Who can invite you: nobody");

String get inviteSettingsNobodyExplain =>
    Intl.message("Your server turns every invite away",
        name: "inviteSettingsNobodyExplain",
        desc: "Explains who can invite you: nobody");

String get inviteSettingsBlockedServers => Intl.message("Blocked servers",
    name: "inviteSettingsBlockedServers",
    desc: "Header of the blocked servers list");

String get inviteSettingsNoBlockedServers =>
    Intl.message("You haven't blocked any servers.",
        name: "inviteSettingsNoBlockedServers",
        desc: "Empty blocked servers list");

String inviteSettingsGlobExplain(String pattern) =>
    Intl.message("Every server matching $pattern",
        args: [pattern],
        name: "inviteSettingsGlobExplain",
        desc: "Under a blocked server pattern with * or ?");

String get inviteSettingsBlockAServer => Intl.message("Block a server",
    name: "inviteSettingsBlockAServer",
    desc: "Label of the field for blocking a server");

String get inviteSettingsServerHint =>
    Intl.message("example.org or *.example.org",
        name: "inviteSettingsServerHint",
        desc: "Hint in the field for blocking a server");

String get inviteSettingsBlock => Intl.message("Block",
    name: "inviteSettingsBlock", desc: "Button: block the typed server");

String get inviteSettingsUnblock => Intl.message("Unblock",
    name: "inviteSettingsUnblock", desc: "Button: unblock a server");

String get inviteSettingsNotAServer =>
    Intl.message("That doesn't look like a server name.",
        name: "inviteSettingsNotAServer",
        desc: "Error when the typed server name isn't valid");

String get inviteSettingsOwnServer => Intl.message(
    "That's your own server: blocking it would turn away invites from everyone on it.",
    name: "inviteSettingsOwnServer",
    desc: "Error when trying to block your own homeserver");

String get inviteSettingsUpdateFailed =>
    Intl.message("Your server didn't accept the change. Try again.",
        name: "inviteSettingsUpdateFailed",
        desc: "Error when changing the invitation settings failed");

String inviteSettingsFooter(String server) => Intl.message(
    "Enforced by your server ($server): blocked invites never reach any of your apps or devices.",
    args: [server],
    name: "inviteSettingsFooter",
    desc: "Footer of the Invitations settings; server is your homeserver");

String get inviteSettingsListsOff => Intl.message(
    "Another app switched these rules off. Blocking a server switches them back on.",
    name: "inviteSettingsListsOff",
    desc: "Shown when another app disabled the invite rule lists");

String get inviteSettingsPointer =>
    Intl.message("Blocked servers and people: Settings › Invitations",
        name: "inviteSettingsPointer",
        desc: "Pointer under the Allow invitations switch in Chat Privacy");
