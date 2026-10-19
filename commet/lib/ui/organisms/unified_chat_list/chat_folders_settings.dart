// Vommet: Settings › Chat folders and the folder editor for the
// Telegram-style chat list (Vommet issue 291, phase 2).
//
// The *View widgets only draw what they're given (renders and tests use
// them with made-up data); the pages wire them to ChatFoldersStore and the
// clients.
import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/navigation/navigation_utils.dart';
import 'package:commet/ui/organisms/unified_chat_list/chat_folders_model.dart';
import 'package:commet/ui/organisms/unified_chat_list/chat_folders_store.dart';
import 'package:commet/ui/organisms/unified_chat_list/chat_folders_view.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_model.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_rows.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_source.dart';
import 'package:flutter/material.dart';

List<Client> get _clients => clientManager?.clients ?? const [];

ChatFoldersDoc _currentFolders() =>
    ChatFoldersStore.instance.foldersFor(_clients);

Future<void> _save(BuildContext context, ChatFoldersDoc doc) async {
  try {
    await ChatFoldersStore.instance.saveFolders(_clients, doc);
  } catch (e, s) {
    Log.onError(e, s);
    if (context.mounted) unawaited(AdaptiveDialog.showError(context, e, s));
  }
}

/// Opens Settings › Chat folders on its own.
Future<void> openChatFoldersSettings(BuildContext context) =>
    NavigationUtils.navigateTo(
        context,
        const _StandalonePage(
            title: "Chat folders", child: ChatFoldersSettingsPage()));

/// Opens the editor for [folder], or for a new folder (holding [withChat]).
Future<void> openFolderEditor(BuildContext context,
        {ChatFolder? folder, String? withChat}) =>
    NavigationUtils.navigateTo(
        context, ChatFolderEditorPage(folder: folder, withChat: withChat));

/// Deletes [folder] after asking.
Future<void> confirmDeleteFolder(
    BuildContext context, ChatFolder folder) async {
  final yes = await AdaptiveDialog.confirmation(context,
      title: "Delete folder",
      prompt:
          "Delete the folder \"${folder.name}\"? The chats in it stay where they are.",
      confirmationText: "Delete",
      cancelText: "Cancel",
      dangerous: true);
  if (yes == true && context.mounted) {
    await _save(context, _currentFolders().withoutFolder(folder.id));
  }
}

class _StandalonePage extends StatelessWidget {
  const _StandalonePage({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      appBar: AppBar(
          title: Text(title),
          backgroundColor: Theme.of(context).colorScheme.surfaceContainer),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640), child: child),
        ),
      ),
    );
  }
}

/// Settings › Chat folders, wired to the store.
class ChatFoldersSettingsPage extends StatefulWidget {
  const ChatFoldersSettingsPage({super.key});

  @override
  State<ChatFoldersSettingsPage> createState() =>
      _ChatFoldersSettingsPageState();
}

class _ChatFoldersSettingsPageState extends State<ChatFoldersSettingsPage> {
  StreamSubscription? _sync;

  @override
  void initState() {
    super.initState();
    ChatFoldersStore.instance.addListener(_changed);
    _sync = clientManager?.onSync.stream.listen((_) => _changed());
  }

  @override
  void dispose() {
    ChatFoldersStore.instance.removeListener(_changed);
    _sync?.cancel();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final doc = _currentFolders();
    return ChatFoldersSettingsView(
      folders: doc,
      onOpen: (f) => openFolderEditor(context, folder: f),
      onCreate: () => openFolderEditor(context),
      onDelete: (f) => confirmDeleteFolder(context, f),
      onReorder: (from, to) => _save(context, doc.reordered(from, to)),
      onAddRecommended: (f) => _save(context, doc.withFolder(f)),
      onKeepUnmutedArchived: (v) =>
          _save(context, doc.copyWith(keepUnmutedArchived: v)),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children, this.footer});
  final String title;
  final List<Widget> children;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
          child: Text(title.toUpperCase(),
              style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6)),
        ),
        Material(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
            child: Text(footer!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
      ]),
    );
  }
}

