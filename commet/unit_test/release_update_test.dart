import 'dart:convert';

import 'package:commet/utils/minisign.dart';
import 'package:commet/utils/release_update.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// A throwaway key (not the release key), signed with minisign's format and
// checked with the minisign tool.
const testKey = "RWTJIzLVySMrGENMlPnzhp78k53MDkAJtANajEo+ntQzOX/YqmMOMMZc";
const sums = "abc123  vommet-linux-x64-testing-2099-01-01.AppImage\n";
const sig = "untrusted comment: signature from the Vommet release key\n"
    "RUTJIzLVySMrGEpHzFsjRB/ztZjx7DmdUhocQOwpC13IrYgyvMiZPgHxfIQ8CSoVL6jrmre+tK/hR+6HDDmTjjVP2zGSANLkXwk=\n"
    "trusted comment: timestamp:1792693626\tfile:SHA256SUMS\trelease:testing-2099-01-01\n"
    "vEf3i+uO4oF83QDJ/+fM2MmLinkfF3cwPHskJmRWGkbIx9+/b2oLwbSwpZ2yKOSWXECuIxCQrp1Ezrvka3LWCA==\n";

const tag = "testing-2099-01-01";
final assets = [
  for (final name in [
    "SHA256SUMS",
    "SHA256SUMS.minisig",
    "vommet-testing-arm64.apk",
    "vommet-testing-x86_64.flatpak",
    "vommet-testing-windows-x64.zip",
    "vommet-linux-x64-$tag.AppImage",
    "vommet-linux-x64-$tag.AppImage.sha256",
    "vommet-linux-arm64-$tag.AppImage",
    "vommet-linux-x64-$tag.deb",
    "vommet-linux-arm64-$tag.rpm",
    "vommet-linux-x64-$tag.tar.gz",
    "vommet-linux-arm64-$tag.tar.gz",
    "vommet-macos-universal-$tag.zip",
    "vommet-nix-$tag.tar.gz",
  ])
    {
      "name": name,
      "size": 10,
      "browser_download_url": "https://nether.codes/dl/$name"
    }
];

String? pick(InstallKind kind, String arch) =>
    ReleaseUpdate.assetFor(kind, arch, assets)?["name"] as String?;

InstallKind detectLinux(
        {Map<String, String> env = const {},
        String exe = "/home/a/vommet/vommet",
        bool dpkg = false}) =>
    ReleaseUpdate.detect(
        android: false,
        ios: false,
        mac: false,
        windows: false,
        linux: true,
        environment: env,
        executable: exe,
        exists: (path) => dpkg && path == "/var/lib/dpkg/info/vommet.list");

