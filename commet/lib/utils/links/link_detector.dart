import 'package:commet/utils/links/top_level_domains.dart';

/// A web address or e-mail address found in message text.
class DetectedLink {
  /// UTF-16 offsets into the searched text.
  final int start;
  final int end;

  /// What the text says, e.g. `example.com/path`.
  final String text;

  /// Where a tap goes: `http://example.com/path`, `mailto:a@example.com`.
  final Uri uri;

  const DetectedLink(this.start, this.end, this.text, this.uri);

  @override
  String toString() => "DetectedLink($start, $end, $text -> $uri)";
}

/// Vommet: finds links in message text.
///
/// Commet only linked text starting with `http://`, `https://` or `www.`.
/// With [bareDomains] on, it also links what Telegram links: addresses such
/// as `example.com`, `sub.example.com:8080/path?q=1#frag`, bare IPv4
/// addresses and e-mail addresses. This is a port of TDLib's `match_urls`,
/// `fix_url` and `is_email_address` (td/telegram/MessageEntity.cpp, tdlib/td
/// a94b83d67ab4c8397c6245e541b31a4131ea2f79, Boost Software License 1.0):
/// * a bare domain links only when its last label is on Telegram's TLD list
///   ([commonTopLevelDomains]), so `file.txt`, `v1.2.3` and `node.js` stay
///   text while `test.sh` and `notes.md` link (they are real TLDs);
/// * trailing `.:;,('?!` and backtick are dropped from the end of a path,
///   and an unbalanced `)`, `]` or `}` ends it;
/// * text glued to a word character, `/`, `#` or `@` in front is not a link.
///
/// Vommet additions on top of Telegram's rules:
/// * the server part of a Matrix ID or alias (`@alice:example.org`,
///   `#room:example.org`) is not linked;
/// * nothing between backticks is linked (inline code typed as plain text).
///
/// Bare addresses open as `http://` (the browser upgrades to https), like
/// Telegram does. With [bareDomains] off this finds exactly what Commet found.
class LinkDetector {
  static final RegExp _schemeOrWww = RegExp(
    r'(?:(?:https?):\/\/|www\.)(?:\([-A-Z0-9+&@#/%=~_|$?!:,.]*\)|[-A-Z0-9+&@#/%=~_|$?!:,.])*(?:\([-A-Z0-9+&@#/%=~_|$?!:,.]*\)|[A-Z0-9+&@#/%=~_|$])',
    caseSensitive: false,
    dotAll: true,
  );

  static final RegExp _backtickCode = RegExp(r'```[\s\S]*?```|`[^`\n]+`');

  static final RegExp _separator = RegExp(r'\s', unicode: true);
  static final RegExp _wordCharacter = RegExp(r'[\p{L}\p{N}_]', unicode: true);

  static List<DetectedLink> find(String text, {bool bareDomains = true}) {
    final schemeLinks = <DetectedLink>[];
    for (final m in _schemeOrWww.allMatches(text)) {
      final matched = text.substring(m.start, m.end);
      final uri = _parse(matched.toLowerCase().startsWith("www.")
          ? "http://$matched"
          : matched);
      if (uri != null) {
        schemeLinks.add(DetectedLink(m.start, m.end, matched, uri));
      }
    }

    if (!bareDomains || !text.contains('.')) return schemeLinks;

    final code = _backtickCode.allMatches(text).toList();
    final cps = text.runes.toList();
    final offsets = List<int>.filled(cps.length + 1, 0);
    for (var i = 0, o = 0; i < cps.length; i++) {
      offsets[i] = o;
      o += cps[i] > 0xffff ? 2 : 1;
    }
    offsets[cps.length] = text.length;

    // Candidates come in text order, so walk the other lists alongside.
    final bare = <DetectedLink>[];
    var nextScheme = 0;
    var nextCode = 0;
    bool taken(int start, int end) {
      while (nextScheme < schemeLinks.length &&
          schemeLinks[nextScheme].end <= start) {
        nextScheme++;
      }
      if (nextScheme < schemeLinks.length &&
          schemeLinks[nextScheme].start < end) {
        return true;
      }
      return bare.isNotEmpty && bare.last.end > start;
    }

    for (final (s, e) in _matchUrls(cps)) {
      var start = offsets[s];
      var end = offsets[e];
      if (taken(start, end)) continue;
      while (nextCode < code.length && code[nextCode].end <= start) {
        nextCode++;
      }
      if (nextCode < code.length && code[nextCode].start < end) continue;
      if (_isMatrixIdServer(cps, s)) continue;

      var matched = text.substring(start, end);
      Uri? uri;
      if (isEmailAddress(matched)) {
        // TDLib stops the name at the previous candidate, so
        // `first.last+tag@example.org` would link only `+tag@...`; take the
        // whole name.
        var floor = bare.isEmpty ? 0 : bare.last.end;
        if (nextScheme > 0 && schemeLinks[nextScheme - 1].end > floor) {
          floor = schemeLinks[nextScheme - 1].end;
        }
        var nameStart = start;
        while (nameStart > floor &&
            _isEmailNameSymbol(text.codeUnitAt(nameStart - 1))) {
          nameStart--;
        }
        if (nameStart < start &&
            isEmailAddress(text.substring(nameStart, end))) {
          start = nameStart;
          matched = text.substring(nameStart, end);
        }
        uri = _parse("mailto:$matched");
      } else if (matched.toLowerCase().startsWith("mailto:") &&
          isEmailAddress(matched.substring(7))) {
        uri = _parse(matched);
      } else {
        final fixed = _fixUrl(matched);
        if (fixed == null) continue;
        end = start + fixed.length;
        matched = fixed;
        uri = _parse(_hasProtocol(matched) ? matched : "http://$matched");
      }
      if (uri == null) continue;
      bare.add(DetectedLink(start, end, matched, uri));
    }

    if (bare.isEmpty) return schemeLinks;
    return [...schemeLinks, ...bare]
      ..sort((a, b) => a.start.compareTo(b.start));
  }

