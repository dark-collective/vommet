// Vommet: lets the user pick the STUN server calls fall back to when their
// homeserver provides none (Vommet issue 563). One STUN URL only: no TURN
// credentials and no list of servers.
import 'package:commet/main.dart';
import 'package:commet/utils/stun_server_url.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class StunFallbackServerField extends StatefulWidget {
  const StunFallbackServerField({super.key});

  @override
  State<StunFallbackServerField> createState() =>
      _StunFallbackServerFieldState();
}

class _StunFallbackServerFieldState extends State<StunFallbackServerField> {
  late final TextEditingController _controller =
      TextEditingController(text: preferences.fallbackTurnServer.value);
  final FocusNode _focus = FocusNode();

  String get labelStunFallbackServer => Intl.message("Fallback STUN server",
      name: "labelStunFallbackServer",
      desc: "Label of the text field for the STUN server calls fall back to");

  String get labelStunFallbackServerInvalid => Intl.message(
      "Enter a STUN address starting with stun: or stuns:, for example stun:stun.example.org:3478",
      name: "labelStunFallbackServerInvalid",
      desc: "Error shown under the fallback STUN server field");

  String labelStunFallbackServerReset(String server) =>
      Intl.message("Reset to $server",
          args: [server],
          name: "labelStunFallbackServerReset",
          desc: "Tooltip of the button that resets the fallback STUN server");

  String get defaultServer => preferences.fallbackTurnServer.defaultValue;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void dispose() {
    _commit();
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _commit() {
    final text = _controller.text.trim();
    if (!isValidStunServerUrl(text)) return;
    if (text != preferences.fallbackTurnServer.value) {
      preferences.fallbackTurnServer.set(text);
    }
  }

  void _reset() {
    _controller.text = defaultServer;
    _commit();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final text = _controller.text;
    final valid = isValidStunServerUrl(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        tiamat.Text.labelEmphasised(labelStunFallbackServer),
        const SizedBox(height: 4),
        TextField(
          controller: _controller,
          focusNode: _focus,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            hintText: defaultServer,
            errorText: valid ? null : labelStunFallbackServerInvalid,
            errorMaxLines: 3,
            suffixIcon: text.trim() == defaultServer
                ? null
                : IconButton(
                    tooltip: labelStunFallbackServerReset(defaultServer),
                    icon: const Icon(Icons.restart_alt),
                    onPressed: _reset,
                  ),
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _commit(),
          onTapOutside: (_) => _focus.unfocus(),
        ),
      ],
    );
  }
}
