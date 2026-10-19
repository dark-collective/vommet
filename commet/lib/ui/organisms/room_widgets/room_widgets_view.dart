import 'dart:async';

import 'package:commet/client/components/widgets/widget_component.dart';
import 'package:commet/client/components/widgets/widget_send_types.dart';
import 'package:commet/client/matrix/matrix_role.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/room.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/adaptive_context_menu.dart';
import 'package:commet/ui/atoms/scaled_safe_area.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/organisms/room_widgets/add_widget_picker.dart';
import 'package:commet/ui/organisms/room_widgets/widget_catalog.dart';
import 'package:commet/utils/links/link_utils.dart';
import 'package:commet/client/matrix/components/widgets/widget_call_guard.dart';
import 'package:flutter/material.dart';

import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:intl/intl.dart';

class RoomWidgetsView extends StatefulWidget {
  const RoomWidgetsView(this.room, {super.key});
  final Room room;

  @override
  State<RoomWidgetsView> createState() => _RoomWidgetsViewState();
}

class _RoomWidgetsViewState extends State<RoomWidgetsView> {
  late List<UserWidgetInfo> widgets;
  late List<WidgetHostType> additionalHostTypes;

  StreamSubscription? sub;
  StreamSubscription? sessionsSub;

  /// Vommet: widgets (by namespace) whose events the user can't send.
  Map<String, bool> viewOnly = {};

  @override
  void initState() {
    var client = widget.room.client;

    var widgetComponent = client.getComponent<WidgetComponent>();

    widgets = visibleWidgets(widgetComponent!);

    sub = widgetComponent.onWidgetsChanged.listen(onWidgetsChanged);

    additionalHostTypes = widgetComponent
        .supportedHostTypes()
        .where((i) => i != widgetComponent.defaultHostType)
        .toList();

    // Vommet: catalog icons for widgets without an avatar of their own.
    WidgetCatalog.load().then((_) {
      if (mounted) setState(() {});
      checkViewOnly();
    });
    // A widget that opens tells us what it sends.
    sessionsSub = WidgetComponent.currentSessions.onListUpdated.listen((_) {
      checkViewOnly();
    });

    super.initState();
  }

  @override
  void dispose() {
    sub?.cancel();
    sessionsSub?.cancel();
    super.dispose();
  }

  void onWidgetsChanged(void event) {
    setState(() {
      var client = widget.room.client;
      var widgetComponent = client.getComponent<WidgetComponent>();
      widgets = visibleWidgets(widgetComponent!);
    });
    checkViewOnly();
  }

  /// Vommet: marks widgets that send events the user's power level can't.
  Future<void> checkViewOnly() async {
    final room = widget.room;
    final result = <String, bool>{};
    for (final data in widgets) {
      final sends = await WidgetSendTypes.known(
          room.client.identifier, data.namespace,
          declared: WidgetCatalog.match(data.url)?.sends ?? const []);
      result[data.namespace] =
          sends.isNotEmpty && !WidgetSendTypes.canSendAll(room, sends);
    }
    if (mounted) setState(() => viewOnly = result);
  }

  /// Vommet (issue 444): a voice room is already a call, so call widgets
  /// (Element Call, Jitsi) are left out there.
  List<UserWidgetInfo> visibleWidgets(WidgetComponent component) {
    final all = component.getWidgets(widget.room);
    if (!WidgetCallGuard.isVoiceRoom(widget.room)) return all;
    return all.where((w) => !WidgetCallGuard.isCallWidgetType(w.type)).toList();
  }

  String hostTypeToLabel(WidgetHostType type) {
    return switch (type) {
      WidgetHostType.embedded => "Open embedded",
      WidgetHostType.childProcess => "Open in new window",
      WidgetHostType.remoteHttpClient => "Open on another device",
      WidgetHostType.externalBrowser => "Open in browser",
      WidgetHostType.androidActivity => "Open in new activity",
    };
  }

  IconData hostTypeToIcon(WidgetHostType type) {
    return switch (type) {
      WidgetHostType.embedded => Icons.widgets_rounded,
      WidgetHostType.childProcess => Icons.open_in_new,
      WidgetHostType.remoteHttpClient => Icons.qr_code_rounded,
      WidgetHostType.externalBrowser => Icons.open_in_browser,
      WidgetHostType.androidActivity => Icons.widgets_rounded,
    };
  }

  /// Vommet: the power level adding a widget needs, or null when unknown.
  int? get addWidgetLevel {
    final room = widget.room;
    if (room is MatrixRoom) {
      return room.matrixRoom
          .powerForChangingStateEvent("im.vector.modular.widgets");
    }
    return null;
  }

  /// "Moderator or higher" for the standard levels, else the number.
  static String levelName(int level) => switch (level) {
        50 || 100 || 150 => roomWidgetsRoleOrHigher(MatrixRole(level).name),
        _ => roomWidgetsPowerLevelOrHigher(level),
      };

