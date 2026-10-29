import 'package:commet/client/matrix/auth/loopback_redirect_server.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

// Vommet: shown while a sign-in waits on the browser. If the browser never
// shows up (it failed to start, or opened on another screen), the user can
// copy the link into any browser, try again, or cancel, instead of watching
// a spinner. Without a browser sign-in in progress it is just a spinner.
class BrowserSignInPanel extends StatelessWidget {
  const BrowserSignInPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: LoopbackRedirectServer.pending,
      builder: (context, signIn, _) {
        if (signIn == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return ValueListenableBuilder(
          valueListenable: signIn.browserOpened,
          builder: (context, opened, _) =>
              _Panel(signIn: signIn, opened: opened ?? true),
        );
      },
    );
  }
}

class _Panel extends StatefulWidget {
  const _Panel({required this.signIn, required this.opened});
  final BrowserSignIn signIn;
  final bool opened;

  @override
  State<_Panel> createState() => _PanelState();
}

class _PanelState extends State<_Panel> {
  bool copied = false;

  void copy() {
    Clipboard.setData(ClipboardData(text: widget.signIn.url.toString()));
    setState(() => copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final signIn = widget.signIn;
    final opened = widget.opened;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.colorScheme.outline),
          boxShadow: [
            BoxShadow(blurRadius: 50, color: theme.shadowColor.withAlpha(80))
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (opened)
                    const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5))
                  else
                    Icon(Icons.error_outline, color: theme.colorScheme.error),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      opened
                          ? "Finish signing in in your browser"
                          : "Couldn't open your browser",
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                opened
                    ? "Don't see it? Copy this link into any browser:"
                    : "Copy this link into a browser to sign in:",
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SelectableText(
                  signIn.url.toString(),
                  maxLines: 3,
                  style:
                      theme.textTheme.bodySmall?.copyWith(fontFamily: "Code"),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  tiamat.Button.secondary(
                    text: "Cancel",
                    onTap: signIn.cancel,
                  ),
                  tiamat.Button.secondary(
                    text: "Open again",
                    onTap: signIn.reopen,
                  ),
                  tiamat.Button(
                    text: copied ? "Copied" : "Copy link",
                    onTap: copy,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
