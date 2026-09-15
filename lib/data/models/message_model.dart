import '../../core/utils/api_datetime.dart';
import 'package:equatable/equatable.dart';

import 'user_model.dart';
import 'reply_preview_model.dart';
import 'reaction_model.dart';

/// Publishing admin signature (Telegram-like channel/group author label).
class MessageAuthor extends Equatable {
  final String id;
  final String displayName;
  final String? username;
  const MessageAuthor({required this.id, required this.displayName, this.username});
  factory MessageAuthor.fromJson(Map<String, dynamic> json) => MessageAuthor(
        id: json['id'] as String,
        displayName: json['display_name'] as String? ?? '',
        username: json['username'] as String?,
      );
  @override
  List<Object?> get props => [id, displayName, username];
}

class MessageModel extends Equatable {
  final String id;
  final String chatId;
  final String senderId;
  final UserModel? sender;
  final MessageAuthor? author;
  final String messageType;
  final String? content;
  final String? mediaId;
  final String? mediaUrl;
  final String? replyToId;
  final ReplyPreviewModel? replyTo;
  final String? forwardedFromId;
  final bool isViewOnce;
  final bool isSpoiler;
  final bool isScheduled;
  final DateTime? scheduledAt;
  final String? originalName;
  final int? fileSize;
  final bool isPinned;
  final DateTime? viewedAt;
  final bool isEdited;
  final DateTime? editedAt;
  // Encrypted (password-protected) messages
  final bool isEncrypted;
  final String? encryptionHint;
  // Secure-mode messages
  final bool isSecure;
  // Location messages
  final double? latitude;
  final double? longitude;
  final String? locationTitle;
  final DateTime? liveUntil;
  // Music / audio messages
  final String? audioTitle;
  final String? audioArtist;
  final double? audioDuration;
  // Video editor: muted videos play silently on every client
  final bool isMuted;
  final DateTime createdAt;
  final String status; // sent | delivered | read
  final List<ReactionModel> reactions;

  const MessageModel({
    required this.id,
    required this.chatId,
    required this.senderId,
    this.sender,
    this.author,
    required this.messageType,
    this.content,
    this.mediaId,
    this.mediaUrl,
    this.replyToId,
    this.replyTo,
    this.forwardedFromId,
    this.isViewOnce = false,
    this.isSpoiler = false,
    this.isScheduled = false,
    this.scheduledAt,
    this.originalName,
    this.fileSize,
    this.isPinned = false,
    this.viewedAt,
    this.isEdited = false,
    this.editedAt,
    this.isEncrypted = false,
    this.encryptionHint,
    this.isSecure = false,
    this.latitude,
    this.longitude,
    this.locationTitle,
    this.liveUntil,
    this.audioTitle,
    this.audioArtist,
    this.audioDuration,
    this.isMuted = false,
    required this.createdAt,
    this.status = 'sent',
    this.reactions = const [],
  });

  bool get isLocation => messageType == 'location' || messageType == 'live_location';
  bool get isLiveLocation => messageType == 'live_location';
  bool get isLiveActive => isLiveLocation && liveUntil != null && liveUntil!.isAfter(DateTime.now());
  bool get isMusic => messageType == 'audio' || messageType == 'music';
  bool get isVoiceOrMusic => messageType == 'voice' || isMusic;

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    return MessageModel(
      id: json['id'] as String,
      chatId: json['chat_id'] as String,
      senderId: json['sender_id'] as String,
      sender: json['sender'] != null
          ? UserModel.fromJson(json['sender'] as Map<String, dynamic>)
          : null,
      author: json['author'] is Map<String, dynamic>
          ? MessageAuthor.fromJson(json['author'] as Map<String, dynamic>)
          : null,
      messageType: json['message_type'] as String? ?? 'text',
      content: json['content'] as String?,
      mediaId: json['media_id'] as String?,
      mediaUrl: json['media_url'] as String?,
      replyToId: json['reply_to_id'] as String?,
      replyTo: json['reply_to'] is Map<String, dynamic>
          ? ReplyPreviewModel.fromJson(json['reply_to'] as Map<String, dynamic>)
          : null,
      forwardedFromId: json['forwarded_from_id'] as String?,
      isViewOnce: json['is_view_once'] as bool? ?? false,
      isSpoiler: json['is_spoiler'] as bool? ?? false,
      isScheduled: json['is_scheduled'] as bool? ?? false,
      scheduledAt: json['scheduled_at'] != null
          ? parseApiDateTime(json['scheduled_at'] as String?)
          : null,
      originalName: json['original_name'] as String?,
      fileSize: json['file_size'] as int?,
      isPinned: json['is_pinned'] as bool? ?? false,
      viewedAt: json['viewed_at'] != null
          ? parseApiDateTime(json['viewed_at'] as String?)
          : null,
      isEdited: json['is_edited'] as bool? ?? false,
      editedAt: json['edited_at'] != null
          ? parseApiDateTime(json['edited_at'] as String?)
          : null,
      isEncrypted: json['is_encrypted'] as bool? ?? false,
      encryptionHint: json['encryption_hint'] as String?,
      isSecure: json['is_secure'] as bool? ?? false,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      locationTitle: json['location_title'] as String?,
      liveUntil: json['live_until'] != null
          ? parseApiDateTime(json['live_until'] as String?)
          : null,
      audioTitle: json['audio_title'] as String?,
      audioArtist: json['audio_artist'] as String?,
      audioDuration: (json['audio_duration'] as num?)?.toDouble(),
      isMuted: json['is_muted'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? parseApiDateTime(json['created_at'] as String?) ?? DateTime.now()
          : DateTime.now(),
      status: json['status'] as String? ?? 'sent',
      reactions: (json['reactions'] as List?)?.map((e) => ReactionModel.fromJson(e as Map<String, dynamic>)).toList() ?? const [],
    );
  }

