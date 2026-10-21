import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:image/image.dart' as img;

/// One entry of the tray icon's menu. A null [label] is a separator.
class LinuxTrayMenuItem {
  const LinuxTrayMenuItem(this.label, {this.onClicked});

  const LinuxTrayMenuItem.separator()
      : label = null,
        onClicked = null;

  final String? label;
  final void Function()? onClicked;
}

/// An ARGB32 image in the byte order StatusNotifierItem expects (A, R, G, B
/// per pixel, rows top to bottom).
class LinuxTrayPixmap {
  const LinuxTrayPixmap(this.width, this.height, this.argb);

  /// [source] scaled to fit [size]×[size].
  factory LinuxTrayPixmap.fromImage(img.Image source, int size) {
    final scale =
        size / (source.width > source.height ? source.width : source.height);
    final scaled = img
        .copyResize(source,
            width: (source.width * scale).round().clamp(1, size),
            height: (source.height * scale).round().clamp(1, size),
            interpolation: img.Interpolation.average)
        .convert(format: img.Format.uint8, numChannels: 4);
    final argb = <int>[];
    for (final p in scaled) {
      argb
        ..add(p.a.toInt())
        ..add(p.r.toInt())
        ..add(p.g.toInt())
        ..add(p.b.toInt());
    }
    return LinuxTrayPixmap(scaled.width, scaled.height, argb);
  }

  final int width;
  final int height;
  final List<int> argb;
}

/// A tray icon on Linux (Vommet issue 454), over D-Bus with the
/// StatusNotifierItem protocol that KDE Plasma, Waybar, the GNOME AppIndicator
/// extension, XFCE and others host. Pure Dart (package:dbus), so there is no
/// native library to build or bundle.
///
/// The item is registered by object path from the connection's unique name,
/// like libappindicator does, so the Flatpak only needs to talk to
/// `org.kde.StatusNotifierWatcher` and doesn't own any extra bus name. When
/// the watcher goes away (the panel restarts) [available] turns false until a
/// new watcher shows up; the item registers with it again by itself.
class LinuxTray {
  LinuxTray._(this._bus, this._ownsBus, this._item, this._menu);

  static const watcherName = "org.kde.StatusNotifierWatcher";
  static const _watcherInterface = "org.kde.StatusNotifierWatcher";
  static final _watcherPath = DBusObjectPath("/StatusNotifierWatcher");

  final DBusClient _bus;
  final bool _ownsBus;
  final _StatusNotifierItem _item;
  final _DBusMenu _menu;
  StreamSubscription? _ownerChanges;
  StreamSubscription? _hostChanges;

  bool _available = false;

  /// Whether a tray host currently shows the icon (as far as the watcher
  /// knows). Closing to the tray is only safe while this is true.
  bool get available => _available;

  final StreamController<bool> _availableChanged = StreamController.broadcast();

  /// Emits [available] whenever it changes.
  Stream<bool> get onAvailableChanged => _availableChanged.stream;

  /// Puts an icon in the tray. [onActivate] runs on a left click; [menu] is
  /// the right-click menu. [bus] replaces the session bus (tests); it is left
  /// open by [dispose]. Returns null when the session bus can't be reached.
  static Future<LinuxTray?> start({
    required String id,
    required String title,
    required String iconName,
    required List<LinuxTrayPixmap> iconPixmaps,
    required void Function() onActivate,
    required List<LinuxTrayMenuItem> menu,
    DBusClient? bus,
  }) async {
    final client = bus ?? DBusClient.session();
    final menuObject = _DBusMenu(menu);
    final item = _StatusNotifierItem(
      id: id,
      title: title,
      iconName: iconName,
      iconPixmaps: iconPixmaps,
      onActivate: onActivate,
      menuPath: menuObject.path,
    );

    final tray = LinuxTray._(client, bus == null, item, menuObject);
    try {
      await client.registerObject(item);
      await client.registerObject(menuObject);
    } catch (_) {
      if (bus == null) unawaited(client.close());
      return null;
    }

    tray._ownerChanges =
        client.nameOwnerChanged.where((e) => e.name == watcherName).listen((e) {
      if (e.newOwner != null && e.newOwner!.isNotEmpty) {
        tray._register();
      } else {
        tray._setAvailable(false);
      }
    });

    tray._hostChanges = DBusSignalStream(client,
            interface: _watcherInterface,
            name: "StatusNotifierHostRegistered",
            path: _watcherPath)
        .listen((_) => tray._register());

    await tray._register();
    return tray;
  }

