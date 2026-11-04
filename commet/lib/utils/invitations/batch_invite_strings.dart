// Vommet issue 842: the batch invitation screens' text, ready for
// translation (Intl.message).
import 'package:intl/intl.dart';

String batchInviteLabelSent(int count) => Intl.plural(count,
    one: "Invitations: $count sent",
    other: "Invitations: $count sent",
    args: [count],
    name: "batchInviteLabelSent",
    desc:
        "Batch invitations: background task title; count is how many invitations the server accepted");

String batchInviteLabelShares(int count) => Intl.plural(count,
    one: "$count history share recorded",
    other: "$count history shares recorded",
    args: [count],
    name: "batchInviteLabelShares",
    desc: "Batch invitations: background task title, after the sent count");

String get batchInviteLabelStopping => Intl.message("stopping",
    name: "batchInviteLabelStopping",
    desc: "Batch invitations: background task title suffix while stopping");

String get batchInviteLabelSending => Intl.message("sending",
    name: "batchInviteLabelSending",
    desc: "Batch invitations: background task title suffix while sending");

String get batchInviteLabelNeedsAttention => Intl.message("needs attention",
    name: "batchInviteLabelNeedsAttention",
    desc:
        "Batch invitations: background task title suffix when some requests failed");

String get batchInviteReasonOtherBatch => Intl.message(
    "Already in another invitation batch",
    name: "batchInviteReasonOtherBatch",
    desc:
        "Batch invitations: why a request waits: another batch is sending it");

String get batchInviteReasonJoinedConfirmed => Intl.message(
    "Already joined; membership confirmed",
    name: "batchInviteReasonJoinedConfirmed",
    desc:
        "Batch invitations: an unconfirmed invitation turned out not to be needed");

String get batchInviteReasonPendingConfirmed => Intl.message(
    "Invite pending; membership confirmed",
    name: "batchInviteReasonPendingConfirmed",
    desc:
        "Batch invitations: an unconfirmed invitation turned out to be pending");

String get batchInviteReasonNotSent => Intl.message("Not sent",
    name: "batchInviteReasonNotSent",
    desc: "Batch invitations: a request stopped before it was sent");

String get batchInviteReasonWaitingParent =>
    Intl.message("Waiting for the parent space invitation",
        name: "batchInviteReasonWaitingParent",
        desc: "Batch invitations: why a room invitation waits");

String get batchInviteReasonNotAllowed =>
    Intl.message("Not allowed. Check membership and invite permissions.",
        name: "batchInviteReasonNotAllowed",
        desc: "Batch invitations: a request the user may not send");

String get batchInviteAlreadyJoined => Intl.message("Already joined",
    name: "batchInviteAlreadyJoined",
    desc: "Batch invitations: the person is already a member");

String get batchInviteInvitePending => Intl.message("Invite pending",
    name: "batchInviteInvitePending",
    desc: "Batch invitations: the person already has an invitation");

String get batchInviteReasonServerBusy =>
    Intl.message("Server busy; waiting to retry",
        name: "batchInviteReasonServerBusy",
        desc: "Batch invitations: rate limited, will retry");

String get batchInviteReasonJoinedOrInvited => Intl.message(
    "Already joined or invited",
    name: "batchInviteReasonJoinedOrInvited",
    desc: "Batch invitations: found to be a member or invited before retrying");

String get batchInviteReasonNoLongerAllowed => Intl.message("No longer allowed",
    name: "batchInviteReasonNoLongerAllowed",
    desc: "Batch invitations: permission was lost before retrying");

String batchInviteReasonCheckFailed(String reason) => Intl.message(
    "Could not check membership. Nothing was sent for this request. $reason",
    args: [reason],
    name: "batchInviteReasonCheckFailed",
    desc:
        "Batch invitations: the membership check failed; reason is a sentence explaining the error");

String get batchInviteAccessBanned => Intl.message("Banned",
    name: "batchInviteAccessBanned",
    desc: "Batch invitations: the person is banned from this room");

String get batchInviteAccessCannotInvite => Intl.message("Cannot invite",
    name: "batchInviteAccessCannotInvite",
    desc: "Batch invitations: the user may not invite people to this room");

