import 'package:commet/client/matrix/components/widgets/matrix_widget_component.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('picks the first usable IPv4 address for a widget link', () {
    expect(pickLinkIPv4(["2601:547:ca86:8ae0::74b7", "192.168.1.174"]),
        "192.168.1.174");
    expect(pickLinkIPv4(["127.0.0.1", "169.254.3.4", "10.0.0.5"]), "10.0.0.5");
  });

  test('returns null when there is no usable IPv4 address', () {
    expect(pickLinkIPv4(["fe80::1", "::1", "127.0.0.1"]), isNull);
    expect(pickLinkIPv4([]), isNull);
  });
}
