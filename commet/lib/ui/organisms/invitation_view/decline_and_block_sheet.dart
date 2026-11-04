import 'package:commet/config/preferences/bool_preference.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/organisms/invitation_view/invite_strings.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: what to do besides declining. Each tick is remembered for the
/// next time (block the person starts ticked).
class DeclineAndBlockChoice {
  const DeclineAndBlockChoice(
      {required this.blockUser,
      required this.blockServer,
      required this.reportRoom});
  final bool blockUser;
  final bool blockServer;
  final bool reportRoom;
}

final BoolPreference _rememberBlockUser =
    BoolPreference("vommet_invite_decline_block_user", defaultValue: true);
final BoolPreference _rememberBlockServer =
    BoolPreference("vommet_invite_decline_block_server", defaultValue: false);
final BoolPreference _rememberReportRoom =
    BoolPreference("vommet_invite_decline_report_room", defaultValue: false);

/// Vommet: the "Decline and block…" options. Returns null on Cancel.
class DeclineAndBlockSheet extends StatefulWidget {
  const DeclineAndBlockSheet(
      {required this.roomName,
      required this.inviterId,
      required this.inviterServer,
      required this.ownServer,
      super.key});

  final String roomName;

  /// Null when the invite doesn't say who sent it: no "Block" option then.
  final String? inviterId;

  /// Null (option hidden) when unknown or your own server.
  final String? inviterServer;
  final String ownServer;

  static Future<DeclineAndBlockChoice?> show(BuildContext context,
      {required String roomName,
      required String? inviterId,
      required String? inviterServer,
      required String ownServer}) {
    return AdaptiveDialog.show<DeclineAndBlockChoice>(context,
        title: inviteDeclineAndBlockTitle,
        initialHeightMobile: 0.6,
        builder: (_) => DeclineAndBlockSheet(
            roomName: roomName,
            inviterId: inviterId,
            inviterServer: inviterServer,
            ownServer: ownServer));
  }

  @override
  State<DeclineAndBlockSheet> createState() => _DeclineAndBlockSheetState();
}

class _DeclineAndBlockSheetState extends State<DeclineAndBlockSheet> {
  late bool blockUser = _rememberBlockUser.value;
  late bool blockServer = _rememberBlockServer.value;
  late bool reportRoom = _rememberReportRoom.value;

  bool get _canBlockServer =>
      widget.inviterServer != null &&
      widget.inviterServer!.isNotEmpty &&
      widget.inviterServer != widget.ownServer;

  void _confirm() {
    _rememberBlockUser.set(blockUser);
    if (_canBlockServer) _rememberBlockServer.set(blockServer);
    _rememberReportRoom.set(reportRoom);
    Navigator.of(context).pop(DeclineAndBlockChoice(
      blockUser: widget.inviterId != null && blockUser,
      blockServer: _canBlockServer && blockServer,
      reportRoom: reportRoom,
    ));
  }

  Widget _option(
      {required Key key,
      required IconData icon,
      required String title,
      required String explain,
      required bool value,
      required ValueChanged<bool> onChanged}) {
    return InkWell(
      mouseCursor: WidgetStateMouseCursor.clickable,
      key: key,
      borderRadius: BorderRadius.circular(8),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(value: value, onChanged: (v) => onChanged(v ?? false)),
            const SizedBox(width: 4),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(icon, size: 16),
                      const SizedBox(width: 6),
                      Flexible(child: tiamat.Text.labelEmphasised(title)),
                    ]),
                    const SizedBox(height: 2),
                    tiamat.Text.labelLow(explain),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: tiamat.Text.labelLow(
                inviteDeclineAndBlockIntro(widget.roomName)),
          ),
          if (widget.inviterId != null)
            _option(
              key: const ValueKey("decline-block-user"),
              icon: Icons.person_off_outlined,
              title: inviteBlockUser(widget.inviterId!),
              explain: inviteBlockUserExplain,
              value: blockUser,
              onChanged: (v) => setState(() => blockUser = v),
            ),
          if (_canBlockServer)
            _option(
              key: const ValueKey("decline-block-server"),
              icon: Icons.dns_outlined,
              title: inviteBlockServer(widget.inviterServer!),
              explain: inviteBlockServerExplain(widget.inviterServer!),
              value: blockServer,
              onChanged: (v) => setState(() => blockServer = v),
            ),
          _option(
            key: const ValueKey("decline-report-room"),
            icon: Icons.flag_outlined,
            title: inviteReportRoom,
            explain: inviteReportRoomExplain(widget.ownServer),
            value: reportRoom,
            onChanged: (v) => setState(() => reportRoom = v),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: tiamat.Button.secondary(
                    text: inviteCancel,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: tiamat.Button.danger(
                    key: const ValueKey("decline-block-confirm"),
                    text: inviteDeclineAndBlockTitle,
                    onTap: _confirm,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