Widget _folderLeading(BuildContext context, ChatFolder f) => SizedBox(
      width: 32,
      child: Center(
        child: f.emoji != null
            ? Text(f.emoji!, style: const TextStyle(fontSize: 20))
            : Icon(folderIcon(f),
                color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );

/// What Settings › Chat folders shows.
class ChatFoldersSettingsView extends StatelessWidget {
  const ChatFoldersSettingsView({
    super.key,
    required this.folders,
    this.onOpen,
    this.onCreate,
    this.onDelete,
    this.onReorder,
    this.onAddRecommended,
    this.onKeepUnmutedArchived,
  });

  final ChatFoldersDoc folders;
  final void Function(ChatFolder folder)? onOpen;
  final VoidCallback? onCreate;
  final void Function(ChatFolder folder)? onDelete;
  final void Function(int from, int to)? onReorder;
  final void Function(ChatFolder folder)? onAddRecommended;
  final void Function(bool value)? onKeepUnmutedArchived;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recommended = recommendedFolders()
        .where((r) => folders.folder(r.id) == null)
        .toList();
    return Material(
      color: Colors.transparent,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 18),
          child: Row(children: [
            Icon(Icons.folder_copy_outlined,
                size: 40, color: theme.colorScheme.primary),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                  "Create folders for different groups of chats and switch between them quickly.",
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
          ]),
        ),
        _Section(
          title: "Chat folders",
          footer: folders.folders.length > 1
              ? "Drag folders to change their order."
              : null,
          children: [
            ListTile(
              leading: Icon(Icons.add, color: theme.colorScheme.primary),
              title: Text("Create a new folder",
                  style: TextStyle(color: theme.colorScheme.primary)),
              onTap: onCreate,
            ),
            if (folders.folders.isNotEmpty)
              ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                onReorder: (from, to) => onReorder?.call(from, to),
                children: [
                  for (var i = 0; i < folders.folders.length; i++)
                    _folderTile(context, folders.folders[i], i),
                ],
              ),
          ],
        ),
        if (recommended.isNotEmpty)
          _Section(title: "Recommended folders", children: [
            for (final f in recommended)
              ListTile(
                leading: _folderLeading(context, f),
                title: Text(f.name),
                subtitle: Text(recommendedFolderDescription(f.id)),
                trailing: FilledButton.tonal(
                    onPressed: () => onAddRecommended?.call(f),
                    child: const Text("Add")),
              ),
          ]),
        _Section(
          title: "Archive",
          footer:
              "Archived chats that aren't muted come back to the list when a new message arrives. Muted chats always stay archived.",
          children: [
            SwitchListTile(
              title: const Text("Keep unmuted chats archived"),
              value: folders.keepUnmutedArchived,
              onChanged: onKeepUnmutedArchived,
            ),
          ],
        ),
      ]),
    );
  }

  Widget _folderTile(BuildContext context, ChatFolder f, int index) {
    return ListTile(
      key: ValueKey("folder-setting-${f.id}"),
      leading: _folderLeading(context, f),
      title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle:
          Text(folderSummary(f), maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: () => onOpen?.call(f),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
            tooltip: "Delete folder",
            onPressed: () => onDelete?.call(f),
            icon: const Icon(Icons.delete_outline)),
        ReorderableDragStartListener(
          index: index,
          child: const Padding(
            padding: EdgeInsets.all(8),
            child: Icon(Icons.drag_handle),
          ),
        ),
      ]),
    );
  }
}

/// A row's picture, at [size].
Widget topRowAvatar(TopRow row, {double size = 36}) => switch (row) {
      ChatTopRow(:final chat) => ChatAvatar(
          name: chat.name, image: chat.avatar, color: chat.color, size: size),
      SpaceTopRow(:final space) => ChatAvatar(
          name: space.name,
          image: space.avatar,
          color: space.color,
          size: size,
          square: true),
    };

String _kindLabel(TopRow row) => switch (row.folderType) {
      FolderChatType.direct => "Direct message",
      FolderChatType.room => "Room",
      FolderChatType.space => "Space",
    };

