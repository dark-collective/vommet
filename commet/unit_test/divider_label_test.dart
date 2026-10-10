// Vommet: the timeline's date divider shows date and time.

import 'package:commet/utils/text_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets("date divider labels", (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));
    final now = DateTime(2026, 10, 9, 18, 0); // a Friday
    String label(DateTime t, {bool relative = true}) =>
        TextUtils.dividerLabel(t, ctx, relative: relative, now: now);

    expect(label(DateTime(2026, 10, 9, 16, 16)), "Today, 4:16 PM");
    expect(label(DateTime(2026, 10, 8, 23, 2)), "Yesterday, 11:02 PM",
        reason: "under 24 hours old but yesterday");
    expect(label(DateTime(2026, 10, 5, 15, 0)), "Monday, 3:00 PM");
    expect(label(DateTime(2026, 9, 2, 15, 0)), "Sep 2, 3:00 PM");
    expect(label(DateTime(2025, 9, 2, 15, 0)), "Sep 2, 2025, 3:00 PM");
    expect(label(DateTime(2026, 10, 9, 16, 16), relative: false),
        "Fri, Oct 9, 4:16 PM");
  });
}