  static Uri? _parse(String s) {
    try {
      return Uri.parse(s);
    } catch (_) {
      return null;
    }
  }

  static bool _hasProtocol(String s) {
    final l = s.toLowerCase();
    return l.startsWith("http://") ||
        l.startsWith("https://") ||
        l.startsWith("ftp://") ||
        l.startsWith("tonsite://");
  }

  // `@alice:example.org`, `#room:example.org`, `!id:example.org`: the part
  // after the colon is a Matrix server name, not something to open.
  static bool _isMatrixIdServer(List<int> cps, int start) {
    if (start < 2 || cps[start - 1] != 0x3a /* : */) return false;
    var i = start - 2;
    while (i > 0 && !_isSeparator(cps[i - 1])) {
      i--;
    }
    final first = cps[i];
    return first == 0x40 /* @ */ || first == 0x23 /* # */ || first == 0x21;
  }

  static bool _isSeparator(int c) {
    if (c < 0x80) return c == 0x20 || (c >= 0x09 && c <= 0x0d);
    return _separator.hasMatch(String.fromCharCode(c));
  }

  static bool _isWordCharacter(int c) {
    if (c < 0x80) return _isAlphaDigit(c) || c == 0x5f;
    return _wordCharacter.hasMatch(String.fromCharCode(c));
  }

  static bool _isEmailNameSymbol(int c) =>
      _isAlphaDigitUnderscoreMinus(c) || c == 0x2e || c == 0x2b;

  static bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

  static bool _isAlpha(int c) =>
      (c >= 0x41 && c <= 0x5a) || (c >= 0x61 && c <= 0x7a);

  static bool _isAlphaDigit(int c) => _isAlpha(c) || _isDigit(c);

  static bool _isAlphaDigitUnderscoreMinus(int c) =>
      _isAlphaDigit(c) || c == 0x5f || c == 0x2d;

  static bool _isUrlUnicodeSymbol(int c) {
    if (0x2000 <= c && c <= 0x206f) {
      // Zero width non-joiner/joiner and dashes only.
      return c == 0x200c || c == 0x200d || (0x2010 <= c && c <= 0x2015);
    }
    return !_isSeparator(c);
  }

  static bool _isUrlPathSymbol(int c) {
    switch (c) {
      case 0x0a: // \n
      case 0x3c: // <
      case 0x3e: // >
      case 0x22: // "
      case 0xab: // «
      case 0xbb: // »
        return false;
      default:
        return _isUrlUnicodeSymbol(c);
    }
  }

  static bool _isProtocolSymbol(int c) {
    if (c < 0x80) return _isAlphaDigit(c) || c == 0x2b || c == 0x2d;
    return !_isSeparator(c);
  }

  static bool _isUserDataSymbol(int c) {
    switch (c) {
      case 0x0a: // \n
      case 0x2f: // /
      case 0x5b: // [
      case 0x5d: // ]
      case 0x7b: // {
      case 0x7d: // }
      case 0x28: // (
      case 0x29: // )
      case 0x27: // '
      case 0x60: // `
      case 0x3c: // <
      case 0x3e: // >
      case 0x22: // "
      case 0x40: // @
      case 0xab: // «
      case 0xbb: // »
        return false;
      default:
        return _isUrlUnicodeSymbol(c);
    }
  }

  static bool _isDomainSymbol(int c) {
    if (c < 0xc0) {
      return c == 0x2e || _isAlphaDigitUnderscoreMinus(c) || c == 0x7e;
    }
    return _isUrlUnicodeSymbol(c);
  }

  static const String _badPathEndChars = ".:;,('?!`";