/// The folder editor, wired to the store and the clients.
class ChatFolderEditorPage extends StatefulWidget {
  const ChatFolderEditorPage({super.key, this.folder, this.withChat});
  final ChatFolder? folder;
  final String? withChat;

  @override
  State<ChatFolderEditorPage> createState() => _ChatFolderEditorPageState();
}

class _ChatFolderEditorPageState extends State<ChatFolderEditorPage> {
  UnifiedChatSource? _source;
  late final ChatFolder _start = widget.folder ??
      ChatFolder(
          id: ChatFolder.newId(),
          name: "",
          include: {if (widget.withChat != null) widget.withChat!});

  @override
  void initState() {
    super.initState();
    if (clientManager != null) {
      _source = UnifiedChatSource(clientManager!)..addListener(_changed);
    }
  }

  @override
  void dispose() {
    _source?.removeListener(_changed);
    _source?.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ChatFolderEditorView(
      initial: _start,
      isNew: widget.folder == null,
      rows: _source?.allRows ?? const [],
      archivedIds: _source?.archivedIds ?? const {},
      onSave: (folder) async {
        await _save(context, _currentFolders().withFolder(folder));
        if (context.mounted) Navigator.of(context).pop();
      },
      onDelete: widget.folder == null
          ? null
          : () async {
              await confirmDeleteFolder(context, widget.folder!);
              if (context.mounted &&
                  _currentFolders().folder(widget.folder!.id) == null) {
                Navigator.of(context).pop();
              }
            },
    );
  }
}

/// The folder editor: name, included and excluded chats, and options.
class ChatFolderEditorView extends StatefulWidget {
  const ChatFolderEditorView({
    super.key,
    required this.initial,
    this.isNew = false,
    this.rows = const [],
    this.archivedIds = const {},
    this.onSave,
    this.onDelete,
  });

  final ChatFolder initial;
  final bool isNew;

  /// Every chat (archived too), for names and the chat picker.
  final List<TopRow> rows;
  final Set<String> archivedIds;
  final void Function(ChatFolder folder)? onSave;
  final VoidCallback? onDelete;

  @override
  State<ChatFolderEditorView> createState() => _ChatFolderEditorViewState();
}

class _ChatFolderEditorViewState extends State<ChatFolderEditorView> {
  late ChatFolder draft = widget.initial;
  late final TextEditingController name =
      TextEditingController(text: widget.initial.name);

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  bool get canSave => name.text.trim().isNotEmpty && draft.isUsable;

  TopRow? _row(String id) =>
      widget.rows.where((r) => r.roomId == id).firstOrNull;

  Future<void> _pickEmoji() async {
    final text = await AdaptiveDialog.textPrompt(context,
        title: "Folder emoji",
        submitText: "Set",
        hintText: "One emoji, or leave empty for an icon",
        initialText: draft.emoji);
    if (text == null || !mounted) return;
    final trimmed = text.trim();
    setState(() => draft = draft.copyWith(
        emoji: () =>
            trimmed.isEmpty ? null : trimmed.characters.first.toString()));
  }

