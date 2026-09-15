import '../../core/utils/api_datetime.dart';
import '../models/message_model.dart';
import '../models/reply_preview_model.dart';

/// Payload for an edited / live-location message reconciled via polling.
class MessageSyncUpdate {
  final String id;
  final String? content;
  final bool isEdited;
  final DateTime? editedAt;
  final bool? isEncrypted;
  final String? encryptionHint;
  final double? latitude;
  final double? longitude;
  final DateTime? liveUntil;

  const MessageSyncUpdate({
    required this.id,
    this.content,
    this.isEdited = false,
    this.editedAt,
    this.isEncrypted,
    this.encryptionHint,
    this.latitude,
    this.longitude,
    this.liveUntil,
  });

  factory MessageSyncUpdate.fromJson(Map<String, dynamic> json) {
    return MessageSyncUpdate(
      id: json['id'] as String,
      content: json['content'] as String?,
      isEdited: json['is_edited'] as bool? ?? false,
      editedAt: parseApiDateTime(json['edited_at'] as String?),
      isEncrypted: json['is_encrypted'] as bool?,
      encryptionHint: json['encryption_hint'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      liveUntil: parseApiDateTime(json['live_until'] as String?),
    );
  }
}

/// A bounded /messages/statuses response. Missing fields keep older servers
/// compatible, though live deletion requires the updated backend.
class MessageSyncResult {
  final Set<String> deletedIds;
  final Map<String, String> statuses;
  final Map<String, DateTime> viewedAt;
  final Map<String, MessageSyncUpdate> updated;

  /// Ids of the currently pinned messages of the chat, newest first. Null on
  /// an older server that does not report pins at all.
  final List<String>? pinnedIds;

  const MessageSyncResult({
    this.deletedIds = const {},
    this.statuses = const {},
    this.viewedAt = const {},
    this.updated = const {},
    this.pinnedIds,
  });

  factory MessageSyncResult.fromJson(Map<String, dynamic> json) {
    final statuses = json['statuses'] as Map<String, dynamic>? ?? {};
    final views = json['viewed_at'] as Map<String, dynamic>? ?? {};
    final pinned = json['pinned_ids'] as List?;
    final updatedList = (json['updated'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(MessageSyncUpdate.fromJson)
        .toList();
    return MessageSyncResult(
      pinnedIds: pinned?.whereType<String>().toList(),
      deletedIds: (json['deleted_ids'] as List? ?? [])
          .whereType<String>()
          .toSet(),
      statuses: {
        for (final entry in statuses.entries)
          if (entry.value is String) entry.key: entry.value as String,
      },
      viewedAt: {
        for (final entry in views.entries)
          if (entry.value is String &&
              parseApiDateTime(entry.value as String) != null)
            entry.key: parseApiDateTime(entry.value as String)!,
      },
      updated: {for (final u in updatedList) u.id: u},
    );
  }
}

/// Tombstones last as long as the chat screen. A delayed history/send/poll
/// response cannot bring back a message (or quoted content) already removed.
class MessageReconciler {
  final Set<String> _unavailableIds = {};

  bool isUnavailable(String id) => _unavailableIds.contains(id);

  void remove(Iterable<String> ids) => _unavailableIds.addAll(ids);

  static String newestStatus(String previous, String? incoming) {
    const rank = {'sent': 0, 'delivered': 1, 'read': 2};
    return (rank[incoming] ?? -1) > (rank[previous] ?? 0)
        ? incoming!
        : previous;
  }

  List<MessageModel> reconcile(
    Iterable<MessageModel> messages, {
    MessageSyncResult? update,
  }) {
    if (update != null) remove(update.deletedIds);
    final pinned = update?.pinnedIds == null
        ? null
        : update!.pinnedIds!.toSet();
    return [
      for (final message in messages)
        if (!isUnavailable(message.id))
          () {
            final edit = update?.updated[message.id];
            return message.copyWith(
              status: newestStatus(message.status, update?.statuses[message.id]),
              content: edit?.content ?? message.content,
              viewedAt: message.viewedAt ?? update?.viewedAt[message.id],
              isPinned: pinned == null
                  ? message.isPinned
                  : pinned.contains(message.id),
              isEdited: edit != null ? (edit.isEdited || message.isEdited) : message.isEdited,
              editedAt: edit?.editedAt ?? message.editedAt,
              isEncrypted: edit?.isEncrypted ?? message.isEncrypted,
              encryptionHint: edit?.encryptionHint ?? message.encryptionHint,
              latitude: edit?.latitude ?? message.latitude,
              longitude: edit?.longitude ?? message.longitude,
              liveUntil: edit?.liveUntil ?? message.liveUntil,
              replyTo:
                  message.replyToId != null && isUnavailable(message.replyToId!)
                  ? ReplyPreviewModel.unavailable(message.replyToId!)
                  : null,
            );
          }(),
    ];
  }

  /// Include received/read messages, old pages, search results and originals
  /// outside the visible page. An unread-outgoing-only poll misses deletions.
  List<List<String>> batches(
    Iterable<MessageModel> messages, {
    MessageModel? selectedReply,
  }) {
    final ids = <String>{};
    for (final message in messages) {
      if (!isUnavailable(message.id)) ids.add(message.id);
      final replyId = message.replyToId;
      if (replyId != null && !isUnavailable(replyId)) ids.add(replyId);
    }
    if (selectedReply != null && !isUnavailable(selectedReply.id)) {
      ids.add(selectedReply.id);
    }
    final list = ids.toList();
    return [
      for (var start = 0; start < list.length; start += 100)
        list.sublist(
          start,
          start + 100 > list.length ? list.length : start + 100,
        ),
    ];
  }
}
