import 'package:commet/client/matrix/matrix_mxc_image_provider.dart';
import 'package:commet/client/matrix/power_level_tags.dart';
import 'package:commet/client/role.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' as matrix;

class MatrixRole implements Role {
  int powerLevel;
  late int rank;

  /// Vommet: from the room's MSC3949 power level tags, if one applies; the
  /// member list's role headers draw them.
  @override
  Color? color;
  @override
  String? emoji;
  Uri? iconMxc;

  /// Loads an image icon ([iconMxc]).
  final matrix.Client? client;

  MatrixRole(this.powerLevel,
      {String? nameOverride,
      IconData? iconOverride,
      PowerLevelTags? tags,
      this.client}) {
    if (powerLevel >= 150) {
      name = "Owner";
      rank = 150;
      icon = Icons.local_police;
    } else if (powerLevel >= 100) {
      name = "Admin";
      rank = 100;
      icon = Icons.security;
    } else if (powerLevel >= 50) {
      name = "Moderator";
      rank = 50;
      icon = Icons.shield_rounded;
    } else {
      name = "Member";
      icon = Icons.groups;
      rank = 0;
    }

    // Vommet: a tag names this level (or the nearest lower tagged one). Rank by the
    // tagged level so members group by tag. A tag below the built-in tier
    // (a "Helper" tag at 10 for an admin, or a negative "Muted" level)
    // doesn't replace it.
    final tag = tags?.tagFor(powerLevel);
    if (tag != null && tag.$1 >= rank) {
      rank = tag.$1;
      name = tag.$2.name;
      color = tag.$2.color;
      emoji = tag.$2.emoji;
      iconMxc = tag.$2.iconMxc;
    }

    if (nameOverride != null) {
      name = nameOverride;
    }

    if (iconOverride != null) {
      icon = iconOverride;
    }
  }

  @override
  late String name;

  @override
  bool operator ==(Object other) {
    if (other is! MatrixRole) return false;
    if (identical(this, other)) return true;
    return rank == other.rank;
  }

  @override
  // Vommet: hash what == compares (was powerLevel, so equal roles could
  // hash differently).
  int get hashCode => rank.hashCode;

  @override
  late IconData icon;

  @override
  ImageProvider? get image => iconMxc != null && client != null
      ? MatrixMxcImage(iconMxc!, client!, doFullres: false)
      : null;
}
