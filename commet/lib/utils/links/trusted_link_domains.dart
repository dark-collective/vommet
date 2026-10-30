// Vommet: "Always open links to <domain>" on the Open Link prompt (Vommet
// issue 503), like Discord's "trust this domain". Only the exact host is
// trusted (www.example.com doesn't cover example.com or docs.example.com),
// and the list stays on this device. Settings › Privacy lists and removes
// them (TrustedLinkDomainsPanel).

import 'package:commet/main.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class TrustedLinkDomains {
  /// The domain a web link would be trusted as: its host, lower-cased, or
  /// null for anything but an http(s) link with a host.
  static String? domainOf(Uri uri) {
    if (uri.scheme != "http" && uri.scheme != "https") return null;
    final host = uri.host.toLowerCase();
    return host.isEmpty ? null : host;
  }

  static List<String> get domains => preferences.trustedLinkDomains.value;

  static bool isTrusted(Uri uri) {
    final domain = domainOf(uri);
    return domain != null && domains.contains(domain);
  }

  static Future<void> trust(Uri uri) async {
    final domain = domainOf(uri);
    if (domain == null || domains.contains(domain)) return;
    await preferences.trustedLinkDomains.set([...domains, domain]);
  }

  static Future<void> remove(String domain) async {
    await preferences.trustedLinkDomains
        .set(domains.where((d) => d != domain).toList());
  }
}

/// The switch row on the Open Link prompt. Off each time the prompt opens;
/// [onChanged] reports the current state.
class TrustLinkDomainSwitch extends StatefulWidget {
  const TrustLinkDomainSwitch(
      {required this.domain, required this.onChanged, super.key});

  final String domain;
  final void Function(bool value) onChanged;

  @override
  State<TrustLinkDomainSwitch> createState() => _TrustLinkDomainSwitchState();
}

class _TrustLinkDomainSwitchState extends State<TrustLinkDomainSwitch> {
  bool trust = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
              child: tiamat.Text.labelLow(linkAlwaysOpenDomain(widget.domain))),
          tiamat.Switch(
            state: trust,
            onChanged: (value) {
              setState(() => trust = value);
              widget.onChanged(value);
            },
          ),
        ],
      ),
    );
  }
}

/// Settings › Privacy: the trusted domains, each with a remove button.
/// Hidden while the list is empty.
class TrustedLinkDomainsPanel extends StatelessWidget {
  const TrustedLinkDomainsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: preferences.trustedLinkDomains.onChanged,
      builder: (context, _) {
        final domains = TrustedLinkDomains.domains;
        if (domains.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: tiamat.Panel(
            header: trustedLinkDomainsHeader,
            mode: tiamat.TileType.surfaceContainerLow,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                tiamat.Text.labelLow(trustedLinkDomainsDescription),
                const SizedBox(height: 8),
                for (final domain in domains)
                  Row(children: [
                    Expanded(child: SelectableText(domain)),
                    IconButton(
                      tooltip: trustedLinkDomainsRemove,
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => TrustedLinkDomains.remove(domain),
                    ),
                  ]),
              ],
            ),
          ),
        );
      },
    );
  }
}

String linkAlwaysOpenDomain(String domain) => Intl.message(
    "Always open links to $domain",
    name: "linkAlwaysOpenDomain",
    args: [domain],
    desc:
        "Switch on the Open Link prompt that trusts the link's domain, so later links to it open without asking",
    examples: const {"domain": "docs.example.com"});

String get trustedLinkDomainsHeader => Intl.message("Trusted link domains",
    name: "trustedLinkDomainsHeader",
    desc: "Header of the privacy settings panel listing trusted link domains");

String get trustedLinkDomainsDescription => Intl.message(
    "Links to these sites open without asking. Only the exact domain is trusted.",
    name: "trustedLinkDomainsDescription",
    desc: "Explanation above the list of trusted link domains");

String get trustedLinkDomainsRemove => Intl.message("Remove",
    name: "trustedLinkDomainsRemove",
    desc: "Tooltip of the button that stops trusting a link domain");
