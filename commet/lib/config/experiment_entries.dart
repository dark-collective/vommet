// Vommet: every experiment on the Experiments page, one entry per feature.
//
// This file is union-merged (.gitattributes), so topics that each add an
// entry don't conflict. To keep the merged file valid Dart:
// * add your imports as separate lines below the existing ones;
// * add your entry directly above the closing `];` line, as one block whose
//   FIRST line is `// experiment: <preference key>` and whose LAST line is
//   `), // <preference key>`. Unique first and last lines stop git from
//   sliding two topics' blocks into each other when it unions them;
// * never change another topic's entry or import in the same commit.
// The page groups entries by category; order within a category is file order.
// Experiments are on by default (opt-out); add `optIn: true` only when one is
// too risky to switch on for everyone.
import 'package:commet/config/experiment_registry.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/organisms/friends/friends_experiment.dart';
import 'package:commet/ui/organisms/new_home/new_home.dart';

List<Experiment> experimentEntries() => [
      // experiment: experiment_enabled_e2ee_element_call
      Experiment(
        preference: preferences.experimentEnableE2eeElementCall,
        title: "Encrypted Element Call",
        description: "Join calls in encrypted rooms (end-to-end encrypted "
            "Element Call media).",
        category: ExperimentCategory.calls,
      ), // experiment_enabled_e2ee_element_call
      // experiment: vommet_experiment_friends_tab
      Experiment(
        preference: experimentFriendsTab,
        title: "Friends tab",
        description:
            "Home gets a Friends tab, like Discord's: the people you add, who's online, and Active Now with the calls a friend is in. Your list is private account data, shared by your devices, and nobody is told when you add them. Suggestions come from your DMs",
        category: ExperimentCategory.layout,
        optIn: true,
        onChanged: onFriendsTabToggled,
      ), // vommet_experiment_friends_tab
      // experiment: vommet_experiment_new_home
      Experiment(
        preference: experimentNewHome,
        title: "New Home",
        description:
            "Home's column gets Overview, People and Rooms above your direct messages, like Discord. Overview shows cards (Recent activity, Favourites, Standalone rooms) that you can reorder, hide and set up from their ⋯ menu; the layout is private account data, shared by your devices. People has your contacts (with Active Now), direct-message invites and blocked people. Rooms lists standalone rooms and your spaces, with a search and filters",
        category: ExperimentCategory.layout,
        optIn: true,
        onChanged: onNewHomeToggled,
      ), // vommet_experiment_new_home
    ];
