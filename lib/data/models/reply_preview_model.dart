import 'package:equatable/equatable.dart';

/// A bounded, non-recursive quote. Unavailable originals never expose content.
class ReplyPreviewModel extends Equatable {
  final String id;
  final String? senderId;
  final String? senderName;
  final String messageType;
  final String? content;
  final String? mediaUrl;
  final bool isViewOnce;
  final bool isUnavailable;

  const ReplyPreviewModel({
    required this.id,
    this.senderId,
    this.senderName,
    this.messageType = 'text',
    this.content,
    this.mediaUrl,
    this.isViewOnce = false,
    this.isUnavailable = false,
  });

  const ReplyPreviewModel.unavailable(this.id)
    : senderId = null,
      senderName = null,
      messageType = 'text',
      content = null,
      mediaUrl = null,
      isViewOnce = false,
      isUnavailable = true;

  factory ReplyPreviewModel.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    if (json['is_unavailable'] == true) {
      return ReplyPreviewModel.unavailable(id);
    }
    final isViewOnce = json['is_view_once'] == true;
    return ReplyPreviewModel(
      id: id,
      senderId: json['sender_id'] as String?,
      senderName: json['sender_name'] as String?,
      messageType: json['message_type'] as String? ?? 'text',
      content: isViewOnce ? null : json['content'] as String?,
      mediaUrl: isViewOnce ? null : json['media_url'] as String?,
      isViewOnce: isViewOnce,
    );
  }

  @override
  List<Object?> get props => [
    id,
    senderId,
    senderName,
    messageType,
    content,
    mediaUrl,
    isViewOnce,
    isUnavailable,
  ];
}