  Future<void> _pick({required bool exclude}) async {
    final current = exclude ? draft.exclude : draft.include;
    final picked = await showChatPicker(context,
        title: exclude ? "Exclude chats" : "Add chats",
        rows: widget.rows,
        selected: current);
    if (picked == null || !mounted) return;
    setState(() {
      draft = exclude
          ? draft.copyWith(
              exclude: picked, include: draft.include.difference(picked))
          : draft.copyWith(
              include: picked, exclude: draft.exclude.difference(picked));
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      backgroundColor: scheme.surfaceContainer,
      appBar: AppBar(
        backgroundColor: scheme.surfaceContainer,
        title: Text(widget.isNew ? "New folder" : "Edit folder"),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
                onPressed: canSave
                    ? () => widget.onSave
                        ?.call(draft.copyWith(name: name.text.trim()))
                    : null,
                child: const Text("Save")),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Material(
              color: Colors.transparent,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Section(title: "Folder name", children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 6, 14, 6),
                        child: Row(children: [
                          IconButton(
                            tooltip: "Folder emoji",
                            onPressed: _pickEmoji,
                            icon: draft.emoji != null
                                ? Text(draft.emoji!,
                                    style: const TextStyle(fontSize: 22))
                                : Icon(folderIcon(draft),
                                    color: scheme.onSurfaceVariant),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: TextField(
                              controller: name,
                              maxLength: 32,
                              onChanged: (_) => setState(() {}),
                              decoration: const InputDecoration(
                                  hintText: "Folder name",
                                  counterText: "",
                                  border: InputBorder.none),
                            ),
                          ),
                        ]),
                      ),
                    ]),
                    _Section(
                      title: "Included chats",
                      footer:
                          "Pick chat types and chats that will appear in this folder.",
                      children: [
                        _addTile(
                            context, "Add chats", () => _pick(exclude: false)),
                        _typeTile(FolderChatType.direct, "Direct messages",
                            Icons.person_outline),
                        _typeTile(FolderChatType.room, "Rooms not in a space",
                            Icons.tag),
                        _typeTile(FolderChatType.space, "Spaces",
                            Icons.workspaces_outline),
                        for (final id in draft.include)
                          _chatTile(
                              id,
                              () => setState(() => draft = draft.copyWith(
                                  include: {...draft.include}..remove(id)))),
                      ],
                    ),
                    _Section(
                      title: "Excluded chats",
                      footer:
                          "Chats picked here never show in this folder. A chat picked in both lists is excluded.",
                      children: [
                        _addTile(context, "Exclude chats",
                            () => _pick(exclude: true)),
                        _flagTile(
                            "Muted",
                            Icons.notifications_off_outlined,
                            draft.excludeMuted,
                            (v) => draft.copyWith(excludeMuted: v)),
                        _flagTile("Read", Icons.done_all, draft.excludeRead,
                            (v) => draft.copyWith(excludeRead: v)),
                        _flagTile(
                            "Archived",
                            Icons.archive_outlined,
                            draft.excludeArchived,
                            (v) => draft.copyWith(excludeArchived: v)),
                        for (final id in draft.exclude)
                          _chatTile(
                              id,
                              () => setState(() => draft = draft.copyWith(
                                  exclude: {...draft.exclude}..remove(id)))),
                      ],
                    ),
                    if (!draft.isUsable)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                        child: Text(
                            "Include at least one chat type or chat to save this folder.",
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: scheme.error)),
                      ),
                    if (widget.onDelete != null)
                      _Section(title: "Folder", children: [
                        ListTile(
                          leading:
                              Icon(Icons.delete_outline, color: scheme.error),
                          title: Text("Delete folder",
                              style: TextStyle(color: scheme.error)),
                          onTap: widget.onDelete,
                        ),
                      ]),
                  ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _addTile(BuildContext context, String text, VoidCallback onTap) {
    final primary = Theme.of(context).colorScheme.primary;
    return ListTile(
        leading: Icon(Icons.add_circle_outline, color: primary),
        title: Text(text, style: TextStyle(color: primary)),
        onTap: onTap);
  }

  Widget _typeTile(FolderChatType type, String text, IconData icon) =>
      CheckboxListTile(
        secondary: Icon(icon),
        title: Text(text),
        value: draft.types.contains(type),
        onChanged: (v) => setState(() => draft = draft.copyWith(
            types: v == true
                ? {...draft.types, type}
                : ({...draft.types}..remove(type)))),
      );

  Widget _flagTile(String text, IconData icon, bool value,
          ChatFolder Function(bool v) apply) =>
      CheckboxListTile(
        secondary: Icon(icon),
        title: Text(text),
        value: value,
        onChanged: (v) => setState(() => draft = apply(v == true)),
      );

  Widget _chatTile(String id, VoidCallback onRemove) {
    final row = _row(id);
    return ListTile(
      key: ValueKey("folder-chat-$id"),
      leading: row == null
          ? const CircleAvatar(radius: 18, child: Icon(Icons.question_mark))
          : topRowAvatar(row),
      title:
          Text(row?.name ?? id, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(row == null
          ? "Not in your list"
          : _kindLabel(row) +
              (widget.archivedIds.contains(id) ? " · archived" : "")),
      trailing: IconButton(
          tooltip: "Remove",
          onPressed: onRemove,
          icon: const Icon(Icons.close)),
    );
  }
}