String get batchInviteAccessUnchecked => Intl.message(
    "Will invite; membership is checked again before sending",
    name: "batchInviteAccessUnchecked",
    desc:
        "Batch invitations: current membership could not be loaded for this person and room");

String get batchInviteAccessWillInvite => Intl.message("Will invite",
    name: "batchInviteAccessWillInvite",
    desc: "Batch invitations: an invitation will be sent to this room");

String get batchInviteHistoryIncluded => Intl.message("History included",
    name: "batchInviteHistoryIncluded",
    desc:
        "Batch invitations: inviting to this encrypted room shares earlier messages");

String get batchInviteHistoryNewMessagesOnly => Intl.message(
    "New messages only",
    name: "batchInviteHistoryNewMessagesOnly",
    desc:
        "Batch invitations: inviting to this encrypted room shares only new messages");

String get batchInviteHistoryNotEncrypted => Intl.message("Not encrypted",
    name: "batchInviteHistoryNotEncrypted",
    desc: "Batch invitations: the room is not encrypted");

String get batchInviteHistorySpace => Intl.message("Space",
    name: "batchInviteHistorySpace",
    desc: "Batch invitations: this destination is a space");

String get batchInviteHistoryRecorded => Intl.message(
    "History share recorded. Delivery to other devices may finish later.",
    name: "batchInviteHistoryRecorded",
    desc: "Batch invitations: a history share succeeded");

String get batchInviteHistoryNoDevices => Intl.message(
    "History share recorded. This person has no cross-signed sessions yet; devices send it when they join.",
    name: "batchInviteHistoryNoDevices",
    desc:
        "Batch invitations: a history share for someone with no cross-signed sessions");

String get batchInviteHistoryNothingShareable =>
    Intl.message("History share recorded. No messages may be shared yet.",
        name: "batchInviteHistoryNothingShareable",
        desc: "Batch invitations: a history share with nothing to share yet");

String get batchInviteHistoryIdentityChanged => Intl.message(
    "This person’s identity changed. Verify them, then share history again. The history grant is recorded; check Encrypted history settings.",
    name: "batchInviteHistoryIdentityChanged",
    desc: "Batch invitations: a history share blocked by an identity change");

String get batchInviteHistoryNeedsAttention => Intl.message(
    "History share recorded, but delivery needs attention. Check Encrypted history settings or retry this history share.",
    name: "batchInviteHistoryNeedsAttention",
    desc: "Batch invitations: a history share whose delivery failed");

String get batchInviteErrorForbidden => Intl.message(
    "Not allowed. Check permissions or whether this person is banned.",
    name: "batchInviteErrorForbidden",
    desc: "Batch invitations: the server refused the request");

String get batchInviteErrorRateLimited =>
    Intl.message("Server busy. Try again later.",
        name: "batchInviteErrorRateLimited",
        desc: "Batch invitations: the server rate limited the request");

String get batchInviteErrorNotFound =>
    Intl.message("The person or room could not be found.",
        name: "batchInviteErrorNotFound",
        desc: "Batch invitations: the server did not find the person or room");

String get batchInviteErrorServer =>
    Intl.message("The server could not complete this request.",
        name: "batchInviteErrorServer",
        desc: "Batch invitations: another server error");

String get batchInviteErrorTimeout => Intl.message(
    "Could not confirm the result. The server may still be processing it.",
    name: "batchInviteErrorTimeout",
    desc: "Batch invitations: the request timed out");

String get batchInviteErrorUnknown => Intl.message(
    "Could not confirm the result. Check your connection and membership before retrying.",
    name: "batchInviteErrorUnknown",
    desc: "Batch invitations: the request failed without a server answer");

String get batchInviteViewResults => Intl.message("View results",
    name: "batchInviteViewResults",
    desc: "Batch invitations: button on the background task card");

String get batchInviteStopping => Intl.message("Stopping…",
    name: "batchInviteStopping",
    desc:
        "Batch invitations: button on the background task card while stopping");

String get batchInviteStop => Intl.message("Stop",
    name: "batchInviteStop",
    desc: "Batch invitations: button on the background task card");