void main() {
  group("minisign", () {
    test("a good signature verifies", () async {
      expect(
          await Minisign.verify(
              publicKey: testKey, message: utf8.encode(sums), signature: sig),
          isTrue);
    });

    test("a changed file doesn't", () async {
      expect(
          await Minisign.verify(
              publicKey: testKey,
              message: utf8.encode(sums.replaceFirst("abc", "abd")),
              signature: sig),
          isFalse);
    });

    test("a changed trusted comment doesn't", () async {
      expect(
          await Minisign.verify(
              publicKey: testKey,
              message: utf8.encode(sums),
              signature: sig.replaceFirst("2099", "2098")),
          isFalse);
    });

    test("another key doesn't, and garbage is just false", () async {
      expect(
          await Minisign.verify(
              publicKey: ReleaseUpdate.publicKey,
              message: utf8.encode(sums),
              signature: sig),
          isFalse);
      expect(
          await Minisign.verify(
              publicKey: testKey, message: utf8.encode(sums), signature: "x"),
          isFalse);
      expect(
          await Minisign.verify(
              publicKey: "not base64!",
              message: utf8.encode(sums),
              signature: sig),
          isFalse);
    });
  });

  test("install kinds", () {
    expect(detectLinux(env: {"FLATPAK_ID": "im.nether.chat"}),
        InstallKind.flatpak);
    expect(detectLinux(env: {"APPIMAGE": "/home/a/Vommet.AppImage"}),
        InstallKind.appImage);
    expect(
        detectLinux(exe: "/nix/store/abc-vommet/bin/vommet"), InstallKind.nix);
    expect(
        detectLinux(exe: "/gnu/store/abc-vommet/bin/vommet"), InstallKind.guix);
    expect(detectLinux(exe: "/opt/vommet/vommet", dpkg: true), InstallKind.deb);
    expect(detectLinux(exe: "/opt/vommet/vommet"), InstallKind.rpm);
    expect(detectLinux(), InstallKind.tarball);
    expect(
        ReleaseUpdate.detect(
            android: true,
            ios: false,
            mac: false,
            windows: false,
            linux: false,
            environment: const {},
            executable: "",
            exists: (_) => false),
        InstallKind.apk);
  });

  test("each kind gets its own file", () {
    expect(pick(InstallKind.apk, "arm64"), "vommet-testing-arm64.apk");
    expect(pick(InstallKind.flatpak, "x64"), "vommet-testing-x86_64.flatpak");
    expect(pick(InstallKind.flatpak, "arm64"), isNull);
    expect(pick(InstallKind.appImage, "x64"), "vommet-linux-x64-$tag.AppImage");
    expect(pick(InstallKind.appImage, "arm64"),
        "vommet-linux-arm64-$tag.AppImage");
    expect(pick(InstallKind.deb, "x64"), "vommet-linux-x64-$tag.deb");
    expect(pick(InstallKind.deb, "arm64"), isNull);
    expect(pick(InstallKind.rpm, "arm64"), "vommet-linux-arm64-$tag.rpm");
    expect(pick(InstallKind.tarball, "x64"), "vommet-linux-x64-$tag.tar.gz");
    expect(pick(InstallKind.macos, "x64"), "vommet-macos-universal-$tag.zip");
    expect(pick(InstallKind.windows, "x64"), "vommet-testing-windows-x64.zip");
    expect(pick(InstallKind.nix, "x64"), isNull);
    expect(pick(InstallKind.web, "x64"), isNull);
  });

  test("what the bar does per kind", () {
    expect(ReleaseUpdate.actionFor(InstallKind.apk), UpdateAction.install);
    expect(ReleaseUpdate.actionFor(InstallKind.deb), UpdateAction.install);
    expect(ReleaseUpdate.actionFor(InstallKind.appImage), UpdateAction.replace);
    expect(ReleaseUpdate.actionFor(InstallKind.windows), UpdateAction.reveal);
    expect(ReleaseUpdate.actionFor(InstallKind.guix), UpdateAction.command);
    expect(ReleaseUpdate.commandFor(InstallKind.guix),
        "guix pull && guix upgrade vommet");
    expect(ReleaseUpdate.actionFor(InstallKind.web), UpdateAction.reload);
    expect(ReleaseUpdate.actionFor(InstallKind.ios), UpdateAction.page);
  });

  test("only signed releases offer the in-app update", () {
    ReleaseUpdate.kindForTest = InstallKind.tarball;
    addTearDown(() => ReleaseUpdate.kindForTest = null);
    expect(ReleaseUpdate.canDownload({"assets": assets}), isTrue);
    expect(
        ReleaseUpdate.canDownload({
          "assets":
              assets.where((a) => a["name"] != "SHA256SUMS.minisig").toList()
        }),
        isFalse);
    ReleaseUpdate.kindForTest = InstallKind.guix;
    expect(ReleaseUpdate.canDownload({"assets": assets}), isFalse);
  });

  test("SHA256SUMS lookup", () {
    final h = "a" * 64;
    final text = "$h  one.apk\n${"B" * 64} *two.zip\n";
    expect(ReleaseUpdate.checksumFor(text, "one.apk"), h);
    expect(ReleaseUpdate.checksumFor(text, "two.zip"), "b" * 64);
    expect(ReleaseUpdate.checksumFor(text, "one"), isNull);
  });

  group("download refuses unsigned releases", () {
    setUp(() => ReleaseUpdate.kindForTest = InstallKind.tarball);
    tearDown(() {
      ReleaseUpdate.kindForTest = null;
      ReleaseUpdate.state.value = UpdateState.idle;
    });

    test("no signature file", () async {
      final client = MockClient((r) async => http.Response("", 404));
      await ReleaseUpdate.download({
        "assets":
            assets.where((a) => a["name"] != "SHA256SUMS.minisig").toList()
      }, client: client);
      expect(ReleaseUpdate.state.value.phase, UpdatePhase.failed);
      expect(ReleaseUpdate.state.value.error, UpdateError.verify);
    });

    test("a signature from another key", () async {
      final client = MockClient((r) async => r.url.path.endsWith(".minisig")
          ? http.Response(sig, 200)
          : http.Response(sums, 200));
      await ReleaseUpdate.download({"assets": assets}, client: client);
      expect(ReleaseUpdate.state.value.phase, UpdatePhase.failed);
      expect(ReleaseUpdate.state.value.error, UpdateError.verify);
    });
  });
}
