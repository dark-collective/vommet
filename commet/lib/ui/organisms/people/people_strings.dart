// Vommet issue 580: the words of the People button and its list.
import 'package:intl/intl.dart';

class PeopleStrings {
  static String get labelPeople => Intl.message("People",
      name: "labelPeople",
      desc:
          "Name of the sidebar button under Home that lists all your direct messages, and the header of that list");

  static String get promptPeopleNewMessage => Intl.message("New message",
      name: "promptPeopleNewMessage",
      desc:
          "Tooltip of the pencil button in the People list that starts a new direct message");

  static String get peopleSearchHint => Intl.message("Find a person",
      name: "peopleSearchHint",
      desc: "Hint in the search field at the top of the People list");

  static String get peopleSearchClear => Intl.message("Clear search",
      name: "peopleSearchClear",
      desc: "Tooltip of the button that empties the People list's search");

  static String peopleInvitesHeader(int count) => Intl.message(
      "Invites — $count",
      args: [count],
      name: "peopleInvitesHeader",
      desc:
          "Header above the direct message invitations in the People list, with how many there are");

  static String peopleDirectMessagesHeader(int count) => Intl.message(
      "Direct messages — $count",
      args: [count],
      name: "peopleDirectMessagesHeader",
      desc:
          "Header above the direct messages in the People list, with how many there are");

  static String get peopleListEmpty =>
      Intl.message("No direct messages yet. Press the pencil to start one.",
          name: "peopleListEmpty",
          desc: "Shown in the People list when you have no direct messages");

  static String peopleSearchNoResults(String query) =>
      Intl.message("No one matches “$query”.",
          args: [query],
          name: "peopleSearchNoResults",
          desc: "Shown in the People list when its search matches no one");

  static String get peopleYesterday => Intl.message("Yesterday",
      name: "peopleYesterday",
      desc:
          "Time of a direct message's last message in the People list, when it was sent yesterday");

  static String get promptPeopleMarkAllRead => Intl.message("Mark all as read",
      name: "promptPeopleMarkAllRead",
      desc:
          "Menu item on the People sidebar button that marks every direct message as read");

  static String get promptHidePeople => Intl.message("Hide this button",
      name: "promptHidePeople",
      desc: "Menu item on the People sidebar button that hides it");

  static String get labelHidePeopleTitle => Intl.message("Hide “People”?",
      name: "labelHidePeopleTitle",
      desc: "Title of the dialog shown when hiding the People sidebar button");

  static String get promptHidePeopleReminder => Intl.message(
      "Your direct messages go back to showing as pictures under Home when they have new messages. You can turn People back on in Settings → Appearance → Add a “People” button.",
      name: "promptHidePeopleReminder",
      desc:
          "Shown when hiding the People sidebar button: what changes, and where to turn it back on");

  static String get promptWhatsPeople => Intl.message("What's People?",
      name: "promptWhatsPeople",
      desc: "Menu item on the People sidebar button that explains what it is");

  static String get labelWhatsPeopleBody => Intl.message(
      "People lists all your direct messages in one place, newest first, with invitations from people who want to message you at the top. The red number counts the messages you haven't read yet. Home still shows your favourites and direct messages as before.",
      name: "labelWhatsPeopleBody",
      desc: "Explanation shown from the People sidebar button's menu");

  static String get labelShowPeopleInRail => Intl.message(
      "Add a “People” button",
      name: "labelShowPeopleInRail",
      desc:
          "Label of the setting that shows the People button (all direct messages) under Home in the sidebar");

  static String get labelShowPeopleInRailDescription => Intl.message(
      "Adds a People button under Home on the space bar on the far left. It lists all your direct messages, and its red number counts the ones you haven't read. Without it, each direct message with new messages shows as a picture under Home.",
      name: "labelShowPeopleInRailDescription",
      desc:
          "Description of the setting that shows the People button (all direct messages) under Home in the sidebar");
}
