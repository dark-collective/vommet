import 'package:intl/intl.dart';

class ScheduledListStrings {
  static String get chooseAccount => Intl.message("Choose an account",
      name: "scheduledGlobalChooseAccount",
      desc: "Prompt before showing scheduled messages for multiple accounts");
  static String get noAccount => Intl.message("No account selected",
      name: "scheduledGlobalNoAccount",
      desc: "No default account is chosen for the scheduled list");
  static String get signedOut => Intl.message(
      "This account is no longer signed in. Choose an account to continue.",
      name: "scheduledGlobalSignedOut",
      desc: "Scheduled list after logout");
  static String get none =>
      Intl.message("No scheduled messages for this account.",
          name: "scheduledGlobalNone",
          desc: "Empty account-wide delayed events list");
  static String get loading =>
      Intl.message("Checking support and loading pending messages…",
          name: "scheduledGlobalLoading", desc: "Loading delayed events");
  static String get unavailable => Intl.message(
      "Couldn’t load scheduled messages. Check your connection and try again.",
      name: "scheduledGlobalUnavailable",
      desc: "Capability or list request failed");
  static String get retry => Intl.message("Retry",
      name: "scheduledGlobalRetry", desc: "Retry loading delayed events");
  static String get refresh => Intl.message("Refresh",
      name: "scheduledGlobalRefresh",
      desc: "Reload account scheduled messages");
  static String get roomUnavailable => Intl.message("Room unavailable",
      name: "scheduledGlobalRoomUnavailable",
      desc: "Scheduled message in a missing or left room");
  static String get roomUnavailableHelp => Intl.message(
      "This room is unavailable or you are no longer joined. You can still delete this scheduled message.",
      name: "scheduledGlobalRoomUnavailableHelp",
      desc: "Unavailable scheduled room disables send edit and reschedule");
  static String get gone => Intl.message(
      "This message is no longer pending. It may have been sent or deleted.",
      name: "scheduledGlobalGone",
      desc: "Scheduled message disappeared from a fresh server answer");
  static String get draftConflict => Intl.message(
      "This room already has a draft or pending forward. Finish or clear it before editing a scheduled message.",
      name: "scheduledGlobalDraftConflict",
      desc:
          "Do not replace existing draft when editing a scheduled message from Settings");
  static String get scope => Intl.message("All rooms · soonest first",
      name: "scheduledGlobalScope",
      desc: "Account-wide scheduled message sort order");
  static String get noAccounts => Intl.message("No accounts are signed in.",
      name: "scheduledGlobalNoAccounts",
      desc: "Scheduled messages without any account");
}