  /// Vommet: adding a widget changes room state, so it needs that power level.
  bool get canAddWidgets {
    final room = widget.room;
    if (room is MatrixRoom) {
      return room.matrixRoom.canChangeStateEvent("im.vector.modular.widgets");
    }
    return true;
  }

  void onAddTapped() {
    if (canAddWidgets) {
      AddWidgetPicker.show(context, widget.room);
    } else {
      AdaptiveDialog.show(context,
          title: roomWidgetsAddDialogTitle,
          builder: (_) => SizedBox(
                width: 400,
                child: tiamat.Text.label(addWidgetLevel == null
                    ? roomWidgetsAddNotAllowed
                    : roomWidgetsAddNeedsLevel(
                        levelName(addWidgetLevel!).toLowerCase(),
                        addWidgetLevel!)),
              ));
    }
  }

  List<tiamat.ContextMenuItem> menuFor(UserWidgetInfo data) => [
        for (var i in additionalHostTypes)
          tiamat.ContextMenuItem(
            text: hostTypeToLabel(i),
            icon: hostTypeToIcon(i),
            onPressed: () {
              WidgetComponent.runWidget(widget.room, context, data, type: i);
            },
          ),
        tiamat.ContextMenuItem(
          text: "Clear Permissions",
          icon: Icons.delete,
          color: ColorScheme.of(context).error,
          onPressed: () {
            preferences.clearWidgetSettings(
                widget.room.client.identifier, data.namespace);
          },
        ),
        tiamat.ContextMenuItem(
          text: "Remove Widget",
          icon: Icons.delete_forever,
          color: ColorScheme.of(context).error,
          onPressed: () async {
            if (await AdaptiveDialog.confirmation(context,
                    prompt:
                        "Are you sure you want to remove the widget '${data.name}' from '${widget.room.displayName}'?") ==
                true) {
              var comp = widget.room.client.getComponent<WidgetComponent>();
              comp?.removeWidget(widget: data, room: widget.room);
            }
          },
        )
      ];

  // Vommet: widgets as a grid of tiles, with "Add widget" first (it replaces
  // the "Browse Widgets" link to Commet's widget page).
  @override
  Widget build(BuildContext context) {
    return tiamat.Tile.low(
      child: ScaledSafeArea(
        bottom: true,
        top: false,
        left: false,
        right: false,
        child: RoomWidgetsGrid(
          tiles: [
            WidgetTile.add(
                onTap: onAddTapped,
                enabled: canAddWidgets,
                caption: canAddWidgets || addWidgetLevel == null
                    ? null
                    : levelName(addWidgetLevel!)),
            for (var data in widgets)
              AdaptiveContextMenu(
                items: menuFor(data),
                child: WidgetTile(
                  name: data.name,
                  icon: data.icon.icon,
                  image: data.icon.image,
                  catalog: WidgetCatalog.match(data.url),
                  viewOnly: viewOnly[data.namespace] ?? false,
                  onTap: () =>
                      WidgetComponent.runWidget(widget.room, context, data),
                ),
              ),
          ],
          footer: widgets.isEmpty
              ? RoomWidgetsEmptyHint(
                  onHelp: () => LinkUtils.open(Uri.parse(WidgetCatalog.helpUrl),
                      context: context))
              : null,
        ),
      ),
    );
  }
}

/// The tile grid; sized for the 250 px side panel (2 across) and wider
/// phone panels (3+ across).
class RoomWidgetsGrid extends StatelessWidget {
  const RoomWidgetsGrid({required this.tiles, this.footer, super.key});
  final List<Widget> tiles;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(slivers: [
      SliverPadding(
        padding: const EdgeInsets.all(8),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 130,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.95),
          delegate: SliverChildListDelegate(tiles),
        ),
      ),
      if (footer != null) SliverToBoxAdapter(child: footer),
    ]);
  }
}

class RoomWidgetsEmptyHint extends StatelessWidget {
  const RoomWidgetsEmptyHint({required this.onHelp, super.key});
  final VoidCallback onHelp;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          tiamat.Text.labelLow(roomWidgetsEmpty),
          TextButton(
            style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            onPressed: onHelp,
            child: Text(roomWidgetsWhatAreWidgets),
          ),
        ],
      ),
    );
  }
}

class WidgetTile extends StatelessWidget {
  const WidgetTile(
      {required this.name,
      required this.onTap,
      this.icon,
      this.image,
      this.catalog,
      this.viewOnly = false,
      super.key})
      : isAdd = false,
        enabled = true,
        caption = null;

  WidgetTile.add(
      {required this.onTap, this.enabled = true, this.caption, super.key})
      : name = roomWidgetsAddTile,
        icon = Icons.add_rounded,
        image = null,
        catalog = null,
        viewOnly = false,
        isAdd = true;

  final String name;
  final IconData? icon;
  final ImageProvider? image;

  /// Matching catalog entry: its tinted icon stands in for a missing avatar.
  final CatalogWidget? catalog;
  final VoidCallback onTap;
  final bool isAdd;
  final bool enabled;