String get batchInviteDismiss => Intl.message("Dismiss",
    name: "batchInviteDismiss",
    desc: "Batch invitations: button on the background task card");

String get batchInviteStateWaiting => Intl.message("Waiting",
    name: "batchInviteStateWaiting",
    desc: "Batch invitations: state of a request not sent yet");

String get batchInviteStateSending => Intl.message("Sending…",
    name: "batchInviteStateSending",
    desc: "Batch invitations: state of a request being sent");

String get batchInviteStateShareRecorded =>
    Intl.message("History share recorded",
        name: "batchInviteStateShareRecorded",
        desc: "Batch invitations: state of a finished history share");

String get batchInviteStateSent => Intl.message("Sent",
    name: "batchInviteStateSent",
    desc: "Batch invitations: state of an invitation the server accepted");

String get batchInviteStateSkipped => Intl.message("Skipped",
    name: "batchInviteStateSkipped",
    desc:
        "Batch invitations: state of a request that wasn't needed or possible");

String get batchInviteStateFailed => Intl.message("Failed",
    name: "batchInviteStateFailed",
    desc: "Batch invitations: state of a failed request");

String get batchInviteStateUnconfirmed => Intl.message("Could not confirm",
    name: "batchInviteStateUnconfirmed",
    desc: "Batch invitations: state of a request whose result is unknown");

String get batchInviteStateOtherBatch =>
    Intl.message("In another invitation batch",
        name: "batchInviteStateOtherBatch",
        desc: "Batch invitations: state of a request another batch is sending");

String get batchInviteStateWaitingParent => Intl.message(
    "Waiting for parent space",
    name: "batchInviteStateWaitingParent",
    desc:
        "Batch invitations: state of a room invitation waiting for the space invitation");

String get batchInviteRetryUnconfirmedTitle =>
    Intl.message("Retry unconfirmed invitations?",
        name: "batchInviteRetryUnconfirmedTitle",
        desc: "Batch invitations: confirmation dialog title");

String get batchInviteRetryUnconfirmedBody => Intl.message(
    "The server may still be processing these requests. Membership will be checked again, but retrying could repeat an invitation if the original request is still being processed. Successful invitations will not be resent.",
    name: "batchInviteRetryUnconfirmedBody",
    desc: "Batch invitations: confirmation dialog text");

String get batchInviteCancel => Intl.message("Cancel",
    name: "batchInviteCancel", desc: "Batch invitations: cancel button");

String get batchInviteRetryUnconfirmed => Intl.message("Retry unconfirmed",
    name: "batchInviteRetryUnconfirmed",
    desc: "Batch invitations: confirmation dialog button");

String batchInvitePersonSent(int count) => Intl.plural(count,
    one: "$count invitation sent",
    other: "$count invitations sent",
    args: [count],
    name: "batchInvitePersonSent",
    desc: "Batch invitations: under a person in the results");

String batchInviteNeedAttention(int count) => Intl.plural(count,
    one: "$count needs attention",
    other: "$count need attention",
    args: [count],
    name: "batchInviteNeedAttention",
    desc: "Batch invitations: how many requests failed");

String batchInviteHistoryShareRow(String room) => Intl.message(
    "$room · History share",
    args: [room],
    name: "batchInviteHistoryShareRow",
    desc: "Batch invitations: a history share row; room is the room's name");

String get batchInviteViewRunningTitle => Intl.message("Inviting people",
    name: "batchInviteViewRunningTitle",
    desc: "Batch invitations: results dialog title while sending");

String get batchInviteViewDoneTitle => Intl.message("Invitation results",
    name: "batchInviteViewDoneTitle",
    desc: "Batch invitations: results dialog title when finished");

String batchInviteSummarySent(int count) => Intl.plural(count,
    one: "$count sent",
    other: "$count sent",
    args: [count],
    name: "batchInviteSummarySent",
    desc: "Batch invitations: results summary: invitations sent");

String batchInviteSummarySkipped(int count) => Intl.plural(count,
    one: "$count skipped",
    other: "$count skipped",
    args: [count],
    name: "batchInviteSummarySkipped",
    desc: "Batch invitations: results summary: requests skipped");

