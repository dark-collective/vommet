import 'package:commet/config/room_layout_options.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/layout/pane_widths.dart';
import 'package:commet/ui/layout/responsive_desktop.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_main_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Vommet issue 539: the Telegram-style chat list's own resizable width.
void main() {
  final pane = PaneWidths.chatList;

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await pane.reset();
  });

  test("starts at 400 and is resizable without Resize panels", () async {
    await resizablePanels.set(false);
    expect(pane.value, 400);
    expect(pane.resizable, isTrue);
    expect(PaneWidths.left.resizable, isFalse);
    pane.drag(100);
    expect(pane.effective, 500);
  });

  test("keeps the dragged width in its own preference", () async {
    pane.drag(120);
    await pane.save();
    expect(preferences.chatListPaneWidth.value, 520);
    expect(preferences.leftPaneWidth.value,
        preferences.leftPaneWidth.defaultValue);
    final reloaded = PaneWidth(preferences.chatListPaneWidth,
        min: pane.min, max: pane.max, resizableWhen: () => true);
    expect(reloaded.value, 520);
  });

  test("double-click reset returns to the default", () async {
    pane.drag(-90);
    await pane.save();
    await pane.reset();
    expect(pane.value, 400);
    expect(preferences.chatListPaneWidth.value, 400);
  });

  test("never squeezes the chat under its minimum width", () {
    pane.drag(1000);
    expect(pane.value, pane.max);
    expect(UnifiedMainPageDesktop.paneWidthFor(2000, 0), pane.max);
    const window = 900.0;
    expect(UnifiedMainPageDesktop.paneWidthFor(window, 0),
        window - ResponsiveDesktop.minChatWidth);
    expect(UnifiedMainPageDesktop.paneWidthFor(window, 72),
        window - 72 - ResponsiveDesktop.minChatWidth);
    // Too narrow for both: the list keeps its narrowest width.
    expect(UnifiedMainPageDesktop.paneWidthFor(500, 0), pane.min);
  });
}