  static bool _isBadPathEnd(int c) =>
      c < 0x80 && _badPathEndChars.contains(String.fromCharCode(c));

  /// TDLib `match_urls`: candidate ranges (code point indexes) around dots.
  static List<(int, int)> _matchUrls(List<int> s) {
    final result = <(int, int)>[];
    final end = s.length;
    var begin = 0;

    while (true) {
      var dot = -1;
      for (var i = begin; i < end; i++) {
        if (s[i] == 0x2e) {
          dot = i;
          break;
        }
      }
      if (dot < 0 || dot + 1 == end) break;
      if (s[dot + 1] == 0x20) {
        begin = dot + 2;
        continue;
      }

      var domainBegin = dot;
      while (domainBegin > begin && _isDomainSymbol(s[domainBegin - 1])) {
        domainBegin--;
      }

      var lastAt = -1;
      var domainEnd = dot;
      while (domainEnd < end) {
        final c = s[domainEnd];
        if (c == 0x40) {
          lastAt = domainEnd;
        } else if (!_isDomainSymbol(c)) {
          break;
        }
        domainEnd++;
      }

      if (lastAt != -1) {
        while (domainBegin > begin && _isUserDataSymbol(s[domainBegin - 1])) {
          domainBegin--;
        }
      }

      var urlEnd = domainEnd;
      if (urlEnd < end && s[urlEnd] == 0x3a /* : */) {
        var portEnd = urlEnd + 1;
        while (portEnd < end && _isDigit(s[portEnd])) {
          portEnd++;
        }
        var portBegin = urlEnd + 1;
        while (portBegin < portEnd && s[portBegin] == 0x30) {
          portBegin++;
        }
        if (portBegin != portEnd &&
            portEnd - portBegin <= 5 &&
            int.parse(String.fromCharCodes(s, portBegin, portEnd)) <= 65535) {
          urlEnd = portEnd;
        }
      }

      if (urlEnd < end &&
          (s[urlEnd] == 0x2f || s[urlEnd] == 0x3f || s[urlEnd] == 0x23)) {
        var pathEnd = urlEnd + 1;
        while (pathEnd < end && _isUrlPathSymbol(s[pathEnd])) {
          pathEnd++;
        }
        while (pathEnd > urlEnd + 1 && _isBadPathEnd(s[pathEnd - 1])) {
          pathEnd--;
        }
        if (s[urlEnd] == 0x2f || pathEnd > urlEnd + 1) {
          urlEnd = pathEnd;
        }
      }
      while (urlEnd > dot + 1 && s[urlEnd - 1] == 0x2e) {
        urlEnd--;
      }

      var isBad = false;
      var urlBegin = domainBegin;
      if (urlBegin != begin && s[urlBegin - 1] == 0x40) {
        if (lastAt != -1) isBad = true;
        var userDataBegin = urlBegin - 1;
        while (
            userDataBegin > begin && _isUserDataSymbol(s[userDataBegin - 1])) {
          userDataBegin--;
        }
        if (userDataBegin == urlBegin - 1) isBad = true;
        urlBegin = userDataBegin;
      }

      if (urlBegin != begin) {
        final prefixLength = urlBegin - begin;
        if (prefixLength >= 6 &&
            s[urlBegin - 1] == 0x2f &&
            s[urlBegin - 2] == 0x2f &&
            s[urlBegin - 3] == 0x3a) {
          var protocolBegin = urlBegin - 3;
          while (protocolBegin > begin &&
              _isProtocolSymbol(s[protocolBegin - 1])) {
            protocolBegin--;
          }
          final protocol = String.fromCharCodes(s, protocolBegin, urlBegin - 3)
              .toLowerCase();
          if (protocol.endsWith("http") && protocol != "shttp") {
            urlBegin -= 7;
          } else if (protocol.endsWith("https")) {
            urlBegin -= 8;
          } else if (protocol.endsWith("ftp") &&
              protocol != "tftp" &&
              protocol != "sftp") {
            urlBegin -= 6;
          } else if (protocol.endsWith("tonsite")) {
            urlBegin -= 10;
          } else {
            isBad = true;
          }
        } else {
          final c = s[urlBegin - 1];
          if (_isWordCharacter(c) || c == 0x2f || c == 0x23 || c == 0x40) {
            isBad = true;
          }
        }
      }

      if (!isBad) {
        if (urlEnd > dot + 1) result.add((urlBegin, urlEnd));
        while (urlEnd < end && s[urlEnd] == 0x2e) {
          urlEnd++;
        }
      } else {
        while (s[urlEnd - 1] != 0x2e) {
          urlEnd--;
        }
      }

      if (urlEnd <= dot) urlEnd = dot + 1;
      begin = urlEnd;
    }

    return result;
  }