String batchInviteSummaryNotSent(int count) => Intl.plural(count,
    one: "$count not sent",
    other: "$count not sent",
    args: [count],
    name: "batchInviteSummaryNotSent",
    desc: "Batch invitations: results summary: requests stopped or waiting");

String get batchInviteSentMeaning => Intl.message(
    "Sent means the server accepted the invitation. People still need to accept it. Earlier-message delivery may finish later.",
    name: "batchInviteSentMeaning",
    desc: "Batch invitations: note under the results");

String get batchInviteContinueInBackground =>
    Intl.message("Continue in background",
        name: "batchInviteContinueInBackground",
        desc: "Batch invitations: button while sending");

String get batchInviteStoppingAfterThis =>
    Intl.message("Stopping after this invite…",
        name: "batchInviteStoppingAfterThis",
        desc: "Batch invitations: button while stopping");

String get batchInviteStopAfterThis => Intl.message("Stop after this invite",
    name: "batchInviteStopAfterThis",
    desc: "Batch invitations: button while sending");

String get batchInviteStopExplainer => Intl.message(
    "Stopping keeps sent invitations. You can resume the rest until you close the app.",
    name: "batchInviteStopExplainer",
    desc:
        "Batch invitations: note under the Stop button; unsent requests are not saved across restarts");

String get batchInviteRetryFailedWithShares => Intl.message(
    "Retry failed invitations and history shares",
    name: "batchInviteRetryFailedWithShares",
    desc: "Batch invitations: retry button when the batch has history shares");

String batchInviteRetryFailed(int count) => Intl.plural(count,
    one: "Retry $count failed invitation",
    other: "Retry $count failed invitations",
    args: [count],
    name: "batchInviteRetryFailed",
    desc: "Batch invitations: retry button");

String get batchInviteResume => Intl.message("Resume unsent invitations",
    name: "batchInviteResume",
    desc: "Batch invitations: button to send stopped requests");

String get batchInviteCheckUnconfirmed =>
    Intl.message("Check unconfirmed invitations",
        name: "batchInviteCheckUnconfirmed",
        desc: "Batch invitations: button to check unknown results");

String get batchInviteRetryUnconfirmedEllipsis => Intl.message(
    "Retry unconfirmed…",
    name: "batchInviteRetryUnconfirmedEllipsis",
    desc:
        "Batch invitations: button that asks before retrying unknown results");

String get batchInviteDone => Intl.message("Done",
    name: "batchInviteDone",
    desc: "Batch invitations: button closing the results");

String get batchInviteSearchError =>
    Intl.message("Could not search. Check your connection and try again.",
        name: "batchInviteSearchError",
        desc: "Batch invitations: people search failed");

String get batchInviteLoadError => Intl.message(
    "Could not load rooms. Your selected people are still here. Retry, or explicitly choose Space only.",
    name: "batchInviteLoadError",
    desc: "Batch invitations: loading the space's rooms failed");

String get batchInviteReviewError => Intl.message(
    "Could not check current membership. Nothing has been sent. Try again.",
    name: "batchInviteReviewError",
    desc: "Batch invitations: the review step failed");

String get batchInviteSearchPlaceholder =>
    Intl.message("Search name or Matrix ID",
        name: "batchInviteSearchPlaceholder",
        desc: "Batch invitations: people search field placeholder");

String batchInviteSelectedCount(int count) => Intl.plural(count,
    one: "$count selected",
    other: "$count selected",
    args: [count],
    name: "batchInviteSelectedCount",
    desc: "Batch invitations: how many people are selected");

String batchInviteRemovePerson(String name) => Intl.message("Remove $name",
    args: [name],
    name: "batchInviteRemovePerson",
    desc:
        "Batch invitations: tooltip to unselect a person; name is their name");

String get batchInviteRetrySearch => Intl.message("Retry search",
    name: "batchInviteRetrySearch",
    desc: "Batch invitations: button after a failed search");

String get batchInviteExactIdHint => Intl.message(
    "You can still select this exact Matrix ID. Check it before inviting.",
    name: "batchInviteExactIdHint",
    desc: "Batch invitations: after a failed search for a full Matrix ID");

