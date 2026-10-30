import 'package:commet/config/app_font.dart';
import 'package:commet/config/chat_text_look.dart';
import 'package:commet/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  test("a chat without a look uses the defaults", () {
    final look = ChatTextLooks.of("client:!room:example.org");
    expect(look.isDefault, isTrue);
    expect(look.fontFamily, isNull);
  });

  test("each chat keeps its own look, on this device", () async {
    const a = "client:!a:example.org";
    const b = "client:!b:example.org";
    await ChatTextLooks.set(
        a,
        const ChatTextLook(
            color: Color(0xFF1E88E5), fontId: "lexend", scale: 1.2));
    final look = ChatTextLooks.of(a);
    expect(look.color!.toARGB32(), 0xFF1E88E5);
    expect(look.fontFamily, AppFont.bundledById("lexend")!.family);
    expect(look.scale, 1.2);
    expect(ChatTextLooks.of(b).isDefault, isTrue);

    // Back to the defaults drops the stored entry.
    await ChatTextLooks.set(a, ChatTextLook.none);
    expect(chatTextLooksPreference.value, "{}");
  });

  test("bad stored values fall back", () {
    final look = ChatTextLook.fromJson(
        {"color": "red", "font": "no-such-font", "scale": 9});
    expect(look.color, isNull);
    expect(look.fontId, AppFont.defaultId);
    expect(look.scale, ChatTextLook.maxScale);
    expect(ChatTextLook.fromJson("nonsense").isDefault, isTrue);
  });

  test("the size scales the body text only", () {
    const look = ChatTextLook(scale: 1.5);
    expect(look.apply(const TextStyle(fontSize: 14)).fontSize, 21);
    expect(look.apply(const TextStyle()).fontSize, isNull);
  });

  test("contrast and the nearest readable color", () {
    expect(
        ChatTextLook.contrast(Colors.black, Colors.white), closeTo(21, 0.01));
    const dark = Color(0xFF121212);
    const navy = Color(0xFF1A237E);
    expect(ChatTextLook.contrast(navy, dark),
        lessThan(ChatTextLook.readableContrast));
    final fixed = ChatTextLook.readableNear(navy, dark);
    expect(ChatTextLook.contrast(fixed, dark),
        greaterThanOrEqualTo(ChatTextLook.readableContrast));
    // A readable color stays as it is.
    expect(ChatTextLook.readableNear(Colors.white, dark), Colors.white);
  });
}
