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
      // experiment: experiment_manage_space_rooms
      Experiment(
        preference: preferences.experimentManageSpaceRooms,
        title: "Manage a space's rooms",
        description:
            "Adds \"Manage rooms\" to the space menu for people allowed to edit the space: reorder its rooms and subspaces with drag handles, move a room into another subspace, or remove it from the space (the room isn't deleted). Nothing changes until you save. On phones, long-pressing a room on the space's home page then only opens its menu. No restart needed",
        category: ExperimentCategory.layout,
      ), // experiment_manage_space_rooms
    ];