String get batchInviteNoResults => Intl.message(
    "No matching people. Enter a full Matrix ID to add someone directly.",
    name: "batchInviteNoResults",
    desc: "Batch invitations: search found nobody");

String get batchInviteRecommended => Intl.message("Recommended",
    name: "batchInviteRecommended",
    desc: "Batch invitations: heading over suggested people");

String get batchInviteRetryLoad => Intl.message("Retry loading rooms",
    name: "batchInviteRetryLoad",
    desc: "Batch invitations: button after rooms failed to load");

String get batchInviteSpaceOnly => Intl.message("Space only",
    name: "batchInviteSpaceOnly",
    desc: "Batch invitations: button: invite to the space without its rooms");

String get batchInviteSubspace => Intl.message("Subspace",
    name: "batchInviteSubspace",
    desc: "Batch invitations: in place of a hidden subspace path");

String batchInviteInvitationCount(int count) => Intl.plural(count,
    one: "$count invitation",
    other: "$count invitations",
    args: [count],
    name: "batchInviteInvitationCount",
    desc: "Batch invitations: how many invitations will be sent");

String get batchInviteRoomsIntro => Intl.message(
    "Choose rooms once for everyone. Existing memberships and pending invitations are skipped per person.",
    name: "batchInviteRoomsIntro",
    desc: "Batch invitations: intro of the room picker");

String batchInviteSpaceInvitationCount(int count) => Intl.plural(count,
    one: "$count new space invitation",
    other: "$count new space invitations",
    args: [count],
    name: "batchInviteSpaceInvitationCount",
    desc: "Batch invitations: how many people get a space invitation");

String get batchInviteAllAvailable => Intl.message("All available",
    name: "batchInviteAllAvailable",
    desc: "Batch invitations: button: tick every room that can be chosen");

String get batchInviteTruncatedPicker => Intl.message(
    "Only the first 5,000 destinations are shown. Other rooms are not included.",
    name: "batchInviteTruncatedPicker",
    desc: "Batch invitations: the room list was cut off");

String get batchInviteSpaceDoesNotJoin => Intl.message(
    "Space membership does not automatically join people to its rooms.",
    name: "batchInviteSpaceDoesNotJoin",
    desc: "Batch invitations: note under the room picker");

String batchInvitePeopleCount(int count) => Intl.plural(count,
    one: "$count person",
    other: "$count people",
    args: [count],
    name: "batchInvitePeopleCount",
    desc:
        "Batch invitations: how many people are selected, on the review step");

String get batchInviteWhatTheyReceive => Intl.message("What they will receive",
    name: "batchInviteWhatTheyReceive",
    desc: "Batch invitations: review step heading");

String get batchInviteShareEarlier => Intl.message("Share earlier messages",
    name: "batchInviteShareEarlier",
    desc: "Batch invitations: tick box on the review step");

String get batchInviteShareEarlierHint => Intl.message(
    "Applies to everyone selected. Turn off to share only new messages.",
    name: "batchInviteShareEarlierHint",
    desc: "Batch invitations: under the Share earlier messages tick box");

String get batchInviteSpaceHistoryExplainer => Intl.message(
    "Rooms marked History included share earlier messages permitted by their history-sharing policy. New messages only rooms do not share earlier messages. Unencrypted rooms follow their server history setting.",
    name: "batchInviteSpaceHistoryExplainer",
    desc: "Batch invitations: history note on the review step for a space");

String get batchInviteUnencryptedExplainer => Intl.message(
    "In unencrypted rooms, the server shows earlier messages as each room’s history setting allows.",
    name: "batchInviteUnencryptedExplainer",
    desc: "Batch invitations: history note for unencrypted rooms");

String batchInviteFirstContact(String names) => Intl.message(
    "First contact: $names. Check the Matrix IDs before inviting.",
    args: [names],
    name: "batchInviteFirstContact",
    desc:
        "Batch invitations: warning about people never contacted before; names is a list of names");

String batchInviteFirstContactRedacted(String names) => Intl.message(
    "First contact: $names. Check the selected identities before inviting.",
    args: [names],
    name: "batchInviteFirstContactRedacted",
    desc:
        "Batch invitations: warning about people never contacted before, when names are hidden; names is a list of hidden names");