  Future<void> _register() async {
    try {
      await _bus.callMethod(
        destination: watcherName,
        path: _watcherPath,
        interface: _watcherInterface,
        name: "RegisterStatusNotifierItem",
        values: [DBusString(_item.path.value)],
        replySignature: DBusSignature(""),
        noAutoStart: true,
      );
      _setAvailable(await _hostRegistered());
    } catch (_) {
      // No watcher (plain GNOME, a bare window manager): nothing shows it.
      _setAvailable(false);
    }
  }

  /// A watcher can run without anything drawing the icons. Watchers that
  /// don't answer are taken at their word that a host exists.
  Future<bool> _hostRegistered() async {
    try {
      final value =
          await DBusRemoteObject(_bus, name: watcherName, path: _watcherPath)
              .getProperty(_watcherInterface, "IsStatusNotifierHostRegistered",
                  signature: DBusSignature("b"));
      return value.asBoolean();
    } catch (_) {
      return true;
    }
  }

  void _setAvailable(bool value) {
    if (value == _available) return;
    _available = value;
    _availableChanged.add(value);
  }

  /// Changes a menu entry's label, e.g. Show/Hide.
  Future<void> setMenuLabel(int index, String label) =>
      _menu.setLabel(index, label);

  /// Removes the icon from the tray.
  Future<void> dispose() async {
    await _ownerChanges?.cancel();
    await _hostChanges?.cancel();
    _setAvailable(false);
    try {
      await _bus.unregisterObject(_item);
      await _bus.unregisterObject(_menu);
    } catch (_) {}
    if (_ownsBus) await _bus.close();
  }
}

/// org.kde.StatusNotifierItem at /StatusNotifierItem.
class _StatusNotifierItem extends DBusObject {
  _StatusNotifierItem({
    required this.id,
    required this.title,
    required this.iconName,
    required this.iconPixmaps,
    required this.onActivate,
    required this.menuPath,
  }) : super(DBusObjectPath("/StatusNotifierItem"));

  static const interface = "org.kde.StatusNotifierItem";

  final String id;
  final String title;
  final String iconName;
  final List<LinuxTrayPixmap> iconPixmaps;
  final void Function() onActivate;
  final DBusObjectPath menuPath;

  DBusValue get _pixmaps => DBusArray(
      DBusSignature("(iiay)"),
      iconPixmaps.map((p) => DBusStruct(
          [DBusInt32(p.width), DBusInt32(p.height), DBusArray.byte(p.argb)])));

  DBusValue get _emptyPixmaps => DBusArray(DBusSignature("(iiay)"));

  Map<String, DBusValue> get _properties => {
        "Category": const DBusString("Communications"),
        "Id": DBusString(id),
        "Title": DBusString(title),
        "Status": const DBusString("Active"),
        "WindowId": const DBusInt32(0),
        "IconName": DBusString(iconName),
        "IconPixmap": _pixmaps,
        "IconThemePath": const DBusString(""),
        "OverlayIconName": const DBusString(""),
        "OverlayIconPixmap": _emptyPixmaps,
        "AttentionIconName": const DBusString(""),
        "AttentionIconPixmap": _emptyPixmaps,
        "AttentionMovieName": const DBusString(""),
        "ToolTip": DBusStruct([
          DBusString(iconName),
          _pixmaps,
          DBusString(title),
          const DBusString(""),
        ]),
        "ItemIsMenu": const DBusBoolean(false),
        "Menu": menuPath,
      };

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    if (interface != _StatusNotifierItem.interface) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    final value = _properties[name];
    if (value == null) return DBusMethodErrorResponse.unknownProperty();
    return DBusGetPropertyResponse(value);
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async {
    if (interface != _StatusNotifierItem.interface) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    return DBusGetAllPropertiesResponse(_properties);
  }

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface != interface) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    switch (methodCall.name) {
      case "Activate":
        onActivate();
        return DBusMethodSuccessResponse();
      case "SecondaryActivate":
      case "ContextMenu":
      case "Scroll":
        // ContextMenu is only sent to items without a Menu; middle click
        // and scrolling do nothing.
        return DBusMethodSuccessResponse();
    }
    return DBusMethodErrorResponse.unknownMethod();
  }
}

/// com.canonical.dbusmenu at /MenuBar: a flat menu under the root item 0;
/// entry i has id i + 1.
class _DBusMenu extends DBusObject {
  _DBusMenu(List<LinuxTrayMenuItem> items)
      : _items = List.of(items),
        super(DBusObjectPath("/MenuBar"));

