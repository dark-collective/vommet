import 'package:commet/utils/system_wide_shortcuts/system_wide_shortcuts.dart';
import 'package:dbus/dbus.dart';

// for testing:
// gdbus call --session --dest im.nether.chat --object-path /im/nether/chat/Shortcuts --method im.nether.chat.Shortcuts.unmute
// gdbus call --session --dest im.nether.chat --object-path /im/nether/chat/Shortcuts --method im.nether.chat.Shortcuts.mute

class SystemWideShortcutsLinux {
  static Future<void> init() async {
    await initDbus();
  }

  static Future<void> initDbus() async {
    var client = DBusClient.session();
    await client.requestName('im.nether.chat');
    await client.registerObject(TestObject());
  }
}

class TestObject extends DBusObject {
  TestObject() : super(DBusObjectPath('/im/nether/chat/Shortcuts'));

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    if (interface == 'im.nether.chat.shortcuts' && name == 'Version') {
      return DBusGetPropertyResponse(DBusString('1.0'));
    } else {
      return DBusMethodErrorResponse.unknownProperty();
    }
  }

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    print("Handling dbus message call!");
    print(methodCall.toString());
    if (methodCall.interface != "im.nether.chat.Shortcuts") {
      return DBusMethodErrorResponse.unknownInterface();
    }

    var shortcut = SystemWideShortcuts.shortcuts[methodCall.name];

    if (shortcut != null) {
      shortcut.callback();
    }

    return DBusMethodSuccessResponse();
  }
}