String batchInviteNotToSpace(String names) => Intl.message(
    "You can’t invite $names to the space itself. They are invited to the chosen rooms only.",
    args: [names],
    name: "batchInviteNotToSpace",
    desc:
        "Batch invitations: warning on the review step; names is a list of names");

String get batchInviteDetailsByPerson => Intl.message("Details by person",
    name: "batchInviteDetailsByPerson",
    desc: "Batch invitations: review step section title");

String get batchInviteDetailsByPersonHint =>
    Intl.message("Destinations and skipped invitations",
        name: "batchInviteDetailsByPersonHint",
        desc: "Batch invitations: review step section subtitle");

String get batchInviteShareExisting =>
    Intl.message("Also share earlier messages with existing members",
        name: "batchInviteShareExisting",
        desc: "Batch invitations: tick box on the review step");

String batchInviteShareExistingHint(String pairs) => Intl.message(
    "Optional: $pairs. No new invitations for these memberships. Only shareable messages are included. Stopping later cannot take back history already shared.",
    args: [pairs],
    name: "batchInviteShareExistingHint",
    desc:
        "Batch invitations: under the tick box; pairs is a list of room and person pairs");

String batchInviteGrantPair(String room, String name) => Intl.message(
    "$room with $name",
    args: [room, name],
    name: "batchInviteGrantPair",
    desc:
        "Batch invitations: one history share; room is a room name, name a person's name");

String batchInviteShareCount(int count) => Intl.plural(count,
    one:
        "$count separate history share. Delivery may finish later; check Encrypted history settings if needed.",
    other:
        "$count separate history shares. Delivery may finish later; check Encrypted history settings if needed.",
    args: [count],
    name: "batchInviteShareCount",
    desc: "Batch invitations: how many history shares will be recorded");

String get batchInviteTruncatedReview => Intl.message(
    "Other rooms beyond the loaded 5,000 destinations are not included.",
    name: "batchInviteTruncatedReview",
    desc: "Batch invitations: the room list was cut off");

String get batchInviteChoosePeople => Intl.message("Choose people",
    name: "batchInviteChoosePeople", desc: "Batch invitations: step title");

String get batchInviteChooseRooms => Intl.message("Choose rooms",
    name: "batchInviteChooseRooms", desc: "Batch invitations: step title");

String get batchInviteReviewInvitations => Intl.message("Review invitations",
    name: "batchInviteReviewInvitations",
    desc: "Batch invitations: step title and button");

String batchInviteStepOf(String place, int step, int steps) => Intl.message(
    "$place · $step of $steps",
    args: [place, step, steps],
    name: "batchInviteStepOf",
    desc:
        "Batch invitations: under the step title; place is the room or space name");

String batchInviteTooMany(int max) => Intl.message(
    "Choose fewer rooms or people. A batch can send up to $max invitations and history shares.",
    args: [max],
    name: "batchInviteTooMany",
    desc: "Batch invitations: too many requests chosen; max is the limit");

String get batchInviteNextChooseRooms => Intl.message("Next: choose rooms",
    name: "batchInviteNextChooseRooms", desc: "Batch invitations: button");

String get batchInviteReviewHistory => Intl.message("Review history sharing",
    name: "batchInviteReviewHistory",
    desc: "Batch invitations: button when only history shares are chosen");

String batchInviteReviewCount(int count) => Intl.plural(count,
    one: "Review $count invitation",
    other: "Review $count invitations",
    args: [count],
    name: "batchInviteReviewCount",
    desc: "Batch invitations: button");

String get batchInviteShareHistory => Intl.message("Share history",
    name: "batchInviteShareHistory",
    desc: "Batch invitations: send button when only history shares are chosen");

String batchInviteSendCount(int count) => Intl.plural(count,
    one: "Send $count invitation",
    other: "Send $count invitations",
    args: [count],
    name: "batchInviteSendCount",
    desc: "Batch invitations: send button");

String get batchInviteBack => Intl.message("Back",
    name: "batchInviteBack", desc: "Batch invitations: button");
