// Vommet: the Linux thread probe sorts samples of the UI thread by what it
// was doing (/proc stat state, and the system call it waits in), with fixed
// class names only.

import 'dart:ffi';

import 'package:commet/telemetry/main_spans.dart';
import 'package:commet/telemetry/native_thread_probe_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final x64 = probeSyscalls(Abi.linuxX64);
  final arm64 = probeSyscalls(Abi.linuxArm64);
  String fdKind(int fd) =>
      const {3: "socket", 4: "pipe", 5: "file", 6: "gpu", 7: "dev"}[fd] ??
      "other";
  String classOf(String state, String? syscall, [Map<int, String>? table]) =>
      probeClassOf(
          "1234 (vommet (a) b) $state 1 2 3", syscall, table ?? x64, fdKind);

  test("the state letter is read after the last parenthesis", () {
    expect(probeThreadState("1 (a) b) c) R 2"), "R");
    expect(probeThreadState("garbage"), "?");
  });

  test("running and uninterruptible samples need no system call", () {
    expect(classOf("R", null), "run");
    expect(classOf("D", null), "disk");
    expect(classOf("S", "running"), "run");
  });

  test("sleeping samples are sorted by their system call", () {
    expect(classOf("S", "202 0x7f 0x80 0x0"), "futex");
    expect(classOf("S", "7 0x7f 0x2 0xffffffff"), "poll");
    expect(classOf("S", "232 0x4 0x7f 0x10 0x0"), "poll");
    expect(classOf("S", "230 0x1 0x0 0x7f"), "sleep");
    expect(classOf("S", "74 0x5"), "fsync");
    expect(classOf("S", "999 0x0"), "other");
    expect(classOf("S", "not a number"), "other");
    expect(classOf("S", "98 0x7f 0x80", arm64), "futex");
    expect(classOf("S", "73 0x7f 0x2", arm64), "poll");
  });

  test("reads, writes and ioctls say what they wait on, not which file", () {
    expect(classOf("S", "0 0x3 0x7f 0x1000"), "read_socket");
    expect(classOf("S", "0 0x4 0x7f 0x1000"), "read_pipe");
    expect(classOf("S", "1 0x5 0x7f 0x1000"), "write_file");
    expect(classOf("S", "1 0x7 0x7f 0x1000"), "write_other");
    expect(classOf("S", "16 0x6 0xc0106440"), "ioctl_gpu");
    expect(classOf("S", "16 0x3 0x5401"), "ioctl_other");
    expect(classOf("S", "0"), "read_other");
    expect(classOf("S", "63 0x3 0x7f", arm64), "read_socket");
  });

  test("every class is a valid timer name", () {
    for (final c in probeClasses) {
      expect(MainSpans.nameRe64.hasMatch("Stall_thread_$c"), isTrue);
    }
    for (final kind in {...x64.values, ...arm64.values}) {
      expect(
          probeClasses.contains(kind) ||
              ["read", "write", "ioctl"].contains(kind),
          isTrue,
          reason: kind);
    }
    expect(probeSyscalls(Abi.windowsX64), isEmpty);
  });
}