  MessageModel copyWith({
    String? status,
    String? content,
    bool? isViewOnce,
    bool? isSpoiler,
    bool? isScheduled,
    DateTime? scheduledAt,
    bool? isPinned,
    DateTime? viewedAt,
    bool? isEdited,
    DateTime? editedAt,
    bool? isEncrypted,
    String? encryptionHint,
    double? latitude,
    double? longitude,
    DateTime? liveUntil,
    ReplyPreviewModel? replyTo,
    List<ReactionModel>? reactions,
  }) {
    return MessageModel(
      id: id,
      chatId: chatId,
      senderId: senderId,
      sender: sender,
      author: author,
      messageType: messageType,
      content: content ?? this.content,
      mediaId: mediaId,
      mediaUrl: mediaUrl,
      replyToId: replyToId,
      replyTo: replyTo ?? this.replyTo,
      forwardedFromId: forwardedFromId,
      isViewOnce: isViewOnce ?? this.isViewOnce,
      isSpoiler: isSpoiler ?? this.isSpoiler,
      isScheduled: isScheduled ?? this.isScheduled,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      originalName: originalName,
      fileSize: fileSize,
      isPinned: isPinned ?? this.isPinned,
      viewedAt: viewedAt ?? this.viewedAt,
      isEdited: isEdited ?? this.isEdited,
      editedAt: editedAt ?? this.editedAt,
      isEncrypted: isEncrypted ?? this.isEncrypted,
      encryptionHint: encryptionHint ?? this.encryptionHint,
      isSecure: isSecure,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      locationTitle: locationTitle,
      liveUntil: liveUntil ?? this.liveUntil,
      audioTitle: audioTitle,
      audioArtist: audioArtist,
      audioDuration: audioDuration,
      createdAt: createdAt,
      status: status ?? this.status,
      reactions: reactions ?? this.reactions,
    );
  }

  /// View-once / encrypted content and empty media placeholders are never copied.
  String? get copyableText =>
      !isViewOnce && !isEncrypted && content?.trim().isNotEmpty == true ? content : null;

  ReplyPreviewModel get asReplyPreview => ReplyPreviewModel(
    id: id,
    senderId: senderId,
    senderName: sender?.displayName,
    messageType: messageType,
    content: isViewOnce || isEncrypted ? null : content,
    mediaUrl: isViewOnce || isEncrypted || messageType != 'image'
        ? null
        : mediaUrl ?? (mediaId == null ? null : '/api/v1/media/$mediaId'),
    isViewOnce: isViewOnce,
  );

  @override
  List<Object?> get props => [
    id,
    chatId,
    senderId,
    sender,
    author,
    messageType,
    content,
    createdAt,
    status,
    mediaId,
    mediaUrl,
    replyToId,
    replyTo,
    forwardedFromId,
    isViewOnce,
    isSpoiler,
    isScheduled,
    scheduledAt,
    originalName,
    fileSize,
    isPinned,
    viewedAt,
    isEdited,
    editedAt,
    isEncrypted,
    encryptionHint,
    isSecure,
    latitude,
    longitude,
    locationTitle,
    liveUntil,
    audioTitle,
    audioArtist,
    audioDuration,
    isMuted,
    reactions,
  ];
}
