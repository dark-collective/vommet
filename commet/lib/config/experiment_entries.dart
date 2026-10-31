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
import 'package:commet/config/experiment_registry.dart';
import 'package:commet/main.dart';

List<Experiment> experimentEntries() => [
      // experiment: experiment_enabled_e2ee_element_call
      Experiment(
        preference: preferences.experimentEnableE2eeElementCall,
        title: "Encrypted Element Call",
        description: "Join calls in encrypted rooms (end-to-end encrypted "
            "Element Call media).",
        category: ExperimentCategory.calls,
      ), // experiment_enabled_e2ee_element_call
      // experiment: vommet_experiment_banner_layout
      Experiment(
        preference: preferences.experimentBannerLayout,
        title: "Discord-style layout",
        description:
            "Banners shrink to their name bar as you scroll, the member list is split into Online and Offline, and you can drag the room list and member list edges to resize them (double-click an edge to reset). Takes effect when you next open a room",
        category: ExperimentCategory.layout,
      ), // vommet_experiment_banner_layout
      // experiment: vommet_experiment_thread_read_state
      Experiment(
        preference: preferences.experimentThreadReadState,
        title: "Read state per thread",
        description:
            "Reading a room no longer marks its threads read: each thread keeps its own read position (threaded read receipts), and the Threads list marks threads with new replies. A room stays unread until you've read its threads too. Takes effect as you read",
        category: ExperimentCategory.messages,
      ), // vommet_experiment_thread_read_state
    ];