  static const interface = "com.canonical.dbusmenu";

  final List<LinuxTrayMenuItem> _items;
  int _revision = 1;

  Map<String, DBusValue> _itemProperties(int id) {
    if (id == 0) {
      return {"children-display": const DBusString("submenu")};
    }
    final item = _items[id - 1];
    if (item.label == null) {
      return {"type": const DBusString("separator")};
    }
    return {
      "label": DBusString(item.label!),
      "enabled": const DBusBoolean(true),
      "visible": const DBusBoolean(true),
    };
  }

  bool _exists(int id) => id >= 0 && id <= _items.length;

  DBusStruct _layout(int id, int depth) {
    final children = id == 0 && depth != 0
        ? [for (var i = 1; i <= _items.length; i++) _layout(i, depth - 1)]
        : <DBusValue>[];
    return DBusStruct([
      DBusInt32(id),
      DBusDict.stringVariant(_itemProperties(id)),
      DBusArray.variant(children),
    ]);
  }

  Future<void> setLabel(int index, String label) async {
    if (_items[index].label == label) return;
    _items[index] =
        LinuxTrayMenuItem(label, onClicked: _items[index].onClicked);
    _revision++;
    try {
      await emitSignal(interface, "ItemsPropertiesUpdated", [
        DBusArray(DBusSignature("(ia{sv})"), [
          DBusStruct([
            DBusInt32(index + 1),
            DBusDict.stringVariant({"label": DBusString(label)}),
          ])
        ]),
        DBusArray(DBusSignature("(ias)")),
      ]);
      await emitSignal(
          interface, "LayoutUpdated", [DBusUint32(_revision), DBusInt32(0)]);
    } catch (_) {}
  }

  void _clicked(int id) {
    if (id < 1 || id > _items.length) return;
    _items[id - 1].onClicked?.call();
  }

  Map<String, DBusValue> get _properties => {
        "Version": const DBusUint32(3),
        "TextDirection": const DBusString("ltr"),
        "Status": const DBusString("normal"),
        "IconThemePath": DBusArray.string(const []),
      };

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    if (interface != _DBusMenu.interface) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    final value = _properties[name];
    if (value == null) return DBusMethodErrorResponse.unknownProperty();
    return DBusGetPropertyResponse(value);
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async {
    if (interface != _DBusMenu.interface) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    return DBusGetAllPropertiesResponse(_properties);
  }

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface != interface) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    final args = methodCall.values;
    switch (methodCall.name) {
      case "GetLayout":
        final id = args[0].asInt32();
        if (!_exists(id)) return _unknownId();
        return DBusMethodSuccessResponse(
            [DBusUint32(_revision), _layout(id, args[1].asInt32())]);
      case "GetGroupProperties":
        final ids = args[0].asInt32Array().toList();
        return DBusMethodSuccessResponse([
          DBusArray(DBusSignature("(ia{sv})"), [
            for (final id in ids.isEmpty
                ? List.generate(_items.length + 1, (i) => i)
                : ids.where(_exists))
              DBusStruct(
                  [DBusInt32(id), DBusDict.stringVariant(_itemProperties(id))])
          ])
        ]);
      case "GetProperty":
        final id = args[0].asInt32();
        if (!_exists(id)) return _unknownId();
        final value = _itemProperties(id)[args[1].asString()];
        if (value == null) return DBusMethodErrorResponse.unknownProperty();
        return DBusMethodSuccessResponse([DBusVariant(value)]);
      case "Event":
        if (args[1].asString() == "clicked") _clicked(args[0].asInt32());
        return DBusMethodSuccessResponse();
      case "EventGroup":
        for (final event in args[0].asArray()) {
          final fields = event.asStruct();
          if (fields[1].asString() == "clicked") {
            _clicked(fields[0].asInt32());
          }
        }
        return DBusMethodSuccessResponse([DBusArray.int32(const [])]);
      case "AboutToShow":
        return DBusMethodSuccessResponse([const DBusBoolean(false)]);
      case "AboutToShowGroup":
        return DBusMethodSuccessResponse(
            [DBusArray.int32(const []), DBusArray.int32(const [])]);
    }
    return DBusMethodErrorResponse.unknownMethod();
  }

  DBusMethodErrorResponse _unknownId() =>
      DBusMethodErrorResponse.invalidArgs("Unknown menu item id");
}
