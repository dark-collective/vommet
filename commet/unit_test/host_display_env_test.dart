import 'package:commet/utils/system_processes_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads the host display from systemctl show-environment', () {
    const out = "HOME=/home/fox\nDISPLAY=:1\nLANG=en_US.UTF-8\n"
        "WAYLAND_DISPLAY=wayland-1\nXDG_RUNTIME_DIR=/run/user/1001\n";
    expect(SystemProcessesUtils.parseDisplayEnvironment(out),
        {"DISPLAY": ":1", "WAYLAND_DISPLAY": "wayland-1"});
  });

  test('skips missing, empty and systemd-quoted values', () {
    expect(SystemProcessesUtils.parseDisplayEnvironment("HOME=/root\n"), {});
    expect(SystemProcessesUtils.parseDisplayEnvironment("DISPLAY=\n"), {});
    expect(
        SystemProcessesUtils.parseDisplayEnvironment(
            "WAYLAND_DISPLAY=\$'wayland\\x201'\n"),
        {});
  });

  test('uses the Wayland socket only when there is exactly one', () {
    expect(
        SystemProcessesUtils.singleWaylandSocket(
            "bus\npipewire-0\nwayland-1\nwayland-1.lock\n"),
        "wayland-1");
    expect(SystemProcessesUtils.singleWaylandSocket("wayland-0\nwayland-1\n"),
        isNull);
    expect(SystemProcessesUtils.singleWaylandSocket("bus\n"), isNull);
  });
}