  /// Vommet: a line under the name; on a greyed "Add widget", who may add.
  final String? caption;

  /// Vommet: the user's power level can't send what this widget sends, so
  /// they can watch but not play or edit.
  final bool viewOnly;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    final radius = BorderRadius.circular(14);
    final fg = isAdd ? scheme.primary : scheme.onSurface;
    Widget visual = image != null
        ? ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child:
                Image(image: image!, width: 44, height: 44, fit: BoxFit.cover))
        : catalog != null
            ? Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    color: catalog!.tint,
                    borderRadius: BorderRadius.circular(10)),
                alignment: Alignment.center,
                child: catalog!.buildIcon(size: 24))
            : Icon(icon ?? Icons.widgets_rounded,
                size: isAdd ? 34 : 30, color: fg);

    final content = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: 8,
      children: [
        SizedBox(height: 44, child: Center(child: visual)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: fg, fontWeight: isAdd ? FontWeight.w700 : null)),
        ),
        if (caption != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(caption!,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ),
      ],
    );

    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Material(
        color:
            isAdd ? scheme.primary.withAlpha(18) : scheme.surfaceContainerHigh,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: isAdd
              ? CustomPaint(
                  painter: _DashedBorder(scheme.primary.withAlpha(150), radius),
                  child: content)
              : viewOnly
                  ? Stack(children: [
                      Positioned.fill(child: content),
                      Positioned(
                          top: 6, left: 6, child: _ViewOnlyBadge(scheme)),
                    ])
                  : content,
        ),
      ),
    );
  }
}

/// Vommet: "View only" on a widget the user can watch but not send with.
class _ViewOnlyBadge extends StatelessWidget {
  const _ViewOnlyBadge(this.scheme);
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: roomWidgetsViewOnlyTooltip,
      child: Container(
        key: const ValueKey("widget-tile-view-only"),
        padding: const EdgeInsets.fromLTRB(5, 2, 6, 2),
        decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, spacing: 3, children: [
          Icon(Icons.visibility_outlined,
              size: 11, color: scheme.onSurfaceVariant),
          Text(roomWidgetsViewOnlyBadge,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(fontSize: 10, color: scheme.onSurfaceVariant)),
        ]),
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  _DashedBorder(this.color, this.radius);
  final Color color;
  final BorderRadius radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final path = Path()
      ..addRRect(radius.toRRect(Offset.zero & size).deflate(1));
    for (final metric in path.computeMetrics()) {
      for (double d = 0; d < metric.length; d += 9) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color;
}

String roomWidgetsRoleOrHigher(String role) => Intl.message("$role or higher",
    args: [role],
    name: "roomWidgetsRoleOrHigher",
    desc:
        "Minimum role needed, e.g. 'Moderator or higher'; role is a role name");

String roomWidgetsPowerLevelOrHigher(int level) =>
    Intl.message("Power level $level or higher",
        args: [level],
        name: "roomWidgetsPowerLevelOrHigher",
        desc: "Minimum power level needed when it is not a standard role");

String get roomWidgetsAddDialogTitle => Intl.message("Add a widget",
    name: "roomWidgetsAddDialogTitle",
    desc: "Title of the dialog explaining the user may not add widgets");

String get roomWidgetsAddNotAllowed => Intl.message(
    "Only moderators and admins can add widgets to this room. Ask one of them if there's a widget you'd like here.",
    name: "roomWidgetsAddNotAllowed",
    desc:
        "Shown when the user lacks the power level to add widgets and the needed level is unknown");

String roomWidgetsAddNeedsLevel(String requirement, int level) => Intl.message(
    "Adding widgets to this room needs $requirement (power level $level). Ask a moderator or admin if there's a widget you'd like here.",
    args: [requirement, level],
    name: "roomWidgetsAddNeedsLevel",
    desc:
        "Shown when the user lacks the power level to add widgets; requirement is e.g. 'moderator or higher' (lower-cased), level is the number");

String get roomWidgetsEmpty => Intl.message(
    "No widgets here yet. Widgets are little apps for this room, like games and whiteboards.",
    name: "roomWidgetsEmpty",
    desc: "Shown in the room widgets pane when the room has no widgets");

String get roomWidgetsWhatAreWidgets => Intl.message("What are widgets?",
    name: "roomWidgetsWhatAreWidgets",
    desc: "Link button that opens help about widgets");

String get roomWidgetsAddTile => Intl.message("Add widget",
    name: "roomWidgetsAddTile",
    desc:
        "Label of the tile that adds a widget, in the room widgets grid (short)");

String get roomWidgetsViewOnlyTooltip =>
    Intl.message("Your role here can't send this widget's moves or edits",
        name: "roomWidgetsViewOnlyTooltip",
        desc: "Tooltip on the 'View only' badge of a widget tile");

String get roomWidgetsViewOnlyBadge => Intl.message("View only",
    name: "roomWidgetsViewOnlyBadge",
    desc:
        "Tiny badge on a widget tile the user can watch but not interact with (very short)");