  /// TDLib `fix_url`: the link text after trimming its path, or null when
  /// it isn't a link (no TLD, a bad label, ...).
  static String? _fixUrl(String full) {
    var str = full;
    final hasProtocol = _hasProtocol(str);
    if (hasProtocol) str = str.substring(str.indexOf(':') + 3);

    var domainEnd = str.length;
    for (final ch in ['/', '?', '#']) {
      final i = str.indexOf(ch);
      if (i >= 0 && i < domainEnd) domainEnd = i;
    }
    var domain = str.substring(0, domainEnd);
    final path = str.substring(domainEnd);

    final at = domain.indexOf('@');
    if (at >= 0) domain = domain.substring(at + 1);
    final colon = domain.lastIndexOf(':');
    if (colon >= 0) domain = domain.substring(0, colon);

    if (domain.toLowerCase() == "teiegram.org") return null;

    final balance = [0, 0, 0];
    var pathPos = 0;
    for (; pathPos < path.length; pathPos++) {
      switch (path[pathPos]) {
        case '(':
          balance[0]++;
        case '[':
          balance[1]++;
        case '{':
          balance[2]++;
        case ')':
          balance[0]--;
        case ']':
          balance[1]--;
        case '}':
          balance[2]--;
      }
      if (balance[0] < 0 || balance[1] < 0 || balance[2] < 0) break;
    }
    while (pathPos > 0 && _badPathEndChars.contains(path[pathPos - 1])) {
      pathPos--;
    }
    final fixed = full.substring(0, full.length - (path.length - pathPos));

    final parts = domain.split('.');
    var hasNonDigit = false;
    var isIpv4 = true;
    for (final part in parts) {
      if (part.isEmpty || part.length >= 64 || part.endsWith('-')) return null;
      if (!RegExp(r'^[0-9]+$').hasMatch(part)) {
        isIpv4 = false;
        hasNonDigit = true;
      }
      if (isIpv4) {
        if (part.length > 3) isIpv4 = false;
        if (part.length == 3 && int.parse(part) > 255) isIpv4 = false;
        if (part.startsWith('0') && part.length >= 2) isIpv4 = false;
      }
    }
    if (parts.length == 1) return null;
    if (isIpv4 && parts.length == 4) return fixed;
    if (!hasNonDigit) return null;

    final tld = parts.last;
    if (tld.runes.length <= 1) return null;

    if (tld.startsWith("xn--")) {
      if (tld.length <= 5) return null;
      if (!tld.substring(4).codeUnits.every(_isAlphaDigit)) return null;
    } else {
      if (tld.contains('_') || tld.contains('-')) return null;
      if (!hasProtocol && !_isCommonTld(tld)) return null;
    }

    if (parts[parts.length - 2].contains('_')) return null;

    return fixed;
  }

  /// TDLib `is_common_tld`: `COM` and `com` count, `Com` doesn't (so a
  /// sentence ending without a space before a capitalised word isn't a link).
  static bool _isCommonTld(String tld) {
    final lower = tld.toLowerCase();
    if (lower != tld) {
      final rest = tld.runes.skip(1).toList();
      final lowerRest = lower.runes.skip(1).toList();
      if (rest.length == lowerRest.length &&
          List.generate(rest.length, (i) => rest[i] == lowerRest[i])
              .every((same) => same)) {
        return false;
      }
    }
    return commonTopLevelDomains.contains(lower);
  }

  /// TDLib `is_email_address`.
  static bool isEmailAddress(String str) {
    final at = str.indexOf('@');
    if (at < 0) return false;
    final userdata = str.substring(0, at);
    final domain = str.substring(at + 1);
    if (domain.isEmpty) return false;

    var prev = 0;
    var userdataPartCount = 0;
    for (var i = 0; i < userdata.length; i++) {
      final c = userdata.codeUnitAt(i);
      if (c == 0x2e || c == 0x2b) {
        if (i - prev >= 27) return false;
        userdataPartCount++;
        prev = i + 1;
      } else if (!_isAlphaDigitUnderscoreMinus(c)) {
        return false;
      }
    }
    userdataPartCount++;
    if (userdataPartCount >= 12) return false;
    final lastPartLength = userdata.length - prev;
    if (lastPartLength == 0 || lastPartLength >= 36) return false;

    final parts = domain.split('.');
    if (parts.length <= 1 || parts.length > 7) return false;
    final last = parts.removeLast();
    if (last.length <= 1 || last.length >= 9) return false;
    if (!last.codeUnits.every(_isAlpha)) return false;
    for (final part in parts) {
      if (part.isEmpty || part.length >= 31) return false;
      if (!part.codeUnits.every(_isAlphaDigitUnderscoreMinus)) return false;
      if (!_isAlphaDigit(part.codeUnitAt(0))) return false;
      if (!_isAlphaDigit(part.codeUnitAt(part.length - 1))) return false;
    }
    return true;
  }
}