/// Lets the user tick chats out of [rows]; null when cancelled.
Future<Set<String>?> showChatPicker(BuildContext context,
    {required String title,
    required List<TopRow> rows,
    Set<String> selected = const {}}) {
  return AdaptiveDialog.show<Set<String>>(context,
      title: title,
      scrollable: false,
      initialHeightMobile: 0.8,
      builder: (context) => ChatPickerView(rows: rows, selected: selected));
}

/// The list in the chat picker: search, then every chat with a checkbox.
class ChatPickerView extends StatefulWidget {
  const ChatPickerView(
      {super.key, required this.rows, this.selected = const {}});
  final List<TopRow> rows;
  final Set<String> selected;

  @override
  State<ChatPickerView> createState() => _ChatPickerViewState();
}

class _ChatPickerViewState extends State<ChatPickerView> {
  late final Set<String> picked = {...widget.selected};
  final search = TextEditingController();

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = filterTopRows(widget.rows, search.text);
    return SizedBox(
      width: 420,
      height: 480,
      child: Column(children: [
        TextField(
          controller: search,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
              hintText: "Search", prefixIcon: Icon(Icons.search)),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: ListView.builder(
            itemCount: shown.length,
            itemBuilder: (context, index) {
              final row = shown[index];
              return CheckboxListTile(
                key: ValueKey("pick-${row.key}"),
                secondary: topRowAvatar(row),
                title: Text(row.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(_kindLabel(row)),
                value: picked.contains(row.roomId),
                onChanged: (v) => setState(() => v == true
                    ? picked.add(row.roomId)
                    : picked.remove(row.roomId)),
              );
            },
          ),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Cancel")),
          const SizedBox(width: 8),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(picked),
              child: Text(picked.isEmpty ? "Done" : "Done (${picked.length})")),
        ]),
      ]),
    );
  }
}

/// The folders [row] is in, to tick or untick ("Add to folder").
Future<void> showAddToFolder(BuildContext context, TopRow row,
    {bool archived = false}) async {
  await AdaptiveDialog.show<void>(context,
      title: "Add to folder",
      builder: (dialogContext) => _AddToFolderView(
          row: row,
          archived: archived,
          onNewFolder: () {
            Navigator.of(dialogContext).pop();
            openFolderEditor(context, withChat: row.roomId);
          }));
}

class _AddToFolderView extends StatefulWidget {
  const _AddToFolderView(
      {required this.row, required this.archived, this.onNewFolder});
  final TopRow row;
  final bool archived;
  final VoidCallback? onNewFolder;

  @override
  State<_AddToFolderView> createState() => _AddToFolderViewState();
}

class _AddToFolderViewState extends State<_AddToFolderView> {
  @override
  Widget build(BuildContext context) {
    final doc = _currentFolders();
    final row = widget.row;
    return SizedBox(
      width: 360,
      child: Material(
        color: Colors.transparent,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final f in doc.folders)
            CheckboxListTile(
              secondary: _folderLeading(context, f),
              title: Text(f.name),
              value: folderContains(f, row, archived: widget.archived),
              onChanged: (v) async {
                final next = v == true
                    ? f.withChat(row.roomId)
                    : f.withoutChat(row.roomId,
                        typeWouldInclude: folderTypeMatches(f, row,
                            archived: widget.archived));
                await _save(context, _currentFolders().withFolder(next));
                if (mounted) setState(() {});
              },
            ),
          ListTile(
            leading: Icon(Icons.create_new_folder_outlined,
                color: Theme.of(context).colorScheme.primary),
            title: Text("New folder",
                style: TextStyle(color: Theme.of(context).colorScheme.primary)),
            onTap: widget.onNewFolder,
          ),
        ]),
      ),
    );
  }
}
