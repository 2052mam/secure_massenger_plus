import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/chat_folder_model.dart';
import '../../../data/models/chat_model.dart';
import '../../providers/chat_list_provider.dart';
import '../../widgets/chat/chat_labels.dart';

/// Create or edit a Telegram style folder: pick chat types, individual chats,
/// or any mix of both.
class FolderEditorScreen extends ConsumerStatefulWidget {
  const FolderEditorScreen({super.key, this.folder});

  final ChatFolderModel? folder;

  @override
  ConsumerState<FolderEditorScreen> createState() => _FolderEditorScreenState();
}

class _FolderEditorScreenState extends ConsumerState<FolderEditorScreen> {
  late final TextEditingController _name = TextEditingController(
    text: widget.folder?.name ?? '',
  );
  late bool _private = widget.folder?.includePrivate ?? false;
  late bool _groups = widget.folder?.includeGroups ?? false;
  late bool _channels = widget.folder?.includeChannels ?? false;
  late bool _archived = widget.folder?.includeArchived ?? false;
  late final Set<String> _chatIds = {...?widget.folder?.chatIds};
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final labels = ChatLabels.of(context);
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = labels.folderNameRequired);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final folder = ChatFolderModel(
      id: widget.folder?.id ?? '',
      name: name,
      includePrivate: _private,
      includeGroups: _groups,
      includeChannels: _channels,
      includeArchived: _archived,
      chatIds: _chatIds.toList(),
    );
    try {
      await ref
          .read(chatFoldersProvider.notifier)
          .save(folder, id: widget.folder?.id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  Future<void> _delete() async {
    final labels = ChatLabels.of(context);
    final folder = widget.folder;
    if (folder == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(labels.folderDelete),
        content: Text(folder.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(labels.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              labels.delete,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await ref.read(chatFoldersProvider.notifier).remove(folder.id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final labels = ChatLabels.of(context);
    final chats =
        ref.watch(chatListProvider).valueOrNull?.chats ?? const <ChatModel>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.folder == null ? labels.newFolder : labels.editFolder,
        ),
        actions: [
          if (widget.folder != null)
            IconButton(
              tooltip: labels.folderDelete,
              icon: const Icon(Icons.delete_outline),
              onPressed: _busy ? null : _delete,
            ),
          TextButton(
            onPressed: _busy ? null : _save,
            child: Text(labels.save),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            enabled: !_busy,
            maxLength: 60,
            decoration: InputDecoration(
              labelText: labels.folderName,
              border: const OutlineInputBorder(),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.red, fontSize: 13),
              ),
            ),
          Text(
            labels.folderRules,
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
          const SizedBox(height: 8),
          Text(
            labels.folderTypes,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          SwitchListTile(
            key: const ValueKey('folder-private'),
            value: _private,
            title: Text(labels.folderIncludePrivate),
            onChanged: _busy ? null : (v) => setState(() => _private = v),
          ),
          SwitchListTile(
            key: const ValueKey('folder-groups'),
            value: _groups,
            title: Text(labels.folderIncludeGroups),
            onChanged: _busy ? null : (v) => setState(() => _groups = v),
          ),
          SwitchListTile(
            key: const ValueKey('folder-channels'),
            value: _channels,
            title: Text(labels.folderIncludeChannels),
            onChanged: _busy ? null : (v) => setState(() => _channels = v),
          ),
          SwitchListTile(
            key: const ValueKey('folder-archived'),
            value: _archived,
            title: Text(labels.folderIncludeArchived),
            onChanged: _busy ? null : (v) => setState(() => _archived = v),
          ),
          const Divider(height: 24),
          Text(
            labels.folderChats,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          for (final chat in chats)
            CheckboxListTile(
              key: ValueKey('folder-chat-${chat.id}'),
              value: _chatIds.contains(chat.id),
              title: Text(
                chat.displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              secondary: Icon(
                chat.chatType == 'channel'
                    ? Icons.campaign_outlined
                    : chat.chatType == 'group'
                    ? Icons.group_outlined
                    : Icons.person_outline,
              ),
              onChanged: _busy
                  ? null
                  : (v) => setState(() {
                      if (v == true) {
                        _chatIds.add(chat.id);
                      } else {
                        _chatIds.remove(chat.id);
                      }
                    }),
            ),
        ],
      ),
    );
  }
}
