import 'package:commet/client/components/scheduled_messages/scheduled_messages.dart';
import 'package:commet/ui/organisms/scheduled_messages/scheduled_messages_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Adds secondary actions to Send while leaving primary activation to the
/// composer. Both menu entries delegate to the existing flows.
class ComposerSendActions extends StatefulWidget {
  const ComposerSendActions({
    super.key,
    required this.canSend,
    required this.onPreview,
    required this.onSchedule,
    required this.scheduleSupported,
    required this.child,
  });

  final bool canSend;
  final VoidCallback? onPreview;
  final VoidCallback? onSchedule;
  final bool Function() scheduleSupported;
  final Widget child;

  @override
  State<ComposerSendActions> createState() => _ComposerSendActionsState();
}

class _ComposerSendActionsState extends State<ComposerSendActions> {
  final MenuController _menu = MenuController();
  FocusNode? _previousFocus;
  LocalHistoryEntry? _backEntry;

  static String get _sendLabel => Intl.message(
        'Send',
        name: 'composerSendButtonLabel',
        desc: 'Accessibility label of the message composer Send button',
      );

  static String get _openLabel => Intl.message(
        'Open send actions',
        name: 'composerOpenSendActions',
        desc: 'Accessibility action that opens the Send button menu',
      );

  static String get _previewLabel => Intl.message(
        'Preview translation',
        name: 'composerPreviewSendTranslation',
        desc: 'Send menu action to preview the translated outgoing message',
      );

  void _openMenu() {
    if (_menu.isOpen) return;
    _previousFocus = FocusManager.instance.primaryFocus;
    _menu.open();
    final route = ModalRoute.of(context);
    if (route != null) {
      final entry = LocalHistoryEntry(
        impliesAppBarDismissal: false,
        onRemove: () {
          if (_backEntry == null) return;
          _backEntry = null;
          _menu.close();
        },
      );
      _backEntry = entry;
      route.addLocalHistoryEntry(entry);
    }
  }

  void _removeBackEntry() {
    final entry = _backEntry;
    _backEntry = null;
    entry?.remove();
  }

  @override
  void dispose() {
    _removeBackEntry();
    super.dispose();
  }

  void _closeMenu() {
    _removeBackEntry();
    final previousFocus = _previousFocus;
    _previousFocus = null;
    if (previousFocus?.context?.mounted == true) {
      previousFocus!.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ScheduledMessages.changed,
      child: widget.child,
      builder: (context, child) {
        final preview = widget.onPreview;
        final schedule = widget.onSchedule != null && widget.scheduleSupported()
            ? widget.onSchedule
            : null;
        final hasActions = preview != null || schedule != null;
        if (!hasActions && _menu.isOpen) {
          // Vommet issue 1092: an empty menu must release its Back entry.
          // Close after layout so route/focus updates cannot interrupt build.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted &&
                widget.onPreview == null &&
                (widget.onSchedule == null || !widget.scheduleSupported())) {
              _menu.close();
            }
          });
        }

        return MenuAnchor(
          controller: _menu,
          consumeOutsideTap: true,
          onClose: _closeMenu,
          menuChildren: [
            if (preview != null)
              MenuItemButton(
                autofocus: true,
                leadingIcon: const Icon(Icons.translate),
                onPressed: preview,
                child: Text(_previewLabel),
              ),
            if (schedule != null)
              MenuItemButton(
                autofocus: preview == null,
                leadingIcon: const Icon(Icons.schedule_send_outlined),
                onPressed: schedule,
                child: Text(ScheduleStrings.scheduleMessageLabel),
              ),
          ],
          child: CallbackShortcuts(
            bindings: {
              if (hasActions) ...{
                const SingleActivator(LogicalKeyboardKey.contextMenu):
                    _openMenu,
                const SingleActivator(LogicalKeyboardKey.f10, shift: true):
                    _openMenu,
              },
            },
            child: Semantics(
              label: _sendLabel,
              button: true,
              customSemanticsActions: hasActions
                  ? {CustomSemanticsAction(label: _openLabel): _openMenu}
                  : null,
              child: GestureDetector(
                excludeFromSemantics: true,
                // A held press should never fall through to a tap-to-send,
                // even when this draft has no available secondary actions.
                onLongPress: !widget.canSend
                    ? null
                    : hasActions
                        ? _openMenu
                        : () {},
                onSecondaryTap: hasActions ? _openMenu : null,
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}
