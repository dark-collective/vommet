import 'package:commet/client/client.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/components/invitation/invitation_component.dart';
import 'package:commet/client/components/profile/profile_component.dart';
import 'package:commet/ui/atoms/scaled_safe_area.dart';
import 'package:commet/ui/molecules/profile/mini_profile_view.dart';
import 'package:commet/ui/organisms/invitation_view/batch_invite_source.dart';
import 'package:commet/ui/organisms/invitation_view/batch_invite_widget.dart';
import 'package:commet/utils/debounce.dart';
import 'package:flutter/material.dart';

import 'package:tiamat/tiamat.dart' as tiamat;

class SendInvitationWidget extends StatefulWidget {
  const SendInvitationWidget(this.client, this.component,
      {super.key,
      this.roomId,
      this.displayName,
      this.onUserPicked,
      this.showSuggestions = true,
      this.existingMembers,
      this.initialQuery});
  final Client client;
  final bool showSuggestions;
  final Iterable<String>? existingMembers;

  final Future<void> Function(String userId)? onUserPicked;

  final String? roomId;
  final String? displayName;
  final InvitationComponent component;

  /// Vommet: text already in the search field, searched at once (the
  /// member list's find box).
  final String? initialQuery;

  @override
  State<SendInvitationWidget> createState() => _SendInvitationWidgetState();
}

class _SendInvitationWidgetState extends State<SendInvitationWidget> {
  late TextEditingController controller;
  late Debouncer debouncer;

  bool isSearching = false;
  List<Profile>? searchResults;

  bool loading = false;
  ClientBatchInviteSource? batchSource;

  bool get showRecommendations =>
      (!(isSearching || searchResults?.isNotEmpty == true)) &&
      widget.showSuggestions;

  @override
  void initState() {
    controller = TextEditingController(text: widget.initialQuery);
    debouncer = Debouncer(delay: const Duration(milliseconds: 500));
    super.initState();
    final query = widget.initialQuery;
    if (widget.onUserPicked != null && query != null && query.isNotEmpty) {
      isSearching = true;
      debouncer.run(() => doSearch(query));
    }
  }

  @override
  void dispose() {
    debouncer.cancel();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onUserPicked == null && widget.roomId != null) {
      return BatchInviteWidget(
        source: batchSource ??= ClientBatchInviteSource(
            widget.client,
            widget.component,
            widget.roomId!,
            widget.displayName ?? widget.roomId!),
        initialQuery: widget.initialQuery,
      );
    }
    var dmComponent = widget.client.getComponent<DirectMessagesComponent>();
    var recommended = List.from(dmComponent?.directMessageRooms ?? []);

    recommended.removeWhere((element) =>
        widget.existingMembers
            ?.contains(dmComponent?.getDirectMessagePartnerId(element)) ==
        true);

    return Opacity(
      opacity: loading ? 0.3 : 1.0,
      child: IgnorePointer(
        ignoring: loading,
        child: ScaledSafeArea(
          child: SizedBox(
              width: 500,
              child: Column(children: [
                tiamat.TextInput(
                  controller: controller,
                  icon: const Icon(Icons.search),
                  maxLines: 1,
                  onChanged: onSearchTextChanged,
                ),
                if (isSearching || searchResults?.isNotEmpty == true)
                  SizedBox(
                      height: 300,
                      child: isSearching
                          ? const Center(child: CircularProgressIndicator())
                          : ListView.builder(
                              itemCount: searchResults!.length,
                              shrinkWrap: true,
                              itemBuilder: (context, index) {
                                return MiniProfileView(
                                  client: widget.component.client,
                                  userId: searchResults![index].identifier,
                                  initialProfile: searchResults![index],
                                  onTap: () => invitePeer(
                                      searchResults![index].identifier),
                                );
                              },
                            )),
                if (!isSearching && searchResults?.isEmpty == true)
                  Column(
                    children: [
                      tiamat.Text("Could not find any users"),
                      tiamat.Button(
                        text: "Send invite",
                        onTap: () => invitePeer(controller.text),
                      )
                    ],
                  ),
                if (showRecommendations && recommended.isNotEmpty)
                  Column(
                    children: [
                      const tiamat.Seperator(),
                      const tiamat.Text.labelLow("Recommended"),
                      ListView.builder(
                        shrinkWrap: true,
                        itemCount: recommended.length,
                        itemBuilder: (context, index) {
                          var room = recommended[index];
                          var userId =
                              dmComponent!.getDirectMessagePartnerId(room)!;
                          return MiniProfileView(
                              client: room.client,
                              onTap: () => invitePeer(userId),
                              userId: userId);
                        },
                      ),
                    ],
                  )
              ])),
        ),
      ),
    );
  }

  void onSearchTextChanged(String value) async {
    setState(() {
      isSearching = value.isNotEmpty;
      searchResults = null;
      debouncer.cancel();
    });

    if (value.isNotEmpty) {
      debouncer.run(() => doSearch(value));
    }
  }

  void doSearch(String value) async {
    var result = await widget.component.searchUsers(value);

    if (!mounted || controller.text != value) return;
    setState(() {
      isSearching = false;
      searchResults = result;
    });
  }

  void invitePeer(String userId) async {
    final onPicked = widget.onUserPicked;
    if (onPicked == null) return;
    setState(() => loading = true);
    await onPicked(userId);
    if (mounted) Navigator.pop(context);
  }
}
