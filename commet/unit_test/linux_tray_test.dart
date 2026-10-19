import 'dart:io';

import 'package:commet/utils/tray/linux_tray.dart';
import 'package:dbus/dbus.dart';
import 'package:image/image.dart' as img;
import 'package:test/test.dart';

/// A tray host's StatusNotifierWatcher, as KDE Plasma or Waybar runs it.
class _Watcher extends DBusObject {
  _Watcher() : super(DBusObjectPath("/StatusNotifierWatcher"));

  final registered = <String>[];
  final senders = <String?>[];
  bool hostRegistered = true;

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.name == "RegisterStatusNotifierItem") {
      registered.add(methodCall.values[0].asString());
      senders.add(methodCall.sender);
      return DBusMethodSuccessResponse();
    }
    return DBusMethodErrorResponse.unknownMethod();
  }

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    if (name == "IsStatusNotifierHostRegistered") {
      return DBusGetPropertyResponse(DBusBoolean(hostRegistered));
    }
    return DBusMethodErrorResponse.unknownProperty();
  }
}

void main() {
  late Directory dir;
  late DBusServer server;
  late DBusClient appBus;
  late DBusClient hostBus;
  late DBusAddress address;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync("vommet-tray-test");
    server = DBusServer();
    address = await server.listenAddress(DBusAddress.unix(dir: dir));
    appBus = DBusClient(address);
    hostBus = DBusClient(address);
  });

  tearDown(() async {
    await appBus.close();
    await hostBus.close();
    await server.close();
    dir.deleteSync(recursive: true);
  });

  Future<_Watcher> startWatcher(DBusClient bus) async {
    final watcher = _Watcher();
    await bus.registerObject(watcher);
    await bus.requestName(LinuxTray.watcherName);
    return watcher;
  }

  var activations = 0;
  var hides = 0;
  var quits = 0;

  Future<LinuxTray> startTray() async {
    activations = 0;
    hides = 0;
    quits = 0;
    final tray = await LinuxTray.start(
      id: "im.nether.chat",
      title: "Vommet",
      iconName: "",
      iconPixmaps: [
        LinuxTrayPixmap(1, 1, [255, 1, 2, 3])
      ],
      onActivate: () => activations++,
      menu: [
        LinuxTrayMenuItem("Hide Vommet", onClicked: () => hides++),
        const LinuxTrayMenuItem.separator(),
        LinuxTrayMenuItem("Quit Vommet", onClicked: () => quits++),
      ],
      bus: appBus,
    );
    return tray!;
  }

  DBusRemoteObject item() => DBusRemoteObject(hostBus,
      name: appBus.uniqueName, path: DBusObjectPath("/StatusNotifierItem"));

  DBusRemoteObject menu() => DBusRemoteObject(hostBus,
      name: appBus.uniqueName, path: DBusObjectPath("/MenuBar"));

  Future<void> settle() => Future.delayed(const Duration(milliseconds: 100));

  test("registers its object path with the watcher", () async {
    final watcher = await startWatcher(hostBus);
    final tray = await startTray();
    expect(watcher.registered, ["/StatusNotifierItem"]);
    expect(watcher.senders, [appBus.uniqueName]);
    expect(tray.available, isTrue);
    await tray.dispose();
  });

  test("without a watcher nothing shows the icon", () async {
    final tray = await startTray();
    expect(tray.available, isFalse);
    await tray.dispose();
  });

  test("a watcher with no host doesn't count as a tray", () async {
    final watcher = await startWatcher(hostBus)
      ..hostRegistered = false;
    final tray = await startTray();
    expect(watcher.registered, hasLength(1));
    expect(tray.available, isFalse);
    await tray.dispose();
  });

  test("registers again when a watcher starts later, and notices it leave",
      () async {
    final tray = await startTray();
    expect(tray.available, isFalse);

    final panel = DBusClient(address);
    final watcher = await startWatcher(panel);
    await settle();
    expect(watcher.registered, ["/StatusNotifierItem"]);
    expect(tray.available, isTrue);

    await panel.close();
    await settle();
    expect(tray.available, isFalse);
    await tray.dispose();
  });

  test("exposes the item's properties and activates on a click", () async {
    await startWatcher(hostBus);
    final tray = await startTray();

    final props = await item().getAllProperties("org.kde.StatusNotifierItem");
    expect(props["Id"]!.asString(), "im.nether.chat");
    expect(props["Title"]!.asString(), "Vommet");
    expect(props["Status"]!.asString(), "Active");
    expect(props["Menu"]!.asObjectPath().value, "/MenuBar");
    expect(props["ItemIsMenu"]!.asBoolean(), isFalse);
    final pixmap = props["IconPixmap"]!.asArray().single.asStruct();
    expect(pixmap[0].asInt32(), 1);
    expect(pixmap[2].asByteArray().toList(), [255, 1, 2, 3]);

    await item().callMethod("org.kde.StatusNotifierItem", "Activate",
        [const DBusInt32(10), const DBusInt32(20)],
        replySignature: DBusSignature(""));
    expect(activations, 1);
    await tray.dispose();
  });

  test("the menu lists its entries and runs the clicked one", () async {
    await startWatcher(hostBus);
    final tray = await startTray();

    final reply = await menu().callMethod("com.canonical.dbusmenu", "GetLayout",
        [const DBusInt32(0), const DBusInt32(-1), DBusArray.string([])],
        replySignature: DBusSignature("u(ia{sv}av)"));
    final root = reply.values[1].asStruct();
    expect(root[0].asInt32(), 0);
    final children =
        root[2].asArray().map((c) => c.asVariant().asStruct()).toList();
    expect(children.map((c) => c[0].asInt32()), [1, 2, 3]);
    final labels = children
        .map((c) => c[1].asStringVariantDict()["label"]?.asString())
        .toList();
    expect(labels, ["Hide Vommet", null, "Quit Vommet"]);
    expect(
        children[1][1].asStringVariantDict()["type"]!.asString(), "separator");

    await menu().callMethod(
        "com.canonical.dbusmenu",
        "Event",
        [
          const DBusInt32(3),
          const DBusString("clicked"),
          DBusVariant(const DBusInt32(0)),
          const DBusUint32(0)
        ],
        replySignature: DBusSignature(""));
    expect(quits, 1);
    expect(hides, 0);

    final version =
        await menu().getProperty("com.canonical.dbusmenu", "Version");
    expect(version.asUint32(), 3);
    await tray.dispose();
  });

  test("relabelling an entry shows in the next layout", () async {
    await startWatcher(hostBus);
    final tray = await startTray();
    await tray.setMenuLabel(0, "Show Vommet");

    final reply = await menu().callMethod("com.canonical.dbusmenu",
        "GetProperty", [const DBusInt32(1), const DBusString("label")],
        replySignature: DBusSignature("v"));
    expect(reply.values[0].asVariant().asString(), "Show Vommet");
    await tray.dispose();
  });

  test("pixmaps are ARGB in network order and fit the size", () {
    final source = img.Image(width: 4, height: 2, numChannels: 4);
    img.fill(source, color: img.ColorRgba8(10, 20, 30, 255));
    final pixmap = LinuxTrayPixmap.fromImage(source, 2);
    expect(pixmap.width, 2);
    expect(pixmap.height, 1);
    expect(pixmap.argb, [255, 10, 20, 30, 255, 10, 20, 30]);
  });
}
